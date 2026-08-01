# Milestone 12 final regression audit

**Project:** Braid (`DamiyX/bsgc-app`)
**Branch:** `codex/bsgc-full-remediation`
**Review date:** 2026-08-01
**Integrated checkpoint reviewed:** `bcb047c` (Wave 11 release configuration)
**Disposition:** source remediation is substantially implemented, but the branch
is not release-ready. Keep it in development/internal preview until the gates
in Section 8 are evidenced.

## 1. Authority and scope

This is the Milestone 12 verification requested by
`docs/post-remediation-audit/05-prioritized-implementation-plan.md`. The
review used the following documents as the current source of truth, in this
order:

1. `00-audit-scope-and-executive-summary.md` — scope and severity model;
2. `01-functional-reliability-and-offline.md` — REL findings;
3. `02-security-backend-migration-and-scale.md` — SEC, MIG, and SCL findings;
4. `03-ui-ux-accessibility-and-product.md` — UX, A11Y, and UXE findings;
5. `04-app-size-performance-release-and-quality.md` — SIZE, PERF, BUILD, and
   RELENG findings;
6. `05-prioritized-implementation-plan.md` — milestone ownership, acceptance,
   and the release decision rule.

Earlier audit drafts and the original prompt are historical context. If a
historical document conflicts with the five files above or with the running
source, this report records the conflict instead of treating the older claim
as proof.

Milestone 12 is verification, not a new feature wave. A source change is
marked **implemented** only when the relevant code path exists. It is marked
**accepted** only when the plan's required automated, emulator/device,
production, or product evidence also exists. Those are intentionally separate
states.

## 2. Checkpoint and changes in this audit

The last clean integrated checkpoint was `bcb047c`. Milestone 12 also found
and corrected source/documentation drift:

- `lib/screens/legal_screen.dart` no longer says that private Firestore data is
  never persisted. `lib/main.dart` enables Firestore SDK persistence for warm
  offline study data, so the legal copy now says that plainly and explains the
  current sign-out cleanup boundary.
- `docs/testing/offline-capability-matrix.md` now contains an explicit M12
  correction: any earlier sentence saying Firestore persistence is disabled or
  cleared is superseded by the running source. Account-switch isolation and a
  complete SDK-cache purge remain device gates.
- `docs/testing/branch-preview-guide.md` now reflects the current 80 Flutter,
  70 Functions, and 31 Rules test counts rather than the obsolete 4/21/26
  counts.
- `docs/post-remediation-audit/05-prioritized-implementation-plan.md` now
  points to this report and records the M12 release-gate disposition.
- `functions/package-lock.json` was refreshed with
  `npm audit fix --package-lock-only`; no force upgrade or package.json
  dependency change was used.

No production deployment, migration apply, default-branch merge, asset
deletion, or GitHub push was performed during this audit.

## 3. Automated evidence

| Check | Result | What it proves | What it does not prove |
| --- | --- | --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | Pass; 85 files checked | Formatting is stable | Visual layout or runtime behavior |
| `flutter analyze` | Pass; no issues | Static Dart/analyzer checks | Android packaging or backend integration |
| `flutter test` | Pass; 80 tests | Current unit/widget seams and failure contracts | Real Firestore latency, process death, radio transitions, or device accessibility |
| `npm run check` in `functions` | Pass | Functions JavaScript syntax/check contract | Deployed Functions configuration |
| `npm test -- --test-concurrency=1` in `functions` | Pass; 70 tests | Callable, migration, scheduler, moderation, and lifecycle seams | Production data, IAM, load, and network behavior |
| `npm run test:rules` in `functions` | Pass; 31 tests | Firestore/Storage Rules Emulator permissions and negative cases | A production project or real client session |
| `npm ci` in `functions` | Pass | Lockfile is installable | Node 22 CI parity (local run used Node 24.15.0) |
| `npm audit --omit=dev --audit-level=high` | Exit 0; 9 moderate nested `uuid` advisories remain | No high-severity production advisory in the refreshed lockfile | Removal of the moderate Google-client transitive chain without a breaking downgrade |
| `npm run migrate:v2:rehearse -- --report build/migration-v2-wave12.json --run-id wave12-rehearsal-updated` | Pass | Interruption/resume and exact-seed rollback rehearsal | A production backup, real legacy dataset, or applied migration |
| Scheduled-job coverage | Pass; 1,200 lifecycle writes split `450/450/300`; 800-item deletion path split `450/350` | No single test path assumes a Firestore batch above the safe cap | Production backlog drain rate or timeout behavior |
| `git diff --check` and JSON parsing | Pass | No whitespace errors; Firebase/Hosting configuration parses | Hosted behavior |
| Android local debug compile | Inconclusive; bounded 120-second and 300-second arm64 attempts produced no APK and Gradle was stopped | The local laptop was not left running an unbounded build | It does not establish a compiler failure or a successful build |
| Quality CI Android smoke | Pending | Authoritative CI compile evidence | Not available from this local checkout |
| Protected signed AAB and `--analyze-size` evidence | Pending | Release artifact, checksums, mapping/symbols, and controlled size baseline | Not reproducible until the owner configures secrets/environment |

