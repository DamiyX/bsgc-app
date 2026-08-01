import 'dart:async';

import 'package:bsgc_app/controllers/study_room_controller.dart';
import 'package:bsgc_app/models/group_model.dart';
import 'package:bsgc_app/models/message_model.dart';
import 'package:bsgc_app/screens/study_room_screen.dart';
import 'package:bsgc_app/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Study Room personal visibility', () {
    final clearedBefore = DateTime.utc(2026, 7, 29, 12);
    final state = MessageVisibilityState(
      hiddenMessageIds: const {'hidden-message'},
      clearedBefore: clearedBefore,
    );

    test('hides persisted hidden IDs and messages at the clear cutoff', () {
      expect(
        state.allows(
          _message(
            id: 'hidden-message',
            timestamp: clearedBefore.add(const Duration(minutes: 1)),
          ),
          userId: 'reader',
        ),
        isFalse,
      );
      expect(
        state.allows(
          _message(id: 'before-clear', timestamp: clearedBefore),
          userId: 'reader',
        ),
        isFalse,
      );
    });

    test('keeps messages created after clear visible', () {
      expect(
        state.allows(
          _message(
            id: 'after-clear',
            timestamp: clearedBefore.add(const Duration(milliseconds: 1)),
          ),
          userId: 'reader',
        ),
        isTrue,
      );
    });

    test('retains legacy deletedFor read compatibility', () {
      expect(
        state.allows(
          _message(
            id: 'legacy-hidden',
            timestamp: clearedBefore.add(const Duration(minutes: 1)),
            deletedFor: const ['reader'],
          ),
          userId: 'reader',
        ),
        isFalse,
      );
    });
  });

  test(
    'GroupMessagePager constrains every page to its message space',
    () async {
      for (final space in StudyRoomController.messageSpaces) {
        final pageSource = _RecordingMessagePageSource();
        final pager = GroupMessagePager.fromSource(
          pageSource,
          groupId: 'group-1',
          space: space,
        );
        final subscription = pager.stream.listen((_) {});
        addTearDown(subscription.cancel);
        addTearDown(pager.dispose);

        await Future<void>.delayed(Duration.zero);

        expect(pageSource.latestSpaces, [space]);

        await pager.loadOlder();
        expect(pageSource.olderSpaces, [space]);
      }
    },
  );

  test('controller defines one independent pager scope per chat space', () {
    expect(StudyRoomController.messageSpaces, {
      'reflection',
      'discussion',
      'prayer',
    });
    expect(StudySpace.values.map((space) => space.name), [
      'plan',
      'reflection',
      'discussion',
      'prayer',
    ]);
  });

  test('message pager rejects non-chat spaces', () {
    expect(
      () => GroupMessagePager.fromSource(
        _RecordingMessagePageSource(),
        groupId: 'group-1',
        space: 'plan',
      ),
      throwsArgumentError,
    );
  });

  test(
    'active room read reconciliation repeats after an in-flight update',
    () async {
      final firstAcknowledgement = Completer<void>();
      var acknowledgements = 0;
      final reconciler = ActiveRoomReadReconciler(() {
        acknowledgements++;
        if (acknowledgements == 1) return firstAcknowledgement.future;
        return Future<void>.value();
      });

      final first = reconciler.reconcile();
      final second = reconciler.reconcile();
      expect(acknowledgements, 1);

      firstAcknowledgement.complete();
      await Future.wait([first, second]);

      expect(acknowledgements, 2);
    },
  );

  test('personal room state writes wait for server acknowledgement', () async {
    final acknowledgement = Completer<void>();
    var writes = 0;
    var completed = false;
    final mutation = persistAcknowledgedChatStateWrite(
      write: () async {
        writes++;
      },
      awaitAcknowledgement: () => acknowledgement.future,
    );
    unawaited(mutation.then((_) => completed = true));

    await Future<void>.delayed(Duration.zero);
    expect(writes, 1);
    expect(completed, isFalse);

    acknowledgement.complete();
    await mutation;
    expect(completed, isTrue);
  });

  test(
    'room read reconciliation pauses while the room is not visible',
    () async {
      var acknowledgements = 0;
      final reconciler = ActiveRoomReadReconciler(() async {
        acknowledgements++;
      });

      reconciler.setActive(false);
      await reconciler.reconcile();
      expect(acknowledgements, 0);

      await reconciler.setActive(true);
      expect(acknowledgements, 1);
    },
  );

  test('draft reply keeps its ID until the parent message arrives', () {
    final reference = DraftReplyReference.restore(
      'parent-message',
      const <MessageModel>[],
    );

    expect(reference.messageId, 'parent-message');
    expect(reference.message, isNull);

    final resolved = reference.reconcile([
      _message(id: 'parent-message', timestamp: DateTime.utc(2026, 7, 29, 12)),
    ]);

    expect(resolved.messageId, 'parent-message');
    expect(resolved.message?.id, 'parent-message');
  });

  test('chapter mutation merges each toggle into the latest server state', () {
    expect(
      ChapterProgressMutation.toggle(
        current: const [1, 2],
        chapter: 3,
        totalChapters: 4,
      ),
      const ChapterProgressMutation(
        completedChapters: [1, 2, 3],
        progress: 0.75,
      ),
    );
    expect(
      ChapterProgressMutation.toggle(
        current: const [1, 2, 3],
        chapter: 2,
        totalChapters: 4,
      ),
      const ChapterProgressMutation(completedChapters: [1, 3], progress: 0.5),
    );
  });

  test('study date contract rejects same-day and over-365-day ranges', () {
    final start = DateTime(2026, 8, 1);

    expect(
      StudyDateRangePolicy.validationMessage(start, start),
      'Choose an end date after the start date.',
    );
    expect(
      StudyDateRangePolicy.validationMessage(
        start,
        start.add(const Duration(days: 366)),
      ),
      'A study can run for at most 365 days.',
    );
    expect(
      StudyDateRangePolicy.validationMessage(
        start,
        start.add(const Duration(days: 365)),
      ),
      isNull,
    );
  });

  test('study date duration uses calendar days across clock changes', () {
    final start = DateTime(2026, 3, 28, 23, 30);
    final end = DateTime(2026, 3, 29, 0, 15);

    expect(StudyDateRangePolicy.calendarDateKey(start), '2026-03-28');
    expect(StudyDateRangePolicy.calendarDateKey(end), '2026-03-29');
    expect(StudyDateRangePolicy.calendarDurationDays(start, end), 1);
    expect(StudyDateRangePolicy.validationMessage(start, end), isNull);
  });

  test('server date reasons map to stable field-level copy', () {
    expect(
      StudyDateRangePolicy.messageForReason('missing'),
      'Select both a start and an end date.',
    );
    expect(
      StudyDateRangePolicy.messageForReason('end-before-or-same-day'),
      'Choose an end date after the start date.',
    );
    expect(
      StudyDateRangePolicy.messageForReason('too-long'),
      'A study can run for at most 365 days.',
    );
  });

  test('group operation failures expose stable product copy', () {
    expect(
      groupOperationFailureForCode('unavailable').message,
      'Check your connection and try again.',
    );
    expect(
      groupOperationFailureForCode('invalid-argument').message,
      'Check the study details and try again.',
    );
    expect(
      groupOperationFailureForCode('internal').message,
      'The study could not be saved right now. Try again.',
    );
  });

  test('date validation details remain field-scoped and stable', () {
    final failure = groupOperationFailureForCode(
      'invalid-argument',
      details: const {
        'field': 'dateRange',
        'reason': 'too-long',
        'message': 'raw server detail should not render',
      },
    );

    expect(failure.field, 'dateRange');
    expect(failure.message, 'A study can run for at most 365 days.');
    expect(failure.message, isNot(contains('raw server detail')));
  });

  test('pending and unknown message timestamps remain stable', () {
    final clientCreatedAt = DateTime.utc(2026, 7, 29, 12, 30);
    final pending = resolveMessageTimestamp(
      serverTimestamp: null,
      clientCreatedAt: clientCreatedAt,
    );
    final unknown = resolveMessageTimestamp(
      serverTimestamp: null,
      clientCreatedAt: null,
    );

    expect(pending.value, clientCreatedAt);
    expect(pending.isKnown, isTrue);
    expect(unknown.value, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(unknown.isKnown, isFalse);
  });

  test('message pager retry creates a new live subscription', () async {
    final pageSource = _RetryableMessagePageSource();
    final pager = GroupMessagePager.fromSource(
      pageSource,
      groupId: 'group-1',
      space: 'discussion',
    );
    final errors = <Object>[];
    final subscription = pager.stream.listen((_) {}, onError: errors.add);
    addTearDown(subscription.cancel);
    addTearDown(pager.dispose);
    await Future<void>.delayed(Duration.zero);

    pageSource.failCurrent(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));

    await pager.retry();

    expect(pageSource.watchCount, 2);
  });

  test('main group retry replaces the failed stream', () {
    var subscriptions = 0;
    final retry = GroupStreamRetryController(() {
      subscriptions++;
      return Stream<List<GroupModel>>.value(const []);
    });
    final first = retry.stream;

    retry.retry();

    expect(subscriptions, 2);
    expect(retry.stream, isNot(same(first)));
  });
}

