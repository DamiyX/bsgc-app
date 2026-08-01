# App Check rollout

## Source integration gate

The client-side provider plan and activation adapter are implemented in
`lib/services/app_check_bootstrap.dart` using the official FlutterFire
`firebase_app_check` `0.4.5+2` package. `activateConfiguredAppCheck()` runs
after `Firebase.initializeApp()` and before Messaging, Firestore, or any other
Firebase service is used. Provider selection is controlled by the
`BRAID_ENV` compile-time define:

- `local` (the default for development and CI debug builds) uses the Android
  and Apple debug providers;
- `staging` uses Play Integrity on Android and App Attest with DeviceCheck
  fallback on Apple;
- `production` uses the same attested providers as staging.

No debug token is committed or logged by the client. Unsupported web and
desktop targets fail startup with an explicit configuration diagnostic rather
than silently presenting an unenforced client as secure. Web remains outside
the current mobile release scope and needs an explicit reCAPTCHA provider
before it can be supported.

This source integration does not enable either Functions enforcement parameter.
Do not enable enforcement until the release-client and operator gates below
are complete.

Provider policy:

- local development: Android and Apple debug providers;
- staging/release: Play Integrity on Android;
- staging/release: App Attest with DeviceCheck fallback on Apple;
- debug tokens are local secrets and must never be committed or logged.

The required activation adapter should call `FirebaseAppCheck.instance.activate`
after `Firebase.initializeApp`, using the plan selected by the `BRAID_ENV`
compile-time define. Web is outside the current mobile release scope and must
receive an explicit provider before enforcement.

## Staged enforcement

1. Ship activation with both `ENFORCE_APP_CHECK` and
   `ENFORCE_HIGH_ABUSE_APP_CHECK` false.
2. In staging, exercise every callable from signed Android and Apple release
   builds. Record valid, invalid, and missing-token metrics for at least seven
   representative days.
3. Set `ENFORCE_HIGH_ABUSE_APP_CHECK=true` in staging. Verify group creation,
   invite creation/redemption, message creation/editing, comments/reactions,
   reports, publishing, moderation, and appeals. Verify message deletion with
   the broader callable policy as well.
4. Roll the same high-abuse switch to production only after the supported app
   version carrying App Check reaches the agreed adoption threshold.
5. Enable the broader `ENFORCE_APP_CHECK` switch only after all remaining
   callables are verified.

## Rollback

If legitimate-call rejection rises above the release threshold:

1. set the affected enforcement parameter to false;
2. do not remove client token generation;
3. verify callable recovery from a supported release build;
4. retain rejection metrics and diagnose provider/config/version by platform;
5. re-stage enforcement after the corrective release is adopted.

Turning enforcement off is the rollback. It does not weaken authentication,
authorization, validation, or server rate limits.
