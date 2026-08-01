# Review-branch preview guide and Antigravity handoff

## Goal

Preview and evaluate `codex/bsgc-full-remediation` without merging it into the default branch and without deploying or migrating production Firebase data.

This repository is a Flutter application. Android Studio supplies the Android SDK and emulator; Flutter builds and launches the app on that emulator.

## Safety rules

1. Do not merge the branch during preview.
2. Do not run the migration with an apply flag.
3. Do not deploy Functions, indexes, Firestore Rules, or Storage Rules to production.
4. Do not replace production association files or signing configuration with guessed values.
5. Do not discard existing local changes in an old checkout. Use a fresh clone if `git status` is not clean.
6. Use disposable test accounts and non-sensitive content.

## Fresh-clone setup

```text
git clone https://github.com/DamiyX/bsgc-app.git
cd bsgc-app
git fetch origin
git switch --track origin/codex/bsgc-full-remediation
git branch --show-current
git log -1 --oneline
```

The branch command should print:

```text
codex/bsgc-full-remediation
```

If the repository is already cloned:

```text
git status --short
git fetch origin
git switch codex/bsgc-full-remediation
git pull --ff-only origin codex/bsgc-full-remediation
```

If `git status --short` prints local work, stop and preserve it. Do not reset, clean, or force-checkout it merely to preview this branch.

## Android/Flutter prerequisites

- current Flutter stable compatible with `pubspec.yaml`;
- Android Studio with Android SDK, platform tools, and an Android API 35 or 36 system image;
- Java 21 for the repository’s verified local/CI setup;
- Node.js 22 and Java 21 only when running backend/rules tests;
- Git;
- enough free disk space for the Android SDK, Gradle cache, emulator, and app.

Run:

```text
flutter doctor -v
flutter pub get
flutter devices
```

Resolve only the Android and Flutter issues reported by `flutter doctor`. Visual Studio is not required for this Android application.

## Create or start an Android emulator

In Android Studio:

1. Open **Device Manager**.
2. Create a virtual phone such as Pixel 7 or Pixel 8.
3. Select an API 35 or 36 Google APIs image that matches the laptop architecture.
4. Allocate sufficient internal storage.
5. Start the emulator and wait for the Android home screen.

Then confirm Flutter can see it:

```text
adb devices
flutter devices
```

Launch the app:

```text
flutter run
```

If multiple targets are listed:

```text
flutter run -d <device-id>
```

Useful run controls:

- `r` — hot reload;
- `R` — hot restart;
- `q` — stop the app.

Do not use `flutter build appbundle --release --analyze-size` merely to preview the app. That R8 release operation is resource-intensive and is a separate release gate.

## Backend compatibility warning

The branch updates the Flutter client, Cloud Functions, indexes, Firestore Rules, Storage Rules, and schema contract together.

`flutter run` does not deploy those backend changes. If the checked-in Firebase client points to an older deployed backend, visual screens can still be reviewed, but new server-backed actions may fail or behave differently until an approved staging rollout is completed.

That mismatch must be reported as one of:

- client/UI defect;
- expected old-backend incompatibility;
- missing staging/deployment configuration;
- unknown, requiring logs.

Do not “solve” it by deploying to production. Follow `docs/release/backend-rollout.md` and use an approved staging project.

## Automated checks before visual review

From the repository root:

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected result:

- formatting check succeeds;
- analyzer reports no issues;
- 93 Flutter tests pass at the Wave 16 checkpoint (the exact count may increase with later test-only additions; record the command output and commit).

Optional backend/security verification:

```text
cd functions
npm ci
npm run check
npm test
npm run test:rules
```

Expected result:

- 70 Functions tests pass;
- 31 Firestore/Storage rules tests pass.

Rules tests intentionally run serially because both integration-test files share and clear one emulator project.

## Visual and functional review matrix

Record pass/fail, device/API, account state, network state, screenshots, logs, and exact reproduction steps for every failure.

### 1. Startup and authentication

- fresh install while online;
- signed-out launch;
- sign-in failure and retry;
- onboarding at narrow and normal widths;
- warm restart while signed in;
- explicit Firebase/startup error state rather than silent navigation.

### 2. Core navigation and product clarity

- Today, Groups, Journal, and Me are present and understandable;
- next study action is easy to find from Today;
- back navigation and bottom navigation preserve sensible state;
- loading, empty, error, and offline screens are intentional;
- no generic social-media follower/leaderboard language returns.

### 3. Offline media regression

- open the app online and view avatars/group covers;
- close the app, enable airplane mode, and reopen;
- cached media remains visible;
- uncached media shows deterministic initials/local fallbacks rather than blank space;
- profile, settings, contacts, group list, group details, and study room all retain usable identity visuals;
- no spinner remains forever solely because the network is absent.

### 4. Offline outbox and drafts

- type a reflection/message offline and close/reopen the app;
- confirm the draft or queued item survives;
- restore internet and confirm it sends once;
- queue image and voice content, restart, then retry;
- force a failed upload and verify retry/discard;
- confirm no duplicate message appears;
- sign out and confirm another account cannot see the previous account’s drafts/outbox/cache.

