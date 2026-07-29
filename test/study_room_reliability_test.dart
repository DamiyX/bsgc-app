import 'dart:async';

import 'package:bsgc_app/controllers/study_room_controller.dart';
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
