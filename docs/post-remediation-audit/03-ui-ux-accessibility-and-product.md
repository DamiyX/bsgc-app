# UI, UX, accessibility, and product audit

## Product interpretation

Braid is not supposed to be a WhatsApp clone with Bible-related labels. Its strongest product opportunity is a calm, structured place where a person can:

1. spend time with Scripture privately;
2. capture what they understood;
3. decide whether and where to share it;
4. study with a small trusted group;
5. return later and see spiritual continuity rather than a noisy social feed.

The remediation moves the product closer to that direction with:

- `Today`, `Groups`, `Journal`, and `Me` as the primary navigation;
- group spaces named `Plan`, `Reflections`, `Discussion`, and `Prayer`;
- clearer separation between private notes and shared group conversation;
- improved empty, loading, and offline states;
- cached avatars and deterministic fallbacks.

Those are meaningful improvements. The remaining issue is that the information architecture now says “Bible study product,” while several interaction models still behave like generic social/chat patterns.

---

## Executive UX assessment

### What the experience currently feels like

- A capable Christian small-group chat application.
- A collection of improved but partly disconnected surfaces.
- Visually more coherent than the baseline, but still assembled primarily from Material defaults and screen-specific decisions.
- Reflection-centered in naming, but chat-centered in behavior.

### What it should feel like

- Quiet, safe, focused, and spiritually intentional.
- Easy to capture a thought without first deciding a technical destination.
- Structured enough to build a daily/weekly rhythm, but never gamified into guilt.
- Personal first, selectively communal second.
- Warm and contemporary without looking like WhatsApp, Facebook comments, or Instagram Stories.

### Primary design gap

The app has better navigation labels, but it does not yet have one coherent “study → reflect → save → share → revisit” journey. Users still move among separate composers, rooms, notes, and expiring Insights with different mental models.

---

## Information architecture and navigation findings

### UX-001 — The “one thought, choose an audience” flow is not truly unified

**Severity:** P1
**Evidence:** Today share action and its destination sheet

The action appears to offer one idea that can be sent to different audiences, but choosing a destination opens separate composers. The draft itself is not shared across those destinations. Opening a group goes to the room’s default `Discussion` space rather than a reflection-specific share flow.

**Why this matters**

The user’s natural thought is:

> “I learned something and may want to share it.”

The app currently makes them think:

> “Which feature and content model must I enter before I write?”

**Recommended redesign**

Create a single reflection composer with:

- optional Scripture reference;
- reflection body;
- optional image/voice attachment;
- initial state `Private`;
- audience selector: `Only me`, one study group, selected contacts;
- destination-aware preview;
- explicit expiry only when sharing as an expiring Insight;
- durable draft restoration.

This does not require merging every backend collection immediately. A presentation/domain layer can map one composer result into the appropriate existing write path.

---

### UX-002 — “Today’s next study” is not actually schedule-aware

**Severity:** P1
**Evidence:** Today screen group selection

The selected group is effectively the first active group in last-message ordering. It is not derived from an assignment, scheduled study day, chapter due date, personal progress, or group cadence.

**Impact**

- The product promises guidance it does not possess.
- A recently chatty group can replace the group the user actually needs to study.

**Recommended correction**

For the MVP, use honest language such as `Continue a study` unless schedule data exists. Then introduce a minimal study-session model:

- group plan/book;
- next chapter or passage;
- optional target date;
- user completion/progress;
- group progress summary.

Today can then answer “What should I read next?” instead of “Which group had the latest message?”

---

### UX-003 — Private reflection and group reflection are still separate worlds

**Severity:** P1

The original direction called for a private reflection that could later be shared. Journal notes do not provide a clear, reversible “share this reflection” journey into a group/contact audience.

**Recommended correction**

Add a `Share a copy` action from a private journal entry. Make it explicit that:

- the private original remains private;
- subsequent private edits do not silently change the shared copy;
- the user can choose the target and review the shared version.

This makes privacy the default and sharing an intentional second step.

---

### UX-004 — Archived groups become difficult to rediscover

**Severity:** P1

Archived groups are filtered out of the primary group list without a sufficiently discoverable archive/history destination.

**Impact**

