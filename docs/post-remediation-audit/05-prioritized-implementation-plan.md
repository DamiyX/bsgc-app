# Prioritized implementation plan

## Status and intent

This is the implementation plan for findings in the **post-remediation audit** of commit `bfcfa5f4eff358535e06de9d3ca5614ffefd600a`.

No item in this document is marked complete merely because earlier remediation work touched the same area. Completion requires the acceptance evidence defined here.

This plan is deliberately divided into small milestones. An AI agent or developer should receive only one milestone at a time, make a focused branch/commit series, and return evidence before the next milestone begins.

## Implementation status — wave 1

**Local status:** implemented and combined-verification clean; not yet committed,
pushed, deployed, or physically device-tested.

This first bounded wave addresses:

| Finding | Implemented outcome |
|---|---|
| REL-001 | `hidden_messages`, `clearedBefore`, and legacy `deletedFor` now feed one rendered-message visibility contract with rollback on failed hide/clear writes. |
| REL-002 | Reflection, Discussion, and Prayer now use independent space-constrained pagers and cursors; the required composite index is declared. |
| REL-003 | My Insights opens the item the user actually tapped. |
| REL-004 | Current unread/first-unseen behavior consistently consumes the per-user `insight_state` collection; adjacent prebuilt pages do not mark content seen. |
| REL-005 | The MVP contract is now an honest expiring bookmark: unavailable/expired sources remove stale pointers and the UI no longer promises permanent private revisiting. Immutable saved copies remain a later product/backend decision. |
| REL-006 | Note editing validates, awaits persistence, prevents repeat submission, preserves failed drafts, and reports success only after the write completes. |
| SEC-001 | The false end-to-end encryption statement was removed and replaced with accurate service-processing/visibility copy. |
| MIG-001 | Migration preserves note bodies through 50,000 characters and quarantines larger records instead of silently truncating them. |
| SCL-001 | Up to 800 eligible lifecycle transitions are committed in safe 450/350 chunks rather than one invalid Firestore batch. |

Combined local evidence:

- Dart formatting: 61 files checked, 0 changes;
- Flutter analysis: no issues;
- Flutter tests: 19/19 passed;
- Functions tests: 25/25 passed;
- Functions and migration script syntax: passed;
- `firestore.indexes.json`: valid JSON;
- Git whitespace validation: passed.

The Rules Emulator was not rerun locally because this machine has no active
Java 21 runtime. No rule file changed in wave 1; the current branch baseline
has a successful GitHub security-rules job. The new composite index still
requires approved deployment and emulator/device verification.

Everything not listed above remains open under the milestones below.

## Implementation status — wave 8 UX slice

**Local status:** implemented locally and verified by static analysis and
focused/full Flutter tests; device/emulator visual verification remains open.

This bounded product wave addresses the safe MVP portion of Milestone 8:

| Finding | Implemented outcome |
|---|---|
| UX-001, UX-003 | Journal cards can open a reviewed, prefilled contacts-reflection copy; the private note is not mutated. The existing audience entry sheet remains the adapter boundary for private, contact, and group destinations. |
| UX-002 | Today only selects an active study and says “Continue a study”; it does not claim schedule-aware “Next study” behavior. |
| UX-004 | Groups exposes a separately loaded Archived studies route with read-only room access. |
| UX-006 | Contact reflections use calm labeled cards instead of story-ring urgency gradients or tap-third presentation. |
| UX-007, UX-008, REL-024 | Group reflection entry opens the Reflections space, and the last non-plan space is remembered per account and group. |
| UX-012, UX-014, UX-016 | Public copy prefers “reflection”; shared spacing/radius/motion tokens and semantic light/dark surfaces are documented and applied to core surfaces. |

Wave 8 evidence:

- Dart formatting: pass;
- Flutter analysis: no issues;
- Full Flutter tests: 78 passed;
- Focused product-journey tests: 3 passed;
- Git whitespace validation: pass.

Still required before Milestone 8 acceptance: emulator/physical-device checks
for archive read-only behavior, scheduled-only Today state, journal copy
privacy/expiry, remembered spaces, large text, light/dark themes, and product
usability screenshots. Final brand asset approval remains a release gate.

## Implementation status — wave 9 accessibility and component slice

**Local status:** implemented locally and verified with static analysis and
automated tests; device accessibility, large-text, RTL, and contrast review
remain open.

This bounded wave addresses the testable MVP portion of A11Y-001–007 and
UXE-001–003:

