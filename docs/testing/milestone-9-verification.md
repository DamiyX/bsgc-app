# Milestone 9 verification — accessibility and component slice

## Scope

This wave implements the testable MVP portion of A11Y-001–007 and
UXE-001–003. It does not claim a completed device accessibility certification
or a wholesale rewrite of the core screens.

- Reflection and comment actions expose labels, tooltips, selected/toggled
  state, and platform-sized hit targets.
- Author-written voice summaries are persisted through the message model,
  outbox, callable normalization, migration, and rendered room UI. The limit
  is 1,000 characters; automatic transcription is intentionally not enabled.
- Voice download progress, room voice summaries, and composer progress expose
  live-region/status semantics.
- `ClickableScriptureText` and `ExpandableRichText` own their
  `TapGestureRecognizer` instances and dispose/rebuild them across lifecycle,
  text, style, and theme changes.
- Scripture links use the semantic theme focus color. Reflection cards expand
  their row height for larger platform text scales, and the expansion action is
  keyboard/assistive-technology reachable.
- Viewer/comment motion uses reduced-motion-aware durations where the route
  animates.

## Verification performed

- Dart formatting on changed Dart files: pass.
- `flutter analyze`: no issues.
- Full Flutter test suite: 79 passed.
- Focused insight/journal regressions: 19 passed.
- Functions `node --check index.js`: pass.
- Functions test suite: 70 passed.
- Git whitespace validation: pass.

## Manual checks still required

These are not safely provable on the current desktop-only run:

1. TalkBack/VoiceOver can complete sign-in, room entry, voice summary editing,
   reflection reaction/save, comment/reply, and retry flows.
2. Voice audio unavailable/offline still leaves the text summary visible and
   announced; download progress is announced without repeated noisy updates.
3. 200% text and long names/content do not clip on the smallest supported
   phone; reflection cards, composer previews, menus, and comment controls
   remain usable.
4. RTL layout keeps navigation, composer, reply, archive, and reaction actions
   in the correct reading direction.
5. Light/dark contrast and reduced-motion behavior are acceptable on a real
   device/emulator, including focus indicators and keyboard traversal where
   available.

## Deferred decisions

- Automatic transcription requires a separate privacy, cost, retention, and
  offline policy decision.
- The largest screens still need a deliberate controller/component extraction
  with performance evidence; this wave only creates bounded, testable seams.
