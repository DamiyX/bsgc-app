# Braid Full Remediation — Implementation Progress

**Source audit:** `docs/audit/`
**Implementation branch:** `codex/bsgc-full-remediation`
**Started:** 2026-07-28
**Status:** In progress

This is the durable execution ledger for the full audit remediation. A phase is marked complete only after its repository changes and available automated checks pass. Deployment-only or account-owner actions remain explicitly separated from repository implementation.

## Verification baseline

- [x] Audit documents reconciled with commit `777e266`.
- [x] Remote audit branch fetched and confirmed current at `d8b5710`.
- [x] Clean implementation branch created from the audit branch.
- [x] Existing workspace build memory reviewed.
- [ ] Flutter/Dart static analysis available.
- [ ] Firebase Emulator rule tests available.
- [ ] Android release build environment available.
- [ ] Deployed Firebase state captured.
- [ ] Production backup captured before migration.

## Phase status

| Phase | Scope | Status | Evidence |
| --- | --- | --- | --- |
| 0 | Baseline, governance, repository hygiene, CI, release configuration | In progress | Working branch and ledger created |
| 1 | Security, privacy, schema, rules, migrations, rule tests | In progress | Threat model and current paths revalidated |
| 2 | Invitations, onboarding, connections | Not started | — |
| 3 | Group lifecycle and administration | Not started | — |
| 4 | Reliable chat, outbox, media | Not started | — |
| 5 | Offline media and session hygiene | Not started | — |
| 6 | Reflection-centered product and UI | Not started | — |
| 7 | Accessibility | Not started | — |
| 8 | Notifications and backend scale | Not started | — |
| 9 | Bible, backup, deferred features | Not started | — |
| 10 | Size, release, policy, store readiness | Not started | — |

## Phase 0 checklist

- [x] Confirm audited baseline and branch divergence.
- [x] Create isolated implementation branch.
- [ ] Capture deployed Firestore rules, indexes, Functions, Storage rules, and Firebase environment.
- [ ] Back up production data.
- [ ] Establish canonical Android application ID and domain in repository documentation.
- [ ] Configure production signing without committing secrets.
- [ ] Add CI for format, analyze, tests, rules, Functions, and release AAB.
- [ ] Replace template README with setup/build/release documentation.
- [ ] Stop tracking generated dependencies, APKs, logs, and temporary scripts.
- [ ] Add versioned schema, product, design, and release documents.

## Phase 1 checklist

- [ ] Add and document schema version 2.
- [ ] Split public, private, and per-device user data.
- [ ] Add explicit group owner, lifecycle, roles, and member records.
- [ ] Define immutable message content and private per-user state.
- [ ] Define and enforce contacts-scoped Insight audience.
- [ ] Add blocks, reports, and moderation state.
- [ ] Rewrite Firestore rules with allowlisted fields, types, lengths, ownership, and transitions.
- [ ] Rewrite Storage rules with ownership/membership/type/size/path controls.
- [ ] Add Firestore and Storage Emulator tests for allowed and denied paths.
- [ ] Add idempotent dry-run/apply migration tooling and rollback report.
- [ ] Add staged compatibility/deployment runbook.
- [ ] Add App Check configuration only after rules are proven.

## External action register

These actions cannot be truthfully completed from source code alone:

1. Export deployed Firebase state and production data using an authorized project identity.
2. Supply the production upload-signing certificate fingerprint for Android App Links.
3. Configure production signing material in local/CI secret storage.
4. Publish canonical-domain association files and verify them over HTTPS.
5. Deploy rules, indexes, Functions, Storage rules, and migrations after review.
6. Create store-console privacy/data-safety declarations and moderation operations.

## Change discipline

For every implementation slice:

1. State the current failing contract.
2. Add the smallest meaningful regression or contract test.
3. Prove the test fails when the environment permits.
4. Implement the repository change.
5. Run focused verification, then broader verification.
6. Record remaining environment or deployment gaps here.
7. Commit a coherent verified slice; do not push until the final external-action gate.
