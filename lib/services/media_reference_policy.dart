bool isCanonicalProfilePhotoPath(String value, String ownerUid) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(ownerUid)) return false;
  return RegExp(
    '^users/${RegExp.escape(ownerUid)}/profile/[A-Za-z0-9_.-]{1,160}\$',
  ).hasMatch(value);
}

bool isCanonicalGroupCoverPath(String value, String groupId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(groupId)) return false;
  return RegExp(
    '^groups/${RegExp.escape(groupId)}/covers/[A-Za-z0-9_.-]{1,160}\$',
  ).hasMatch(value);
}

bool isAllowedLegacyProfileUrl(String value, String ownerUid) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.host == 'lh3.googleusercontent.com') return true;
  if (uri.host != 'firebasestorage.googleapis.com') return false;
  try {
    final decodedPath = Uri.decodeComponent(uri.path);
    return decodedPath.startsWith(
      '/v0/b/bsgc-app.firebasestorage.app/o/users/$ownerUid/profile/',
    );
  } on FormatException {
    return false;
  }
}
