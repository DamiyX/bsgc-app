# ADR-003: Trusted writes, App Check, and moderation operations

**Status:** accepted for repository implementation; enforcement and production
roles require staged owner approval

**Decision type:** Type 1.5 — the boundary is reversible, but changing it affects
every publishing client and operational workflow

## Context

Braid accepts user-generated group messages, attachments, Insights, comments,
reactions, invitations, and reports. Firestore Rules can authorize document
shape and relationship access, but they cannot provide a durable per-user rate
bucket or safely coordinate all fan-out and audit writes. The current message
rule also reaches Firestore's 1,000-expression evaluation ceiling for a valid
four-part message.

App Check can attest that a request came through a recognized application
installation. It does not authenticate a person, replace authorization, or
prove that a client is benign. Enforcing it before released clients send valid
tokens would block legitimate users.

Reports without a documented queue, action model, audit history, retention
policy, and appeal path are data capture rather than a moderation system.

## Bedrock requirements

- A modified client must not bypass authorization, identity validation, quotas,
  or rate limits.
- A failed trusted write must not be presented as saved.
- Retrying the same client operation must not create duplicate logical content
  or double-apply fan-out/counters.
- Moderation actions must be attributable, reviewable, bounded, and reversible
  where safety permits.
- Operators must not receive broader access than their assigned role requires.
- App Check rollout must preserve a fast rollback path.

## Options considered

### 1. Keep direct client writes and expand Rules

This preserves Firestore's native offline queue, but Rules cannot maintain
durable rate buckets and already exceed their evaluation budget for the
supported message shape. More rule expressions increase cost and create
failures that appear to users as generic permission denials.

### 2. Keep direct writes and add asynchronous abuse cleanup

This keeps latency low, but harmful or high-cost writes exist before cleanup.
Fan-out, notifications, and recipient downloads may already have happened. It
is unsuitable as the primary enforcement boundary.

### 3. Route abuse-prone publishing through trusted callable functions

The callable validates authentication, optional App Check attestation,
authorization, canonical identity, content shape, target visibility, rate and
quota state, and idempotency before one coordinated commit. The client retains
an account-scoped durable outbox and reports success only after server
acknowledgement.

## Decision

Use option 3 for group creation, invite creation/redemption, messages,
message edits/tombstones, attachments/finalization, Insight publishing and
fan-out, comments, reactions, and reports. Firestore Rules deny direct client
creation and message mutation for these
server-authoritative records. Owner-local state that has no shared abuse or
fan-out impact may remain a Rules-authorized direct write.

### Trusted write sequence

1. The client creates a stable operation or document ID and stores its draft in
   the account-scoped outbox when the operation must survive process death.
2. The callable verifies Firebase Authentication and, when enabled for that
   callable/environment, App Check.
3. The server validates bounded input using the same domain contracts used by
   tests and canonicalizers.
4. The server reads authoritative membership, block, target-visibility,
   ownership, canonical-identity, quota, and rate-bucket state.
5. A transaction uses the stable operation ID as its idempotency boundary,
   consumes the rate bucket, and writes the source plus required indexes,
   counters, fan-out, audit, or notification intent.
6. The response returns the canonical record identity and an explicit
   committed/already-committed result.
7. Only then does the client remove the outbox item and show remote success.

Attachment bytes remain in Firebase Storage. A trusted finalize step registers
their canonical managed-asset record before a message may reference the path.

## Rate and quota policy

Buckets are server-owned and use both a short burst window and a longer
sustained window. Limits are action-specific because a reaction, a report, and
an attachment have different cost and harm profiles. Rejections use stable
codes and a retry-after value where retry is appropriate.

Group-count, member-count, attachment byte/type, fan-out, and active-content
caps remain separate from rate limits. Raising a rate limit must never
silently raise a storage or fan-out quota.

Metrics must report action, result, environment, latency, retry status, and
bucket rejection count without logging message, note, report, or appeal
content.

## App Check rollout

1. Add the official client SDK and activate debug providers only in explicitly
   local/debug builds.
2. Use platform production providers in release builds.
3. Deploy callables with enforcement disabled and observe valid/invalid/missing
   token metrics.
