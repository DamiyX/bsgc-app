# Report 5 — Size, Performance, Scale, and Release

## 1. APK measurement

Audited artifact:

`web_deployment/public/Braid-App-v2.2.apk`

- 92,801,911 bytes
- 92.80 MB decimal
- 88.50 MiB binary
- SHA-256: `7D48C7B23542A0D2720F3205D0F4A58AA5DBCB5D0BA8C02738BE067AA19C31F1`

The reported “about 97 MB” may refer to another artifact or measurement convention. The audited v2.2 file is 92.80 MB.

APK download size and installed size are different measurements.

## 2. Compressed APK composition

Approximate categories:

| Category | Compressed size |
|---|---:|
| Native libraries | 57.75 MiB |
| Flutter/application assets | 11.10 MiB |
| Android resources | 10.14 MiB |
| DEX bytecode | 8.63 MiB |
| `resources.arsc` | 0.46 MiB |
| Other | Remaining content |

Native libraries:

| Architecture | Size |
|---|---:|
| x86_64 | 20.94 MiB |
| arm64-v8a | 19.48 MiB |
| armeabi-v7a | 17.33 MiB |

The universal APK contains all three ABIs. A phone uses one. This is the largest explanation for the artifact size.

## 3. Confirmed avoidable size

### Unused `icon1.png`

- 2048×2048.
- Approximately 6.53 MiB compressed in APK.
- Declared in `pubspec.yaml`.
- No source reference found.

Remove after a final reference check. Expected trade-off: none.

### Oversized `icon2.png`

- 1254×1254.
- Approximately 1.04 MiB.
- Displayed at much smaller sizes.

Resize/compress for actual use. Expected saving: roughly 0.8–0.95 MiB.

### Splash resources

- Source approximately 1881×1881 and 1.17 MiB.
- Repeated raster variants across theme/version/density resources.
- Android `res` totals approximately 10.14 MiB.

Replace with an optimized/vector-friendly mark and correctly generated density assets.

### Release shrinking disabled

`android/app/build.gradle.kts` sets:

- `isMinifyEnabled = false`
- `isShrinkResources = false`

Enable supported release shrinking after tests confirm reflection/plugin behavior.

### Broken/incomplete feature dependencies

Drive backup, Google APIs, and incomplete media features add code and dependency weight. Measure after removing already-deferred MVP features.

KJV and WEB are not the main size problem. Together they provide valuable offline capability for a relatively modest compressed cost.

## 4. Distribution recommendation

Use Android App Bundle for Play distribution:

`flutter build appbundle --release --analyze-size`

Play will deliver device-specific ABI/density/language resources instead of the entire universal APK.

Directional target after:

- AAB delivery;
- unused asset removal;
- icon/splash optimization;
- shrinking;
- removing deferred/broken feature dependencies;

is approximately **35–45 MB download** for a common device configuration. This is an estimate and must be replaced by the size analyzer and Play Console's device-specific download report.

Below 30 MB may require deeper plugin/dependency changes. Do not trade reliability or offline Scripture away without measured evidence.

References:

- <https://docs.flutter.dev/perf/app-size>
- <https://docs.flutter.dev/deployment/android>
- <https://developer.android.com/guide/app-bundle>

## 5. Repository size versus application size

The repository tracks:

- nine APKs, approximately 75–92 MB each;
- `functions/node_modules` with approximately 12,896 files/77.8 MB working-tree size;
- backup `.bak` source files;
- analyzer/build logs;
- patch scripts;
- large web deployment artifacts.

The Git pack is approximately 226.55 MiB.

These files do **not** automatically enter the installed app unless declared as Flutter/Android assets. They still:

- slow clone/fetch;
- complicate review;
- risk GitHub size limits;
- make builds less reproducible;
- increase accidental release confusion.

Actions:

- ignore/remove `node_modules`, retain lockfiles;
- stop committing APKs;
- store builds in CI/Play/release artifacts;
- remove `.bak` files after confirming no needed work;
- repair malformed/duplicated `.gitignore`;
- do not rewrite Git history without explicit approval and coordination.

## 6. Dart/UI performance risks

