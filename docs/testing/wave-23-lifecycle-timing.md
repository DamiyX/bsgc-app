# Remediation Wave 4 — lifecycle timing boundary

**Track:** B — scheduled/completed study write safety
**Finding:** REL-025
**Historical repository label:** continuation Wave 23
**Status:** source correction and automated verification completed locally; scheduler cadence and device acceptance remain external gates.

## Defect confirmed

Group lifecycle state is advanced by the `advanceGroupLifecycle` scheduled
function every 60 minutes. The Study Room disables its composer from the
persisted `lifecycle`, but direct member progress writes are allowed by
Firestore Rules whenever the member changes only their own state. A group with
an `active` lifecycle could therefore remain writable after `endDate` until
the next scheduler run. The same stale-state window existed at the callable
message boundary because `sendGroupMessage` and `editGroupMessage` checked
`lifecycle == "active"` without checking the date window.

## Bounded correction

- Added `isGroupEffectivelyActive` in `functions/lib/lifecycle_policy.js`.
  It requires `lifecycle == "active"`, rejects a future `startDate`, and
  rejects an `endDate` at or before the request instant. Missing dates remain
  compatible with legacy active documents.
- Applied that policy to `sendGroupMessage` and `editGroupMessage`, so a stale
  active document cannot accept new or edited messages after its configured
  end.
- Added the equivalent date guard to `firestore.rules` for member-owned
  `readingProgress`, `userCompletedChapters`, and `unreadCounts` updates.
  Scheduled and completed groups remain read-only even when a client has an
  old document snapshot.
- Present-but-malformed `startDate` and `endDate` values now fail closed in
  the callable policy instead of being silently treated as missing legacy
  dates.
- `advanceGroupLifecycle` and `cleanupExpiredData` declare an explicit
  540-second Cloud Functions timeout, covering their bounded sequential drain
  budgets and making the operational contract visible in source and tests.

No scheduler cadence, date storage format, group query, identity/timestamp
contract, or UI layout was changed in this track. The existing Study Room copy
continues to disclose that activation/completion refresh can take about an
hour; that copy is now backed by a server/rules safety boundary rather than
being the only protection.

## Verification

The four-test/82-test values in the original block below are the initial
Wave 4 checkpoint before the final verification correction. The superseding
integrated result is recorded after that block.

- `node --check index.js` — pass.
- `node --test test/functions/lifecycle_policy.test.js` — 4 passed.
- `npm test -- --test-concurrency=1` — 82 passed.
- `npm run test:rules` — 32 passed across 8 suites. This requires the Firebase
  Firestore/Storage emulators and is not a substitute for a deployed staging
  check.

## Final verification correction

The completion audit added two lifecycle-safety checks: malformed present
`startDate`/`endDate` values fail closed, and the scheduled handlers declare a
540-second timeout that covers their bounded drain budgets. The integrated
correction result is **6 lifecycle-policy tests**, **87 Functions tests**, and
**32 Rules Emulator tests**. It also adds a bounded Storage-finalize cleanup
for invalid canonical message objects. That cleanup does not replace a full
reservation-before-upload protocol; the larger cross-layer design remains a
follow-up if pre-upload reservation is required.

## Remaining evidence

The source correction cannot prove Cloud Scheduler delivery latency. Before
release, measure the 60-minute job's real delay and backlog under representative
load, deploy Functions and Rules together, and walk scheduled → active →
completed → archived on a physical/emulated device. Until then, a room may
remain visually read-only or show the approximate timing copy while the
scheduler catches up, but stale timestamps can no longer authorize the covered
writes.
