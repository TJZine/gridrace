Status: Active
Scope: GridRace Phase 2 backend foundation and Phase 3 two-player live slice
Owner: Primary orchestrator
Started: 2026-08-30
Last updated: 2026-09-22

# Phase 2 and Phase 3 Live Slice Plan

## Goal and current checkpoint

Prove the first authoritative Blind Race: two authenticated players, one five-letter
round, creator start, server-owned guesses and time, clue-free progress, recovery,
and shared reveal. Daily Classic stays immediately playable offline and signed out;
its imported personal history never becomes verified competitive evidence.

This plan remains the sole active plan. The 2026-09-22 task is **planning only**:
brainstorming, accepted direction, documentation revision, independent adversarial
review, and documentation checkpoints. It does not implement P2 or P3 product code,
run destructive resets, deploy, purchase services, or close this ongoing live plan.

### Repository evidence

- Branch `dev/classic-mode`; reactivation checkpoints `0162081` and `764b9e1`.
- Six migrations, six authenticated Edge handlers, pinned CLI `2.116.0` and Swift
  SDK `2.55.1` exist. Recorded reactivation proof: deterministic 100-answer seed,
  clean reset, 217 pgTAP assertions, no lint errors (extra warnings recorded),
  3 shared-rule tests, and 96 Edge tests. These are prior execution results, not
  tests rerun by this planning task.
- Phase 2 includes private answers, service-only transactions, RLS, deletion,
  minute-scheduled Cron finalization, and `matches.revision` change signals.
  Database round state stays `countdown` until reveal; snapshots derive `playing`.
- iOS has Daily Classic, optional accounts, profile/deletion, account-scoped storage,
  and Daily sync. `SupabaseAccountService` owns the SDK client and already supplies
  Daily transport. Reuse its authenticated client through composition; do not create
  competing Auth sessions or put live state in `DailyAccountCoordinator`.
- No live Swift domain, command service, session model, Realtime service, or UI exists.
  Existing Edge tests inject dependencies; SQL assertions are not proof of independent
  concurrent transactions or of actual Edge gateway/Realtime delivery.
- Staging/Release configuration placeholders and CI already exist. Remote deployment,
  a passing hosted CI run, and real Apple exchange are not established by those files.
- Unrelated dictionary/attribution work includes the runbook, `DailyViews.swift`, and
  Xcode project. Preserve every pre-existing edit/untracked file. The planning task
  must not edit or stage the runbook. The iOS writer waits for the maintainer to
  checkpoint or otherwise separate overlapping work; no automatic stash/commit.

## Accepted BRAINSTORM_RESULT

- **Goal:** validate simultaneous private play and a shared social reveal before
  investing in broader match flow.
- **Constraints/non-goals:** native iPhone first; existing secrecy, RLS, server time,
  idempotency, deletion, accessibility and recovery; exactly two players/one round;
  local proof now; no paid services while validating with the owner and friends.
- **Options considered:** keep current stack; cross-platform client; custom server or
  Edge-owned gameplay; direct client gameplay RPCs; polling-only/Broadcast transport.
- **Direction:** retain SwiftUI and Supabase Auth/PostgreSQL/RLS/Edge/Realtime/Cron.
  Transactions stay with their data, Edge owns authenticated command translation,
  and one live session owns client lifecycle. Keep existing Postgres signals and add
  bounded snapshot refresh. No demonstrated benefit justifies a replacement stack.
- **Trade-offs:** SQL/RLS and multi-service testing remain real maintenance costs;
  Auth/Realtime/SDK integration creates vendor coupling; private room fan-out is
  small but throughput must be measured before expansion. No abstraction framework
  or provider-neutral facade is warranted.
- **Resolved by maintainer:** defer opponent presence labels; accept retry-safe
  creation, bounded recovery, and the proposed planning improvements; use free
  services initially and obtain explicit approval before any spend.
- **Open decisions:** none blocking local implementation planning. Distribution,
  real provider setup, hosted retention/backups, and any paid service remain later
  maintainer decisions; see operating boundary below.
- **Planning changes:** freeze pending backend corrections, split P3 by dependency,
  define transport/recovery/deletion behavior, attach evidence to each exit gate,
  and reconcile stale authorities without changing the broader beta promise.

## Scope, non-goals, and product invariants

Phase 2 finishes the local backend integration/security checkpoint, including the
bounded contract corrections below. Phase 3 connects create/join/start, countdown,
guessing, count/state progress, recovery, and reveal through independent clients.

No more players/rounds, rematches, competitive history, links, notifications,
reports/blocks, opponent presence, friends graph, public matchmaking, chat, custom
answers, rankings, generalized modes, telemetry service, or new dependency framework.
Reports/blocks and other broader MVP requirements remain mandatory before beta exit;
local slice completion is neither beta exit nor permission to distribute publicly.
No remote linking/reset/deployment, TestFlight, paid infrastructure, CI redesign,
production retention choice, or dictionary changes are part of this milestone.

