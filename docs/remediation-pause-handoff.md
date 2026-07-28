# Braid remediation pause and remaining-work handoff

**Paused:** July 28, 2026  
**Working branch:** `codex/bsgc-full-remediation`  
**Git state at pause:** local and uncommitted; nothing had been pushed at the time of the pause
**Current preservation action:** this paused state is now being committed and pushed to the dedicated remediation branch; no merge to the default branch is intended.
**Source audit:** `docs/audit/`  
**Implementation ledger:** `docs/implementation-progress.md`

## Executive status

The work is intentionally paused at the user's request.

- Estimated repository implementation: **about 88%**
- Estimated verification and release readiness: **about 68%**
- Estimated total remediation completion: **about 78%**

This is not honestly at 95% yet. Most major implementation is present, but a
large cross-platform change cannot be called 95% complete before Flutter
compilation, static analysis, widget tests, Firebase Rules Emulator tests, and
a release build have run. Those toolchains are not currently installed or
available on this machine.

## Alignment with the original six audit documents

The work remains aligned with `docs/audit/01-product-and-system-understanding.md`
through `docs/audit/06-implementation-plan.md`. New work was added only where
the implementation exposed a concrete security, privacy, reliability, or
production-readiness gap. The phase status is:

| Original phase | Alignment at pause |
| --- | --- |
| Phase 0 — baseline/release governance | **Partial.** CI, README, schema/product/design/release docs, permissions, shrinking, and signing structure exist. Deployed-state export, production backup, lockfile refresh, clean-build proof, and default-branch decision remain external or unverified. |
| Phase 1 — security/data contract | **Mostly implemented.** Versioned boundaries, rules, Storage controls, callable authority, migration tooling, account lifecycle, reports, blocks, and tests exist. Emulator execution, staged production migration, backup, and App Check enforcement remain. |
| Phase 2 — invitations/onboarding | **Mostly implemented.** Opaque invites, QR/share flow, canonical links, continuation state, capacity, accepted connections, and no global directory download exist. Real certificate/Team ID association verification and production hosting remain. Phone-book discovery stays intentionally deferred as the audit recommended. |
| Phase 3 — group lifecycle | **Mostly implemented.** Lifecycle, topic progress, owner/member administration, dates, room subscriptions, recap, archive, extension, and FAQ alignment exist. Focus/book editing after creation is intentionally not exposed because the old UI never persisted it; implement a server-authoritative focus-edit flow only if that remains a product requirement. |
| Phase 4 — reliable chat/outbox | **Mostly implemented.** Controller separation, drafts, stable IDs, queue states, retries, cursor paging, clear-before state, supported message spaces, media caps, and hidden unsupported attachments exist. Flutter compilation, emulator tests, real-device retry tests, and visible upload-progress verification remain. |
| Phase 5 — offline media/session hygiene | **Mostly implemented.** Shared fallbacks, cached media, bounded decode sizes, account-scoped outbox/drafts, sign-out cleanup, and explicit startup/error states exist. Device airplane-mode, cache-isolation, and warm/cold verification remain. |
| Phase 6 — reflection-centered UI | **Mostly implemented.** Today/Groups/Journal/Me, Plan/Reflections/Discussion/Prayer, explicit audiences, contacts feed, private notes, safety/settings, semantic colors, and async states exist. Composer component sharing, final legacy-screen polish, and visual review remain. |
| Phase 7 — accessibility | **Partial.** Semantics, tooltips, fallback labels, larger controls, dynamic layouts, dark mode, and reduced-motion-safe dependencies were addressed. 200% text, TalkBack order, keyboard/focus, contrast, RTL, and media-announcement testing remain. |
| Phase 8 — notifications/scale | **Mostly implemented.** Per-device preferences, permission UX, routing, bounded feeds, invalid-token cleanup, cleanup jobs, rate-limited publishing/reporting, and connection limits exist. Comment/reaction/message abuse limits, metrics/alerts, load tests, and production observability remain. |
| Phase 9 — Bible/backup/deferred features | **Bible and deferrals implemented.** KJV/WEB initialization and honest availability are corrected; backup/video/documents remain intentionally deferred until their safety contracts exist. |
| Phase 10 — size/release | **Mostly implemented.** Large assets/APKs and unused dependencies were removed, release shrinking/signing structure and CI were added, and permissions were reduced. A release AAB size report, lockfile, store QA, association verification, legal publication, and production signing remain. |

This means the remediation follows the original plan, but it does not falsely
mark external or toolchain-dependent acceptance criteria as complete.

The worktree currently contains:

