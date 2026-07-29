import 'package:bsgc_app/services/media_reference_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts only canonical managed profile and group paths', () {
    expect(
      isCanonicalProfilePhotoPath('users/alice/profile/avatar.jpg', 'alice'),
      isTrue,
    );
    expect(
      isCanonicalProfilePhotoPath('users/bob/profile/avatar.jpg', 'alice'),
      isFalse,
    );
    expect(
      isCanonicalGroupCoverPath('groups/group-a/covers/cover.jpg', 'group-a'),
      isTrue,
    );
    expect(
      isCanonicalGroupCoverPath('groups/group-b/covers/cover.jpg', 'group-a'),
      isFalse,
    );
  });

  test('allows narrow profile bootstrap hosts and rejects tracking URLs', () {
    expect(
      isAllowedLegacyProfileUrl(
        'https://lh3.googleusercontent.com/a/example',
        'alice',
      ),
      isTrue,
    );
    expect(
      isAllowedLegacyProfileUrl(
        'https://firebasestorage.googleapis.com/v0/b/bsgc-app.firebasestorage.app/o/users%2Falice%2Fprofile%2Favatar.jpg?alt=media',
        'alice',
      ),
      isTrue,
    );
    expect(
      isAllowedLegacyProfileUrl('https://tracker.example/pixel.jpg', 'alice'),
      isFalse,
    );
    expect(
      isAllowedLegacyProfileUrl(
        'https://firebasestorage.googleapis.com/v0/b/bsgc-app.firebasestorage.app/o/users%2Fbob%2Fprofile%2Favatar.jpg?alt=media',
        'alice',
      ),
      isFalse,
    );
    expect(
      isAllowedLegacyProfileUrl(
        'https://firebasestorage.googleapis.com/v0/b/attacker.appspot.com/o/users%2Falice%2Fprofile%2Favatar.jpg',
        'alice',
      ),
      isFalse,
    );
    expect(
      isAllowedLegacyProfileUrl(
        'https://firebasestorage.googleapis.com/v0/b/bsgc-app.firebasestorage.app/o/users%ZZalice%2Fprofile%2Favatar.jpg',
        'alice',
      ),
      isFalse,
    );
  });
}