At final commit preparation, the current PowerShell session did not have
`dart` or `flutter` on `PATH`, so a second Flutter run was not fabricated. The
80-test/analyzer/format pass above is the recorded integrated verification from
the Wave 11/M12 preflight; the friend or CI runner must rerun it from a
Flutter-equipped checkout before release.

The independent read-only cross-check agreed with these results and specifically
flagged the Firestore persistence contract, source-only test seams, stale guide
counts, and all owner-controlled release gates. It did not modify code, commit,
push, or run a heavy build.

## 4. Finding ledger: functional reliability and offline (REL)

| ID | Current disposition | Evidence boundary / next proof |
| --- | --- | --- |
| REL-001 | Implemented visibility/hide/clear contract with rollback | Seeded room emulator plus offline/restart/member-isolation test still required |
| REL-002 | Implemented independent bounded space pagers and index declaration | 100/45/35 seeded-space and process-restart acceptance still required |
| REL-003 | Implemented selected My Insights route | Real Firestore route and deleted/no-access item test still required |
| REL-004 | Implemented `insight_state` unread source | Cross-device unread/first-unseen behavior still requires emulator/device evidence |
| REL-005 | Implemented honest expiring-bookmark behavior and stale-pointer cleanup | Product confirmation that expiry/save wording is acceptable remains open |
| REL-006 | Implemented validation, awaited persistence, duplicate-submit guard, and failed-draft retention | Existing widget tests pass; real offline/network failure still requires device proof |
| REL-007 | Implemented reversible optimistic actions | Backend-rule and reconnect race tests remain acceptance work |
| REL-008 | Implemented cursor-based comment pagination | Long-comment dataset and restart verification remain open |
| REL-009 | Implemented open-room unread handling | Multi-device read/unread behavior remains unproven |
| REL-010 | Implemented target-preserving notification navigation | Foreground/background/terminated device matrix remains open |
| REL-011 | Implemented terminal invalid-invite clearing and retryable states | Signed-out/offline/expired invite matrix remains open |
| REL-012 | Implemented OS-permission-aware notification state | Deny/re-enable settings flow requires a device |
| REL-013 | Implemented durable outbox replacement/recovery boundaries | Kill/relaunch and filesystem interruption test remains open |
| REL-014 | Implemented account-scoped reply-draft loading boundary | Slow-network reply race still needs integration/device proof |
| REL-015 | Implemented account-scoped voice cache with explicit download/retry | Codec, relaunch, airplane-mode, and cache eviction checks remain open |
| REL-016 | Implemented serialized chapter-progress writes | Rapid-update and reconnect acceptance remains open |
| REL-017 | Implemented canonical current-user identity path | Multi-account restart test remains open |
| REL-018 | Implemented partial profile loading and section-level retry | Offline visual review remains open |
| REL-019 | Implemented immediate shell/lazy Bible loading boundary | Startup timing and memory trace on target Android devices remain open |
| REL-020 | Implemented a new recovery action for group-list retry | Device retry/empty/error visual check remains open |
| REL-021 | Implemented edit/delete-aware last-message summaries | Long-room and concurrent edit/delete test remains open |
| REL-022 | Implemented durable private/contact composer drafts | Account-switch and process-death matrix remains open |
| REL-023 | Implemented audio-preparation failure recovery and retry | Device media failure cases remain open |
| REL-024 | Implemented archived-group rediscovery/read-only route | Device navigation and permissions review remains open |
| REL-025 | Timing remains deliberately approximate and is surfaced honestly | Product decision and real scheduler timing evidence remain open |
| REL-026 | Implemented normalized date contract at the source boundary | Time-zone/device picker review remains open |
| REL-027 | Implemented stable user-facing error mapping in reviewed paths | Full error-copy sweep and localization review remain open |
| REL-028 | Implemented explicit timestamp fallback/state handling | Missing-timestamp dataset and visual review remain open |
| REL-029 | Implemented outbox item/byte quota, expiry, and retry cap | Long-running device storage/eviction evidence remains open |
| REL-030 | Implemented bounded startup/auth failure states with Retry | Cold start, offline launch, and process-kill evidence remains open |