- Five letters, six accepted guesses; correct sixth solves, incorrect sixth fails.
  Shared versioned Swift/TypeScript vectors and the development seed stay unchanged.
  The development pack is deliberately small and is not production dictionary proof.
- Creator starts after two seats; no readiness, cancellation, automatic next round,
  or ordinary forfeit UI. Countdown is 3 seconds, round 180 seconds. Eligibility is
  `starts_at <= transaction_timestamp() < ends_at`; equality times out. Preserve this
  accepted database-transaction-time rule, including lock-wait tests; do not substitute
  device send time or wall-clock-after-lock time silently.
- Match `lobby -> in_progress -> completed`; effective round
  `pending -> countdown -> playing -> revealed`; player
  `playing -> solved|failed|timed_out|forfeited`. Terminal states do not change.
  Disconnect, navigation away, and sign-out do not forfeit. Active account deletion
  explicitly forfeits only a still-playing player; solved/failed results remain intact.
- PostgreSQL selects nonrepeating answers and owns dictionary acceptance, feedback,
  timestamps, rankings,
  constraints, atomicity and transitions. Edge verifies identity/build/input and maps
  stable errors. Views send intents and render validated domain values only.
- Normal credentials cannot read private answers, pre-reveal opponent clue/timing
  fields, unrelated matches, or mutate authoritative state. Service credentials stay
  server-side. Membership filters alone never replace grants/RLS.
- Realtime payloads are refresh signals, not state or ordering authority. Client
  clock estimates never decide acceptance, timeout, placement, or reveal.
- Preserve in-app deletion, anonymized survivor results, Daily cache isolation,
  non-color meaning, VoiceOver, Dynamic Type, Reduce Motion, Increased Contrast,
  Bold Text, usable targets, and optional native haptics.
- No raw words, feedback, snapshots, names, join codes, tokens, request receipts,
  credentials, or raw identifiers in diagnostics. No new telemetry collection.

## Contract checkpoint and ownership

[`../live-api-contract.md`](../live-api-contract.md) is the normative wire and recovery
contract. Its **pending P2-04A** sections distinguish accepted targets from current
implementation. Freeze that checkpoint before Swift DTOs depend on it.

1. Add required `request_id` to create. An authenticated actor's identical retry,
   including concurrent/lost-response retry, returns the original match ID without
   spending another create quota or allocating another room. Receipt and room commit
   atomically. Reject conflicting reuse; never build a generalized command bus.
2. Keep snapshot v1, and fix deleted members' `is_self` to Boolean false: current SQL
   compares nullable `auth_user_id` directly and can emit null. Preserve every other
   privacy restriction. Define enum/null/timestamp/state validation against real output.
3. Preserve submit receipts and original response times. The client never uses a
   replayed guess timestamp to calibrate its clock or replaces a newer snapshot with
   an older command response. Placements come from SQL; millisecond display values
   do not recreate the database's microsecond tie-breaker.
4. Reuse the existing deletion receipt flow, which is a database-preparation/Auth
   deletion/completion sequence, not a single transaction across Auth and Postgres.
   Receipt status can precede normal authentication only on the narrow deletion route;
   it grants no account data. Prove lost responses and all partial-failure stages.
5. Audit the whole lock graph, including rate counters, new create receipts, account
   deletion and Cron. The canonical game-row order is match, round, players in seat
   order, then guesses; it is not a claim that every existing lock follows that list.
   Prove rollback and deadlock/retry behavior with independent connections.

### Client lifecycle and recovery target

- One account-bound `@MainActor` live session, one command in flight, and one
  coalesced snapshot fetch. Signals during a fetch set a trailing-refresh flag.
  Subscribe before the catch-up snapshot; refresh after subscription/reconnection.
- Generation guards discard callbacks after account/match changes even when task
  cancellation races completion. Serialize snapshot application with commands: a
  pre-command response cannot overwrite its result; refresh after accepted commands.
  Snapshot version is a schema version, not a monotonically increasing state version.
- Before network dispatch, durably save the pending create/guess identity in a small
  account-scoped recovery file. Save recovered match ID before exposing its UI.
  Relaunch retries the same operation/UUID and obtains a snapshot before enabling
  another guess. A snapshot lacks request IDs, so it cannot by itself acknowledge an
  uncertain guess. Never resend a guess under a new UUID automatically.
- Store only the latest match pointer and one pending intent, not a competitive
  history or offline guess queue. Clear resolved pending data, clear live recovery
  state on sign-out/confirmed deletion, and hide it immediately on identity change.
  Persist no bearer, accepted-board cache, answer, or opponent data. Protect pending
  words as private account data. Failure to persist blocks dispatch with safe retry.
