import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationDestination {
  static const schemaVersion = 1;
  static const messageSpaces = {'reflection', 'discussion', 'prayer'};

  final int version;
  final String type;
  final String? groupId;
  final String? messageId;
  final String? insightId;
  final String? space;
  final String? parentId;

  const NotificationDestination({
    this.version = schemaVersion,
    required this.type,
    this.groupId,
    this.messageId,
    this.insightId,
    this.space,
    this.parentId,
  });

  factory NotificationDestination.fromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final rawSpace = data['space']?.toString();
    return NotificationDestination(
      version: int.tryParse(data['version']?.toString() ?? '') ?? schemaVersion,
      type: type,
      groupId: _optionalValue(data['groupId']),
      messageId: _optionalValue(data['messageId']),
      insightId: _optionalValue(data['insightId']),
      space: messageSpaces.contains(rawSpace)
          ? rawSpace
          : type == 'group_message'
          ? 'discussion'
          : null,
      parentId: _optionalValue(data['parentId']),
    );
  }

  factory NotificationDestination.fromJson(Map<String, dynamic> data) =>
      NotificationDestination.fromData(data);

  static NotificationDestination? fromPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final destination = NotificationDestination.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return destination.isValid ? destination : null;
    } catch (_) {
      return null;
    }
  }

  bool get isValid {
    if (version != schemaVersion || type.isEmpty) return false;
    if (type == 'group_message') {
      return _hasValue(groupId) &&
          _hasValue(messageId) &&
          messageSpaces.contains(space);
    }
    if (type == 'insight' || type == 'new_insight') {
      return _hasValue(insightId);
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'type': type,
    if (_hasValue(groupId)) 'groupId': groupId,
    if (_hasValue(messageId)) 'messageId': messageId,
    if (_hasValue(insightId)) 'insightId': insightId,
    if (_hasValue(space)) 'space': space,
    if (_hasValue(parentId)) 'parentId': parentId,
  };

  String toPayload() => jsonEncode(toJson());

  bool matches(NotificationDestination other) {
    return version == other.version &&
        type == other.type &&
        groupId == other.groupId &&
        messageId == other.messageId &&
        insightId == other.insightId &&
        space == other.space &&
        parentId == other.parentId;
  }

  static String? _optionalValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _hasValue(String? value) => value?.trim().isNotEmpty == true;
}

abstract interface class NotificationDestinationPersistence {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

class SharedPreferencesNotificationDestinationPersistence
    implements NotificationDestinationPersistence {
  static const _pendingDestinationKey = 'pending_notification_destination_v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_pendingDestinationKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pendingDestinationKey, value);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingDestinationKey);
  }
}

class NotificationDestinationStore
    extends ValueNotifier<NotificationDestination?> {
  final NotificationDestinationPersistence _persistence;

  NotificationDestinationStore({
    NotificationDestinationPersistence? persistence,
  }) : _persistence =
           persistence ?? SharedPreferencesNotificationDestinationPersistence(),
       super(null);

  Future<void> restore() async {
    final payload = await _persistence.read();
    if (payload == null) return;
    final destination = NotificationDestination.fromPayload(payload);
    if (destination == null) {
      await _persistence.clear();
      return;
    }
    value = destination;
  }

  Future<void> setPending(NotificationDestination destination) async {
    if (!destination.isValid) {
      throw const FormatException('Invalid notification destination.');
    }
    await _persistence.write(destination.toPayload());
    value = destination;
  }

  Future<void> complete(NotificationDestination destination) async {
    final pending = value;
    if (pending == null || !pending.matches(destination)) return;
    await _persistence.clear();
    value = null;
  }

  Future<void> discardAll() async {
    await _persistence.clear();
    value = null;
  }
}
