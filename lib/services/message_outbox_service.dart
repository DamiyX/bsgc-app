import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_model.dart';
import 'chat_service.dart';
import 'storage_service.dart';

enum OutboxStatus { queued, sending, failed }

class OutboxMessage {
  final String id;
  final String userId;
  final String groupId;
  final String space;
  final List<MessagePart> parts;
  final String? replyToMessageId;
  final DateTime createdAt;
  final OutboxStatus status;
  final int attempts;
  final String? lastError;

  const OutboxMessage({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.space,
    required this.parts,
    required this.createdAt,
    this.replyToMessageId,
    this.status = OutboxStatus.queued,
    this.attempts = 0,
    this.lastError,
  });

  OutboxMessage copyWith({
    OutboxStatus? status,
    int? attempts,
    String? lastError,
    bool clearError = false,
  }) {
    return OutboxMessage(
      id: id,
      userId: userId,
      groupId: groupId,
      space: space,
      parts: parts,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'userId': userId,
    'groupId': groupId,
    'space': space,
    'parts': parts.map((part) => part.toMap()).toList(),
    if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'attempts': attempts,
    if (lastError != null) 'lastError': lastError,
  };

  factory OutboxMessage.fromJson(Map<String, dynamic> data) {
    final rawParts = data['parts'];
    return OutboxMessage(
      id: data['id']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      groupId: data['groupId']?.toString() ?? '',
      space: data['space']?.toString() ?? 'discussion',
      parts: rawParts is List
          ? rawParts
                .whereType<Map>()
                .map(
                  (part) => MessagePart.fromMap(
                    Map<String, dynamic>.from(part),
                  ),
                )
                .toList(growable: false)
          : const [],
      replyToMessageId: data['replyToMessageId']?.toString(),
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      status: OutboxStatus.values.firstWhere(
        (value) => value.name == data['status'],
        orElse: () => OutboxStatus.queued,
      ),
      attempts: data['attempts'] is num
          ? (data['attempts'] as num).toInt()
          : 0,
      lastError: data['lastError']?.toString(),
    );
  }
}

/// A process-safe outbox for message metadata and local media.
///
/// Firestore already persists text writes while offline. This outbox closes
/// the gap before that write, especially for media that must reach Storage
/// first. A stable message ID makes every retry idempotent.
class MessageOutboxService {
  static const int maxImageBytes = 8 * 1024 * 1024;
  static const int maxAudioBytes = 10 * 1024 * 1024;

  Future<String> persistAttachment({
    required String userId,
    required String groupId,
    required String messageId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = extension.toLowerCase().replaceAll('.', '');
    if (!RegExp(r'^(jpg|jpeg|png|webp|m4a|aac)$')
        .hasMatch(normalizedExtension)) {
      throw ArgumentError('Unsupported attachment type.');
    }
    final isAudio = {'m4a', 'aac'}.contains(normalizedExtension);
    final limit = isAudio ? maxAudioBytes : maxImageBytes;
    if (bytes.isEmpty || bytes.length > limit) {
      throw ArgumentError(
        isAudio
            ? 'Voice reflections must be under 10 MB.'
            : 'Images must be under 8 MB.',
      );
    }

    final directory = await _entryDirectory(userId, groupId, messageId);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'attachment_${DateTime.now().microsecondsSinceEpoch}.$normalizedExtension',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    return file.uri.toString();
  }

  Future<OutboxMessage> enqueue({
    required String id,
    required String userId,
    required String groupId,
    required String space,
    required List<MessagePart> parts,
    String? replyToMessageId,
  }) async {
    if (parts.isEmpty) {
      throw ArgumentError('An outbox message cannot be empty.');
    }
    final entry = OutboxMessage(
      id: id,
      userId: userId,
      groupId: groupId,
      space: space,
      parts: List.unmodifiable(parts),
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now(),
    );
    await _write(entry);
    return entry;
  }

  Future<List<OutboxMessage>> list({
    required String userId,
    required String groupId,
  }) async {
    final root = await _groupDirectory(userId, groupId);
    if (!await root.exists()) return const [];
    final entries = <OutboxMessage>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final metadata = File(
        '${entity.path}${Platform.pathSeparator}message.json',
      );
      if (!await metadata.exists()) continue;
      try {
        final decoded = jsonDecode(await metadata.readAsString());
        if (decoded is Map<String, dynamic>) {
          final entry = OutboxMessage.fromJson(decoded);
          if (entry.id.isNotEmpty &&
              entry.userId == userId &&
              entry.groupId == groupId) {
            entries.add(entry);
          }
        }
      } catch (_) {
        // A damaged entry stays on disk for support recovery but cannot send.
      }
    }
    entries.sort((first, second) => first.createdAt.compareTo(second.createdAt));
    return entries;
  }

