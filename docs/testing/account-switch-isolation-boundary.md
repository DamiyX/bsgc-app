# Account-switch isolation boundary

This branch now enforces an in-process account-session boundary at the auth
root (`lib/main.dart`). Each auth identity transition receives a monotonically
new session generation. `UserDataWrapper` and the signed-out foyer are keyed by
that generation, so Flutter disposes the previous account-owned subtree before
the next account is rendered. The same token can be used by account-scoped
async work to reject a result that completed after the user changed.

This is deliberately not described as a Firestore-cache purge. The FlutterFire
`clearPersistence()` API must run only while the instance is stopped and before
other Firestore methods; calling it during normal sign-out with active
listeners would lose offline writes or break subsequent reads. Firestore
persistence remains enabled for warm offline study use. Sign-out currently
clears account-scoped drafts, outbox records, voice files, image cache, and
navigation state, while the native Firestore cache requires the device checks
below.

## Automated evidence

`test/account_session_boundary_test.dart` verifies:

- account A → account B advances the session epoch;
- sign-out → same-account reauthentication also advances it; and
- stale async tokens fail the current-identity check.

The existing startup reliability test verifies Android backup and device
transfer are explicitly disabled for private app data.

## Required device verification

Before external beta, run on a low-memory and a current Android device:

1. Sign in as account A and load private journal/group data while online.
2. Sign out, sign in as account B, and verify A's journal, drafts, outbox,
   media, notifications, and selected group do not appear.
3. Repeat with the app offline after a warm cache, then kill and relaunch.
4. Reconnect and confirm B can load only B-authorized data.
5. Repeat A → sign-out → A to verify a fresh session cannot display stale
   widgets or stale in-flight profile results.

Record the result and the Firestore SDK/platform versions. A failed cache
isolation check is a release blocker; do not work around it by calling
`terminate()`/`clearPersistence()` from a live sign-out path.
