# Functional reliability and offline audit

## Primary-journey findings

### REL-001 — P0 — Hide and clear actions are functionally disconnected

**Evidence**

- `ChatService.deleteMessageForMe()` writes `users/{uid}/group_state/{groupId}/hidden_messages/{messageId}`.
- `ChatService.clearChatForMe()` writes `clearedBefore`.
- The study room filters only `message.space` and the legacy `message.deletedFor` list.
- No client code subscribes to `hidden_messages` or reads/applies `clearedBefore`.
- New v2 messages cannot contain `deletedFor` under current rules.

**Impact**

The app confirms “Message hidden for you” and “Earlier messages are now hidden for you,” but reopening or rebuilding the room shows the same content. These are false success states in a privacy/safety control.

**Correction**

Create one account-scoped room-state stream/repository. Apply `clearedBefore` in the Firestore query or pager and merge the hidden-message ID set before rendering. Update this state optimistically with rollback. Add emulator-backed widget/integration tests that prove the item disappears and remains hidden after restart.

### REL-002 — P0 — Global pagination makes room spaces incomplete

**Evidence**

`GroupMessagePager` queries the latest 30 messages across the entire group. `StudyRoomScreen` then filters that one page into Reflection, Discussion, or Prayer. If the selected space has no item in the current global page, `_EmptyStudySpace` is shown. There is no list to scroll and therefore no way to trigger `loadOlder()`.

**Impact**

Thirty recent Discussion messages can make older Reflections and Prayers appear not to exist. This breaks the product’s central promise that these are durable, distinct spaces.

**Correction**

Use one cursor-paginated query/controller per message space (`where('space', isEqualTo: ...)`, ordered by timestamp), with the required composite indexes. Keep Plan separate. Each space needs its own loading, cached, empty, error, and “load older” state.

### REL-003 — P1 — Tapping a My Insights row opens the wrong Insight

Every row passes the complete `[insights]` group to `ViewInsightScreen`, which initializes the group at index zero/first unseen. The tapped `index` is never passed. Tapping the third Insight generally opens the first.

Add an explicit initial insight index or open a one-item route. Test every row, not only the first.

### REL-004 — P1 — Seen state was migrated, but unread UI still reads legacy arrays

`markAsSeen()` writes `users/{uid}/insight_state/{insightId}`. New Insight documents do not receive `seenBy`. `InsightsRow` and `ViewInsightScreen` continue deriving unseen counts and first-unseen position from `InsightModel.seenBy`.

New Insights therefore remain visually “unseen,” unread badges do not settle, and opening a group can repeatedly start from the first item. Join feed data with the current user’s bounded state documents or denormalize a safe per-user read marker into feed pointers.

### REL-005 — P1 — “Saved for revisiting” expires into an invisible stale pointer

The app saves only an Insight ID. After `expiresAt`, a contact no longer satisfies `canReadInsight()`, so `getSavedInsights()` catches the denied read and returns nothing. The saved pointer is not removed by cleanup.

This contradicts “Saved contacts’ Insights stay here for private revisiting.” Decide the real contract:

- saved means a private immutable snapshot retained by the saver with author/audience consent; or
- saved means a bookmark that expires, and the UI must say so and clean it up.

Do not promise permanent revisiting while storing only an expiring pointer.

### REL-006 — P0 — Note edit reports success before validation or persistence

`ViewNoteScreen._saveChanges()` calls `saveNote()` without awaiting or catching it, immediately exits edit mode, and displays “Note saved!” Editing can also produce an empty body or exceed backend limits because the edit fields have no validation/max lengths.

A rejected write is an unhandled asynchronous failure and the only visible copy can be lost after navigation. Await the write, preserve a local draft, validate with the same contract as creation/rules, show pending/offline state, and report success only after an appropriate durability boundary.

### REL-007 — P1 — Insight and comment actions are optimistic without rollback

- Like and save toggle UI first, then await a write without `try/catch`.
- Comment text is cleared before `addComment()` and failure is not handled.
- Comment-reaction writes are fire-and-forget.
- Save-status and reaction-status reads can fail without a recoverable state.

Introduce per-action busy/pending state, rollback on rejection, preserve failed comment text, and provide retry. Ensure offline behavior is deliberate rather than an indefinitely pending Future.

### REL-008 — P1 — Comment pagination returns the oldest 100 forever

Comments use `orderBy('createdAt').limit(100)`. Once an Insight has more than 100 comments, newer comments do not appear; the displayed count is also capped and replies whose parents are outside the page can disappear.

Use descending cursor pagination (or `limitToLast` where appropriate), render in chronological order after retrieval, and maintain an authoritative bounded count.

### REL-009 — P1 — Unread counts rise while the room is already open

Unread is reset only immediately before navigation. The message trigger increments recipient counts for all later messages, including messages received and rendered while that user is in the room. Nothing marks read continuously or on exit.