| Finding | Implemented outcome |
|---|---|
| A11Y-001 | Core reflection, comment, save, reply, send, menu, and create actions use semantic labels and platform-sized targets; reaction and saved state expose selected/toggled semantics. |
| A11Y-002 | Reflection cards grow with the platform text scaler (up to a bounded 2x accommodation); directional alignment is used for composer affordances; long text remains ellipsized with an accessible expansion action. |
| A11Y-003 | Shared motion tokens are used where the viewer animates; viewer and journal routes honor `disableAnimations`, including comments and scrolling. |
| A11Y-004 | Voice summaries, download progress, save/share progress, and room summaries are exposed as live regions or explicit status labels. |
| A11Y-005 | Scripture links use semantic theme focus colors instead of a hard-coded accent; core light/dark surfaces continue to use semantic scheme colors. |
| A11Y-006 | Voice reflections support an author-written, persisted summary (maximum 1,000 characters) and display an explicit no-summary equivalent when absent. Automatic transcription remains out of MVP scope. |
| A11Y-007 | Scripture recognizers are owned and disposed by both `ClickableScriptureText` and `ExpandableRichText`; rebuilds dispose old recognizers when text/style/theme changes. |
| UXE-001–003 | The bounded component work improves isolated scripture parsing, reflection cards, action semantics, and voice-summary boundaries; a full controller extraction of the largest screens remains a follow-up. |

Wave 9 evidence:

- Dart formatting: pass;
- `flutter analyze`: no issues;
- Full Flutter tests: 79 passed;
- Focused insight/journal regression tests: 19 passed;
- Functions syntax check and tests: 70 passed;
- Git whitespace validation: pass.

Rules emulator tests were not rerun in this wave because no Rules files
changed; the last integrated Rules run remains 31 passed. Manual acceptance
still requires TalkBack/VoiceOver, 200% text, RTL, reduced-motion, light/dark,
small-screen, and contrast checks on a device or emulator. Automatic
transcription, a full screen-controller extraction, and production release
configuration remain outside this bounded wave.

## Implementation status — wave 10 scale and measured-performance slice

**Local status:** implemented locally and verified by static analysis,
automated tests, and Rules Emulator checks; production-scale device traces and
legacy pointer backfill remain release gates.

This wave addresses SCL-004–005 and PERF-002–006 with bounded source paths:

| Finding | Implemented outcome |
|---|---|
| SCL-004, PERF-006 | Active/scheduled Groups, Journal notes, saved reflections, and archived studies use bounded first pages and explicit cursor-based “Load older” actions. Active and archived study queries are separate and indexed. |
| SCL-005, PERF-003 | Server-created `insight_feed` pointers now carry a safe display snapshot. The active feed renders that snapshot without one dependent `insights/{id}` read per pointer; legacy pointers use a compatibility fallback. Saved bookmarks carry the same bounded snapshot and are paged. |
| PERF-002 | Main Hall/Profile list responsibilities are moved into bounded paged components; the largest room/viewer screens retain their existing state boundaries for a later measured extraction. |
| PERF-004, PERF-005 | Existing account-scoped voice cache and outbox quota/expiry controls remain the enforced media budget; this wave keeps their user-visible download/retry paths while bounding the surrounding lists. |

Wave 10 evidence:

- Dart formatting: pass;
- `flutter analyze`: no issues;
- Full Flutter tests: 80 passed;
- Functions syntax check and tests: 70 passed;
- Firestore/Storage Rules Emulator: 31 passed;
- `firestore.indexes.json` parse and Git whitespace validation: pass.

Known limitations: old feed pointers and old saved bookmarks are hydrated by a
bounded compatibility path until a server migration/backfill writes snapshots;
the pointer snapshot intentionally trades some fanout bytes for predictable
feed latency and must be measured against fanout-on-read before million-user
scale. Device traces for time-to-first-content, reads per open, room frame
time, memory, and cache bytes are still required before claiming production
performance budgets.

---

## Non-negotiable execution contract

For every milestone:

1. Pull the exact audit branch and record the starting SHA.
2. Read all reports in `docs/post-remediation-audit/`.
3. Read the repository’s current instructions and existing architecture/migration documentation.
4. Inspect the current implementation before editing; do not assume this plan contains line-perfect code instructions.
5. Preserve unrelated work.
6. Add or update tests with the behavior change.
7. Run the narrow tests during development and the complete quality suite before handoff.
8. Trace each changed behavior from user action → client state → service → rules/function → stored data → rendered result.
9. Update documentation and copy when the truth changes.
10. Do not deploy, migrate production, merge to the default branch, or delete assets without explicit approval.

Every handoff must include:

- starting and ending SHA;
- files changed;
- findings addressed by ID;
- tests run and their exact results;
- manual checks still required;
- known limitations or follow-up risks;
- screenshots/video for visible UI changes.

---

## Dependency map

