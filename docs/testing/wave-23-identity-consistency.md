# Remediation Wave 4 — canonical identity consistency

**Track:** A — authored identity and cached public profile
**Finding:** `REL-017`
**Historical repository label:** continuation Wave 23

## Defect confirmed

Several authored paths still used Firebase Auth `displayName`/`photoURL`
directly while the Firestore `users_public/{uid}` profile was the documented
canonical source. After a profile edit, new Insights and comments could carry
stale Auth identity, and a transient profile read could make the UI jump to a
generic placeholder or another account's cached identity.

## Bounded correction

- Added `CurrentProfileRepository`, keyed by UID, with request coalescing and a
  last-known canonical value for transient read failures.
- `CreateInsightScreen` now loads canonical public identity before publishing.
- `ViewInsightScreen` now loads canonical identity before creating a comment and
  preserves the entered text when that profile read fails.
- The Main Hall Me header and My Insights avatar now read the same canonical
  `users_public/{uid}` profile stream, falling back to Auth identity only while
  the canonical snapshot is unavailable.
- Profile edit and onboarding writes invalidate the selected account's cached
  identity; sign-out clears it; account boundaries cannot reuse another UID's
  value.
- Firestore canonical identity reads use the server/cache source contract.

## Regression protection

`test/identity_consistency_test.dart` covers canonical-over-Auth identity,
UID-isolated caching, concurrent-load coalescing, and rejection of a source
that returns the wrong UID.

## Verification

```text
.tooling/flutter/bin/dart.bat format lib/services/canonical_identity_service.dart lib/services/current_profile_repository.dart lib/screens/create_insight_screen.dart lib/screens/edit_profile_screen.dart lib/screens/onboarding_screen.dart lib/screens/view_insight_screen.dart test/identity_consistency_test.dart
.tooling/flutter/bin/flutter.bat test test/identity_consistency_test.dart --reporter compact
```

Focused result: **4 tests passed**; formatting passed. The integrated Wave 4
gate also passed full Flutter analysis/tests and the Functions/Rules suites.

## Final verification correction

The post-remediation completion audit found that authored content was using
the canonical repository while two visible identity surfaces still rendered a
constructor-time Auth snapshot. The Main Hall and My Insights surfaces now use
`CurrentUserAvatar`/canonical profile data. An explicit fallback mode keeps
injected data-source widget tests independent of Firebase initialization; the
production `InsightService` path continues to use the canonical stream.

The integrated correction also added a recorder-stop regression test because
the same audit found that a null recorder return could otherwise clear an
owned temporary path without moving or deleting it. The test is recorded in
`test/voice_recording_recovery_test.dart` and is part of the 126-test Flutter
gate.

## Remaining boundary

This source cache does not replace Firestore security authorization or repair
historical authored records that already contain stale denormalized identity.
Deployed profile rules, migration/backfill policy, offline device behavior, and
accessibility review remain external gates.