### 5. Study lifecycle and administration

- create or open book and topic studies;
- inspect scheduled, active, completed, and archived states;
- verify progress, extension/reactivation, recap, archive, owner transfer, member removal, leave, and role restrictions;
- confirm scheduled/completed rooms prevent unsupported writes;
- verify live group metadata updates without reopening the room.

### 6. Reflections, Insights, and safety

- create a private Journal note;
- create a group Reflection;
- publish a contacts-only Insight;
- confirm explicit audience language;
- confirm an unrelated account cannot read the Insight;
- comment/react only as an eligible viewer;
- block and report;
- confirm participating under one Insight does not expose another commenter’s independent Insights.

### 7. Invitations

- open a valid join link while installed and signed in;
- repeat while signed out and during onboarding;
- test expired, revoked, full, already-member, and blocked states;
- confirm the token, not a raw group ID, grants the invitation opportunity;
- verify QR/share presentation and return flow.

### 8. Notifications

- verify in-app explanation before the OS permission prompt;
- test foreground, background, and terminated routing;
- test master preference, study-message preference, contacts-Insight preference, per-study mute, and lock-screen preview off/on;
- confirm notification taps open the intended destination;
- use two devices/emulators if testing independent per-device tokens.

### 9. Accessibility and layout

- text scale at 100%, 150%, and 200%;
- TalkBack reading order and control names;
- error/send/offline announcements;
- light/dark contrast;
- portrait phone widths including a narrow device;
- 48 dp touch targets;
- keyboard/focus order where applicable;
- no fixed-height clipping or color-only meaning.

### 10. Destructive/account flows

- sign-out cleanup;
- leave study;
- ownership-transfer requirement;
- account deletion with recent-authentication requirement;
- shared-message tombstones;
- blocked deletion when the user still owns a shared study;
- error recovery when a server operation fails.

## Defect report format

```text
Title:
Severity: blocker / high / medium / polish
Branch commit:
Device and Android API:
Flutter version:
Account state:
Network state:
Preconditions:
Steps:
Expected:
Actual:
Reproducibility:
Screenshot/video:
flutter run log:
Likely category: UI / client logic / backend mismatch / rules / environment / unknown
```

## Prompt to paste into Google Antigravity

```text
You are reviewing a Flutter/Firebase remediation branch for the Braid Bible-study and reflection app.

Repository:
https://github.com/DamiyX/bsgc-app

Branch:
codex/bsgc-full-remediation

Your task is verification and reporting first. Do not merge, deploy Firebase, apply migrations, rewrite Git history, delete local work, or change production data.

1. Use a fresh clone, or first prove the existing checkout is clean.
2. Fetch and switch to origin/codex/bsgc-full-remediation.
3. Read these files completely before acting:
   - docs/audit/01-product-and-system-understanding.md
   - docs/audit/02-security-backend-and-privacy.md
   - docs/audit/03-functional-reliability-and-offline.md
   - docs/audit/04-ui-ux-brand-and-accessibility.md
   - docs/audit/05-size-performance-scale-and-release.md
   - docs/audit/06-implementation-plan.md
   - docs/implementation-progress.md
   - docs/remediation-pause-handoff.md
   - docs/testing/branch-preview-guide.md
   - docs/testing/test-matrix.md
   - docs/release/backend-rollout.md

4. Identify the installed Flutter and Android Studio/SDK locations; run flutter doctor -v and fix only local Android/Flutter environment problems.
5. Start an Android emulator, run flutter pub get, then run:
   - dart format --output=none --set-exit-if-changed lib test
   - flutter analyze
   - flutter test
   - flutter run
6. Perform the complete visual/functional matrix in docs/testing/branch-preview-guide.md, especially offline avatars/covers, offline outbox restart/retry, Today/Groups/Journal/Me navigation, study lifecycle, Insights privacy, invitations, notifications, account switching, TalkBack, and 200% text.
7. If Node 22 and Java 21 are available, run from functions/:
   - npm ci
   - npm run check
   - npm test
   - npm run test:rules
8. Keep UI/client defects separate from failures caused by the old deployed Firebase backend. flutter run does not deploy this branch’s Functions, indexes, or rules.
9. Do not deploy anything to production to make a test pass. If full backend testing is required, propose an approved staging rollout following docs/release/backend-rollout.md.
10. Produce a detailed report containing:
   - exact branch commit tested;
   - environment and emulator;
   - every command and result;
   - pass/fail for every matrix section;
   - screenshots/logs for failures;
   - prioritized blocker/high/medium/polish findings;
   - whether the defect is client, backend compatibility, rules, environment, or unknown;
   - explicit merge recommendation: approve, approve after listed fixes, or reject.

Do not silently fix findings during this first review. Report them with exact reproduction evidence so the owner can approve a focused correction pass.
```

## Merge decision

After review:

1. fix confirmed blockers on `codex/bsgc-full-remediation`;
2. rerun all automated and relevant manual checks;
3. inspect the final three-dot diff against the intended target branch;
4. obtain product-owner approval;
5. merge without rewriting history;
6. perform backend rollout and release as separately approved operations.