- A foreground open lobby/countdown/round refreshes after **5 seconds without a
  successful snapshot**, even if the socket appears healthy. Coalesce with events;
  no per-frame requests. On network failure use 5/10/20/30-second capped backoff,
  reset by success. Stop this loop in background, on session exit, reveal, expired
  lobby, invalid membership, or unavailable authentication. Foreground/reconnect and
  explicit retry restart recovery. No indefinite lobby polling beyond its expiry.
- Bound each request to 10 seconds; cancellation/timeout means uncertain outcome,
  not rollback. Refresh expired Auth once for an operation, then require sign-in.
  No automatic replay of validation/conflict/permission errors. Retry create/guess
  only with their saved IDs; join with the same code; start through snapshot recovery.
- Display time from a fresh snapshot's server time plus monotonic elapsed time.
  Device clock changes do not extend the round. Network latency makes display
  approximate; at local countdown/deadline expiry fetch canonical state. At deadline
  lock input while recovering; never reveal or award a timeout locally.
- Returning Home leaves server membership intact and offers Resume for the saved
  match. One locally selected match at a time; the server may contain other lobbies.
  No list/history feature or automatic cancellation is implied. Host deletion makes
  a guest's lobby unavailable; guest deletion restores a one-seat lobby.
- Daily stays the primary home action. Live create/join uses the existing optional
  account flow; live errors do not block Daily. Reuse passive visual primitives where
  useful, never the Daily/tutorial evaluator as an authoritative live guess path.
- Opponents show avatar/name/count/coarse game state only. Show this client's own
  connecting/recovering/unavailable status; do not infer opponent connectivity from
  inactivity or from the local socket. Presence remains later.

## Work units and dependency order

All statuses below concern future implementation unless explicitly complete. The
primary controller owns shared contracts, plan, integration, index and commits.
Future filenames below are proposed write boundaries, **not existing files**.

| Unit | Owner / exclusive write boundary | Dependency | Acceptance / status |
| --- | --- | --- | --- |
| PLAN-01 | Primary; this plan, API, architecture, privacy, flow, product, decisions, NOW | Accepted brainstorming | Complete: accepted direction revised and independently reviewed; documentation proof below; no product writes |
| P2-01..03 | Historical backend owners; existing migrations, seed, handlers/tests | Original contract | Complete baseline; evidence retained below, not proof of new targets |
| P2-04A Recovery contract corrections | One backend writer; future `supabase/migrations/202609220001_live_recovery_contract.sql`, future `supabase/tests/database/live_recovery_contract.sql`, existing `supabase/functions/create-match/index.ts` and `index_test.ts`; controller owns API integration | PLAN-01 checkpoint | Pending: atomic create receipts and Boolean deleted-member identity, real-output contract fixtures, forward/reset proof; no iOS/project edits |
| P2-04B Backend security/integration checkpoint | Primary plus fresh read-only security reviewer; integrated backend, future `supabase/tests/integration/live_slice_test.ts`, and exact reproduced repair paths assigned serially | P2-04A | Pending: current RLS/grants/secret/deletion/revision/lock audit, negative and concurrent proof, accepted fixes closed |
| P3-01 Transport and mapping | One iOS writer; future `ios/GridRace/App/LiveMatch.swift`, `SupabaseLiveMatchService.swift`, `ios/GridRaceTests/LiveMatchTests.swift`; existing `SupabaseAccountService.swift`; serialized project registration | P2-04B and dictionary overlap resolved | Pending: all six command boundaries reused or mapped, real fixtures decode, typed HTTP/errors, no SDK types in domain |
| P3-02 Session and recovery | Same iOS writer; future `ios/GridRace/App/LiveMatchSession.swift`, `LiveMatchRecoveryStore.swift`, `SupabaseMatchRealtimeService.swift`, `ios/GridRaceTests/LiveMatchSessionTests.swift`; controller approves exact composition edits | P3-01 | Pending: single session, durable IDs, lifecycle cancellation, bounded refresh, auth/account isolation, clock and uncertainty proof |
| P3-03 Live UI | Same iOS writer; future `ios/GridRace/App/LiveMatchViews.swift`; existing `DailyViews.swift`, `GridRaceApp.swift`, `DailyAccountCoordinator.swift` only for composition/routing; serialized project | P3-02 | Pending: create/join/lobby/countdown/round/reveal, recovery/errors, Home/Resume, accessibility; retain Daily ownership and settings |
| P3-04 Real integration and race proof | Primary; future `ios/GridRaceTests/LiveMatchIntegrationTests.swift`, future `supabase/tests/integration/live_slice_test.ts`, disposable local fixtures and simulator containers | P3-01..03 for app proof; backend HTTP/Realtime/concurrency harness is established during P2-04B | Pending: actual Edge/Auth/Realtime, independent users/connections and two simulator apps; promote exact new commands only after successful runs |
| R-01 Implementation final review | Fresh read-only reviewer; integrated implementation and evidence | P3-04 | Pending: security/recovery/deletion/accessibility/operations findings adjudicated |
| C-02 Implementation closeout | Primary; authorities, plan and task-owned Git paths | R-01 fixes and all local exit gates | Pending: record evidence, mark historical only when the slice is complete |

