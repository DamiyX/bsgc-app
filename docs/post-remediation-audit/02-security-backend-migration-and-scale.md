# Security, backend, migration, and scale audit

## Purpose

This report covers trust boundaries, privacy claims, Firebase authorization, media lifecycle, account deletion, abuse controls, migration safety, scheduled maintenance, and the changes required before Braid can responsibly scale.

The audit distinguishes:

- **authorization**: whether Firebase rules permit an operation;
- **privacy**: who can technically read retained content;
- **confidentiality**: whether content is encrypted from the service operator;
- **lifecycle correctness**: whether deletion, expiry, revocation, and migration do what the UI promises;
- **scale safety**: whether a path remains valid with large users, groups, and content volumes.

Passing Firestore and Storage rules tests does not by itself prove all five.

---

## Critical and high-priority findings

### SEC-001 — The end-to-end encryption claim is false

**Severity:** P0 / release-blocking trust issue
**Evidence:** `lib/screens/my_insights_screen.dart`

The app tells users:

> “Your insights are end-to-end encrypted.”

Insights are normal Firestore documents. They are protected by Firebase authentication and security rules, but the backend/service operator can technically access their plaintext. No client key generation, encryption envelope, key distribution, device recovery, or ciphertext-only storage exists.

**Impact**

- Users may share sensitive faith, relationship, health, or pastoral information under a materially false privacy promise.
- This creates legal, ethical, and reputational risk.
- The claim cannot be fixed with wording such as “Firebase encrypts data”; encryption at rest and in transit is not end-to-end encryption.

**Required correction**

For the MVP, remove the E2EE statement and use precise copy such as:

> “Visible only to the people you choose while it is active. Braid stores and processes this content securely to provide the service.”

If true E2EE becomes a product requirement, treat it as a separate architecture program covering group-key rotation, new-device recovery, notification previews, abuse reporting, backups, search, and account recovery.

---

### SEC-002 — Firebase download URLs behave like bearer links outside membership rules

**Severity:** P0
**Evidence:** `lib/services/storage_service.dart`, message/profile/group media fields, `storage.rules`

Uploads call `getDownloadURL()` and persist the resulting tokenized URL in Firestore. Firebase Storage download tokens can grant direct possession-based access to the object. A person who has copied the URL may retain access even after:

- leaving a group;
- being removed or blocked;
- a Firestore message being tombstoned;
- a Firestore group being deleted.

Firestore membership checks are not consulted when the token URL is fetched directly.

**Impact**

- “Delete,” membership removal, and invite revocation do not reliably revoke already-issued media access.
- Sensitive audio, photos, and attachments may outlive the record users can see.

**Required correction**

1. Define a media threat model and honest retention promise.
2. Delete Storage objects when their owning message/profile/group asset is replaced or permanently deleted.
3. Store Storage paths as the canonical reference, not only opaque download URLs.
4. For stricter revocation, serve protected media through an authenticated path or short-lived signed URL rather than long-lived token URLs.
5. Add lifecycle tests covering copied URLs after membership removal and deletion.

---

### SEC-003 — Account and group deletion orphan Storage media

**Severity:** P0
**Evidence:** account-deletion callable in `functions/index.js`; upload paths in `lib/services/storage_service.dart`

For an owned solo group, account deletion recursively removes the Firestore group before later collection-group message processing. The corresponding message documents are therefore no longer available to enumerate their attachments. There is also no complete deletion of the group’s Storage prefix.

Message tombstones delete message data but do not reliably delete the related media object. Profile and group cover replacements use new UUID paths without deleting the previous object.

**Impact**

- “Permanently delete” is not true for media.
- Storage cost grows continuously.
- Failed upload/database-update sequences create unreachable objects.
- A user’s account may disappear while their uploaded files remain addressable.

**Required correction**

- Persist canonical `storagePath` metadata for every managed asset.
- Implement idempotent object cleanup before losing the references, or use a durable deletion job.
- Delete old profile/group covers only after the new database reference commits.
- Add an orphan reconciler with a dry-run mode, metrics, and bounded deletion batches.
- Rewrite deletion copy until the full lifecycle is implemented and verified.

