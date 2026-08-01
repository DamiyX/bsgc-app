# App Check rollout

## Source integration gate

The client-side provider plan is implemented in
`lib/services/app_check_bootstrap.dart`. Completing activation requires the
official FlutterFire `firebase_app_check` package. Do not enable either
Functions enforcement parameter until release clients include and activate
that package.

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
