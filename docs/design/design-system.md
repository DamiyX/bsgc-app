# Braid design system

## Character

Warm, contemplative, trustworthy, and human. The interface should feel like a well-used study journal shared around a table—not a high-stimulation social feed.

## Semantic color

The source of truth is `BraidSemanticColors` in `lib/theme.dart`.

- Parchment surfaces support Scripture and reflection.
- Plum identifies Braid and group audience.
- Blue identifies study contacts.
- Muted plum identifies private content.
- Sage is success/progress.
- Amber is pending/warning.
- Slate is offline/stale.

Color is never the only carrier of status; pair it with text and icons. Light and dark modes must preserve meaning.

## Layout tokens

The shared Flutter tokens in `lib/theme.dart` are the starting contract for
core screens:

- `AppSpacing`: 4, 8, 12, 16, 20, 24, and 32 dp rhythm;
- `AppRadii`: 10, 14, 18, and pill radii;
- `AppMotion`: 150 ms quick feedback and 220 ms standard transitions.

New components should use these tokens (or the active Material color scheme)
instead of inventing screen-local values. Semantic colors come from the theme
so the same component remains legible in light and dark mode.

## Typography

Comfortaa is bundled for brand/headings. System text is preferred for long body copy and platform readability. Do not reference an unbundled font. Body text must scale to 200% without fixed-height clipping.

## Components

- Minimum interactive target: 48×48 dp.
- `BraidAvatar`: cached network image plus deterministic initials fallback.
- `BraidCoverImage`: cached cover plus deterministic local graphic.
- Audience row/chip: icon + explicit audience text.
- Async state: loading, content, empty, cached/offline, recoverable error.
- Pending outbox row: saved/sending/failed text plus Retry and Discard.
- Destructive confirmation: specific consequence and non-destructive first action.
- Voice reflection: an optional author-written text summary (maximum 1,000
  characters) is shown below the player; when absent, the UI says that no text
  summary is available. Automatic transcription is not enabled in the MVP.

## Navigation and icons

Use one Material icon family with outlined unselected and filled selected navigation icons. Icons require tooltips or nearby labels. Primary navigation order is Today, Groups, Journal, Me.

Archived studies are discoverable from Groups and open read-only. Journal
cards can launch a reviewed copy flow into a contacts-scoped reflection; the
private journal record is not mutated by sharing.

Long histories are loaded in bounded cursor pages. Recent Groups, Journal, and
saved-reflection pages render first; explicit “Load older…” actions retrieve
more records, while Archived studies remains a separate history surface. Feed
pointers contain the server-created safe reflection snapshot so opening the
active feed does not issue one content read per pointer. Legacy pointers are
hydrated only as a compatibility path until the snapshot backfill is complete.

## Motion

Motion is optional and functional. Avoid looping/decorative motion in core flows. Respect the platform’s reduced-motion setting; navigation and status understanding must never depend on animation.

## Accessibility verification

TalkBack/VoiceOver must complete sign-in, invite redemption, onboarding, group entry, reflection send/retry, progress update, settings, report/block, and deletion. Verify keyboard focus, RTL-safe flexible layouts, 200% text, contrast, live error/status announcements, and meaningful media labels.

## Brand asset status

The current optimized mark is retained for MVP continuity. A final braid/book/reflection mark requires design approval, then synchronized launcher, adaptive icon, splash, website, and store artwork generation. Do not ship multiple draft logos as app assets.