```text
Milestone 0: Reproducible baseline and test harness
        |
        +--> Milestone 1: Release-blocking truth and data-loss fixes
        |         |
        |         +--> Milestone 2: Room data correctness
        |         +--> Milestone 3: Insight/note correctness
        |
        +--> Milestone 4: Notification/invite/permission reliability
        +--> Milestone 5: Offline, startup, drafts, and account isolation
        |
        +--> Milestone 6: Media security and deletion lifecycle
                  |
                  +--> Milestone 7: Migration, scheduled jobs, and abuse controls

Milestones 2–7 verified
        |
        +--> Milestone 8: Reflection-centered UX and design system
        +--> Milestone 9: Accessibility and component refactor
        +--> Milestone 10: Scale/performance work
        |
        +--> Milestone 11: Release configuration and measured app size
                  |
                  +--> Milestone 12: Final regression audit and release decision
```

Milestones that touch the same models/rules should not run concurrently.

---

# Milestone 0 — Establish a reproducible baseline

**Priority:** P0 enabling work
**Scope:** testing and evidence only; no feature redesign

## Objectives

- Prove the current branch builds/tests in a clean environment.
- Add the minimum test seams needed to fix high-risk paths safely.
- Stop relying on a four-test Flutter suite as proof of application correctness.

## Tasks

### 0.1 Toolchain and clean-checkout evidence

- Record Flutter, Dart, Java, Android SDK, Gradle, Node, and Firebase Emulator versions.
- Run:
  - Dart formatting check;
  - `flutter analyze`;
  - complete Flutter tests;
  - Functions lint/tests;
  - Firestore/Storage rules emulator tests;
  - Android debug compile smoke.
- If Flutter is unavailable locally, use the project CI or a correctly configured development machine and attach logs.

### 0.2 Add Firebase test fixtures/builders

Create reusable fixtures for:

- two users plus a blocked relationship;
- active/archived/expired groups;
- 12-member limit;
- each room space;
- more than 30 messages per space;
- more than 100 comments;
- active/expired/saved Insights;
- message media with canonical Storage paths;
- old/legacy migration shapes.

### 0.3 Add testable state boundaries

Without redesigning screens yet, isolate enough controller/service logic to test:

- message visibility and paging;
- selected Insight navigation;
- seen/saved state;
- note save state;
- notification destination;
- invite terminal/retryable states;
- OS permission versus in-app preference.

## Acceptance

- Clean-checkout CI produces a documented green baseline.
- Android source/resource integration is compiled at least in debug.
- Failing regression tests are added for the P0 functional bugs before their fixes.
- No production data or deployment is involved.

---

# Milestone 1 — Correct release-blocking claims and immediate data-loss paths

**Priority:** P0
**Addresses:** REL-006, SEC-001, MIG-001, UX-011, UX-013

## 1.1 Remove false E2EE and deletion/save claims

### Implementation

- Replace “end-to-end encrypted” with technically accurate visibility/storage copy.
- Audit every occurrence of:
  - encrypted/secure;
  - permanent delete;
  - saved forever/for revisiting;
  - disappears after;
  - support/contact.
- Align copy with actual server and retention behavior.
- Remove visible repository/draft language from any build intended for external testers.
- If operator/legal/support facts are still unavailable, block external-beta release rather than inventing them.

### Acceptance

- No UI claims E2EE.
- A claims inventory maps each sensitive statement to an implemented behavior/test.
- Legal/support screens have no placeholder production claims.

## 1.2 Make note saving truthful and lossless

### Implementation

- Validate note body and any length constraints before write.
- Await persistence.
- Keep editor content intact on failure.
- Show explicit `Saving`, `Saved`, and retryable failure states.
- Prevent duplicate submissions while a write is in flight.
- Handle offline behavior deliberately: either verified queued save or honest unavailable/retry state.

### Tests

- valid save;
- empty body;
- maximum allowed body;
- rule rejection;
- network failure;
- rapid repeated save;
- navigating back during save.

### Acceptance

- Success is never shown before confirmed persistence/queueing.
- Empty/rejected content is not silently discarded.

## 1.3 Remove migration truncation

### Implementation

- Preserve full legacy notes up to the actual target limit.
- Quarantine/report data that cannot be represented; never silently truncate.
- Add Unicode and boundary fixtures.
- Produce before/after hashes or lengths in dry-run evidence without leaking note contents.

### Acceptance

- Migration tests prove 20,001–50,000-character legacy notes remain intact.
- Over-limit records stop or quarantine with an explicit issue.

---

# Milestone 2 — Repair Study Room data correctness

**Priority:** P0/P1
**Addresses:** REL-001, REL-002, REL-009, REL-014, REL-016, REL-020, REL-021, REL-025, REL-026, REL-027, REL-028

## 2.1 Connect per-user hidden/clear state to rendering

### Implementation