REL-001 and REL-002 are P0 findings. Their source seams and tests are not
accepted as a substitute for the seeded emulator/device scenarios required by
the plan.

## 5. Finding ledger: security, migration, and scale

| ID | Current disposition | Evidence boundary / next proof |
| --- | --- | --- |
| SEC-001 | False end-to-end-encryption claim removed; service visibility is described accurately | Legal/support approval and deployed-copy review remain open |
| SEC-002 | Managed media access and membership checks are source-controlled | Signed URL expiry/revocation and real Storage authorization test remain open |
| SEC-003 | Resumable account/group media cleanup path exists | Production orphan scan, retry, and Storage evidence remain open |
| SEC-004 | Server-authoritative display identity/rules path exists | Modified-client and deployed callable verification remain open |
| SEC-005 | Arbitrary untrusted HTTPS media is constrained in reviewed paths | Full URL ingestion audit and privacy review remain open |
| SEC-006 | Partial: Android backup/transfer is excluded and local drafts/outbox/media are cleared; Firestore SDK persistence remains enabled | Account-switch isolation and complete-cache behavior are not proven; this is a P1 release gate |
| SEC-007 | Open: no `firebase_app_check` client dependency/provider is configured | Owner must select provider, configure debug/staging/production, and exercise enforcement |
| SEC-008 | Source-level quotas/abuse controls and moderation seams exist | Operations, monitoring, alerting, and abuse-load review remain open |
| SEC-009 | Block-aware invite checks exist in source/rules | Signed-out, blocked, expired, and replayed invite tests remain open |
| SEC-010 | Multi-step resumable account-deletion job exists | Production retry, timeout, backup, and external-media verification remain open |
| SEC-011 | Deletion status/tombstone behavior is explicit in reviewed paths | “Permanent delete” product/legal confirmation and full-flow evidence remain open |
| SEC-012 | Upload/reference lifecycle has validated managed paths | Atomic failure, orphan cleanup, and production Storage verification remain open |
| MIG-001 | Large note bodies are preserved or quarantined rather than truncated | Real legacy corpus rehearsal remains open |
| MIG-002 | Group normalization path exists | Real mixed-schema dataset and dry-run report remain open |
| MIG-003 | Migration is resumable and bounded in source | Production-scale throughput, checkpoint, and operator rollback remain open |
| MIG-004 | Rollback rehearsal now restores the exact seed after interruption | Real backup restore and applied migration remain open |
| MIG-005 | Invite naming/schema compatibility is documented in source paths | Deployed collection inventory and legacy-data verification remain open |
| SCL-001 | Scheduler writes are chunked below the Firestore batch limit | Production backlog and retry metrics remain open |
| SCL-002 | Cleanup paths have bounded batches and continuation behavior | Multi-day backlog-drain rehearsal remains open |
| SCL-003 | Account deletion scans are bounded/resumable rather than one unbounded callable | Production dataset and timeout evidence remain open |
| SCL-004 | Core lists use bounded first pages/cursors | Device read counts and long-dataset traces remain open |
| SCL-005 | Feed/saved snapshots remove the normal N+1 dependency; legacy pointers use a compatibility path | Legacy backfill and million-user fanout/read measurement remain open |
| SCL-006 | Moderation records and basic actions exist | There is not yet evidence of a complete moderation operating system, staffing, alerts, or retention policy |
| SCL-007 | Repeated rule lookup paths are reduced/cached in reviewed code | Production cost trace and rule-change invalidation evidence remain open |

## 6. Finding ledger: product UX, accessibility, and architecture

