# Braid post-remediation audit

**Branch audited:** `codex/bsgc-full-remediation`
**Audited commit:** `bfcfa5f4eff358535e06de9d3ca5614ffefd600a`
**Original baseline:** `777e266`
**Audit date:** July 29, 2026
**Mode:** read-only application audit; no application fixes, commits, pushes, deployments, migrations, or production access

## Why this audit exists

The earlier remediation branch is materially better than the original baseline, but the repository ledger overstates completion in several places. Passing formatting, analysis, unit tests, and Firebase Rules Emulator tests proves useful things; it does not prove that the primary mobile journeys work, that all private-state writes are consumed by the UI, that security claims match the storage architecture, or that the app is ready for hundreds of thousands of users.

This audit re-traced the product from source to final consumer. It covered:

- startup, authentication, onboarding, profiles, invitations, navigation, and notifications;
- Today, Groups, Journal, Me, study-room Plan/Reflections/Discussion/Prayer, Insights, comments, reactions, and media;
- offline reads, drafts, queued writes, image fallbacks, audio, process death, and account switching;
- Firestore and Storage rules, Cloud Functions, data migration, account deletion, scheduled jobs, abuse controls, and cost/scale;
- UI structure, language, interaction design, dark mode, accessibility, reduced motion, and brand coherence;
- Android packaging, assets, dependencies, signing, App Links, CI, app-size evidence, and release gates.

## Severity

- **P0 — release blocker:** a primary journey is false/broken, private-data protection is materially weaker than claimed, destructive operations can lose data, or production rollout can fail catastrophically.
- **P1 — high:** a common journey fails or misleads, an abuse/privacy/reliability problem is significant, or scale will break under credible growth.
- **P2 — medium:** meaningful UX, accessibility, maintainability, cost, or edge-case defect.
- **P3 — low:** polish, cleanup, or long-horizon improvement.

## Executive conclusion

The branch should remain a review branch. It is not ready to replace the production/default branch or enter an external beta.

The strongest improvements are real:

- the main information architecture is now Today / Groups / Journal / Me;
- groups have Plan / Reflections / Discussion / Prayer;
- public, private, device, and personal-state documents are substantially better separated;
- Firestore and Storage rules are deny-by-default and tested;
- invitations use opaque expiring tokens;
- group media uses a persistent local outbox with stable message IDs;
- avatars and covers use cached images with deterministic local fallbacks;
- KJV and WEB remain available as offline assets;
- Android release shrinking and explicit release signing are configured;
- tracked generated dependencies and APK artifacts were removed.

However, fresh tracing found release-blocking contradictions:

1. **“Hide for me” and “Clear this view” do not affect rendered messages.** The app writes `hidden_messages` and `clearedBefore`, but the room never reads either state.
2. **The three message spaces share one global 30-message page.** A busy Discussion can make older Reflections or Prayers appear empty and provide no way to load them.
3. **The app claims Insights are end-to-end encrypted, but they are ordinary Firestore documents readable by the backend.**
4. **Firebase Storage download URLs are stored as bearer-token URLs.** Possessing a cached URL can bypass the membership intent of Storage rules, and deletion does not reliably revoke or remove the media.
5. **Account deletion can leave all Storage media for deleted solo groups behind.** The Firestore group is recursively deleted before the later message-media query, and no group Storage prefix is removed.
6. **The migration can silently truncate legacy note bodies to 20,000 characters although the product supports 50,000, and it does not normalize all fields required by v2 rules.**
7. **The hourly lifecycle job can put as many as 800 writes into a 500-write batch.** At scale the entire job can fail repeatedly.
8. **Private-note editing reports “Note saved!” before the write completes and ignores failure.** Clearing the body can be rejected by rules while the UI still reports success.

There are also high-impact core defects: tapping an item in My Insights opens the first item rather than the selected one; new seen state is written to per-user documents but unread rings still read legacy `seenBy` arrays; saved contact Insights become unreadable after expiry; notification taps do not navigate to the target message; unread counts increase while a user is already reading a room; notification permission denial leaves the app switch falsely enabled; message/comment display identity is client-supplied; and startup blocks on parsing both complete Bible files before the first app frame.

## Original reported offline-image issue

The original blank-image family is **partially and substantially improved**, not fully proven:

- `BraidAvatar` and `BraidCoverImage` now use `CachedNetworkImage`.
- Both provide deterministic initials or local graphic fallbacks.
- Previously fetched images can be served from disk cache.
- Empty, invalid, or never-downloaded URLs no longer need to render a blank hole.

Remaining limitations:

- cold offline launch without a cached private profile still stops at a reconnect screen;
- profile screens combine unrelated reads, so one failed contacts query can discard otherwise available profile data;
- current-user identity sometimes comes from stale Firebase Auth fields and sometimes from Firestore;
- voice media has no equivalent offline cache;
- message images say “unavailable offline” for every load failure, even if the cause is deletion, authorization, corruption, or a bad URL;
- account-switch isolation does not clear Firestore persistence;
- no physical cold/warm airplane-mode matrix has been run.

The correct status is therefore **code-level fallback implemented; complete offline contract unverified and still inconsistent**.

## Report set

1. `01-functional-reliability-and-offline.md`
2. `02-security-backend-migration-and-scale.md`
3. `03-ui-ux-accessibility-and-product.md`
4. `04-app-size-performance-release-and-quality.md`
5. `05-prioritized-implementation-plan.md`

## Verification evidence and limits

The audited commit has a passing clean-checkout CI run recorded by the prior work: Flutter format/analyze/tests, Functions tests, and Firestore/Storage Rules Emulator tests passed. The Flutter suite contains only four tests, however, and no Android artifact is produced by normal pull-request CI. The release AAB/R8 build was stopped locally because it caused unacceptable laptop load. No emulator or physical Android device was used for this fresh audit.

Accordingly:

- source/data-flow findings in these reports are confirmed where stated;
- visual, TalkBack, OS-permission, notification, process-death, and device-size outcomes remain explicit manual gates;
- the historical “90–97 MB” number is not treated as a trustworthy Play download-size measurement.
