# Report 1 — Product and System Understanding

## 1. Executive interpretation

Braid is an Android-first Flutter/Firebase application for small-group Bible study. It tries to extend study and fellowship beyond a weekly meeting by combining:

- small study groups capped at twelve members;
- book- or topic-based study periods;
- group chat and media;
- private Notes;
- short-lived, intended contacts-based Insights (currently implemented without the required audience filter);
- Scripture recognition and reading;
- profiles, referrals, and contact-based discovery;
- notifications and backup.

The product has a valuable problem to solve, but its current implementation communicates **“Christian group chat plus Stories”** more strongly than **“a purpose-built rhythm for studying, reflecting, applying, and praying together.”**

The strongest product loop available to Braid is:

> Private reflection → deliberate sharing → Scripture-anchored discussion → application or prayer → later review.

That loop should become the organizing principle for the data model, navigation, notifications, and UI.

## 2. Audited source and repository state

The GitHub default branch was behind the version that appears to match the actual v2.2 application. The audit therefore used commit `777e266` from `feature/ui-fixes-batch-1`.

This is a release-governance risk:

- a contributor cloning `main` does not receive the apparent release candidate;
- CI built from the default branch could produce a stale application;
- documentation and bug reports can refer to different products;
- a hotfix can be applied to the wrong branch.

Approximate source shape:

- 14,500 lines of Dart;
- 54 Dart files;
- `study_room_screen.dart`: approximately 2,088 lines;
- `view_insight_screen.dart`: approximately 1,210 lines;
- `group_details_screen.dart`: approximately 1,086 lines;
- `add_member_sheet.dart`: approximately 980 lines;
- `main_hall_screen.dart`: approximately 938 lines;
- `profile_screen.dart`: approximately 693 lines.

The repository has no substantive product specification, architecture document, Firestore schema, design-system document, operational runbook, release process, or meaningful test plan. The README and package description remain close to Flutter template content.

## 3. Current feature inventory

### Authentication and onboarding

- Google authentication.
- Required phone-number collection.
- Contact permission and contact discovery.
- Inviter/referral selection.
- User profile creation.

### Groups

- Maximum of twelve members.
- Book or topic configuration.
- Start/end dates.
- Progress/extension concepts.
- Group photo/cover.
- Invitation sharing.
- Member addition from contacts.

### Study room and chat

- Text.
- Voice parts.
- Images.
- Video uploads.
- Document uploads.
- Replies.
- Reactions/star/edit/delete/clear-chat controls.
- Custom bubble appearance.
- Group notification sounds.

### Reflection and Scripture

- Private Notes.
- Scripture-reference detection.
- Scripture bottom sheets.
- Text-to-speech.
- Insights with comments, likes, views/seen state, themes, and three-day expiry.
- Saved Insights.

### Profile and network

- Profile photo and personal information.
- Referral relationship.
- Direct and second-degree reach.
- Notes/Insights statistics.

### Utilities

- Google Drive backup/restore.
- Local and FCM notification infrastructure.
- Support chat/FAQ.
- Theme and appearance settings.

## 4. What is already directionally strong

The following ideas should be preserved:

1. **Twelve-person groups.** This supports intimacy and meaningful participation better than open networks.
2. **Private Notes.** Private capture is an important beginning to the reflection loop.
3. **Scripture recognition.** Turning a reference into an immediately readable passage is a real product differentiator.
4. **Text-to-speech.** Useful for accessibility and hands-free study.
5. **KJV and WEB offline assets.** These can provide genuine offline value.
6. **Light/dark scaffolding.** There is already a theme foundation to standardize.
7. **Crashlytics initialization.** The application has the beginning of production error visibility.
8. **Partial media compression and bounded message queries.** These show awareness of performance even though the implementation remains incomplete.

## 5. Product contradictions

### 5.1 Quiet formation versus social performance

The support copy says Braid rejects addictive, viral social media. The interface nevertheless emphasizes:

- Stories-style avatar rings;
- unseen counts;
- short expiry;
- likes and views;
- referral reach;
- global activity;
- cosmetic chat themes.

These mechanics reward checking and visibility more than reflection and application.

### 5.2 Trusted-network intent versus unscoped Insights implementation

