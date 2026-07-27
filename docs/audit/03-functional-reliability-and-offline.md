# Report 3 — Functional Reliability and Offline Behavior

## 1. Offline media and the reported missing visuals

The reported offline defect is confirmed. It is not one bug; it is a family of inconsistent image behaviors.

### Confirmed causes

1. `main_hall_screen.dart` uses raw `NetworkImage` for the current profile and group covers.
2. Other screens use cached providers but do not consistently provide loading/error widgets.
3. A fallback often exists only when a URL is `null`; an empty, invalid, deleted, or never-cached URL still attempts remote loading.
4. Some absent member photos are replaced with random Unsplash people. This is misleading and fails offline.
5. Insight themes use remote Unsplash backgrounds.
6. Some local fallback person icons use nearly/exactly the avatar background color, so the fallback is present but invisible.
7. There is no shared image policy, cache policy, or offline placeholder component.

### Important distinction

Material and Font Awesome fonts are bundled in the APK. The APK build artifacts show those fonts were tree-shaken to small local resources. Most “missing icons” are therefore likely remote avatars/covers/status images or invisible fallbacks—not a general inability to render Material icons.

### Required implementation

Create:

- `BraidAvatar`
- `BraidRemoteImage`
- `BraidGroupCover`

Required behavior:

- trim and validate URL;
- treat null/empty equally;
- cached network rendering;
- loading placeholder;
- error placeholder;
- deterministic initials/color;
- local bundled fallback;
- accessible semantic label;
- bounded decode size/thumbnail;
- optional cached/stale indicator;
- no random human identity placeholder.

### Required offline matrix

- first launch without internet;
- warm cache without internet;
- image never cached;
- invalid URL;
- empty URL;
- remote file deleted;
- cache evicted;
- slow network;
- connection lost during load;
- account changed while cache exists.

## 2. Application-wide offline-state gap

Firestore can cache supported document data, but the app does not provide a coherent offline contract for:

- Storage media;
- arbitrary network images;
- queued writes;
- failed media uploads;
- pending invitations;
- draft persistence;
- stale profile/group data;
- retry.

Recommended global states:

- **Offline — viewing saved data**
- **Pending — will send when connected**
- **Failed — tap to retry**
- **Stale — last updated [time]**

The user should never have to infer connectivity from blank content.

## 3. P0/P1 — Group invitations are broken

### Failure chain

1. Group details shares `https://braidapp.com/join/{groupId}`.
2. Android handles only `bsgc-app.web.app/invite`.
3. `DeepLinkService` handles only an `inviter` query parameter.
4. The group `joinGroup()` method has no matching group-link call path.
5. Deployed `assetlinks.json` names `com.example.bsgc_app`.
6. The fingerprint is `YOUR_SHA256_FINGERPRINT_HERE`.
7. The real package is `com.bsgc.bsgc_app`.
8. The live `braidapp.com/join/...` request redirects to `/lander`.

This means App Link verification fails and the primary group invitation cannot complete.

Required replacement:

- one canonical HTTPS domain;
- expiring/revocable invite token;
- verified association file;
- installed/not-installed landing;
- authentication/onboarding continuation;
- join confirmation;
- full/already-member/expired/revoked handling;
- server-validated capacity.

## 4. Group plan and lifecycle defects

### Topic plans do not progress

The Days grid is rendered with no tap action. Topic-group progress therefore cannot advance.

### Book/topic editing is unreachable

The UI says study content can change during extension, but the controls remain inside `AbsorbPointer` and there is no functional extension-edit state.

### Creation copy is inaccurate

The creation experience describes choosing one or more Bible books, but the model/UI supports one.

### Dates do not govern behavior

- Chat remains accessible before the configured start.
- The end date does not close, archive, recap, or transition the group.
- There is no complete status model.

### Admin model is fragile

- Admin is inferred from `members.first`.
- Creator leave can silently transfer control by array order.
- There is no explicit transfer ownership.
- There is no robust remove-member/moderator flow.
- Add Members can be visible without adequate role authorization.

### Concurrency and feedback

- Join/add/extension use read-then-update patterns.
- Group edits can be fire-and-forget.
- A caller can display success before persistence.
- `StudyRoom` receives a snapshot of the group and does not fully subscribe to metadata changes, leaving progress/cover/details stale while open.

Required lifecycle:

`draft → scheduled → active → completed → archived`

Every transition must define allowed actors, required fields, notifications, and UI behavior.

## 5. Chat reliability

### Draft loss

