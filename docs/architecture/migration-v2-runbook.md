# Version 2 migration runbook

The canonical invite collection is `invites/{tokenHash}`. `group_invites` is a
legacy migration source only. A successful migration copies a valid legacy
invite to `invites`, captures both before-images, and removes the legacy
document. An existing destination is quarantined for manual reconciliation
instead of being overwritten.

## Safety contract

- Dry-run is the default. It writes only a local checkpoint and a content-free
  report.
- Apply mode requires `--apply`, replaces canonicalized documents rather than
  merging legacy fields, and persists its run/checkpoint at
  `_migration_runs/{runId}`.
- Pages are ordered by full Firestore document path. Page size is at most 500,
  write batches are at most 400, and transform concurrency is at most 16.
- A source cursor advances only after every bounded write for that source
  document succeeds. Repeating an interrupted page is safe.
- Apply data and its checkpoint/count update commit in one Firestore batch.
  A five-minute renewable run lease rejects concurrent owners; an abandoned
  lease can be taken over after expiry.
- Apply mode writes the first before-image for every target to a mode-0600
  JSONL artifact before changing it. Firestore timestamps, bytes, geo-points,
  and document references use explicit tagged encodings.
- Reports contain path hashes, serialized lengths, field counts, error codes,
  and field names. They never contain note, message, Insight, profile, or invite
  content.

Treat the before-image artifact as sensitive user data. Put it on an encrypted,
access-restricted volume, copy it to the approved encrypted backup location,
verify that the copy can be read, and apply the project's retention/deletion
policy after the rollback window. A managed Firestore export immediately
before apply is an additional recovery layer, not a replacement for testing
this document-level restore.

## Staging sequence

From `functions/`:

```text
node scripts/migrate-v2.js --rehearse --run-id staging-rehearsal --report ./artifacts/staging-rehearsal.json
node scripts/migrate-v2.js --project <staging-project> --run-id <run-id> --report ./artifacts/dry-run.json
node scripts/migrate-v2.js --project <staging-project> --run-id <run-id> --apply --artifact <encrypted-path>/before-images.jsonl --report ./artifacts/apply.json
```

Review all quarantined records before apply. Use a fresh run ID when moving
from dry-run to apply because run mode is immutable. To resume an interrupted
apply, repeat the exact apply command with the same run ID and artifact path.

Rollback in staging:

```text
node scripts/migrate-v2.js --project <staging-project> --run-id <run-id> --rollback <encrypted-path>/before-images.jsonl --apply --report ./artifacts/rollback.json
```

The executable rehearsal injects a failure after a committed batch, resumes
from the persisted cursor, restores changed documents, removes documents
created by migration, and fails unless the final fixture dataset exactly
matches its starting state.

## Release evidence

Keep the content-free dry-run/apply/rollback reports, the managed-export
identifier, aggregate counts, issue disposition, and the rehearsal result.
Do not attach the before-image artifact to tickets, chat, logs, or reports.
