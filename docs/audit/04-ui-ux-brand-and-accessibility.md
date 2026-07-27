# Report 4 — UI/UX, Brand, and Accessibility

## 1. Design-audit limitation

This assessment is based on source structure, UI code, copy, assets, navigation, and feature behavior. A later implementation phase still needs on-device usability testing, screen-reader testing, text scaling, low-end Android testing, and moderated sessions with actual Bible-study participants.

## 2. Current experience diagnosis

The current visual/product grammar is dominated by:

- WhatsApp-style group chat and bubbles;
- Instagram/WhatsApp-style status rings;
- unseen and like counts;
- ephemeral three-day content;
- referral/network metrics;
- purple gradients;
- multiple cosmetic chat themes.

These patterns are familiar, but they cause the product's unique purpose to disappear. Braid feels like a social messenger with Christian content rather than a tool designed around spiritual study and formation.

## 3. Experience principles

1. **Scripture remains visible in context.**
2. **Reflection is easier than posting.**
3. **Audience is explicit before sharing.**
4. **The app supports small trusted relationships.**
5. **Progress describes a study journey, not popularity.**
6. **Notifications call users back to meaning, not checking behavior.**
7. **Offline and failure states preserve trust.**
8. **The interface is calm, warm, readable, and non-performative.**

## 4. Recommended primary navigation

### Today

Purpose: answer “What is meaningful for me now?”

Content:

- current passage or topic;
- current group study day;
- continue private draft;
- group prompts awaiting response;
- prayer/application follow-up;
- concise recent group summary;
- connectivity and pending-sync state.

### Groups

Purpose: manage active, scheduled, completed, and archived study circles.

Each card should show:

- name;
- passage/topic;
- phase and progress;
- next scheduled moment;
- unread discussion/reflection count;
- member summary;
- offline/pending state if applicable.

“Circle” could be tested as a warmer product term, but should not be changed without user-language research.

### Journal

Purpose: one durable library for:

- private reflections;
- shared reflections;
- saved passages;
- applications;
- prayers;
- study history.

Users should not have to choose between Notes and Insights before they know what they want to say.

### Me

Purpose:

- profile;
- privacy;
- notifications;
- offline media/storage;
- accessibility/appearance;
- account/data;
- help/safety/legal.

Referral reach should not dominate personal identity.

## 5. Study-room redesign

Recommended tabs:

1. **Overview** — purpose, passage/topic, members, dates, next action.
2. **Plan** — days/weeks, prompts, progress, completed states.
3. **Reflections** — deliberate Scripture-anchored shares.
4. **Discussion** — conversational chat.
5. **Prayer** — requests, commitments, follow-up.

If five tabs are too dense on smaller devices, Overview can be the header/home while Plan, Reflections, Discussion, and Prayer are the internal destinations.

Every group item should optionally anchor to:

- Scripture reference;
- study day;
- prompt;
- application;
- prayer.

This creates differentiation without removing the familiarity of chat.

## 6. Unified Reflection composer

Replace separate Note and Insight composers with one model and interface.

Optional sections:

- **Scripture**
- **Observation — What does the text say?**
- **Meaning — What do I understand?**
- **Application — What will I do?**
- **Prayer — How will I respond?**

Audience:

- Only me.
- Selected group.
- Another future explicitly defined trusted audience.

Behavior:

- autosave local draft;
- show offline/pending state;
- allow intentional share later;
- preserve original private record/history;
- attach Scripture context;
- support edit/version behavior explicitly.

## 7. Redesign Insights

The current Stories implementation encourages fast checking and expiring visibility.

Recommended replacement: **Reflections**

- durable by default;
- tied to Scripture/study;
- explicit audience;
- group scoped for MVP;
- thoughtful comments;
- save to Journal;
- resurface after a useful interval;
- no global public feed;
- no popularity ranking.

If short-lived updates are retained, separate them as “Updates” and do not present them as substantial study reflections.

## 8. Healthy engagement

Meaningful reasons to return:

- continue an unfinished reflection;
- respond to today's group prompt;
- follow up on an application;
- pray for a request;
- view a weekly study recap;
- revisit what the user wrote seven days ago;
- facilitate the next group session.

Avoid:

- aggressive streak loss;
- infinite/global feed;
- popularity-based ranking;
- referral reach as status;
- notification copy designed only to create curiosity;
- excessive seen/like metrics.

If a rhythm feature is introduced, support grace days and nonjudgmental copy.

## 9. Brand audit

### Current mark

The current logo is a generic chat bubble with a purple radial style. It has weak small-size definition and does not express:

- Braid;
- Scripture;
- study;
- reflection;
- trusted small groups.

### Recommended concept

Explore three woven strands forming:

- an open book;
- a subtle conversation shape;
- a path;
- a flame/leaf.

Conceptual meaning:

1. Scripture.
2. Personal understanding.
3. Shared community.

A literal cross can be explored, but should be tested against the app's intended denominational and geographic breadth.

### Brand character

- thoughtful;
- warm;
- grounded;
- trustworthy;
- contemporary but not trendy;
- reflective rather than performative.

## 10. Color system

Recommended direction:

