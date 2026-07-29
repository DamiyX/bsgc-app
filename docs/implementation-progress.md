# Braid full remediation — final repository ledger

**Source audit:** `docs/audit/01-product-and-system-understanding.md` through `docs/audit/06-implementation-plan.md`

**Implementation branch:** `codex/bsgc-full-remediation`

**Audited baseline:** `777e266`

**Audit-plan commit:** `d8b5710`

**Repository implementation commit before final verification:** `c6e328e`

**Final verification date:** July 29, 2026

**Repository status:** ready for branch review; not yet approved for production deployment

This ledger reconciles the implementation with every phase in Report 6. “Implemented” means the repository contains the change. “Automated verified” means the available static, unit, integration, or Rules Emulator checks passed. “Manual/external” means the result depends on a physical device, production credentials, signing material, deployed data, legal facts, or store consoles and therefore cannot be proven from source code.

## Final verification evidence

| Check | Result |
| --- | --- |
| Flutter dependency restore | Passed with Flutter 3.44.8 / Dart 3.12.2 |
| Dart formatting | 59 files checked, 0 changes required after formatting |
| Flutter static analysis | Passed: no issues found |
| Flutter tests | Passed: 4/4 |
| Functions lockfile restore | `npm ci` passed |
| Functions syntax | `functions/index.js` and `functions/scripts/migrate-v2.js` passed `node --check` |
| Functions contract/migration tests | Passed: 21/21 |
| Firestore and Storage Rules Emulator tests | Passed: 26/26 |
| Rules test determinism | Test files serialized with `--test-concurrency=1` to prevent shared-emulator cleanup races |
| Repository whitespace validation | Passed before commit |
| GitHub clean-checkout Quality workflow | Passed all Flutter, Functions, and security-rules jobs at commit `1086723` |
| Android release AAB | Not completed locally; the R8 build was stopped because it caused unacceptable laptop load |
| Physical Android UX regression | Not performed; no Android device/emulator was connected in this workspace |

The local Node installation is v24 while Functions declares Node 22. The JavaScript tests pass locally, and CI explicitly uses Node 22. This distinction is environment evidence, not an application failure.

## Alignment with the original implementation plan

| Phase | Repository result | Automated evidence | Remaining manual/external gate |
| --- | --- | --- | --- |
| 0 — baseline and governance | Implemented locally: isolated branch, CI, release workflow, README, architecture/product/design/release documents, generated-artifact cleanup, lockfiles, signing template, and ignored build outputs | Flutter, Node, JSON, and rules checks available | Decide default-branch replacement; capture deployed Firebase state; production backup; configure signing secrets |
| 1 — security and data contract | Implemented: schema v2, public/private/device data boundaries, authoritative roles and lifecycle, immutable/bounded message contract, contacts-only Insight access, reports/blocks, strict Firestore/Storage rules, resumable migration tooling, rollout runbook | 21 Functions tests and 26 Rules Emulator tests pass | Review real data dry-run, back up production, staged deployment, then App Check rollout |
| 2 — invitations and onboarding | Implemented: opaque expiring/revocable tokens, canonical join route, continuation flow, QR/share, capacity enforcement, accepted connections, and removal of global user-directory discovery | Invite token, normalization, and accepted-connection contracts tested | Real signing fingerprint/domain association; installed/not-installed device testing |
| 3 — group lifecycle | Implemented: draft/scheduled/active/completed/archived behavior, progress, owner transfer, member removal, leave/archive, extension/reactivation, live metadata, and recap | Rules and Functions contracts cover authority/lifecycle boundaries | Multi-user device exercise and scheduled-time behavior |
| 4 — reliable chat and outbox | Implemented: controller/service separation, persistent drafts, stable IDs, queued/sending/sent/failed/retry states, cursor paging, `clearedBefore`, idempotent media paths, bounded image/voice, and hidden unsupported attachments | Message contracts, media paths, widget compilation, analyzer, and group-message rules pass | Airplane-mode restart/retry, upload-progress, playback, and duplicate-prevention checks on Android |
| 5 — offline media and session hygiene | Implemented: shared cached avatar/cover widgets, deterministic initials, bounded decode sizes, explicit offline/error states, account-scoped drafts/outbox, and sign-out cache cleanup | Flutter tests and analyzer pass | Cold/warm airplane-mode and account-switch cache-isolation checks |
| 6 — reflection-centered product and UI | Implemented: semantic design system, Today/Groups/Journal/Me navigation, Plan/Reflections/Discussion/Prayer room structure, explicit audiences, contacts feed, private notes, safety/settings, and full async-state patterns | Theme/narrow-layout widget tests and analyzer pass | Visual product review on representative phone sizes; final copy/design approval |
| 7 — accessibility | Repository improvements implemented: semantics, tooltips, labels, larger controls, dynamic layouts, theme contrast tokens, and safer reduced-motion behavior | Narrow-screen and semantic compilation checks pass | TalkBack journey, 200% text, focus order, contrast tooling, RTL, and switch/keyboard testing |
| 8 — notifications and scale | Implemented: per-device tokens/preferences, explicit permission UX, per-study mute, privacy-safe previews, routing, invalid-token cleanup, bounded feeds, cleanup jobs, publish/report rate limits, and connection caps | Notification contract tests pass | Production FCM states, metrics/alerts, load tests, and stronger abuse controls for direct message/comment/reaction volume |
| 9 — Bible, backup, deferred features | Implemented as planned: KJV/WEB initialization and honest availability; unsafe backup, video, document, and fake support experiences remain removed/deferred | Flutter analysis/tests pass | Translation/license review; backup only after its complete safety contract exists |
| 10 — size and release | Implemented locally: unused APKs/assets/dependencies removed, shrinking configured, release signing cannot fall back to debug, permissions reduced, manual signed-AAB CI workflow added | Dependency cleanup and build configuration inspected; Flutter/Node/rules checks pass | Successful signed AAB and size report, physical closed-track QA, real App Links, legal/store declarations |

