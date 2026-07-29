# Braid remediation final handoff

**Finalized:** July 29, 2026

**Review branch:** `codex/bsgc-full-remediation`

**Source audit:** `docs/audit/`

**Authoritative phase ledger:** `docs/implementation-progress.md`

**Preview instructions and AI prompt:** `docs/testing/branch-preview-guide.md`

## Current state

The repository-side remediation described in the original six audit reports has been implemented to the point supported by source code and local automated verification. The branch is intended for review and Android preview before any merge to the default branch.

It must not yet be described as production-ready. Production migration, backend deployment, signing, association files, legal/store configuration, and physical-device regression require owner credentials or human verification.

No Firebase production deployment or production migration was performed as part of this remediation.

## What changed

### Security, privacy, and backend contracts

- Added a documented schema-v2 boundary for public identity, private account data, per-device notification state, groups, membership, messages, private notes, Insights, comments, reactions, invites, reports, blocks, and private per-user state.
- Rewrote Firestore and Storage Rules with explicit ownership, membership, type, size, path, transition, and field controls.
- Moved privileged group, invitation, lifecycle, publication, moderation, and account-deletion actions behind Cloud Functions.
- Added opaque invite tokens, accepted contact relationships, contacts-only Insight access, reports, blocks, cleanup jobs, and dry-run-first migration tooling.
- Added deterministic Functions and Emulator Suite coverage.

### Offline reliability and media

- Added cached avatar/group-cover components with deterministic local fallbacks, addressing the reported blank profile/icon/cover experience without internet.
- Added persistent, account-scoped message and reflection drafts.
- Added stable message IDs and a persistent outbox with queued, sending, sent, failed, retry, and discard behavior.
- Moved supported media toward Storage-backed, bounded files with idempotent paths and recoverable state.
- Added sign-out cleanup for private drafts, outbox state, memory images, and cached network media.

### Product and UI/UX

- Reframed primary navigation around Today, Groups, Journal, and Me.
- Reframed study rooms around Plan, Reflections, Discussion, and Prayer.
- Made sharing audience explicit: Only me, Study contacts, or a selected Study group.
- Added lifecycle-aware study states, progress, recap, moderation, privacy, notification, storage, and account controls.
- Replaced misleading or incomplete surfaces with supported behavior or intentional deferral.
- Added semantic design documentation, light/dark theme tokens, responsive layouts, labels, tooltips, and safer empty/loading/error/offline states.

### Notifications, scale, release, and repository hygiene

- Added per-device notification preferences, privacy-safe previews, per-study mute, routing, invalid-token cleanup, and bounded feeds.
- Added cleanup/rate-limit contracts for high-risk server actions.
- Removed tracked APKs, generated `node_modules`, caches, logs, patch scripts, redundant assets, and unused dependencies.
- Added reproducible lockfiles, quality CI, a manually triggered signed-Android workflow, release signing templates, minimized permissions, and release shrinking.
- Replaced the template README and added architecture, product, design, testing, rollout, and release documents.

## Verification completed

The final local checks produced:

- Dart format check: 59 files, 0 changes required;
- Flutter analysis: no issues;
- Flutter tests: 4 passed;
- Functions dependency restore: `npm ci` passed;
- Functions syntax checks: passed;
- Functions contract/migration tests: 21 passed;
- Firestore/Storage Rules Emulator tests: 26 passed;
- generated dependencies tracked by Git: 0;
- tracked APKs: 0.

The full rules command now sets `--test-concurrency=1`. Both rules files use the same emulator project and clear test state; running their files concurrently created a nondeterministic cleanup race even though each focused suite passed.

## Release-build evidence

Windows Developer Mode was enabled, a repository-local Flutter SDK and Android command-line SDK were configured under ignored `.tooling/`, Android licenses were accepted, and the Android toolchain passed `flutter doctor`.

A full R8/resource-shrunk Android App Bundle build was attempted. It remained CPU-intensive for an unacceptable period and caused severe laptop lag, so it was terminated. No release AAB or trustworthy size report was produced.

This does not invalidate the Dart, Flutter test, Functions, or rules results. It leaves native release packaging and app-size analysis as an explicit open release gate. The manual GitHub workflow can perform the signed build once the four Android signing secrets are configured.

## Remaining required review

### Android preview

Use `docs/testing/branch-preview-guide.md`. At minimum verify:

1. first launch, sign-in, onboarding, and navigation;
2. Today, Groups, Journal, and Me at representative phone widths;
3. cold and warm launch with airplane mode;
4. cached and uncached avatars/covers;
5. offline text/image/voice queue, restart, retry, and discard;
6. study lifecycle, progress, ownership, member actions, recap, and archive;
7. invitations across sign-in/onboarding;
8. contacts-only Insight visibility, block, report, comment, and reaction behavior;
9. notification opt-in, mute, privacy preview, and deep routing;
10. sign-out/account-switch cache isolation;
11. TalkBack, 100/150/200% text, focus order, contrast, and touch targets.

### Backend compatibility

The Flutter client and backend contract changed together. A UI-only run can start with the checked-in Firebase client configuration, but full functional testing against an old deployed backend can fail because the new Functions, indexes, and rules may not be live.

Before a staged backend preview:

1. export the deployed Firebase state;
2. back up Firestore and Storage;
3. run the migration in dry-run mode;
4. review the report and legacy media findings;
5. follow `docs/release/backend-rollout.md`;
6. deploy only to an approved development/staging project first;
7. never apply the migration to production merely to make an emulator preview work.

### Release and production

- configure an upload keystore outside Git;
- set GitHub signing secrets;
- replace association placeholders with the real Android certificate fingerprint and Apple Team ID;
- verify App/Universal Links on physical devices;
- run the signed AAB workflow and inspect the size report;
- complete closed-track QA;
- approve legal, privacy, retention, UGC, moderation, deletion, and store declarations;
- configure monitoring, alerts, backups, and incident ownership.

## Review outcome

Compared with the audited baseline, this branch has substantially stronger authorization boundaries, offline behavior, chat durability, product structure, accessibility foundations, notification privacy, release hygiene, and test coverage.

The correct next milestone is review—not immediate production merge. Confirm the Android experience, log reproducible defects, fix verified blockers on this branch, rerun automated checks, and then decide whether it should replace the current default branch.
