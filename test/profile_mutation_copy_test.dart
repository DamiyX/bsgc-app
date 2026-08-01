import 'dart:async';

import 'package:bsgc_app/screens/edit_profile_screen.dart';
import 'package:bsgc_app/services/firestore_commit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile mutations use explicit queued and retry copy when offline', () {
    expect(profilePicturePendingMessage, contains('queued locally'));
    expect(profilePicturePendingMessage, contains('retry'));
    expect(profileChangesPendingMessage, contains('queued locally'));
    expect(profileChangesPendingMessage, contains('retry'));
  });

  test(
    'commit acknowledgement completes only after pending writes clear',
    () async {
      await waitForCommitAcknowledgement(
        Stream.fromIterable([true, false]),
        timeout: const Duration(milliseconds: 100),
      );
    },
  );

  test(
    'commit acknowledgement times out while a write stays pending',
    () async {
      await expectLater(
        waitForCommitAcknowledgement(
          Stream.value(true),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
