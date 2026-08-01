# Wave 20B notification and mutation source-closure handoff

**Scope:** `REL-012` / `UX-010` notification preference and device-token
mutation reliability

**Starting SHA:** `646cb17` (`Document Wave 19 remaining work checkpoint`)

**Ending source SHA:** `68d544c` (`Close Wave 20 media and notification reliability gaps`)

**Status:** source change and focused tests pass; no commit or push was made by
this track

## Finding

`NotificationService.updatePreferences()` wrote the four local
`SharedPreferences` switches before updating the account's device document.
When token registration, device-document update, or device removal failed, the
settings screen restored only its in-memory fields. The next settings load
could therefore resurrect the failed values from local storage and present a
different state from the server. The Firestore writes also returned after the
SDK accepted a local offline write, so the caller could treat an unacknowledged
device-token/category mutation as complete.

## Source correction

- `NotificationPreferenceState` models the four local switches as one logical
  record.
- `persistNotificationPreferenceState` verifies every platform write and
  restores previously changed keys when a write rejects or throws. This is a
  deterministic, injectable seam for regression tests.
- Remote preference updates and token registration now await
  `waitForDocumentCommit` on the exact account/device document before the
  caller can report success.
- Device removal waits for acknowledgement of the delete. If a remote
  operation fails, the local preference record is restored and the original
  failure reaches the existing retry/error copy.
- Token-refresh listener failures are contained and logged in debug builds so
  a transient registration failure cannot become an unhandled asynchronous
  exception. The next initialization/token refresh can retry registration.

## Regression protection

`test/notification_invite_reliability_test.dart` covers:

1. rejection after an earlier switch changed restores the complete previous
   state;
2. unchanged switches do not perform unnecessary platform writes;
3. the existing permission truth and notification-destination contracts remain
   green.

## Verification

Using the repository-pinned Flutter toolchain:

```text
.tooling/flutter/bin/dart.bat format lib/services/notification_service.dart test/notification_invite_reliability_test.dart
.tooling/flutter/bin/flutter.bat test test/notification_invite_reliability_test.dart --reporter compact
.tooling/flutter/bin/flutter.bat analyze
```

Results:

- focused notification/invite suite: **11 passed**;
- `flutter analyze`: **no issues found**;
- formatting: pass.

## Remaining boundary

These tests do not prove Firebase Messaging delivery, Android/iOS permission
dialogs, notification-channel behavior, cold-start/background tap routing,
native Firestore cache isolation, or deployed Functions/FCM token cleanup.
Those remain emulator/physical-device and staging/deployment gates. The
notification destination store still intentionally retains retryable routes;
this track changes only preference/device mutation durability.
