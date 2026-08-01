# Wave 2.1 notification destinations

## Reliability fixes

- `NotificationDestinationStore` now serializes restore, set, complete, and
  discard operations. A delayed restore cannot overwrite a newer destination,
  and a delayed clear cannot remove a later write.
- `DeepLinkService` keeps initialization retryable after a storage or platform
  failure. Concurrent callers share one initialization future, and deep-link
  stream persistence errors are handled instead of escaping an unawaited
  callback.
- `MainHallScreen` suppresses duplicate opens for the same destination while a
  navigation is in flight. Destination completion and invite cleanup are
  wrapped so unawaited callbacks cannot create unhandled persistence errors.
- `NotificationService` now applies the same error boundary when a local or
  remote notification callback persists a destination; a storage failure is
  logged in debug builds while the pending route remains available for a later
  notification or retry path.

## Verification

From `bsgc-app-v2`:

```text
.\.tooling\flutter\bin\dart.bat format lib/services/notification_destination_store.dart lib/services/deep_link_service.dart lib/screens/main_hall_screen.dart test/notification_invite_reliability_test.dart
.\.tooling\flutter\bin\flutter.bat test test/notification_invite_reliability_test.dart
.\.tooling\flutter\bin\flutter.bat analyze lib/services/notification_destination_store.dart lib/services/deep_link_service.dart lib/screens/main_hall_screen.dart test/notification_invite_reliability_test.dart
```

The focused test includes a deterministic delayed-restore race: the newer
destination must remain both in memory and in persistence after the restore
finishes.

The focused notification/invite reliability suite passed **12 tests**. The
full Flutter suite passed **115 tests** after this wave; the Functions suite
remained at **78 tests**, and no Rules files changed.
