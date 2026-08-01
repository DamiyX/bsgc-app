# Scheduled job safety

Lifecycle and cleanup jobs use a maximum of 450 Firestore writes per commit.
Multi-write work records its write cost before batching; no item may exceed the
cap. Managed-media cleanup uses single-document transactions plus idempotent
Storage deletion.

Eligible lifecycle and cleanup records leave their query when processed.
Jobs therefore page repeatedly from the query head. This mutation-derived
cursor is safe across invocations and includes records inserted before or
after a prior page boundary. Jobs stop at a bounded time budget; the next
invocation resumes from remaining eligible records.

Every run logs:

- processed and error counts;
- page count and time-budget stop state;
- remaining backlog count;
- oldest eligible record age;
- cursor strategy.

Alert when errors are non-zero, backlog grows across three runs, or oldest age
exceeds twice the scheduler interval/retention target. Never increase page
sizes above 450 to hide backlog.
