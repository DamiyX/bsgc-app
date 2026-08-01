# Wave 20A media URL security handoff

**Scope:** SEC-002 / SEC-005 source review of legacy profile-image URLs and
message-media URL ingestion

**Review date:** 2026-08-01

**Status:** local source fix and focused Flutter tests pass; deployed Storage
authorization, bearer-token expiry/revocation, and device evidence remain open

## Finding closed in source

`isAllowedLegacyProfileUrl` was intended to be a narrow compatibility allowlist,
but the Firebase Storage branch accepted every object below the owner’s
`users/{uid}/profile/` prefix. A crafted value could therefore point the avatar
renderer at a nested or traversal-shaped object path while still passing the
client’s “allowed legacy profile URL” check. The same branch accepted arbitrary
query parameters, which made a profile field an unnecessary place to carry
tracking or other request parameters.

The policy now:

- validates the owner identifier before constructing the allowlist expression;
- requires HTTPS, no user-info, and no URL fragment;
- accepts Google bootstrap URLs only on the exact
  `lh3.googleusercontent.com` host (existing size-query compatibility is kept);
- accepts Firebase Storage URLs only on the reviewed production bucket;
- permits only the legacy `alt=media` and `token` query keys for Firebase
  compatibility, rejecting other query keys and non-media `alt` values; and
- decodes the object path and matches one exact
  `users/{ownerUid}/profile/{assetName}` object, rejecting nested paths,
  traversal-shaped paths, and prefix collisions.

This is a client rendering boundary and does not replace Storage rules. A
modified client can still attempt direct Storage requests, and long-lived
Firebase download tokens remain bearer credentials until they expire or the
object is removed. Signed URL expiry/revocation and deployed authorization must
be proven against Firebase separately.

## HTTPS message-media review

`MessagePart` and the callable normalizer require image/voice attachments to
carry a canonical managed Storage path plus the deterministic managed asset ID.
Legacy HTTPS image/voice values are classified as explicit external links and
the Study Room renders them as text; it does not pass them to `BraidMedia`,
`VoiceMessageBubble`, or the cache downloader. The production call sites pass
only `firebase-storage:///groups/.../messages/...` to the authenticated cache.
No additional HTTPS ingestion change was required in this slice.

## Changed source

- `lib/services/media_reference_policy.dart`
  - exact path/host/query/fragment validation for legacy profile URLs;
- `test/media_reference_policy_test.dart`
  - regression coverage for nested-path/prefix and traversal cases, query
    allowlisting, fragments, owner-ID validation, and legacy token URLs.

## Verification

Run with the repository-pinned Flutter toolchain:

```text
.tooling/flutter/bin/dart.bat format lib/services/media_reference_policy.dart test/media_reference_policy_test.dart
.tooling/flutter/bin/flutter.bat test test/media_reference_policy_test.dart --reporter compact
```

Result: **2 tests passed**. `git diff --check` is clean for this change.

## Remaining boundary

The source policy is not evidence that a copied Firebase download URL is
revoked after membership removal or deletion. The next release/security gate
must run the real Storage authorization and copied-URL revocation matrix on a
deployed project, including legacy data and backend/client version skew.
