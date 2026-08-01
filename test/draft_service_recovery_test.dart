import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bsgc_app/services/draft_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('braid-draft-recovery-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DraftService service({DraftWriteHook? writeHook}) {
    return DraftService(
      writeHook: writeHook,
      draftRootProvider: (userId) async =>
          Directory('${root.path}${Platform.pathSeparator}$userId'),
    );
  }

  File draftFile(String userId, String groupId) {
    return File(
      '${root.path}${Platform.pathSeparator}$userId'
      '${Platform.pathSeparator}$groupId.json',
    );
  }

  Map<String, dynamic> encodedGroup(String text, String updatedAt) => {
    'schemaVersion': 1,
    'text': text,
    'parts': const [],
    'space': 'discussion',
    'updatedAt': updatedAt,
  };

  test('restores a valid temporary draft after an interrupted write', () async {
    final file = draftFile('account-a', 'group-a');
    await file.parent.create(recursive: true);
    await File('${file.path}.tmp').writeAsString(
      jsonEncode(encodedGroup('from temporary', '2026-08-01T10:00:00Z')),
      flush: true,
    );

    final restored = await service().load(
      userId: 'account-a',
      groupId: 'group-a',
    );

    expect(restored?.text, 'from temporary');
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('falls back to a valid backup when the live and temp files are torn',
      () async {
    final file = draftFile('account-a', 'group-a');
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken', flush: true);
    await File('${file.path}.tmp').writeAsString('{also broken', flush: true);
    await File('${file.path}.bak').writeAsString(
      jsonEncode(encodedGroup('from backup', '2026-08-01T09:00:00Z')),
      flush: true,
    );

    final restored = await service().load(
      userId: 'account-a',
      groupId: 'group-a',
    );

    expect(restored?.text, 'from backup');
    expect(jsonDecode(await file.readAsString()), isA<Map>());
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect(await File('${file.path}.bak').exists(), isFalse);
  });

  test('serializes writes to one account root', () async {
    final firstFlushed = Completer<void>();
    final releaseFirst = Completer<void>();
    var flushCount = 0;
    final drafts = service(
      writeHook: (stage) async {
        if (stage != DraftWriteStage.tempFlushed || flushCount++ != 0) {
          return;
        }
        firstFlushed.complete();
        await releaseFirst.future;
      },
    );

    var secondFinished = false;
    final first = drafts.save(
      userId: 'account-a',
      groupId: 'group-a',
      draft: const GroupDraft(text: 'first', parts: []),
    );
    await firstFlushed.future;
    final second = drafts
        .save(
          userId: 'account-a',
          groupId: 'group-a',
          draft: const GroupDraft(text: 'second', parts: []),
        )
        .then((_) => secondFinished = true);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(secondFinished, isFalse);
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(
      (await drafts.load(userId: 'account-a', groupId: 'group-a'))?.text,
      'second',
    );
  });

  test('atomic write interruption leaves a valid recovery candidate', () async {
    final stable = service();
    await stable.save(
      userId: 'account-a',
      groupId: 'group-a',
      draft: const GroupDraft(text: 'old', parts: []),
    );
    final interrupted = service(
      writeHook: (stage) async {
        if (stage == DraftWriteStage.backupReady) {
          throw StateError('simulated draft process death');
        }
      },
    );

    await expectLater(
      interrupted.save(
        userId: 'account-a',
        groupId: 'group-a',
        draft: const GroupDraft(text: 'new', parts: []),
      ),
      throwsStateError,
    );
    expect(
      (await stable.load(userId: 'account-a', groupId: 'group-a'))?.text,
      'new',
    );
  });

  test('rejects unsafe account and group path components', () async {
    final drafts = service();
    await expectLater(
      drafts.load(userId: '../outside', groupId: 'group-a'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      drafts.save(
        userId: 'account-a',
        groupId: 'group/a',
        draft: const GroupDraft(text: 'blocked', parts: []),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      drafts.clearAllForUser('account-a/other'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
