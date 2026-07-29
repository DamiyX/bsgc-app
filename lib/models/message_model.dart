import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _messageDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class MessageTimestamp {
  final DateTime value;
  final bool isKnown;

  const MessageTimestamp({required this.value, required this.isKnown});
}

MessageTimestamp resolveMessageTimestamp({
  required dynamic serverTimestamp,
  required dynamic clientCreatedAt,
}) {
  final resolved =
      _messageDate(serverTimestamp) ?? _messageDate(clientCreatedAt);
  return MessageTimestamp(
    value: resolved ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isKnown: resolved != null,
  );
}

enum MessageType { text, voice, hybrid, image, video, document }

class MessagePart {
  final MessageType type;

  /// Text content or an HTTPS/file URI for staged media.
  final String content;
  final int? durationSeconds;

  MessagePart({
    required this.type,
    required this.content,
    this.durationSeconds,
  });

  static MessageType _parseMessageType(dynamic typeStr) {
    if (typeStr == 'voice') return MessageType.voice;
    if (typeStr == 'image') return MessageType.image;
    if (typeStr == 'video') return MessageType.video;
    if (typeStr == 'document') return MessageType.document;
    if (typeStr == 'hybrid') return MessageType.hybrid;
    return MessageType.text;
  }

  factory MessagePart.fromMap(Map<String, dynamic> data) {
    final rawDuration = data['durationSeconds'];
    return MessagePart(
      type: _parseMessageType(data['type']),
      content: data['content']?.toString() ?? '',
      durationSeconds: rawDuration is num ? rawDuration.toInt() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'content': content,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    };
  }
}

class MessageModel {
  final String id;
  final int schemaVersion;
  final String? clientMessageId;
  final String space;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String? replyToMessageId;
  final List<MessagePart> parts;
  final DateTime timestamp;
  final bool hasKnownTimestamp;
  final List<String> deletedFor;
  final bool isDeleted;
  final bool isEdited;
  final bool isPending;
  final bool isFromCache;

  MessageModel({
    required this.id,
    this.schemaVersion = 2,
    this.clientMessageId,
    this.space = 'discussion',
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    this.replyToMessageId,
    required this.parts,
    required this.timestamp,
    this.hasKnownTimestamp = true,
    this.deletedFor = const [],
    this.isDeleted = false,
    this.isEdited = false,
    this.isPending = false,
    this.isFromCache = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : const <String, dynamic>{};

    List<MessagePart> parsedParts = [];
    if (data['parts'] is List) {
      parsedParts = (data['parts'] as List)
          .whereType<Map>()
          .map((item) => MessagePart.fromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } else {
      // Backward compatibility for old single-part messages
      parsedParts = [
        MessagePart(
          type: MessagePart._parseMessageType(data['type']),
          content: data['content']?.toString() ?? '',
          durationSeconds: data['durationSeconds'] is num
              ? (data['durationSeconds'] as num).toInt()
              : null,
        ),
      ];
    }

    final resolvedTimestamp = resolveMessageTimestamp(
      serverTimestamp: data['timestamp'],
      clientCreatedAt: data['clientCreatedAt'],
    );

    return MessageModel(
      id: doc.id,
      schemaVersion: data['schemaVersion'] is int ? data['schemaVersion'] : 1,
      clientMessageId: data['clientMessageId']?.toString(),
      space: switch (data['space']?.toString()) {
        'reflection' => 'reflection',
        'prayer' => 'prayer',
        _ => 'discussion',
      },
      senderId: data['senderId']?.toString() ?? '',
      senderName: data['senderName']?.toString() ?? 'Believer',
      senderPhotoUrl: data['senderPhotoUrl']?.toString(),
      replyToMessageId: data['replyToMessageId']?.toString(),
      parts: parsedParts,
      timestamp: resolvedTimestamp.value,
      hasKnownTimestamp: resolvedTimestamp.isKnown,
      deletedFor: data['deletedFor'] is List
          ? (data['deletedFor'] as List).whereType<String>().toList()
          : const [],
      isDeleted: data['isDeleted'] == true,
      isEdited: data['isEdited'] == true,
      isPending: doc.metadata.hasPendingWrites,
      isFromCache: doc.metadata.isFromCache,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      'space': space,
      'senderId': senderId,
      'senderName': senderName,
      if (senderPhotoUrl != null) 'senderPhotoUrl': senderPhotoUrl,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      'parts': parts.map((p) => p.toMap()).toList(),
      'timestamp': timestamp,
      'deletedFor': deletedFor,
      'isDeleted': isDeleted,
      'isEdited': isEdited,
    };
  }
}

class MessageVisibilityState {
  final Set<String> hiddenMessageIds;
  final DateTime? clearedBefore;

  const MessageVisibilityState({
    this.hiddenMessageIds = const {},
    this.clearedBefore,
  });

  bool allows(MessageModel message, {required String userId}) {
    if (hiddenMessageIds.contains(message.id)) return false;
    if (message.deletedFor.contains(userId)) return false;

    final clearCutoff = clearedBefore;
    return clearCutoff == null || message.timestamp.isAfter(clearCutoff);
  }
}
