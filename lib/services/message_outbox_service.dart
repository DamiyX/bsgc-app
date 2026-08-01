import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_model.dart';
import 'chat_service.dart';
import 'storage_service.dart';

enum OutboxStatus { queued, sending, failed, corrupt }

enum OutboxWriteStage { tempFlushed, backupReady, committed }

class OutboxPolicy {
  static const defaultMaxTotalBytes = 64 * 1024 * 1024;

  final int maxItems;
  final int maxTotalBytes;
  final Duration retention;
  final int maxAutomaticAttempts;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;

  const OutboxPolicy({
    this.maxItems = 25,
    this.maxTotalBytes = defaultMaxTotalBytes,
    this.retention = const Duration(days: 30),
    this.maxAutomaticAttempts = 6,
    this.initialRetryDelay = const Duration(seconds: 30),
    this.maxRetryDelay = const Duration(hours: 6),
  });

  Duration retryDelay(int attempts) {
    var milliseconds = initialRetryDelay.inMilliseconds;
    for (var index = 1; index < attempts; index++) {
      if (milliseconds >= maxRetryDelay.inMilliseconds) {
        return maxRetryDelay;
      }
      milliseconds *= 2;
    }
    return Duration(
      milliseconds: milliseconds.clamp(0, maxRetryDelay.inMilliseconds).toInt(),
    );
  }
}

class OutboxDataException implements Exception {
  final String message;

  const OutboxDataException(this.message);

  @override
  String toString() => message;
}

class OutboxQuotaException implements Exception {
  final String message;

  const OutboxQuotaException(this.message);

  @override
  String toString() => message;
}

class OutboxRetryException implements Exception {
  final String message;

  const OutboxRetryException(this.message);

  @override
  String toString() => message;
}

class OutboxMessage {
  final String id;
  final String userId;
  final String groupId;
  final String space;
  final List<MessagePart> parts;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final OutboxStatus status;
  final int attempts;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final bool retryable;
  final bool automaticRetryAvailable;
  final String? lastError;

  const OutboxMessage({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.space,
    required this.parts,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.replyToMessageId,
    this.status = OutboxStatus.queued,
    this.attempts = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.retryable = true,
    this.automaticRetryAvailable = true,
    this.lastError,
  });

  bool canAttempt({required bool manual, required DateTime now}) {
    if (!retryable || status == OutboxStatus.corrupt) return false;
    if (manual) return true;
    if (!automaticRetryAvailable) return false;
    final dueAt = nextRetryAt;
    return dueAt == null || !dueAt.isAfter(now);
  }

  OutboxMessage beginAttempt(DateTime now) {
    return copyWith(
      status: OutboxStatus.sending,
      attempts: (attempts + 1).clamp(0, 1000000),
      lastAttemptAt: now,
      updatedAt: now,
      clearNextRetryAt: true,
      clearError: true,
    );
  }

  OutboxMessage failAttempt({
    required DateTime now,
    required String safeError,
    required OutboxPolicy policy,
  }) {
    final canRetryAutomatically = attempts < policy.maxAutomaticAttempts;
    return copyWith(
      status: OutboxStatus.failed,
      updatedAt: now,
      nextRetryAt: canRetryAutomatically
          ? now.add(policy.retryDelay(attempts))
          : null,
      clearNextRetryAt: !canRetryAutomatically,
      automaticRetryAvailable: canRetryAutomatically,
      lastError: safeError,
    );
  }