- Old study history appears lost.
- Users may be afraid to archive.

**Recommended correction**

Add `Archived studies` under Groups or Me, show the archive count, and explain whether an archived group is read-only, resumable, or restorable.

---

### UX-005 — Profile shortcuts duplicate primary navigation

**Severity:** P2

Notes and saved content appear in profile-related surfaces while `Journal` and other primary destinations already exist.

**Impact**

- Multiple paths imply different content but may lead to the same thing.
- The `Me` tab becomes a miscellaneous menu rather than identity, preferences, and trust controls.

**Recommended correction**

Use:

- `Journal` for private notes, saved reflections, and personal history;
- `Groups` for active and archived studies;
- `Me` for profile, account, appearance, notifications, privacy, support, and legal.

Keep shortcuts only when they provide a distinct personal summary.

---

## Interaction model findings

### UX-006 — Insight interactions feel borrowed from social media

**Severity:** P1

Circular unseen rings, tap-left/tap-right navigation, expiring story-like content, thumb likes, and Facebook-style comments make the experience feel like a social feed.

**Why this conflicts with Braid**

- It encourages rapid consumption rather than reflection.
- A thumb-up is ambiguous for grief, confession, prayer, or difficult Scripture.
- Expiry can create pressure/FOMO in a product meant to support quiet growth.

**Recommended direction**

Present shared reflections as calm cards or a small “reflection shelf”:

- author and Scripture first;
- short reading progress or deliberate next/previous controls;
- reactions such as `Amen`, `Helpful`, or `Encouraging`;
- `Praying` only when contextually appropriate;
- a visible save policy;
- no urgency animation for unseen content.

Expiry may remain as an optional privacy feature, but should not define the visual language of the whole feature.

---

### UX-007 — Group spaces are labels over one chat model rather than distinct study tools

**Severity:** P1

`Reflections`, `Discussion`, and `Prayer` filter a shared message collection and change hints, but their interaction models remain substantially the same.

**Impact**

- The information architecture promises more differentiation than the features deliver.
- Prayer and reflection lack the behaviors that would make them uniquely useful.

**MVP recommendation**

Keep one underlying message system, but give each space one distinctive capability:

- **Plan:** passage, progress, next session, group completion.
- **Reflections:** Scripture-linked posts, less chat-like layout, optional private-to-group sharing.
- **Discussion:** conversational threads and replies.
- **Prayer:** prayer request, `Praying`, optional `Answered`, gentle follow-up date.

Do not add a large feature set to every tab. One clear capability per space is enough to establish identity.

---

### UX-008 — The default group destination overemphasizes Discussion

**Severity:** P2

Group entry and sharing often default to `Discussion`. For a reflection-centered product, this subtly trains users to treat the room as generic chat.

**Recommended correction**

- Restore the user’s last selected space per group.
- Open a shared reflection directly in `Reflections`.
- Open a notification in the exact referenced space/message.
- For first entry, choose `Plan` or `Reflections` based on group state instead of always `Discussion`.

---

### UX-009 — “Undo delete” is not a true undo

**Severity:** P1
**Evidence:** My Insights delete/undo flow

Undo republishes through the callable as a new Insight with a new ID/timestamp. It does not restore the original comments, reactions, saves, or distribution state, and it can fail or be rate-limited.

**Impact**

- The UI promises reversibility that the data model does not provide.

**Recommended correction**

Either:

- implement a short server-supported soft-delete window that restores the same record; or
- remove `UNDO` and require a confirmation before deletion.

Never label “create a replacement” as undo.

---

### UX-010 — Several success messages occur before success is known

**Severity:** P1

Notes, reactions, comments, preference changes, and some media paths optimistically confirm success without complete rollback/error presentation.

**Impact**

- Trust erodes because the app says content is saved when it may not be.
- Offline behavior becomes ambiguous.

**Recommended correction**

Use three deliberate states:

- `Saving…`
- `Saved` or queued offline
- `Couldn’t save — retry`

Preserve the user’s text/attachment on every failure. Optimistic changes are acceptable only with rollback and an accessible failure notice.

---

## Content, terminology, and trust findings

### UX-011 — Product copy makes unsupported promises

**Severity:** P0

