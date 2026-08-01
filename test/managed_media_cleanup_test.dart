import 'package:bsgc_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed reference does not run cleanup', () async {
    var cleanupCalls = 0;

    await StorageService.commitReferenceOrCleanup(
      commit: () async {},
      cleanup: () async {
        cleanupCalls++;
      },
      shouldCleanup: (_) => true,
    );

    expect(cleanupCalls, 0);
  });

  test(
    'definitive reference failure cleans the new asset and rethrows',
    () async {
      var cleanupCalls = 0;
      final failure = StateError('permission denied');

      await expectLater(
        StorageService.commitReferenceOrCleanup(
          commit: () async => throw failure,
          cleanup: () async {
            cleanupCalls++;
          },
          shouldCleanup: (_) => true,
        ),
        throwsA(same(failure)),
      );

      expect(cleanupCalls, 1);
    },
  );

  test(
    'ambiguous reference failure leaves cleanup to reconciliation',
    () async {
      var cleanupCalls = 0;
      final failure = StateError('request lost after commit');

      await expectLater(
        StorageService.commitReferenceOrCleanup(
          commit: () async => throw failure,
          cleanup: () async {
            cleanupCalls++;
          },
          shouldCleanup: (_) =>
              StorageService.shouldCleanupAfterReferenceFailure('unavailable'),
        ),
        throwsA(same(failure)),
      );

      expect(cleanupCalls, 0);
    },
  );

  test(
    'reference failure policy is fail-closed for known definitive errors',
    () {
      expect(
        StorageService.shouldCleanupAfterReferenceFailure('permission-denied'),
        isTrue,
      );
      expect(
        StorageService.shouldCleanupAfterReferenceFailure(
          'failed-precondition',
        ),
        isTrue,
      );
      expect(
        StorageService.shouldCleanupAfterReferenceFailure('unavailable'),
        isFalse,
      );
      expect(
        StorageService.shouldCleanupAfterReferenceFailure('deadline-exceeded'),
        isFalse,
      );
    },
  );

  test(
    'asset discard rejects paths outside the caller scope before deletion',
    () async {
      await expectLater(
        StorageService.deleteUncommittedAsset(
          storagePath: 'groups/other-group/covers/cover.jpg',
          ownerId: 'owner',
          groupId: 'group-a',
        ),
        throwsArgumentError,
      );
      await expectLater(
        StorageService.deleteUncommittedAsset(
          storagePath: 'https://tracker.example/pixel.jpg',
          ownerId: 'owner',
        ),
        throwsArgumentError,
      );
      await expectLater(
        StorageService.deleteUncommittedAsset(
          storagePath: 'groups/group-a/covers/../other.jpg',
          ownerId: 'owner',
          groupId: 'group-a',
        ),
        throwsArgumentError,
      );
    },
  );
}
