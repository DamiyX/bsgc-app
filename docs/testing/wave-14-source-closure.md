# Wave 14 source-closure verification

**Branch:** `codex/bsgc-full-remediation`
**Parent audit:** `docs/testing/milestone-12-final-audit.md`
**Plan:** `docs/post-remediation-audit/05-prioritized-implementation-plan.md`

## Purpose and boundary

Wave 14 is a bounded continuation of the Milestone 12 reconciliation. It
re-checks the source gaps that Milestone 12 deliberately left open; it does
not reinterpret device, Firebase-console, production, legal, or product-owner
evidence as completed merely because the source compiles.

Two independent source tracks were reviewed and then integrated together:

1. App Check client activation for the mobile build path.
2. The duplicate Me navigation shortcut and profile-edit success semantics.

The Profile/Journal information architecture was intentionally not changed in
this wave. That remains a product migration decision requiring a focused
walkthrough and migration tests.

## Finding reconciliation

| Audit finding | Wave 14 source result | Acceptance boundary that remains |
| --- | --- | --- |
| `SEC-007` | The official `firebase_app_check` FlutterFire dependency is present. `lib/services/app_check_bootstrap.dart` maps `BRAID_ENV=local` to debug providers and staging/production to Play Integrity/App Attest with DeviceCheck fallback. `lib/main.dart` activates it immediately after `Firebase.initializeApp()` and before Messaging, Firestore, or Crashlytics use. | Register the Android/Apple apps and providers in Firebase, privately register local debug tokens, exercise signed staging clients, inspect valid/missing/invalid-token metrics, and only then consider enforcement. |
| `RELENG-004` | Provider selection is source-controlled and the quality/release workflows pass explicit `BRAID_ENV` values. Functions enforcement switches remain unchanged and false. Unsupported web/desktop hosts fail with an explicit configuration diagnostic instead of being presented as attested clients. | Owner/provider setup, signed artifacts, staging observation period, callable coverage, and rollback rehearsal are still required. |
| `UX-005` | The Me tab now has one Settings destination. The redundant app-bar Settings action was removed; Profile, Safety center, and Settings remain discoverable from the Me surface. | Human navigation review must confirm hierarchy and decide whether Profile's saved-reflection presentation should later be consolidated with Journal. |
| `UX-010` | Profile photo and profile-details writes now wait for Firestore metadata to report no pending writes before showing confirmed success. A bounded timeout uses explicit queued-local/reconnect/retry copy and keeps the editor open. | Device/offline testing should verify the actual pending-write transition, retry behavior, process death, and any orphaned uploaded media. A complete mutation-by-mutation success-copy inventory is still open. |

The source statuses above update the open dispositions recorded in Milestone 12;
they do not close the acceptance gates in that report.

## Structural behavior trace

### App Check

`BRAID_ENV` compile-time define → `braidEnvironmentFromDefine` →
`appCheckPlanFor` → official `FirebaseAppCheck.instance.activate` provider →
Firebase requests from the initialized mobile client. Activation is awaited in
the startup gate before Messaging and Firestore are configured. Backend
enforcement is intentionally outside this source change.

### Profile mutation acknowledgement

User submits an edit → Firestore `DocumentReference.update` queues the write →
`waitForDocumentCommit` observes `snapshots(includeMetadataChanges: true)` →
success is shown only after `hasPendingWrites` becomes false, otherwise the
timeout copy keeps the user in the editor. A Firebase error still takes the
existing failure path.

### Me navigation

User selects the Me tab → the Me destination list renders → Settings is opened
from the single `_MeDestination` row. There is no second app-bar action for the
same destination.

## Verification evidence

The parent verification used the repository-pinned toolchain
`.tooling/flutter/bin`:

- `dart format --output=none --set-exit-if-changed lib test` — pass after
  formatting the new tests;
- `flutter analyze` — pass, no issues;
- `flutter test --reporter compact` — pass, **86 tests**;
- `git diff --check` — pass;
- focused App Check, profile-copy, Insight/Journal, and reflection journey
  tests — pass during the two subtracks, then re-run in the full suite.

The focused tests validate provider mapping, the injectable activation boundary,
unsupported-host diagnostics, and the commit-acknowledgement success/timeout
contract. They do not substitute for a real Firebase project or device.

## Remaining gates and follow-up

- Android/Apple device and emulator review: offline launch, pending writes,
  process death, account switching, accessibility, light/dark themes, and
  long-dataset behavior.
- Firestore native-cache account isolation and complete cache purge behavior
  after sign-out; the in-process account-session boundary from Wave 13 remains
  a separate source safeguard.
- App Check Firebase registration, debug-token handling, staged metrics,
  enforcement and rollback rehearsal.
- CI Android smoke, signed AAB/arm64 APK, size JSON, Play App Links, migration
  backup/deployment, moderation operations, legal copy, and release approval.
- Product walkthrough for the Me/Profile/Journal hierarchy and the remaining
  UX-002, UX-009, UX-012, UX-013, UX-015, UX-016, and UXE findings.

Wave 14 therefore closes the source-controlled portions of the four affected
finding boundaries, while the branch remains internal preview/development
only as required by Milestone 12.