Examples include:

- “end-to-end encrypted” for normal Firestore content;
- “permanently delete” where a tombstone/status remains;
- saved Insights implying durable private revisiting although the source becomes unreadable after expiry;
- “contact Braid support” when no support channel is exposed.

**Recommended correction**

Create a claims inventory. Every statement about privacy, deletion, expiry, saving, delivery, offline status, or support must be paired with:

- owning code/data path;
- verified behavior;
- product owner;
- test or manual acceptance check.

Trust copy is functionality, not decoration.

---

### UX-012 — Internal terminology is inconsistent

**Severity:** P2

The app alternates among `Insight`, `note`, `reflection`, and `active note`. “Insight” is branded but abstract. “Active notes” is particularly confusing in an empty state.

**Recommended terminology**

- `Reflection`: something learned or shared from study.
- `Journal entry`: private personal writing.
- `Discussion`: conversation in a group.
- `Prayer request`: prayer-specific shared content.
- `Saved reflection`: a durable user-created copy/bookmark, with a clear retention model.

Keep `Insight` only if user research shows people understand and prefer it.

---

### UX-013 — Legal and support surfaces are visibly unfinished

**Severity:** P0 before external beta

Legal content contains draft/repository wording and incomplete operator details. The app can tell users to contact support without a usable support destination.

**Required correction**

Before external beta:

- identify the operator and jurisdiction;
- publish real privacy/terms versions with effective dates;
- provide a support/contact route;
- define account deletion and complaint contact;
- remove all draft markers;
- preserve version acceptance where required.

Legal review itself remains outside this code audit, but obviously draft product surfaces must not ship.

---

## Visual system findings

### UX-014 — There is no complete design system

**Severity:** P1

The code has useful colors/themes, but many screens choose their own:

- padding and gaps;
- corner radii;
- icon sizes;
- surface colors;
- text sizes/weights;
- empty/loading/error compositions;
- button and chip styles.

The result mixes story rings, social comments, chat bubbles, and Material defaults without a single interaction/brand grammar.

**Recommended foundation**

Create versioned Flutter theme extensions or tokens for:

| Token group | Minimum content |
|---|---|
| Color | background, surface, elevated surface, text, muted text, border, brand, success, warning, error, focus |
| Typography | display, title, section, body, label, caption with scalable line height |
| Spacing | 4, 8, 12, 16, 24, 32 |
| Radius | small, medium, large, pill |
| Elevation | flat, raised, modal |
| Motion | fast, standard, slow plus reduced-motion behavior |
| Components | app bar, primary/secondary button, text field, list row, reflection card, message bubble, empty state |

Do not create a large abstract library first. Extract tokens and the 8–10 most repeated components, migrate core journeys, then expand from evidence.

---

### UX-015 — Brand assets are not production-resolved

**Severity:** P1

The repository contains multiple large draft logo assets while the product lacks a clearly documented final mark, usage rules, icon construction, and small-size tests.

**Recommended correction**

Create a compact brand package:

- primary and monochrome mark;
- app icon and adaptive icon;
- wordmark;
- minimum size and clear space;
- light/dark usage;
- approved brand colors;
- no-go examples;
- SVG/source plus optimized export workflow.

The visual direction should communicate warmth, Scripture, conversation, and continuity without relying on a generic cross/chat-bubble combination.

---

### UX-016 — Dark mode is not consistently token-driven

**Severity:** P1
**Evidence:** hard-coded white surfaces in My Insights and other screen-specific colors

Hard-coded `Colors.white`, black opacities, and accent colors bypass theme semantics.

**Impact**

- Poor contrast or visually broken cards in dark mode.
- Theme changes require screen-by-screen repair.

**Recommended correction**

Ban direct visual colors in feature screens except explicitly approved semantic cases. Add theme tests/goldens for the four primary destinations and core detail screens.

---

## Accessibility findings

### A11Y-001 — Several controls do not meet reliable touch-target/semantic requirements

**Severity:** P1

The code contains many `GestureDetector` controls and tightly constrained icon-only actions. Some send, reply, close, add, like, and navigation controls lack clear semantics, tooltips, or a guaranteed 48×48 logical-pixel hit area.