No parallel writers on migrations, API, project, account/composition roots, or
tracking documents. Read-only reviewers may inspect broadly, cannot stage/commit,
and return findings to the controller. A missing dependency pauses its dependent
unit only; P2-04A has no dictionary/Xcode overlap and is executable next.

## Risk and evidence gates

Cross-boundary architecture and the eventual implementation are **High** risk. This
task changes documentation only: run the runbook's workflow/docs checks and one fresh
independent review of the revised plan. Do not mislabel this as the P2 security audit
or the P3 implementation review. No unrelated application builds are needed now.

Existing commands are owned by [`../ENGINEERING_RUNBOOK.md`](../ENGINEERING_RUNBOOK.md).
Use its current Deno, seed, Supabase reset/test/lint and Xcode discovery/test/build
commands during affected implementation units. Include `app_rls` in the security
inspection; the earlier three-schema lint result is retained below. A clean reset
proves zero-state migration only: P2-04A also needs a forward upgrade from the current
six-migration fixture, verifying resulting normal-role grants without manually
repairing them in the proof harness.

New concurrency/HTTP/Realtime harnesses, Release-specific checks and the coordinated
simulator procedure are **future proof surfaces**, not commands claimed to work.
P2-04B/P3-04 must establish and record exact invocations, prerequisites, cleanup and
results; promote them to the runbook only after they run. Missing/opt-in-skipped proof
is unavailable, not passed. Local reset is permitted only on confirmed disposable
GridRace test state; never reset a linked/remote project or the user's live data.

| Gate / exit criterion | Owner and feasible evidence path |
| --- | --- |
| E1 Backend authority and secrecy | P2-04B: clean reset + forward path, lint, pgTAP with anonymous/rostered/unrelated/deleted/service identities; direct private reads, column grants, RPC execution and direct mutation denied; before/after reveal audits including Realtime payloads |
| E2 Contract, rules, creation and submission | P2-04A/P3-01: existing shared vectors in Swift/Deno plus SQL equivalent proof; actual snapshot fixtures (not fabricated Edge mock shapes); HTTP success/non-2xx errors, unknown/version/malformed rejection; same create/guess UUID returns original result, conflicting guess reuse fails, no extra quota/rows |
| E3 Concurrent transitions | P2-04B/P3-04: separate transactions synchronized at lock boundaries; competing seat-two joins, same/different UUID submissions, same UUID across matches, finalizers vs last/sixth guess, deadline equality and lock-wait ordering, deletion vs join/start/submit, rollback and rate-counter deadlocks; bounded completion and exactly one canonical outcome |
| E4 Two-client product loop | P3-04: two separate app processes/simulators and two Auth users use actual local Edge gateway, same roster/start/deadline, independently submit and converge on reveal/placement; third user and anonymous requests fail; local fixture admin credentials never enter client paths |
| E5 Recovery and persistence | P3-02/P3-04: lost create/guess response before and after commit; relaunch between persistence/send/ack; same UUID replay after deadline/reveal; blocked auth/expired token; account switch and late callbacks; disk failure; exact accepted-board restoration and no duplicate row |
| E6 Realtime, timers and terminal behavior | P3-02/P3-04: healthy event path plus all signals dropped, duplicates/reordering, subscription handshake race, silent socket, foreground/background and clock jumps; trailing fetch cannot regress state; bounded watchdog restores lobby and early reveal without another event; creator disconnect never forfeits |
| E7 No-client finalization | P3-04: both apps closed; local scheduled job reaches reveal after deadline without a client snapshot; inspect job outcome through privileged test setup, invoke finalizer repeatedly, reopen both clients and compare. Direct finalizer tests alone do not prove scheduling. Remote Cron remains external |
| E8 Deletion and account isolation | P2-04B/P3-04: host/guest lobby deletion, active deletion, already-solved deletion, survivor reveal, both accounts deleted; preparation/Auth/completion failure and lost-response retries through real Edge; no reversible auth mapping, old credentials cannot read/write; live state cleared and Daily UUID cache removed only after confirmed deletion; guest files retained |
| E9 UI/accessibility/regressions | P3-03: build/tests plus inspect all live states with VoiceOver, largest Dynamic Type, Reduce Motion, Increased Contrast, Bold Text, non-color tiles, hit targets, hardware keyboard and haptics preference; waiting after early solve, errors/recovery and reveal semantic order; repeat Daily/tutorial/account regressions |
| E10 Local environment and diagnostics | P3-04: Debug tests and clean build, Release build/debug-auth exclusion, no bundled secrets, correct build floor; actual local gateway auth modes and Realtime authorization; safe error/timeout diagnostics and no payload leakage; record request count, snapshot byte size and latency without user data |
| E11 Final quality | R-01/C-02: fresh implementation review, accepted fixes verified, whole owned diff and command/path checks, evidence for every gate, unrelated edits preserved, no remote mutation or spend |