---

### SEC-004 — Display identity can be spoofed by a modified client

**Severity:** P1
**Evidence:** message/comment creation rules and client-supplied `senderName`, `senderPhotoUrl`, `authorName`, and `authorPhotoUrl`

Rules bind author UIDs, but they do not ensure that the submitted display name/photo matches the canonical user profile. A modified client can create a message or comment with its own UID and another person’s displayed identity.

**Impact**

- Impersonation inside a trusted study group.
- Confusing moderation evidence.
- Notifications and room history may show different author identities because some server paths fetch canonical profile data while the room renders embedded client fields.

**Required correction**

Prefer one of:

1. render identity from the canonical profile by UID;
2. populate immutable message author snapshots server-side;
3. strictly validate submitted snapshots against canonical data in trusted code.

The second option gives stable historical names while preventing client spoofing.

---

### SEC-005 — Arbitrary HTTPS media URLs create a tracking and trust-boundary gap

**Severity:** P1
**Evidence:** message validators in Firestore rules and client media rendering

The current model accepts arbitrary HTTPS media URLs. A modified client can embed a third-party image or audio URL. When another user views it, the third-party host can observe network metadata such as IP address, user agent, timing, and request behavior.

**Impact**

- Reader privacy can be leaked without a visible external-link action.
- Content bypasses Braid’s Storage path, size, ownership, and cleanup assumptions.
- Moderation and offline caching become less predictable.

**Required correction**

- Restrict managed message media to approved Firebase Storage paths or trusted proxy URLs.
- Validate media ownership and content metadata.
- Render explicit external links as links rather than silently loading them as message media.

---

### SEC-006 — Sensitive local data is plaintext and backup behavior is not explicitly controlled

**Severity:** P1
**Evidence:** local draft/outbox/cache services; `android/app/src/main/AndroidManifest.xml`

Drafts and the outbox can contain religious reflections, notes, image paths, and recorded-audio paths. They are stored as normal local files/preferences. The Android manifest does not explicitly declare a backup/data-extraction policy, and Firebase offline persistence is not cleared at sign-out.

**Impact**

- Sensitive content may remain on a shared or transferred device.
- Account A’s cached Firestore data may remain locally after sign-out even if the UI changes to Account B.
- Platform backup behavior is left to defaults rather than a conscious privacy decision.

**Required correction**

1. Classify which local content is sensitive and which must survive process death.
2. Exclude sensitive stores from cloud/device transfer backup unless the product deliberately supports it.
3. Encrypt especially sensitive durable drafts/outbox records where practical.
4. Clear or isolate account-scoped local persistence on sign-out/account switch.
5. Document exactly what “remove local data” means.

---

### SEC-007 — App Check is not operationally ready

**Severity:** P1
**Evidence:** `functions/index.js`, Flutter dependencies/configuration

Callable functions expose an `ENFORCE_APP_CHECK` parameter whose default is false. The Flutter client does not include and initialize Firebase App Check. Turning enforcement on today would therefore reject legitimate clients.

**Impact**

- Callables are more exposed to scripted abuse.
- Operations may assume App Check can be enabled as a simple production toggle when it cannot.

**Required correction**

- Integrate App Check in Flutter with debug providers only for local development.
- Validate Android/iOS production providers.
- Observe App Check metrics before enforcing.
- Roll out enforcement per environment and callable with a rollback switch.

---

### SEC-008 — Abuse controls are incomplete

**Severity:** P1
**Evidence:** `functions/index.js`, direct Firestore writes

There is no robust per-user creation limit for study groups. Direct message, comment, reaction, and report writes lack meaningful server-enforced rate limits. App Check is disabled. Report creation does not sufficiently verify that the target exists, is visible to the reporter, or belongs to the reported context.

**Impact**

- Spam and write-cost abuse.
- Report queue pollution using invented target IDs.
- High notification fanout and moderation load.

**Required correction**