Track `lastReadAt`/visible message, reset on lifecycle changes and route exit, and derive unread from an event/count contract that cannot drift.

### REL-010 — P1 — Notification navigation loses the actual target

The payload contains `messageId`, but the app opens only the group’s default Discussion space. It neither identifies the message’s space nor loads/scrolls to that message. If the message is outside the global 30-message page, the notification appears to lead nowhere.

The destination is also cleared before its Firestore read; an offline failure loses the navigation with no retry.

Include space in the payload, persist the pending destination until successful, query around the target message, highlight it, and provide a retryable unavailable state.

### REL-011 — P1 — Invalid invitation tokens can poison every app entry

Pending invite state is cleared only after successful redemption. Expired, revoked, used, malformed-at-server, or full-group errors are all treated like a temporary network failure and retain the token indefinitely. Every app entry retries it.

Map callable codes. Keep only retryable network/unavailable failures. Clear terminal tokens and offer “Dismiss invitation” in the error UI.

### REL-012 — P1 — Notification switch can say On when OS permission is denied

`updatePreferences()` persists `enabled: true` before requesting permission. `registerCurrentDevice()` silently returns when permission is denied. No failure is returned, so Today hides the permission offer and Settings keeps the switch on despite no registered enabled device.

Return a permission result, reconcile with OS settings on resume, display “Blocked in system settings,” and deep-link to system settings when appropriate.

### REL-013 — P1 — Outbox writes are not fully process-safe

`MessageOutboxService._write()` writes a temp file, deletes the current metadata, then renames the temp file. Process death between delete and rename leaves only `.tmp`; `list()` ignores it. Corrupt JSON is silently hidden while left on disk. The “process-safe” comment is therefore incorrect.

Use atomic replacement appropriate to each platform, retain/restore a backup like `DraftService`, recover valid temp files at startup, quarantine corrupt entries visibly, and test forced termination at each write boundary.

### REL-014 — P1 — Draft reply context races message loading

Draft restoration runs in parallel with pager initialization and looks for the replied-to message only in the controller’s current list. If messages have not arrived or the parent is older than the first page, `_replyToMessageId` is cleared from UI state and a later draft save can erase it.

Retain the ID independently, resolve the parent asynchronously/by ID, and show an “original message unavailable” placeholder rather than discarding the relationship.

### REL-015 — P1 — Voice messages do not have offline caching parity

Images use a disk-backed cache. Voice playback passes a remote URL directly to `audioplayers`; there is no download/cache manager, integrity check, or locally retained playback source. Previously played voice content is not guaranteed offline.

Add an account/group-scoped authenticated media cache with size/LRU policy and explicit download state. Never promise general cached media when only images have that behavior.

### REL-016 — P1 — Rapid chapter updates can lose progress

Each chapter tap copies the last server-rendered list and writes the complete list. Rapid taps can run concurrently from the same stale list; last completion wins and drops earlier taps.

Serialize updates or maintain optimistic local state with a transaction/operation queue. Disable only the affected chip while saving and reconcile server rejection.

### REL-017 — P1 — Current-user identity has competing sources

Profiles use Firestore in some screens but Firebase Auth `displayName`/`photoURL` in messages, comments, Insights, and “My” avatars. Firestore is documented as canonical, yet Auth updates are allowed to fail. `EditProfileScreen` loads Firestore name/bio but continues rendering the Auth photo.

This produces stale names/photos and inconsistent offline identity. Use a single cached `CurrentProfileRepository`, and make all authored records/server denormalization derive from that authoritative profile.

### REL-018 — P1 — Profile loading discards good partial data

`ProfileScreen` loads the public profile and up to 500 connections in one `Future.wait`. If the connection query fails, an available cached profile is discarded and generic identity is displayed. Group-member loading similarly fails the entire list if one profile read fails.

Handle independent results independently and retain last good state. Offline identity should not depend on a contact-count query.

### REL-019 — P1 — Startup waits on two full Bible decodes before first frame

`main()` waits for Firebase, then both Bible JSON assets and deep links before `runApp()`. The two raw Bible files total about 8.8 MB and are parsed into much larger in-memory object graphs. There are no timeouts around startup services.

Render the app shell immediately after essential Firebase/auth initialization. Lazy-load or isolate-index Bible data behind a ready state. Deep-link and Bible failures must not delay the first frame.

### REL-020 — P2 — Main groups retry does not create a new recovery action

On first stream error, `_LoadError(onRetry: () => setState(() {}))` rebuilds with the same final stream. Firestore streams may reconnect automatically, but the button itself does not resubscribe or perform a read, so its promise is misleading.

Expose a repository retry/recreate operation, or label the state as automatic reconnect without a fake button.

### REL-021 — P1 — Last-message summaries survive edit and deletion

The group summary is updated only by the message-create trigger. Editing/tombstoning the latest message or deleting an account does not recompute `lastMessageText`/sender. The Groups screen can continue displaying text that the author deleted.