The intended product rule is valuable: an author’s approved contacts can see that author’s Insight and interact under it, while those viewers do not automatically gain access to one another’s separate Insights. The implementation currently queries all unexpired Insights without applying that relationship rule. “Global” in this audit means global among signed-in Braid users, not public on the open internet. The product promise, query, and rules must describe and enforce the same audience.

### 5.3 Study plan versus dated group chat

Start and end dates are largely metadata. The room is accessible outside those dates, topic days are not interactive, and completion does not lead to a meaningful recap/archive state. The study plan therefore does not govern the experience.

### 5.4 Intimate groups versus unsafe membership

The twelve-member cap implies trust, but group documents are broadly readable and group membership is mutable under weak rules. The trust promise is not upheld by the authorization model.

### 5.5 Private reflection versus fragmented content types

Notes and Insights use separate creation experiences. There is no simple path from a private reflection to an intentional group share. Users must understand product-internal record types instead of expressing one thought and choosing an audience.

### 5.6 Evangelism intent versus status-like presentation

The intended purpose of referrals is to encourage believers to welcome others into Braid and record their contribution to forming new study relationships. That is consistent with the mission. The risk comes from presenting referral and second-degree reach like a public follower/status count while study completion, application follow-through, prayer support, and learning history are less prominent.

Preserve invitation-impact tracking, but frame it as “people you welcomed” or “friends who joined through your invitation,” preferably private by default. Measure whether invitees become active in study circles, not only how large a referral tree becomes. Avoid leaderboards or public rank.

## 6. Recommended product definition

Recommended promise:

> Braid helps small groups turn personal Bible study into shared understanding, prayer, and practical action.

Recommended principles:

1. Scripture first, conversation second.
2. Reflection before reaction.
3. Small trusted groups over large audiences.
4. Durable learning over disappearing status.
5. Meaningful rhythm over addictive engagement.
6. Privacy by default.
7. Offline resilience as a product feature, not an error case.

## 7. Recommended MVP boundary

### Keep and complete

- Google authentication.
- Secure invite-based onboarding.
- Small groups with explicit ownership/roles.
- Book/topic plan and lifecycle.
- Text discussion.
- Image sharing.
- Storage-backed voice messages.
- Private journal/reflections.
- Intentional sharing of a reflection to a group.
- Contacts-based Insights with comments and carefully designed reactions, backed by real audience enforcement.
- KJV and WEB offline Scripture.
- Basic profile/preferences.
- Notification preferences.
- Reporting, blocking, privacy, and account deletion.

### Hide or remove until complete

- Google Drive backup/restore.
- Video attachments.
- Document attachments.
- The current unscoped query that exposes every active Insight to every signed-in user.
- Dummy/unavailable translations.
- Simulated support chat.
- Prayer Alarm placeholder.
- Mute Contacts placeholder.
- Unverified contact discovery.
- Multiple cosmetic bubble themes.
- Unsupported edit/delete/reaction actions.
- Public/competitive referral reach as a primary profile statistic; retain private invitation-impact tracking.

This is not a reduction of product quality. It concentrates the MVP on a smaller set of correct, safe, and distinctive journeys.

## 8. Target system boundaries

The next architecture should separate:

- **Authentication:** account and session state.
- **Private user data:** phone, devices, deletion status, consent.
- **Public/member profile:** only fields required to represent a person inside authorized groups.
- **Groups:** immutable identity, owner, roles, plan, lifecycle.
- **Membership:** explicit records/state transitions rather than a freely mutable array.
- **Reflections:** one content model with audience and Scripture anchors.
- **Discussion:** messages and media metadata.
- **Per-user state:** reads, saves, stars, mute state, cleared-before cursor.
- **Media:** Storage objects with ownership, type, size, status, and cleanup.
- **Moderation:** reports, blocks, group actions, audit trail.
- **Notifications:** per-device tokens and user/group preferences.
- **Invitations:** expiring/revocable tokens, never raw membership authority.

## 9. Proposed primary user journey

1. User opens **Today**.
2. The current passage or group prompt is visible.
3. User writes a private reflection using optional Observation, Meaning, Application, and Prayer prompts.
4. User keeps it private or shares it with a selected group.
5. The group discusses it with the Scripture context attached.
6. An application or prayer commitment can be marked for follow-up.
7. Braid resurfaces the commitment or reflection later.
8. At study completion, the group receives a recap and archives the study.

That journey should be the acceptance test for the product—not the number of chat or social features present.