- Add server-enforced rate buckets for high-cost or abuse-prone operations.
- Add sensible per-user active-group limits.
- Validate report target existence and reporter visibility.
- Instrument rejection rates, fanout volume, and suspicious repeated writes.
- Avoid relying on UI disabling as a security boundary.

---

### SEC-009 — Invite redemption does not enforce the block relationship

**Severity:** P1
**Evidence:** `redeemGroupInvite` in `functions/index.js`

Insight sharing checks block documents, but group invite redemption does not clearly reject a blocked relationship between the inviter/owner and redeemer.

**Impact**

- Blocking is inconsistent across product surfaces.
- An unwanted person may re-enter a shared group via a valid invite path.

**Required correction**

Define the exact block policy for shared groups, then enforce it in the callable. At minimum, prevent a blocked user from joining through an invite issued by the blocker while retaining honest copy that already-shared group content may remain visible under group policy.

---

## Deletion and transactional integrity

### SEC-010 — Account deletion is multi-step, non-atomic, and not safely resumable

**Severity:** P1
**Evidence:** account-deletion callable in `functions/index.js`

Account deletion performs many Firestore queries, updates, recursive deletes, and Storage operations. If it fails halfway, retrying can repeat earlier side effects. In particular, connection-count decrements can occur before the user’s own connection records are deleted, allowing a retry to decrement counterpart counts again.

**Impact**

- Incorrect counters.
- Partially deleted accounts.
- Support cannot confidently tell whether deletion finished.
- A large account can exceed function time/memory limits.

**Required correction**

Use a durable deletion state machine:

1. create a deletion job with a unique ID and phase;
2. make each phase idempotent;
3. page through content with checkpoints;
4. record failures and retry safely;
5. verify absence/reconciliation before marking complete;
6. expose truthful “deletion in progress” state.

Counters should be derived/reconciled or changed using operation IDs that cannot be applied twice.

---

### SEC-011 — “Permanent delete” is implemented as a status/tombstone in some flows

**Severity:** P1
**Evidence:** Insight and message deletion paths

Some user-facing delete copy implies immediate permanent erasure while the implementation changes a status or retains metadata for synchronization/moderation.

**Impact**

- Privacy promise does not match backend behavior.
- Users cannot make informed decisions about sensitive content.

**Required correction**

Define and document:

- delete for me;
- delete for everyone;
- soft delete/tombstone;
- retention for abuse/security records;
- final physical deletion time.

Use those exact concepts consistently in UI copy and data lifecycle jobs.

---

### SEC-012 — Uploads and reference updates are not an atomic lifecycle

**Severity:** P2
**Evidence:** profile/group/message upload flows

The file upload and the Firestore record update are separate operations. If the upload succeeds and the write fails, the file is orphaned. If replacing a cover/photo, deleting the old file too early would create the inverse failure.

**Required correction**

Use an explicit pending/committed asset lifecycle or a reliable orphan collector. Commit the new reference first, then asynchronously delete the old known path. Never derive destructive targets from an unvalidated URL.

---

## Migration findings

### MIG-001 — Legacy note migration silently truncates content

**Severity:** P0 for any production migration
**Evidence:** `deriveNoteMigration` in `functions/lib/migration.js`

The migration truncates legacy note bodies at 20,000 characters, while current app/rules behavior allows a larger note size (50,000 characters).

**Impact**

- Irreversible loss of users’ private Bible-study notes.
- The migration can report success while silently discarding content.

**Required correction**

- Never silently truncate source content.
- Preserve the complete body when it fits the target contract.
- If a source exceeds a true platform limit, quarantine it and report it for explicit handling.
- Add boundary and Unicode tests using real maximum-size fixtures.

---

### MIG-002 — Group migration does not fully normalize records to the strict v2 contract

**Severity:** P1
**Evidence:** group transformation in `functions/lib/migration.js`; v2 Firestore rules

The migration adds selected fields such as schema version, owner, members, lifecycle, and extension information, but does not reliably normalize every field required by stricter v2 update rules—for example core text, type, and map shapes.

**Impact**

- A migrated group can be readable but fail later updates.
- The first user action after migration appears broken despite a “successful” rollout.

**Required correction**

