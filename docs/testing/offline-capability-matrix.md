# Braid offline capability contract

**Status:** repository contract; physical-device verification still required
**Scope:** Android MVP behavior on `codex/bsgc-full-remediation`

Braid is offline-resilient, not universally offline-first. The app must never
describe a write as saved merely because Firestore accepted it into a local
queue. User-content saves complete only after server acknowledgement, except
for the explicitly durable local drafts and message outbox below.

## Capability matrix

| Journey | Cold offline, no prior cache | Warm offline, usable local state | Offline write behavior | Reconnect behavior | Honest failure or state copy |
| --- | --- | --- | --- | --- | --- |
| App startup | The shell renders immediately. Firebase initialization has a 15-second bound and offers Retry. A signed-in private profile may be unavailable after a process restart because private Firestore disk persistence is deliberately disabled. | In-process screen state remains usable while the process lives. Bundled Bible content remains available. | Not applicable. | Retry re-runs bounded startup. Authentication/profile sections recover independently. | Startup failure is retryable; the UI must not spin forever. |
| Authentication/profile | Sign-in needs network. Previously downloaded remote profile photos may render from the bounded image cache; otherwise deterministic initials/icons render. | Last successfully rendered identity remains while contact/count sections retry independently. | Profile changes require server acknowledgement. | Failed identity or contact sections can be retried locally without blanking the other section. | “Profile unavailable” and section-level retry replace blank identity or an endless loader. |
| Group list/details | A fresh process cannot promise private group data offline. Cached cover media may render; uncached media uses a local fallback. | Existing in-process group data remains visible. Missing member profiles do not hide available members. | Privileged group changes require network/server Functions. | Retry the failed operation or section; canonical server state wins. | Operation-specific stable error copy; unavailable member profiles are labelled. |
| Study Room messages | A fresh process cannot load uncached history. | Loaded history remains visible. Account-scoped drafts and queued outgoing messages survive relaunch. | Text and supported local image/audio parts enter the durable outbox with a stable message ID. The queue is capped at 25 items and 64 MiB per account, expires after 30 days, and stops automatic retry after six attempts. | Due items retry with exponential backoff; manual Retry bypasses the delay. A message leaves the queue only after server acknowledgement. | Queued/failed/corrupt/missing-attachment states remain visible with Retry or Discard as appropriate. |
| Message attachments | Uncached remote media is unavailable. | Locally queued attachments and cached voice recordings remain available within their retention limits. | Supported attachments are copied into an account-scoped outbox before enqueue. Per-file and total quota failures are shown before claiming success. | Upload resumes through the outbox; stable IDs and paths prevent duplicate logical messages. | Missing files become non-retryable visible items instead of disappearing. |
| Voice playback | Uncached remote audio cannot play; the UI says it must be downloaded first. | Explicitly downloaded or first-play-cached audio plays from the account-scoped cache. | Download progress is visible. The cache is capped at 50 MiB per account with 14-day expiry and least-recently-used eviction. | Download/first play may be retried. Cached playback does not require reconnect. | Unsupported format, no authorization, removed file, offline miss, and transient failure have distinct copy and a retry/download action. |
| Bible reading | KJV loads from the bundled asset without network. | Requested bundled translations load on demand and remain in memory for the session. | Reading does not create a network write. | Not required for bundled content. | Translation-load failure is local and retryable; startup is not blocked on decoding every Bible. |
| Journal/private notes | Existing server notes are not promised after a fresh offline restart. Composer drafts are account-scoped and durable. | A current composer draft restores text and supported local context. | Save/delete requires server acknowledgement. A failed save retains the composer draft and must not display a durable-success state. | Retry submits the same logical note; server state becomes canonical. | The draft stays available and the user receives retryable save copy. |
| Insights/comments/reactions/saves | A fresh process cannot load an uncached feed. | Loaded feed/comments remain on screen while the process lives; composer drafts restore. | Publish is server-authoritative. Comment text is retained on failure. Like/save/reaction UI is pending and reversible; completion waits for server acknowledgement. | Retry reuses stable records where applicable and reconciles to canonical server state. | Failed optimistic actions roll back; unavailable saved source content is explained rather than shown as permanently saved. |
| Notifications/deep links/invites | A stored destination or retryable invite is retained until it can be resolved; content still needs authentication/network. | Already resolved navigation remains normal. | No content write is implied by tapping a notification. | Authentication/network restoration retries resolution. Terminal invite failures are cleared; retryable failures remain dismissible/retryable. | Deleted, unavailable, no-access, invalid, expired, and transient states are distinct. |
| Sign-out/account switch | Not applicable. | Not applicable. | Before the next account is shown, Braid clears the signing-out account’s drafts, outbox, voice/image caches, pending routes/invites, and selected navigation state. Private Firestore disk persistence is disabled and cleared at startup. Android app-data backup and device transfer are excluded. | The next account starts with its own scoped local directories and keys. | Cleanup failures are logged; no previous account content may be rendered to the next account. |

## Required airplane-mode verification

Run this matrix on an Android emulator and at least one physical device:

1. Fresh install, launch offline, confirm bounded startup failure and Retry.
2. Sign in online, visit every primary tab, then enable airplane mode without
   killing the process and confirm partial/cached states.
3. Queue text, image, and voice messages; kill the app; relaunch offline; check
   that every valid item remains visible.
4. Corrupt a test outbox metadata file and remove a queued attachment; confirm
   visible Discard-only states.
5. Restore network before and after the retry due time; confirm exactly one
   logical message is created.
6. Download voice audio, kill/relaunch offline, and play it. Repeat with an
   uncached recording and confirm the offline-miss explanation.
7. Save a note/comment/reaction while offline; confirm no durable-success
   message is shown and the recoverable text/state remains.
8. Sign out after creating drafts, queued media, and cached voice; sign in as a
   second account and inspect every primary screen for leakage.
9. Deny notification permission, tap a notification/invite offline, restore
   authentication/network, and confirm exact-destination recovery.

## Evidence boundary

Automated tests cover startup timeout/retry, backup exclusion, server-write
acknowledgement, outbox validation/recovery/quota/backoff, voice cache
progress/isolation/eviction/failure classification, and key UI states.

The matrix is not considered fully passed until the physical/emulator steps are
recorded with device/OS, build commit, result, and reproduction notes. Source
tests cannot prove Android process death, filesystem replacement boundaries,
actual radio transitions, media codec support, or cross-account visual leakage.
