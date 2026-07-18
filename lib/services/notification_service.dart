import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Set audio player context for notifications
    await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);

    // Create the custom Android channel for messages
    const AndroidNotificationChannel messageChannel = AndroidNotificationChannel(
      'braid_messages', // id
      'Braid Messages', // title
      description: 'Notifications for new messages with custom sound.',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('message_notification'),
    );

    // Create the custom Android channel for insights
    const AndroidNotificationChannel insightChannel = AndroidNotificationChannel(
      'braid_insights', // id
      'Braid Insights', // title
      description: 'Notifications for new insights.',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('insight_notification'),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(messageChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(insightChannel);

    // Request permission for iOS / Android 13+
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) print('User granted permission for notifications');
      await _saveTokenToDatabase();

      // Listen to token refreshes
      _fcm.onTokenRefresh.listen(_updateTokenInDatabase);
      
      // Handle foreground messages if needed later
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Got a message whilst in the foreground!');
        }
        final type = message.data['type'];
        if (type == 'insight' || type == 'new_insight') {
          playInsightSound();
        } else {
          playMessageSound();
        }
      });
    } else {
      if (kDebugMode) print('User declined or has not accepted permission');
    }
  }

  Future<void> playActionSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('mute_app_sounds') == true) return;

      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/action_notification.mp3'), mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) print('Error playing action sound: $e');
    }
  }

  Future<void> playInsightSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/insight_notification.mp3'), mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) print('Error playing insight sound: $e');
    }
  }

  Future<void> playMessageSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/message_notification.mp3'), mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) print('Error playing message sound: $e');
    }
  }

  Future<void> _saveTokenToDatabase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _updateTokenInDatabase(token);
      }
    } catch (e) {
      if (kDebugMode) print('Error getting FCM token: $e');
    }
  }

  Future<void> _updateTokenInDatabase(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) print('FCM Token saved to Firestore');
    } catch (e) {
      if (kDebugMode) print('Error saving FCM token to Firestore: $e');
    }
  }
}
