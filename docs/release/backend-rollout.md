# Backend rollout and migration

## Stop conditions

Do not deploy if a production export is missing, emulator rule tests fail, the migration dry-run contains unresolved ownership guesses, App Links placeholders remain, or rollback ownership is unclear.

## Staged order

1. Record project ID, deployed Functions, rules, indexes, Storage rules, App Check state, and minimum client version.
2. Export Firestore and Storage; record timestamp, location, checksum, and restore owner.
3. Run migration dry-run against an authorized read-only view and review counts/exceptions.
4. Run Functions unit tests and Firestore/Storage Emulator tests.
5. Deploy additive indexes and wait until ready.
6. Deploy compatible Functions, including managed-asset finalization and
   cleanup workers, but leave new scheduled reconciliation disabled.
7. Apply the idempotent v2 migration in bounded batches; retain the report and
   confirm every private-media reference is either a canonical Storage path or
   an explicitly measured legacy exception.
8. Deploy v2 Firestore and Storage rules. Do not deploy these rules before the
   compatible Functions and managed-asset records exist: new message writes
   intentionally require the server-validated asset contract.
9. Release the v2 client to internal testers, then enable scheduled managed
   media and account-deletion reconciliation.
10. Observe authorization denials, Function errors, notification failures, invite redemption, and deletion.
11. Enable App Check enforcement only after valid clients and authorization tests are stable.

## Rollback

- Stop the client rollout and Functions triggers.
- Restore the previous compatible rule set only if doing so does not re-open a known authorization vulnerability.
- Restore data from the named export or apply the migration’s before-value report.
- Never “fix” rollout failures by deploying permissive allow-all rules.

## External actions

Production export, deployment, migration apply, App Check enforcement, certificate fingerprints, Apple Team ID, DNS/hosting, secrets, and store-console declarations require authorized owner access and are not completed by source changes.
