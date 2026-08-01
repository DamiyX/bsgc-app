# Wave 17 source-closure handoff

**Branch:** `codex/bsgc-full-remediation`

**Scope:** Milestone 12 continuation against
`docs/post-remediation-audit/05-prioritized-implementation-plan.md`

**Review date:** 2026-08-01

**Status:** source-controlled remediation verified locally; device, deployed
backend, and release gates remain open

## Authority and finding mapping

This wave was limited to the two source gaps left explicit by the Milestone 12
ledger and the implementation plan:

- `REL-023` from Audit 01 / Milestone 5. A stopped voice recording must not be
  described as saved when preparation fails without a path to recover it.
- `REL-026` from Audit 01 / Milestone 2. The study date picker, client
  validation, callable contract, and user-facing error need the same
  calendar-date semantics.

The baseline ledger in `docs/testing/milestone-12-final-audit.md` remains the
historical checkpoint. This document records the later source evidence and
does not convert any emulator, physical-device, Firebase-console, deployment,
or product approval requirement into a pass.

## REL-023 — voice recording preparation/recovery

### Previous failure contract

`AudioService` wrote a recording to the OS temporary directory and
`StudyRoomScreen` attempted to read/process it before adding a draft part. A
read or preparation exception displayed copy equivalent to “saved locally”
without exposing a durable draft, retry target, or delete target.

### Source closure

The stopped-file path now follows this bounded sequence:

1. `AudioService.stopRecording()` returns the recorder path. A missing path is
   released and uses truthful discard/re-record copy.
2. `MessageOutboxService.persistAttachmentFile()` validates the extension,
   file existence, per-file size, account quota, and group/message scope. It
   atomically renames the file into the account-scoped outbox, with a flushed
   copy-and-rename fallback for cross-volume platforms. The OS temporary file
   is not the long-term recovery location.
3. `StudyRoomScreen` creates a voice `MessagePart` pointing at that local
   attachment and awaits `DraftService.save()` before changing only in-memory
   composer state. After the draft write succeeds, a restart can reload the
   voice part and its caption/duration metadata from the account/group draft.
4. Quota failures do not show a success state. Preparation/save failures make
   best-effort scoped cleanup and use explicit “discarded; record again” copy;
   the prior false “saved locally” claim is gone.
5. `removeAttachment()` accepts only a `file:` URI inside the requested
   account/group outbox directory, so a discard action cannot delete outside
   that scope.

The outbox attachment is intentionally not sent until the user submits the
draft. Submission still flows through the existing bounded outbox, retry,
managed-media upload, and server-acknowledgement path.

### Evidence

- `test/voice_recording_recovery_test.dart`: four tests cover durable move and
  discard, draft reload, cross-group deletion rejection, and missing-file copy.
- Focused Flutter run: 23 tests passed (the four voice tests plus the study
  room reliability file).
- `flutter analyze`: no issues.

### Remaining boundary

The move and draft write are separate filesystem operations. A process death in
that very small interval can leave an unreferenced, bounded outbox attachment;
the existing expiry/cleanup path eventually removes it. The acceptance matrix
must still exercise codec/permission failures, low storage, kill/relaunch,
airplane mode, and real-device playback. No source-only test claims that a
temporary recorder file survives process death or that every device codec is
supported.

## REL-026 — calendar date contract

### Previous failure contract

The picker could previously disagree with the callable because the client
selected calendar dates while the server compared raw instants. Same-calendar-
day values with different times and daylight-saving boundaries could therefore
produce different results, and invalid-argument details were shown as generic
snackbar copy.

### Source closure

- `StudyDateRangePolicy` now derives a date-only `YYYY-MM-DD` key and computes
  duration using UTC calendar components, not local-midnight elapsed hours.
  The picker already constrains the end date to at least one day after the
  start and at most 365 calendar days; the submit path revalidates the same
  policy. Topic chapter counts use the same calendar-day calculation.
- `ChatService.createGroup()` sends both the explicit date keys and the
  existing millisecond values. Milliseconds remain the stored/lifecycle
  timestamps; keys prevent device UTC-offset reinterpretation during contract
  validation. Legacy callers that omit keys retain the UTC-instant fallback.
- `functions/lib/study_dates.js` rejects missing/malformed dates, same-day or
  earlier ends, and ranges beyond 365 calendar days. Exactly 365 days is
  accepted. The callable returns only a stable `field: dateRange` and
  machine-readable `reason` in `HttpsError.details`.
- `GroupOperationFailure` maps those reasons to stable field-level copy, and
  `CreateGroupScreen` renders the date guidance under the date selector rather
  than exposing a raw server message.

### Evidence

- `functions/test/functions/study_dates.test.js`: eight contract tests cover
  same-day instants, the exact 365-day boundary, 366-day rejection, missing
  values, timezone-shifted explicit keys, malformed keys, and key-pair/storage
  requirements.
- `test/study_room_reliability_test.dart`: calendar-duration, reason-copy,
  and field-scoped error-detail tests pass.
- Full pinned Flutter suite: 101 tests passed; `flutter analyze` is clean.
- Functions syntax check and full Functions suite: 78 tests passed.

### Remaining boundary

The deployed callable must be updated together with the client, and a staging
or emulator run must confirm old/new client compatibility. Device review still
needs date-picker behavior across locales/time zones and DST transitions. The
source contract does not by itself prove deployed backend parity.

## Verification snapshot

The final Wave 17 verification commands are recorded in the parent audit and
branch preview guide. Formatting and `git diff --check` are clean. The branch
remains internal preview/development only until the existing Milestone 12
release gates (CI Android compile, signed artifact/size evidence, device and
accessibility matrix, Firestore cache isolation, App Check rollout, staging
deployment, migration/operations, legal, and product approval) are evidenced.
