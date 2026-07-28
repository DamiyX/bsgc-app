# Report 6 — Prioritized Implementation Plan

## 1. Objective

Produce the smallest safe, distinctive, reliable Android MVP while preserving a reversible route to 200,000–1,000,000 users.

The order below is deliberate. UI polish must not be implemented on top of insecure schemas or contradictory feature contracts.

## 2. Non-negotiable constraints

- Do not deploy permissive rules to make broken buttons work.
- Do not migrate production data without backup, validation, and rollback.
- Do not expose phone/device data during contact redesign.
- Do not ship debug signing.
- Do not show incomplete features.
- Do not claim success before awaited persistence.
- Do not rewrite Git history without explicit approval.
- Every phase needs tests and acceptance evidence.

## 3. Phase 0 — Baseline and release governance

### Tasks

1. Confirm `777e266` as the intended baseline.
2. Resolve/merge the default-branch divergence.
3. Record current Firebase project, deployed rules, indexes, Functions, Storage rules, and environment configuration.
4. Export/back up production data before schema/rule changes.
5. Decide permanent Android application ID and canonical domain.
6. Configure release/upload signing outside Git.
7. Add CI:
   - format;
   - analyze;
   - tests;
   - rule tests;
   - Function tests;
   - release AAB.
8. Replace template README with setup/build/release instructions.
9. Stop tracking generated dependencies and future APKs.
10. Create schema/product/design documents.

### Acceptance criteria

- clean clone builds predictably;
- default branch represents the product;
- release configuration does not use debug signing;
- secrets/keys absent from Git;
- deployed backend state is captured;
- CI produces a release AAB;
- version is derived, not hardcoded.

## 4. Phase 1 — Security and data-contract rebuild

### Tasks

1. Define versioned schema.
2. Split private/public/device user data.
3. Add explicit group `ownerId`, lifecycle, roles, and member records.
4. Define message immutability and per-user state.
5. Define Insight/Reflection audience and ownership, including the rule that only an author’s approved contacts can read that author’s contacts-scoped Insight.
6. Define reports/blocks.
7. Rewrite Firestore rules with field allowlists/type/length checks.
8. Rewrite Storage paths/rules with ownership, membership, type, and size.
9. Add Emulator tests.
10. Write migration that can resume idempotently.
11. Deploy rules/migration in staged order so old/new clients do not corrupt data.
12. Add App Check after authorization tests pass.

### Acceptance criteria

- nonmember cannot enumerate/read private group/messages/media;
- member cannot modify membership/roles without authority;
- private phone/token data inaccessible;
- nonauthor cannot alter/delete content;
- malformed/oversized writes denied;
- Storage authorization matches Firestore membership;
- tests cover allowed and denied paths;
- migration includes dry-run/report/rollback strategy.

## 5. Phase 2 — Invitations and onboarding

### Tasks

1. Remove global user-directory downloads and stop treating unverified phone numbers as trusted relationships.
2. Implement server-generated expiring/revocable invite tokens.
3. Configure one canonical `/join/{token}` route.
4. Correct Manifest intent filters.
5. Deploy correct `assetlinks.json` package and signing fingerprint.
6. Support installed/not-installed/authenticated/unauthenticated continuations.
7. Add QR sharing.
8. Handle full, expired, revoked, already-member, and blocked cases.
9. Create an explicit accepted-connection graph from invitations so contacts-based Insights can work without exposing the user directory.
10. If WhatsApp-style phone discovery is required for the first beta, implement it as an explicit opt-in, verified-phone, server-side matching service that returns only matches. Otherwise defer phone-book discovery while keeping invite-created connections.
11. Add a disconnect/remove-synced-contacts control if phone discovery is enabled.
12. Add analytics without storing raw invite-token, phone, contact-list, message, or Insight content.

### Acceptance criteria

- new user can open invite, install/sign in/onboard, review, and join;
- raw group ID does not authorize membership;
- capacity enforced atomically;
- revoked/expired tokens fail safely;
- no client downloads the users collection.
- Insight audience relationships can be resolved without exposing unrelated accounts.
- phone discovery, if enabled, never returns or downloads the global directory.

## 6. Phase 3 — Core group lifecycle

### Tasks

