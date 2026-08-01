# Remediation Wave 3 / repository continuation Wave 22 — deletion semantics

**Finding:** `SEC-011` (P1 — “permanent delete” copy did not match status or
tombstone behavior)

**Scope:** Insight removal, account-deletion explanation, saved Insight
bookmark removal, and group-message removal copy. This track intentionally
does not change Firestore schemas, timestamp/model contracts, backend retention
durations, or physical deletion jobs.

## Confirmed source mismatch

The Insight owner action called `InsightService.deleteInsight`, which updates
the document to `status: deleted` and waits for server acknowledgement. It does
not physically erase the document in that request. The previous dialog said
“This will permanently delete this reflection,” and the success snackbar said
“Reflection deleted.” That wording concealed the deletion status/tombstone and
retention boundary. Saved Insight records are separate bookmarks and are
invalidated when their source is no longer active; they are not the same
operation as deleting the source reflection.

The account deletion callable is a durable multi-phase job. It disables the
account first, tombstones authored group messages as `deleted_account`, removes
or anonymizes other records by phase, and only then finalizes identity. The
settings subtitle “Permanent and irreversible” did not explain that a job and
retained safety records can exist during and after processing.

Group-message “Delete for everyone” also writes a tombstone (`isDeleted: true`,
empty `parts`, and `deletedAt`) rather than deleting the message document. The
rendered row previously said only “This message was deleted,” which did not
distinguish audience removal from physical erasure.

## Source correction

- Added `lib/services/deletion_semantics.dart` as the single source for the
  destructive-action copy.
- Insight removal now says it stops sharing, identifies the deletion status and
  retention boundary, and says saved bookmarks become unavailable.
- Account deletion copy now says the account is disabled first, messages may
  remain as a deleted-account tombstone, safety records may be retained, and
  final physical deletion follows the applicable retention policy.
- The group-message action is labelled “Remove for everyone”; the tombstone
  row says the message was removed for everyone and that safety metadata may be
  retained.
- Saved Insight’s local operation is labelled “Remove bookmark” instead of
  “Delete,” making it clear that it removes the user’s private bookmark rather
  than deleting the source reflection.

## Regression protection

- `test/insight_reliability_test.dart` continues to prove that deletion success
  is shown only after persistence, and now checks the truthful status/tombstone
  explanation in the confirmation dialog.
- `test/deletion_semantics_test.dart` checks the shared copy for the account,
  message, source-reflection, and bookmark distinctions.

## Verification

Using the repository-pinned Flutter toolchain:

```text
.tooling/flutter/bin/dart.bat format lib/services/deletion_semantics.dart lib/screens/my_insights_screen.dart lib/screens/settings_screen.dart lib/screens/study_room_screen.dart lib/widgets/saved_insight_card.dart test/insight_reliability_test.dart test/deletion_semantics_test.dart
.tooling/flutter/bin/flutter.bat test test/insight_reliability_test.dart --reporter compact
```

Results for this track:

- Insight reliability focused suite: **13 passed**;
- formatting: **pass** (the seven source/test files in this track were clean
  after formatting);
- copy-contract suite: **2 passed**;
- combined deletion/Insight focused run: **15 passed**.
- the new copy-contract suite should be run with the parent wave’s combined
  focused command before integration.

## Remaining gates

This is a source-copy correction, not proof of physical erasure. The team still
needs an owner-approved retention duration and legal/privacy wording, deployed
callable/Rules parity, and device or emulator evidence for source reflection
removal, account-job progress/failure, saved-bookmark invalidation, and
message tombstones. No commit or push was made by this track.