- 75 tracked paths modified or deleted;
- 35 untracked implementation/documentation paths;
- 10,310 inserted lines and 10,781 removed lines across tracked text changes;
- no commit or push had occurred at the pause boundary.

## Stop boundary

No new feature or remediation work should begin from this point until the user
asks to resume.

The next session must first:

1. read this file;
2. confirm the current branch is `codex/bsgc-full-remediation`;
3. preserve all existing uncommitted work;
4. run the verification sequence below;
5. fix only failures revealed by that sequence before opening new scope.

At the pause boundary, do not resume feature work, merge, deploy, migrate
production data, install tooling, or change external Firebase/GitHub state. The
current request authorizes only preserving this paused state in the dedicated
GitHub branch.

## Major implementation already completed

### 1. Security and data boundaries

- Added an explicit schema-v2 contract for public users, private users,
  per-device tokens/preferences, groups, group members, messages, notes,
  Insights, comments, reactions, invitations, reports, blocks, and private
  per-user state.
- Split public identity from private account/contact fields.
- Rewrote Firestore Rules with field allowlists, data types, lengths,
  ownership, audience, group membership, lifecycle, and timestamp checks.
- Rewrote Storage Rules for profile images, group covers, and group-message
  media with ownership/membership, type, size, and path checks.
- Made study creation, invitation creation/redemption, membership
  administration, Insight publication, reporting, lifecycle administration,
  and account deletion server-authoritative Cloud Functions operations.
- Added opaque high-entropy invitation tokens; only token hashes are stored.
- Added callable abuse limits for invitations, Insight publication, and
  reports.
- Added a 500-contact limit contract and server-maintained connection counts.
- Added contacts-only Insight authorization and per-user feed pointers.
- Added block and report controls.
- Added recent-authentication enforcement for permanent account deletion.

### 2. Migration and lifecycle

- Added dry-run-first, idempotent schema-v2 migration tooling.
- Added migration report generation and explicit unsafe-record reporting.
- Added migration support for users, private/public profiles, devices, notes,
  saved Insight pointers, connections, groups, members, messages, and Insights.
- Legacy inline voice/image records are reported instead of being silently
  retained in Firestore.
- Added scheduled group activation/completion.
- Added study extension limits and completed-study reactivation.
- Added scheduled cleanup for expired invitations, expired Insight feed
  pointers, old notification event records, old rate-limit records, and
  abandoned message-media uploads.

### 3. Offline and media behavior

- Added cached-network avatar and cover components with deterministic local
  fallbacks, addressing the reported blank-offline-icons/profile-image issue.
- Removed direct dependence on remote images for basic identity rendering.
- Added a persistent per-user/per-group message outbox.
- Added stable message IDs and idempotent media paths.
- Added local attachment persistence, upload retry, failure, discard, and
  outbox recovery states.
- Added image and voice size/duration limits.
- Rebuilt voice playback to support HTTPS and local file URIs with progress,
  speed controls, and accessibility semantics.
- Added persistent reflection drafts.
- Cleared private drafts, outbox data, image memory, and cached network media
  during sign-out.

### 4. Study and reflection product experience

- Rebuilt the main navigation around Today, Groups, Journal, and Me.
- Added explicit audiences: Only me, Study contacts, and a selected Study
  group.
- Added a reflection-centered Today screen and one-tap return to the next
  study.
- Rebuilt the study room around Plan, Reflections, Discussion, and Prayer.
- Added lifecycle-aware read-only states for scheduled/completed studies.
- Added chapter/topic progress, pinned Scripture, and completed-study recap.
- Removed misleading message actions and unsupported social behavior.
- Rebuilt profile presentation around identity, study contacts, private notes,
  and saved reflections instead of vanity engagement statistics.
- Rebuilt study details around supported actions only. The previous screen
  appeared to change the Bible book without persisting that change; that
  misleading control has been removed.
- Rebuilt private-note and contacts-Insight composers with clear audience
  explanations and bounded input.
- Rebuilt the sign-in foyer with responsive layout, failure handling, privacy
  language, and legal links.

### 5. Notifications and privacy

- Added per-device master, study-message, contacts-Insight, and lock-screen
  preview preferences.
- Lock-screen content preview is off by default.
- Added per-study mute controls.
- Added invalid-token cleanup and notification preference filtering.
- Added message and Insight routing from notification payloads.
- Stopped requesting notification permission without context.
- Added an in-app explanation and explicit Enable action before the OS
  permission prompt.

### 6. Safety and account deletion

- Added block, report, remove-member, transfer-ownership, leave-study, archive,
  and permanent account-deletion flows.
- Account deletion now removes private user data, public profile, authentication
  record, authored Insights, reciprocal contact records, authored reactions,
  inbound block records, invitations, user-owned group-message media, and user
  storage.
