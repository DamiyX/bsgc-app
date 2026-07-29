import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bsgc_app/models/message_model.dart';
import 'package:bsgc_app/services/message_outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryRoot;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('braid_outbox_test_');
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  MessageOutboxService service({
    OutboxPolicy policy = const OutboxPolicy(),
    DateTime Function()? clock,
    Future<void> Function(OutboxWriteStage stage)? writeHook,
  }) {
    return MessageOutboxService(
      policy: policy,
      clock: clock,
      writeHook: writeHook,
      outboxRootProvider: (userId) async =>
          Directory('${temporaryRoot.path}${Platform.pathSeparator}$userId'),
    );
  }

  test(
    'recovers the flushed temp file after a crash before replacement',
    () async {
      final stable = service();
      await stable.enqueue(
        id: 'message-1',
        userId: 'user-1',
        groupId: 'group-1',
        space: 'discussion',
        parts: [_textPart('original')],
      );
      final crashing = service(
        writeHook: (stage) async {
          if (stage == OutboxWriteStage.tempFlushed) {
            throw StateError('simulated process death');
          }
        },
      );

      await expectLater(
        crashing.enqueue(
          id: 'message-1',
          userId: 'user-1',
          groupId: 'group-1',
          space: 'discussion',
          parts: [_textPart('newest')],
        ),
        throwsStateError,
      );

      final recovered = await stable.list(userId: 'user-1', groupId: 'group-1');
      expect(recovered, hasLength(1));
      expect(recovered.single.parts.single.content, 'newest');
    },
  );

  test('recovers after a crash between backup and committed rename', () async {
    final stable = service();
    await stable.enqueue(
      id: 'message-1',
      userId: 'user-1',
      groupId: 'group-1',
      space: 'discussion',
      parts: [_textPart('original')],
    );
    final crashing = service(
      writeHook: (stage) async {
        if (stage == OutboxWriteStage.backupReady) {
          throw StateError('simulated process death');
        }
      },
    );

    await expectLater(
      crashing.enqueue(
        id: 'message-1',
        userId: 'user-1',
        groupId: 'group-1',
        space: 'discussion',
        parts: [_textPart('newest')],
      ),
      throwsStateError,
    );

    final recovered = await stable.list(userId: 'user-1', groupId: 'group-1');
    expect(recovered.single.parts.single.content, 'newest');
  });

  test(
    'surfaces corrupt metadata instead of silently returning empty',
    () async {
      final outbox = service();
      await outbox.enqueue(
        id: 'message-1',
        userId: 'user-1',
        groupId: 'group-1',
        space: 'discussion',
        parts: [_textPart('hello')],
      );
      final metadata = _metadataFile(
        temporaryRoot,
        userId: 'user-1',
        groupId: 'group-1',
        messageId: 'message-1',
      );
      final decoded = jsonDecode(await metadata.readAsString()) as Map;
      final payload = Map<String, dynamic>.from(decoded['payload'] as Map);
      payload['space'] = 'tampered';
      decoded['payload'] = payload;
      await metadata.writeAsString(jsonEncode(decoded), flush: true);

      final entries = await outbox.list(userId: 'user-1', groupId: 'group-1');

      expect(entries, hasLength(1));
      expect(entries.single.status, OutboxStatus.corrupt);
      expect(entries.single.retryable, isFalse);
    },
  );

  test('rejects valid metadata that belongs to another account', () {
    final entry = _entry(userId: 'user-2');
    final encoded = OutboxMessageCodec.encode(entry);

    expect(
      () => OutboxMessageCodec.decode(
        encoded,
        expectedUserId: 'user-1',
        expectedGroupId: 'group-1',
        expectedMessageId: 'message-1',
      ),
      throwsA(isA<OutboxDataException>()),
    );
    final unsupported = Map<String, dynamic>.from(encoded)
      ..['schemaVersion'] = 99;
    expect(
      () => OutboxMessageCodec.decode(
        unsupported,
        expectedUserId: 'user-2',
        expectedGroupId: 'group-1',
        expectedMessageId: 'message-1',
      ),
      throwsA(isA<OutboxDataException>()),
    );
  });

  test('enforces per-account item and byte quotas', () async {
    final itemLimited = service(policy: const OutboxPolicy(maxItems: 1));
    await itemLimited.enqueue(
      id: 'message-1',
      userId: 'user-1',
      groupId: 'group-1',
      space: 'discussion',
      parts: [_textPart('hello')],
    );

    await expectLater(
      itemLimited.enqueue(
        id: 'message-2',
        userId: 'user-1',
        groupId: 'group-1',
        space: 'discussion',
        parts: [_textPart('second')],
      ),
      throwsA(isA<OutboxQuotaException>()),
    );
    final byteLimited = service(policy: const OutboxPolicy(maxTotalBytes: 5));
    await expectLater(
      byteLimited.persistAttachment(
        userId: 'user-2',
        groupId: 'group-1',
        messageId: 'message-1',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        extension: 'jpg',
      ),
      throwsA(isA<OutboxQuotaException>()),
    );
  });

  test(
    'attachment-only drafts count toward quota and expire when orphaned',
    () async {
      var now = DateTime.utc(2026, 1, 1);
      final outbox = service(
        policy: const OutboxPolicy(maxItems: 1, retention: Duration(days: 2)),
        clock: () => now,
      );
      await outbox.persistAttachment(
        userId: 'user-1',
        groupId: 'group-1',
        messageId: 'message-1',
        bytes: Uint8List.fromList([1]),
        extension: 'jpg',
      );
      final firstEntryDirectory = _metadataFile(
        temporaryRoot,
        userId: 'user-1',
        groupId: 'group-1',
        messageId: 'message-1',
      ).parent;
      for (final entity in firstEntryDirectory.listSync()) {
        if (entity is File) await entity.setLastModified(now);
      }

      await expectLater(
        outbox.persistAttachment(
          userId: 'user-1',
          groupId: 'group-1',
          messageId: 'message-2',
          bytes: Uint8List.fromList([2]),
          extension: 'jpg',
        ),
        throwsA(isA<OutboxQuotaException>()),
      );

      now = now.add(const Duration(days: 3));
      await outbox.persistAttachment(
        userId: 'user-1',
        groupId: 'group-1',
        messageId: 'message-2',
        bytes: Uint8List.fromList([2]),
        extension: 'jpg',
      );
      expect(await firstEntryDirectory.exists(), isFalse);
    },
  );

  test('expires old entries and removes their attachment directory', () async {
    var now = DateTime.utc(2026, 1, 1);
    final outbox = service(
      policy: const OutboxPolicy(retention: Duration(days: 2)),
      clock: () => now,
    );
    await outbox.enqueue(
      id: 'message-1',
      userId: 'user-1',
      groupId: 'group-1',
      space: 'discussion',
      parts: [_textPart('hello')],
    );
    final entryDirectory = _metadataFile(
      temporaryRoot,
      userId: 'user-1',
      groupId: 'group-1',
      messageId: 'message-1',
    ).parent;
    now = now.add(const Duration(days: 3));

    final entries = await outbox.list(userId: 'user-1', groupId: 'group-1');

    expect(entries, isEmpty);
    expect(await entryDirectory.exists(), isFalse);
  });

  test(
    'failed attempts use bounded exponential backoff and manual override',
    () {
      final entry = _entry();
      final policy = const OutboxPolicy(
        maxAutomaticAttempts: 3,
        initialRetryDelay: Duration(seconds: 10),
        maxRetryDelay: Duration(seconds: 30),
      );
      final firstFailure = entry
          .beginAttempt(DateTime.utc(2026, 1, 1))
          .failAttempt(
            now: DateTime.utc(2026, 1, 1),
            safeError: 'offline',
            policy: policy,
          );
      final thirdFailure = firstFailure
          .beginAttempt(DateTime.utc(2026, 1, 1, 0, 0, 10))
          .failAttempt(
            now: DateTime.utc(2026, 1, 1, 0, 0, 10),
            safeError: 'offline',
            policy: policy,
          )
          .beginAttempt(DateTime.utc(2026, 1, 1, 0, 0, 30))
          .failAttempt(
            now: DateTime.utc(2026, 1, 1, 0, 0, 30),
            safeError: 'offline',
            policy: policy,
          );

      expect(firstFailure.nextRetryAt, DateTime.utc(2026, 1, 1, 0, 0, 10));
      expect(
        firstFailure.canAttempt(
          manual: false,
          now: DateTime.utc(2026, 1, 1, 0, 0, 9),
        ),
        isFalse,
      );
      expect(
        firstFailure.canAttempt(
          manual: false,
          now: DateTime.utc(2026, 1, 1, 0, 0, 10),
        ),
        isTrue,
      );
      expect(thirdFailure.automaticRetryAvailable, isFalse);
      expect(
        thirdFailure.canAttempt(manual: true, now: DateTime.utc(2026)),
        isTrue,
      );
    },
  );

  test('missing attachment becomes visible and non-retryable', () async {
    final outbox = service();
    final missingFile = File(
      '${temporaryRoot.path}${Platform.pathSeparator}missing.jpg',
    );
    await outbox.enqueue(
      id: 'message-1',
      userId: 'user-1',
      groupId: 'group-1',
      space: 'discussion',
      parts: [
        MessagePart(
          type: MessageType.image,
          content: missingFile.uri.toString(),
        ),
      ],
    );

    final entries = await outbox.list(userId: 'user-1', groupId: 'group-1');

    expect(entries.single.status, OutboxStatus.failed);
    expect(entries.single.retryable, isFalse);
    expect(entries.single.lastError, contains('no longer available'));
  });

  test('corrupt entries remain manually discardable', () async {
    final outbox = service();
    await outbox.enqueue(
      id: 'message-1',
      userId: 'user-1',
      groupId: 'group-1',
      space: 'discussion',
      parts: [_textPart('hello')],
    );
    final metadata = _metadataFile(
      temporaryRoot,
      userId: 'user-1',
      groupId: 'group-1',
      messageId: 'message-1',
    );
    await metadata.writeAsString('{broken', flush: true);
    final corrupt = (await outbox.list(
      userId: 'user-1',
      groupId: 'group-1',
    )).single;

    await outbox.remove(corrupt);

    expect(await metadata.parent.exists(), isFalse);
  });
}

MessagePart _textPart(String content) =>
    MessagePart(type: MessageType.text, content: content);

OutboxMessage _entry({String userId = 'user-1'}) {
  return OutboxMessage(
    id: 'message-1',
    userId: userId,
    groupId: 'group-1',
    space: 'discussion',
    parts: [_textPart('hello')],
    createdAt: DateTime.utc(2026, 1, 1),
    expiresAt: DateTime.utc(2026, 2, 1),
  );
}

File _metadataFile(
  Directory root, {
  required String userId,
  required String groupId,
  required String messageId,
}) {
  return File(
    '${root.path}${Platform.pathSeparator}$userId'
    '${Platform.pathSeparator}$groupId'
    '${Platform.pathSeparator}$messageId'
    '${Platform.pathSeparator}message.json',
  );
}