## Original high-risk findings now addressed

The repository changes directly cover the audit’s major risk families:

- offline profile/group media no longer relies on a successful network request to render identity;
- private user/device fields are separated from public identity;
- group membership, roles, lifecycle, invitations, publication, moderation, and deletion use server-authoritative operations;
- Firestore and Storage permissions are deny-by-default and regression-tested;
- global user-directory/contact downloads were removed;
- chat drafts and queued media survive transient failure with stable identifiers;
- unsupported or misleading controls are hidden instead of pretending to work;
- contacts-scoped Insights require an accepted author-viewer relationship;
- notifications honor per-device and privacy preferences;
- release builds cannot silently use debug signing;
- tracked APKs, generated dependencies, caches, logs, and patch scripts are removed;
- the app’s product structure is centered on reflection, study, discussion, prayer, and private journaling rather than generic social metrics.

## Deliberately incomplete or deferred items

These are not omissions that another coding agent should silently “finish.” They require authority, credentials, product decisions, or human observation:

1. Production Firestore/Storage backup and deployed-state capture.
2. Migration dry-run against real data and review of every unsafe legacy record.
3. Staged deployment of indexes, Functions, Firestore Rules, and Storage Rules.
4. App Check enforcement after verified clients are live.
5. Android upload keystore, passwords, and release certificate SHA-256.
6. Real `assetlinks.json`, Apple Team ID, iOS Firebase registration, and physical link verification.
7. Operator/legal facts, privacy/terms approval, child-safety position, retention policy, and store declarations.
8. Physical Android offline, accessibility, notifications, microphone, media upload/playback, lifecycle, and account-deletion regression.
9. Production metrics, alerts, crash monitoring, moderation operations, backup/restore drills, and load tests.
10. A completed release AAB size analysis. The historical 90–97 MB universal/debug package is not a reliable Play download-size measurement.

## Branch-review decision

This branch is materially safer, more testable, more maintainable, and more coherent than the audited baseline. It is suitable for Android emulator/device review and code review. It is not yet a production release because the external gates above remain open.

Do not merge it to the default branch merely because automated checks pass. First complete the preview matrix in `docs/testing/branch-preview-guide.md`, record defects with exact reproduction steps, fix confirmed blockers on this branch, and obtain product-owner approval.
