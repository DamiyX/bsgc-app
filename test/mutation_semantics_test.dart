import 'package:bsgc_app/screens/settings_screen.dart';
import 'package:bsgc_app/services/draft_service.dart';
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