  OutboxMessage copyWith({
    OutboxStatus? status,
    int? attempts,
    DateTime? updatedAt,
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    bool? retryable,
    bool? automaticRetryAvailable,
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
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      retryable: retryable ?? this.retryable,
      automaticRetryAvailable:
          automaticRetryAvailable ?? this.automaticRetryAvailable,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  OutboxMessage missingAttachment(DateTime now) {
    return copyWith(
      status: OutboxStatus.failed,
      updatedAt: now,
      retryable: false,
      automaticRetryAvailable: false,
      clearNextRetryAt: true,
      lastError:
          'A saved attachment is no longer available. Discard this upload.',
    );
  }

  factory OutboxMessage.corrupt({
    required String id,
    required String userId,
    required String groupId,
    required DateTime discoveredAt,
  }) {
    return OutboxMessage(
      id: id,
      userId: userId,
      groupId: groupId,
      space: 'discussion',
      parts: const [],
      createdAt: discoveredAt,
      updatedAt: discoveredAt,
      status: OutboxStatus.corrupt,
      retryable: false,
      automaticRetryAvailable: false,
      lastError:
          'Saved upload information is damaged. Discard this upload safely.',
    );
  }

  Map<String, dynamic> toPayload() => {
    'id': id,
    'userId': userId,
    'groupId': groupId,
    'space': space,
    'parts': parts.map((part) => part.toMap()).toList(),
    if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': (updatedAt ?? createdAt).toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    'status': status.name,
    'attempts': attempts,
    if (lastAttemptAt != null)
      'lastAttemptAt': lastAttemptAt!.toUtc().toIso8601String(),
    if (nextRetryAt != null)
      'nextRetryAt': nextRetryAt!.toUtc().toIso8601String(),
    'retryable': retryable,
    'automaticRetryAvailable': automaticRetryAvailable,
    if (lastError != null) 'lastError': lastError,
  };
}

class OutboxMessageCodec {
  static const schemaVersion = 2;

  static Map<String, dynamic> encode(OutboxMessage entry) {
    final unsigned = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'accountId': entry.userId,
      'payload': entry.toPayload(),
    };
    return {...unsigned, 'checksum': _checksum(unsigned)};
  }

  static OutboxMessage decode(
    Map<String, dynamic> data, {
    required String expectedUserId,
    required String expectedGroupId,
    required String expectedMessageId,
    Duration legacyRetention = const Duration(days: 30),
  }) {
    final version = data['schemaVersion'];
    if (version == 1) {
      return _fromPayload(
        data,
        expectedUserId: expectedUserId,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        legacyRetention: legacyRetention,
      );
    }
    if (version != schemaVersion) {
      throw const OutboxDataException('Unsupported outbox schema.');
    }
    final accountId = data['accountId'];
    final rawPayload = data['payload'];
    final checksum = data['checksum'];
    if (accountId is! String || rawPayload is! Map || checksum is! String) {
      throw const OutboxDataException('Incomplete outbox envelope.');
    }
    final payload = Map<String, dynamic>.from(rawPayload);
    final unsigned = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'accountId': accountId,
      'payload': payload,
    };
    if (_checksum(unsigned) != checksum) {
      throw const OutboxDataException('Outbox checksum mismatch.');
    }
    if (accountId != expectedUserId) {
      throw const OutboxDataException('Outbox account mismatch.');
    }
    return _fromPayload(
      payload,
      expectedUserId: expectedUserId,
      expectedGroupId: expectedGroupId,
      expectedMessageId: expectedMessageId,
      legacyRetention: legacyRetention,
    );
  }

