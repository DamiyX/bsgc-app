# App size, performance, release, and quality audit

## Executive answer about the reported 90–97 MB size

The repository does **not** currently contain a trustworthy final APK/AAB artifact that proves the Play Store download size is 90–97 MB. That number is most likely one of:

- a universal debug APK;
- an installed application size reported by Android;
- a locally shared APK containing multiple CPU architectures;
- a release APK rather than an Android App Bundle;
- a measurement that includes extracted native libraries, caches, or user data.

Those numbers are not directly comparable with the compressed per-device download that Google Play serves from an AAB.

The app has legitimate size contributors, but nothing in the inspected source supports the conclusion that a real Play download must be 97 MB.

---

## Size evidence from the repository

### Declared Flutter assets

Approximate raw total:

**9.55 MB**

The largest functional assets are the two offline Bible JSON files:

- KJV: approximately **4.56 MB raw**
- WEB: approximately **4.28 MB raw**

Test compression produced approximately:

- KJV gzip: **1.37 MB**
- WEB gzip: **1.20 MB**

Combined compressed Bible payload: approximately **2.56 MB**.

These files are valuable to the offline product promise and are not a credible explanation for a 97 MB Play download by themselves. Their larger runtime cost is discussed below.

### Android packaged resources

Approximate raw total:

**11.09 MB**

Splash-screen variants account for approximately:

**10.31 MB**

The same high-resolution visual is represented across light/dark, density, and Android-version resource variants. PNG assets may already be compressed, so ZIP/AAB compression cannot always reduce them substantially.

### Tracked repository assets

Approximate total:

**32.52 MB**

Several draft logos are around 4–5.6 MB each. They are not all declared in `pubspec.yaml`, so they do **not** all increase the packaged application. They do increase repository clone/history size and create asset-selection confusion.

### Native dependencies

The app includes substantial native functionality:

- Firebase Auth;
- Firestore;
- Storage;
- Messaging;
- Functions;
- Crashlytics;
- Google Sign-In;
- local notifications;
- audio recording/playback;
- text-to-speech;
- image selection/compression;
- caching and connectivity libraries.

Native SDKs and the Flutter engine are likely a larger contributor to a universal APK than the app’s Dart feature count. An app with “more screens” can still be smaller if it has fewer native SDKs, a different build mode, or a split delivery format.

---

## SIZE-001 — The current measurement compares unlike artifacts

**Severity:** P1 diagnostic gap

App size must be named precisely:

- universal APK file size;
- split APK download size for a specific ABI/density/language;
- AAB upload size;
- Play Console download size;
- installed size;
- installed size plus cache/user data.

Without this, a “30 MB app” and a “97 MB app” may not be measuring the same thing.

**Required correction**

Establish one release measurement record containing:

| Measurement | Required value |
|---|---|
| Build commit | exact Git SHA |
| Flutter version | exact stable version |
| Build mode | release |
| Artifact | signed AAB |
| Analysis | `--analyze-size` report |
| Target | representative arm64 Android device |
| Play download | Play Console estimate/actual |
| Installed | fresh install before content cache |

Do not optimize against a number until it is reproducible.

---

## SIZE-002 — Splash assets are disproportionately large and duplicated

**Severity:** P1

Android splash resources account for almost all inspected Android raw resource bytes.

**Impact**

- Avoidable package/repository size.
- Longer resource processing during builds.
- More manual variants to maintain.

**Recommended correction**

1. Identify the exact visible source used on each supported Android version.
2. Prefer a compact vector/brand mark over full-canvas high-resolution PNGs where Android splash constraints allow.
3. Optimize PNG dimensions and bit depth to the actual rendered size.
4. Generate variants from one approved source rather than storing unrelated exports.
5. Compare AAB component size before and after; do not judge only raw source bytes.

This can improve size without reducing UX quality if the rendered result is visually verified.

---

