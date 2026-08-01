# Wave 19B offline/media source-closure handoff

**Branch:** `codex/bsgc-full-remediation`
**Starting source checkpoint:** `11be6f7` (`Close Wave 18 media cleanup and mute acknowledgement gaps`)
**Track:** account-scoped voice-cache clear barrier
**Commit/push:** this track was not committed or pushed; the parent Wave 19 review owns the combined commit.

## Scope

This track re-checked the remaining offline/media items in the post-remediation
audit, with emphasis on account-scoped cache cleanup. It does not repeat the
Wave 18 profile-photo or study-cover reference cleanup, and it does not claim
to close device-only codec, process-death, or native Firestore-cache gates.

## Finding and race window

`VoiceCacheService` already used an account generation to invalidate an
in-flight download when sign-out starts. The generation was checked before the
final file rename, but `clearAllForUser` deleted the account directory without
serializing final rename/metadata writes, cache-hit metadata refresh, or
pruning. A sign-out could therefore race
the following sequence:

1. a download finishes and passes the generation check;
2. the cache renames the temporary media file and starts writing metadata;
3. sign-out deletes the account cache directory; and
4. the metadata write recreates the directory after cleanup, leaving media
   state under the signed-out account (and potentially returning a successful
   entry to an ended session).

This is a source-confirmed local-filesystem race, not a claim about Firebase
Storage or the platform's process-death behavior.

## Source change

`lib/services/voice_cache_service.dart` now has a small per-account async file
barrier around the final media rename/metadata commit, cache-hit metadata
refresh, and bounded pruning. The barrier is keyed by account ID, so work for
unrelated accounts does not block and a clear does not wait for a network
transfer that has not reached finalization.

- `clearAllForUser` increments the account generation before waiting for the
  account's short commit section, then deletes the root while holding the same
  barrier.
- If the clear wins before finalization, the generation check aborts the
  commit and the temporary file is removed.
- If finalization already owns the barrier, cleanup waits for the complete
  rename/metadata write and removes the committed result immediately after.
- A second generation check after the barrier prevents a session that has
  already ended from receiving a successful cache entry.
- The optional write-stage hook is a deterministic test seam only; normal
  production construction leaves it unset.

The normal data path is therefore:

`VoiceMessageBubble`/`BraidMedia` → `VoiceCacheService.prepare(accountId, sourceUrl)` →
account-root temporary download → per-account finalization barrier → media and
metadata → bounded prune → cached playback/rendering.

## Regression test

`test/voice_cache_service_test.dart` adds **“clear waits for final cache commit
and removes its result”**. The test pauses immediately after the media rename,
starts sign-out cleanup, proves cleanup cannot complete while the account
commit barrier is held, then releases the commit and verifies:

- preparation is rejected as an ended/unauthorized session;
- cleanup completes after the finalization section; and
- the signed-out account directory does not remain on disk.

Focused command (pinned toolchain):

```text
.tooling/flutter/bin/flutter.bat test test/voice_cache_service_test.dart --reporter compact
```

Result: **10 tests passed**. Pinned Dart formatting and `git diff --check`
were also clean for this track.

## Boundaries still requiring later proof

- Android/physical-device process death during the voice move-to-draft boundary
  (`REL-023`) remains open; this change only covers cache finalization during an
  account clear.
- Firebase Storage codec support, authenticated download behavior, offline
  radio transitions, and cache eviction under real device pressure remain
  device/integration gates.
- Firestore native persistence isolation across account switches remains an
  external device/emulator gate; this local voice-cache barrier does not purge
  or redesign that SDK cache.
- The message outbox's own process/recovery and account cleanup paths were not
  changed in this bounded track.
