import 'dart:async';

import 'package:bsgc_app/screens/settings_screen.dart';
import 'package:bsgc_app/services/draft_service.dart';
import 'package:bsgc_app/services/insight_action_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sound preference persistence reports storage failures', () async {
    final persisted = await persistMuteAppSoundsPreference(
      true,
      loadPreferences: () async => throw StateError('storage unavailable'),
    );

    expect(persisted, isFalse);
  });

  test(
    'draft cleanup wrappers preserve a durable mutation on local failure',
    () async {
      final draftService = _FailingDraftService();

      expect(
        await tryClearComposerDraft(
          draftService: draftService,
          userId: 'user-1',
          audience: ComposerDraftAudience.private,
        ),
        isFalse,
      );
      expect(
        await tryClearGroupDraft(
          draftService: draftService,
          userId: 'user-1',
          groupId: 'group-1',
        ),
        isFalse,
      );
    },
  );

  test(
    'study notification mute stays pending, blocks repeats, and rolls back',
    () async {
      final acknowledgement = Completer<void>();
      final mute = ReversibleToggleController(initialValue: false);

      final save = mute.setValue(true, (_) => acknowledgement.future);

      expect(mute.value, isTrue);
      expect(mute.isPending, isTrue);
      expect(
        await mute.setValue(false, (_) async {}),
        isFalse,
        reason: 'A second toggle must not race the pending server write.',
      );

      acknowledgement.completeError(StateError('offline'));
      expect(await save, isFalse);
      expect(mute.value, isFalse);
      expect(mute.isPending, isFalse);
      expect(mute.lastError, isNotNull);
    },
  );

  test(
    'study notification mute remains changed after acknowledgement',
    () async {
      final mute = ReversibleToggleController(initialValue: false);

      expect(await mute.setValue(true, (_) async {}), isTrue);
      expect(mute.value, isTrue);
      expect(mute.isPending, isFalse);
      expect(mute.lastError, isNull);
    },
  );
}

class _FailingDraftService extends DraftService {
  @override
  Future<void> clearComposerDraft({
    required String userId,
    required ComposerDraftAudience audience,
  }) async {
    throw StateError('draft storage unavailable');
  }

  @override
  Future<void> clear({required String userId, required String groupId}) async {
    throw StateError('draft storage unavailable');
  }
}
