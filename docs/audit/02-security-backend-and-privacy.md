# Report 2 — Security, Backend, and Privacy

## 1. Overall verdict

The current Firebase authorization model is a release blocker. Several UI problems can be repaired locally, but weak Security Rules allow a modified or malicious client to bypass the UI completely. Client-side checks are not authorization.

The rules present in the repository were audited. The deployed Firebase console must still be compared with these files because deployed rules can differ from Git.

## 2. P0 — Group privacy and membership integrity

### Finding

`firestore.rules` allows authenticated users to read group documents. Group updates are primarily constrained by the resulting member count being no greater than twelve.

### Abuse path

A signed-in attacker can potentially:

1. Enumerate group documents.
2. Add their UID to `members`.
3. Pass the membership check used for message reads.
4. Read private group discussion.
5. Remove or reorder members.
6. Alter group metadata, progress, dates, or other writable fields.
7. Become the UI's implied administrator if administration is derived from `members.first`.

### Impact

- Private-study confidentiality failure.
- Membership takeover.
- Group corruption.
- Loss of admin control.
- Broken trust promise.

### Required correction

- Add an immutable `ownerId`.
- Represent membership/roles explicitly.
- Restrict group reads to authorized members, with only narrowly scoped invitation metadata exposed.
- Do not allow arbitrary member-array changes from ordinary clients.
- Validate allowed keys, types, string lengths, state transitions, and immutable fields.
- Use transactions or server operations for joins, leaves, capacity, role changes, and ownership transfer.
- Add Emulator tests for every allow/deny path before deploying.

## 3. P0 — User directory and device-token exposure

### Finding

Any authenticated user can read user documents. These documents contain phone information and FCM tokens. Multiple features download the entire `users` collection.

Confirmed call sites include:

- `contact_cache_service.dart`
- `add_member_sheet.dart`
- `inviter_selection_screen.dart`

### Impact

- Registered phone information can be enumerated or scraped.
- FCM registration tokens are visible to clients that do not need them.
- The complete account directory is exposed.
- The architecture violates data minimization.
- A malicious signed-in account can automate extraction.

### Required correction

Split data into:

1. `users_private/{uid}` — phone, consent, deletion state, sensitive account data; owner/server only.
2. `users_public/{uid}` — minimal safe public/member representation.
3. `users/{uid}/devices/{deviceId}` — FCM token and timestamps; owner/server only.

Group member views should be derived only for authorized members. A public profile must not include phone or device tokens.

## 4. P0 — Contact discovery is unsafe

### Current behavior

- Phone entry is required.
- Multiple numbers can be saved without ownership verification.
- Contact permission is requested during onboarding and again from the main experience.
- All users are downloaded.
- Phone suffixes are compared locally.
- Results are cached in ordinary `SharedPreferences`.

### Defects

1. **Phone ownership is unverified.** A user can claim another person's number.
2. **Suffix matching collides.** Matching the final 7–12 or 10 digits is not a stable global identity system.
3. **Duplicates are nondeterministic.** Later records can overwrite earlier matches.
4. **International parsing is incorrect.** `EditProfile` removes three digits after `+` for non-Nigerian numbers and initializes the phone component as Nigeria.
5. **Cached data is not account-scoped.** A later signed-in account can inherit mappings unless all relevant keys are cleared.
6. **Permission timing is coercive.** The user does not receive enough contextual value/disclosure before the system prompt.
7. **Data minimization is absent.** Every client receives data for people unrelated to that user.

### Scale consequence

The design is O(all users) per syncing user.

- 200,000 syncing users against 200,000 accounts is roughly 40 billion document reads for one complete sync per user.
- 1,000,000 against 1,000,000 is one trillion reads.

Those figures illustrate the shape of the problem; they are not a billing forecast. The architecture cannot be retained for large scale.

### Recommended MVP choice

Remove contact discovery and use secure group invite links/QR codes.

### If contact discovery returns later

