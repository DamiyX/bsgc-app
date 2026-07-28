# Braid

Braid is a reflection-centered Flutter app for private Bible journaling, small study circles, contacts-scoped Insights, discussion, and prayer.

This repository contains:

- the Flutter client in `lib/`;
- Firestore and Storage rules plus indexes;
- Firebase Functions, migration tooling, and backend tests in `functions/`;
- canonical-domain hosting source in `web_deployment/`;
- the source audit and remediation ledger in `docs/`.

## Supported product targets

Android is the current release target. iOS has an app target and Associated Domains configuration, but requires Apple signing, a Team ID, Firebase registration, and device verification before release. Web and desktop folders are generated Flutter scaffolding, not supported Braid product surfaces.

The registered Android application ID remains `com.bsgc.bsgc_app` for compatibility with the existing Firebase app. The canonical invite domain is `https://braidapp.com`.

## Prerequisites

- Flutter stable with a Dart SDK compatible with `pubspec.yaml`;
- Android SDK and Java 17 for Android builds;
- Node.js 22 for Cloud Functions;
- Java 11 or newer plus Firebase CLI for Emulator Suite tests;
- an authorized Firebase project identity only for deployment or migration.

No production credential, keystore, Firebase token, or signing password belongs in Git.

## Local client setup

```text
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run
```

The checked-in Firebase configuration identifies the existing Braid Firebase app. Use a separate Firebase project or the Emulator Suite for development data; do not point experimental migrations at production.

## Backend checks

From `functions/`:

```text
npm install
npm run check
npm test
npm run test:rules
```

Rule tests use `demo-braid-rules` and the Firestore/Storage emulators. They do not require production access. Functions unit tests are pure local tests.

## Schema migration

The v2 migration is dry-run by default:

```text
npm run migrate:v2:dry-run
```

Applying changes requires both an authorized project identity and an explicit apply flag described by `functions/scripts/migrate-v2.js`. Never apply before:

1. exporting production Firestore and Storage state;
2. reviewing the dry-run report;
3. validating new rules in emulators;
4. following `docs/release/backend-rollout.md`.

## Android signing and release

Copy `android/key.properties.example` to `android/key.properties` and reference a keystore stored outside Git. Release builds use R8 and resource shrinking and never fall back to debug signing.

```text
flutter build appbundle --release --analyze-size
```

For Play distribution, prefer the AAB. A universal APK is not an accurate estimate of a user’s device-specific download size.

The release workflow requires these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

## Invite-domain setup

Before enabling external invites:

1. replace the release-certificate placeholder in `web_deployment/public/.well-known/assetlinks.json`;
2. replace the Apple Team ID placeholder in `apple-app-site-association`;
3. deploy the files to `braidapp.com` over HTTPS without redirects;
4. verify both association endpoints from a physical device;
5. test installed, not-installed, signed-out, onboarding, expired, revoked, full, and already-member paths.

The website intentionally does not serve a repository APK.

## Architecture and operational documents

- `docs/architecture/ADR-001-security-data-contract.md`
- `docs/architecture/schema-v2.md`
- `docs/product/product-contract.md`
- `docs/design/design-system.md`
- `docs/release/backend-rollout.md`
- `docs/release/release-checklist.md`
- `docs/testing/test-matrix.md`
- `docs/implementation-progress.md`

## Git discipline

Generated dependencies, APK/AAB files, secrets, keystores, logs, and local build directories are ignored. Work should be reviewed on an isolated branch before it is merged into the default branch.