Key `sendHybridMessage` calls are not awaited. The composer clears before the service confirms success.

Possible result:

- message is lost;
- user sees no retry state;
- attachments may have uploaded without a message;
- group preview/unread state may partially update.

### Non-atomic side effects

Message creation, group last-message metadata, unread counters, and interaction counters are separate operations. Partial success and inconsistent state are possible.

### Required outbox model

Each outgoing message needs:

- stable client-generated ID;
- locally persisted draft;
- queued/sending/sent/failed state;
- idempotent retry;
- upload progress;
- cancellation;
- draft restoration;
- cleanup of abandoned media.

### Pagination

“Load more” increases the query limit from 20 to 40 to 60. Previous documents are downloaded and processed again. End-of-history detection remains unreliable.

Use cursor pagination with `startAfterDocument` and deduplicate by stable message ID.

### Clear chat

The client reads and updates every message. Rules deny those updates and the operation becomes increasingly expensive.

Use one per-user `clearedBefore` cursor or private message-state record.

## 6. Voice messages

Voice audio is base64-encoded into the Firestore message.

Problems:

- approximately 33% encoding expansion;
- full file held in memory;
- no clear recording-duration cap;
- Firestore document maximum of 1 MiB;
- every message read carries the audio payload;
- local recording is deleted before confirmed send;
- offline/oversized failure can lose the only copy.

The recorder is also not comprehensively preserved/stopped through lifecycle transitions.

Required design:

1. Record to a temporary local file.
2. Preserve draft through pause/termination.
3. Validate duration/size.
4. Upload to Storage with progress.
5. Write metadata/path in Firestore.
6. Delete local temporary data only after acknowledgement or explicit discard.

## 7. Images, videos, and documents

### Images

Image support is closer to complete but still needs:

- upload outbox;
- decode-size limits;
- thumbnail generation;
- retry/cancel;
- offline placeholders;
- removal of orphaned uploads.

### Video

Video can be selected/uploaded, but recipients largely see “Video Attachment.” Playback, thumbnail, duration, download state, retry, and failure handling are incomplete.

### Documents

Documents similarly render as a generic label without a complete open/download/filename/size experience.

### Memory pressure

Several flows read attachment bytes into memory. A permitted 50 MB file can cause major pressure or termination on lower-end devices.

MVP recommendation: keep images and properly implemented voice; hide video/document sending until complete.

## 8. Message composer implementation issues

Voice-part text controllers are recreated during builds. This can cause:

- cursor jumps;
- lost edits;
- unnecessary allocations;
- inconsistent state during rebuild.

The recorder/draft should belong to a controller/state object with deterministic disposal and restoration.

One light-gray bubble theme uses pale voice metadata on a near-white surface, producing poor contrast.

## 9. Insights defects

### Global and unbounded feed

The active query listens to all unexpired Insights without a limit/pagination or audience filter.

Consequences:

- privacy contradiction;
- escalating reads;
- increasingly expensive client grouping/sorting;
- a malformed record can affect the global feed.

### Historical personal feed

Personal Insights load broad history and filter expiry on the client.

### Hot, unbounded arrays

`seenBy` and `likedBy` arrays grow on content/comment documents. This increases contention and approaches Firestore's 1 MiB document limit.

### Seen-state corruption

Adding a comment or reaction resets `seenBy` to the actor. “Has viewed” is overloaded to mean “has viewed current activity.”

### Client-controlled time

Expiry and ordering rely on client timestamps without strong server validation.

### False success

Create Insight calls the service without awaiting it, then plays fixed delays and success animation. The UI can claim creation succeeded when the write failed.

### Saved Insights

The client uses `saved_insights`, but rules do not authorize it. Saving/listing fails.

### Missing safety/audience

No explicit audience enforcement, report, block, or moderation system exists.

Recommended MVP: remove the global ephemeral feed and replace it later with group-scoped/deliberately shared Reflections.

## 10. Notes defects

The per-user Notes path is one of the better data boundaries, and create-note correctly awaits save.

Remaining issues:

- no autosave or durable draft;
- back navigation can lose writing;
- view/edit save paths can be fire-and-forget while showing success;
- local model/date can remain stale after save;
- no title/body length validation;
- duplicate creation experience overlaps with Insights;
- backup reads the wrong Notes path.

Recommendation: make Notes the foundation of a unified Reflection model rather than maintaining parallel creation systems.

## 11. Bible service defects

### Initialization race

`BibleService.init()` starts `_loadTranslation` calls without awaiting them. Startup can complete before Bible data is available.