- Load `hidden_messages` and `clearedBefore` for the signed-in user/group.
- Apply both filters in one canonical message-visibility function.
- Decide whether replies to hidden/cleared parent messages show an unavailable-parent marker.
- Ensure pagination does not repeatedly surface filtered records without a way forward.
- Subscribe to or refresh personal state after mutations.

### Tests

- hide one message;
- clear current view;
- new message after clear remains visible;
- reconnect and relaunch preserve state;
- other group members still see content;
- hidden reply parent behavior;
- legacy `deletedFor` compatibility only if deliberately supported.

### Acceptance

- UI confirmation is followed by visible removal.
- State persists after process restart.
- No write uses a rules-disallowed legacy path.

## 2.2 Make pagination space-aware

### Recommended design

Use one query/page controller per space with server query constraints on `space`, stable ordering, and a cursor. Do not fetch a global latest page and filter it after retrieval.

### Implementation

- Add/verify composite indexes.
- Preserve message order across pending server timestamps.
- Expose loading-more/error/end state per space.
- Restore scroll/space state sensibly.

### Tests

Seed:

- 100 Discussion;
- 45 Reflections;
- 35 Prayer;

Then prove every space can reach all of its own messages independently.

### Acceptance

- A busy space cannot make another space falsely empty.
- Older content can always be requested while it exists.

## 2.3 Correct unread behavior for an open room

- Define “read” as actually visible/active, not merely navigation intent.
- Suppress or immediately acknowledge unread increments for the active group/space.
- Reconcile on foreground/resume.
- Preserve correct unread for other spaces/groups.

## 2.4 Serialize chapter/progress mutations

Choose an atomic representation:

- per-chapter documents/statuses; or
- transactionally merge a map/set with server-side validation.

Do not write a complete stale client list from parallel taps.

## 2.5 Recompute group summaries after mutation

- Update/repair `lastMessage` after edit/delete/account deletion.
- Do not leave deleted sensitive text in the group list.
- Use server-authoritative summary update logic with idempotent reconciliation.

## 2.6 Align lifecycle and date UX

- Restrict the picker to the same start/end rules as the callable.
- Explain the approximate lifecycle scheduler timing.
- Convert callable error codes to specific user-facing messages.
- Stop using `DateTime.now()` as a silent historical timestamp substitute; represent pending/unknown states explicitly.

## Milestone acceptance

- Automated room tests cover all three spaces, paging, hide/clear, unread, progress races, and deleted summaries.
- Physical/emulator testing covers offline→online recovery and process restart.

---

# Milestone 3 — Repair Insights, comments, saved content, and Journal

**Priority:** P0/P1
**Addresses:** REL-003, REL-004, REL-005, REL-007, REL-008, REL-017, REL-022, SEC-004, UX-009, UX-010, UX-012

## 3.1 Open the selected Insight

- Pass the tapped ID/index into the viewer.
- Resolve the selected item deterministically if the list changes.
- Preserve correct next/previous order.

## 3.2 Use one seen-state model

- Remove UI dependence on legacy shared `seenBy` arrays.
- Read/write the per-user `insight_state` document consistently.
- Define state for expired/deleted/unavailable content.
- Backfill or tolerate legacy items without writing other users’ state.

## 3.3 Redesign saved Insight retention

Recommended MVP option:

- when saving, create a private immutable snapshot/copy of the allowed display content plus source metadata;
- explain that the saved copy remains private;
- define whether author deletion must remove/revoke the copy.

Alternative:

- make bookmarks expire with the source and say so clearly.

Do not retain a pointer that inevitably becomes unreadable while promising revisiting.

## 3.4 Make optimistic actions reversible

For like/save/react/comment:

- track pending operation;
- await result;
- rollback on rejection;
- restore comment text and attachment on failure;
- prevent duplicate taps;
- expose retry.

## 3.5 Paginate comments correctly

- Load the newest page or use a deliberate top-level/reply model.
- Add a stable cursor.
- Keep parent/reply relationships available.
- Do not cap displayed counts at the first 100.
- Test concurrent new comments and deleted parents.

## 3.6 Replace fake undo

Either implement a same-record short soft-delete restore window or remove the `UNDO` action and confirm before delete. Test reaction/comment/save preservation.

## 3.7 Establish canonical current-user identity

- Use the Firestore profile as the application profile source.
- Treat Firebase Auth fields as authentication/bootstrap data, not an independent presentation truth.
- Refresh/auth-sync only through an explicit service.
- Stop trusting client-supplied display names/photos as authoritative message/comment identity.
- Render by canonical UID or have trusted server code write a validated immutable author snapshot.
- Add modified-client rules/function tests proving a user cannot impersonate another profile.

## 3.8 Add durable drafts

Add account-scoped drafts for:

- private reflection/journal composer;
- contact Insight composer;
- group reflection composer.