1. Implement `draft/scheduled/active/completed/archived`.
2. Define start/end behavior.
3. Implement topic-day progress.
4. Implement book/topic extension edit state.
5. Add owner transfer and member removal.
6. Restrict Add Members by role.
7. Use transactions/server operations for capacity/progress/extension.
8. Subscribe Study Room to current group metadata.
9. Add completed-study recap/archive.
10. Make FAQ match actual behavior.

### Acceptance criteria

- both book and topic groups complete end-to-end;
- concurrent joins cannot exceed twelve;
- owner leave is explicitly resolved;
- dates/lifecycle affect the UI;
- room updates without reopen;
- every visible admin action is authorized and tested.

## 7. Phase 4 — Reliable chat and offline outbox

### Tasks

1. Split Study Room into controller/repository/components.
2. Persist composer drafts locally per account/group.
3. Generate stable client message IDs.
4. Implement queued/sending/sent/failed/retry states.
5. Await writes and retain draft on failure.
6. Make side effects atomic/idempotent.
7. Replace pagination with cursors.
8. Replace clear-chat batch mutation with `clearedBefore`.
9. Align/hide reaction/edit/delete/star actions.
10. Move voice recordings to Storage.
11. Add duration/size caps and upload progress.
12. Keep temporary audio until acknowledged.
13. Hide video/document attachments.

### Acceptance criteria

- no draft lost on network failure/process termination;
- retry creates no duplicate;
- failed uploads recover or cancel;
- voice never enters Firestore as base64;
- old pages are not re-read;
- unsupported actions are invisible;
- offline queue state is clear.

## 8. Phase 5 — Offline media and session hygiene

### Tasks

1. Build shared avatar/image/cover components.
2. Replace raw `NetworkImage`.
3. Remove remote/random identity placeholders.
4. Add deterministic local initials/fallbacks.
5. Add thumbnail/decode bounds.
6. Add offline/stale/pending/error states.
7. Partition caches by account or securely clear them.
8. Cancel account-specific background tasks on sign-out.
9. Make Firebase/startup failure states explicit.
10. Fix sign-out so Firebase session clears even when Google sign-out fails.
11. Add storage/cache controls.

### Acceptance criteria

- no blank avatar/cover due only to lack of internet;
- cached media works offline;
- uncached media has meaningful fallback;
- one account cannot inherit another's private cache;
- startup/onboarding never silently bypasses required state;
- cold/warm airplane tests pass.

## 9. Phase 6 — Reflection-centered product and UI

### Tasks

1. Implement semantic design tokens.
2. Add Today, Groups, Journal, Me navigation.
3. Redesign group around Plan/Reflections/Discussion/Prayer.
4. Share the underlying draft/composer building blocks between private Notes, group Reflections, and contacts-based Insights without erasing their different audiences and lifecycles.
5. Keep audience explicit: Only me, selected group, or approved contacts.
6. Replace the unscoped active-Insights query with a paginated contacts feed that enforces the author-viewer relationship.
7. Preserve comments for eligible viewers; do not let shared participation under one Insight grant access to commenters’ separate Insights.
8. Retain reactions with noncompetitive presentation and no popularity-ranked feed.
9. Add Journal search/filter and revisit flow.
10. Reframe referrals as private invitation impact (“people you welcomed”), not public follower-like status.
11. Redesign settings around privacy/notifications/storage/data/safety.
12. Replace logo/launcher/splash with optimized brand assets.
13. Bundle intentional fonts.
14. Add complete loading/empty/error/offline states.

### Acceptance criteria

- primary value is understandable without explanation;
- current study action is one tap from Today;
- private reflection can later be shared deliberately;
- contacts can discover and discuss eligible Insights outside their study groups;
- no noncontact can read an author’s contacts-only Insight;
- participation under one Insight does not expose commenters’ independent Insights;
- referral impact encourages successful invitations without leaderboards or public rank;
- every core async screen has all states;
- light/dark themes use semantic tokens.

## 10. Phase 7 — Accessibility

### Tasks

1. Audit 48dp targets.
2. Add semantics/tooltips.
3. Test screen-reader order and announcements.
4. Meet contrast requirements.
5. Support 200% text scaling.
6. Respect reduced motion.
7. Remove fixed-height clipping.
8. Add focus/keyboard/switch support.
9. Prepare RTL/localization-safe layouts.
10. Add media labels/transcript path.

### Acceptance criteria

