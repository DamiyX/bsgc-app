import 'package:bsgc_app/services/deletion_semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reflection removal copy describes the status/tombstone boundary', () {
    expect(insightDeletionDialogTitle, 'Remove reflection?');
    expect(insightDeletionDialogBody, contains('deletion status'));
    expect(insightDeletionDialogBody, contains('retention policy'));
    expect(insightDeletionDialogBody, contains('Saved bookmarks'));
    expect(insightDeletionSuccessMessage, 'Reflection no longer shared.');
  });

  test(
    'account and message copy distinguishes cleanup from retained records',
    () {
      expect(accountDeletionDialogBody, contains('disabled first'));
      expect(accountDeletionDialogBody, contains('deleted-account tombstone'));
      expect(accountDeletionDialogBody, contains('retention policy'));
      expect(accountDeletionSubtitle, contains('safety records may remain'));
      expect(
        messageRemovedForEveryoneLabel,
        contains('Some safety metadata may be retained'),
      );
      expect(savedInsightRemovalLabel, 'Remove bookmark');
    },
  );
}