Build a complete v2 canonicalizer and validate every transformed document against the same invariant set enforced by the rules. Add fixtures for every known legacy shape, including missing/null/wrong-type fields.

---

### MIG-003 — The migration is not designed for a large production dataset

**Severity:** P1
**Evidence:** `functions/scripts/migrate-v2.js`

The script accumulates database documents/operations in memory and performs sequential or N+1 work per user/group. It has no durable checkpoint, shard ownership, or safe resume cursor.

**Impact**

- Slow or failed migration as dataset size grows.
- Difficult recovery after a local process/network failure.
- Increased read/write cost and a large blast radius.

**Required correction**

- Page by deterministic document ID or timestamp.
- Store checkpoints outside the process.
- Use bounded concurrency and batch-size limits.
- Support dry-run, sample validation, and repeatable idempotent execution.
- Reconcile counts before and after each shard.

---

### MIG-004 — The documented rollback procedure cannot perform the promised restore

**Severity:** P1
**Evidence:** migration/rollout documentation and generated report format

The rollout documentation refers to restoring values from the migration report, but that report contains counts and issues rather than a complete, secure record of prior document values.

**Impact**

- The claimed rollback path does not exist.
- Operators may proceed under false confidence.

**Required correction**

Choose one real strategy:

- an export/snapshot verified before migration;
- append-only reversible transformations;
- or a secure before-image store with retention and access controls.

Then rehearse the restore in a non-production environment.

---

### MIG-005 — Schema documentation and implementation disagree on invite collection names

**Severity:** P2
**Evidence:** `docs/architecture/schema-v2.md` versus `functions/index.js`

Documentation names `group_invites`, while implementation uses `invites`.

**Impact**

- Future rules, cleanup scripts, dashboards, or AI-assisted changes can target the wrong collection.

**Required correction**

Select the canonical name, update all code/rules/docs/tests, and add a schema conformance checklist.

---

## Scale and operations findings

### SCL-001 — Lifecycle scheduler can exceed Firestore’s 500-write batch limit

**Severity:** P0 at production scale
**Evidence:** `advanceGroupLifecycle` in `functions/index.js`

The scheduler reads up to 400 records from each of two lifecycle queries and can attempt to process both sets in one batch. In the worst case that produces approximately 800 writes, above Firestore’s 500-operation batch limit.

**Impact**

- The entire scheduled run fails and retries.
- Expired groups remain active or lifecycle states drift precisely when volume increases.

**Required correction**

- Page and commit batches comfortably below 500 operations.
- Account for any multi-write item, not just document count.
- Continue until the current bounded time budget is reached.
- Record cursor, processed count, errors, and backlog age.

---

### SCL-002 — Cleanup jobs have fixed daily/hourly caps without backlog draining

**Severity:** P1
**Evidence:** scheduled queries using limits of 400 and 250 in `functions/index.js`

Cleanup jobs process only a fixed first page. If eligible records arrive faster than the cap, the backlog grows indefinitely.

**Impact**

- Expired content and orphan media persist longer than promised.
- Costs and compliance exposure compound silently.

**Required correction**

Use paged loops with a time budget and persisted cursor, publish backlog metrics, and alert on oldest-eligible age rather than only function failure.

---

### SCL-003 — Account deletion uses unbounded content scans inside a time-limited callable

**Severity:** P1
**Evidence:** collection-group and Storage work in account deletion

A high-content user can have more records than a single 540-second function invocation can safely enumerate and mutate.

**Required correction**

Move deletion to the resumable job described in SEC-010. The callable should authorize and enqueue, not perform the complete unbounded deletion inline.

---

### SCL-004 — Core client queries are unbounded

**Severity:** P1
**Evidence:** groups, notes, and related list services/screens

Some lists stream or load all groups/notes and perform search/filtering in memory. There is no meaningful group-creation cap.

**Impact**

- Startup memory, latency, reads, and rendering cost grow with user history.
- An abusive or long-lived account can degrade its own app and backend spend.

**Required correction**

