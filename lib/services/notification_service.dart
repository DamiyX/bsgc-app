import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';
import 'firestore_commit_service.dart';
import 'notification_destination_store.dart';

export 'notification_destination_store.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

enum DeviceNotificationPermission {
  notDetermined,
  denied,
  authorized,
  provisional,
}

class NotificationPreferenceDecision {
  final bool enabled;
  final bool shouldOpenSystemSettings;

  const NotificationPreferenceDecision({
    required this.enabled,
    required this.shouldOpenSystemSettings,
  });
}

NotificationPreferenceDecision resolveNotificationPreference({
  required bool requestedEnabled,
  required DeviceNotificationPermission permission,
}) {
  final permissionGranted =
      permission == DeviceNotificationPermission.authorized ||
      permission == DeviceNotificationPermission.provisional;
  return NotificationPreferenceDecision(
    enabled: requestedEnabled && permissionGranted,
    shouldOpenSystemSettings:
        requestedEnabled && permission == DeviceNotificationPermission.denied,
  );
}

/// The four local notification switches are one logical preference record.
///
/// SharedPreferences exposes a per-key write API, so a platform/storage
/// failure can otherwise leave a partially updated set of switches. Keeping
/// the previous state here gives the settings screen a truthful rollback
/// boundary and makes the behavior testable without booting Firebase.
class NotificationPreferenceState {
  final bool enabled;
  final bool messages;
  final bool insights;
  final bool previewContent;

  const NotificationPreferenceState({
    required this.enabled,
    required this.messages,
    required this.insights,
    required this.previewContent,
  });

  Map<String, bool> toMap() => {
    'enabled': enabled,
    'messages': messages,
    'insights': insights,
    'preview': previewContent,
  };
}

typedef NotificationPreferenceWriter =
    Future<bool> Function(String key, bool value);