MessageModel _message({
  required String id,
  required DateTime timestamp,
  List<String> deletedFor = const [],
}) {
  return MessageModel(
    id: id,
    senderId: 'author',
    senderName: 'Author',
    parts: [MessagePart(type: MessageType.text, content: id)],
    timestamp: timestamp,
    deletedFor: deletedFor,
  );
}

class _RecordingMessagePageSource implements GroupMessagePageSource {
  final List<String> latestSpaces = [];
  final List<String> olderSpaces = [];

  @override
  Stream<GroupMessagePage> watchLatest({
    required String groupId,
    required String space,
    required int pageSize,
  }) {
    latestSpaces.add(space);
    return const Stream.empty();
  }

  @override
  Future<GroupMessagePage> loadOlder({
    required String groupId,
    required String space,
    required int pageSize,
    required Object? cursor,
  }) async {
    olderSpaces.add(space);
    return const GroupMessagePage(
      items: [],
      oldestCursor: null,
      hasMore: false,
    );
  }
}

class _RetryableMessagePageSource implements GroupMessagePageSource {
  final List<StreamController<GroupMessagePage>> _controllers = [];

  int get watchCount => _controllers.length;

  void failCurrent(Object error) => _controllers.last.addError(error);

  @override
  Stream<GroupMessagePage> watchLatest({
    required String groupId,
    required String space,
    required int pageSize,
  }) {
    final controller = StreamController<GroupMessagePage>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<GroupMessagePage> loadOlder({
    required String groupId,
    required String space,
    required int pageSize,
    required Object? cursor,
  }) async {
    return const GroupMessagePage(
      items: [],
      oldestCursor: null,
      hasMore: false,
    );
  }
}
