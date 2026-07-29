# ADR-002: Managed media and deletion lifecycle

**Status:** accepted for repository implementation; deployment requires staged
review
**Decision type:** Type 1.5 — privacy-sensitive and only partly reversible

## Context

Private group media is currently uploaded to rule-protected Firebase Storage
paths, but some client records retain Firebase download URLs. A download URL is
a bearer capability: possession of the token can bypass the membership check
that protected the original SDK request. Deleting a Firestore record also does
not automatically delete its Storage object, and deleting an object cannot
erase copies already downloaded to another device.

Account deletion currently performs large unbounded queries and destructive
work inside one callable. A timeout can leave an ambiguous partially deleted
account after some media references have already been lost.

## Options considered

1. Keep download URLs and document their limitation. This is compatible but
   does not provide credible membership revocation for private media.
2. Rotate download tokens on membership changes. This creates fan-out,
   coordination, and race problems and still relies on bearer URLs.
3. Persist canonical Storage paths, read private media through the authenticated
   Storage SDK, and run destructive cleanup from durable lifecycle records.

## Decision

Use option 3 for all new private group media. Legacy HTTPS media remains
read-compatible only while migration identifies it; it is never considered a
managed or revocable asset.

### Canonical asset record

Every managed object must have server-readable metadata containing:

- schema version;
- bucket and canonical object path;
- owner UID;
- owning entity type and ID;
- group ID where authorization is group-scoped;
- MIME type and byte size;
- created and updated timestamps;
- lifecycle status: `pending`, `committed`, `delete_pending`, `deleted`, or
  `failed`;
- optional checksum and last error/attempt metadata.

The Storage object metadata must repeat the minimum identity fields needed for
rules/event validation. A client-provided HTTPS URL is not asset identity.

### Upload and replacement

1. Allocate a deterministic, entity-bound object path.
2. Upload an immutable pending object with matching owner/entity metadata.
3. Create or update its asset record as pending.
4. Commit the owning Firestore record using the canonical path.
5. Mark the new asset committed.
6. Mark the replaced object `delete_pending`.
7. An idempotent worker deletes the old object, then marks it deleted.

A retry may repeat any phase without creating a second logical asset or
double-applying a counter.

### Rendering and authorization

- Private group covers, images, and audio are fetched using a Firebase Storage
  reference while the user is authenticated.
- Storage Rules remain the read authority and re-check current membership.
- Arbitrary HTTPS URLs render as explicit external links only. They do not
  auto-render as trusted images or audio.
- Public profile media may use a separate explicitly public policy; it must not
  silently inherit the private-group promise.

### Deletion jobs

Account and owning-entity deletion is a resumable job:

1. freeze the account/entity and persist job state;
2. validate ownership-transfer prerequisites;
3. page through memberships and authored content;
4. anonymize or tombstone content whose conversation history must remain;
5. enqueue managed assets for deletion while their canonical paths still
   exist;
6. reconcile reciprocal counters and pointers idempotently;
7. remove private/public profile data;
8. delete the authentication identity only after all required phases finish;
9. persist completion evidence that does not contain deleted private content.

Each phase records a cursor, attempt count, timestamps, and stable run ID.
Starting the callable again returns or resumes the same job.

## Revocation truth

| Event | New managed private media | Legacy token URL | Already downloaded/cached copy |
| --- | --- | --- | --- |
| User leaves/is removed | The authenticated SDK request is denied as soon as membership authority changes. | May remain readable until the object/token is removed; migration must measure this. | Cannot be remotely erased. |
| Message/group/account deletion | Access ends after the lifecycle worker deletes the object; UI shows deletion as pending until then. | Access is not promised to end before measured object deletion. | Cannot be remotely erased. |
| Cover/profile replacement | The new reference commits first; the previous asset is then deleted idempotently. | Old token may work until deletion completes. | Cannot be remotely erased. |

Product and privacy copy must say that access is removed from Braid, not that
copies another recipient already downloaded are destroyed.

## Consequences

- Private media rendering needs an authenticated Storage-backed cache rather
  than a generic network-image URL.
- Offline access remains possible only for a previously authorized,
  account-scoped cached copy and must be cleared on sign-out.
- Legacy URL migration is required before claiming complete revocation.
- Lifecycle documents add writes and operational monitoring, but prevent lost
  cleanup references and make retries observable.

## Verification and rollout gate

Before deployment:

1. Rules tests must prove outsider/removed-member reads fail.
2. Contract tests must reject traversal, cross-entity paths, and arbitrary URLs
   as managed media.
3. Worker tests must prove idempotent resume and that media paths are retained
   until deletion succeeds.
4. A staging test must copy the old reference before leave/removal/delete and
   record when access stops.
5. Migration dry-run must count every legacy token URL.

This ADR authorizes repository implementation only. It does not authorize a
production rules, Functions, migration, or Storage deployment.