- Add indexed pagination and stable cursors.
- Separate recent/active and archived history.
- Search using an intentional index/service when local bounded search is no longer enough.
- Apply product limits where unlimited creation adds no user value.

---

### SCL-005 — Insight feeds use N+1 reads and fanout-heavy writes

**Severity:** P1
**Evidence:** Insight feed/saved loaders and publish/sync functions

The feed first reads pointer documents and then fetches individual Insight documents (up to roughly 40 for active and 100 for saved). Publishing can fan out pointers to up to 500 connections. A prolific publisher can dominate the top expiry-ordered feed and generate substantial write volume.

**Impact**

- High latency and read cost.
- Write amplification and notification pressure.
- Feed diversity is poor: one prolific contact can displace everyone else.

**Required correction**

For the MVP:

- denormalize a safe display snapshot into feed pointers;
- page by stable cursor;
- cap publishing with an understandable product limit;
- rank/group feed items to preserve contact diversity;
- measure reads per feed open and fanout writes per publish.

Before million-user scale, evaluate fanout-on-write versus fanout-on-read using measured relationship/frequency distributions.

---

### SCL-006 — Moderation has data capture but not an operating system

**Severity:** P1 before broad public launch

Reports and blocks are not enough. The repository does not define a complete operator workflow, evidence retention policy, response targets, appeal/correction path, escalation, or abuse analytics.

**Impact**

- Harmful content can be reported but not resolved predictably.
- Operators may inspect sensitive faith content without a defined least-privilege policy.

**Required correction**

Create a minimal moderation runbook:

- report taxonomy and required evidence;
- authorized operator roles;
- response and escalation targets;
- retention/deletion rules;
- audit logging;
- emergency disable/remove paths;
- user-visible status and appeal wording.

---

### SCL-007 — Repeated rule lookups add cost and complexity

**Severity:** P2
**Evidence:** `firestore.rules`

Membership helpers use repeated document `get`/`exists` patterns. With groups capped around 12 members this is not an immediate blocker, but it should be tested against rule evaluation limits for compound writes and busy screens.

**Required correction**

Use emulator tests to measure representative read/write rule paths. Consolidate lookups only where it improves both correctness and rule-cost headroom.

---

## What is already strong

- Firestore and Storage rules are substantially more deliberate than a typical MVP.
- Sensitive mutations are often moved into callable functions.
- Group size is bounded.
- Blocks, reports, lifecycle states, schema versions, and migration tests exist.
- Insight expiry and cleanup are designed as explicit concepts rather than UI-only behavior.
- The remediation introduced a useful foundation for idempotency and server-authoritative actions.

These strengths reduce risk, but they do not negate the lifecycle, privacy-copy, and scaling issues above.

---

## Required security verification before release

1. Attempt identity spoofing from a modified client/emulator.
2. Copy a media download URL, then remove membership and delete the message; test whether the URL still works.
3. Replace profile/group covers repeatedly and reconcile Storage objects.
4. Interrupt account deletion after each phase and retry it.
5. Delete an owner with groups containing media and verify Firestore plus Storage absence.
6. Enable App Check in a staging project and run every callable from release builds.
7. Abuse-test group creation, messages, comments, reactions, reports, and Insight fanout.
8. Run migration fixtures for all legacy shapes, maximum note lengths, null/wrong-type fields, and Unicode.
9. Run a migration, deliberately fail halfway, resume, and verify no duplicate side effects.
10. Drive lifecycle/cleanup datasets beyond 500 eligible records and verify the backlog drains.
11. Test sign-out/account switching for local Firestore cache, drafts, cached media, and outbox isolation.
12. Review every privacy/deletion sentence against the verified backend lifecycle.

---

## Recommended release gate

Do not call the app production-ready until:

- the false E2EE statement is removed;
- media retention/revocation behavior is accurately documented and the worst orphan paths are fixed;
- migration no longer loses data and has a real rollback/recovery path;
- lifecycle batching cannot exceed platform limits;
- account deletion is resumable or the product truthfully limits it while a safe job system is implemented;
- App Check and basic rate controls are operational;
- privacy, support, and moderation responsibilities have named owners.
