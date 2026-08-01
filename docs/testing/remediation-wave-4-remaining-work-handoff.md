# Remediation Wave 4 - remaining-work handoff

**Repository branch:** `codex/bsgc-full-remediation`
**Starting source checkpoint:** `2105d1e` (Remediation Wave 3 / historical Wave 22)
**Current checkpoint:** local Wave 4 source closure (historical Wave 23)
**Push status:** not pushed by this wave

## Wave count and naming

This remediation continuation uses four normalized source waves:

| Normalized wave | Historical repository label | Scope |
| --- | --- | --- |
| Wave 1 | Wave 20 | media and notification reliability |
| Wave 2 | Wave 21 | Insight, notification, and invite reliability |
| Wave 3 | Wave 22 | deletion semantics and timestamp contracts |
| Wave 4 | Wave 23 | canonical identity and lifecycle timing |

The historical labels are checkpoints, not additional work waves. There is no
predeclared Wave 5. A future wave must be opened only if a concrete source,
device, deployed, or release check produces a new defect. Device, deployed,
release, operations, legal, and product acceptance are external gates, not
automatic code waves.

## Track A - canonical identity consistency (`REL-017`)

Authored Insights and comments now load the current account's canonical public
profile instead of copying potentially stale Firebase Auth `displayName` and
`photoURL`. `CurrentProfileRepository` keeps the last known value per UID,
coalesces concurrent reads for the same account, rejects a source response for
the wrong UID, and is invalidated after onboarding/profile writes and sign-out.
The comment composer keeps the entered text when canonical profile loading
fails.

Changed source and regression files:

- `lib/services/current_profile_repository.dart`
- `lib/services/canonical_identity_service.dart`
- `lib/services/auth_service.dart`
- `lib/screens/create_insight_screen.dart`
- `lib/screens/view_insight_screen.dart`
- `lib/screens/edit_profile_screen.dart`
- `lib/screens/onboarding_screen.dart`
- `test/identity_consistency_test.dart`
- `docs/testing/wave-23-identity-consistency.md`

Focused result: **4 identity tests passed**.

## Track B - lifecycle timing (`REL-025`)

Callable group message creation/editing and member-owned progress writes now
enforce the configured start/end timestamps as well as the persisted lifecycle.
This closes the stale-active window between scheduled lifecycle runs. Legacy
active groups without dates remain compatible.

Changed source and regression files:

- `functions/lib/lifecycle_policy.js`
- `functions/index.js`
- `firestore.rules`
- `functions/test/functions/lifecycle_policy.test.js`
- `functions/test/rules/firestore.rules.test.js`
- `docs/testing/wave-23-lifecycle-timing.md`

Focused result: **4 lifecycle-policy tests passed**. Rules regressions are
included in the integrated Rules result below.

## Integrated verification

All checks were run locally from the pinned repository toolchain:

- Dart format check: passed.
- `flutter analyze`: no issues found.
- Full Flutter suite: **125 tests passed**.
- Functions syntax check: passed.
- Functions suite: **82 tests passed**.
- Firestore/Storage Rules Emulator suite: **32 tests passed**.
- `git diff --check`: passed for the staged Wave 4 scope.

No Android emulator, release build, signed AAB, or production Firebase
deployment was run during this source wave.

## Remaining evidence gates

These are intentionally not claimed by source tests:

1. Android emulator and physical-device review of offline profile/media/icon
   behavior, lifecycle transitions, accessibility, and navigation.
2. Firestore persistence/account-switch proof on a real client, including
   complete cache-purge behavior.
3. Deployed Functions and Rules parity, App Check registration/enforcement,
   scheduler latency/backlog measurement, and staged backend deployment.
4. Android CI compilation, signed release AAB size evidence, production
   migration/rollback rehearsal, monitoring, legal, store, and operations
   approval.

If any of these checks produces a new reproducible source defect, record it as
the evidence for a subsequent wave. Otherwise, the repository source work for
the current audit plan is complete at this checkpoint and the next action is
review/acceptance, not an automatic Wave 5.
