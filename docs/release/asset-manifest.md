# Runtime asset manifest and size review

This is the source-side asset inventory for the Android release evidence. It
is intentionally separate from the signed AAB report: Flutter and Play can
compress, split, and transform assets, so source bytes are a triage signal,
not a download-size claim.

Measured on 2026-08-01 at commit `9a25f2f` with PowerShell
(`Get-ChildItem -Recurse assets,android/app/src/main/res`):

| Asset or family | Approx. source size | Decision |
| --- | ---: | --- |
| `assets/bibles/kjv.json` | 4.34 MiB | Keep. Required for the promised offline KJV path. |
| `assets/bibles/web.json` | 4.08 MiB | Keep for now. Confirm translation/licensing and offline product scope before replacing or splitting it. |
| `assets/logos/icon 6.png` | 5.35 MiB | Not declared in `pubspec.yaml`; preserve as an unapproved design source until the owner selects the production mark. |
| `assets/logos/icon 3.png` | 4.51 MiB | Same: preserve, but do not package accidentally. |
| `assets/logos/icon 7.png` | 4.05 MiB | Same: preserve, but do not package accidentally. |
| `assets/logos/Braid-Logo.png` | 1.12 MiB | Unapproved design source; not declared at runtime. |
| `assets/logos/icon 4.png` | 0.94 MiB | Unapproved design source; not declared at runtime. |
| `assets/logos/icon 5.png` | 0.72 MiB | Unapproved design source; not declared at runtime. |
| `assets/launcher_icon_radial.png` | 1.34 MiB | Native launcher build input; keep until the replacement icon is visually approved. |
| `assets/padded_icon.png` | 1.19 MiB | Native launcher build input; keep until the replacement icon is visually approved. |
| `assets/splash_icon.png` | 1.12 MiB | Native splash build input; keep until the replacement splash is visually approved. |
| `assets/launcher_icon.png` | 0.84 MiB | Declared launcher input; keep. |
| `assets/splash_icon_padded.png` | 0.51 MiB | Declared splash input; keep. |
| Android `splash.png` / `android12splash.png` density and night variants | about 9 MiB combined | Optimization candidate. Re-generate from one approved source after visual review; do not delete density variants blindly. |
| `assets/fonts/Comfortaa/*` | about 0.39 MiB | Keep; declared runtime font. |
| `assets/sounds/*` | about 0.10 MiB | Keep; declared runtime sounds. |

## Packaging boundary

The Flutter runtime manifest currently declares only `assets/icon2.png`,
`assets/bibles/`, and `assets/sounds/`; the `Comfortaa` font family is also
declared under `flutter.fonts`. The logo drafts are therefore not included
through a broad `assets/logos/` glob. The splash and launcher images under
`android/app/src/main/res` are native Android resources and are included by the
Android build when referenced by the generated launch configuration.

## Release-size procedure

1. Run the manual signed workflow
   [`.github/workflows/release-android.yml`](../../.github/workflows/release-android.yml)
   from the exact reviewed commit.
2. Retain the AAB, arm64 device APK, SHA-256 file, toolchain file, artifact
   inventory, and any Flutter `size-analysis*.json` output together.
3. Compare the Play Console device-specific download size, not the universal
   APK or the repository's historical 90–97 MB debug/install estimate.
4. Only after visual approval, optimize duplicated splash resources and rerun
   the same evidence procedure. Never remove the offline Bible assets merely
   to improve a headline number.

## Known external inputs

The Play App Signing certificate, Play Console size report, and signed AAB are
not present in this checkout. The release owner must put the real Play App
Signing SHA-256 fingerprint in
`web_deployment/public/.well-known/assetlinks.json` for Play-installed builds;
the upload certificate is a separate credential and must not be substituted
for the Play app-signing certificate. A placeholder must never ship to
production.