## SIZE-003 — Draft brand assets bloat the repository and asset workflow

**Severity:** P2

Large draft logos are tracked even when not bundled.

**Impact**

- Clone and history weight.
- Team uncertainty about the authoritative asset.
- Risk that a future broad asset declaration packages drafts accidentally.

**Recommended correction**

- Keep approved runtime exports under a clearly named app asset directory.
- Keep editable design sources in an appropriate design/source location or release package.
- Remove obsolete drafts only after the team confirms they are recoverable from history/design storage.
- Add an asset manifest documenting source, dimensions, purpose, and optimization.

This cleanup should be a separate reviewed commit because deletion is destructive and the current files may belong to ongoing brand work.

---

## SIZE-004 — Offline Bible data is reasonable for size but expensive at startup/runtime

**Severity:** P1 performance

Both Bible JSON files are loaded before `runApp`. Raw JSON decoding creates many Dart objects and strings, often consuming several times the on-disk byte size in memory.

**Impact**

- Blank/native splash lasts longer on slower devices.
- Increased startup CPU and peak memory.
- The app cannot display a useful shell if parsing fails or is slow.

**Recommended correction**

For the near term:

- call `runApp` after only essential Firebase/config initialization;
- load Bible content lazily behind a repository;
- load the selected translation first;
- show a controlled loading/error state;
- move heavy parsing off the critical first-frame path where practical.

For later measurement-driven optimization:

- benchmark indexed binary/SQLite formats;
- load by book/chapter instead of decoding both complete translations;
- keep the current fully offline promise.

Do not remove offline Scripture merely to win a small size number. Optimize its representation and load path.

---

## Performance findings

### PERF-001 — Startup blocks on multiple unbounded operations before first frame

**Severity:** P1
**Evidence:** app initialization

Startup performs Bible asset parsing and deep-link initialization before the Flutter UI can render. SharedPreferences initialization and other dependencies also have insufficient failure isolation/timeouts.

**Required correction**

Split startup into:

- **boot-critical:** binding, minimal configuration, Firebase needed for auth shell;
- **post-frame:** Bible repository warming, notification/deep-link resolution, nonessential preferences;
- **on-demand:** secondary translation and expensive caches.

Every startup dependency needs a bounded failure state. The app shell must remain usable when a noncritical service fails.

---

### PERF-002 — Large “god screens” increase rebuild and regression risk

**Severity:** P1

Study Room, View Insight, and Main Hall combine multiple subscriptions, lists, controls, and side effects in very large files.

**Impact**

- Harder to isolate unnecessary rebuilds.
- Difficult to profile and test state transitions.
- Small changes cause wide analyzer/build work and merge conflicts.

**Required correction**

Refactor along state ownership boundaries, then profile with Flutter DevTools:

- rebuild counts;
- raster/UI frame time;
- memory during long room scroll;
- audio/image cache behavior;
- stream subscription lifetime.

Refactoring alone is not a performance claim; measure before and after.

---

### PERF-003 — Feed pointer hydration creates N+1 reads and latency

**Severity:** P1

Insights load pointer records and then individual content records. Saved content can trigger up to roughly 100 dependent reads.

**Impact**

- Slower feed open on poor networks.
- High Firestore bill.
- Many independent failure points.

**Recommended correction**

Denormalize an authorized display snapshot or use a queryable content structure that supports the required audience checks. Paginate and measure:

- reads per open;
- time to first content;
- time to complete page;
- cache hit rate.

---

### PERF-004 — Voice playback has no explicit offline cache path

**Severity:** P1

Images use cache-aware rendering, while audio playback relies on its remote URL.

**Impact**

- Previously played voice reflections may fail offline.
- Behavior is inconsistent across media types.

**Recommended correction**

Create an account-scoped media cache policy:

- stream immediately online;
- cache after explicit download or first successful play;
- show download/cached state;
- cap total bytes and use LRU cleanup;
- delete on account switch/sign-out based on privacy policy;
- never store unbounded audio silently.