- Shared messages are tombstoned instead of destroying other members'
  conversation history.
- Shared-study ownership must be transferred before deletion.

### 7. Bible and deferred features

- Corrected Bible initialization so bundled translations are actually ready
  before use.
- Made KJV and WEB the only advertised bundled/offline translations.
- Removed placeholder ESV/BBE files and silent translation substitution.
- Removed broken/dead backup and support-chat implementations instead of
  presenting functionality that did not exist.

### 8. Size, platform, and release work

- Removed eight tracked APK binaries from the deploy folder.
- Removed a 6.85 MB redundant icon and unused/placeholder assets.
- Reduced the principal app/splash image sizes.
- Removed unused Flutter dependencies.
- Enabled Android release shrinking/obfuscation and resource shrinking.
- Removed debug-signing fallback from release builds.
- Added an external signing configuration example without secrets.
- Reduced Android permissions to Internet and microphone.
- Removed unused Android intent queries and unsafe/unneeded media/contact
  permissions.
- Added canonical HTTPS join-link handling.
- Added iOS Associated Domains configuration and corrected iOS privacy reasons.
- Restricted iPhone orientation to the supported portrait experience.
- Added CI definitions for quality checks and signed Android AAB release builds.
- Added release, architecture, product, design, testing, and rollout documents.
- Replaced the template README.
- Removed direct APK downloads from the public website.
- Added website privacy, terms, and deletion pages.

## Verification completed at pause

The following checks passed on July 28, 2026:

- `node --check functions/index.js`
- `node --check functions/scripts/migrate-v2.js`
- pure Cloud Functions/contract/migration tests: **21 passed, 0 failed**
- JSON parsing for Firebase configuration, indexes, hosting configuration,
  Android association, and Apple association files
- `git diff --check`
- structural delimiter scan across **59 Dart files**
- text encoding scan across the repository

Important limitation: the Dart structural scan checks balanced delimiters and
basic source structure. It is not a Dart compiler or Flutter analyzer.

## Work that remains before 95%

### P0 — required repository verification

These items are the main reason the work is not yet at 95%.

1. Make a Flutter SDK available, with explicit approval if installation changes
   this machine.
2. Run `flutter pub get`.
3. Regenerate and review `pubspec.lock`; it is currently stale because
   dependencies were removed without an available Flutter toolchain.
4. Run `dart format --set-exit-if-changed .` and review any broad formatting
   changes.
5. Run `flutter analyze` and fix every error. Review warnings in changed code.
6. Run `flutter test` and fix all failures, including the new narrow-screen,
   deep-link, theme, and message-contract tests.
7. Build a signed-equivalent release AAB or unsigned release artifact and run
   Flutter's size analysis. The previous 90–97 MB observation cannot be closed
   without measuring a release build; a universal/debug APK is not a reliable
   store-download-size measurement.
8. Install/update repository-local Functions test dependencies only with
   approval, update `functions/package-lock.json`, and replace nondeterministic
   CI `npm install` with `npm ci`.
9. Run Firestore and Storage Rules tests through the Firebase Emulator Suite.
10. Fix every Rules Emulator failure and add regression tests for any contract
    adjusted during the fix.
11. Run a final Android manifest, R8, signing, App Links, and release-build
    inspection.

### P0 — required functional testing

Test these paths on at least one real Android device:

1. Existing signed-in user opens with no internet.
2. Avatars, group covers, local fallback icons, cached notes, cached groups,
   Bible translations, and previous messages render offline.
3. Text reflection is queued offline and syncs exactly once.
4. Image and voice reflections survive app restart before upload.
5. Failed media upload can retry and discard without duplicate messages.
6. Sign-out removes private local drafts/outbox/cache.
7. Invite link survives sign-in/onboarding and redeems once.
8. Scheduled study is read-only, activates on time, completes on time, and can
   be extended/reactivated by its owner.
9. Transfer ownership, remove member, leave, archive, and account deletion.
10. Block/report behavior and contacts-only Insight visibility.
11. Notification opt-in, per-study mute, content-preview off/on, invalid-token
    cleanup, and deep routing.
12. Font scaling at 100%, 150%, and 200%; TalkBack labels; keyboard/focus
    order; light/dark contrast; 48 dp interaction targets.

### P1 — repository cleanup and final polish

1. Remove the tracked `functions/node_modules` tree after all locally available
   Node tests are finished. It contains **12,896 tracked generated files**.
2. Remove or deliberately preserve the tracked root build logs, analyzer logs,
   temporary patch scripts, and one-off build scripts. Examples include
   `analyze*.txt`, `build*_log.txt`, `patch_*.py`, and duplicate build scripts.