### Misrepresented availability

UI options: KJV, WEB, ESV, BBE, NIV, NLT, MSG, AMP.

Actual:

- KJV: complete;
- WEB: complete;
- ESV: three dummy entries;
- BBE: three dummy entries;
- NIV/NLT/MSG/AMP: not loaded.

The UI can state that ESV/BBE are downloaded even though the files are dummy data. Unavailable translations return errors.

Required MVP correction:

- expose only KJV and WEB;
- await initialization;
- provide a loading/error state;
- verify attribution/license text;
- add licensed translations only through authorized assets/APIs.

## 12. Backup and restore defects

### Wrong paths

- Backup reads root `notes`; actual Notes use `users/{uid}/notes`.
- Backup uses `savedInsights`; current service uses `saved_insights`.

### Missing IDs

Restore uses `note['id']` and `insight['id']`, but serialization does not reliably include document IDs.

### Reliability and safety

- initialization/registration futures are not consistently awaited;
- background task can silently return when Drive authorization is unavailable;
- dispatcher can report success after no backup;
- temporary personal JSON is not securely cleaned up;
- client resources are not reliably closed;
- no schema version/checksum/encryption;
- restore does broad profile merge;
- no validation, staging, rollback, or conflict policy.

### Trust problem

Settings tells users to bypass Google's unverified-app warning. Remove this instruction and the feature from MVP.

## 13. Notifications

### Initialization

`_isInitialized` is set before awaited setup. A first failure prevents later retry.

### Foreground behavior

Foreground messages mainly play sound. The local notification plugin is not fully initialized to show consistent foreground banners.

### Channel mismatch

Android channels are created, but the Cloud Function does not consistently set matching channel/sound fields.

### Payload/routing mismatch

- foreground code checks message `type`;
- the function payload does not provide a consistent `type`;
- payload mainly contains `groupId`;
- no complete `getInitialMessage`/`onMessageOpenedApp` routing.

### Preference mismatch

Mute is applied to some action sounds but not consistently to message/Insight sound paths.

### Multi-device and stale tokens

One token per user overwrites earlier devices. Invalid/stale tokens are not removed.

### Cloud Function

- sequential member-user reads;
- client-supplied sender name;
- no robust partial-failure retry;
- no token cleanup;
- private message previews without lock-screen privacy controls;
- no regional/operational configuration documented.

## 14. Startup, onboarding, profile, and settings

### Startup

- Firebase initialization errors are caught but Firebase-dependent services continue.
- User-data fetch errors can route to Main Hall, allowing an uncached/incomplete user to bypass onboarding.
- No explicit retry/stale/offline onboarding state.

### Sign-out

- Google sign-out happens before Firebase sign-out; an exception can leave Firebase authenticated.
- user-specific local caches/background jobs are not comprehensively removed.

### Profile

- Notes count is displayed as “Insights” in one statistic.
- referral reach performs sequential second-degree queries.
- redundant streams/count queries increase reads.
- state is mutated during build in places.
- loading can render an empty `SizedBox`, looking broken.
- gender defaults missing data to Male and is binary despite no clear product requirement.

### Phone editing

International numbers can be corrupted by removing three digits after `+`; country defaults to NG.

### Settings

- hardcoded `2.1 MVP` while package is 2.2.0;
- Mute Contacts has no action;
- Prayer Alarm is “coming soon”;
- Delete Account is a placeholder;
- backup is broken;
- excessive cosmetic controls;
- missing privacy, contact-sync, storage, group-mute, data, and safety controls.

### FAQ contract mismatches

Claims not matched by implementation include:

- contact-only Insights;
- simultaneous group limit;
- described cooldown behavior;
- direct messages inside a group;
- converting Notes to Insights;
- saving Insights into Notes;
- study-cycle ending behavior.

The FAQ must be treated as a product contract and tested against the app.

## 15. Testing and observability

The only Flutter test is the default counter test and does not match Braid. There are no meaningful unit, widget, integration, rules, function, offline, golden, accessibility, or load tests.

The tracked analyzer report contains 77 findings, but a fresh toolchain run is required.

Crashlytics exists, but many catches only `debugPrint`, swallow exceptions, or report success optimistically.

Minimum operational events:

- authentication/onboarding failure;
- invitation open/join outcome;
- rule denial;
- message queued/sent/failed;
- upload started/failed/orphaned;
- notification delivery/click;
- group lifecycle transition;
- account deletion state;
- backup state if ever restored.

Logs must not contain message bodies, phone numbers, tokens, or private identifiers.