---

### PERF-005 — Local outbox has no quota or retention bound

**Severity:** P1

Queued entries can include large images/audio. There is no robust total-byte quota, item cap, or expiry policy.

**Impact**

- Storage growth and low-disk failures.
- Retry loops around files that no longer exist.
- Sensitive content retained indefinitely.

**Required correction**

Define:

- maximum per-item media size;
- maximum queue item count and total bytes;
- retry/backoff policy;
- user-visible failed-items state;
- expiry/manual discard;
- cleanup of associated temporary media.

---

### PERF-006 — Unbounded list queries will degrade with loyal users

**Severity:** P1

Groups and notes can grow without server-side pagination/archiving boundaries.

**Required correction**

Use cursor pagination, bounded active lists, and archive/history screens. Profile with datasets representing one month, one year, and several years of intended usage.

---

## Build and workstation findings

### BUILD-001 — The heavy task was release compilation, not an emulator

**Severity:** Operational clarification

No Android emulator was required for the work that caused the laptop to lag. The expensive process was Android release compilation/minification/resource shrinking.

`android/gradle.properties` allocates approximately:

- Gradle heap: 8 GB;
- metaspace: 4 GB.

Those are maximums rather than guaranteed steady usage, but on a laptop with limited RAM they can create severe memory pressure alongside the IDE, Codex, browser, and antivirus.

**Recommended local configuration**

For routine development on a constrained laptop, begin with a lower project-approved budget such as 2–4 GB heap and 1 GB metaspace, then increase only if measured builds fail. Do not change it blindly: the correct value depends on project size, RAM, and Gradle/R8 behavior.

Use:

- physical-device/debug builds for routine preview;
- one release/AAB build at a milestone;
- CI for repeatable heavy builds when available;
- no emulator unless visual/device testing actually requires one.

---

### BUILD-002 — Flutter is not available on the current PowerShell PATH

**Severity:** Verification environment gap

A fresh local dependency diagnostic could not run because `flutter` was not found in the active shell PATH. Historical CI evidence exists, but it does not replace a current local run for this exact worktree.

**Required correction**

On the tester’s machine:

1. install/use the project-approved Flutter stable version;
2. ensure `flutter doctor -v` is healthy;
3. confirm Android SDK licenses and a device/emulator;
4. run `flutter pub get`;
5. run format/analyze/test before preview.

Do not install or globally reconfigure the user’s environment as an implicit part of an audit.

---

### BUILD-003 — Current output does not include a completed release artifact

**Severity:** Verification gap

Inspected build output contains mapping/log material but no final APK/AAB suitable for size conclusions. The previous release build was stopped to avoid further laptop impact.

**Required correction**

Run the size measurement once, deliberately, on a capable machine or CI after functional corrections stabilize.

---

## Release engineering findings

### RELENG-001 — Normal quality CI does not compile Android

**Severity:** P1

The quality workflow covers formatting, analysis, Flutter tests, Functions tests, and rules tests, but Android release compilation is delegated to a separate manual signed workflow.

**Impact**

- Pull requests can pass while native Gradle/resource/manifest issues remain.
- Release-only shrinking problems are discovered late.

**Recommended correction**

Add an unsigned Android compile smoke check on pull requests or protected branch merges:

- `flutter build apk --debug` for faster native integration validation; or
- a carefully cached unsigned release build on scheduled/release-candidate runs.

Keep secret-dependent signed builds manual/protected.

---

### RELENG-002 — Production App Links configuration is incomplete

**Severity:** P0 for public invite links

The Android Digital Asset Links file contains placeholder production certificate data. Apple association configuration is also placeholder/incomplete, and the iOS Firebase configuration file is absent.

**Impact**

- Invite links may open a browser instead of the app.
- Verification differs between debug and production signing.
- iOS cannot be claimed as production-ready.