Restore text, Scripture reference, audience, reply context, and valid local attachments. Define expiry/quota and account-switch cleanup.

## Milestone acceptance

- Tapped content always opens correctly.
- Seen indicators survive relaunch and are per-user.
- Saved behavior exactly matches its copy after source expiry.
- Comment 101+ is visible through paging.
- Failed posts never lose user text.
- No operation is called undo unless it restores the same logical record.

---

# Milestone 4 — Notification, deep-link, invitation, and permission reliability

**Priority:** P1
**Addresses:** REL-010, REL-011, REL-012

## 4.1 Preserve notification destination until delivery

Define a typed destination payload containing:

- group ID;
- space;
- message/Insight/comment ID;
- notification type;
- optional parent/thread ID.

### Implementation

- Validate payload version.
- Do not clear pending destination before successful navigation/resolution.
- Query or page until the target is found.
- Show a specific unavailable/deleted/no-access state.
- Retry after authentication or network restoration.

## 4.2 Classify invite failures

Terminal:

- invalid;
- expired;
- revoked;
- already used;
- group full/no longer available.

Retryable:

- offline;
- timeout;
- transient backend failure.

Clear terminal tokens after showing the result. Keep retryable tokens with a visible retry/dismiss option. Enforce block policy server-side.

## 4.3 Separate preference from OS authorization

Model:

- user wants notifications;
- OS permission status;
- token registration status;
- individual category preferences.

The UI must never say notifications are on when OS authorization is denied. Provide `Open settings` after denial where appropriate.

## Acceptance

- Cold-start and background notification taps open the exact target.
- Offline tap resumes after reconnect.
- Deleted/no-access content has an honest state.
- Bad invite does not retry on every launch.
- Permission denial and later settings enablement stay synchronized.

---

# Milestone 5 — Offline contract, startup, drafts, and account isolation

**Priority:** P1
**Addresses:** REL-013, REL-015, REL-018, REL-019, REL-023, REL-029, REL-030, PERF-001, PERF-004, PERF-005, SEC-006

## 5.1 Define an offline capability matrix

For every primary screen/action, document:

- cold offline with no cache;
- warm offline with cache;
- offline write queue;
- attachment behavior;
- reconnect behavior;
- failure copy.

Do not use “offline-first” as a universal claim until the matrix passes.

## 5.2 Harden the outbox

- Write temp file, flush/close, atomic replace without deleting the last valid file first.
- Recover or deliberately discard validated temp files after crash.
- Surface corrupt state instead of silently treating it as empty.
- Add account ID/version/checksum.
- Add quota, total bytes, item cap, retry/backoff, expiry, manual retry/discard.
- Reconcile missing attachment files.

## 5.3 Add voice cache parity

- Support explicit/first-play cache with progress.
- Indicate cached/offline availability.
- Bound bytes with LRU/expiry.
- Keep cache account-scoped and privacy-aware.
- Provide text summary/caption support in the UX milestone.
- Distinguish unsupported format, authorization, missing file, offline miss, and transient network failure.
- Keep a retry/download action available after audio preparation or playback failure.

## 5.4 Make profile loading partial and resilient

- Load canonical profile independently of contacts/counts.
- Render cached profile while secondary data retries.
- Avoid `Future.wait` all-or-nothing for independent data.
- Give each failed section a local retry state.

## 5.5 Move noncritical work after first frame

- Render an app shell before both complete Bible datasets are decoded.
- Load selected translation/chapter on demand.
- Bound deep-link/notification initialization.
- Catch preferences/auth-stream errors and provide a recovery UI.

## 5.6 Isolate account-scoped local data

On sign-out/account switch, deliberately handle:

- drafts;
- outbox;
- cached attachments/audio/images;
- Firestore persistence;
- notification destinations;
- selected group/space.

Do not erase another account’s data by broad path deletion; use validated account-scoped directories/keys.

## Acceptance

- Physical/emulator airplane-mode matrix passes.
- Crash during outbox replace preserves either old or new valid state.
- Queue cannot grow without bound.
- Previously cached avatars/covers/audio work according to matrix.
- A second account cannot see the first account’s local content.
- First frame is not blocked on complete Bible parsing.

---

# Milestone 6 — Media authorization and deletion lifecycle

**Priority:** P0/P1
**Addresses:** SEC-002, SEC-003, SEC-005, SEC-010, SEC-011, SEC-012

This milestone changes privacy and destructive behavior. It requires a design review before implementation and must not be deployed automatically.

## 6.1 Introduce canonical asset metadata

For managed media store:

- Storage bucket/path;
- owner UID;
- owning entity ID/type;
- MIME/size;
- created timestamp;
- lifecycle status;
- optional checksum.

Do not use a download URL as the only deletion/authorization reference.

## 6.2 Restrict accepted message media