  static OutboxMessage _fromPayload(
    Map<String, dynamic> data, {
    required String expectedUserId,
    required String expectedGroupId,
    required String expectedMessageId,
    required Duration legacyRetention,
  }) {
    final id = data['id'];
    final userId = data['userId'];
    final groupId = data['groupId'];
    final space = data['space'];
    final rawParts = data['parts'];
    final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    if (id != expectedMessageId ||
        userId != expectedUserId ||
        groupId != expectedGroupId) {
      throw const OutboxDataException('Outbox identity mismatch.');
    }
    if (space is! String ||
        !const {'reflection', 'discussion', 'prayer'}.contains(space) ||
        rawParts is! List ||
        rawParts.isEmpty ||
        rawParts.length > 4 ||
        createdAt == null) {
      throw const OutboxDataException('Invalid outbox payload.');
    }
    final parts = <MessagePart>[];
    for (final rawPart in rawParts) {
      if (rawPart is! Map) {
        throw const OutboxDataException('Invalid outbox message part.');
      }
      final partData = Map<String, dynamic>.from(rawPart);
      if (!const {'text', 'voice', 'image'}.contains(partData['type']) ||
          (partData['content']?.toString().isEmpty ?? true)) {
        throw const OutboxDataException('Invalid outbox message part.');
      }
      parts.add(MessagePart.fromMap(partData));
    }
    final status = OutboxStatus.values.where(
      (value) => value.name == data['status'],
    );
    final attempts = data['attempts'];
    if (status.isEmpty ||
        attempts is! num ||
        attempts < 0 ||
        attempts > 1000000) {
      throw const OutboxDataException('Invalid outbox retry state.');
    }
    final parsedCreatedAt = createdAt.toLocal();
    return OutboxMessage(
      id: id as String,
      userId: userId as String,
      groupId: groupId as String,
      space: space,
      parts: List.unmodifiable(parts),
      replyToMessageId: data['replyToMessageId']?.toString(),
      createdAt: parsedCreatedAt,
      updatedAt:
          DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toLocal() ??
          parsedCreatedAt,
      expiresAt:
          DateTime.tryParse(data['expiresAt']?.toString() ?? '')?.toLocal() ??
          parsedCreatedAt.add(legacyRetention),
      status: status.first,
      attempts: attempts.toInt(),
      lastAttemptAt: DateTime.tryParse(
        data['lastAttemptAt']?.toString() ?? '',
      )?.toLocal(),
      nextRetryAt: DateTime.tryParse(
        data['nextRetryAt']?.toString() ?? '',
      )?.toLocal(),
      retryable: data['retryable'] is bool ? data['retryable'] as bool : true,
      automaticRetryAvailable: data['automaticRetryAvailable'] is bool
          ? data['automaticRetryAvailable'] as bool
          : attempts.toInt() < 6,
      lastError: data['lastError']?.toString(),
    );
  }

