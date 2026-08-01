# Wave 16 source-closure verification

**Branch:** `codex/bsgc-full-remediation`
**Parent audit:** `docs/testing/milestone-12-final-audit.md`
**Plan:** `docs/post-remediation-audit/05-prioritized-implementation-plan.md`

## Purpose and boundary

Wave 16 continues the UX-010 mutation review after Waves 14 and 15. Two
subtracks inspected the reflection action paths and the study/settings/draft
paths independently, then the parent integrated only the concrete source
gaps. The wave does not claim that a desktop test substitutes for offline
device or Firebase-server evidence.

## Finding reconciliation

| Audit finding | Wave 16 source result | Acceptance boundary that remains |
| --- | --- | --- |
| `UX-010` / reflection deletion | `InsightService.deleteInsight` now waits for Firestore's pending-write metadata to clear before `MyInsightsScreen` can show “Reflection deleted”. A widget regression test holds the delete future open and proves no success copy appears early. | Run offline/process-death deletion tests against a real Firestore project and complete the remaining mutation inventory. |
| `UX-010` / local draft and outbox cleanup | Private/contact draft discard reports local-storage failure and preserves the editor text. Study-room outbox discard reports failure. When an outbox entry is already queued, a failed local draft cleanup is explicit while the durable outbox remains authoritative. | Exercise filesystem interruption, process restart, duplicate draft recovery, and attachment cleanup on low/mid Android devices. |
| `UX-010` / sound preference | Mute-app-sounds preference changes optimistically only while persistence is attempted; a failed/false `SharedPreferences` result rolls the switch back and shows stable copy. | Device storage/permission failure and settings visual review remain open. |
| `REL-027` | The wave confirms the audited reflection/study paths already use stable failure copy or rollback; raw account/invite error text was closed in Wave 15. | Finish the full error-copy/localization sweep across every remaining surface. |

## Structural behavior trace

### Reflection deletion

Delete confirmation → Firestore status update → local pending-write stream →
server acknowledgement or bounded timeout → `MyInsightsScreen` success/error
copy. The previous record-replacement “UNDO” behavior remains absent.

### Local cleanup

User discards or sends a draft → cleanup wrapper attempts the local file delete
→ success clears the local state, failure preserves/reports the state → any
already-enqueued outbox item remains the authoritative retry record.

### Sound preference

Toggle → in-memory UI update → injected persistence operation → rollback and
snackbar on failure. No storage failure is allowed to escape as an uncaught
future or leave a misleading persisted state.

## Verification evidence

Using the repository-pinned `.tooling/flutter/bin` toolchain:

- `dart format lib test` followed by `dart format --output=none --set-exit-if-changed lib test` — pass;
- `flutter analyze` — pass, no issues;
- focused Wave 16 reliability/mutation tests — **26 passed**;
- `flutter test --reporter compact` — **93 passed**;
- `git diff --check` — pass after integration.

The focused tests cover deletion success timing, rollback/persistence helpers,
draft cleanup failure, reversible insight actions, and existing room mutation
contracts. They do not prove native Firestore acknowledgement or physical
filesystem/process-death behavior.

## Remaining gates and follow-up

- Complete the mutation-by-mutation success/error audit for comments,
  reactions, preferences, media, drafts, publish, deletion, and notification
  paths; add device evidence for offline and process death.
- Verify native Firestore account-cache isolation and complete cache purge.
- Keep App Check project registration/enforcement, Android CI/device review,
  signed artifacts/size, links, migration/backup, operations, legal copy, and
  product approval open.

Wave 16 improves the source-level truthfulness boundary while the branch
remains internal preview/development only.