- Accept only authorized managed paths for inline media.
- Treat external URLs as explicit links.
- Bind uploader/owner/entity in rules or trusted server code.
- Validate content type and size.

## 6.3 Implement replace/delete lifecycle

- Upload pending object.
- Commit new asset reference.
- Mark asset committed.
- Queue old object for idempotent deletion.
- Reconcile abandoned pending objects.

Cover:

- profile photo;
- group cover;
- message image/audio/file;
- deleted Insight media;
- failed composer submission.

## 6.4 Convert account deletion to a durable job

Phases should be idempotent and paged:

1. freeze/mark account;
2. revoke sessions/tokens as designed;
3. remove or anonymize memberships/content according to policy;
4. delete managed media using stored paths;
5. reconcile counters/pointers/summaries;
6. remove profile/auth identity;
7. verify and mark complete.

The client callable authorizes/enqueues and then displays status.

## 6.5 Test revocation truth

Copy a download URL before:

- leaving group;
- being removed;
- deleting message;
- deleting group/account.

Document exactly when it stops working. If long-lived token URLs remain, the UI/privacy policy must not promise immediate revocation.

## Acceptance

- No account/group deletion path loses the media references before cleanup.
- Replacing images does not leak unlimited orphan objects.
- Retry cannot double-decrement counters.
- Arbitrary third-party URLs do not auto-render as trusted media.
- Deletion/retention copy matches measured behavior.

---

# Milestone 7 — Migration, scheduled jobs, App Check, and abuse controls

**Priority:** P0/P1
**Addresses:** MIG-002–005, SCL-001–003, SCL-006–007, SEC-007–009

## 7.1 Build a complete v2 canonicalizer

- Normalize all required group/user/note fields and map shapes.
- Validate transformed records against the same invariants as rules/functions.
- Add every known legacy fixture.
- Select one invite collection name and align code, rules, docs, cleanup, indexes, and tests.

## 7.2 Make migration resumable

- Deterministic pagination/cursors.
- Bounded concurrency/batches.
- Idempotent per-document transformation.
- Persisted checkpoint and run ID.
- Dry-run summary.
- Secure export/before-image restore strategy.
- Rehearsed failure/resume/rollback in staging.

## 7.3 Fix scheduled batch limits

- Keep each commit safely below 500 writes including multi-write items.
- Page until time budget is reached.
- Persist/derive cursor safely.
- Emit processed/error/backlog/oldest-age metrics.
- Apply the same pattern to cleanup queries capped at 400/250.

## 7.4 Integrate and stage App Check

- Add client dependency/initialization.
- Configure debug/staging/production providers.
- Observe metrics.
- Enforce per callable in staging.
- Roll forward with rollback plan.

## 7.5 Add abuse controls

Prioritize:

- group creation;
- invites/redemption attempts;
- messages and attachments;
- comments/reactions;
- reports;
- Insight publish/fanout.

Validate report targets and visibility. Add block checks to invite redemption according to documented policy.

## 7.6 Create moderation operations

- operator roles;
- report taxonomy/evidence;
- audit logs;
- response targets;
- content/account action path;
- user status/appeal;
- retention/access policy.

## Acceptance

- A dataset with >1,000 eligible lifecycle records drains without a >500 write attempt.
- Migration interruption/resume is safe and complete.
- Rollback is demonstrated rather than described hypothetically.
- Legitimate release clients work with App Check enforcement.
- Basic abuse attempts receive server-enforced limits.

---

# Milestone 8 — Build the reflection-centered product journey

**Priority:** P1 product work
**Addresses:** UX-001–008, UX-012, UX-014–016, REL-022, REL-024

Do this after core data correctness is stable. It is a deliberate UX milestone, not a collection of screen restyles.

## 8.1 Approve product language and content model

Recommended public concepts:

- Reflection;
- Journal entry;
- Discussion;
- Prayer request;
- Saved reflection.

Decide whether `Insight` remains a branded term based on user comprehension, not repository history.

## 8.2 Create one reflection composer

Capabilities:

- private-first draft;
- optional Scripture;
- body;
- optional image/audio;
- audience selector;
- destination preview;
- durable recovery;
- share-a-copy from Journal;
- clear expiry/save behavior.

Use adapters to existing backend models initially if a safe unified schema would broaden scope.

## 8.3 Make Today truthful

Until study schedule data exists, say `Continue a study`. Add a minimal schedule/progress model before saying `Next study`.

Today should remain bounded to:

- continue reading;
- write/continue reflection;
- one or two relevant responses.

## 8.4 Differentiate the four room spaces

- Plan: next passage and progress.
- Reflections: Scripture-linked reflective cards.
- Discussion: replies/conversation.
- Prayer: praying/answered/follow-up.

Preserve the last selected space and deep-link to the exact one.

