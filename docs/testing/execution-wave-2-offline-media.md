# Execution Wave 2 — offline and managed-media source closure

**Branch:** `codex/bsgc-full-remediation`
**Starting checkpoint:** `60f2984` (`Complete Wave 4 verification corrections`)
**Plan ownership:** Milestones 5 and 6 of
`docs/post-remediation-audit/05-prioritized-implementation-plan.md`
**Status:** source changes prepared; Flutter/Dart verification is pending in a
Flutter-equipped checkout

This is the next bounded execution slice after the previously integrated
source work. It is not a re-audit and it does not open another execution slice
until this one is tested, reviewed, and committed.

## Track A — local drafts and voice-cache durability

The offline client track closes concrete source gaps in the local persistence
boundaries:

- `DraftService` now serializes operations per account root, validates account
  and group identifiers before invoking a root provider, and rejects paths
  that escape the validated root.
- Draft and composer loads inspect the canonical file plus `.tmp` and `.bak`
  candidates, ignore malformed candidates, select the newest valid record, and
  restore the canonical file while removing stale sidecars.
- Draft replacement keeps the previous valid file until the new file is
  renamed into place. A write-stage hook makes the interruption boundary
  deterministic in tests.
- `VoiceCacheService` writes metadata through the same backup-preserving
  replacement contract, repairs valid metadata sidecars during lookup/prune,
  and removes stale orphan temporary files without deleting active downloads.
- Voice downloads use unique temporary paths so concurrent operations cannot
  delete one another's partial file. Account clear increments a generation,
  removes stale in-flight coalescing entries, waits for the short filesystem
  barrier, and prevents an ended operation from deleting a replacement cache
  entry.

Regression coverage added:

- `test/draft_service_recovery_test.dart`: temporary/backup recovery,
  interrupted replacement, per-root write serialization, and unsafe IDs.
- `test/voice_cache_service_test.dart`: metadata sidecar recovery,
  interrupted metadata replacement, and same-account clear/in-flight
  invalidation.

## Track B — managed media cleanup and migration leases

The backend track closes two source contracts:

- Finalized Storage objects are recognized across canonical profile-photo,
  group-cover, and group-message paths. An unregistered object is deleted only
  when its path and bucket pass the managed-media guard, with idempotent
  `ignoreNotFound` behavior. Noncanonical and malformed objects are left
  untouched.
- Migration lease expiry uses a live injectable lease clock on every acquire
  and renewal. Persisted rehearsal timestamps remain deterministic through
  `nowMillis`, while production renewals do not reuse a fixed startup time.

Regression coverage is in
`functions/test/functions/managed_media.test.js` and
`functions/test/functions/migration_runner.test.js`.

## Verification recorded so far

- `npm run check`: passed.
- `npm test -- --test-concurrency=1`: **90 tests passed**.
- `npm run test:rules`: **32 tests passed**.
- `git diff --check`: passed.
- Dart/Flutter commands were not runnable in this shell because neither
  executable is installed or available on `PATH`. The focused and full Flutter
  suites therefore remain an explicit external verification item, not an
  assumed pass.

## Boundary and remaining evidence

This execution slice does not claim to prove Android process death, radio
transitions, codec behavior, native Firestore cache isolation, deployed
Storage/Functions parity, or release readiness. Those checks are listed in
`offline-capability-matrix.md` and the Wave 4 handoff. No outbox contract was
changed in this slice because its checksum, recovery, quota, and retry seams
were already present and remain covered by the existing tests.

The next execution slice must not open until this one has a Flutter-equipped
verification result, a reviewed diff, and a commit on this branch. If that
verification finds a new source defect, it must be recorded as the concrete
reason for the next slice; otherwise the remaining work is external
acceptance, deployment, and owner approval rather than an automatic wave.
