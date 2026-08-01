# Wave 19 mutation inventory — Study Room personal-state acknowledgement

## Scope and starting point

This bounded Wave 19A slice started from commit `11be6f7` on
`codex/bsgc-full-remediation`. It reviewed the remaining UX-010/reliability
mutation surface called out by the post-remediation audit, with particular
attention to Study Room personal state. The change is source-level only; it
does not claim device, emulator, or deployed-backend acceptance.

## Finding and root cause

The Study Room treated three Firestore mutations as complete when the SDK had
only accepted them into its local cache:

- `ChatService.deleteMessageForMe()` writes the account/group-scoped
  `hidden_messages/{messageId}` marker.
- `ChatService.clearChatForMe()` writes the account/group-scoped
  `group_state/{groupId}.clearedBefore` marker.
- `ChatService.resetUnreadCount()` updates the per-user unread field on the
  group document.

Each method previously returned after `set`/`update`. Firestore can resolve
that Future while offline, so the Study Room could hide content, show
“Earlier messages are now hidden for you,” or clear an unread badge even when
the server had not acknowledged the write. The optimistic hide/clear state
already had rollback in `StudyRoomController`; it was the service durability
boundary that was missing.

## Source correction

`persistAcknowledgedChatStateWrite` in `lib/services/chat_service.dart` now
sequences each write as:

1. enqueue the exact, account/group-scoped Firestore write;
2. await `waitForDocumentCommit` on the same document reference;
3. allow the caller to present confirmed state only after pending writes clear.

The hidden-message, clear-view, and unread-reset methods all use this helper.
The existing Study Room optimistic hide/clear controller therefore rolls back
after an acknowledgement timeout or write failure instead of claiming a
durable change. Main Hall's fire-and-forget unread reset now uses a safe wrapper
so a timeout cannot become an unhandled asynchronous error. Controller
disposal uses the same safe boundary because disposal has no retry UI.

## Regression protection

`test/study_room_reliability_test.dart` adds a deterministic contract test:
the mutation Future remains incomplete after the local write until the injected
acknowledgement completes. The existing visibility and active-room read
reconciliation tests continue to cover the rollback/rendering and retry seams.

## Verification performed

- Pinned Flutter test: `test/study_room_reliability_test.dart` — 19 tests
  passed.
- Pinned `flutter analyze` — no issues found.
- `git diff --check` — clean for this slice.

The Wave 18 `lib/services/voice_cache_service.dart` changes were already
present in the shared worktree and are intentionally outside this handoff.

## Remaining gates

The source contract still needs physical/emulator verification for airplane
mode, reconnect, process restart, and Firestore cache metadata on the target
platforms. The 8-second acknowledgement timeout is an honest retry boundary,
not proof that the write will eventually be accepted. Rules Emulator,
deployed Functions parity, App Check, release artifacts, and production
observability remain external gates.