**Required correction**

- obtain the real Play App Signing SHA-256 certificate;
- update hosted `assetlinks.json`;
- verify declared package/host paths;
- test a Play-installed build;
- complete Apple association/Firebase setup only if iOS is in scope.

Until then, document the release as Android-only and treat external invite links as not production-verified.

---

### RELENG-003 — Release size and functionality lack a reproducible evidence bundle

**Severity:** P1

There is no committed/generated release record joining:

- source SHA;
- toolchain versions;
- tests;
- rules/function deployment versions;
- artifact checksum;
- size report;
- manual device results.

**Recommended correction**

For every release candidate, generate a small evidence package:

```text
commit
Flutter/Dart/Java/Gradle versions
format/analyze/test results
Functions/rules test results
APK/AAB build result
artifact SHA-256
analyze-size summary
manual device matrix
known limitations
```

This prevents “it worked on my laptop” from becoming the release standard.

---

### RELENG-004 — App Check cannot be enabled safely as a release toggle

**Severity:** P1

This is also covered in the security report. Release engineering must include client provider configuration and staged enforcement, not just a Functions parameter change.

---

## Quality strategy

### Current positive controls

- formatting/analyzer workflow;
- Flutter tests;
- Functions tests;
- Firestore/Storage rules tests;
- Crashlytics dependency/configuration;
- release minification/resource shrinking settings;
- manual signed Android workflow.

### Major gaps

- too few Flutter journey tests;
- no regular Android native compile in quality CI;
- no offline/reconnect integration suite;
- no notification/deep-link device suite;
- no accessibility/golden matrix;
- no scale/load fixtures for feed, migration, cleanup, deletion;
- no measured startup/frame/read-cost budgets;
- no release evidence bundle.

### Recommended quality gates

#### Every pull request

- formatting;
- static analysis;
- unit/widget tests;
- Functions/rules tests;
- Android debug compile smoke;
- secret scan/dependency advisory check.

#### Release candidate

- signed AAB;
- `--analyze-size`;
- physical low/mid-range Android device;
- offline cold/warm start;
- notification and invite deep links;
- OS permission denial/re-enable;
- TalkBack, 200% text, dark mode;
- account switching and deletion;
- migration/cleanup scale simulation;
- Crashlytics symbol/mapping upload verification.

#### Production monitoring

- crash-free users/sessions;
- cold-start time;
- failed/queued writes;
- callable error/rate-limit volume;
- Firestore reads per core journey;
- Storage orphan/backlog age;
- lifecycle cleanup backlog;
- notification delivery/open destination failures;
- support reports by workflow.

---

## Recommended size-reduction sequence

Do this in order so quality is not traded for a misleading number:

1. Produce a signed release AAB and analyze-size report.
2. Record arm64 Play download/installed estimates.
3. Optimize the duplicated splash resources.
4. Remove only confirmed obsolete/unbundled design drafts from active runtime paths.
5. Lazy-load/index offline Bible data for startup memory, not merely package size.
6. Inspect native library contribution by package in the size report.
7. Remove a dependency only if its capability is unused and replacement does not reduce reliability.
8. Re-measure the same artifact class and device target.

### What should not be done

- Do not remove offline Bibles solely to make the APK look smaller.
- Do not disable Crashlytics, security, or required Firebase modules without an architectural replacement.
- Do not compare debug universal APK size with Play-delivered app size.
- Do not run repeated release builds on the constrained laptop while functionality is still changing.
- Do not claim a reduction until a reproducible AAB report proves it.

---

## Final size conclusion

The likely explanation for the reported 90–97 MB is primarily **build/distribution format plus the Flutter/native SDK stack**, with **oversized duplicated splash resources** as a real optimization opportunity. The offline Bible assets are not the main explanation and support an important product promise.

A professional answer requires one controlled AAB measurement. Until that exists, any exact “the app should be X MB” claim would be speculation.