| ID | Current disposition | Evidence boundary / next proof |
| --- | --- | --- |
| UX-001 | Bounded one-thought/audience adapter exists | Product walkthrough must confirm it feels unified |
| UX-002 | Copy is honest about “Continue a study”; schedule-aware next-study logic is not claimed | Product decision and schedule data design remain open |
| UX-003 | Journal-to-reflection bridge exists without mutating the private note | Product/device walkthrough remains open |
| UX-004 | Archived studies have a separate entry route | Visual and permission review remains open |
| UX-005 | Duplicate profile shortcuts remain a navigation review item | Simplification decision remains open |
| UX-006 | Calm labeled reflection cards replace urgency/social-story treatment | Brand/product walkthrough remains open |
| UX-007 | Reflections, Discussion, and Prayer have distinct bounded spaces | Real group study usability remains open |
| UX-008 | Reflection is the default group entry in the bounded slice | Product walkthrough remains open |
| UX-009 | A true server-backed undo-delete guarantee is not evidenced | Keep as open until the product chooses reversible delete semantics |
| UX-010 | Reviewed note paths await persistence; a full success-copy sweep is not evidenced | Audit every mutation and device-failure state |
| UX-011 | Unsupported security/product promises were removed in reviewed copy | Final legal/product copy approval remains open |
| UX-012 | “Reflection” terminology and shared tokens are applied in the bounded slice | Full copy sweep/localization remains open |
| UX-013 | Open P0: Legal screen still identifies itself as a repository draft and requires verified operator/contact details | Owner must supply legal/support/retention content before external beta |
| UX-014 | Shared spacing/radius/motion/color token slice exists | Full design-system coverage and component migration remain open |
| UX-015 | Open: production brand/logo approval is not recorded; draft assets remain intentionally | Owner approval and final asset manifest remain open |
| UX-016 | Core surfaces use semantic light/dark tokens in the bounded slice | Hard-coded colors remain in several screens; dark/contrast device sweep is open |
| A11Y-001 | Semantic labels, toggled states, and target-size improvements exist | TalkBack/VoiceOver device proof remains open |
| A11Y-002 | Bounded 2x text scaling and expansion affordances exist | 200% text on target devices remains open |
| A11Y-003 | Reduced-motion handling is wired in reviewed viewer/journal paths | System reduced-motion device review remains open |
| A11Y-004 | Voice/status/download states expose semantics/live regions | Screen-reader workflow remains open |
| A11Y-005 | Scripture focus and core surfaces use semantic theme colors | Contrast measurement on device remains open |
| A11Y-006 | Author-written voice summaries are persisted/displayed; automatic transcription remains out of MVP | Product decision on transcription remains open |
| A11Y-007 | Scripture recognizers are owned and disposed; tests cover the seam | Long-session leak/performance check remains open |
| UXE-001 | Some high-risk components were isolated | Full controller extraction of the largest screens remains deferred |
| UXE-002 | Recognizer disposal was implemented | Device memory trace remains open |
| UXE-003 | Test surface expanded to 80 Flutter tests | Full journey/integration/device coverage remains open |

## 7. Finding ledger: size, performance, build, and release engineering

| ID | Current disposition | Evidence boundary / next proof |
| --- | --- | --- |
| SIZE-001 | Release workflow now records artifact/toolchain/checksum context | A signed AAB and same-artifact baseline are still missing |
| SIZE-002 | Asset manifest records duplicated splash inputs without destructive cleanup | Measure release output before removing any asset |
| SIZE-003 | Draft brand assets are separated/documented rather than silently deleted | Brand approval and approved cleanup remain open |
| SIZE-004 | Bundled Bible payloads are preserved; Bible parsing is lazy | Device memory/startup and size trace remain open |
| PERF-001 | Startup shell and lazy loading were implemented | Device time-to-first-content/memory evidence remains open |
| PERF-002 | Bounded list components reduce some god-screen risk | Full controller extraction remains deferred |
| PERF-003 | Feed snapshots remove normal pointer hydration N+1 reads | Legacy backfill and production measurement remain open |
| PERF-004 | Voice cache has bounded account-scoped path and retry UI | Device codec/offline/cache-byte trace remains open |
| PERF-005 | Outbox has item/byte/expiry/retry limits | Long-running device storage trace remains open |
| PERF-006 | Major lists are paged/cursor-bounded | Read-count and long-dataset traces remain open |
| BUILD-001 | Release compilation is isolated to protected CI workflow; local attempts were bounded | CI run is required |
| BUILD-002 | Preview/release docs state Flutter/Java prerequisites; local PATH is environment-dependent | Friend’s machine must run `flutter doctor -v` |
| BUILD-003 | No completed release artifact exists in this checkout | Signed AAB gate is open |
| RELENG-001 | Quality workflow now includes pinned Flutter and arm64 Android smoke | GitHub run on this branch is required |
| RELENG-002 | Hosting no longer ignores `.well-known`; the checked-in asset links still contain a production placeholder fingerprint | Real Play App Signing SHA, HTTPS deploy, and Play-installed invite test are required |
| RELENG-003 | Protected workflow and evidence bundle procedure exist | Actual AAB/APK, mapping, symbols, checksums, and size JSON are required |
| RELENG-004 | App Check remains intentionally unconfigured | Owner approval/provider/debug-staging-production rollout is required |

