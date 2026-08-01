# Wave 21 Insight mutation pending-state handoff

**Scope:** `UX-010` / Insight reaction, comment, and save mutation pending
states

**Status:** source correction and focused tests pass; no commit or push was
made by this track

## Finding

The Insight viewer could leave an action pending indefinitely when a callable
write never resolved. Reaction buttons are disabled while
`ReversibleToggleController.isPending` is true, the comment composer is
disabled while `_isCommentPending` is true, and comment-reaction rows are
blocked while their id is in `_pendingCommentReactionIds`. Without a bounded
Future, a stalled network operation could keep each of those guards active
forever.

Save writes already wait for a Firestore server acknowledgement through
`waitForDocumentCommit` (which has an eight-second timeout), but the viewer's
save controller now shares the same explicit mutation boundary as reactions
and comments.

## Source correction

- `insight_mutation_contract.dart` defines the injectable
  `insightMutationTimeout` (eight seconds) and `awaitInsightMutation` helper.
- `ReversibleToggleController` accepts an injectable timeout, rolls an
  optimistic value back on timeout, and always clears `isPending`.
- `persistCommentText` accepts an injectable timeout, preserves the draft on
  timeout, and clears the draft only after the mutation succeeds.
- `InsightService.addComment` and callable reaction writes use the shared
  boundary. The viewer's comment-reaction `finally` block clears each pending
  id, while the existing save/reaction controllers clear their pending state
  after success, failure, or timeout.

## Regression protection

`test/insight_reliability_test.dart` covers deterministic unresolved Futures:

1. comment persistence times out and preserves the entered text;
2. an optimistic reaction/save-style toggle times out, rolls back, and clears
   its pending flag;
3. the shared mutation helper rejects an unresolved operation with
   `TimeoutException`.

## Verification

Using the repository-pinned Flutter toolchain:

```text
.tooling/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/services/insight_action_controller.dart lib/services/insight_mutation_contract.dart lib/services/insight_service.dart test/insight_reliability_test.dart
.tooling/flutter/bin/flutter.bat test test/insight_reliability_test.dart
.tooling/flutter/bin/flutter.bat analyze
```

Results:

- focused Insight reliability suite: **25 passed**;
- `flutter analyze`: **no issues found**;
- formatting: **pass (4 files, 0 changed)**.

## Remaining boundary

The timeout is an honest retry boundary; it does not cancel an already-issued
callable or Firestore write. A timed-out server operation may still complete
later, so deployed Functions idempotency and device/offline reconnect testing
remain release gates. This source check does not prove Firebase callable
latency, Firestore metadata behavior, or native UI accessibility on physical
devices.