- Very large stateful screens cause broad rebuilds.
- Voice text controllers are created during build.
- Media files can be fully loaded into memory.
- Profile/referral code performs sequential N+1 queries.
- Multiple redundant streams/count requests.
- Some state is mutated during build.
- Network images lack bounded decode/thumbnail strategy.
- Global Insights sorts/groups client-side.
- Increasing-limit message pagination repeats reads.

Recommended measurement:

- Flutter DevTools CPU/memory/network;
- raster/UI frame timing;
- rebuild profiling;
- low-memory Android test;
- large chat/group datasets;
- image/media decode sizes.

Do not add a new state-management dependency solely to “fix performance.” First separate controllers/repositories and measure.

## 7. Firestore scale risks

### Contact discovery

O(all users) per syncing user; absolute scale blocker.

### Insights

- global unbounded listener;
- client-side sorting;
- unbounded `seenBy`/`likedBy`;
- hot documents;
- no audience partition.

### Profile network

Sequential second-degree referral queries create N+1 growth.

### Messages

Increasing query limits repeatedly read old pages.

### Clear chat

Reads/writes every message rather than one user-state record.

### Group operations

Read-then-update causes races.

### Notifications

Function reads each member profile sequentially and stores one token per user.

Required principles:

- every list query bounded and cursor-paginated;
- no global collection downloads;
- no unbounded arrays on active records;
- per-user state separated from shared content;
- server timestamps;
- transactions/idempotency for state transitions;
- denormalized summaries only when ownership/update path is explicit;
- load-test query counts before launch claims.

## 8. Cloud Functions dependencies

Current `npm audit --omit=dev` reported:

- 10 production dependency vulnerabilities;
- 1 high;
- 9 moderate;
- high finding involving `fast-xml-parser` in the installed dependency graph.

This does not prove exploitation. Upgrade supported Firebase Admin/Functions dependencies, review breaking changes, rerun tests/audit, and deploy through a controlled environment.

`functions/node_modules` must not be committed.

## 9. Android release configuration

### Release uses debug signing

`signingConfig = signingConfigs.getByName("debug")`

Do not distribute publicly in this state.

Required:

- decide permanent application ID;
- create protected upload/release key;
- use Play App Signing;
- keep key material outside Git;
- document key ownership/recovery;
- generate correct App Links fingerprints.

### Package/domain inconsistency

- application ID: `com.bsgc.bsgc_app`;
- deployed association: `com.example.bsgc_app`;
- group shares: `braidapp.com/join/...`;
- manifest handles: `bsgc-app.web.app/invite`.

Choose one permanent domain and package contract before launch.

### Permissions

Manifest includes:

- Internet;
- contacts;
- audio recording;
- legacy external storage;
- media images/video;
- camera.

Camera does not appear necessary for the currently completed gallery-centric flow. Broad legacy/media permissions may be unnecessary on modern Android. Minimize and request contextually.

### Other flags

- `multiDexEnabled = true` is likely unnecessary at minSdk 24.
- Impeller is explicitly disabled without documented evidence.

Measure before retaining nondefault behavior.

## 10. Platform status

### Android

Primary target, but release signing/App Links/store requirements are incomplete.

### iOS

Flutter scaffolding exists, but Firebase options do not support iOS and no complete iOS Firebase configuration is present. Display naming remains template-like.

Declare Android-only MVP until iOS is fully configured, permission-reviewed, signed, and tested.

### Web/desktop

Scaffolding is not evidence of supported products. Remove unsupported-platform promises from documentation.

## 11. Testing and release gates

Before external beta:

- fresh `flutter pub get`;
- format/analyze;
- unit/widget/integration tests;
- Firestore/Storage Emulator tests;
- Function tests;
- release AAB build;
- `--analyze-size`;
- Play internal/closed testing;
- low/mid/high-tier devices;
- Android versions around supported minimum/current;
- airplane/cold-cache testing;
- notification background/terminated/tap routing;
- account deletion;
- App Links installed/not-installed;
- accessibility scan and manual screen reader;
- privacy/data-safety declarations.

## 12. Release artifact strategy

Use:

- CI build artifacts for internal QA;
- Play Internal App Sharing or internal/closed testing;
- versioned release notes;
- checksums and provenance;
- one canonical version source.

Do not distribute multiple ambiguous APKs from a static website/repository as the primary production pipeline.
