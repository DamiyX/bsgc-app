# Milestone 11 verification — release configuration and measured size

Date: 2026-08-01
Branch: `codex/bsgc-full-remediation`
Source checkpoint before this slice: `9a25f2f`

## Source changes verified

- `android/gradle.properties` no longer reserves an 8 GB Gradle heap. Local
  builds use 3 GB heap, 1 GB metaspace, two workers, and serial project
  execution.
- `.github/workflows/quality.yml` pins Flutter 3.44.8 and adds an arm64 debug
  APK compile smoke.
- `.github/workflows/release-android.yml` pins Flutter 3.44.8, serializes
  signed runs, declares the `android-release` environment, captures commit/ref
  and toolchain/version evidence, builds an arm64 signed AAB and arm64 split
  APK with size analysis, and uploads checksums, size reports, mapping/symbol
  outputs, and artifacts.
- `android/app/build.gradle.kts` and the release workflow share an explicit
  `storeFile` path relative to `android/`.
- Firebase Hosting no longer ignores `.well-known`, so the association files
  can be deployed and served with their JSON content types.
- `docs/release/asset-manifest.md` documents source sizes and the approved
  runtime/draft boundary without removing unapproved assets or offline Bibles.

## Automated checks

| Check | Result |
| --- | --- |
| Flutter toolchain inspection | Flutter 3.44.8 / Dart 3.12.2 |
| Local arm64 debug APK compile (120-second bound) | Inconclusive: timed out without APK; Gradle stopped |
| Local arm64 debug APK compile (300-second bound) | Inconclusive: timed out without APK; Gradle stopped |
| Quality CI arm64 smoke | Pending GitHub run on this commit |
| Signed arm64 AAB and arm64 APK size analysis | Pending release-owner secrets/environment |
| Play device-specific download/install estimate | Pending Play Console |
| Production assetlinks and installed invite flow | Pending production host, certificate, and device |

The local timeout is not reported as a successful build and is not treated as
proof of a code-level Android failure. It is evidence that repeated local
release-style compilation is unsuitable for this machine; CI is the required
clean-build check.

## Remaining owner-controlled gates

1. Configure required reviewers and secrets in the `android-release` GitHub
   environment.
2. Replace the assetlinks placeholder with the Play App Signing SHA-256 and
   deploy Hosting; verify with HTTPS `curl` and the Android App Links checker.
3. Run the signed workflow from the exact reviewed commit and retain the AAB,
   arm64 APK, checksums, size-analysis JSON, mapping/symbol outputs, and
   toolchain evidence.
4. Record Play Console arm64 download/install estimates and exercise the
   canonical invite link from a Play-installed build.
