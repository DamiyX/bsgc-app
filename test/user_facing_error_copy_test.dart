import 'package:bsgc_app/services/account_service.dart';
import 'package:bsgc_app/services/chat_service.dart';
import 'package:bsgc_app/services/user_facing_error_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('account deletion error copy', () {
    test('maps typed backend codes to actionable, stable copy', () {
      expect(
        accountDeletionErrorCopy(
          const AccountDeletionException(
            'INTERNAL: raw callable detail',
            code: 'unavailable',
          ),
        ),
        'We could not submit the deletion request. Check your connection and try again.',
      );
      expect(
        accountDeletionErrorCopy(
          const AccountDeletionException(
            'permission denied at /users_private',
            code: 'permission-denied',
          ),
        ),
        'Your account cannot be deleted from this session. Sign in again and try.',
      );
    });

    test('does not expose an unknown exception message', () {
      const raw = 'FirebaseError: users_private/abc internal stack detail';
      final copy = accountDeletionErrorCopy(StateError(raw));

      expect(copy, isNot(contains(raw)));
      expect(
        copy,
        'We could not submit the account deletion request. Please try again.',
      );
    });
  });

  group('group invitation error copy', () {
    test('maps invite backend codes without rendering server text', () {
      expect(
        groupInviteErrorCopy(
          const ChatServiceException(
            code: 'resource-exhausted',
            message: 'group members length = 500; firestore path ...',
          ),
        ),
        'This study cannot accept more members right now. Try again later.',
      );
      expect(
        groupInviteErrorCopy(
          const ChatServiceException(
            code: 'permission-denied',
            message: 'PERMISSION_DENIED: groups/secret',
          ),
        ),
        'Only a study owner can create an invitation for this group.',
      );
    });

    test('uses a safe retry message for unknown failures', () {
      const raw = 'PlatformException(firebase_firestore, socket 10.0.0.1)';
      final copy = groupInviteErrorCopy(Exception(raw));

      expect(copy, isNot(contains(raw)));
      expect(copy, 'We could not create the invitation. Please try again.');
    });
  });
}