## 8. Product questions from the original audit

### Is this clearly a Bible study/reflection product rather than a chat clone?

The source structure now centers Today, Groups, Journal, Reflections,
Discussion, Prayer, Scripture, and audience choice. The bounded UX slice moves
the product in the intended direction. A human walkthrough is still required
to confirm that the visual hierarchy and copy feel like study rather than a
generic social feed.

### Can a user capture privately before deciding to share?

Account-scoped composer drafts and the private-to-audience reflection adapter
exist. Persistence, offline retry, and the distinction between a private draft
and a published reflection are covered by source tests, but the complete
offline/kill/relaunch flow remains a device gate.

### Does the group experience help a real study progress?

Distinct Reflection, Discussion, and Prayer spaces, study lifecycle states,
progress, recap, and bounded history exist in source. The product question is
not accepted until a reviewer walks through a real group with long history,
offline recovery, member roles, and archived/completed states.

### Are privacy, expiry, save, and delete behaviors obvious and true?

The false encryption claim and the false “Firestore is never persisted” claim
were corrected. Draft/outbox/media cleanup and server deletion jobs are
account-scoped or resumable in source. Firestore cache isolation, Storage URL
revocation/orphan cleanup, production deletion, legal retention, and the
repository-draft legal/support content remain open. The branch must not make a
stronger privacy or permanent-delete promise than those facts support.

### Does the experience feel calm and return-worthy?

The bounded cards, copy, spacing, motion, and reduced-social-urgency changes
support that intent. This is a human product judgment; screenshots and device
review are still required.

### Do Today, Groups, Journal, and Me each have one clear job?

The navigation and source responsibilities are clearer, but UX-005 duplicate
shortcuts, UX-002 schedule semantics, and the unresolved design-system/brand
review mean this is not yet a signed-off product decision.

## 9. Remaining release gates and owners

1. **Android build:** run the quality workflow on this exact branch and record
   the debug compile result.
2. **Signed release:** configure the protected `android-release` environment
   and secrets, produce the signed AAB/arm64 APK, checksums, mapping/symbols,
   and Flutter size JSON.
3. **Play/App Links:** replace the placeholder fingerprint, deploy the real
   `.well-known` files, verify HTTPS and the Play-installed invite flow.
4. **Device matrix:** low/mid Android, current/oldest supported OS, fresh and
   upgrade install, online/airplane mode, process death, drafts/outbox/media,
   notifications, invites, permission deny/re-enable, TalkBack, 200% text,
   light/dark/reduced motion, account switch/deletion, and long datasets.
5. **Firestore privacy:** specifically test whether data from account A can be
   observed by account B after sign-out, relaunch, and offline startup. If any
   cross-account cached content appears, stop release work and redesign cache
   lifecycle before beta.
6. **App Check:** choose the official Flutter provider, configure debug,
   staging, and production, then verify legitimate clients before enforcement.
7. **Migration/backup:** run a non-production backup, mixed-schema rehearsal,
   interruption/resume, rollback, and scheduled-job backlog drain with an
   operator runbook.
8. **Scale/operations:** measure reads/open, first useful frame, room frame
   time, memory, cache bytes, fanout/backfill behavior, moderation alerts, and
   deletion backlog on representative data.
9. **Legal/product/brand:** replace repository-draft copy, approve operator and
   support contacts, retention/deletion language, production logo/assets, and
   store disclosures.