3. Remove the tracked `web_deployment/.firebase` generated cache.
4. Decide whether `.agents/workflows/bsgc-full-remediation.json` belongs in the
   product repository; it is local workflow state, not app source.
5. Finish dead-code cleanup in `ChatService` and models. Examples include the
   now-unreachable message-star API/legacy fields and redundant parameters in
   the progress API.
6. Consolidate the duplicate Bible-book/chapter catalog still present in older
   source.
7. Run a final accessibility pass on the older, not fully rebuilt screens:
   onboarding, edit profile, inviter selection, My Insights, View Insight, and
   Bible/settings subpages.
8. Run a final error-message pass so no raw backend/internal exception is shown
   to end users.
9. Verify message/comment/reaction abuse behavior under load. Insight
   publication and reporting are rate-limited, but direct Firestore group
   messages/comments/reactions still rely on authorization and client UX rather
   than a server-side request-rate service.
10. Add or verify group-cover orphan cleanup. Message-media orphan cleanup is
    implemented; cover uploads can still be abandoned if upload succeeds and
    the subsequent metadata update fails.
11. Load-test Insight feed fan-out and account deletion with large but allowed
    datasets.
12. Update `docs/implementation-progress.md`, which predates much of the current
    implementation and is now stale. This handoff is the authoritative pause
    record until that ledger is reconciled.

### P2 — external owner/release actions

These cannot be completed safely from repository source alone.

1. Export deployed Firebase Rules, indexes, Functions configuration, and a
   production data backup.
2. Run the migration in dry-run mode against the real project and review every
   reported unsafe record.
3. Migrate legacy inline voice/image records to Storage before enforcing the
   strict v2 media contract.
4. Deploy indexes, Functions, Firestore Rules, and Storage Rules in the staged
   order documented in `docs/release/backend-rollout.md`.
5. Enable and monitor App Check only after proven clients and rules are live.
6. Supply Android release signing secrets and the real SHA-256 certificate
   fingerprint.
7. Replace the Android association placeholder and verify
   `https://braidapp.com/.well-known/assetlinks.json`.
8. Register/configure the iOS Firebase app, supply the Apple Team ID, replace
   the Apple association placeholder, sign the app, and verify Universal Links
   on a physical device.
9. Publish the canonical website and association files.
10. Supply verified operator identity/contact, jurisdiction, retention periods,
    subprocessors, regional rights, age/child-safety position, and moderation
    operations.
11. Complete Google Play/App Store privacy, data-safety, content-rating,
    account-deletion, and user-generated-content declarations.
12. Configure production logs, alerts, crash monitoring, moderation queues,
    backup/restore drills, and incident ownership.

## Known verification blockers

- `flutter` is unavailable.
- `dart` is unavailable.
- Firebase CLI/Rules Emulator is unavailable.
- `@firebase/rules-unit-testing` is not installed in the current generated
  Functions dependency tree.
- iOS Firebase configuration and Apple signing values are absent.
- Android App Links certificate fingerprint is intentionally a placeholder.
- Apple Team ID is intentionally a placeholder.
- Legal/operator facts are not available and must not be invented.

## Exact recommended restart sequence

1. Confirm no new user change supersedes this handoff.
2. Confirm branch and preserve the dirty worktree.
3. Obtain approval for repository-local dependency/tool installation if still
   required.
4. Run Flutter dependency resolution, formatting, analysis, and tests.
5. Fix compiler/analyzer/test findings only.
6. Run Functions tests and Rules Emulator tests.
7. Remove tracked generated dependencies/logs/cache and update lockfiles.
8. Run the real-device offline/accessibility/notification matrix.
9. Build and analyze the Android release artifact.
10. Reconcile the progress ledger and produce a final review report.
11. Stop for user review.
12. Only after explicit approval: create a coherent commit and push
    `codex/bsgc-full-remediation`.

## Definition of 95% for this remediation

The work can reasonably be called 95% only when:

- Flutter format, analyze, and tests pass;
- Functions tests and Firebase Rules Emulator tests pass;
- a release Android build succeeds and its size report is reviewed;
- the P1 generated-file/dead-code cleanup is complete;
- the critical real-device offline and lifecycle tests pass;
- remaining tasks are limited to external credentials, production deployment,
  store-console declarations, and final owner decisions.

## Definition of 100%

One hundred percent requires the approved production migration/deployment,
App/Universal Link verification, signing, real-device regression matrix, legal
publication, store declarations, monitoring/alerts, backup/restore proof, and
post-deployment observation. Repository implementation alone cannot truthfully
claim that state.
