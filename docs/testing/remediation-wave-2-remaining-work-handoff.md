# Remediation Wave 2 remaining-work handoff

**Current remediation label:** Wave 2
**Historical repository label:** continuation Wave 21
**Starting source checkpoint:** `f33cacd`
**Branch:** `codex/bsgc-full-remediation`
**Status:** source work completed and locally verified; commit/push is the
next delivery step

## What this wave closed

Wave 2 was intentionally limited to two independent source tracks. It did not
reopen already-verified room pagination, media URL policy, voice-cache,
notification preference, or Firebase Functions paths.

### Track A — Insight mutation reliability

Finding IDs: `REL-007`, `REL-008`, `UX-010`

Files:

- `lib/services/insight_mutation_contract.dart`
- `lib/services/insight_action_controller.dart`
- `lib/services/insight_service.dart`
- `test/insight_reliability_test.dart`

The shared eight-second boundary prevents unresolved callable operations from
leaving reaction, save, or comment controls disabled forever. Timeout rollback
preserves the user's comment draft and restores optimistic toggle state. The
compatibility comment stream now uses the same newest-first bounded ordering
as the cursor-based viewer path.

### Track B — Notification and invite destination reliability

Finding IDs: `REL-010`, `REL-011`, `UX-010`

Files:

- `lib/services/notification_destination_store.dart`
- `lib/services/deep_link_service.dart`
- `lib/services/notification_service.dart`
- `lib/screens/main_hall_screen.dart`
- `test/notification_invite_reliability_test.dart`

Destination restore/write/complete/discard operations are serialized. Deep
link initialization can retry after a transient failure, concurrent invite
operations share an ordered queue, and stream/notification callbacks contain
storage errors. Main Hall prevents duplicate opens for the same pending route
and keeps the route available when cleanup fails.

## Verification trace

All commands used the pinned repository toolchain:

```text
.tooling/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test
.tooling/flutter/bin/flutter.bat analyze
.tooling/flutter/bin/flutter.bat test --reporter compact
cd functions
npm run check
npm test -- --test-concurrency=1
```

Results:

- Insight reliability: **25 passed**;
- notification/invite reliability: **12 passed**;
- full Flutter suite: **115 passed**;
- `flutter analyze`: no issues;
- Dart format and `git diff --check`: pass;
- Functions syntax check: pass;
- Functions suite: **78 passed**;
- Rules: no files changed; the integrated **31-test** Rules Emulator baseline
  remains the applicable evidence.

## Remaining work and gates

These are not silently treated as source defects fixed by Wave 2:

1. Run the Android emulator/physical-device matrix for offline launch, cached
   avatars/covers, notifications, deep links, accessibility, process death,
   account switching, and large text. The source suite cannot prove those
   native/device behaviors.
2. Run the Android CI debug compilation and obtain signed AAB size analysis.
   The earlier local Gradle attempts timed out; no release-size claim is made
   from that result.
3. Verify deployed Functions, Firestore/Storage Rules, App Check registration
   and enforcement, FCM permission/delivery, Storage bearer-token behavior,
   and staging rollback with the approved Firebase project.
4. Verify native Firestore cache isolation and complete purge behavior across
   sign-out/account-switch/process-death scenarios.
5. Complete migration/backup rehearsal, production-scale scheduled-job and
   rollback evidence, moderation/abuse monitoring, retention, legal/support,
   and product approval gates.

## Sequencing rule for the next wave

There is no honest fixed number of remaining waves. The historical “Wave 19”
and “Wave 20” labels are repository checkpoints, not a count of unresolved
tasks. The current normalized sequence is:

- remediation Wave 1: the completed Wave 20 checkpoint;
- remediation Wave 2: this Insight/notification source correction;
- remediation Wave 3 and later: only when a fresh source trace, CI result, or
  device/deployed test produces a concrete defect. At most two tracks will be
  opened inside one wave, and no wave will be started concurrently with
  another.

The next agent must read this handoff and the implementation plan before
opening Wave 3. It must record a new starting SHA, preserve this branch's
clean verification evidence, add focused regression tests, and keep external
release gates separate from source closure.
