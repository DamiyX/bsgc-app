# Remediation Wave 3 remaining-work handoff

**Current remediation label:** Wave 3
**Historical repository label:** continuation Wave 22
**Starting source checkpoint:** `ae824b7`
**Branch:** `codex/bsgc-full-remediation`
**Status:** source corrections and local verification complete; commit is the
next delivery step; no push has been performed

## What this wave closed

### Track A — deletion semantics (`SEC-011`)

The client previously said “permanently delete,” “Delete for everyone,” or
“Reflection deleted” while the current backend deliberately keeps status or
tombstone records for synchronization, moderation, or retention. A centralized
copy contract now distinguishes removing content from physically erasing all
records:

- reflection removal explains the `status: deleted` and retention boundary;
- account deletion explains disabled-first processing, deleted-account
  tombstones, retained safety records, and the final retention policy;
- message removal is labelled “Remove for everyone” and explains retained
  safety metadata;
- saved Insight actions say “Remove bookmark,” not “Delete.”

Changed source/test/documents:

- `lib/services/deletion_semantics.dart`
- `lib/screens/my_insights_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/study_room_screen.dart`
- `lib/widgets/saved_insight_card.dart`
- `test/deletion_semantics_test.dart`
- `test/insight_reliability_test.dart`
- `docs/testing/wave-22-deletion-semantics.md`

### Track B — stable historical timestamps (`REL-028`)

Note, Insight, comment, and group compatibility readers no longer substitute
the current wall clock for missing or malformed historical timestamps. They use
one stable Unix epoch and expose known-state flags. Message compatibility
already had the equivalent epoch/client-created precedence and is now covered
by the shared contract tests.

Changed source/test/documents:

- `lib/models/timestamp_contract.dart`
- `lib/models/note_model.dart`
- `lib/models/insight_model.dart`
- `lib/models/group_model.dart`
- `test/timestamp_contract_test.dart`
- `docs/testing/wave-22-timestamps.md`

## Verification trace

Using the pinned Flutter toolchain:

```text
.tooling/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test
.tooling/flutter/bin/flutter.bat analyze
.tooling/flutter/bin/flutter.bat test --reporter compact
cd functions
npm run check
npm test -- --test-concurrency=1
```

Results:

- Insight reliability: **13 passed**;
- deletion semantics: **2 passed**;
- timestamp contract: **4 passed**;
- combined Wave 3 focused tests: **19 passed**;
- full Flutter suite: **121 passed**;
- `flutter analyze`: no issues;
- formatting and `git diff --check`: pass;
- Functions syntax check: pass;
- Functions suite: **78 passed**;
- no Functions or Rules files changed; the integrated **31-test** Rules
  Emulator baseline remains the applicable Rules evidence.

## Remaining boundaries

Wave 3 is source closure, not a claim that physical erasure or historical
repair is complete. The following still require approved external evidence:

1. Owner/legal approval of the retention duration and wording, plus deployed
   parity for account deletion, message tombstones, Insight removal, and
   moderation records.
2. A migration/repair job for existing rows whose timestamp flags are false;
   the client cannot reconstruct an authoritative historical instant from a
   missing field.
3. Android emulator/physical-device review of wrapped deletion copy, unknown
   timestamp presentation, offline restart, accessibility, and account-job
   progress/failure.
4. Firestore native cache/account-switch proof, App Check registration and
   enforcement, CI Android compilation, signed AAB size analysis, staging
   rollout/rollback, backup/migration rehearsal, operations, legal, and
   product approval.

## Sequencing rule

The normalized sequence is now remediation Wave 1 (old repository Wave 20),
remediation Wave 2 (old repository Wave 21), and remediation Wave 3 (old
repository Wave 22). There is no honest fixed number of remaining waves. Open
the next wave only for a concrete defect from source, CI, device, or deployed
evidence; keep at most two tracks inside a wave and never run multiple waves
concurrently.