  Future<void> send(
    OutboxMessage entry, {
    required ChatService chatService,
  }) async {
    final sending = entry.copyWith(
      status: OutboxStatus.sending,
      attempts: entry.attempts + 1,
      clearError: true,
    );
    await _write(sending);
    try {
      final uploadedParts = <MessagePart>[];
      for (var index = 0; index < entry.parts.length; index++) {
        final part = entry.parts[index];
        final uri = Uri.tryParse(part.content);
        if (uri?.scheme != 'file') {
          uploadedParts.add(part);
          continue;
        }
        final file = File.fromUri(uri!);
        if (!await file.exists()) {
          throw StateError('A local attachment is no longer available.');
        }
        final bytes = await file.readAsBytes();
        final extension = file.path.split('.').last.toLowerCase();
        final contentType = lookupMimeType(file.path) ??
            (part.type == MessageType.voice
                ? 'audio/mp4'
                : 'application/octet-stream');
        final remoteUrl = await StorageService.uploadMessageAsset(
          bytes: bytes,
          groupId: entry.groupId,
          messageId: entry.id,
          ownerId: entry.userId,
          extension: extension,
          contentType: contentType,
          assetId: 'part_$index.$extension',
        );
        uploadedParts.add(
          MessagePart(
            type: part.type,
            content: remoteUrl,
            durationSeconds: part.durationSeconds,
          ),
        );
      }

      await chatService.sendHybridMessage(
        entry.groupId,
        uploadedParts,
        replyToMessageId: entry.replyToMessageId,
        clientMessageId: entry.id,
        space: entry.space,
      );
      await remove(entry);
    } catch (error) {
      await _write(
        sending.copyWith(
          status: OutboxStatus.failed,
          lastError: _safeError(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> remove(OutboxMessage entry) async {
    final directory = await _entryDirectory(
      entry.userId,
      entry.groupId,
      entry.id,
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> clearAllForUser(String userId) async {
    final root = await _userDirectory(userId);
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<void> _write(OutboxMessage entry) async {
    final directory = await _entryDirectory(
      entry.userId,
      entry.groupId,
      entry.id,
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}message.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<Directory> _entryDirectory(
    String userId,
    String groupId,
    String messageId,
  ) async {
    final root = await _groupDirectory(userId, groupId);
    return Directory(
      '${root.path}${Platform.pathSeparator}${_safeId(messageId)}',
    );
  }

  Future<Directory> _groupDirectory(String userId, String groupId) async {
    final root = await _userDirectory(userId);
    return Directory(
      '${root.path}${Platform.pathSeparator}${_safeId(groupId)}',
    );
  }

  Future<Directory> _userDirectory(String userId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}message_outbox'
      '${Platform.pathSeparator}${_safeId(userId)}',
    );
  }

  String _safeId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value)) {
      throw ArgumentError('Invalid outbox identifier.');
    }
    return value;
  }

  String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 180 ? text : '${text.substring(0, 177)}...';
  }
}
