# Wave 18A security/media handoff

**Scope:** SEC-003 / SEC-012 source-controlled profile-photo and study-cover
upload lifecycle

**Review date:** 2026-08-01

**Status:** local source fix and focused Flutter tests pass; Firebase Storage,
callable deployment, scheduled reconciliation, and device evidence remain open

## Gap closed in source

Profile-photo and study-cover flows upload a new managed Storage object before
writing the owning Firestore reference. A deterministic reference-write failure
previously left the new object and its pending `managed_assets` record for the
next scheduled orphan sweep. The failure path now uses
`StorageService.commitReferenceOrCleanup`:

- a successful reference write performs no cleanup;
- a definitive permission/validation failure best-effort deletes the newly
  uploaded object;
- ambiguous network/timeout/internal failures do not delete, because the
  remote write may already have committed; the pending managed asset remains
  available to the server reconciler;
- deletion accepts only canonical account-scoped profile paths or the current
  owner’s canonical group-cover path, and treats an already-missing object as
  idempotently deleted.

The Firestore `managed_assets` document remains server-owned. If client-side
Storage deletion fails, the pending record is intentionally retained for the
existing scheduled cleanup path.

## Changed source

- `lib/services/storage_service.dart`
  - added the commit/cleanup boundary, definitive-vs-ambiguous failure policy,
    and canonical path-guarded object deletion;
- `lib/screens/edit_profile_screen.dart`
  - profile reference writes use the boundary;
- `lib/screens/group_details_screen.dart`
  - group-cover callable writes use the boundary;
- `test/managed_media_cleanup_test.dart`
  - covers success, deterministic failure/rethrow, ambiguous failure deferral,
    failure-code policy, and cross-scope/path traversal rejection.

## Verification

Run with the repository-pinned Flutter toolchain:

```text
.tooling/flutter/bin/flutter.bat test test/managed_media_cleanup_test.dart test/media_reference_policy_test.dart test/message_media_policy_test.dart
```

Result: 9 focused tests passed.

`flutter analyze` was started against the same checkout; its final result is
recorded by the parent wave review because another Wave 18 source track was
editing shared UI files concurrently.

## Remaining boundary

This is not proof that a deployed Storage object is revoked, that Cloud
Functions and the client are deployed in lockstep, or that the scheduled
reconciler drains production backlog. A lost response after a committed
callable/write intentionally defers to server reconciliation. Physical-device
offline/process-death and real Firebase Storage tests remain required.