Handle message writes, not only creates, and recompute the latest visible summary transactionally. Test edit, delete, account deletion, and concurrent newer messages.

### REL-022 — P1 — Private and contacts composers have no durable drafts

Only the group composer persists drafts. A long Journal reflection or 12,000-character Insight can be lost on process death, back navigation, or a failed publish followed by closure.

Share a durable composer foundation across audiences, with account-scoped autosave and explicit discard. Keep audience-specific publishing rules separate.

### REL-023 — P2 — Audio preparation failure offers no recovery

The app says a recording “is saved locally” when preparation fails, but provides no path to find, retry, attach, or delete that temp recording. It can become an orphan.

Move the raw recording into a visible recoverable draft state before processing, or delete it after explicit confirmation.

### REL-024 — P2 — Archived groups become unreachable

`getUserGroups()` filters archived groups and there is no Archived screen. Archive is irreversible in the UI. This conflicts with the broader “revisit what changed” promise.

Add an Archived section/read-only history or clearly define archive as permanent removal from the member experience.

### REL-025 — P2 — Lifecycle timing is approximate and not communicated

Groups transition on an hourly scheduler. A scheduled group may stay read-only for almost an hour after its displayed start, and a completed group may remain writable similarly. At scale, the scheduler has more severe backend failure modes described in Report 2.

Either enforce effective lifecycle from timestamps in rules/UI or run a robust sufficiently frequent transition mechanism and show exact timezone-aware timing.

### REL-026 — P2 — Date picker and server contract disagree

The UI permits ranges up to five years and can allow a same-day range. The Function rejects same-day/end-equal-start and anything over 365 days. The resulting UI exposes raw `Error: ...` text.

Use one shared contract: constrain the picker/validator, explicitly decide whether one-day studies are supported, and map server errors to field-level guidance.

### REL-027 — P2 — Raw internal errors reach users

Confirmed examples include image attachment, group creation/editing, settings account deletion, and some callable messages. Raw plugin/Firebase exception text is unstable, technical, and can reveal implementation details.

Use typed domain failures, log sanitized diagnostics to observability, and show actionable user language. Never use `error.toString()` as product copy.

### REL-028 — P2 — Missing or unstable timestamps become “now”

Group, message, note, Insight, and comment compatibility readers frequently substitute `DateTime.now()` for malformed/missing timestamps. Rebuilds can reorder data and misrepresent history.

Use a stable epoch/created fallback, mark malformed records, and make migration repair them. Pending server timestamps need a stable client-created timestamp retained separately.

### REL-029 — P2 — Outbox has no quota or retention policy

Offline attachments can accumulate without a total byte/count cap. A user can fill application storage with 8–10 MB entries. Automatic retry on room open can also consume substantial mobile data without a policy.

Add per-user/global quotas, age cleanup, available-space checks, Wi-Fi/mobile policy, upload progress/cancel, and a central “Pending uploads” view.

### REL-030 — P2 — Startup/auth errors can become indefinite loading

`SharedPreferences.getInstance()` is outside startup error handling. Auth stream errors are not represented; before the first auth value the spinner can remain indefinitely, while later errors retain a stale screen.

Add bounded startup stages, auth error UI, retry, and safe cached-session behavior.

## Offline capability matrix after remediation

| Capability | Code-level state | Remaining issue |
| --- | --- | --- |
| Avatar/cover | Disk cache plus deterministic fallback | Physical cold/warm tests absent; profile source can be discarded/stale |
| Bible KJV/WEB | Bundled | Parsed before first frame; memory/cold-start cost |
| Group/message text | Firestore persistence | hide/clear disconnected; cross-space paging incomplete |
| Group image send | Durable local outbox | atomic crash window, quota/progress absent |
| Group voice send | Durable local outbox | failed preparation recovery absent |
| Group image view | Cached | error reason mislabeled as offline |
| Group voice view | Direct URL | no deliberate offline cache |
| Journal create/edit | Firestore write | no durable draft; edit falsely reports success |
| Insight create/comment | Online/Firestore write | no durable draft; failed comments/actions lose/lie |
| Invite | Pending token | terminal token persists; no dismiss |
| Notifications | Local prefs + device doc | OS-denied state can still show enabled |

## Required verification

Automate what can be automated, then run on a low-memory Android device and a current Android device:

1. cold/warm airplane launch with and without prior profile/media cache;
2. every room space with more than 30 interleaved messages;
3. hide/clear, restart, account switch, and removed-member scenarios;
4. process kill at each outbox/draft write and upload stage;
5. rapid progress taps and concurrent multi-device progress;
6. notification tap to old Reflection/Prayer messages while online/offline;
7. denied/permanently-denied notification and microphone permissions;
8. note/Insight/comment failure with text preservation;
9. saved Insight before and after expiry;
10. unread counts while actively viewing the room.