/// Persists the complete local notification preference as one logical
/// mutation. If any individual key rejects the write, restore the keys that
/// changed and rethrow the original failure so callers can show retry copy.
Future<void> persistNotificationPreferenceState({
  required NotificationPreferenceState previous,
  required NotificationPreferenceState next,
  required NotificationPreferenceWriter write,
}) async {
  final previousValues = previous.toMap();
  final nextValues = next.toMap();
  final changedKeys = <String>[];
  try {
    for (final entry in nextValues.entries) {
      if (entry.value == previousValues[entry.key]) continue;
      // Track the key before invoking the platform writer. A writer can
      // mutate storage and then throw while reporting its result.
      changedKeys.add(entry.key);
      final persisted = await write(entry.key, entry.value);
      if (!persisted) {
        throw StateError(
          'Notification preference storage rejected ${entry.key}.',
        );
      }
    }
  } catch (error, stackTrace) {
    for (final key in changedKeys.reversed) {
      try {
        await write(key, previousValues[key]!);
      } catch (_) {
        // Preserve the original error. The next settings load will expose
        // the storage failure and the user can retry the whole record.
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

class NotificationService {
  static const _deviceIdKey = 'braid_installation_device_id';
  static const _enabledKey = 'notifications_enabled';
  static const _messagesEnabledKey = 'message_notifications_enabled';
  static const _insightsEnabledKey = 'insight_notifications_enabled';
  static const _previewContentKey = 'notification_preview_content';
  static const _permissionOfferDismissedKey =
      'notification_permission_offer_dismissed';
  static const _messagesChannelId = 'braid_messages';
  static const _insightsChannelId = 'braid_insights';
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final NotificationDestinationStore destination =
      NotificationDestinationStore();

  bool _pluginInitialized = false;

  Future<void> init() async {
    await destination.restore();
    if (!_pluginInitialized) {
      await _initializePluginAndListeners();
      _pluginInitialized = true;
    }
    final preferences = await loadPreferences();
    if (preferences['enabled'] == true) {
      await registerCurrentDevice();
    }
  }

  Future<void> _initializePluginAndListeners() async {
    await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final parsedDestination = _destinationFromLocalPayload(payload);
        if (parsedDestination != null) {
          unawaited(_setDestinationSafely(parsedDestination));
        }
      },
    );

    const messageChannel = AndroidNotificationChannel(
      _messagesChannelId,
      'Braid messages',
      description: 'New activity in your study groups.',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('message_notification'),
    );
    const insightChannel = AndroidNotificationChannel(
      _insightsChannelId,
      'Braid reflections',
      description: 'New reflections shared with you.',
      importance: Importance.defaultImportance,
      sound: RawResourceAndroidNotificationSound('insight_notification'),
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(messageChannel);
    await androidPlugin?.createNotificationChannel(insightChannel);

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_routeRemoteMessage);
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _routeRemoteMessage(initialMessage);

    _messaging.onTokenRefresh.listen((token) {
      unawaited(
        _writeDeviceToken(token).catchError((error, stackTrace) {
          if (kDebugMode) {
            debugPrint('Notification token registration failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }),
      );
    });
  }

  Future<DeviceNotificationPermission> registerCurrentDevice({
    bool requestPermission = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return DeviceNotificationPermission.denied;

    final permission = await _readDevicePermission(
      requestPermission: requestPermission,
    );
    final decision = resolveNotificationPreference(
      requestedEnabled: true,
      permission: permission,
    );
    if (!decision.enabled) {
      await _persistEnabledPreference(false);
      await unregisterCurrentDevice();
      return permission;
    }

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) await _writeDeviceToken(token);
    return permission;
  }

  Future<DeviceNotificationPermission> getDevicePermission() {
    return _readDevicePermission(requestPermission: false);
  }

  Future<DeviceNotificationPermission> _readDevicePermission({
    required bool requestPermission,
  }) async {
    final settings = requestPermission
        ? await _messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          )
        : await _messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => DeviceNotificationPermission.authorized,
      AuthorizationStatus.provisional =>
        DeviceNotificationPermission.provisional,
      AuthorizationStatus.denied => DeviceNotificationPermission.denied,
      AuthorizationStatus.notDetermined =>
        DeviceNotificationPermission.notDetermined,
    };
  }

  Future<Map<String, bool>> loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      'enabled': preferences.getBool(_enabledKey) ?? false,
      'messages': preferences.getBool(_messagesEnabledKey) ?? true,
      'insights': preferences.getBool(_insightsEnabledKey) ?? true,
      'preview': preferences.getBool(_previewContentKey) ?? false,
    };
  }

  Future<bool> shouldOfferPermission() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_permissionOfferDismissedKey) == true ||
        preferences.getBool(_enabledKey) == true) {
      return false;
    }
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.notDetermined;
  }

  Future<void> dismissPermissionOffer() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_permissionOfferDismissedKey, true);
  }

  Future<NotificationPreferenceDecision> updatePreferences({
    required bool enabled,
    required bool messages,
    required bool insights,
    required bool previewContent,
  }) async {
    final permission = enabled
        ? await _readDevicePermission(requestPermission: true)
        : await _readDevicePermission(requestPermission: false);
    final decision = resolveNotificationPreference(
      requestedEnabled: enabled,
      permission: permission,
    );
    final preferences = await SharedPreferences.getInstance();
    final previous = NotificationPreferenceState(
      enabled: preferences.getBool(_enabledKey) ?? false,
      messages: preferences.getBool(_messagesEnabledKey) ?? true,
      insights: preferences.getBool(_insightsEnabledKey) ?? true,
      previewContent: preferences.getBool(_previewContentKey) ?? false,
    );
    final next = NotificationPreferenceState(
      enabled: decision.enabled,
      messages: messages,
      insights: insights,
      previewContent: previewContent,
    );
    await persistNotificationPreferenceState(
      previous: previous,
      next: next,
      write: (key, value) => preferences.setBool(switch (key) {
        'enabled' => _enabledKey,
        'messages' => _messagesEnabledKey,
        'insights' => _insightsEnabledKey,
        'preview' => _previewContentKey,
        _ => throw StateError('Unknown notification preference key: $key'),
      }, value),
    );

    try {
      if (!decision.enabled) {
        await unregisterCurrentDevice();
        return decision;
      }

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) await _writeDeviceToken(token);
      final user = FirebaseAuth.instance.currentUser;
      final deviceId = preferences.getString(_deviceIdKey);
      if (user == null || deviceId == null) return decision;
      final deviceReference = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId);
      if (!(await deviceReference.get()).exists) return decision;
      await deviceReference.update({
        'notificationsEnabled': decision.enabled,
        'messageNotifications': messages,
        'insightNotifications': insights,
        'previewContent': previewContent,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await waitForDocumentCommit(deviceReference);
      return decision;
    } catch (error, stackTrace) {
      await _restoreLocalNotificationPreferences(preferences, previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _restoreLocalNotificationPreferences(
    SharedPreferences preferences,
    NotificationPreferenceState state,
  ) async {
    final values = {
      _enabledKey: state.enabled,
      _messagesEnabledKey: state.messages,
      _insightsEnabledKey: state.insights,
      _previewContentKey: state.previewContent,
    };
    for (final entry in values.entries) {
      try {
        await preferences.setBool(entry.key, entry.value);
      } catch (_) {
        // Keep the original remote failure as the user-facing error. A later
        // settings load can retry the complete preference record.
      }
    }
  }

  Future<void> _persistEnabledPreference(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }

  Future<void> _writeDeviceToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || token.isEmpty) return;

    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await preferences.setString(_deviceIdKey, deviceId);
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final localPreferences = await loadPreferences();
    final deviceReference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId);
    final existingDevice = await deviceReference.get();
    await deviceReference.set({
      'token': token,
      'platform': _platformName,
      'appVersion': packageInfo.version,
      'notificationsEnabled': localPreferences['enabled'],
      'messageNotifications': localPreferences['messages'],
      'insightNotifications': localPreferences['insights'],
      'previewContent': localPreferences['preview'],
      if (!existingDevice.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await waitForDocumentCommit(deviceReference);
  }

  Future<void> unregisterCurrentDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final preferences = await SharedPreferences.getInstance();
    final deviceId = preferences.getString(_deviceIdKey);
    if (deviceId != null) {
      final deviceReference = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId);
      await deviceReference.delete();
      await waitForDocumentCommit(deviceReference);
    }
    try {
      await _messaging.deleteToken();
    } catch (_) {
      // Deleting the private Firestore token record is the security boundary.
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
      _ => 'android',
    };
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final data = message.data;
    final isInsight =
        data['type'] == 'insight' || data['type'] == 'new_insight';
    final preferences = await loadPreferences();
    if (preferences['enabled'] != true ||
        (isInsight && preferences['insights'] != true) ||
        (!isInsight && preferences['messages'] != true)) {
      return;
    }
    final channelId = isInsight ? _insightsChannelId : _messagesChannelId;
    final soundName = isInsight
        ? 'insight_notification'
        : 'message_notification';

    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: notification.title ?? 'Braid',
      body: preferences['preview'] == true
          ? notification.body ?? 'New activity'
          : 'Open Braid to view this update.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          isInsight ? 'Braid reflections' : 'Braid messages',
          channelDescription: isInsight
              ? 'New reflections shared with you.'
              : 'New activity in your study groups.',
          importance: Importance.high,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound(soundName),
          tag: data['groupId']?.toString(),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: NotificationDestination.fromData(data).toPayload(),
    );
  }

  void _routeRemoteMessage(RemoteMessage message) {
    final parsedDestination = NotificationDestination.fromData(message.data);
    if (parsedDestination.isValid) {
      unawaited(_setDestinationSafely(parsedDestination));
    }
  }

  Future<void> _setDestinationSafely(
    NotificationDestination parsedDestination,
  ) async {
    try {
      await destination.setPending(parsedDestination);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Notification destination persistence failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  NotificationDestination? _destinationFromLocalPayload(String payload) {
    final jsonDestination = NotificationDestination.fromPayload(payload);
    if (jsonDestination != null) return jsonDestination;

    final segments = payload.split('|');
    if (segments.isEmpty) return null;
    final legacyDestination = NotificationDestination.fromData({
      'type': segments.first,
      if (segments.length > 1) 'groupId': segments[1],
      if (segments.length > 2) 'messageId': segments[2],
      if (segments.length > 3) 'insightId': segments[3],
    });
    return legacyDestination.isValid ? legacyDestination : null;
  }

  Future<void> playActionSound() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('mute_app_sounds') == true) return;
    await _playAsset('sounds/action_notification.mp3');
  }

  Future<void> playInsightSound() =>
      _playAsset('sounds/insight_notification.mp3');

  Future<void> playMessageSound() =>
      _playAsset('sounds/message_notification.mp3');

  Future<void> _playAsset(String path) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(path), mode: PlayerMode.lowLatency);
    } catch (_) {
      // Sound is decorative; notification delivery must not depend on it.
    }
  }
}