4. Enforce one low-risk staging callable, run legitimate and modified-client
   tests, then expand callable by callable.
5. Keep the environment parameter as an audited emergency rollback switch.
6. Enforce production only after the minimum supported clients produce valid
   tokens and the rollback rehearsal succeeds.

Debug tokens are secrets. They must not be committed, logged, embedded in
release builds, or reused as production credentials.

## Moderation operating model

### Roles

- `moderation_reviewer`: read assigned reports and evidence, add internal notes,
  and propose an outcome.
- `moderation_operator`: apply bounded content/account actions and resolve or
  reopen a case.
- `moderation_admin`: manage operator claims and exceptional escalations.

No role may edit immutable audit entries. Custom claims provide coarse access;
server-side role documents provide active assignment, suspension, and scope.

### Case and evidence model

Every report records a supported taxonomy reason, reporter, canonical target
type and ID, target context, visibility proof captured by trusted code,
timestamps, priority, status, and an evidence snapshot limited to what is
necessary for review. Reporter-authored free text is bounded and treated as
untrusted content.

Targets are validated before case creation. A user cannot create a report for
content they cannot access, substitute a target from another group/thread, or
modify a submitted case.

### Actions and audit

Supported actions are explicit and allowlisted: no action, warning, content
restriction/removal, temporary account restriction, permanent disable,
restoration, and escalation. Every action records the case ID, operator UID,
reason code, before/after status, timestamp, and a stable action ID in an
append-only audit collection. Repeating an action ID is idempotent.

Emergency action is still audited. It is not a path around evidence,
authorization, or later review.

### User status and appeal

Affected users receive a non-sensitive reason category, action scope,
effective/expiry time, and an appeal path. Appeals are separate immutable
submissions linked to the case and cannot be reviewed solely by the operator
whose action is appealed.

### Response and retention

Response targets are documented by risk tier and monitored by oldest-open-case
age, not merely case count. Evidence and audit retention are distinct:
unnecessary content snapshots expire; the minimum action audit may be retained
longer for integrity and legal obligations. Exact production periods require
operator/legal approval and must not be invented in client copy.

## Failure modes and recovery

| Failure | Required behavior |
| --- | --- |
| Callable timeout after commit | Retry with the same operation ID returns the committed result. |
| Rate store unavailable | Fail closed for the shared write and preserve the client draft. |
| App Check provider outage | Use the audited per-environment rollback switch; do not weaken Auth or Rules. |
| Fan-out partially fails | Source transaction records resumable fan-out state; workers reconcile idempotently. |
| Moderator action fails midway | The action remains pending/failed with no false resolved state and can resume by action ID. |
| Evidence target is deleted | Preserve only the policy-approved evidence snapshot and show the source as unavailable. |

## Consequences

- Shared publishing depends on callable availability; the durable outbox and
  retry-after contract become essential user-experience infrastructure.
- Direct Firestore latency may increase slightly, while abuse resistance,
  observability, idempotency, and rule simplicity improve.
- App Check reduces automated abuse from unrecognized clients but does not
  remove the need for authentication, authorization, content validation, rate
  limits, or moderation.
- Moderation introduces privileged operational data and therefore requires
  access review, alerting, retention controls, and an owner-run operating
  process before broad public launch.

## Verification and rollout gate

- Contract tests accept every supported maximum shape, including a four-part
  message, and reject forged identity, context, asset, and target references.
- Emulator tests prove direct client writes are denied and owner/operator reads
  are least-privileged.
- Concurrency tests prove operation IDs, buckets, counters, and fan-out are
  idempotent.
- A staging client with valid App Check succeeds; missing/invalid tokens fail
  only after enforcement is deliberately enabled.
- Scheduler tests drain more than 1,000 eligible records without a batch above
  500 writes and expose backlog age.
- Moderation tests cover assignment, role denial, action/retry, immutable audit,
  restoration, and independent appeal review.
- Rollback rehearsals cover App Check enforcement, callable client rollout, and
  moderation action restoration.

This ADR authorizes source implementation and local/emulator verification. It
does not authorize production claims, operator assignment, App Check
enforcement, migration, deployment, or moderation action against real users.