  static String _checksum(Map<String, dynamic> data) {
    final encoded = _canonicalJson(data);
    var hash = 0x811c9dc5;
    for (final codeUnit in encoded.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:'
          '${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}

/// A bounded, account-scoped outbox for message metadata and local media.
class MessageOutboxService {
  static const int maxImageBytes = 8 * 1024 * 1024;
  static const int maxAudioBytes = 10 * 1024 * 1024;

  final OutboxPolicy policy;
  final DateTime Function() _clock;
  final Future<Directory> Function(String userId)? outboxRootProvider;
  final Future<void> Function(OutboxWriteStage stage)? writeHook;

  MessageOutboxService({
    this.policy = const OutboxPolicy(),
    DateTime Function()? clock,
    this.outboxRootProvider,
    this.writeHook,
  }) : _clock = clock ?? DateTime.now;

  Future<String> persistAttachment({
    required String userId,
    required String groupId,
    required String messageId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = extension.toLowerCase().replaceAll('.', '');
    if (!RegExp(
      r'^(jpg|jpeg|png|webp|m4a|aac)$',
    ).hasMatch(normalizedExtension)) {
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
    if (!await directory.exists()) {
      await _ensureItemQuota(userId);
    }
    await _ensureByteQuota(userId, bytes.length);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'attachment_${_clock().microsecondsSinceEpoch}.$normalizedExtension',
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
    if (parts.isEmpty || parts.length > 4) {
      throw ArgumentError('An outbox message must contain one to four parts.');
    }
    final directory = await _entryDirectory(userId, groupId, id);
    if (!await directory.exists()) {
      await _ensureItemQuota(userId);
    }
    final now = _clock();
    final entry = OutboxMessage(
      id: id,
      userId: userId,
      groupId: groupId,
      space: space,
      parts: List.unmodifiable(parts),
      replyToMessageId: replyToMessageId,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(policy.retention),
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
      final entry = await _recoverEntry(
        entity,
        userId: userId,
        groupId: groupId,
      );
      if (entry == null) continue;
      final expiresAt =
          entry.expiresAt ?? entry.createdAt.add(policy.retention);
      if (!expiresAt.isAfter(_clock())) {
        await entity.delete(recursive: true);
        continue;
      }
      final reconciled = await _reconcileAttachments(entry);
      if (reconciled != entry) await _write(reconciled);
      entries.add(reconciled);
    }
    entries.sort(
      (first, second) => first.createdAt.compareTo(second.createdAt),
    );
    return entries;
  }

  Future<void> send(
    OutboxMessage entry, {
    required ChatService chatService,
    bool manual = false,
  }) async {
    final now = _clock();
    if (!entry.canAttempt(manual: manual, now: now)) {
      throw OutboxRetryException(
        entry.retryable
            ? 'This upload will retry after its wait period.'
            : 'This upload cannot be retried. Discard it and compose again.',
      );
    }
    final sending = entry.beginAttempt(now);
    await _write(sending);
    try {
      final uploadedParts = <MessagePart>[];
      for (var index = 0; index < sending.parts.length; index++) {
        final part = sending.parts[index];
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
        final contentType =
            lookupMimeType(file.path) ??
            (part.type == MessageType.voice
                ? 'audio/mp4'
                : 'application/octet-stream');
        final managedAsset = await StorageService.uploadMessageAsset(
          bytes: bytes,
          groupId: sending.groupId,
          messageId: sending.id,
          ownerId: sending.userId,
          extension: extension,
          contentType: contentType,
          assetId: 'part_$index.$extension',
        );
        uploadedParts.add(
          MessagePart(
            type: part.type,
            content: managedAsset.storagePath,
            assetId: managedAsset.assetId,
            sizeBytes: managedAsset.sizeBytes,
            durationSeconds: part.durationSeconds,
            caption: part.caption,
          ),
        );
      }

      await chatService.sendHybridMessage(
        sending.groupId,
        uploadedParts,
        replyToMessageId: sending.replyToMessageId,
        clientMessageId: sending.id,
        space: sending.space,
      );
      await remove(sending);
    } catch (error) {
      await _write(
        sending.failAttempt(
          now: _clock(),
          safeError: _safeError(error),
          policy: policy,
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

  Future<OutboxMessage?> _recoverEntry(
    Directory directory, {
    required String userId,
    required String groupId,
  }) async {
    final messageId = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    final metadata = File(
      '${directory.path}${Platform.pathSeparator}message.json',
    );
    final candidates = <_OutboxCandidate>[];
    var discoveredAt = _clock();
    for (final file in [
      metadata,
      File('${metadata.path}.tmp'),
      File('${metadata.path}.bak'),
    ]) {
      if (!await file.exists()) continue;
      discoveredAt = await file.lastModified();
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        final entry = OutboxMessageCodec.decode(
          map,
          expectedUserId: userId,
          expectedGroupId: groupId,
          expectedMessageId: messageId,
          legacyRetention: policy.retention,
        );
        candidates.add(
          _OutboxCandidate(
            file: file,
            entry: entry,
            isLegacy: map['schemaVersion'] == 1,
            modifiedAt: await file.lastModified(),
          ),
        );
      } catch (_) {
        // If no validated candidate remains, a discard-only corrupt item is
        // returned below instead of pretending the outbox is empty.
      }
    }
    if (candidates.isEmpty) {
      final anyMetadata =
          await metadata.exists() ||
          await File('${metadata.path}.tmp').exists() ||
          await File('${metadata.path}.bak').exists();
      return anyMetadata
          ? OutboxMessage.corrupt(
              id: messageId,
              userId: userId,
              groupId: groupId,
              discoveredAt: discoveredAt,
            )
          : null;
    }
    candidates.sort((first, second) {
      final logical = (second.entry.updatedAt ?? second.entry.createdAt)
          .compareTo(first.entry.updatedAt ?? first.entry.createdAt);
      return logical != 0
          ? logical
          : second.modifiedAt.compareTo(first.modifiedAt);
    });
    final selected = candidates.first;
    final needsRecovery =
        selected.file.path != metadata.path || selected.isLegacy;
    if (needsRecovery) {
      await _write(selected.entry.copyWith(updatedAt: _clock()));
    }
    for (final stale in [
      File('${metadata.path}.tmp'),
      File('${metadata.path}.bak'),
    ]) {
      if (await stale.exists()) await stale.delete();
    }
    return selected.entry;
  }

  Future<OutboxMessage> _reconcileAttachments(OutboxMessage entry) async {
    for (final part in entry.parts) {
      final uri = Uri.tryParse(part.content);
      if (uri?.scheme == 'file' && !await File.fromUri(uri!).exists()) {
        return entry.missingAttachment(_clock());
      }
    }
    return entry;
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
    final backup = File('${file.path}.bak');
    final updated = entry.copyWith(updatedAt: _clock());
    await temporary.writeAsString(
      jsonEncode(OutboxMessageCodec.encode(updated)),
      flush: true,
    );
    await writeHook?.call(OutboxWriteStage.tempFlushed);

    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      await writeHook?.call(OutboxWriteStage.backupReady);
    }
    try {
      await temporary.rename(file.path);
      await writeHook?.call(OutboxWriteStage.committed);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<void> _ensureItemQuota(String userId) async {
    await _cleanupExpiredEntries(userId);
    final root = await _userDirectory(userId);
    if (!await root.exists()) return;
    var count = 0;
    await for (final group in root.list(followLinks: false)) {
      if (group is! Directory) continue;
      await for (final entry in group.list(followLinks: false)) {
        if (entry is Directory) count++;
      }
    }
    if (count >= policy.maxItems) {
      throw const OutboxQuotaException(
        'Pending uploads are full. Retry or discard one before adding another.',
      );
    }
  }

  Future<void> _ensureByteQuota(String userId, int additionalBytes) async {
    await _cleanupExpiredEntries(userId);
    final root = await _userDirectory(userId);
    var usedBytes = 0;
    if (await root.exists()) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) usedBytes += await entity.length();
      }
    }
    if (usedBytes + additionalBytes > policy.maxTotalBytes) {
      throw const OutboxQuotaException(
        'Pending uploads reached the storage limit. Retry or discard one first.',
      );
    }
  }

  Future<void> _cleanupExpiredEntries(String userId) async {
    final root = await _userDirectory(userId);
    if (!await root.exists()) return;
    final now = _clock();
    await for (final group in root.list(followLinks: false)) {
      if (group is! Directory) continue;
      final groupId = _directoryName(group);
      await for (final entity in group.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final entry = await _recoverEntry(
          entity,
          userId: userId,
          groupId: groupId,
        );
        if (entry != null) {
          final expiresAt =
              entry.expiresAt ?? entry.createdAt.add(policy.retention);
          if (!expiresAt.isAfter(now)) {
            await entity.delete(recursive: true);
          }
          continue;
        }
        final modifiedAt = await _latestModifiedAt(entity);
        if (!modifiedAt.add(policy.retention).isAfter(now)) {
          await entity.delete(recursive: true);
        }
      }
    }
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
    final safeUserId = _safeId(userId);
    if (outboxRootProvider != null) {
      return outboxRootProvider!(safeUserId);
    }
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}message_outbox'
      '${Platform.pathSeparator}$safeUserId',
    );
  }

  String _safeId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value)) {
      throw ArgumentError('Invalid outbox identifier.');
    }
    return value;
  }

  String _directoryName(Directory directory) {
    return directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
  }

  Future<DateTime> _latestModifiedAt(Directory directory) async {
    DateTime? latest;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final modified = await entity.lastModified();
      if (latest == null || modified.isAfter(latest)) latest = modified;
    }
    return latest ?? (await directory.stat()).modified;
  }

  String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 180 ? text : '${text.substring(0, 177)}...';
  }
}

class _OutboxCandidate {
  final File file;
  final OutboxMessage entry;
  final bool isLegacy;
  final DateTime modifiedAt;

  const _OutboxCandidate({
    required this.file,
    required this.entry,
    required this.isLegacy,
    required this.modifiedAt,
  });
}
