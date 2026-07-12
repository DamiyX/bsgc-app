# Android Studio, VS Code & Flutter Build Troubleshooting

This document is persistent project memory for any Anti-Gravity agent working on this codebase. 
**ALWAYS read this before attempting to resolve build issues or VS Code crashes in this workspace.**

## 1. VS Code Dart Analysis Server Crash (Error -32097)
**Symptom:** VS Code bottom bar says "No device" despite a phone being plugged in. The Dart/Analyzer output pane shows: `Pending response rejected since connection got disposed Code: -32097`. The analysis server crashes 3 times and gives up. Running `flutter doctor` or `flutter --version` in terminal hangs endlessly.
**Root Cause:** Ghost processes (`vdart.exe` or `dart.exe`) are holding an infinite lock on the Dart SDK cache, which eventually corrupts it. Redundant paths in `.vscode/settings.json` can also trigger initialization races.
**The Fix Sequence:**
1. **Kill Ghost Processes:** `cmd.exe /c "taskkill /F /IM dart.exe & taskkill /F /IM vdart.exe"`
2. **Nuke Corrupted Cache:** `cmd.exe /c "rmdir /S /Q C:\Users\HP\Documents\DEV\flutter3\bin\cache\dart-sdk"`
3. **Redownload SDK:** Run the direct executable `C:\Users\HP\Documents\DEV\flutter3\bin\flutter.bat doctor -v` to force a clean redownload of the Dart SDK.
4. **Fix VS Code Settings:** Ensure `.vscode/settings.json` ONLY defines `"dart.flutterSdkPath"`. Remove any manual `"dart.sdkPath"` entry.
5. **Restart VS Code:** The Analysis server will launch successfully. Note: This workflow has also been saved globally as the `vs-code-dart-crash` skill.

## 2. "Errors exist in your project" Popup in VS Code
**Symptom:** Pressing F5 / Run in VS Code pops up an error refusing to launch the app, but the current file only shows yellow `avoid_print` warnings.
**Root Cause:** VS Code blocks compilation if there are *any* fatal syntax errors or missing packages anywhere in the project, not just the active file.
**The Fix Sequence:**
1. Do **not** assume the warnings in the active file are the cause.
2. Run `flutter analyze` in the terminal to reveal the true compilation-blocking errors (e.g., missing package dependencies, syntax errors in other screens).
3. Fix the fatal errors (e.g., `flutter pub add <missing_package>`). Once `flutter analyze` returns only "infos" and "warnings" (0 errors), the user can safely click "Run Anyway".

## 3. APK Installation Failure: "Requested internal only, but not enough space"
**Symptom:** `flutter run` or `flutter build apk` successfully compiles the APK, but fails right at the end during `Performing Streamed Install` with `java.io.IOException: Requested internal only, but not enough space`.
**Root Cause:** The target device (Samsung SM A156E) has zero internal storage space remaining. The APK cannot be transferred.
**The Fix:** This is a hardware state issue, not a code issue. Instruct the user to delete old files/apps to free up at least 500MB - 1GB of space on their phone.

## 4. App Crashing on Launch (Release / Built APK)
**Symptom:** The app runs perfectly in Debug mode through VS Code, but when built as an APK (`flutter build apk`) and installed manually, it crashes immediately on the splash screen.
**Root Cause:** Often caused by `FirebaseCrashlytics`, Cloudinary missing config, or unhandled exceptions in `main()` before `runApp()` executes. Debug builds swallow these gracefully; release builds crash.
**The Fix:** 
- Wrap `Firebase.initializeApp()` in a `try-catch` block.
- Ensure any pre-launch services (like Cloudinary preset configuration) have fallback default values.
- Never let an async init function fail unhandled inside `void main()`.

## 5. Gradle / Android Studio Environment History
- **AGP Version:** 8.9.1 (defined in settings.gradle.kts)
- **Gradle Wrapper:** 8.11.1
- **Kotlin Version:** 2.2.20
- **Warning Notice:** If the build fails indicating mismatched KGP (Kotlin Gradle Plugin) versions across plugins (like `flutter_contacts`, `share_plus`), update the plugins using `flutter pub upgrade`.