## 8.5 Add archived studies

Provide a discoverable archive with clear read-only/restore semantics.

## 8.6 Replace social urgency

- remove/soften story-ring pressure and tap-third navigation;
- replace generic thumb with contextual, respectful reactions;
- avoid popularity-first counts/ranking;
- use deliberate next/previous controls and calm cards.

## 8.7 Establish design tokens and core components

Implement tokens for color, typography, spacing, radius, elevation, motion, and state. Migrate the main four tabs and core details first.

## 8.8 Resolve the production brand asset package

- approve one source mark and wordmark;
- produce adaptive app icon, monochrome, light/dark, and small-size variants;
- document clear space, minimum size, color use, and prohibited treatments;
- optimize runtime exports and identify obsolete drafts for a separate reviewed cleanup;
- never delete draft/source assets without confirming their recoverability.

## Acceptance

- A user can capture privately and share a reviewed copy without retyping.
- Today never invents schedule intelligence.
- Each group space has one meaningful distinct capability.
- Core screens use semantic tokens in light/dark mode.
- Usability sessions show users understand privacy/audience and the four tabs.

---

# Milestone 9 — Accessibility and maintainable component architecture

**Priority:** P1
**Addresses:** A11Y-001–007, UXE-001–003

## 9.1 Fix interaction accessibility

- 48×48 minimum targets.
- Semantic labels/tooltips.
- selected/toggled/expanded state.
- keyboard/focus order where applicable.
- live regions for important async state.

## 9.2 Support adaptive text and directionality

- Test 200% text.
- Remove clipping fixed heights.
- Use directional layout primitives.
- Test long names/content and smallest phone.

## 9.3 Respect reduced motion

- Centralize motion durations.
- Check platform reduced-motion preference.
- Remove nonessential slide/scale/auto progress.

## 9.4 Fix contrast and theme bypasses

- Replace failing link/accent colors.
- Remove hard-coded white/black feature surfaces.
- Add golden/contrast checks for light/dark states.

## 9.5 Provide audio equivalents

- Author-entered summary/caption first.
- Consider automatic transcription only as a separate privacy/cost decision.

## 9.6 Decompose core screens

Extract state/controllers and bounded components for:

- room paging/visibility/composer/items;
- Insight content/comments/reactions;
- main navigation/destination resolution.

Fix and test `ClickableScriptureText` recognizer disposal.

## Acceptance

- TalkBack core-journey pass.
- Accessibility scanner has no critical findings on core screens.
- 200% text/light/dark/reduced-motion goldens pass.
- Core business state is testable without mounting thousand-line screens.

---

# Milestone 10 — Scale and measured performance

**Priority:** P1 before large growth
**Addresses:** SCL-004–005, PERF-002–006

## 10.1 Bound client lists

- cursor pagination for groups, notes, comments, saved content;
- active/archive split;
- stable ordering and error/retry state.

## 10.2 Reduce Insight N+1 reads

Implement a safe pointer snapshot or revised query model. Measure authorization, staleness, and update cost. Do not denormalize sensitive fields without rules tests.

## 10.3 Control fanout

- product-aligned publish limits;
- task queue/chunking if needed;
- per-publisher/feed diversity;
- cost/latency metrics;
- backpressure and retry idempotency.

## 10.4 Establish performance budgets

Example starting budgets to validate on target hardware:

- time to first useful frame;
- Today/Groups cached and network load;
- reads per feed/list open;
- room scroll frame time;
- peak memory after loading a Bible chapter and long room;
- outbox/media cache total bytes.

Set final numbers from device evidence, not arbitrary desktop timings.

## Acceptance

- Representative multi-year data remains responsive.
- Reads/writes per journey are recorded.
- No unbounded list or queue remains in a primary path.
- Performance changes have before/after traces.

---

# Milestone 11 — Release configuration and measured app size

**Priority:** P0 release gate
**Addresses:** SIZE-001–004, BUILD-001–003, RELENG-001–004

## 11.1 Complete production link configuration

- real Play App Signing SHA-256 in hosted Digital Asset Links;
- verified production host/package/path;
- Play-installed invite test;
- iOS Firebase/association only if iOS is genuinely supported.

## 11.2 Add Android compile evidence to CI

Use a debug compile smoke on normal quality CI and a protected signed AAB workflow for release candidates.

## 11.3 Produce one controlled size baseline

Run:

- signed release AAB;
- Flutter analyze-size;
- bundle/device-specific APK analysis;
- Play Console download and installed estimates for arm64.

Record exact commit/toolchain/artifact checksum.

## 11.4 Optimize from evidence

First candidate: duplicated oversized splash resources. Then inspect native libraries/dependencies from the size report. Preserve offline Bibles unless an alternative provides the same offline quality.