10. **Release decision:** attach the evidence bundle and choose development,
    internal testing, closed beta, merge/default, or production. Do not infer
    this decision from source tests alone.

## 10. Final disposition

Milestone 12 is aligned with the newly written post-remediation audit set and
the implementation plan. The work completed in Waves 1–11 maps to the planned
finding families, and this report explicitly carries every finding ID back into
its acceptance boundary. The branch is materially safer and more coherent than
the original checkpoint, including the reported offline image/icon fallback
paths, but “source tests pass” is not the same as “the app is release-ready.”

The correct current state is **internal preview/development only**. Commit this
report and its evidence updates locally, then let the friend/device reviewer
run the preview guide and return screenshots, logs, exact device/OS, and the
gates above. Only after those results are reviewed should the branch be
considered for merge or release.

## Continuation verification — Wave 14 source closure

Wave 14 re-opened only the source-controlled gaps identified by this report;
the complete handoff is `docs/testing/wave-14-source-closure.md`. This is a
continuation of the Milestone 12 baseline, not a claim that the external gates
above were completed.

- `SEC-007` and `RELENG-004`: the official FlutterFire
  `firebase_app_check` dependency and activation adapter are now present.
  `BRAID_ENV=local` uses debug providers; staging and production select Play
  Integrity on Android and App Attest with DeviceCheck fallback on Apple. The
  startup gate activates App Check after `Firebase.initializeApp()` and before
  other Firebase service use. Quality and release workflows pass explicit
  environment defines. Functions enforcement remains disabled pending owner,
  Firebase-console, signed-client, metrics, and rollback evidence.
- `UX-005`: the duplicate Me-tab app-bar Settings action is removed. Settings
  remains a single destination in the Me list. Profile/Journal information
  architecture is intentionally unchanged pending a product walkthrough.
- `UX-010`: profile photo and details writes now wait for Firestore's pending
  write metadata to clear before confirmed success. A bounded timeout shows
  queued-local/reconnect/retry copy and does not dismiss the editor. The full
  mutation inventory and device behavior remain follow-up gates.

The pinned Flutter verification after integration is recorded in the Wave 14
handoff and workflow state. It remains source evidence only: the branch is
still **internal preview/development only**, and device, native Firestore cache
isolation, Firebase App Check registration/enforcement, signed artifacts,
production operations, legal approval, and release decision remain open.

## Continuation verification — Wave 16 source closure

Wave 16 continued the UX-010 audit with two focused source tracks:

- Reflection deletion now waits for Firestore's server acknowledgement before
  `MyInsightsScreen` shows confirmed deletion. The previous replacement-record
  “UNDO” behavior remains absent, and a widget test proves success is withheld
  while persistence is pending.
- Draft, outbox, and sound-preference failures now have bounded local cleanup
  handling: draft discard preserves text, outbox cleanup reports a retryable
  failure, queued outbox data remains authoritative when draft cleanup fails,
  and a failed sound-preference write rolls back the toggle.

The Wave 16 handoff records clean analysis, 26 focused tests, and 93 full
Flutter tests. This remains source evidence only; the mutation device matrix,
native Firestore cache isolation, App Check project/enforcement, signed
artifacts, operations, legal, and product gates remain open.

## Continuation verification — Wave 15 source closure

Wave 15 checked the next source-adjacent items without reopening the accepted
boundaries or treating device evidence as implied:

- `REL-027` and the scoped `UX-010` paths now map account-deletion and
  group-invite failures from typed backend codes to stable actionable copy.
  Raw exception/plugin messages are not rendered; debug diagnostics omit the
  raw message. Profile-edit commit acknowledgement from Wave 14 remains in
  force.
- `REL-026` is improved for those callable paths because their server codes are
  mapped instead of displayed. The broader date-picker/time-zone contract is
  still a separate review item.
- `REL-020` was re-verified rather than changed: the earlier Wave 2
  `GroupStreamRetryController` creates a fresh stream and the existing test
  proves the stream identity changes. Its device visual/error acceptance gate
  remains open.

The Wave 15 handoff records clean analysis, 20 focused tests, and 90 full
Flutter tests. The branch remains **internal preview/development only**; the
full mutation inventory, device/offline matrix, native Firestore cache
isolation, App Check project/enforcement, signed artifacts, operations, and
legal/product approval remain open.
