# Wave 18 UX/mutation source-closure handoff

**Scope:** per-study message-notification mute preference (`UX-010`)

**Starting SHA:** `0b0ddfc595cdd2100fa691d936ded35e61ad0190`

**Ending SHA:** working tree only; no commit or push

## Source change

The study-details notification switch previously treated Firestore's local
write completion as durable and allowed a second toggle while the first write
was still unresolved. The path now follows one bounded mutation contract:

1. `GroupDetailsScreen` moves the switch into a pending state and disables
   repeated toggles.
2. `ReversibleToggleController` applies the requested value optimistically,
   then restores the prior value if persistence fails.
3. `ChatService.setGroupMuted` waits for Firestore pending-write metadata to
   clear before the mutation is considered acknowledged. A timeout/offline
   failure therefore reaches the existing retry copy instead of leaving a
   misleading switch state.
4. The pending state is exposed as a live-region status (`Saving notification
   setting…`) for assistive technology.

The data path is account-scoped `users/{uid}/group_state/{groupId}` with the
existing `mutedUntil` and `updatedAt` fields; no rules, callable, or media
contract changed.

## Files changed

- `lib/screens/group_details_screen.dart`
- `lib/services/chat_service.dart`
- `lib/services/insight_action_controller.dart`
- `test/mutation_semantics_test.dart`

## Verification

- `flutter test test/mutation_semantics_test.dart` — **4 passed**
- `flutter analyze` — **no issues found**
- Dart formatting on changed files — **pass**

## Remaining boundary

Source tests do not prove a native Firestore server acknowledgement, airplane-
mode transition, process death, or device accessibility rendering. Those still
belong to the Android/offline/TalkBack acceptance matrix. The switch copy also
needs visual review at large text scale and in RTL layouts.

No device, product, legal, deployed-backend, or security/media evidence is
claimed by this handoff.