Create an asset manifest and separate approved runtime exports from editable/draft sources. Remove obsolete large drafts only through an explicitly approved cleanup commit.

## 11.5 Tune build resources for environment

Do not require every contributor laptop to reserve 8 GB Gradle heap/4 GB metaspace. Validate a lower local profile and retain adequate CI resources.

## Acceptance

- Production invite link works from a Play-signed install.
- A signed AAB exists with a reproducible evidence bundle.
- Reported app size names the artifact and device context.
- Any reduction is measured against the same baseline.
- No UX/security capability was removed solely for size.

---

# Milestone 12 — Final regression audit and release decision

**Priority:** P0
**Scope:** verification, not new feature work

## Automated gates

- format;
- static analysis;
- full Flutter unit/widget/integration tests;
- Functions tests;
- Firestore/Storage emulator tests;
- Android compile and signed AAB;
- migration scale/resume tests;
- scheduled job >500-record tests;
- dependency/security checks.

## Manual device matrix

At minimum:

- low/mid-range Android physical device;
- current supported Android version plus oldest supported version if available;
- fresh install and upgrade;
- cold/warm online and airplane mode;
- kill/relaunch during draft/outbox/upload;
- notification foreground/background/terminated;
- invite link authenticated/unauthenticated/offline;
- OS notification permission deny/re-enable;
- TalkBack;
- 200% text;
- light/dark/reduced motion;
- account switch and account deletion;
- long group/message/comment datasets.

## Product audit

Re-run the original product questions:

- Is this clearly a Bible study/reflection product rather than a chat clone?
- Can a user capture privately before deciding to share?
- Does the group experience help a real study progress?
- Are privacy, expiry, save, and delete behaviors obvious and true?
- Does the experience feel calm and return-worthy?
- Do Today/Groups/Journal/Me each have one clear job?

## Release decision

Only after evidence is attached should the team choose:

- keep branch in development;
- internal testing;
- closed beta;
- merge/default branch;
- production release.

Passing source tests alone is not enough to skip the device and product gates.

---

## Recommended work packets for multiple developers or AI agents

Do **not** ask one agent to “fix the entire audit” in a single run. Suggested isolated packets:

1. Baseline/tests and P0 note/copy/migration fixes.
2. Study Room visibility/pagination/unread.
3. Insights seen/save/comments/selected navigation.
4. Notifications/invites/permissions.
5. Offline outbox/startup/account isolation.
6. Media lifecycle/account deletion.
7. Migration/schedulers/App Check/abuse controls.
8. Reflection composer/Today/space UX/design tokens.
9. Accessibility/component refactor.
10. Scale/performance.
11. Release links/CI/AAB/size.
12. Independent final audit.

Each packet should use its own `codex/`-prefixed branch from the latest integrated review branch. Integrate sequentially where data models overlap.

---

## Finding-to-milestone traceability

This matrix is the completeness check. Ranges include every integer in the range.

| Finding IDs | Milestone |
|---|---:|
| REL-006 | 1 |
| REL-001–002, REL-009, REL-014, REL-016, REL-020–021, REL-025–028 | 2 |
| REL-003–005, REL-007–008, REL-017, REL-022 | 3 |
| REL-010–012 | 4 |
| REL-013, REL-015, REL-018–019, REL-023, REL-029–030 | 5 |
| SEC-001 | 1 |
| SEC-004 | 3 |
| SEC-006 | 5 |
| SEC-002–003, SEC-005, SEC-010–012 | 6 |
| SEC-007–009 | 7 |
| MIG-001 | 1 |
| MIG-002–005 | 7 |
| SCL-001–003, SCL-006–007 | 7 |
| SCL-004–005 | 10 |
| UX-009–013 | 1, 3, and 8 according to the affected copy/interaction |
| UX-001–008, UX-014–016 | 8 |
| A11Y-001–007 | 9 |
| UXE-001–003 | 9 |
| PERF-001, PERF-004–005 | 5 |
| PERF-002–003, PERF-006 | 10 |
| SIZE-001–004 | 11 |
| BUILD-001–003 | 0 and 11 |
| RELENG-001–004 | 7 and 11 |

All findings also return to Milestone 12 for regression verification and release disposition.

---

## Definition of “done”

The remediation is done only when:

- every P0 has implementation plus passing acceptance evidence;
- every deferred P1 has an explicit owner/reason/release consequence;
- private/user-generated content survives failure without false success;
- privacy/deletion/save claims match data lifecycle;
- offline behavior is defined and tested, not inferred;
- core UX is reflection-centered and accessible;
- migration/deletion/scheduled jobs are resumable and bounded;
- release links, Android build, and app-size measurement are production-real;
- a fresh audit finds no known release blocker.

The target is not “many edited files.” The target is a traceable, testable, trustworthy product.
