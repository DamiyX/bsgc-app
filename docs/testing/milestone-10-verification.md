# Milestone 10 verification — bounded history and feed latency

## Scope

This wave makes the primary history surfaces bounded and cursor-based and
removes the normal active-feed N+1 hydration pattern.

- Active/scheduled Groups load in a 50-item cursor page and offer explicit
  older-page loading. Archived studies use a separate 50-item cursor page and
  read-only route.
- Journal notes load in bounded cursor pages with refresh, retry, and older
  history actions. Search operates on loaded pages rather than silently
  downloading an unbounded account history.
- Saved reflections use bounded cursor pages and server-created display
  snapshots. Expired/unavailable bookmarks are removed as before.
- New `insight_feed` pointers contain an allowlisted server-created snapshot of
  the reflection fields needed by the client. Active feed opens therefore do
  not perform one `insights/{id}` read per pointer. Legacy pointers still use a
  compatibility read until backfill.
- Firestore indexes declare the lifecycle/order combinations used by the
  bounded Group queries.
- Existing account-scoped voice-cache and outbox byte/item/expiry controls are
  retained as the media/storage budget boundary.

## Verification performed

- Dart formatting on changed Dart files: pass.
- `flutter analyze`: no issues.
- Full Flutter test suite: 80 passed.
- Functions `node --check index.js`: pass.
- Functions test suite: 70 passed.
- Firestore/Storage Rules Emulator: 31 passed.
- `firestore.indexes.json` parse and Git whitespace validation: pass.

## Manual and production-scale checks still required

1. Measure time to first useful frame, reads per Groups/Journal/Saved/Feed
   open, page completion time, cache hits, room scroll frame time, peak memory,
   and total outbox/media-cache bytes on representative low/mid-range devices.
2. Compare snapshot fanout bytes/writes against a measured fanout-on-read model
   before increasing the audience cap or targeting million-user scale.
3. Run a controlled migration/backfill for legacy feed and bookmark pointers;
   verify idempotence, authorization, expiry, and no private-content leakage.
4. Test long histories (one month, one year, several years), offline refresh,
   cursor retry, account switching, and deletion while a page is loading.
5. Profile Study Room, View Insight, and Main Hall rebuild counts and frame
   timing before extracting additional controllers/components.

The source changes do not claim a device performance budget has passed; those
measurements remain a release decision gate.
