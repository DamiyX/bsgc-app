# ADR-001 — Security and Data Contract Migration

**Status:** Accepted for implementation
**Date:** 2026-07-28
**Decision type:** Type 1

## Context

Braid currently combines public profile fields, phone numbers, notification tokens, referrals, and account state in globally readable `users/{uid}` documents. Group authority is inferred from the first entry of a mutable member array. Clients can mutate group membership and content fields directly, and the existing rules do not enforce the product's contacts-only Insight audience.

The product must remain usable during a staged migration, but preserving compatibility cannot mean preserving unsafe authorization.

## Bedrock requirements

1. A caller may read or mutate only data explicitly authorized for that identity and resource.
2. Phone numbers, device tokens, consent, and deletion state are private.
3. Group ownership and role changes are authoritative and atomic.
4. Contacts-only Insights are readable only through an accepted connection with the author.
5. Client-controlled identity, membership, counters, and timestamps are not authoritative.
6. Migration must be resumable, observable, and reversible before destructive cleanup.

## Options considered

### Option A — Hard cutover in the existing collections

Replace rules and documents in place, then require every client to update immediately.

- Benefit: least duplicate data.
- Cost: high outage and data-corruption risk; old clients fail abruptly.
- Decision: rejected.

### Option B — Versioned contract in the existing Firebase project

Introduce private/public/device boundaries, explicit member records, connections, reports, and per-user state while retaining only narrowly defined legacy reads during migration. Use idempotent Admin SDK tooling, compatibility readers, staged rules, and a measured cleanup gate.

- Benefit: safe, incremental, and affordable for the MVP while preserving a route to scale.
- Cost: temporary dual-read/dual-shape complexity and a carefully sequenced deployment.
- Decision: selected.

### Option C — New Firebase project and complete data re-import

Build the secure model in a separate project and migrate users/data during a scheduled cutover.

- Benefit: strongest environmental isolation and simplest final backend.
- Cost: authentication migration, downtime risk, operational overhead, and a much larger launch project.
- Decision: reserved as a contingency if deployed-state inspection reveals unrecoverable contamination.

## Selected boundaries

- `users_public/{uid}`: minimal member-visible identity.
- `users_private/{uid}`: account owner and trusted server only.
- `users/{uid}/devices/{deviceId}`: private per-installation notification state.
- `groups/{groupId}`: safe group metadata and immutable `ownerId`.
- `groups/{groupId}/members/{uid}`: explicit role and membership lifecycle.
- `groups/{groupId}/messages/{messageId}`: immutable sender/content contract plus authorized tombstone fields.
- `groups/{groupId}/member_state/{uid}`: private clear/read/progress state.
- `users/{uid}/connections/{otherUid}`: two symmetric, server-written
  relationship records; each side can read only its own accepted connections.
- `insights/{insightId}`: author-owned content with explicit audience.
- `insights/{insightId}/reactions/{uid}` and comment reaction subcollections: one reaction per eligible user.
- `users/{uid}/saved_insights/{insightId}`: owner-only bookmark reference.
- `blocks/{blockId}` and `reports/{reportId}`: safety controls with restricted visibility.
- `invites/{tokenHash}`: server-managed, expiring, revocable invitation.

## Migration sequence

1. Capture deployed state and backup production data.
2. Deploy additive indexes/Functions that can write the new shape.
3. Backfill new documents in dry-run, apply, and verify modes.
4. Release a client that reads new data and performs privileged writes through server operations.
5. Deploy restrictive rules and Storage rules.
6. Observe denials, errors, and migration coverage.
7. Remove legacy sensitive fields only after verified client adoption.

## Failure and rollback

- Migration writes are idempotent and never delete legacy fields in the first pass.
- Every run produces counts, skipped records, validation failures, and proposed writes.
- Rules deployment is versioned and reversible independently of data backfill.
- If group ownership is ambiguous, the migration reports the group and makes no authority-changing guess.
- If a public profile cannot be safely derived, it is omitted until the account owner repairs it.

## Consequences

This adds temporary implementation complexity, but it contains the highest-risk authorization failures without forcing a dangerous one-time rewrite. It also creates stable boundaries for invitations, offline caching, account deletion, notifications, and scale work that follow.
