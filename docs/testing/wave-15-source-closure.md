# Wave 15 source-closure verification

**Branch:** `codex/bsgc-full-remediation`
**Parent audit:** `docs/testing/milestone-12-final-audit.md`
**Plan:** `docs/post-remediation-audit/05-prioritized-implementation-plan.md`

## Purpose and boundary

Wave 15 re-checks the remaining source-adjacent error and recovery findings
after Wave 14. It deliberately separates a real source change from a finding
that was already closed in an earlier wave but was easy to misread from the
older audit wording.

## Finding reconciliation

| Audit finding | Wave 15 result | Acceptance boundary that remains |
| --- | --- | --- |
| `REL-027` | Account deletion and group-invite creation no longer render raw exception/plugin text. Typed Firebase Functions codes are mapped to stable actionable copy; unknown failures use a safe retry message. Diagnostics are debug-only and omit the raw exception text. | Complete the remaining mutation/error-copy inventory, localization review, and device/network failure walkthrough. |
| `UX-010` | The scoped account-deletion and invite paths now have deliberate failure states instead of unstable exception copy. Wave 14 profile edits still wait for Firestore commit acknowledgement before confirmed success. | Audit every remaining mutation (comments, reactions, preferences, media, drafts, and publish flows) and verify queued/offline/retry behavior on device. |
| `REL-026` | The account/invite client paths preserve server error codes and map them to product language rather than exposing raw callable messages. | A complete shared date-picker/server-contract review and timezone/device acceptance remain separate work. |
| `REL-020` | No new source change was necessary. The earlier `ff6a986` implementation already creates a new group stream in `GroupStreamRetryController.retry()`, and Main Hall passes the replaced stream to `StreamBuilder`. | Device retry/empty/error visual review remains open. |

## Structural behavior trace

### Stable error copy

Callable/Firebase exception → typed code preserved by the service or read from
the typed exception → `user_facing_error_copy.dart` maps the code → screen
renders actionable copy. The exception's message is not used as UI text, and
debug diagnostics are limited to runtime type plus stack trace.

### Group retry confirmation

Error state → Main Hall `_retryGroups()` → `GroupStreamRetryController.retry()`
invokes its stream factory → a new Firestore snapshots pipeline is supplied to
`StreamBuilder`. The existing regression test asserts both factory invocation
and stream identity replacement.

## Verification evidence

Using the repository-pinned `.tooling/flutter/bin` toolchain:

- `dart format --output=none lib test` — pass;
- `flutter analyze` — pass, no issues;
- focused error-copy and reliability tests — **20 passed**;
- `flutter test --reporter compact` — **90 passed**;
- `git diff --check` — pass after integration.

The tests cover typed-code mappings, unknown-error redaction, stream retry
replacement, and the previously integrated Wave 13/14 boundaries. They do not
substitute for Firebase callable failures on a device or production-like
backend.

## Remaining gates and follow-up

- Finish the mutation-by-mutation success/error copy inventory, including
  comments, reactions, preferences, media, drafts, and publish paths.
- Exercise account deletion and invitation failure states with offline,
  permission, expired-study, rate-limit, and process-restart scenarios.
- Run the Android/Apple device matrix and native Firestore cache-isolation
  checks.
- Keep App Check project registration/enforcement, signed artifacts, CI smoke,
  links, migration/backup, operations, legal copy, and product approval open.

Wave 15 therefore improves the source-level trust boundary while the branch
remains internal preview/development only.