No gate is satisfied merely by test counts. Record named scenarios, actual result,
fixture/environment, and limitations. UI approval is required for material departures
from the accepted Daily-first flow; routine implementation within that flow needs no
repeat approval. If a genuine rule/privacy/API decision emerges, ask before changing it.

## Operating, cost, and release boundary

**Accepted constraint:** spend $0 initially while the owner and friends validate the
app. Do not provision paid plans/add-ons, domains, telemetry, CI capacity or hosting.
External traction permits reconsideration, not automatic spending. The maintainer
must approve any paid commitment. Local development continues without hosted spend.

Official facts checked 2026-09-22: Supabase Free lists 500 MB database, 5 GB egress,
50,000 monthly active users, 200 peak Realtime connections, 2 million messages/month
and 500,000 Edge invocations/month; it can pause after a week of inactivity and has
no automatic backups. These are current quotas, not a GridRace capacity guarantee.
[Supabase pricing](https://supabase.com/pricing)

Inference: a small friends-only trial should fit if usage is measured. At a 5-second
watchdog interval, two foreground clients in a 3-minute round generate roughly 72
watchdog snapshots before event resets and other commands; an idle lobby costs more
if left open. Daily sync shares the same quota. Measure real request counts, bytes,
latency and storage growth locally; before hosted testing inspect project usage and
stop/reduce test activity if free quotas are insufficient. Never weaken recovery or
retention secretly to save quota. Do not add synthetic traffic to defeat pausing.

Native distribution is a distinct blocker under a strict zero-spend constraint:
Apple lists a $99/year Developer Program membership including TestFlight. Free
personal-device provisioning is limited and expires after seven days; it is not a
promise of convenient free friends distribution. Existing membership/eligibility is
unknown. The maintainer must resolve distribution before that later milestone;
no purchase or native-stack reversal is authorized here.
[Apple program](https://developer.apple.com/programs/) ·
[Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)

Keep the existing local stack. Later hosted friend testing needs an explicitly
approved deployment plan, isolated environment/configuration, provider setup,
retention and backup/export/restore decisions, safe secrets and usage checks.
No hosted availability promise follows from the local proof; free-tier pauses,
provider incidents and quota failures must leave Daily playable and live recovery
honest. Restore current auth and snapshot state when service returns.

Cron already invokes the same database finalizer once a minute. Acceptance stops at
the stored deadline; unattended persisted reveal may lag until a job runs. No hard
real-time scheduling guarantee is implied. Prove the local schedule and command
fallback; hosted Cron delivery is a later gate.
[Supabase Cron](https://supabase.com/docs/guides/cron)

Postgres Changes performs per-subscriber authorization and ordered processing; use
small match-scoped subscriptions and coalesced snapshots now. Benchmark fan-out and
lock contention before expansion; consider authorized Broadcast only if measurements
show a bottleneck. SQL remains comparatively portable, but Auth/Realtime/Edge APIs
are coupling. Self-hosting shifts operational responsibility and is not a free
maintenance solution. Short-lived Edge handlers should not host the match clock.
[Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) ·
[Self-hosting](https://supabase.com/docs/guides/self-hosting) ·
[Edge limits](https://supabase.com/docs/guides/functions/limits)

Use only safe operation/error category, elapsed duration and aggregate request counts
for local proof diagnostics. Do not add persistent production telemetry or log raw
responses/SQL errors. Capture Cron failure and recovery failures without gameplay
payloads. Production log retention/authorized access remains a pre-hosting decision.

Rollback during local implementation means revert task-owned code and recreate only
explicitly disposable local fixtures. Do not edit applied migration history; add a
forward migration. The required create request field is a coordinated local API
change before any live iOS client ships; no compatibility framework is needed.
A future hosted release requires a data-preserving migration/rollback strategy,
backup verification and compatible client/build gating before any rollout.

## Decisions, blockers, and next action

| ID | State | Decision / blocker / owner |
| --- | --- | --- |
| DEC-01 | Retained | Native SwiftUI, fixed slice, authoritative PostgreSQL, thin authenticated Edge, canonical recovery; no framework or dependency change |
| DEC-02 | Accepted 2026-09-22 | Opponent presence deferred by maintainer; own transport status only |
| DEC-03 | Accepted 2026-09-22 | Retry-safe create and bounded foreground snapshots; P2-04A contract change before Swift |
| DEC-04 | Accepted 2026-09-22 | $0 initial spend; paid commitments need explicit maintainer approval after revisiting traction |
| BLK-01 | Open for overlapping files | Maintainer must checkpoint/separate unrelated dictionary work before `DailyViews.swift`, Xcode or overlapping runbook writes; no agent may stage/discard it. P2-04A product paths remain independent |
| BLK-02 | Open implementation gate | P2-04A corrections and P2-04B security/concurrency checkpoint precede iOS dependency |
| BLK-03 | Later external proof | Maintainer: Apple credentials/revocation, distribution cost, physical devices, hosted environment/retention/backups/usage; not local-slice completion claims |
| BLK-04 | Known limitation | Trusted client-IP provenance unavailable locally; prove per-user limits and keyed-IP SQL path, do not trust arbitrary forwarded headers; resolve before hosted abuse-control claims |

Full Ponytail mode and the simplicity/test preferences in `AGENTS.md` apply to
implementation; they do not reduce this agreed scope.

**Exact next implementation unit: P2-04A.** After this documentation checkpoint,
start with real-output fixtures for deleted-member snapshots and lost/concurrent
create retries; add the one forward migration and the bounded create handler/test
change listed in the unit. Preserve the six-migration baseline, demonstrate forward
and reset paths plus negative RLS/receipt/HTTP tests, then checkpoint for P2-04B.
This planning task stops before making any of those product changes.

## Current planning review and verification

Planning findings and independent revised-plan review dispositions are recorded
below before committing. A closed planning finding means the plan now requires the
repair/proof; it never means a pending product fix has been implemented.

| ID | Severity | Location / claim | Evidence | Disposition | Action | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| PLAN-01 | High | Original next action treated the backend contract as ready for Swift recovery | `create_match` has no receipt; deleted-member `is_self` SQL comparison can return null | Accepted | P2-04A precedes mapping and security checkpoint; target/current API split | Source traced; product proof remains E2/E5/E8 |
| PLAN-02 | High | Event/lifecycle refresh alone cannot bound recovery from silent lost signals | No next event guaranteed in lobby or early reveal | Accepted | Bounded foreground watchdog and handshake/trailing refresh proof | E5/E6 explicitly exercise all signals dropped |
| PLAN-03 | Medium | Opponent connectivity had no owner or wire field | Screen flow promised it; snapshot/service has no presence | Accepted | Maintainer deferred labels; update flow/architecture | API and screen flow agree |
| PLAN-04 | Medium | Single iOS unit and generic evidence could hide missing real transport/race proof | Edge tests inject RPC/auth; SQL tests are sequential | Accepted | Dependency units and E1–E11 evidence paths | Distinguish mocks, SQL, concurrency, gateway, simulator, external |
| PLAN-05 | Medium | Stale paused/current claims and clean-worktree closeout conflict with reactivation/user edits | Product/flow/decisions stale; pre-existing dictionary/runbook changes | Accepted | Correct active authorities; preserve unrelated hashes and task-only staging | Final documentation checks |
| PLAN-06 | Medium | Initial cost/distribution assumptions were unspecified | Maintainer zero-spend constraint; current Apple and Supabase docs | Accepted | Free-first budget, no automatic upgrades, explicit later distribution blocker | Official sources checked; no purchase or deployment |

### Fresh review of the revised state

A fresh read-only reviewer inspected the full revised plan, all eight task-owned
current authorities, scoped diffs, and relevant implementation seams. No additional
material findings or user decisions were identified. Coverage included product/beta
alignment, factual/current-versus-pending claims, dependencies, trust/API/snapshots,
secrecy, state machines, concurrency/retry/cancellation, Realtime/recovery, deletion,
accessibility, realistic tests, diagnostics, environment/rollback/cost and evidence
feasibility. This was not the future implementation security or final review.

Controller final dependency inspection clarified that Phase 2 requires only backend
portions of shared evidence gates; Swift mapper proof waits for P3-01. The backend
HTTP/Realtime/concurrency harness starts in P2-04B, avoiding an apparent cycle through
the later simulator unit. No product decision or scope changed.

### Planning verification, 2026-09-22

Task-owned files: this plan, `docs/live-api-contract.md`, `docs/architecture.md`,
`docs/privacy-data-map.md`, `docs/screen-flow.md`, `docs/product-spec.md`,
`docs/DECISIONS.md`, and `docs/NOW.md`. No runbook, TODO, game-rule or product-code
change was required; all pre-existing changes remain unrelated.

| Check | Result |
| --- | --- |
| Required authority reads and bounded source tracing | Complete; all named authorities read, implementation inspected only at relevant seams |
| `rg -l '^Status: Active$' docs/plans` | Exactly this one active plan |
| Local Markdown targets and inline file references | All 12 relative links resolve; missing implementation paths are explicitly labeled future |
| Existing command resolution | Git, rg, Python, npm/npx, Deno and xcodebuild resolve; 22 existing command input/project/scheme paths exist; npm seed script inspected; new harness/Release procedures labeled future, no new command promoted |
| Task-scoped `git diff --check` and complete owned diff inspection | Passed; eight documents reviewed in full/scoped diff, including accepted pending API changes |
| Unrelated working-tree preservation | SHA-256 comparison of all 22 pre-existing changed/untracked files passed; no product or unrelated write |
| Independent revised-plan review | Complete; no additional material findings; controller dependency clarification inspected |
| Product execution | Not run in this documentation task: no reset, product tests/build, simulator, gateway, Realtime or concurrency execution; prior evidence remains labeled historical |

## Historical implementation findings

| ID | Severity | Location and claim | Evidence | Disposition | Action | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| DB-01 | High | `submit_guess`: a concurrent identical retry can consume rate quota before the second receipt check. | Counter call preceded match lock and serialized receipt lookup. | Accepted | Counter moved after lock/receipt resolution; unchanged-counter test added. | Closed: reset/lint/79 pgTAP pass |
| DB-02 | Medium | `delete_account`: member lock preceded round/player locks. | Source contradicted frozen shared lock order and `start_match`. | Accepted | Member mutation now follows round and seat-ordered player locks. | Closed: reset/lint/79 pgTAP pass |
| DB-03 | Medium | `create_match`: code existence check and unique insert were separate. | Concurrent creation could win the code between check and insert. | Accepted | Insert retries only the join-code unique constraint. | Closed: reset/lint/79 pgTAP pass |
| DB-04 | Low | `pg_cron` privileges were not explicitly denied to client roles. | Game schemas were explicit; extension schema relied on defaults. | Accepted | Client schema/table/routine privileges revoked; owner job retained. | Closed: reset/lint/79 pgTAP pass |
| DB-05 | Low | Initial pgTAP matrix lacked focused round/player unrelated checks and retry counter proof. | Controller inspection of 68 assertions. | Accepted | Added bounded rostered/unrelated/snapshot/counter assertions. | Closed: 79/79 pgTAP pass |

## Prior execution evidence (not rerun by the planning task)

| Surface | Exact command or inspection | Result |
| --- | --- | --- |
| Starting tree | `git status --short`; `git branch --show-current`; `git log --oneline -12` | Passed: clean `main`, HEAD `e7ccb96` |
| Active-plan uniqueness | `rg -l '^Status: Active$' docs/plans` before this file | Passed: no result |
| Required reads | Complete reads of every named task/repository file | Passed |
| Word pack | `python3 scripts/check_word_pack.py` | Passed: 100 words |
| TypeScript format | `deno fmt --check rules/typescript` | Passed: 2 files |
| TypeScript lint | `deno lint rules/typescript` | Passed: 2 files |
| TypeScript check | `deno check rules/typescript/evaluator.ts rules/typescript/evaluator_test.ts` | Passed |
| TypeScript tests | `deno test --allow-read rules/typescript/evaluator_test.ts` | Passed: 3 tests, 0 failed |
| Xcode project | `xcodebuild -project ios/GridRace.xcodeproj -list` | Passed |
| Simulator discovery | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -showdestinations` | Passed historically: local UUID used in the following commands; rediscover before reuse |
| iOS tests | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' -derivedDataPath /tmp/GridRaceDerivedData-baseline-test test` | Passed: 16 tests, 0 failed |
| iOS clean build | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' -derivedDataPath /tmp/GridRaceDerivedData-baseline-build clean build` | Passed |
| Package install | `npm ci --no-audit --no-fund` | Passed: 8 packages from lockfile |
| Pinned Supabase CLI | `npx supabase --version` | Passed: `2.116.0` |
| Derived word seed | `npm run check:seed` | Passed: 100 canonical rows |
| Supabase config | Python 3 `tomllib` assertions for Postgres 17, API schemas, auto-exposure, and seed path | Passed |
| Database reset | `npx supabase db reset --local` | Passed: migration and exact seed applied from zero |
| Database lint | `npx supabase db lint --local --schema public,private,app_rls --level error --fail-on error` | Passed: zero results |
| Database/RLS tests | `npx supabase test db --local supabase/tests/database` | Passed: 79 tests, 0 failed |
| Reactivation uniqueness | `rg -l '^Status: Active$' docs/plans` before reactivation | Passed: no result |
| Reactivation seed | `npm run check:seed` | Passed: 100 canonical rows |
| Reactivation TypeScript and Edge static gates | `deno fmt --check rules/typescript supabase/functions`; `deno lint rules/typescript supabase/functions`; explicit `deno check` for all handlers and tests | Passed: 17 formatted files, 16 linted files, all checked entrypoints |
| Reactivation shared rules | `deno test --allow-read rules/typescript/evaluator_test.ts` | Passed: 3 tests, 0 failed |
| Reactivation Edge tests | `deno test --config supabase/functions/deno.json supabase/functions/` | Passed: 96 tests, 0 failed |
| Reactivation database reset | `npx --no-install supabase db reset --local` | Passed: all six migrations and seed applied from zero |
| Reactivation database tests | `npx --no-install supabase test db --local supabase/tests/database` | Passed: 217 assertions across 5 files |
| Reactivation database lint | `npx --no-install supabase db lint --local --schema public,private,app_rls --level warning --fail-on error` | Passed with no errors; existing unused/shadowed-variable extra warnings remain |

## Integrated commits

Phase 2/3 commits to date:

| Commit | Purpose | Status |
| --- | --- | --- |
| `70c0339 docs: track phase 2 and 3 live slice` | Activate durable task tracking | Complete |
| `357af25 docs: define phase 2 and 3 live contract` | Freeze phase naming, trust boundaries, commands, snapshot, deletion, and proof | Complete |
| `f69365b build(backend): bootstrap local Supabase` | Pin the local Supabase CLI and deterministic canonical word seed | Complete |
| `b9628c0 feat(backend): add private game schema and RLS` | Add authoritative schema, service-only transactions, RLS, finalizer, deletion, and database proof | Complete |
| `95edc90 feat(backend): add authenticated command edge functions` | Preserve the six authenticated Edge boundaries after format, lint, and type checks | Complete after `ddde194` added focused tests |
| `ddde194 test(edge): cover all six handlers and prove Edge Deno canon` | Complete focused contract coverage for the six Edge handlers | Complete |
| `f0b7b5f fix(live): replace matches.updated_at realtime signal with revision` | Use an explicit monotonic match revision as the safe Realtime refresh signal | Complete |
| `f73da30 feat(backend): add daily classic personal sync storage` | Add owner-private Daily storage without changing competitive live state | Complete |
| `dd85670 feat(ios): add accounts and daily classic synchronization` | Supply the reusable account/session/profile client foundation | Complete |
| `0162081 docs(plan): reactivate phase 2 and 3 live slice` | Reconcile current state, make this the sole active plan, and record fresh backend proof | Complete |
| `764b9e1 docs(plan): record reactivation checkpoint` | Record the reactivation content checkpoint | Complete |
| `2a8ac34 docs(plan): strengthen authoritative live slice and free-first scope` | Accepted brainstorming, eight authority updates, six planning findings addressed, fresh independent review and documentation checks | Complete |


Planning tracker checkpoint: **this commit** records `2a8ac34`. Staging was limited
to the eight task-owned documents; the staged whitespace check passed and staged
content matched the reviewed diff. Product implementation remains pending and this
plan remains Active.

## Milestone exit and checkpoint policy

Phase 2 baseline evidence remains recorded above. **Phase 2 exits only after P2-04A
and P2-04B pass the backend portions of E1–E3 and E8/E10 with no unresolved
material security finding.**
The current planning review does not satisfy that gate.

Phase 3 exits only when E4–E11 and client portions of E2/E5/E8 pass, including real
independent clients, no-client scheduled finalization, negative secrecy proof,
retry/relaunch/account isolation, accessibility and Daily/tutorial regressions.
Unavailable local infrastructure blocks that gate; mocked substitutes do not pass it.
Real Apple exchange/revocation, hosted scheduling/deployment, physical-device coverage,
production word provenance/retention and complete 2–8 player MVP/moderation remain
external/later beta gates, explicitly owned by the maintainer before release.

Checkpoint coherent units with conventional commits after their evidence and review.
Record each content checkpoint here in the next tracker update. Planning completion
leaves this plan Active; implementation closeout alone marks it Historical.

- [ ] P2-04A/B contract/security gates complete with exact evidence.
- [ ] P3 client, real transport, concurrency and two-client gates complete.
- [ ] Implementation review findings adjudicated; accepted fixes verified.
- [ ] Authorities and newly proved commands current; beta limitations explicit.
- [ ] Task-owned changes committed; unrelated work unchanged and unstaged by this task.
- [ ] No remote mutation, push, paid service or unapproved data operation occurred.
- [ ] At live-slice completion only: mark Historical, identify last content checkpoint,
      label tracker closeout “this commit,” and report its SHA.

Stop for more than one active plan, unexpected overlap, a rule/privacy/security/API
choice beyond accepted direction, a proposed paid commitment, or a high-risk gate
that cannot be resolved in scope. Continue independent safe work where possible.