- Verify phone ownership with OTP.
- Normalize E.164 server-side.
- Obtain explicit opt-in.
- Upload only a privacy-preserving representation necessary for matching.
- Match server-side.
- Return only minimal confirmed matches.
- Provide a disconnect/delete-synced-contacts control.
- Never expose the global directory.

## 5. P0 — Insight and comment ownership is not enforced

### Finding

Authenticated clients can update Insights and comments they do not own. Delete authorization relies on the stored `authorUid`.

### Potential abuse

A malicious client may:

1. Edit someone else's content.
2. Change `authorUid` to the attacker's UID.
3. Delete the content.
4. Write malformed types that strict Dart model casts cannot parse.

Malformed global content can become a denial-of-service vector if every feed client attempts to parse it.

### Required correction

- Creator identity must equal `request.auth.uid` on create.
- Author and creation timestamp must be immutable.
- Only the author or an authorized moderator may modify permitted fields.
- Reactions/read-state must not require arbitrary content-document updates.
- Validate strings, arrays, timestamps, audience, references, and allowed keys.
- Prefer server timestamps for order and expiry.

## 6. P0 — Storage rules are broadly permissive

### Finding

Authenticated users can read all stored files. Writes to broad profile/group/chat paths are controlled mainly by size:

- profile/group assets below 5 MB;
- chat media below 50 MB.

### Missing controls

- Owner or group membership.
- Content type.
- Approved extension.
- Path-to-document relationship.
- Immutable ownership.
- Prevention of overwrite.
- Upload status.
- Orphan cleanup.
- Per-user/group quota.
- Abuse/malware response.

### Required correction

Use paths such as:

- `users/{uid}/profile/{assetId}`
- `groups/{groupId}/messages/{messageId}/{assetId}`

Rules must validate `uid`, group membership, metadata, size, and content type. Final message creation should reference only an upload owned by the sender and intended group. Add cleanup for abandoned uploads.

## 7. P0 — User-generated-content controls are absent

Braid accepts text, images, audio, video, documents, comments, and reflections. A safe external beta requires:

- Report content.
- Report user.
- Block user.
- Group admin removal.
- Moderator review state.
- Terms/community guidelines.
- Abuse contact path.
- Rate limits.
- Evidence/audit preservation.
- Illegal-content and emergency escalation policy.

These are not optional million-user features. Store policies require adequate UGC safeguards before launch.

## 8. P0 — Account deletion and privacy lifecycle are incomplete

The Delete Account entry is a snackbar placeholder. There is no complete:

- in-app deletion request;
- reauthentication;
- group ownership transfer/closure decision;
- Firestore deletion;
- Storage deletion;
- device token invalidation;
- background job cancellation;
- retention policy;
- web deletion route;
- completion/failure state.

Required behavior:

1. Explain consequences and retained legal/security data.
2. Reauthenticate.
3. Resolve owned groups.
4. Disable the account promptly.
5. Queue idempotent deletion.
6. Remove private data, media, tokens, caches, and scheduled work.
7. Anonymize content only where the user explicitly understands that group history is retained.
8. Provide request status and retry handling.

## 9. P1 — Missing rules for visible features

The application uses collections without corresponding authorization:

- `cooldowns`
- `users/{uid}/saved_insights`
- `support_chats`

Consequences:

- leaving a group can fail on the cooldown write before membership removal;
- save/unsave Insight fails;
- support reads/writes fail.

Do not solve this with `allow read, write: if authenticated`. Define ownership, participant access, schemas, retention, and rate limits—or remove the feature.

## 10. P1 — Message rules contradict the UI

The client exposes reaction, star, edit, delete, delete-for-me/everyone, and clear-chat operations. Message updates and deletes are denied.

Recommended data boundaries:

- Message content: immutable after send, except a tightly defined short edit window if required.
- Reactions: separate per-user records or restricted map entries.
- Saved/starred: private per-user state.
- Deleted for me: per-user cursor/state.
- Deleted for everyone: authorized tombstone with audit fields.
- Clear chat: update one per-user `clearedBefore`, not every message document.