- TalkBack completes onboarding, join, reflection, send, settings, deletion;
- no essential unlabeled control;
- contrast and scaling pass;
- send/error state announced;
- no color-only meaning.

## 11. Phase 8 — Notifications and backend scale

### Tasks

1. Store per-device tokens with timestamps.
2. Remove stale/invalid tokens.
3. Initialize local notification plugin correctly.
4. Align channel IDs/sounds.
5. Add foreground/background/terminated routing.
6. Derive trusted sender/group names server-side.
7. Add lock-screen preview preferences.
8. Replace global/unbounded queries, including the active-Insights listener, with bounded audience-scoped feeds.
9. Replace seen/liked arrays.
10. Remove sequential N+1 referral/member reads.
11. Add cleanup for invites/tokens/orphan uploads.
12. Add rate limits, metrics, and alerts.

### Acceptance criteria

- multiple devices receive independently;
- mute/privacy settings work in every app state;
- taps open correct content;
- invalid tokens cleaned;
- all list queries bounded/paginated;
- no O(all users) client operation;
- load-test query/write counts documented.

### Product outcome measurements

Measure outcomes that represent fellowship and study rather than vanity:

- percentage of published Insights viewed by at least one eligible contact;
- percentage receiving a substantive comment/question;
- percentage of Insight viewers who later participate in a study circle;
- percentage of accepted invitees who become active in a group;
- weekly percentage of active groups completing a planned study step;
- percentage of private reflections deliberately shared to a group or contacts;
- access-control test/telemetry confirming zero successful noncontact reads.

Do not use total likes, raw referral-tree size, or total posts as the primary success measure.

## 12. Phase 9 — Bible, backup, and deferred features

### Bible

- await initialization;
- expose only KJV/WEB;
- add accurate availability/attribution;
- add licensed translations only with permission and tests.

### Backup

Keep removed until:

- correct paths/IDs;
- versioned schema;
- encryption;
- checksum;
- staging/validation;
- rollback/conflict policy;
- temporary cleanup;
- verified OAuth consent;
- background truthfulness;
- full restore tests.

### Video/documents

Restore only with complete sender/recipient experience, streaming/bounded memory, progress, retry, offline state, safe file handling, and moderation.

## 13. Phase 10 — Size and release

### Tasks

1. Remove unused `icon1.png`.
2. Resize/compress icon assets.
3. optimize splash resources.
4. Remove deferred dependencies.
5. Enable/test minification/resource shrinking.
6. Review multidex/Impeller flags.
7. Minimize permissions.
8. Run `flutter build appbundle --release --analyze-size`.
9. Review dependency audit/upgrades.
10. Play internal/closed-track QA.
11. Complete privacy/data-safety/UGC/deletion requirements.

### Acceptance criteria

- signed AAB;
- correct package/domain/App Links;
- device-specific size measured;
- no unused large assets;
- no debug signing;
- privacy policy/terms/report/block/deletion live;
- release checklist approved.

## 14. Recommended ticket order

1. Capture deployed backend and freeze unsafe external beta.
2. Security schema/rules tests.
3. Private/public user split.
4. Group membership/roles migration.
5. Storage rules/media paths.
6. Invite-token flow/App Links.
7. Remove contact discovery.
8. Remove/hide broken features.
9. Reliable chat outbox/voice migration.
10. Group lifecycle/progress.
11. Offline image components/session cache.
12. Reflection model/navigation redesign.
13. Accessibility.
14. Notifications/scale.
15. Size/release/store readiness.

## 15. Verification contract for every ticket

Every implementation ticket must include:

- current failing behavior;
- desired contract;
- data/schema/rule impact;
- migration/backward-compatibility impact;
- success and failure UI;
- unit/widget/integration/rule tests;
- manual verification steps;
- telemetry without sensitive content;
- rollback/reversibility notes;
- evidence output.

“The button works on the happy path” is not sufficient completion.

## 16. External-beta gate

Do not open an external beta until all are true:

- P0 authorization/privacy issues fixed and tested;
- group invitation works;
- no global user-directory download;
- contacts-only Insight access is enforced and tested;
- account deletion works;
- report/block/moderation exists;
- unsupported features hidden;
- chat cannot silently lose drafts;
- offline image fallbacks pass;
- release signing/App Links correct;
- privacy policy/terms/data declarations live;
- fresh analyzer/tests/release AAB pass.
