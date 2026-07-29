import 'dart:async';
import 'dart:io';

import 'package:bsgc_app/services/firestore_commit_service.dart';
import 'package:bsgc_app/services/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'startup timeout becomes retryable instead of loading forever',
    () async {
      final never = Completer<void>();
      var attempts = 0;
      final controller = StartupController(
        timeout: const Duration(milliseconds: 20),
        initialize: () {
          attempts++;
          return attempts == 1 ? never.future : Future<void>.value();
        },
      );

      await controller.start();
      expect(controller.status, StartupStatus.failed);
      expect(controller.error, isA<TimeoutException>());

      await controller.retry();
      expect(controller.status, StartupStatus.ready);
      expect(attempts, 2);
    },
  );

  test(
    'Android explicitly excludes private app data from backup and transfer',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final backupRules = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      final extractionRules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(backupRules, contains('domain="root" path="."'));
      expect(extractionRules, contains('<cloud-backup>'));
      expect(extractionRules, contains('<device-transfer>'));
    },
  );

  test('session-only writes must not masquerade as remote saves', () async {
    await expectLater(
      waitForCommitAcknowledgement(
        const Stream<bool>.empty(),
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      waitForCommitAcknowledgement(
        Stream<bool>.fromIterable(const [true, false]),
      ),
      completes,
    );
  });
}
