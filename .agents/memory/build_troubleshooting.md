# Android Studio & Flutter Build Troubleshooting

## Incident (June 2026)
Symptom: App stuck on splash screen, unable to build in Android Studio. Storage space rapidly disappearing.

## Fixes Applied
1. Flutter SDK Repair: Deleted flutter/bin/cache and ran flutter.bat --version
2. AGP & Gradle Alignment: Updated settings.gradle.kts to 8.9.1 and gradle-wrapper to 8.11.1.
3. Kotlin Plugin: Updated to 2.2.20.
4. Storage: Deleted massive corrupted caches and unused Pixel 7 emulator.
