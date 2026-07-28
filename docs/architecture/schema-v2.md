# Braid schema version 2

## Invariants

- Public identity, private account data, device tokens, and per-user state are separate.
- Group membership and ownership change only through trusted Functions.
- A group message is immutable except for the author’s 15-minute edit window and author tombstone.
- Personal star, hide, clear, mute, read, saved, seen, and reaction state does not mutate shared content.
- Contacts Insight access requires an accepted author-viewer connection and no block in either direction.
- Raw invite tokens are returned once; Firestore stores only a SHA-256 token hash.
- Every client list query is audience-scoped and bounded or cursor-paginated.

## Collections

### `users_public/{uid}`

Known-document identity lookup. Fields: `schemaVersion`, `uid`, `displayName`, optional `photoUrl`, optional `bio`, `createdAt`, `updatedAt`. Client list is denied.

### `users_private/{uid}`

Owner-only account record. Includes email, optional verified-phone migration fields, consent/onboarding flags, notification/storage preferences, and deletion state.

### `users/{uid}/devices/{deviceId}`

Owner-only per-installation FCM token and notification category/preview preferences. Invalid tokens are removed by Functions.

### `users/{uid}/connections/{otherUid}`

Owner-readable accepted relationship created by trusted invite redemption. This is not a public follower graph.

### `users/{uid}/group_state/{groupId}`

Owner-only `clearedBefore`, `lastReadAt`, `mutedUntil`, and nested hidden/starred message pointers.

### `groups/{groupId}`

Explicit `ownerId`, member IDs, lifecycle (`scheduled`, `active`, `completed`, `archived`), study definition, dates, personal progress maps, and bounded summary fields. Membership changes are server-only.

### `groups/{groupId}/members/{uid}`

Role/lifecycle record for audit and migration. The group document is the rules membership authority for the MVP.

### `groups/{groupId}/messages/{messageId}`

Stable client-generated document ID; `space` is `reflection`, `discussion`, or `prayer`; up to four bounded text/voice/image parts; server timestamp; author identity; optional reply pointer. Video/doc parts are deferred.

### `insights/{insightId}`

Author-owned contacts reflection with explicit audience/status/expiry. Comments and one-document-per-user reactions are nested; seen state and feed pointers live under each viewer.

### `reports/{reportId}` and `users/{uid}/blocks/{blockedUid}`

Client-created immutable report and owner-only block state. Moderator read access requires a custom token claim.

### `group_invites/{tokenHash}`

Server-managed expiring/revocable invite state. A transaction enforces use count, capacity, blocks, membership, and connection creation.

## Storage

- `users/{uid}/profile/{assetId}`
- `groups/{groupId}/covers/{assetId}`
- `groups/{groupId}/messages/{messageId}/{assetId}`

Rules enforce owner/member relationship, type, size, immutable paths, and matching custom metadata. Message outbox retries use deterministic asset names to avoid duplicate uploads.

## Compatibility

Legacy `users/{uid}` remains owner-only during migration. Models accept carefully bounded v1 defaults, while all new writes use `schemaVersion: 2`. Remove compatibility only after migration reports show zero remaining v1 records and the minimum supported app version is v2.
