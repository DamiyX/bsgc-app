# Remaining-work handoff after Wave 19

**Checkpoint:** `3c00b07` (`Close Wave 19 room acknowledgement and cache isolation gaps`)

**Branch:** `codex/bsgc-full-remediation`

**Worktree/push state:** clean; no push performed

## What is closed in source through this checkpoint

- Waves 13-19 are recorded as continuation source-closure slices after the
  original Milestone 12 audit.
- Profile, details, mute, note, reflection, draft, outbox, voice-recording,
  date-picker, Study Room personal-state, and reviewed media-reference paths
  now have explicit persistence or local-recovery boundaries in source.
- Wave 18 added bounded cleanup for deterministic profile/group reference
  failures and a server-acknowledged study mute mutation.
- Wave 19 added server acknowledgement for hide/clear/unread Study Room state
  and a per-account voice-cache barrier covering finalization, cache-hit
  metadata refresh, pruning, and sign-out cleanup.

## Verification at the pause point

- Pinned Dart formatting: pass (`93` files checked).
- Pinned `flutter analyze`: no issues.
- Full pinned Flutter suite: **109 passed**.
- Wave 19 focused Study Room/voice-cache suite: **29 passed**.
- Functions syntax check: pass.
- Full Functions suite: **78 passed**.
- Rules Emulator: no Rules files changed in Waves 18-19; the integrated
  baseline remains **31 passed**.
- `git diff --check`: pass.

These are local source checks. They are not emulator, physical-device,
deployed-backend, or release evidence.

## Remaining source-adjacent or external gates

1. **Offline/device matrix:** airplane mode, warm/cold startup, process death,
   voice move-to-draft recovery, codecs, cache pressure, reconnect, large text,
   RTL, reduced motion, TalkBack, notifications, invites, and account A/B
   switching still need Android emulator and physical-device evidence.
2. **Firestore cache isolation (`SEC-006`):** the in-process session boundary
   and account-scoped local cleanup are source-controlled, but native Firestore
   persistence remains enabled. Prove that account A data cannot appear to B
   after sign-out, relaunch, and offline startup. A failure is a release
   blocker; do not call `terminate()` or `clearPersistence()` during live
   sign-out as a shortcut.
3. **Media lifecycle (`SEC-002`, `SEC-003`, `SEC-012`):** canonical paths,
   managed metadata, bounded client cleanup, and scheduled reconciliation exist
   in source. Signed URL expiry/revocation, Storage authorization, deployed
   Function parity, and production orphan-backlog drain still need evidence.
4. **Voice recording boundary (`REL-023`):** the temp-to-outbox move is
   ordered and recoverable in source, but the small move-to-draft filesystem
   crash window and kill/relaunch behavior remain device gates.
5. **Mutation inventory (`UX-010`):** the highest-risk reviewed paths now wait
   for acknowledgement or preserve retry state. A future source audit may find
   another path, but no further wave should be opened until new evidence or a
   concrete reproduction justifies it.
6. **Backend/release:** run the branch quality workflow, Android debug smoke,
   approved staging deployment, App Check registration/enforcement and
   rollback rehearsal, signed AAB/arm64 size analysis, App/Universal Links,
   migration backup/rollback rehearsal, scheduled backlog drain, and
   production observability checks.
7. **Product/owner decisions:** legal/support/retention copy, permanent-delete
   semantics, schedule-aware Today behavior, duplicate navigation choices,
   brand assets, moderation operations, and store disclosures require owner or
   product approval. Source code cannot infer these decisions safely.

## Recommended next action

Pause implementation here. Give the branch to the friend/device reviewer
using `docs/testing/branch-preview-guide.md`. Ask for the exact commit, device
and Android API, Flutter/SDK versions, network state, screenshots, logs, and
reproduction steps for every failure. Only reopen another source wave when a
new concrete source defect is confirmed from that evidence; otherwise proceed
through the external release gates above.

The branch is materially ahead of the original audit checkpoint, but it is
still **internal preview/development only**, not release-ready.
