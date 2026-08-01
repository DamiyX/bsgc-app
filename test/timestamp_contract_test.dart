import 'package:bsgc_app/models/group_model.dart';
import 'package:bsgc_app/models/insight_model.dart';
import 'package:bsgc_app/models/message_model.dart';
import 'package:bsgc_app/models/note_model.dart';
import 'package:bsgc_app/models/timestamp_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown timestamps resolve to one stable epoch and are marked', () {
    final first = resolveFirestoreTimestamp(null);
    final second = resolveFirestoreTimestamp('not-a-timestamp');

    expect(first.value, stableTimestampEpoch);
    expect(second.value, stableTimestampEpoch);
    expect(first.isKnown, isFalse);
    expect(second.isKnown, isFalse);
  });

  test('note compatibility reader never moves missing history to now', () {
    final note = NoteModel.fromMap('legacy-note', {
      'authorUid': 'author',
      'title': 'Legacy note',
      'body': 'Body',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
    });

    expect(note.createdAt.toUtc(), DateTime.utc(2026, 1, 2));
    expect(note.updatedAt, note.createdAt);
    expect(note.hasKnownCreatedAt, isTrue);
    expect(note.hasKnownUpdatedAt, isFalse);
  });

  test('Insight and comment compatibility readers expose malformed state', () {
    final insight = InsightModel.fromMap('legacy-insight', {
      'authorUid': 'author',
      'authorName': 'Author',
      'title': 'Legacy reflection',
      'body': 'Body',
    });
    final comment = InsightCommentModel.fromMap('legacy-comment', const {
      'insightId': 'legacy-insight',
      'authorUid': 'author',
      'body': 'Legacy comment',
    });

    expect(insight.createdAt, stableTimestampEpoch);
    expect(insight.updatedAt, stableTimestampEpoch);
    expect(
      insight.expiresAt,
      stableTimestampEpoch.add(const Duration(days: 3)),
    );
    expect(insight.hasKnownCreatedAt, isFalse);
    expect(insight.hasKnownUpdatedAt, isFalse);
    expect(insight.hasKnownExpiresAt, isFalse);
    expect(comment.createdAt, stableTimestampEpoch);
    expect(comment.hasKnownCreatedAt, isFalse);
  });

  test(
    'group and message compatibility order unknown records at the epoch',
    () {
      final group = GroupModel.fromMap('legacy-group', {
        'name': 'Legacy group',
        'members': <String>['author'],
      });
      final unknownMessage = resolveMessageTimestamp(
        serverTimestamp: null,
        clientCreatedAt: null,
      );
      final clientMessage = resolveMessageTimestamp(
        serverTimestamp: null,
        clientCreatedAt: Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
      );

      expect(group.createdAt, stableTimestampEpoch);
      expect(group.hasKnownCreatedAt, isFalse);
      expect(unknownMessage.value, stableTimestampEpoch);
      expect(unknownMessage.isKnown, isFalse);
      expect(clientMessage.value.toUtc(), DateTime.utc(2026, 1, 3));
      expect(clientMessage.isKnown, isTrue);
    },
  );
}