**Impact**

- Difficult for users with motor impairments.
- TalkBack may announce only an icon or nothing useful.
- Controls can be hard to discover.

**Required correction**

- Prefer `IconButton`, `TextButton`, and semantic components.
- Guarantee a 48×48 hit target even when the visual icon is smaller.
- Provide tooltip/semantic label and selected/toggled state.
- Test with Android TalkBack and accessibility scanner.

---

### A11Y-002 — Reduced-motion preferences are not respected

**Severity:** P1
**Evidence:** Insight animation/transitions

Animations use fixed controllers/durations without checking `MediaQuery.disableAnimations`.

**Required correction**

When reduced motion is enabled:

- remove slide/scale motion where it is not essential;
- use instant or short crossfades;
- avoid auto-advancing/progress urgency;
- preserve spatial context through layout, not movement.

---

### A11Y-003 — Some color contrast is below the expected text threshold

**Severity:** P1

The Scripture-link purple accent on off-white was calculated at approximately 3.24:1 for normal-sized text, below the WCAG 4.5:1 target.

**Required correction**

Select semantic link colors that pass in light and dark themes. Test disabled, focused, pressed, visited (if used), error, and placeholder states rather than only primary text.

---

### A11Y-004 — Status and error changes are not reliably announced

**Severity:** P1

Snackbars and inline asynchronous changes are not consistently implemented as accessibility live regions. An optimistic control can change visually while a screen-reader user receives no clear success or failure state.

**Required correction**

- Use `Semantics(liveRegion: true)` for important async results.
- Move focus deliberately for blocking validation errors.
- Give progress indicators labels.
- Do not rely on color or temporary snackbar visibility alone.

---

### A11Y-005 — Layout is not fully localization/RTL-safe

**Severity:** P2

Directional values such as `left`, `right`, and non-directional edge insets appear throughout the UI.

**Required correction**

Use `EdgeInsetsDirectional`, `AlignmentDirectional`, and `start/end` positioning. Even if the initial release is English-only, this also improves layout correctness and future translation readiness.

---

### A11Y-006 — Fixed-height surfaces need large-text verification

**Severity:** P1

The Insights row and other compositions use fixed heights. At 200% text scale, author names, labels, or actions can clip or overlap.

**Required correction**

Prefer content-driven constraints, allow wrapping, and test:

- 1.0×, 1.3×, and 2.0× text;
- smallest supported phone;
- landscape;
- keyboard open;
- long names and localized strings.

---

### A11Y-007 — Voice reflections lack an accessible equivalent

**Severity:** P1

Voice content has no optional transcript/caption flow.

**Impact**

- Deaf/hard-of-hearing users cannot consume it.
- Audio is less usable in quiet/noisy environments and when offline caching fails.

**Recommended correction**

For the MVP, allow the author to add a text summary/caption and visibly indicate when none is available. Automatic transcription can come later with clear consent, privacy, and cost controls.

---

## Engineering factors that directly affect UX

### UXE-001 — Core screens are too large to evolve safely

**Severity:** P1

Approximate file sizes observed:

- Study Room: over 1,700 lines;
- View Insight: over 1,300 lines;
- Main Hall: over 1,100 lines.

These files mix UI, querying, optimistic state, navigation, audio, caching, and business rules.

**Impact**

- Small UX changes can create unrelated regressions.
- Loading/error/offline behavior diverges between sections.
- Widget and accessibility testing is difficult.

**Recommended correction**

Refactor by user capability, not arbitrary widget length:

- room data/controller;
- space-specific content list;
- composer;
- message item/actions;
- playback/attachment state;
- Insight viewer state;
- comments/reactions;
- navigation destination handler.

Keep business state testable without constructing the whole screen.

---

### UXE-002 — Scripture tap recognizers are not disposed

**Severity:** P1
**Evidence:** `ClickableScriptureText`

The stateless implementation creates `TapGestureRecognizer` instances during build without a lifecycle that disposes them.

**Impact**

- Resource/memory leakage in long message/note lists and repeated rebuilds.

**Required correction**

Use a stateful lifecycle that owns/disposes recognizers, or use a widget structure that does not require persistent recognizers per span.

---

