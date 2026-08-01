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
  if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(ownerUid)) return false;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }
  if (uri.host == 'lh3.googleusercontent.com') return true;
  if (uri.host != 'firebasestorage.googleapis.com' ||
      // Legacy Firebase URLs may carry `alt=media` and a download token. Do
      // not allow arbitrary query parameters to turn a profile field into a
      // tracking URL; bearer-token expiry/revocation remains a backend gate.
      uri.queryParameters.keys.any(
        (key) => !const {'alt', 'token'}.contains(key),
      ) ||
      (uri.queryParameters['alt'] != null &&
          uri.queryParameters['alt'] != 'media')) {
    return false;
  }
  try {
    final decodedPath = Uri.decodeComponent(uri.path);
    final objectPrefix = '/v0/b/bsgc-app.firebasestorage.app/o/';
    if (!decodedPath.startsWith(objectPrefix)) return false;
    final objectPath = decodedPath.substring(objectPrefix.length);
    return RegExp(
      '^users/${RegExp.escape(ownerUid)}/profile/[A-Za-z0-9_.-]{1,160}\$',
    ).hasMatch(objectPath);
  } on FormatException {
    return false;
  }
}
