import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, voice, hybrid }

class MessagePart {
  final MessageType type;
  final String content; // Text string or Base64 string for audio
  final int? durationSeconds;

  MessagePart({
    required this.type,
    required this.content,
    this.durationSeconds,
  });

  factory MessagePart.fromMap(Map<String, dynamic> data) {
    return MessagePart(
      type: data['type'] == 'voice' ? MessageType.voice : MessageType.text,
      content: data['content'] ?? '',
      durationSeconds: data['durationSeconds'],
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
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String? replyToMessageId;
  final List<MessagePart> parts;
  final DateTime timestamp;
  final List<String> starredBy;
  final List<String> deletedFor;
  final bool isDeleted;
  final bool isEdited;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    this.replyToMessageId,
    required this.parts,
    required this.timestamp,
    required this.starredBy,
    this.deletedFor = const [],
    this.isDeleted = false,
    this.isEdited = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    List<MessagePart> parsedParts = [];
    if (data['parts'] != null) {
      parsedParts = (data['parts'] as List)
          .map((item) => MessagePart.fromMap(item as Map<String, dynamic>))
          .toList();
    } else {
      // Backward compatibility for old single-part messages
      parsedParts = [
        MessagePart(
          type: data['type'] == 'voice' ? MessageType.voice : MessageType.text,
          content: data['content'] ?? '',
          durationSeconds: data['durationSeconds'],
        )
      ];
    }

    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderPhotoUrl: data['senderPhotoUrl'],
      replyToMessageId: data['replyToMessageId'],
      parts: parsedParts,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      starredBy: List<String>.from(data['starredBy'] ?? []),
      deletedFor: List<String>.from(data['deletedFor'] ?? []),
      isDeleted: data['isDeleted'] ?? false,
      isEdited: data['isEdited'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      if (senderPhotoUrl != null) 'senderPhotoUrl': senderPhotoUrl,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      'parts': parts.map((p) => p.toMap()).toList(),
      'timestamp': timestamp,
      'starredBy': starredBy,
      'deletedFor': deletedFor,
      'isDeleted': isDeleted,
      'isEdited': isEdited,
    };
  }
}
