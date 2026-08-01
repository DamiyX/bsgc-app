# Milestone 7 verification contract

This contract is the acceptance evidence for migration, scheduled jobs, App
Check, abuse controls, rule evaluation, and moderation operations. A green
generic test suite is insufficient unless the cases below are represented.

## Automated repository gates

Run from a clean checkout:

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd functions
npm run check
npm test
npm run test:rules
npm run migrate:v2:rehearse
```

The migration rehearsal must use local fakes/fixtures or emulators and must
never connect to a production project.

## Canonical migration

- Every legacy fixture for users, public/private profiles, devices, groups,
  group members, messages, notes, saved Insight pointers, Insights, and invites
  produces either a rule-compatible canonical document or a typed quarantine
  issue.
- Missing, null, wrong-type, over-limit, Unicode, legacy-map, already-v2, and
  ambiguous-owner shapes are represented.
- Applying the canonicalizer twice produces the same logical document.
- Note bodies through 50,000 characters are byte-for-byte preserved.
- Dry-run reports contain document paths, reason codes, counts, lengths, and
  hashes where needed, but never note, message, report, or profile content.
- `invites/{tokenHash}` is the only supported invitation collection. Raw
  tokens never enter Firestore or migration evidence.

## Resume and rollback rehearsal

Seed more than 1,000 source records across multiple collections and verify:

1. deterministic document-ID pagination;
2. every commit stays below its configured write budget;
3. a forced failure after at least two pages persists run ID, phase, cursor,
   counts, and issues;
4. resuming the same run neither skips nor duplicates a record;
5. re-running a completed migration produces no divergent canonical state;
6. a different run cannot silently take over an active checkpoint;
7. rollback restores every changed fixture from an access-controlled
   before-image artifact;
8. restore verification compares path/count/hash evidence;
9. completed/expired before-images follow the documented retention and
   deletion path.

Production application additionally requires a named export, restore owner,
storage location, checksum, and a rehearsed non-production restore. Source
tests cannot prove that operational gate.

## Scheduled work and backlog

With more than 1,000 eligible records:

- lifecycle activation/completion drains across pages without a commit above
  500 writes;
- multi-write items consume their real write cost, not one document slot;
- cleanup workers continue past historical 400/250 first-page caps until their
  bounded time/write budget is reached;
- a timeout or failed page preserves a safe resume cursor;
- a new record inserted around the cursor is eventually processed;
- logs/metrics expose processed, failed, remaining/backlog estimate, oldest
  eligible age, duration, page count, and run ID;
- empty runs perform no empty commit and still emit a healthy completion
  signal.

## Trusted writes and abuse controls

- Direct client creation of server-authoritative messages, Insights, comments,
  reactions, invites, and reports is denied; direct message edits and
  tombstones are denied as well.
- The callable accepts the largest supported valid payload, including a
  four-part message, without reaching a Rules expression limit.
- Forged UID, display identity, group, message, asset, reply parent, report
  target, or visibility context is rejected.
- The same operation ID called concurrently commits one logical record and
  applies counters/fan-out once.
- Burst and sustained limits are tested independently for group creation,
  invite create/redeem attempts, messages, attachments, comments, reactions,
  reports, and Insight publish/fan-out.
- Limit errors return a stable code and retry-after only when retry is valid.
- A block in either direction prevents policy-defined invitation redemption
  and content visibility.
- Report creation proves the target exists and is visible to the reporter in
  the submitted context.
- Rate-store or authorization dependency failure fails closed while the client
  retains its durable draft/outbox item.

## App Check

- Debug builds select only local debug providers; release builds select Android
  Play Integrity and the approved Apple production provider.
- Debug tokens are absent from tracked source, build configuration, logs, and
  release artifacts.
- Callables run with enforcement disabled during observation, then a staging
  test proves valid tokens succeed and missing/invalid tokens fail for each
  enforced callable.
- The enforcement parameter and rollback procedure are tested without
  weakening Firebase Authentication, authorization, Rules, or rate limits.
- Production enforcement remains blocked until minimum supported clients emit
  valid tokens and provider registration is verified in the Firebase console.

## Moderation operations

- Ordinary users cannot enumerate reports, evidence, operator state, appeals,
  or audit records.
- Reviewer, operator, and administrator roles are least-privileged and active
  role state can suspend a claimed operator.
- Supported taxonomy, evidence, free-text length, context, and assignment are
  validated.
- Action IDs are idempotent; each successful action creates one immutable audit
  entry with before/after status.
- Content/account restriction and restoration paths are both tested.
- Failed actions remain pending/failed rather than falsely resolved.
- Users can read only their own non-sensitive action status and submit a
  bounded immutable appeal.
- The original action operator cannot be the sole reviewer of its appeal.
- Oldest-open-case and response-target telemetry is emitted without user
  content or unnecessary personal data.
- Retention cleanup distinguishes expiring evidence from minimum integrity
  audit data.

## Manual staging gates

- Valid release clients exercise every enforced callable.
- A modified/unattested test client is rejected.
- A scheduler interruption and resume is observed in logs/metrics.
- A complete migration dry-run, interrupted apply, resume, rollback, and hash
  verification is rehearsed against a non-production export.
- Operator assignment, case handling, user status, appeal, restoration, and
  audit review are exercised by separate test accounts.

No source commit may claim these production/staging gates passed without the
corresponding environment evidence.
