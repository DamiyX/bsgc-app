# Continuation Wave 13 — source-closure slice

**Branch:** `codex/bsgc-full-remediation`
**Scope:** SEC-006 in-process account-session isolation and UX-016 residual
theme bypasses
**Status:** implemented and locally verified; native Firestore-cache and
device visual acceptance remain open

This wave follows the Milestone 12 reconciliation. It does not reopen the
completed waves or claim that owner-controlled release gates are complete.
Two isolated subtracks were reviewed independently and integrated only after
the parent review.

## Subtrack A — account-session boundary (SEC-006)

Files:

- `lib/services/account_session_boundary.dart`
- `lib/main.dart`
- `test/account_session_boundary_test.dart`
- `docs/testing/account-switch-isolation-boundary.md`

Behavior:

1. Every auth identity transition receives a monotonically increasing in-memory
   session epoch, including sign-out followed by reauthentication as the same
   UID.
2. The account-owned `UserDataWrapper` and signed-out `FoyerScreen` subtrees
   are keyed by that epoch. Flutter therefore disposes the previous subtree
   before the next identity renders.
3. `AccountSessionToken.isCurrent` gives account-scoped asynchronous work a
   deterministic stale-result guard.
4. The implementation does **not** call Firestore `terminate()` or
   `clearPersistence()` during live sign-out. Firestore persistence remains
   enabled for warm offline use; native cache isolation still requires the
   documented Android device matrix.

Automated tests cover account A to B, sign-out to same-account reauthentication,
and stale asynchronous token rejection. They do not prove native Firestore
cache contents after process death or airplane-mode account switching.

## Subtrack B — residual theme bypasses (UX-016)

Files:

- `lib/screens/view_insight_screen.dart`
- `lib/screens/study_room_screen.dart`
- `lib/widgets/add_member_sheet.dart`

Behavior:

- reflection/comment surfaces use `ColorScheme.surfaceContainerLow`;
- saved, reaction, send, progress, and create controls use theme primary and
  semantic foreground/border colors;
- delete and recording indicators use `ColorScheme.error` instead of a fixed
  red;
- invitation buttons and loading indicators use `primary`/`onPrimary`;
- transparent modal/blur layers remain structural;
- QR code white substrate and dark ink remain fixed intentionally for scanner
  contrast and are documented inline.

No feature behavior or data contract changed in this subtrack.

## Verification

Using the repository-pinned `.tooling/flutter` toolchain:

- Dart format: 87 files, 0 changes;
- `flutter analyze`: no issues;
- `flutter test`: 83 passed, 0 failed;
- focused privacy tests: 3 passed;
- focused theme/widget test: 6 passed;
- `git diff --check`: pass.

## Remaining acceptance boundary

- Run the account-switch/offline/process-death matrix on a low-memory and a
  current Android device. Any cross-account cached document is a release
  blocker.
- Run light/dark, contrast, 200% text, TalkBack, and RTL review on the target
  device matrix.
- Continue with the next source wave only after this commit is reviewed; do not
  enable App Check enforcement, deploy production, or merge the branch based on
  this source-only evidence.
