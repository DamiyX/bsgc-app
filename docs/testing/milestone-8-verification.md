# Milestone 8 verification — reflection-centered product journey

## Scope

This wave addresses the safe MVP slice of UX-001–008, UX-012, UX-014–016,
REL-022, and REL-024 without changing the existing callable/data contracts.

- Today now says **Continue a study** and only selects an active study; it no
  longer presents the first returned group as a schedule-aware “next study.”
- Groups exposes an **Archived studies** entry. Archived records are loaded
  separately and open read-only.
- Journal cards offer **Share a copy**. The copy opens a contacts reflection
  composer prefilled from the private note; the user can review/edit before
  sharing and the original journal entry remains private.
- The group reflection entry point opens the room in the Reflections space.
- The last non-plan room space is remembered per signed-in account and group.
- The former story-ring strip is a calm, labeled reflection-card row. It keeps
  selected-item/seen-state behavior but removes urgency gradients and tap-third
  presentation.
- Shared spacing, radius, and motion tokens are defined in `lib/theme.dart`;
  core theme controls use semantic Material colors in both light and dark mode.
- User-facing copy prefers “reflection”; backend `Insight` names remain for
  compatibility.

## Verification performed

- `dart format` on all changed Dart files: pass.
- `flutter analyze`: pass (no issues).

## Manual checks still required

The following require a Flutter device/emulator and representative Firebase
data and are intentionally not claimed as automated evidence:

1. Open Today with active and scheduled-only groups; confirm scheduled-only
   accounts see the honest empty state.
2. Open Groups → Archived studies; confirm an archived room is read-only and
   can be revisited after relaunch.
3. Create a private journal reflection, choose Share a copy, edit the copy,
   cancel it, and confirm the private note is unchanged; then share and confirm
   the expiry/audience copy.
4. Switch between Reflections, Discussion, and Prayer, leave/reopen the room,
   and confirm the last non-plan space is restored. Confirm notification
   deep-links still override remembered space.
5. Repeat the above in light/dark mode and at large text size; verify no card,
   label, or action clips. Capture screenshots for the branch handoff.

## Deferred product decisions

- A real schedule/progress service is still required before “Next study” can
  return.
- A single schema-level composer for group/private/contact destinations,
  Scripture attachments, and audio/image capture remains a later adapter
  expansion; this wave proves the private-first/share-a-copy journey without
  widening backend scope.
- Final logo/wordmark approval and runtime asset cleanup remain release gates.