- **Canvas/parchment:** warm reading surfaces.
- **Ink/plum:** primary brand and text.
- **Sage:** growth, completion, supportive actions.
- **Gold:** sparing highlights, not large gradients.
- **Semantic red/amber/green/blue:** error, warning, success, information.

Required tokens:

- primary/onPrimary;
- surface/onSurface;
- surfaceVariant/onSurfaceVariant;
- outline;
- Scripture surface/text;
- private/group audience;
- pending/failed/offline;
- success/warning/error;
- focus;
- disabled.

Do not encode meaning with hardcoded purple/gray values scattered across screens.

## 11. Typography

- Use a system or bundled sans-serif for UI/body.
- Use one bundled offline serif only for Scripture excerpts if desired.
- `Merriweather` is referenced but not bundled and therefore falls back.
- Comfortaa can remain a limited display/brand face but should not carry dense reading.
- Avoid network font dependencies.

Suggested scale:

- display/title for major study context;
- 20–24sp page titles;
- 16sp primary body;
- 14sp secondary;
- no routine metadata below approximately 12sp;
- comfortable Scripture line height.

All screens must survive 200% text scaling without clipped fixed-height containers.

## 12. Iconography

No new icon dependency is necessary. Material icons are already bundled and small.

Create an icon specification for:

- Today;
- Groups;
- Journal;
- Reflection;
- Scripture;
- Prayer;
- Discussion;
- Progress;
- Save;
- Share;
- Report;
- Block;
- Offline;
- Pending;
- Failed;
- Retry.

Rules:

- choose filled or outlined behavior by state;
- do not mix unrelated icon families casually;
- provide semantic labels/tooltips;
- never use a remote image where a local functional icon is required;
- never rely on color alone to indicate state.

## 13. Core components

Required reusable components:

- `BraidAvatar`
- `BraidRemoteImage`
- `BraidGroupCard`
- `BraidStudyProgress`
- `BraidScriptureCard`
- `BraidReflectionCard`
- `BraidMessageBubble`
- `BraidComposer`
- `BraidAsyncState`
- `BraidOfflineBanner`
- `BraidEmptyState`
- `BraidPermissionRationale`
- `BraidDestructiveActionSheet`

Every asynchronous component must define loading, empty, content, stale, offline, and error states where applicable.

## 14. Profile redesign

Current issues:

- referral and second-degree reach are prominent;
- one statistic labels Notes as Insights;
- binary gender defaults to Male without product need;
- sequential referral queries increase delay;
- loading can look blank.

Recommended profile:

- name/photo;
- optional short bio;
- current study rhythm;
- completed studies;
- personal Journal shortcuts visible only to owner;
- group memberships;
- privacy controls.

Remove gender unless there is a clear, consented feature requirement. Never default unknown data to Male.

## 15. Settings redesign

Recommended hierarchy:

1. Account and profile.
2. Privacy and visibility.
3. Contacts and invitations.
4. Notifications and group mute.
5. Offline media and storage.
6. Appearance and accessibility.
7. Data export/backup.
8. Help, safety, and reporting.
9. Delete account.
10. Version, privacy policy, terms, licenses.

Do not show nonfunctional settings. Derive version from package metadata.

## 16. Permission UX

Before any system permission:

- explain the feature value;
- explain what is accessed;
- explain whether data leaves the device;
- allow “Not now” where possible;
- request only when the user invokes the feature;
- provide a recovery path if denied.

Remove unused or unjustified camera/storage/contact permissions from the manifest.

## 17. Accessibility requirements

### Interaction

- minimum 48×48dp targets;
- clear focus order;
- visible pressed/selected/disabled state;
- no gesture-only essential operation;
- tooltips for ambiguous icons.

### Screen readers

- semantic names for avatars and unlabeled icons;
- group/message context;
- meaningful image descriptions;
- announce send state and errors;
- readable Scripture reference order;
- exclude decorative imagery from semantics.

### Visual

- WCAG AA contrast;
- no white70 text on near-white bubbles;
- do not use color alone;
- high-contrast focus;
- readable text over images with scrim;
- avoid low-opacity disabled text that becomes illegible.

### Dynamic behavior

- 200% text scaling;
- reduced motion;
- keyboard/switch access;
- RTL readiness;
- orientation and narrow-screen testing;
- no fixed heights that clip translated text.

### Media

- audio duration/author/state label;
- transcripts if feasible;
- video captions when video is restored;
- filenames/types/sizes for documents.

## 18. Content and microcopy

Tone:

- invitational;
- calm;
- direct;
- nonjudgmental;
- spiritually serious without sounding institutional.

Replace misleading success with state-aware copy:

- “Saved on this device. Will sync when connected.”
- “Couldn’t send. Your reflection is still here.”
- “This invitation has expired. Ask the group owner for a new one.”

Avoid:

- fake support identity;
- instructions to bypass security warnings;
- claims that a feature is private/contacts-only without enforcement;
- “success” before awaited persistence.

## 19. Design-system deliverables

Create:

- `docs/product-principles.md`
- `docs/design-system.md`
- semantic Dart tokens/theme extensions;
- component catalog;
- icon map;
- content-style guide;
- accessibility checklist;
- responsive layouts;
- offline/error-state specification;
- light/dark golden tests.

The documentation and implementation must share the same semantic names so the system does not drift.