## 11. P1 — Membership and group state use non-transactional updates

Join/add/extension operations use read-then-update behavior. Concurrent clients can:

- exceed intended capacity;
- overwrite each other's member list;
- exceed extension limits;
- lose progress updates.

Capacity, lifecycle, owner transfer, and progress must be atomic and validated server-side or in Firestore transactions.

## 12. P1 — Client-controlled counters and identity

Several values are client writable or client supplied:

- interaction counts;
- sender display name in push payloads;
- Insight expiry/order timestamps;
- read/seen arrays;
- group progress.

These values can be spoofed or lost under concurrency. Authoritative counters and notification identity should be derived from trusted server data.

## 13. P1 — FCM token design

One token is stored per user. Multi-device sign-in overwrites the earlier device. There is no robust token timestamping or stale/invalid-token cleanup.

Required model:

- one document per installation;
- token;
- platform;
- created/lastSeen timestamp;
- notification capability;
- optional app version;
- invalidation/removal on send error or sign-out.

FCM tokens are private device credentials and must never be part of globally readable user profiles.

## 14. P1 — Backup privacy and integrity

Backup currently:

- reads incorrect collection paths;
- serializes personal content into temporary JSON;
- does not reliably delete temporary data;
- lacks encryption;
- lacks schema version/checksum;
- lacks conflict/rollback semantics;
- restores profile/system fields with broad merge behavior;
- may report background success after doing no useful work.

The settings UI asks users to bypass Google's unverified-app warning. This creates unacceptable trust training.

Recommendation: remove backup from the MVP. If restored later, use a versioned manifest, encrypted content, atomic restore staging, field allowlists, validation, cleanup, explicit consent, and verified OAuth branding.

## 15. P2 — App Check and abuse resistance

Firebase App Check is absent. App Check should be introduced after rules are correct. It can reduce calls from unauthorized clients but cannot repair authorization.

Also required:

- rate limits for invites, messages, uploads, comments, and reports;
- per-user/group storage budgets;
- replay/idempotency protection for server operations;
- logs for membership/admin changes;
- alerting for rule denials, unusual reads, upload spikes, and function failure;
- secrets/environment configuration review.

## 16. Required security test matrix

At minimum:

- anonymous user denied everywhere private;
- authenticated nonmember cannot read group/messages/media;
- member can read authorized group;
- member cannot change owner/roles/members;
- admin can perform only documented moderation;
- user cannot read another private profile/device token;
- author cannot alter immutable author/time fields;
- nonauthor cannot update/delete content;
- blocked users cannot interact where policy requires;
- invalid field types and unknown keys denied;
- oversized strings/arrays denied;
- wrong media type/size/path denied;
- expired/revoked invite denied;
- concurrent thirteenth join denied;
- deletion removes access immediately;
- saved/private per-user state is inaccessible to others.

## 17. Policy references

- Firebase Security Rules: <https://firebase.google.com/docs/firestore/security/overview>
- Firebase Rules Emulator testing: <https://firebase.google.com/docs/rules/emulator-setup>
- Firebase App Check: <https://firebase.google.com/docs/app-check>
- Firestore transactions: <https://firebase.google.com/docs/firestore/manage-data/transactions>
- Google Play User Data policy: <https://support.google.com/googleplay/android-developer/answer/10144311?hl=en>
- Google Play prominent disclosure: <https://support.google.com/googleplay/android-developer/answer/11150561?hl=EN-GB>
- Google Play UGC policy: <https://support.google.com/googleplay/android-developer/answer/9876937?hl=en-IN>
- Google Play account deletion: <https://support.google.com/googleplay/android-developer/answer/13327111?hl=en>
- Apple App Review Guidelines: <https://developer.apple.com/app-store/review/guidelines/>
- Apple account deletion: <https://developer.apple.com/support/offering-account-deletion-in-your-app/>
