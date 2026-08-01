# Remediation Wave 3 / Repository Continuation Wave 22 — Timestamp Contract

## Scope

This track closes the remaining REL-028 compatibility-reader defect in the
Flutter models. It is intentionally limited to historical timestamp parsing
for groups, notes, Insights/comments, and the existing message compatibility
path. Deletion, notification, and backend files are outside this track.

## Finding and correction

`NoteModel.fromFirestore` and `InsightModel.fromMap`/`InsightCommentModel`
used `DateTime.now()` when a stored timestamp was missing or malformed. A
legacy record could therefore move to the top of a list every time a stream
rebuilt. The group reader already used the Unix epoch, but did not expose that
the source timestamp was unknown.

The new `lib/models/timestamp_contract.dart` defines one stable epoch and a
small resolver that returns both the value and whether the source was usable.
The readers now:

- use the stable epoch rather than the current wall clock for unknown history;
- retain a valid `createdAt` when `updatedAt` is missing (notes and Insights);
- derive a missing Insight expiry from the stable/created value, never from
  the current time; and
- expose `hasKnownCreatedAt`, `hasKnownUpdatedAt`, and
  `hasKnownExpiresAt` (where applicable) so UI or migration tooling can flag
  malformed records instead of treating a fallback as authoritative.

`MessageModel` already had the equivalent `hasKnownTimestamp` and client
timestamp precedence. Its existing epoch behavior is covered by the new
contract tests rather than rewritten.

## Changed source

- `lib/models/timestamp_contract.dart`
- `lib/models/note_model.dart`
- `lib/models/insight_model.dart`
- `lib/models/group_model.dart`
- `test/timestamp_contract_test.dart`

The new `fromMap` factories on Note, Group, and InsightComment make the same
compatibility contract testable without constructing sealed Firestore snapshot
objects; the production `fromFirestore` paths delegate to those factories.

## Verification

Focused command (pinned Flutter toolchain):

```text
.tooling/flutter/bin/flutter.bat test test/timestamp_contract_test.dart --reporter compact
```

Result: **4 tests passed**. The test cases cover stable repeated fallbacks,
note created/updated fallback semantics, Insight/comment malformed-state flags,
group epoch ordering, and message server/client/unknown timestamp precedence.

Static analysis of the five changed Dart files passed after removing a test
fake that attempted to implement sealed `DocumentSnapshot` (the final test
uses the production `fromMap` seam).

## Remaining evidence boundary

This source-level fix does not repair existing Firestore documents. A deployed
migration/repair job still needs to identify records whose timestamp flags are
false and write authoritative timestamps where the business history can be
recovered. Device/emulator review should confirm that unknown records are
visually distinguishable (or safely omitted from date-dependent views) and
that pending server timestamps settle to their authoritative values after
reconnect.
