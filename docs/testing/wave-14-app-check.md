# Wave 14 — App Check source integration

## Scope

This wave closes the source-controlled part of SEC-007 and RELENG-004 from
the post-remediation audit. It adds the official FlutterFire
`firebase_app_check` package, selects providers by `BRAID_ENV`, and activates
App Check immediately after `Firebase.initializeApp()` and before other
Firebase service use.

## Provider contract

| Build define | Android | Apple | Backend enforcement |
| --- | --- | --- | --- |
| `BRAID_ENV=local` (default) | Debug provider | Debug provider | Must remain off |
| `BRAID_ENV=staging` | Play Integrity | App Attest with DeviceCheck fallback | Must remain off until staging evidence |
| `BRAID_ENV=production` | Play Integrity | App Attest with DeviceCheck fallback | Must remain off until release approval |

Debug tokens are generated/registered outside the repository and are never
passed as source literals. The release workflow explicitly passes
`BRAID_ENV=production`; the quality workflow explicitly passes
`BRAID_ENV=local` for its emulator/debug smoke build.

Web and unsupported desktop targets fail with an explicit startup diagnostic.
They are not treated as App Check-enforced clients. Web support requires a
project-owned reCAPTCHA provider/site key and a separate review.

## Verification performed

- `.tooling/flutter/bin/flutter.bat --version` → Flutter 3.44.8, Dart 3.12.2.
- `.tooling/flutter/bin/flutter.bat pub add firebase_app_check:^0.4.5+2` completed
  successfully and updated `pubspec.yaml`, `pubspec.lock`, and generated
  platform registrants.
- `test/app_check_bootstrap_test.dart` covers local debug mapping, staging and
  production attested mapping, and the injectable activation boundary.
- `flutter analyze`/`flutter test` must be run from the pinned toolchain after
  the parent wave's concurrent edits are settled; this worktree currently has
  unrelated uncommitted files, so no commit or push is performed here.

## Remaining owner/runtime gates

Source activation is not proof that attestation works in a Firebase project.
The owner must still register Android and Apple apps in Firebase App Check,
link Play Integrity to the correct project, configure Apple capabilities,
register local debug tokens privately, and run signed staging clients through
every callable listed in `docs/operations/app-check-rollout.md`. Record valid,
invalid, and missing-token metrics for the agreed observation period before
turning on `ENFORCE_HIGH_ABUSE_APP_CHECK`; keep both backend switches false for
this source-only wave. Re-run the device matrix on low/mid Android and Apple
hardware, emulators, offline/online transitions, and upgrade paths before any
production enforcement decision.