### UXE-003 — The automated UI test surface is too small

**Severity:** P1

Only a small number of Flutter tests exist relative to the number of critical journeys. There are no comprehensive core-journey, offline, golden, or accessibility tests.

**Required correction**

Build a targeted test pyramid:

- controller/service unit tests for audience, pagination, seen, save, and retry state;
- widget tests for Today, group room spaces, Journal save failure, Insight viewer, settings permissions;
- golden tests for light/dark and large text;
- emulator integration tests for offline/reconnect, notifications, invites, account switching;
- manual TalkBack and physical-device release checklist.

---

## Recommended professional UX direction

### 1. Make “Reflection” the central content object in the interface

A reflection can begin privately and optionally be shared. The UI should not force the user to understand collections or feature names before writing.

### 2. Make Today a true action surface

Today should contain at most:

- continue the next reading/study;
- resume a draft/reflection;
- recent response needing attention;
- one quiet prompt.

Avoid turning it into an activity feed.

### 3. Give groups a repeatable study rhythm

A simple weekly loop:

```text
Read passage → Write privately → Share reflection → Discuss → Pray → Mark session complete
```

The group Plan should show where the group is in that loop.

### 4. Reduce social urgency

Remove or soften story rings, unseen pressure, generic like counts, and rapid tap navigation. Reward continuity with history and resurfacing, not streak shame or popularity ranking.

### 5. Build warmth through restraint

Use a quiet neutral background, one confident brand color, readable Scripture typography, soft but consistent surfaces, generous spacing, and limited purposeful motion.

### 6. Treat privacy decisions as part of composition

The audience must be visible before posting. “Only me” should be a first-class choice, not a fallback. Explain expiry and saved-copy behavior at the moment it matters.

---

## Suggested core screen blueprint

### Today

- greeting/date, compact;
- `Continue reading` card with passage and group;
- `Write a reflection` primary action;
- `Continue draft`, only when one exists;
- recent group response, bounded to one or two useful items.

### Groups

- active study cards with passage/progress/next session;
- unread indicator by meaningful space, not generic activity alone;
- archived studies entry;
- create/join actions with clear difference.

### Study room

- group title and study status;
- space navigation with preserved selection;
- Plan containing actual next passage/progress;
- Reflections using reflective cards;
- Discussion using threaded/conversational treatment;
- Prayer with praying/answered states;
- composer adapted to current space.

### Journal

- private entries;
- saved shared reflections with a durable-copy explanation;
- search/filter by Scripture/date/group;
- `Share a copy` action;
- resurfacing such as “From this study last month,” without manipulative streaks.

### Me

- canonical profile;
- appearance and accessibility;
- notifications and OS permission state;
- privacy/blocking;
- support and legal;
- account/export/delete.

---

## UX acceptance checklist

Before declaring the redesign successful, test:

1. A new user can understand the four tabs without explanation.
2. A user can write privately in one action from Today.
3. The same private reflection can be intentionally shared as a copy.
4. A group member can identify the next passage and study progress.
5. Notifications open the exact space/content.
6. Saved content remains readable according to the promise shown when saving.
7. Every write preserves content on offline/failure paths.
8. The app is usable at 200% text scale and with TalkBack.
9. Every interactive control has a meaningful label and 48×48 target.
10. Light/dark mode use semantic tokens with passing contrast.
11. Reduced-motion mode removes nonessential transitions.
12. No screen contains draft legal/support/privacy promises.
13. The experience feels calm in a five-minute usability session—not like a social feed.

---

## MVP versus scale recommendation

### Must complete for a credible MVP

- remove false promises and draft legal/support content;
- unify the reflection composer concept;
- make saved/private/shared behavior understandable;
- differentiate group spaces with one useful behavior each;
- correct the major accessibility failures;
- create a small design-token/component foundation;
- test core offline and error journeys.

### Appropriate after validated user demand

- automatic voice transcription;
- sophisticated study scheduling;
- semantic journal search;
- advanced group facilitation;
- pastoral/moderator dashboards;
- complex feed ranking;
- true end-to-end encrypted sharing.

The professional move is not to add the most features. It is to make the central reflection journey trustworthy, coherent, and repeatable.
