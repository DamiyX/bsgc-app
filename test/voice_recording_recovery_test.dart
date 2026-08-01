import 'dart:io';
import 'dart:typed_data';

import 'package:bsgc_app/models/message_model.dart';
import 'package:bsgc_app/services/audio_service.dart';
import 'package:bsgc_app/services/draft_service.dart';
import 'package:bsgc_app/services/message_outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('braid_voice_recovery_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('keeps the active temporary path when stop returns no path', () {
    expect(
      resolveRecordingPath(null, '/tmp/recording.m4a'),
      '/tmp/recording.m4a',
    );
    expect(
      resolveRecordingPath('/tmp/stopped.m4a', '/tmp/active.m4a'),
      '/tmp/stopped.m4a',
    );
  });

  MessageOutboxService outbox() {
    return MessageOutboxService(
      outboxRootProvider: (userId) async =>
          Directory('${root.path}${Platform.pathSeparator}outbox-$userId'),
    );
  }

  DraftService drafts() {
    return DraftService(
      draftRootProvider: (userId) async =>
          Directory('${root.path}${Platform.pathSeparator}drafts-$userId'),
    );
  }

  test(
    'moves a stopped recording into the scoped outbox and can discard it',
    () async {
      final source = File('${root.path}${Platform.pathSeparator}temporary.m4a');
      await source.writeAsBytes(Uint8List.fromList([1, 2, 3]), flush: true);
      final service = outbox();

      final uri = await service.persistAttachmentFile(
        userId: 'user-1',
        groupId: 'group-1',
        messageId: 'message-1',
        source: source,
        extension: 'm4a',
      );
      final persisted = File.fromUri(Uri.parse(uri));

      expect(await source.exists(), isFalse);
      expect(await persisted.exists(), isTrue);

      await service.removeAttachment(
        userId: 'user-1',
        groupId: 'group-1',
        uri: uri,
      );
      expect(await persisted.exists(), isFalse);
    },
  );

  test('the moved voice part survives a draft reload', () async {
    final source = File('${root.path}${Platform.pathSeparator}temporary.m4a');
    await source.writeAsBytes(Uint8List.fromList([4, 5, 6]), flush: true);
    final uri = await outbox().persistAttachmentFile(
      userId: 'user-1',
      groupId: 'group-1',
      messageId: 'message-1',
      source: source,
      extension: 'm4a',
    );
    final draftService = drafts();

    await draftService.save(
      userId: 'user-1',
      groupId: 'group-1',
      draft: GroupDraft(
        text: 'before the recording',
        parts: [
          MessagePart(
            type: MessageType.voice,
            content: uri,
            durationSeconds: 4,
          ),
        ],
        clientMessageId: 'message-1',
      ),
    );

    final restored = await draftService.load(
      userId: 'user-1',
      groupId: 'group-1',
    );
    expect(restored?.parts.single.type, MessageType.voice);
    expect(restored?.parts.single.content, uri);
    expect(await File.fromUri(Uri.parse(uri)).exists(), isTrue);
  });

  test('attachment deletion cannot cross the requested group scope', () async {
    final source = File('${root.path}${Platform.pathSeparator}temporary.m4a');
    await source.writeAsBytes(Uint8List.fromList([7]), flush: true);
    final service = outbox();
    final uri = await service.persistAttachmentFile(
      userId: 'user-1',
      groupId: 'group-1',
      messageId: 'message-1',
      source: source,
      extension: 'm4a',
    );

    await expectLater(
      service.removeAttachment(userId: 'user-1', groupId: 'group-2', uri: uri),
      throwsArgumentError,
    );
    expect(await File.fromUri(Uri.parse(uri)).exists(), isTrue);
  });

  test(
    'a missing recording fails without claiming that it was saved',
    () async {
      final missing = File('${root.path}${Platform.pathSeparator}missing.m4a');

      await expectLater(
        outbox().persistAttachmentFile(
          userId: 'user-1',
          groupId: 'group-1',
          messageId: 'message-1',
          source: missing,
          extension: 'm4a',
        ),
        throwsStateError,
      );
      expect(voiceRecordingDiscardedMessage, isNot(contains('saved locally')));
      expect(voiceRecordingDiscardedMessage, contains('Record again'));
    },
  );
}
