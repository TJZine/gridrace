Status: Active
Scope: GridRace Phase 2 backend foundation and Phase 3 two-player live slice
Owner: Primary orchestrator
Started: 2026-08-30
Last updated: 2026-10-02

# Phase 2 and Phase 3 Live Slice Plan

## Goal and current checkpoint

Prove the first authoritative Blind Race: two authenticated players, one five-letter
round, creator start, server-owned guesses and time, clue-free progress, recovery,
and shared reveal. Daily Classic stays immediately playable offline and signed out;
its imported personal history never becomes verified competitive evidence.

This plan remains the sole active plan. The accepted 2026-09-22 planning checkpoint
is complete, and the current controller is executing the implementation packages
below. Local product changes and confirmed-disposable GridRace test resets are now
authorized only inside each package's recorded boundary; deployment, remote mutation,
spending, publication, release, and unrelated dictionary work remain excluded.

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
- Live Swift transport, strict mapping, session recovery and Realtime signal handling,
  live UI and recorded two-process app integration proof now exist. Existing
  Edge tests inject dependencies; SQL assertions are not proof of independent
  concurrent transactions or of actual Edge gateway/Realtime delivery.
- Staging/Release configuration placeholders and CI already exist. Remote deployment,
  a passing hosted CI run, and real Apple exchange are not established by those files.
- Unrelated dictionary/attribution work includes the runbook, `DailyViews.swift`, and
  Xcode project. Preserve every pre-existing edit/untracked file. The planning task
  must not edit or stage the runbook. The iOS writer waits for the maintainer to
  checkpoint or otherwise separate overlapping work; no automatic stash/commit.

### Implementation controller bootstrap, 2026-09-22

- Controller task: `GridRace live-slice implementation controller` on the saved local
  checkout `/Users/tristan/Software/gridrace`; controller model/reasoning is
  `gpt-5.6-sol` / medium per the maintainer's corrected pairing. No product worker had
  been dispatched when that correction arrived.
- Pre-bootstrap repository state: branch `dev/classic-mode`, full HEAD
  `656c6ba1c0c95eb5656344c5ab39b39f957fa354`, empty index, cached upstream
  `origin/dev/classic-mode` at `ea630dd985a0e1ffeca1317517539d3d8d9a065b`, ahead 6
  and behind 0. No fetch or fresh remote claim was made. Exactly this plan is Active;
  no repository `.codex/config.toml` or task-role configuration was found.
- A fresh byte-hash baseline for all 23 unrelated tracked/untracked files, including
  the two concrete files under untracked `.codex/cache/`, is stored outside the
  repository at
  `/tmp/gridrace-live-slice-controller-01a0c7dd/unrelated-baseline.tsv`. The unrelated
  paths are the runbook, Xcode project, `DailyViews.swift`, word-pack checker and
  artifacts, `.DS_Store` files, `.codex/cache` review cache, dictionary plan/evidence,
  extraction scripts, attribution, baseline and provenance artifacts. Recheck this
  exact inventory and hashes at every write-lease transfer and closeout; never stage,
  stash, discard, or overwrite it.
- The maintainer authorizes one narrow exception to the runbook's controller-only Git
  rule: the single active implementation writer may stage only its explicit owned
  paths and create exactly its requested conventional implementation commit. The
  controller alone edits/stages/commits this plan and authority integration. Read-only
  workers never mutate Git. All other repository rules remain in force.
- A writer receives the lease only after the controller verifies the branch/full HEAD,
  empty index, unrelated baseline, one-active-plan invariant, repository role config,
  and exact owned paths. While the lease is active, the controller performs no file,
  index, commit, shared-database, or simulator mutation and dispatches no other writer.
  The worker completes edits, proof, staging, its one commit, final status and evidence
  before one callback; that callback releases the lease and no later worker writes are
  allowed. The controller then validates the commit and baseline, independently reruns
  risk-matched proof, records acceptance, and creates a separate plan checkpoint before
  the next serial dispatch.
- The first lease is P2-04A, restricted to
  `supabase/migrations/202609220001_live_recovery_contract.sql`,
  `supabase/tests/database/live_recovery_contract.sql`,
  `supabase/functions/create-match/index.ts`, and
  `supabase/functions/create-match/index_test.ts`. Its worker is explicitly
  `gpt-5.6-luna` / xhigh. It starts from the full SHA of this bootstrap checkpoint,
  proves forward/reset plus focused negative and true-concurrency behavior, and uses
  `feat(backend): make live creation retry-safe`. P2-04B and all Swift work remain
  gated on controller acceptance and the dependencies below.

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
contract. P2-04A now implements its create-receipt and deleted-member identity
checkpoint. P2-04B now supplies the backend security/integration proof required before
Swift DTOs depend on it.

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
Unimplemented future filenames below are proposed write boundaries, **not existing files**.

| Unit | Owner / exclusive write boundary | Dependency | Acceptance / status |
| --- | --- | --- | --- |
| PLAN-01 | Primary; this plan, API, architecture, privacy, flow, product, decisions, NOW | Accepted brainstorming | Complete: accepted direction revised and independently reviewed; documentation proof below; no product writes |
| P2-01..03 | Historical backend owners; existing migrations, seed, handlers/tests | Original contract | Complete baseline; evidence retained below, not proof of new targets |
| P2-04A Recovery contract corrections | Luna/xhigh worker began the four-path package; controller took over at maintainer direction and added only the two existing SQL fixtures required to make the new RPC parameters genuinely mandatory | PLAN-01 checkpoint | Complete in `a80f282`: atomic create receipts, Boolean deleted-member identity, strict RPC/Edge request ID, forward/reset, negative, rollback, lifecycle and independent concurrency proof; no iOS/project edits |
| P2-04B Backend security/integration checkpoint | Primary plus fresh read-only security reviewer; integrated backend, maintained `supabase/tests/integration/live_slice_test.ts`, and exact reproduced repair paths assigned serially | P2-04A | Complete in `68bd474` and `f2d7243`: actual Auth/Edge/RLS/Realtime/deletion proof, concurrent transition matrix, local-only harness controls, and all four security-review findings remediated and verified |
| P3-01 Transport and mapping | Primary controller directly; `ios/GridRace/App/LiveMatch.swift`, `SupabaseLiveMatchService.swift`, `ios/GridRaceTests/LiveMatchTests.swift`; existing `SupabaseAccountService.swift`; serialized project registration | P2-04B and dictionary overlap resolved | Complete in `4b6745a`: five live commands mapped, existing deletion boundary reused, actual local Edge fixtures decode, typed status/error mapping and strict fail-closed snapshots, no SDK types in domain |
| P3-02 Session and recovery | Primary controller directly; `ios/GridRace/App/LiveMatchSession.swift`, `LiveMatchRecoveryStore.swift`, `SupabaseMatchRealtimeService.swift`, `ios/GridRaceTests/LiveMatchSessionTests.swift`; exact composition edits | P3-01 | Complete in `d578ec4`: durable create/guess IDs, persistence-before-dispatch, subscribe-before-catch-up, coalesced canonical recovery, lifecycle/auth/account isolation, monotonic clock and bounded timeout/backoff proof |
| P3-03 Live UI | Fresh local `gpt-5.6-sol` / medium task; `ios/GridRace/App/LiveMatchViews.swift`, existing `DailyViews.swift`, focused tests and serialized project registration | P3-02 | Complete in `2117d71` with proof repair `06955d9`: create/join/lobby/countdown/round/reveal, recovery/errors, Home/Resume and code-inspected accessibility while retaining Daily ownership and settings |
| P3-04 Real integration and race proof | Fresh local `gpt-5.6-sol` / medium tasks; `ios/GridRaceTests/LiveMatchIntegrationTests.swift`, host script and serialized project registration; existing backend harness and disposable local fixtures/simulator containers | P3-01..03 for app proof; backend HTTP/Realtime/concurrency harness completed during P2-04B | Complete in `0fcc113`: fresh two-process Auth/Edge/Realtime/watchdog/Cron/relaunch proof plus E3/E8/E10, Debug/Release and cleanup; IOS-01 repaired in `1d004c1` |
| R-01 Implementation final review | Fresh read-only reviewer; integrated implementation and evidence | P3-04 | IOS-14 closed; closure returned IOS-15 in the Retry caller of selected recovery; bounded repair before final acceptance |
| C-02 Implementation closeout | Primary; authorities, plan and task-owned Git paths | R-01 fixes and all local exit gates | IOS-15 repair and terminal acceptance remain; no Historical status before terminal PASS |

No parallel writers on migrations, API, project, account/composition roots, or
tracking documents. Read-only reviewers may inspect broadly, cannot stage/commit,
and return findings to the controller. A missing dependency pauses its dependent
unit only. P2-04B, BLK-01, P3-01..04 and IOS-01..14 repairs are integrated;
IOS-15 completes the selected-recovery Retry caller boundary before terminal acceptance.

## Risk and evidence gates

Cross-boundary architecture and this implementation are **High** risk. The earlier
planning checkpoint changed documentation only; P2-04A now has the implementation
and risk-matched evidence recorded below. Do not mislabel the planning review or
P2-04A's focused proof as the completed P2-04B security audit or the pending P3
implementation review. No unrelated application builds are required for backend-only
units.

Existing commands are owned by [`../ENGINEERING_RUNBOOK.md`](../ENGINEERING_RUNBOOK.md).
Use its current Deno, seed, Supabase reset/test/lint and Xcode discovery/test/build
commands during affected implementation units. Include `app_rls` in the security
inspection; the earlier three-schema lint result is retained below. A clean reset
proves zero-state migration only: P2-04A separately proved the forward upgrade from
the six-migration fixture and resulting normal-role grants without manually repairing
them in the proof harness.

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
| BLK-01 | Resolved 2026-09-26 | Maintainer checkpoint `3763611` committed the dictionary, `DailyViews.swift`, Xcode project and runbook package with its evidence; only the previously recorded non-overlapping scratch/cache files remain untracked |
| BLK-02 | Resolved 2026-09-26 | P2-04A and P2-04B backend contract, security, integration and concurrency checkpoints are complete; no unresolved material review finding remains |
| BLK-03 | Later external proof | Maintainer: Apple credentials/revocation, distribution cost, physical devices, hosted environment/retention/backups/usage; not local-slice completion claims |
| BLK-04 | Known limitation | Trusted client-IP provenance unavailable locally; prove per-user limits and keyed-IP SQL path, do not trust arbitrary forwarded headers; resolve before hosted abuse-control claims |

Full Ponytail mode and the simplicity/test preferences in `AGENTS.md` apply to
implementation; they do not reduce this agreed scope.

**Exact next unit: IOS-15 Retry capability and caller repair.** A fresh 6.1 Sol medium
worker owns only `ios/GridRace/App/LiveMatchSession.swift`, `LiveMatchViews.swift`,
`ios/GridRaceTests/LiveMatchSessionTests.swift` and, if meaningful existing coverage
needs extension, `LiveMatchViewTests.swift`. Generic Retry must preserve a failed Join
error and cannot select an old unselected pointer; unavailable/top-banner UI must not
offer that wrong action. Retain pending-command, selected-match and storage remediation
Retry behavior. Prove failed Join → Retry → Home → explicit Resume with no old-room
work before Resume and subscribe-before-catch-up afterward. Then obtain a bounded
read-only closure check retaining prior whole-range evidence, not another unrelated
repository audit. Main controller performs Historical closeout only after explicit
terminal PASS. The main
thread now owns orchestration, adjudication, integration and this plan; the stopped
controller and interrupted worker remain stopped. Per maintainer direction on
2026-10-02, future implementation packages use a fresh local `gpt-6.1-sol` / medium
task; the repository's configured read-only reviewer remains a separate role.
Every worker must attempt its structured callback exactly once even when blocked or
when no commit was created; callback delivery never depends on completing a commit.

## P2-04A execution and acceptance, 2026-09-22

- Start checkpoint `dd8230ae43cce495c937bb363eea314242885058`; implementation
  commit `a80f28286aebd38975d627d2616a3afc14286e7f` with that checkpoint as
  its sole parent.
- Worker task `GridRace P2-04A recovery contract`
  (`01a0c7e0-dac1-7ae2-b228-e5b522d3fc21`, `gpt-5.6-luna` / xhigh) created the
  initial four-path implementation and evidence. At maintainer direction, the
  controller revoked its lease before staging or commit; the worker stopped at the
  unchanged start SHA with an empty index and handed back only the four owned edits.
- The controller completed and accepted the package directly. Audit found the Edge
  success fixture still included obsolete `join_code`, receipt lifecycle lacked an
  isolated match-cascade assertion, and the service RPC's generated default made
  `request_id` optional. The first two were repaired in the assigned files. The RPC
  repair necessarily expanded the bounded implementation commit to existing
  `supabase/tests/database/phase_2_3_foundation.sql` and
  `supabase/tests/database/match_revision_signal.sql`, updating only their three
  legacy create calls. No compatibility overload/default remains; all four service
  parameters are mandatory.
- Final implementation paths: the planned migration and recovery SQL test, create
  handler/test, and those two existing SQL fixture files. The controller inspected
  the complete new files and every changed line. Snapshot and deletion function
  comparisons against their prior definitions showed only Boolean `is_self`, the
  shared per-account advisory lock, and create-receipt deletion changes.
- Verification passed: seed check (100 words); Deno format/lint/type checks; all 99
  Edge tests; clean seven-migration resets; all 266 pgTAP assertions across six files;
  database lint over `public,private,app_rls` with no errors and only the recorded
  pre-existing unused/shadow warnings. A fresh two-connection barrier race returned
  two successes with one canonical match, receipt and quota charge.
- Forward proof reset the disposable local stack to the exact six historical
  migrations (migration count 6, old RPC present, no receipt table, 100 seed words),
  then applied only `202609220001_live_recovery_contract.sql`. The result had migration
  count 7, no old RPC, the strict four-argument RPC with zero optional arguments,
  service-only execution/receipt access, the unchanged seed, and a successful real
  fixture creating one match and receipt. The normal seven-migration reset restored
  the local stack afterward.
- Negative/lifecycle proof covers malformed/missing UUIDs, unsupported build, absent
  profile, conflicting payload reuse, quota deduplication, rollback, replay after
  expiry/start/completion, account deletion, match cascade, authenticated denial and
  survivor Boolean identity. Actual Edge gateway/HTTP, broader RLS/secrecy, Realtime,
  deletion receipt partial failures and lock-graph races remain explicitly P2-04B.
- The unrelated 23-file baseline remained byte-identical, the index was empty before
  task staging, and no remote mutation, deployment, push, spend or release occurred.
- P2-04A tracker/authority checkpoint: **this commit** records controller acceptance
  and advances the dependency-ready unit to P2-04B without claiming its pending proof.

## P2-04B execution and acceptance, 2026-09-26

- Integration evidence commit `68bd474bbd46934cd46d24e1fb7a691c39a6b9c7`
  added the single maintained local harness. It uses real local Auth users, the six
  Edge endpoints, RLS/REST, Realtime, privileged disposable fixtures and independent
  concurrent requests; no production handler is replaced by a mock.
- The cold-reset Realtime run exposed a local tenant startup race: channel
  `SUBSCRIBED` preceded registration in `realtime.subscription`. The harness now waits
  up to ten seconds for the authenticated user's actual `public.matches` subscription
  row, then still requires the real published event. It neither sleeps blindly nor
  retries the event, and publication/authorization failure remains fatal.
- The fresh required reviewer task `GridRace P2-04B security review`
  (`01a0ddf2-bf23-7a13-85ad-787de8387e8c`, `gpt-5.6-luna` / xhigh) was read-only and
  returned four Medium findings: database credentials in `psql` argv, no fail-closed
  local target guard, concurrent same request ID across matches returning an internal
  error, and inverted submit/deletion lock order around an existing rate row.
- All four findings were accepted. Remediation commit
  `f2d7243` requires explicit `GRIDRACE_LOCAL_INTEGRATION=1`, rejects non-loopback or
  unexpected Supabase ports before client construction, passes the database password
  only through the child environment, and adds forward migration
  `202609260001_submit_guess_lock_order.sql`. One existing per-account advisory lock,
  acquired before receipt/match/rate locks, serializes both cross-match receipt reuse
  and submission versus deletion without a second locking scheme.
- The strengthened harness proves malformed/version/unknown HTTP rejection; retry-safe
  create; member/outsider/anonymous/private/RPC/direct-write boundaries; timing-safe
  Realtime projection; pre-reveal answer/opponent secrecy and reveal; competing joins;
  identical, conflicting, different and concurrent cross-match request IDs;
  finalizer versus sixth guess; deadline equality and a lock wait crossing the
  deadline; deletion versus join/start/submit with a pre-existing rate row; solved,
  lobby, both-account and partial-stage deletion; and rate-counter concurrency.
- Final verification passed on the disposable local stack: Deno format/check/lint;
  remote-looking API and database configurations rejected before I/O; clean reset
  through eight migrations; 266 pgTAP assertions across six files; three-schema lint
  with no errors and only the recorded pre-existing unused/shadow warnings; and the
  harness with 95 real Edge requests, 21 snapshots, maximum snapshot 1569 bytes and
  maximum observed request 891 ms. A second run after resetting to the exact seven
  prior migrations and applying only the new migration passed the same harness with
  maximum snapshot 1568 bytes and request 889 ms; service-only execution grants and
  the account lock were present. The prior 99 passing Edge tests remain applicable
  because remediation changed only SQL and the integration harness.
- Exact maintained invocation:
  `GRIDRACE_LOCAL_INTEGRATION=1 deno run --config supabase/functions/deno.json --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL --allow-net=127.0.0.1,localhost --allow-run=/opt/homebrew/opt/libpq/bin/psql supabase/tests/integration/live_slice_test.ts`
  after loading local `supabase status -o env` values and serving local functions.
  The command and three-schema lint scope are promoted to the runbook after the
  maintainer's BLK-01 checkpoint.
- Backend portions of E1-E3 and E8/E10 are closed with no unresolved material security
  finding. BLK-04 remains the explicit hosted-abuse limitation; client and simulator
  portions remain Phase 3 work. No remote mutation, deployment, push, release or spend
  occurred, and the unrelated 23-file baseline remained byte-identical.

## BLK-01 maintainer checkpoint, 2026-09-26

- Maintainer commit `3763611efe8a62365f71c6b85e9816904f79fdc0`, parent
  `2c6c8a092c0e417b73378bd80eb6d5046d7db89a`, coherently commits the Wiktionary
  corpus/tooling/attribution package and the overlapping runbook, Xcode project and
  `DailyViews.swift` paths. The index is empty; only the previously recorded
  non-overlapping OS/cache/planning scratch files remain untracked.
- Both the checked-in corpus gate and two source-regeneration runs passed from pinned
  intermediates. The accepted set is 25,545 words, preserving all 725 ordered answers
  at projection SHA-256 `31330cbe412018d0ea94991c321d032def17def40e725fcadc90363b11cebda9`;
  final pack SHA-256 is `442fef53b23066ecda6b1048a94c0d562b801398f9934f2928c78121b361d34d`.
- Xcode project/destination discovery passed, 119 iOS tests passed with one expected
  opt-in local-Supabase skip and zero failures, and the Debug clean build passed.
  `Package.resolved` is unchanged. The staged diff check passed before commit.
- With the overlap removed, the exact P2-04B harness invocation and `app_rls` lint
  scope are now promoted into `docs/ENGINEERING_RUNBOOK.md`; P3-01 may edit/register
  its planned iOS paths from the full current HEAD.

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
| DB-06 | Medium | `join_match` is not serialized with deletion for the same account. | Join checks the profile before locking only the match; deletion takes the account lock, enumerates memberships and deletes the profile. A paused join can insert a new auth-linked membership after preparation and strand Auth deletion/receipt retry. Existing race uses a different replacement identity. | Accepted | Forward migration takes the existing account advisory lock before profile/rate/match work; add same-identity barrier race and terminal deletion/replay assertions. | Closed in `80696f9`: deterministic join/delete orderings, Auth/receipt cleanup, 281 pgTAP, three-schema lint, Edge and real integration passed |
| DB-07 | Medium | Cron finalization and multi-match account deletion acquire match locks in different orders. | Expired-round enumeration orders by `ends_at,id`; deletion orders the user's matches by `match_id`, allowing a two-match M2→M1 versus M1→M2 cycle. | Accepted | Forward-migrate the Cron enumerator to match-ID order and add deterministic two-match deletion/finalizer barrier proof. | Closed in `ded5629`: deterministic two-match barrier, canonical convergence, 290 pgTAP, three-schema lint, Edge and real integration passed |
| IOS-01 | High | Snapshot mapper rejected a valid reveal finalized after `ends_at`. | P3-04 two-process relaunches failed after local Cron set `completed_at = transaction_timestamp()`; mapper capped completion at `endsAt`. | Accepted | Validate `startsAt <= completedAt <= serverTime`; keep all other fail-closed checks. | Closed in `1d004c1`: focused 6/6, full 146 with 2 expected skips, controller focused 6/6 |
| IOS-02 | Medium | Failed sixth-guess command returns efficiency `0`, contradicting the frozen command contract and Swift receipt validator. | Migration sets `v_efficiency := 0` for failed and returns it; the client requires null unless solved, so an accepted request can remain durably pending. | Accepted | Forward migration returns null for unsolved command receipts while stored/snapshot efficiency stays zero; prove failed replay, decode and pending-intent clearance. | Closed in `037f9e3`: reset, 276 pgTAP, three-schema lint, Edge, Swift, real integration and controller focused proof passed |
| IOS-03 | Low | Real failed-path XCTest hardcodes answer-eligible `ADORE` and expects six failed guesses. | Seed marks `adore` accepted, active and answer-eligible, so random selection can solve on the first guess. | Accepted | Host harness chooses/passes an accepted non-answer without exposing the answer to client processes; rerun full two-client/Cron proof. | Closed in `f79ce07`: disposable non-answer fixture, two failed clients/12 guesses, full two-client/Cron/relaunch and controller checks passed |
| IOS-04 | Low | Snapshot mapper does not bind countdown/playing states to snapshot `server_time`. | It validates interval and names but accepts countdown at/after start and playing before start or at/after end, contrary to server-derived state. | Accepted | Require countdown `serverTime < startsAt` and playing `startsAt <= serverTime < endsAt`; add boundary-focused decode tests and full iOS proof. | Closed in `0b37297`: boundary mapper proof, focused 8/8, full 149 with two expected skips, clean Debug and controller focused 8/8 passed |
| IOS-05 | Medium | Recovery storage load/clear failures can replay stale commands or strand live play. | `changeAccount` and invalid-match cleanup suppress `clear()` failure; failed load drops the new store, leaving no reset path; storage-unavailable copy can falsely claim no command was sent. | Accepted | Retain controllable store access on load failure; add explicit safe discard/reset; surface failed deletion; use uncertainty-accurate copy; inject load/clear failures and prove relaunch/re-auth behavior. | Closed in `21cbd01`: durable discard/reset, failure-latched account transitions, uncertainty copy, focused 20/20, full 154 with two expected skips, clean Debug and controller focused 20/20 passed |
| IOS-06 | Medium | A throwing recovery-store factory bypasses IOS-05's controllable-store repair. | Construction failure leaves `store == nil`; the UI exposes no discard, and later switch/sign-out treats nil clear as success so a recovered factory can reload and replay stale intent. | Accepted | Keep the transition fail-closed; expose retry/discard once construction recovers; prove durable discard and no stale replay across relaunch/re-auth plus non-advancing switch/sign-out. | Closed in `b476a53`: retry/discard with nil store, failure-latched pending account transition, focused 25/25, full 159 with two expected skips, clean Debug and controller focused 25/25 passed |
| IOS-07 | Medium | Auth reversion to account A does not cancel a failed A-to-B or A-to-sign-out target. | `changeAccount(to:)` returns early on `accountID == userID` before clearing `requestedAccountID`; later retry/discard can still transition to B or nil and may execute B recovery using A's authenticated client. | Accepted | Reconcile same-account Auth updates by canceling the stale target while keeping storage unavailable; prove both switch and sign-out reversion plus safe retry/discard. | Closed in `eef5789`: stale target cancellation, current-account-only retry/discard, focused 27/27, full 161 executed/159 passed/two expected skips, clean Debug and controller focused 27/27 passed |
| IOS-08 | Medium | Mapper rejects a valid reveal when `completed_at > server_time`. | Both values use transaction timestamps captured before row locks; a snapshot can start first, wait behind a later-starting finalizer, then return its committed reveal with the earlier snapshot transaction time. | Accepted | Remove the upper bound, retain `completedAt >= startsAt`, and add a focused lock-order/timestamp-inversion fixture. | Closed in `cffedf0`: inversion fixture, focused mapper 8/8, full 161 executed/159 passed/two expected skips, clean Debug and controller focused 8/8 passed |
| IOS-09 | Medium | Sign-out and confirmed deletion cannot observe failed durable live-recovery cleanup. | `changeAccount(to:)` returns no outcome; coordinator/model continue and may report success after live storage factory/clear failure, while signed-out UI cannot reach Retry/Discard. | Accepted | Propagate/surface cleanup failure through production account composition, preserve reachable remediation, and add sign-out/deletion integration proof without weakening server-deletion semantics. | Closed in `482fa40`: outcome propagation, former-account Daily isolation, reachable retry/discard, sign-out/deletion seam proof, focused 48/48, full 165 executed/163 passed/two expected skips, clean Debug and controller focused 48/48 passed |
| IOS-10 | Medium | Creating a new match while an old saved match pointer exists falsely enters storage failure. | `createMatch()` adds a create intent without clearing `matchID`, producing the recovery-store-invalid match/create combination before any request is sent. | Accepted | Persist `{ matchID: nil, pendingIntent: create }` atomically and restore the prior in-memory recovery state if persistence fails; prove both replacement and rollback. | Closed in `bec7804`: replacement/rollback proof, focused session 30/30, full 169 executed/167 passed/two expected skips, clean Debug and independent controller session 30/30 |
| IOS-11 | Medium | A pending create becomes unreachable after returning Home. | `leaveToHome()` makes the session inactive, `hasSavedMatch` ignores create-only intents, Create/Join no-op while the intent exists, and inactive Live UI has no retry. | Accepted | Treat a create-only pending intent as resumable saved live state; the existing Home Resume route must reopen recovery and retry its original UUID. | Closed in `bec7804`: original-ID Home resume plus saved-match/pending-guess regression proof; focused/full/build and independent controller proof passed |
| IOS-12 | Medium | A delayed successful create/join restarts recovery after returning Home. | `leaveToHome()` sets `isOpen=false` but retains the uncertain command; both success paths call `open()`, which unconditionally sets `isOpen=true` and starts Realtime/snapshot recovery for a hidden room. | Accepted | Preserve the resolved pointer without reopening when the session is closed; mark join open at dispatch and prove delayed create/join success starts no subscription/snapshot/watchdog until explicit Resume. | Closed in `fc0e918`: delayed create/join, Resume-in-flight/Home-again and visible join proof; session 33/33, full 172 executed/170 passed/two expected skips, clean Debug and independent controller 33/33 |
| IOS-13 | Medium | Failed Join with a saved pointer silently recovers the old room and erases the Join error without subscription catch-up. | IOS-12 sets `isOpen=true`; Join retains the old pointer; `beginCommand()` sets trailing refresh; failure finishes by directly fetching that pointer, clearing the error and starting its watchdog without Realtime. | Accepted | Keep old durable pointer until successful Join; failure must not automatically select/recover it. Prove visible denial/no old subscription, snapshot or timer, then explicit Resume subscribe-before-catch-up, plus saved-pointer Join success/navigation siblings. | Closed in `057d18f`: selected-vs-durable recovery, Join failure/success/persistence/navigation/account/background proof; combined session 43/43, full 182 executed/180 passed/two expected skips, clean Debug and independent controller 43/43 |
| IOS-14 | Medium | Create's successful-response storage failure loses the storageUnavailable latch. | `saveResolvedMatch()` restores the durable create intent and sets storageUnavailable when its save fails, but `recoverPendingIntent()` catches that error and `handlePendingError()` maps it to unavailable and can schedule network replay; the new Join error guard has no pending-command counterpart. | Accepted | Preserve the storage failure before generic pending error translation; prove resolved-create save failure, no automatic dispatch while latched, original-ID explicit retry and safe discard, with Join/guess siblings retained. | Closed in `057d18f`: reproduced pre-fix failure; Create/guess/snapshot/Realtime latch proof, original-ID Retry and durable Discard; combined focused/full/build and independent controller proof passed |
| IOS-15 | Medium | Retry after failed Join selects the old saved room and clears the Join error without explicit Resume. | `retry()` clears lastError and promotes isRecoverySelected; unavailable UI uses hasSavedMatch and top banner offers Retry regardless of selection. The failure regression currently omits this real caller. | Accepted | Guard generic Retry before error mutation; expose narrow retry capability to affected UI callers; prove failed saved-pointer Join → Retry preserves denial/no subscription, snapshot or timer, then Home → Resume subscribes before catch-up. Preserve valid pending, selected and storage retries. | Open; fresh 6.1 Sol medium bounded session/UI/test package |
| CI-01 | Low | Hosted database lint omits `app_rls`. | Workflow uses `public,private`; runbook canonical command uses `public,private,app_rls`. | Accepted | Add `app_rls` to the workflow and validate syntax/local equivalent without claiming a hosted pass. | Closed in `7937a78`: one-line diff, YAML parse and local three-schema lint passed; hosted CI unclaimed |
| API-01 | Low | Malformed or ambiguous six-character join codes return typed `match_not_joinable` with HTTP 400. | The frozen contract and Swift mapper require this typed error at 409; the reachable Home input otherwise becomes a generic transport failure. | Accepted | Return 409 for local join-code validation, update focused Edge proof, and confirm the existing typed Swift mapping remains aligned. | Closed in `3647d61`: shared 409 mapping restored, focused join 15/15, full Edge 100/100, Swift mapping 1/1 and controller focused 15/15 passed |
| DOC-01 | Low | Durable authorities still describe the implemented live client and recovery storage as planned or later. | `NOW.md`, architecture, privacy map and product spec lag the completed slice. | Accepted | Reconcile the authorities during controller-owned C-02 after IOS-05, without marking the plan Historical before a fresh R-01 PASS. | Closed: current-state, recovery and remaining-gate language reconciled across all directly stale authorities; plan remains Active pending review |
| DOC-02 | Low | Three current authorities retain superseded phase wording. | The live API header says only P2-04A is implemented, `DECISIONS.md` says review occurs before client reliance, and game rules call the active Cron safety path later. | Accepted | Reconcile the three statements after API-01 without changing product scope or closing the plan. | Closed: implemented contract/security/client proof, current closeout state and local Cron ownership now match code; plan remains Active pending review |
| DOC-03 | Low | `NOW.md` reports pre-IOS-06 iOS evidence totals. | It records full 154 and focused 20/20 after accepted evidence advanced to full 159 and focused 25/25, with IOS-07 still pending. | Accepted | After IOS-07 acceptance, record the actual final focused/full totals and current wording without marking Historical. | Closed: NOW records focused 27/27 and full 161 executed/159 passed/two expected skips/zero failures; plan remains Active pending review |

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

## P3-01 execution and acceptance, 2026-09-26

- Controller checkpoint `8727773` resolved BLK-01 and promoted the proved backend
  harness command. Implementation commit `4b6745a` added the domain-only live model,
  Supabase command service, strict snapshot mapper, shared authenticated client
  composition and Xcode registration.
- The service maps `create-match`, `join-match`, `start-match`, `submit-guess` and
  `match-snapshot`; `SupabaseAccountService.deleteAccount()` remains the sixth frozen
  command boundary. Requests preserve build `1`, lowercase UUIDs and the one-round
  contract. Cancellation propagates; known server errors are trusted only with their
  documented HTTP statuses; malformed, mismatched and gateway responses fail closed.
- The mapper accepts UTC `Z`/`+00:00` timestamps through microseconds and rejects
  unsupported versions/enums, missing required nullable fields, invalid rosters,
  identity/privacy leaks, contradictory timing/state, malformed boards, clue exposure
  before reveal and incomplete reveal data. Domain values contain no Supabase types.
- The local integration harness passed all 95 real Edge requests and 21 snapshots and
  supplied the exact lobby, playing and revealed fixtures checked into the Swift tests.
  Focused transport tests passed: 5 tests, 0 failures. The full clean-derived-data iOS
  run passed: 124 tests, 1 expected opt-in integration skip, 0 failures. The Debug
  simulator build passed. Only pre-existing Swift concurrency and metadata-extraction
  warnings remained; no remote mutation, deployment, spend or release occurred.

## P3-02 execution and acceptance, 2026-09-26

- Starting checkpoint `445717b`; implementation commit `d578ec4` adds the account-
  scoped recovery store, one live session state machine, filtered match Realtime
  signals, shared-client composition and focused tests. The change contains no P3-03
  live UI.
- Create and guess request UUIDs are persisted before dispatch and reused across
  timeout, relaunch and capped 5/10/20/30-second retry. A recovered match pointer is
  persisted before exposure. Disk failure blocks dispatch, account changes clear the
  previous account state and generation guards discard late callbacks.
- Realtime subscribes before catch-up; payloads are refresh signals only. Canonical
  snapshots own state, signals coalesce behind one fetch with a trailing refresh, and
  a five-second foreground watchdog recovers silent loss. Commands and snapshots use
  a ten-second timeout, refresh authentication once, cancel on background, and resume
  on foreground. Display time advances from monotonic uptime; local deadlines lock
  input and request canonical refresh without locally revealing or completing play.
- Focused recovery/session tests passed: 14 tests, 0 failures. The full iOS suite
  passed: 138 tests, 1 expected opt-in integration skip, 0 failures. The
  clean Debug simulator build passed. `git diff --check` passed; Xcode's incidental
  package-resolution rewrite was removed. Only the pre-existing metadata warning
  remained in the final build. No remote mutation, deployment, push, spend or release
  occurred, and the recorded scratch files remain untouched and untracked.

## P3-03 execution and acceptance, 2026-09-26

- Starting checkpoint `20347be`; implementation commit `2117d71` adds the live Home
  entry, account-gated create/join, Resume, private lobby, canonical countdown and
  round, terminal wait, recovery/error states and canonical reveal. It reuses the
  existing session, board, keyboard, avatars, feedback semantics and design tokens;
  views do not evaluate guesses or invent transitions, opponent detail or reveal.
- The UI keeps Daily Classic primary and available signed out. It shows only coarse
  opponent count/state, derives countdown/deadline display from session server time,
  locks uncertain/deadline input, retains rejected drafts and leaves membership intact
  on Home. Reveal requires a canonical revealed snapshot and orders the viewing player
  first, opponents by seat and rows by original sequence.
- Focused presentation proof passed 6 tests covering join-code presentation,
  canonical countdown, creator-only Start, privacy-safe opponent labels, reveal order
  and safe error messages. Code inspection covered Dynamic Type layout, VoiceOver
  labels/focus structure, Reduce Motion stable reveal, Increased Contrast/Bold Text,
  non-color tile semantics, 44-point controls, hardware key handlers and haptics
  preference gating. Runtime assistive-technology and physical-device inspection remain
  later beta evidence and are not claimed here.
- Controller review reproduced a pre-existing P3-02 test race: the test observed the
  fifth create call before the session persisted its resolved match. Repair commit
  `06955d9` waits for the definitive saved-match state without weakening UUID, attempt
  or 5/10/20/30-backoff assertions. The repaired test passed 20/20 iterations; the
  full iOS suite passed 144 tests with one expected opt-in local-Supabase skip and zero
  failures; the clean Debug simulator build passed. `git diff --check`, active-plan,
  lockfile and scratch-baseline checks passed. P3-04 two-process/backend convergence,
  hosted proof and runtime device accessibility are not claimed. No remote mutation,
  push, deployment, spend or release occurred.

## P3-04 integration blocker checkpoint, 2026-09-26

- The first P3-04 task produced and preserved an uncommitted opt-in integration test,
  executable host orchestrator and Xcode registration. Its actual loopback run proved
  the two-process/Auth/Edge/Realtime/watchdog product loop and local scheduled
  finalization with both client processes stopped.
- Both relaunched clients then failed closed on the valid scheduled reveal. Controller
  adjudication traced IOS-01 to the Swift mapper, not PostgreSQL: the server records
  transaction time for early all-terminal or delayed deadline/Cron completion, so a
  valid `completed_at` may precede or follow `ends_at`. Snapshot `server_time` is the
  canonical upper bound.
- Repair commit `1d004c1` now accepts exactly
  `startsAt <= completedAt <= serverTime`, including boundary equality and delayed
  completion after `endsAt`, while rejecting pre-start and future completion and
  preserving every other fail-closed mapper rule. Focused mapper tests passed 6/6;
  the worker full suite passed 146 tests with two expected opt-in skips and zero
  failures; controller focused mapper proof passed 6/6. The three harness paths,
  executable mode, scratch baseline and unrelated state remained byte-identical.
- At this checkpoint P3-04 was not complete: a fresh continuation still had to rerun
  the full integration script from zero, complete E3/E8/E10 plus
  Debug/Release/cleanup proof, then commit the preserved harness only if every required
  gate passed.

## P3-04 completion and acceptance, 2026-09-26

- Continuation task `01a0dfb0-30b2-7110-b855-ca22de0b6c58` preserved the three-path
  lease, added only the required Xcode test registration, opt-in two-client XCTest and
  local host orchestrator, and committed `0fcc113`. Its first attempt found the
  Supabase status assignments were not exported to the Deno child; the task made the
  minimal harness-only `set -a` / `set +a` repair, stopped the disposable stack without
  backup and reran the entire proof from zero.
- E3 passed through the existing backend matrix: 95 real Edge requests, 21 canonical
  snapshots, maximum snapshot 1,567 bytes and maximum request 890 ms, including join,
  receipt, finalizer, deadline/lock, deletion and rate-counter races. E4–E7 passed with
  two distinct simulator processes, containers and Auth users: real Edge and Realtime
  convergence, Realtime-disabled watchdog recovery, no creator forfeit, scheduled
  local pg_cron finalization while both clients were stopped, idempotent repeat
  finalization and both clients relaunching to canonical reveal.
- E8 passed the real deletion, account-isolation, partial-stage, stale-credential and
  lost-response paths plus client storage/account isolation coverage. E10 passed the
  full 146-test suite with two expected opt-in skips and zero failures, clean Debug and
  Release builds, iOS 18.0 floor, release exclusion of local-auth/debug and privileged
  markers, client-container secret scans, shell/project/diff/lockfile checks and clean
  teardown. No GridRace stack, integration process or temporary directory remained;
  only the two pre-existing simulators stayed booted.
- Controller acceptance verified sole parent `38e7309`, exactly the three leased paths,
  the complete harness, empty index, unchanged scratch hashes and one Active plan.
  Independent proof passed shell syntax, project plist validation, the opt-in test's
  default skip and all six focused mapper/transport tests (seven executed, one expected
  skip, zero failures). Local execution used Xcode 27.0 with iOS 26.5 rather than the
  documented Xcode 26.6 prerequisite; this forward toolchain deviation is retained as
  evidence, not treated as hosted, physical-device or distribution proof.

## R-01 review checkpoint, 2026-09-26

- Fresh read-only task `01a0dfc0-a71b-7232-9889-3ef430865778` reviewed the integrated
  `656c6ba..0fcc113` net diff across security, privacy, correctness, recovery,
  deletion, accessibility, operations, tests and final ownership. It made no writes
  and preserved the empty index, one Active plan and scratch baseline.
- IOS-02 is confirmed medium severity. The frozen command contract says
  `efficiency_points` is null unless solved, and the Swift transport rejects any failed
  receipt with non-null efficiency. The current database function both stores and
  returns zero on a failed sixth guess, so the server accepts the request while the
  client fails closed and can retain/retry its durable pending intent. Canonical
  snapshot efficiency zero remains correct; only the command response shape is wrong.
- CI-01 is confirmed low severity. Local evidence linted `public,private,app_rls`, but
  the hosted workflow names only `public,private`; this is evidence drift rather than
  a demonstrated security defect. No other confirmed security or privacy vulnerability
  was found. Stack-stop ownership and uncertain-join retry UX remain reviewer questions,
  not findings without new evidence.
- R-01 requires the serialized IOS-02 and CI-01 repairs plus controller proof, followed
  by a new fresh read-only final review. External/later limitations remain unchanged.

## IOS-02 repair and acceptance, 2026-09-26

- Fresh task `01a0dfc8-1c12-79c2-b10c-79ca6fd1c8c5` committed `037f9e3` across
  exactly seven leased migration/test paths. The forward migration preserves the
  function signature, privileges, locking, idempotency and stored failed-player
  efficiency zero; its sole function-body difference is returning command
  `efficiency_points` only when solved.
- Proof passed a zero-state migration/reset through `202609260002`, 276/276 pgTAP,
  lint of `public,private,app_rls` with only known warnings, Edge format/lint/check and
  100 tests, focused Swift 20/20, the full 148-test iOS suite with two expected opt-in
  skips, clean Debug build and a fresh full two-client integration run. The real run
  covered a failed sixth receipt/replay, stored and snapshot zero, cleared client
  intent/draft, Cron/relaunch, 97 Edge requests, 22 snapshots and client credential
  scans; disposable resources were cleaned.
- Controller acceptance verified parent `a6b5e1e`, the seven-path lease, the complete
  diff, unchanged strict Swift validator and repository baseline. Independent reset,
  276/276 pgTAP and three-schema lint passed; the focused Swift receipt and session
  tests passed 2/2. Package resolution, scratch hashes, index and cleanup remained
  unchanged. The previously recorded Xcode 27.0/iOS 26.5 deviation remains.

## CI-01 repair and acceptance, 2026-09-26

- Fresh task `01a0dfdd-dfd4-7c63-bc0e-da7c0a53d9f1` committed `7937a78` with one
  insertion and one deletion in `.github/workflows/ci.yml`: the database lint schema
  list now matches the runbook's `public,private,app_rls` command while retaining the
  warning and fail-on-error policy.
- Local Ruby/Psych parsing passed. The exact command passed against a confirmed
  unlinked loopback stack with only the recorded pre-existing warnings and no errors;
  the stack was stopped without backup and cleanup passed. No hosted workflow run,
  push, deployment, publication, spend or remote mutation is claimed.
- Controller acceptance verified sole parent `21fd8bd`, exact one-file/one-line scope,
  YAML parsing, authority-command equality, empty index, one Active plan, unchanged
  package resolution and scratch baseline. CI-01 is closed; R-01 requires a fresh
  read-only rerun over both accepted repairs.

## R-01 second review checkpoint, 2026-09-26

- Fresh read-only task `01a0dfe2-8e62-7243-a580-3cc3f6865d44` reviewed the updated
  `656c6ba..7937a78` range without mutations and confirmed IOS-02 and CI-01 closed.
- DB-06 is confirmed medium severity: `join_match` checks the profile, consumes rate
  quota and later inserts membership under the match lock, but unlike create, submit
  and delete it does not take the same account advisory lock. A same-identity join can
  pause before insertion while deletion prepares existing memberships and removes the
  profile, then insert a new auth-linked membership that prevents hard Auth deletion
  and leaves receipt retry stuck. The current deletion/join race uses a third-party
  replacement identity and therefore does not cover this ordering.
- The smallest correction is a forward migration adding the existing account lock
  before profile/rate/match work while preserving the signature, grants and lock order,
  plus an independent same-identity barrier race proving both legal orderings converge
  to completed deletion, stale-bearer denial, no live identity/profile/rate state and
  terminal idempotent receipt replay. No other finding was promoted; sign-out error
  handling and stack-stop ownership remain questions only.

## DB-06 repair and acceptance, 2026-09-26

- Fresh task `01a0dfe9-1d2f-7f81-b833-2d970ab5f35b` committed `80696f9` across
  exactly three leased paths. The forward `join_match` definition is byte-identical to
  its predecessor except for acquiring the established account advisory transaction
  lock after null-user validation and before profile, rate and match work; signature,
  default, security mode, search path, behavior and grants remain unchanged.
- A deterministic real barrier held the match row while join held the account lock,
  proved deletion waited, then verified join completion followed by preparation,
  hard Auth deletion, terminal receipt replay, stale bearer read/write denial and no
  remaining auth-linked membership, profile or rate state. The delete-before-join path
  also rejected the stale join without recreating state. The existing third-party race
  remains covered.
- Worker proof passed zero-state reset through `202609260003`, 281/281 pgTAP,
  three-schema lint with only known warnings, Edge format/lint/check and 100 tests, and
  fresh real integration with 108 Edge requests and 25 snapshots. Controller acceptance
  verified parent `f591cca`, exact scope and every changed line, reproduced the sole
  function delta, and independently passed reset, 281/281 pgTAP and three-schema lint.
  Cleanup, package resolution, one Active plan, empty index and scratch hashes remained
  unchanged. DB-06 is closed; a new read-only R-01 rerun remains required.

## R-01 third review checkpoint, 2026-09-26

- Fresh read-only task `01a0dff3-0a07-7de3-b0d0-9fac61ae5542` reviewed the complete
  `656c6ba..80696f9` range without mutations and confirmed IOS-02, CI-01 and DB-06
  remained closed.
- DB-07 is confirmed medium severity. `private.finalize_expired_rounds` enumerates
  expired rounds by `ends_at,id`, while multi-match deletion acquires match locks by
  `match_id`. For two shared matches whose deadlines sort opposite their IDs, Cron can
  hold M2 and wait on M1 while deletion holds M1 and waits on M2. Aligning the Cron
  enumeration to match-ID order is the smallest shared-lock correction and needs a
  deterministic two-match barrier race.
- IOS-03 is confirmed low severity because `ADORE` is active, accepted and
  answer-eligible, yet the real XCTest submits it six times and requires failure. The
  privileged host must select an accepted non-answer and pass only that guess to client
  processes before the full two-client/Cron proof is rerun.
- IOS-04 is confirmed low severity. The mapper checks the 180-second interval but not
  the canonical snapshot phase boundaries: countdown requires `serverTime < startsAt`,
  while playing requires `startsAt <= serverTime < endsAt`. Focused boundary fixtures
  and focused/full iOS proof are required. Timeout cancellation and stack-stop
  ownership remain questions only; no other finding was promoted.

## DB-07 repair and acceptance, 2026-09-26

- Fresh task `01a0dffc-9c5d-7470-9f8e-88b95f864ad2` committed `ded5629` across
  exactly three leased paths. The forward scheduled-finalizer definition preserves its
  eligibility, count, security, search path, grants and Cron schedule; the functional
  delta replaces deadline order with stable `match_id,round_id` order shared by
  deletion.
- The deterministic real race created two shared matches whose deadline and UUID orders
  opposed each other, held the lower-ID row, and proved finalizer and deletion both
  waited there while the higher-ID row remained unlocked. After release both completed
  without deadlock: two rounds revealed canonically, survivor snapshots anonymized the
  deleted member, hard Auth deletion and receipt replay completed, stale access failed
  and no live identity state remained.
- Worker proof passed reset through `202609260004`, 290/290 pgTAP, three-schema lint,
  Edge format/lint/check and 100 tests, and fresh real integration with 122 requests and
  30 snapshots. Controller acceptance verified the exact parent/scope/every-line diff,
  reproduced the sole ordering delta and independently passed reset, 290/290 pgTAP and
  three-schema lint. Cleanup, index, package resolution, active plan and scratch state
  remained unchanged. DB-07 is closed.

## IOS-03 repair and acceptance, 2026-09-26

- Fresh task `01a0e010-808e-7ec2-9fec-2870a826b064` committed `f79ce07` in exactly
  the two integration-harness paths. After local reset, the privileged host inserts and
  verifies a five-letter active/accepted word with `is_answer=false`, passes only that
  wrong guess through a dedicated client environment value, and deletes/unsets it on
  cleanup. Neither client receives the answer, service credential, database URL or JWT
  secret.
- Both real simulator clients submitted the fixture six times and proved failed state,
  count six, zero canonical efficiency, cleared intent/draft and 12 stored matching
  guesses. The full zero-state script also passed Realtime/watchdog, stopped-client
  Cron, relaunch/reveal, backend 122-request/30-snapshot evidence and credential scans.
  The full iOS suite passed 148 tests with two expected skips and zero failures; clean
  Debug, shell, project, diff and cleanup gates passed.
- Controller acceptance verified parent `95513f9`, exact two-path diff, fixture
  secrecy/non-answer status, environment cleanup and database deletion, then passed
  shell syntax and the opt-out compile/expected skip. Index, package resolution, one
  Active plan and scratch hashes remained unchanged. IOS-03 is closed.

## IOS-04 repair and acceptance, 2026-09-26

- Fresh task `01a0e01c-9485-7982-a1c3-5efcc3b10831` committed `0b37297` in exactly
  `SupabaseLiveMatchService.swift` and `LiveMatchTests.swift`. The shared snapshot
  mapper now accepts countdown only before `startsAt` and playing only from `startsAt`
  through strictly before `endsAt`; the existing delayed-reveal rule is unchanged.
- Boundary fixtures prove valid countdown and playing snapshots, countdown equality
  and later rejection, playing start equality acceptance, and rejection before start
  or at/after end. Worker proof passed 8/8 focused tests, the full iOS suite with 149
  tests executed, two expected skips and zero failures, plus a clean Debug build.
- Controller acceptance verified parent `5babfc8`, the exact two-path diff and every
  changed line, then independently passed the focused 8/8 suite. Index, package
  resolution, one Active plan and scratch hashes remained unchanged. The local Xcode
  27.0/iOS 26.5 forward-toolchain deviation remains accepted and does not prove hosted,
  physical-device or distribution gates. IOS-04 is closed.

## R-01 fourth review checkpoint, 2026-09-26

- Fresh read-only task `01a0e022-6e04-7212-ab1b-c46f1091cff9` reviewed the complete
  `656c6ba..0b37297` implementation range and current net diff at tracker `ee24013`.
  It made no file, index, history, service, simulator or external mutation and returned
  `REQUIRES FIXES` with one medium implementation finding and one low closeout finding.
- IOS-05 is accepted. `changeAccount` resets runtime and ignores failure clearing the
  old account store; failed load retains no store for explicit reset; invalid/expired
  match cleanup also ignores failed durable deletion. Stale pending intent or match state
  can therefore reappear after re-authentication or relaunch, while the UI may falsely
  say no command was sent. Existing proof does not inject session-level load/clear
  failures.
- DOC-01 is accepted for the already-reserved C-02 authority reconciliation: `NOW.md`,
  architecture, privacy map and product spec still label implemented live/recovery
  surfaces as planned or later. The review independently reconfirmed IOS-01..04, CI-01
  and DB-01..07 closed; accepted hosted, distribution, physical-device, provenance,
  moderation/player-count and client-IP limits remain external or later.

## IOS-05 repair and acceptance, 2026-09-26

- Fresh task `01a0e02b-104d-71d3-9ab1-397c318fc6dc` committed `21cbd01` from exact
  parent `2765953` in `LiveMatchSession.swift`, `LiveMatchViews.swift` and
  `LiveMatchSessionTests.swift`; the recovery-store implementation was inspected but
  did not require change.
- The session retains the applicable store before loading, latches storage-unavailable
  state across live actions, exposes an explicit durable recovery discard, and advances
  account switches, sign-out or invalid-match cleanup only after successful deletion.
  Failed deletion remains visible and retryable; successful discard reloads the intended
  account or completes sign-out. UI copy now preserves uncertainty about earlier command
  dispatch and the destructive action has an accurate accessible label.
- Injected store failures cover unreadable recovery, failed discard, account switch and
  sign-out, invalid/expired saved-match cleanup, and relaunch/re-authentication without
  stale replay after successful discard. Worker proof passed focused 20/20, full iOS
  154 tests with two expected integration skips and zero failures, and clean Debug.
  Controller inspected every changed line and independently passed focused 20/20.
  Package resolution was restored after Xcode's incidental rewrite; index, one Active
  plan and scratch hashes remained unchanged. IOS-05 is closed.

## C-02 authority reconciliation, 2026-09-26

- The controller reconciled `NOW.md`, architecture, privacy map, product spec, screen
  flow, game rules and live API contract with the implemented fixed two-player local
  slice and its durable recovery behavior. Planned/pending claims now describe current
  code, including create/join/Resume, canonical snapshots, Realtime convergence,
  shared reveal and explicit failure-preserving recovery discard.
- The authorities continue to separate Daily Classic's local behavior and imported
  personal history from verified competition. Hosted deployment/Cron/backups/retention,
  hosted CI, Apple credentials/distribution, physical-device accessibility, production
  word provenance, trusted hosted client-IP provenance, 2–8 players/multiple rounds,
  moderation, notifications and broader results remain explicitly external or later.
- This reconciliation closes DOC-01 but intentionally leaves the plan Active. A fresh
  read-only R-01 PASS remains mandatory before the separate Historical closeout.

## R-01 fifth review checkpoint, 2026-09-26

- Fresh read-only task `01a0e036-cf15-7ee0-84e6-794e8f19e632` reviewed the complete
  `656c6ba..1628e83` implementation and authority range. It made no file, cache, index,
  history, test, service, simulator or external mutation and returned `REQUIRES FIXES`
  with IOS-06 medium plus API-01 and DOC-02 low.
- IOS-06 is accepted because a throwing store factory fails before IOS-05 retains a
  store. Storage-unavailable then has no discard action, and a later account change can
  treat nil old-store clearing as success; if construction recovers, the old durable
  request can load and replay. Existing injected proof covers load and clear failure,
  not factory construction failure.
- API-01 is accepted because join-match locally returns `match_not_joinable` at 400 for
  malformed or ambiguous codes while both the frozen contract and Swift typed mapper
  require 409. DOC-02 is accepted for the three directly stale phase statements. The
  review reconfirmed IOS-01..04, CI-01 and DB-01..07 closed; IOS-05 and DOC-01 remain
  incomplete only in the newly identified factory and authority branches.

## IOS-06 repair and acceptance, 2026-09-26

- Fresh task `01a0e03d-39eb-7153-8e9e-9cdda15ecc1a` committed `b476a53` from exact
  parent `b7fd79a` in `LiveMatchSession.swift`, `LiveMatchViews.swift` and
  `LiveMatchSessionTests.swift`; `LiveMatchRecoveryStore.swift` required no change.
- A factory failure now keeps storage unavailable with both Retry and Discard even
  before a store exists. Retry reconstructs and loads only by explicit choice; discard
  reconstructs and durably clears without first loading or replaying saved intent.
  Account switch/sign-out retain old ownership and a pending target until old-account
  storage constructs and clears, and live commands remain blocked throughout failure.
- Injected proof covers factory failure, repeated failure, recovery and original-ID
  retry, create/guess discard without replay across relaunch/re-authentication,
  switch/sign-out non-advancement, and construction/clear failures remaining
  controllable. Worker proof passed focused 25/25, full iOS 159 tests with two expected
  integration skips and zero failures, and clean Debug. Controller inspected every
  transition and changed line and independently passed focused 25/25. Xcode's incidental
  package rewrite was removed; index, one Active plan and scratch hashes were unchanged.
  IOS-06 is closed.

## API-01 repair and acceptance, 2026-09-26

- Fresh task `01a0e045-a4a3-70c1-9b1a-aa462d22f615` committed `3647d61` from exact
  parent `5c5954e` in only `join-match/index.ts` and `join-match/index_test.ts`.
  Malformed or ambiguous local join codes now use the shared `match_not_joinable`
  status mapping at HTTP 409; validation still occurs before authentication/RPC and
  retains the same safe error envelope.
- Worker proof passed formatting of the changed files, canonical Edge lint/check,
  focused join tests 15/15, the full Edge suite 100/100 and focused Swift stable-error
  mapping 1/1. Controller inspected the exact three-line net change and independently
  passed focused join tests 15/15. Contract, shared mapping and Swift mapping all agree
  on 409; index, package resolution, one Active plan and scratch hashes stayed clean.
  API-01 is closed.

## DOC-02 authority reconciliation, 2026-09-26

- The controller updated the live API header from the superseded P2-04A-only state to
  the implemented fixed backend/client contract and local security, recovery and
  two-client proof; hosted and broader-MVP gates remain separate.
- `DECISIONS.md` now identifies the active plan as final review/closeout tracking for
  the implemented local slice, while preserving the durable decision and rationale.
  Game rules now identify the exercised local Cron safety path as a current owner.
- Exact stale-text search found no additional linked current-authority occurrence.
  DOC-02 is closed, but this plan remains Active pending a fresh terminal R-01 PASS.

## R-01 sixth review checkpoint, 2026-09-26

- Fresh read-only task `01a0e04a-cf46-7412-a640-edd3968f2d15` reviewed the complete
  `656c6ba..c43cf7e` implementation and authority range. It made no repository, test,
  service, simulator or external mutation and returned `REQUIRES FIXES` with IOS-07
  medium and DOC-03 low.
- IOS-07 is accepted. After failed A-to-B switch or A-to-nil sign-out, the pending
  target remains latched. A subsequent Auth update reporting A returns at the initial
  equality guard without canceling it, so later retry/discard can still load B recovery
  or sign out while the SDK is authenticated as A. Existing IOS-06 proof covers the
  original requested target succeeding, not Auth reverting to the current account.
- DOC-03 is accepted because `NOW.md` still reports full 154 and focused 20/20 rather
  than the later accepted 159 and 25/25; it will use actual IOS-07 final evidence. The
  review reconfirmed DB-01..07, IOS-01..05, API-01, CI-01 and DOC-01/02 closed; IOS-06
  is incomplete only in the newly identified reversion branch.

## IOS-07 repair and acceptance, 2026-09-26

- Fresh task `01a0e050-fa3a-7731-ac70-16ccf4fdccc3` committed `eef5789` from exact
  parent `b4080ae` in only `LiveMatchSession.swift` and `LiveMatchSessionTests.swift`.
- When Auth reports retained account A after a failed A-to-B switch or A-to-nil
  sign-out, the session now cancels only the stale requested target and latch. It
  preserves account A, storage-unavailable state, store/recovery/runtime state and
  command blocking; subsequent explicit Retry or Discard acts only on A.
- Focused proof covers switch reversion with failed then successful A retry, B storage
  untouched and no B request under A, plus sign-out reversion with failed then
  successful A discard and clean relaunch. Worker proof passed focused 27/27, full iOS
  161 executed with 159 passed, two expected integration skips and zero failures, and
  clean Debug. Controller inspected every changed line and independently passed focused
  27/27. Xcode's incidental package rewrite was removed; index, one Active plan and
  scratch hashes stayed unchanged. IOS-07 is closed.

## DOC-03 authority reconciliation, 2026-09-26

- `NOW.md` now records the actual accepted IOS-07 evidence: focused recovery/session
  27/27 and full iOS 161 executed, 159 passed, two expected opt-in integration skips
  and zero failures. Adjacent current-work and remaining-gate wording remains accurate.
- DOC-03 is closed. This plan intentionally remains Active until a new fresh R-01
  returns terminal `PASS`; Historical closeout remains a separate controller commit.

## R-01 seventh review checkpoint, 2026-09-26

- Fresh read-only task `01a0e058-3a39-7820-a31d-f36a6646dc8d` reviewed the complete
  `656c6ba..8654333` implementation and authority range. It made no repository or
  external mutation and returned `REQUIRES FIXES` with IOS-08 and IOS-09 medium.
- IOS-08 is accepted. Both snapshot `server_time` and finalizer `completed_at` are
  PostgreSQL transaction timestamps captured before row locks. A snapshot transaction
  may begin first, wait behind a later-starting finalizer, then observe its committed
  reveal with `completed_at` later than the snapshot transaction's `server_time`; the
  client currently rejects that canonical state and stops automatic recovery.
- IOS-09 is accepted. Live-account changes keep durable storage failure internal, while
  production sign-out and confirmed deletion continue clearing account state/local
  caches and can report success. Pending guess, match code or request identity can remain
  on disk without a reachable signed-out recovery action. Existing session tests do not
  cover this production coordinator/model seam.
- The review reconfirmed IOS-02..07, API-01, CI-01, DB-01..07 and DOC-01..03 closed;
  IOS-01 and IOS-05 reopen only in these newly identified branches. Timeout cancellation
  remains a hypothesis rather than a finding.

## IOS-08 repair and acceptance, 2026-09-26

- Fresh task `01a0e05f-3171-70b2-8db2-d46607a0aa6d` committed `cffedf0` from exact
  parent `dca946f` in only `SupabaseLiveMatchService.swift` and `LiveMatchTests.swift`.
- The shared mapper no longer assumes revealed `completedAt` is at or before the
  snapshot transaction's `serverTime`. It retains completion presence/nullability,
  `completedAt >= startsAt`, delayed finalization and every other fail-closed mapper
  rule. The focused fixture accepts a lock-order/timestamp inversion while continuing
  to reject completion before the round start.
- Worker proof passed focused mapper 8/8, full iOS 161 executed with 159 passed, two
  expected integration skips and zero failures, and clean Debug. Controller inspected
  every changed line and independently passed focused 8/8. Xcode's incidental package
  rewrite was removed; index, one Active plan and scratch hashes stayed unchanged.
  IOS-08 is closed.

## IOS-09 repair and acceptance, 2026-09-26

- Fresh task `01a0e065-cefb-7811-994d-9b898c03d239` committed `482fa40` from exact
  parent `7363b37` in the live session, Daily account coordinator, account model,
  Daily Home presentation and their existing focused test files.
- Account transitions now return a durable-cleanup outcome. Production sign-out and
  confirmed deletion always isolate former-account Daily/account presentation, surface
  incomplete live cleanup accurately, and leave a signed-out Home route to retry or
  discard the saved live recovery before another race. Confirmed remote deletion is
  never retried merely because local cleanup remains incomplete.
- Worker proof passed focused 48/48, full iOS 165 executed with 163 passed, two expected
  integration skips and zero failures, and clean Debug. Controller inspected every
  changed line and independently passed the same focused 48/48. Xcode's incidental
  package rewrite was removed; index, one Active plan and scratch paths stayed
  unchanged. IOS-09 is closed.

## C-02 final authority/evidence refresh, 2026-09-26

- `fd6ca0b` updates `NOW.md` to the accepted full iOS 165/163/two-skip result and
  focused account/recovery 48/48 result. Architecture, privacy, live API and screen-flow
  authorities now describe former-account isolation, partial local cleanup semantics
  and the signed-out retry/discard route.
- The plan remains the sole Active tracker. Hosted, distribution, physical-device,
  retention and broader-MVP limitations remain explicit; no remote mutation, paid
  commitment or external completion claim was introduced. A fresh terminal R-01 is
  still required before Historical closeout.

## R-01 eighth review checkpoint, 2026-09-26

- Fresh read-only task `01a0e073-3ccf-7120-8f25-9b9d640b6f70` reviewed
  `656c6ba..46ea818` and returned `REQUIRES FIXES` with IOS-10 and IOS-11 medium.
  It made no repository or external mutation.
- IOS-10 is accepted: starting create from Home while an old match pointer remains
  persists an invalid match/create pair, so the command never dispatches and storage
  is falsely reported unavailable. Replacement and persistence-failure rollback need
  focused proof.
- IOS-11 is accepted: a create-only pending intent is not represented as saved live
  state, so leaving Live removes every non-destructive route back to its original
  request UUID. The existing Home Resume route must cover this state.
- The review reconfirmed DB-01..07, IOS-01..09, API-01, CI-01 and DOC-01..03 closed
  and found no additional material security/privacy issue. The plan remains Active;
  another fresh terminal R-01 PASS is mandatory after the serialized repair.

## IOS-10/11 repair and acceptance, 2026-10-02

- At maintainer direction the old controller and worker were stopped. Main thread
  `01a0c7dc-0dea-7691-bf87-d143051132e2` took integration ownership and dispatched
  fresh worker `01a0fb5e-fb94-7b00-a3ff-837216098b22` using `gpt-6.1-sol` / medium.
  It inherited the interrupted two-file patch, remained inside the session/test write
  lease, and made no Git or tracking changes. Its single callback released that lease.
- Implementation `bec7804`, parent `91e1d96`, replaces the entire recovery record
  before create dispatch and restores the previous record on persistence failure.
  Saved live state includes a create-only intent; the existing Home Resume action
  reuses `beginRecovery()` and the original UUID. Saved-match and pending-guess
  recovery retain subscribe-before-catch-up behavior.
- The interrupted focused failure was reproduced and traced to an existing test
  waiting for `hasSavedMatch`, which now becomes true before create acknowledgement.
  Waiting for the expected `savedMatchID` preserves the persistence/order assertions.
  Four regressions prove replacement, no-dispatch rollback, original-ID pending-create
  Home resume, and saved-match/pending-guess Home resume.
- Worker verification passed focused session 30/30, full iOS 169 executed with 167
  passed, two expected opt-in skips and zero failures, plus a clean Debug build.
  The main controller audited the complete diff and independently passed session
  30/30. Logs remain under `/tmp/gridrace-ios1011-resumed-*`; the independent result
  is `/tmp/GridRaceDerivedData-test/Logs/Test/Test-GridRace-2026.10.02_02-53-57--0400.xcresult`.
- The two opt-in backend/two-process tests were skipped, not rerun or claimed passed
  in this package. Prior actual local integration remains recorded separately. The
  accepted Xcode 27.0/iOS 26.5 deviation and external/later gates remain unchanged.
- Main controller removed only the inherited Xcode `swift-issue-reporting` lockfile
  addition; `Package.resolved` again matches committed SHA-256
  `581444159ef3909b1abf75a577ef56f3ba66bb404faf275968daf78ace294f4c`.
  All six scratch hashes match the worker's start baseline; the implementation commit
  contains exactly the two owned files, with an empty index afterward.
- This checkpoint refreshes NOW's totals and the screen-flow authority for pending
  create/guess Home resume. The plan stays Active pending a fresh terminal R-01.

## R-01 ninth review and IOS-12 adjudication, 2026-10-02

- Fresh configured read-only reviewer `01a0fb66-0821-78a3-9c3f-61b7d0711779`
  (`gpt-daybreak-blue-latest` / high) reviewed `656c6ba..1e1f287` and returned
  `REQUIRES FIXES` with IOS-12 medium/high confidence. It made no writes or execution
  mutations and preserved HEAD, index, lockfile and scratch hashes.
- Main controller traced both success callers of `open(matchID:)`, `leaveToHome()`,
  request/Realtime guards and Home navigation. The finding is accepted: preserving
  an in-flight command is correct for uncertainty, but its later success must not
  override the user's closed session and restart hidden network recovery.
- IOS-10/11 and all previous closures remain intact. No additional confirmed
  security/privacy, database, account-cleanup or rule-parity defect was established.
  Existing worker/controller proof was inspected, not rerun by the reviewer.
- Next is a fresh 6.1 Sol medium session/test worker. The main controller retains
  Git/tracking ownership and requires a single callback here even if blocked; stopped
  old tasks remain stopped. Historical closeout remains forbidden on this verdict.

## IOS-12 repair and acceptance, 2026-10-02

- Fresh worker `01a0fb6c-7bca-7701-9054-16fdc9c6b8ed` used `gpt-6.1-sol` / medium
  with only the session/test write lease. It reported one callback, released its
  lease and made no Git/tracking changes. Main controller committed `fc0e918` from
  parent `aaf7f81` after a full owned-diff audit and independent focused proof.
- Join now marks the session open at dispatch. The shared successful-response
  `open()` path checks the current open state instead of reopening unconditionally.
  Both create and join still persist successful match resolution before that check;
  Home stops hidden subscription/snapshot/watchdog work without treating cancellation
  or navigation as server rollback.
- Gate-driven regressions hold create/join success across Home, prove the pointer is
  persisted with no hidden recovery, and then explicitly Resume to subscribe before
  canonical refresh/watchdog. They also cover create Resume while its original
  request runs, another Home before completion, no duplicate dispatch, and normal
  visible join. Existing IOS-01..11 session/account/storage tests remain green.
- Worker proof passed session 33/33, full iOS 172 executed/170 passed/two expected
  opt-in skips/zero failures, and a clean Debug build. Logs are
  `/tmp/gridrace-ios12-focused.log`, `/tmp/gridrace-ios12-full.log` and
  `/tmp/gridrace-ios12-build.log`. Main controller independently passed session
  33/33 at `/tmp/GridRaceDerivedData-test/Logs/Test/Test-GridRace-2026.10.02_03-05-59--0400.xcresult`.
- Package.resolved and all six scratch hashes remained unchanged, with no package
  cleanup necessary. The implementation contains exactly the two owned files;
  whitespace checks passed and the index was empty after commit. No remote mutation,
  service/reset operations or distribution activity occurred.
- NOW and screen-flow now reflect the accepted repair and exact latest totals.
  Earlier real integration remains separately recorded; its two opt-in tests were
  skipped in this package, and external/device/toolchain limitations remain explicit.
  Terminal closure acceptance remains before Historical closeout.

## Terminal closure review and IOS-13 adjudication, 2026-10-02

- Read-only task `01a0fb70-9d50-7943-bd38-51088f229a6e` retained prior full-range
  review evidence and freshly inspected `1e1f287..e33d46e`. It confirmed IOS-12's
  delayed-success closure but returned IOS-13 medium/high confidence as a regression
  in the saved-pointer Join-error sibling. No execution or repository mutation occurred.
- Main controller traced Home's simultaneous Resume/Join controls, Join dispatch and
  error handling, trailing refresh, snapshot application and timer scheduling. With
  an old pointer, failure now fetches that room directly and can clear the Join error;
  it bypasses subscribe-before-catch-up. IOS-13 is accepted; the old pointer itself
  must remain durable until Join succeeds, while automatic target selection must not.
- The new package owns the complete existing session Join transition and regression
  tests, including saved-pointer failure, success and navigation. No new UI direction,
  persistence schema, dependency or generalized state model is approved. All prior
  closures remain retained, with Historical closeout gated on terminal PASS.

## IOS-13 verification and IOS-14 controller finding, 2026-10-02

- Worker `01a0fb75-975c-7401-885c-abe8edb1e313` (`gpt-6.1-sol` / medium) released
  the session/test lease with an uncommitted patch. It separates a durable pointer
  from selected recovery, preserves failed Join errors without automatic old-room
  recovery, and covers saved-pointer success/failure, Resume-in-flight, Home-again,
  persistence failure, account switch and background completion.
- Worker proof passed session 39/39, full iOS 178 executed/176 passed/two expected
  opt-in skips/zero failures, and clean Debug. Main controller audited the full
  two-file diff and independently passed session 39/39 at
  `/tmp/GridRaceDerivedData-test/Logs/Test/Test-GridRace-2026.10.02_03-18-19--0400.xcresult`.
  Logs and final baseline are `/tmp/gridrace-ios13-*`. No implementation commit
  has been made; the complete verified patch is preserved for the next writer.
- Main audit traced both callers of `saveResolvedMatch()` and the new Join storage
  error guard. Create's sibling catch still calls `handlePendingError()` after failed
  resolution persistence; that handler overwrites storageUnavailable and schedules
  pending replay. IOS-14 is accepted by source trace and receives a fresh bounded
  reproduction/repair package before combined integration. No new product decision,
  persisted schema or dependency is needed.

## IOS-13/14 combined integration and acceptance, 2026-10-02

- Fresh worker `01a0fb7c-c688-7673-a4ba-874c3c6752fa` (`gpt-6.1-sol` / medium)
  preserved the verified IOS-13 patch and completed the storage boundary inside only
  the same session/test paths. It reproduced IOS-14 before repair: one test failed
  with eight assertions showing unavailable instead of storageUnavailable, missing
  Retry/Discard, retry scheduling and an extra Create after foreground.
- Six targeted guards preserve storage failure across pending-error translation,
  recovery entry, Realtime events, snapshot application/error and trailing fetch.
  Tests cover original-ID Create acknowledgement failure, repeated explicit Retry,
  eventual persisted resolution and subscribe-before-catch-up, failed/successful
  durable Discard without re-auth/relaunch replay, accepted/rejected guess clearance,
  Realtime/foreground signals and in-flight snapshot success/error with queued refresh.
- An initial expanded test used the same injected duration for retry and stale
  refresh, causing unintended snapshot repetition. Distinct timeout/stale/retry
  durations repaired the test harness without weakening assertions. The completed
  worker focused suite passed 43/43, full iOS 182 executed/180 passed/two expected
  opt-in skips/zero failures, and clean Debug passed. Proof is in
  `/tmp/gridrace-ios14-focused-complete.log`, `/tmp/gridrace-ios14-full.log`,
  `/tmp/gridrace-ios14-build.log` and the corresponding recorded xcresults.
- Main controller audited the inherited IOS-13 diff, incremental IOS-14 diff and
  combined production delta, checked the staged files against audited SHA-256 values,
  and independently passed session 43/43 at
  `/tmp/GridRaceDerivedData-test/Logs/Test/Test-GridRace-2026.10.02_03-26-30--0400.xcresult`.
  Implementation commit `057d18f`, parent `0175c5a`, contains exactly the two files.
- Selection remains runtime-only: durable saved state is not automatically the target
  of a failed Join. Storage failure blocks automatic work until explicit remediation;
  no persisted schema, dependency or UI direction changed. The screen-flow authority
  and NOW now record this behavior and the current proof totals.
- All six scratch hashes and Package.resolved remained unchanged; index is empty after
  commit and exactly one plan is Active. Worker callbacks released their leases before
  controller writes. No remote/service/reset/distribution action occurred; the two
  opt-in integration tests were skipped, and previous real integration and all later
  hosted/device/toolchain limitations remain separately scoped. Terminal acceptance
  remains before Historical closeout.

## Terminal closure review and IOS-15 adjudication, 2026-10-02

- Read-only reviewer `01a0fb85-c78e-7852-89b6-08a96b769fc7` returned
  REQUIRES FIXES, medium/high-confidence IOS-15. IOS-14 is closed; prior accepted
  closures and whole-range review evidence remain retained.
- Controller traced `retry()` and all live UI callers: the no-snapshot unavailable
  view and top banner can offer recovery of an old pointer after Join denial. Generic
  Retry clears the denial and selects that pointer, contrary to explicit Resume
  ownership. IOS-15 is accepted; the screen-flow invariant remains unchanged.
- The bounded lease expands from session/tests to the actual UI Retry caller and its
  existing tests, with no persisted Join code/schema, dependency, new test framework or
  unrelated UI direction. Controller owns tracking, staging and commits; this worker
  must not mutate Git. Release the lease and attempt exactly one callback even blocked.
- Baseline `bfbec74011f55a9cba55d1fb468ad3575995bdcd` has an empty index and no
  tracked modifications; all six unrelated scratch hashes and Package.resolved match
  the prior acceptance. Exactly this plan remains Active. No writer is active before
  the new serial dispatch; old stopped tasks remain stopped.

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
| `656c6ba docs(plan): record reviewed planning checkpoint` | Record the accepted planning content checkpoint and keep this plan Active for implementation | Complete |
| `dd8230a docs(plan): establish live-slice worker execution` | Record the single-writer lease protocol, unrelated baseline and P2-04A dispatch checkpoint | Complete |
| `a80f282 feat(backend): make live creation retry-safe` | Implement strict retry-safe creation, Boolean deleted-member identity and focused database/Edge proof | Complete; accepted by controller |
| `e4462c0 docs(plan): record P2-04A completion` | Record P2-04A evidence and advance the backend dependency | Complete |
| `68bd474 test(backend): prove live slice integration` | Add actual local Auth/Edge/RLS/Realtime/deletion and concurrency proof | Complete; security-reviewed |
| `f2d7243 fix(backend): close live slice security findings` | Fail closed to local fixtures and serialize submission receipts/deletion with one account lock | Complete; all accepted review findings verified |
| `2c6c8a0 docs(plan): close P2-04B security checkpoint` | Record accepted backend evidence, review adjudication and BLK-02 resolution | Complete |
| `3763611 feat(dictionary): integrate Wiktionary guess corpus` | Commit the previously overlapping dictionary, Daily attribution, Xcode and runbook package | Complete; BLK-01 resolved |
| `8727773 docs(plan): unblock live transport implementation` | Record BLK-01 evidence, promote the live harness command and release P3-01 | Complete |
| `4b6745a feat(live): add match transport boundary` | Add domain models, strict command/snapshot mapping and real-fixture Swift proof | Complete |
| `445717b docs(plan): record P3-01 completion` | Record accepted transport evidence and release P3-02 | Complete |
| `d578ec4 feat(live): add session recovery` | Add durable live session recovery, Realtime refresh signals and focused proof | Complete |
| `20347be docs(plan): record P3-02 completion` | Record accepted session evidence and release P3-03 | Complete |
| `2117d71 feat(live): add live match UI` | Add the complete server-backed live UI and focused presentation proof | Complete |
| `06955d9 test(live): stabilize recovery backoff proof` | Synchronize the P3-02 retry proof on persisted match state | Complete; controller-verified |
| `709ed36 docs(plan): record P3-03 completion` | Record accepted live UI evidence and release P3-04 | Complete |
| `1d004c1 fix(live): accept delayed canonical reveal` | Accept server-valid early or delayed completion bounded by start and snapshot server time | Complete; IOS-01 closed |
| `38e7309 docs(plan): record P3-04 mapper repair` | Record IOS-01 acceptance and the preserved continuation lease | Complete |
| `0fcc113 test(live): prove two-client integration` | Add the opt-in two-client harness and complete the local P3-04 evidence gates | Complete; controller-verified |
| `a6b5e1e docs(plan): record R-01 findings` | Record the first final-review findings and serialized remediation | Complete |
| `037f9e3 fix(live): align failed guess receipt` | Return null failed command efficiency while preserving canonical stored/snapshot zero | Complete; IOS-02 closed |
| `21fd8bd docs(plan): record IOS-02 completion` | Record accepted failed-receipt proof and release CI-01 | Complete |
| `7937a78 ci(backend): lint app rls schema` | Align hosted database lint scope with the canonical three-schema command | Complete; CI-01 closed, hosted run unclaimed |
| `244e74d docs(plan): record CI-01 completion` | Record accepted CI evidence and release the fresh R-01 rerun | Complete |
| `f591cca docs(plan): record DB-06 finding` | Record the second final-review finding and bounded repair contract | Complete |
| `80696f9 fix(backend): serialize join with deletion` | Add account-lock serialization and deterministic same-identity deletion race proof | Complete; DB-06 closed |
| `69acd05 docs(plan): record DB-06 completion` | Record accepted lock-order proof and release the next R-01 rerun | Complete |
| `ec1d1b8 docs(plan): record final review findings` | Record DB-07, IOS-03 and IOS-04 with serialized remediation | Complete |
| `ded5629 fix(backend): align finalizer lock order` | Align scheduled finalization with deletion and prove the two-match race | Complete; DB-07 closed |
| `95513f9 docs(plan): record DB-07 completion` | Record accepted finalizer ordering proof and release IOS-03 | Complete |
| `f79ce07 test(live): make failed path deterministic` | Use a disposable accepted non-answer fixture for the real failed-client proof | Complete; IOS-03 closed |
| `5babfc8 docs(plan): record IOS-03 completion` | Record accepted deterministic failed-path proof and release IOS-04 | Complete |
| `0b37297 fix(live): validate snapshot phase time` | Bind countdown and playing snapshots to canonical server-time phase windows | Complete; IOS-04 closed |
| `ee24013 docs(plan): record IOS-04 completion` | Record accepted phase-window proof and release the fresh R-01 rerun | Complete |
| `2765953 docs(plan): record recovery review finding` | Record IOS-05 and DOC-01 from the fourth final-review pass | Complete |
| `21cbd01 fix(live): make recovery discard durable` | Preserve and explicitly clear uncertain recovery state without silent durable failure | Complete; IOS-05 closed |
| `93f7d01 docs(plan): record IOS-05 completion` | Record accepted durable-recovery proof and release DOC-01 reconciliation | Complete |
| `1628e83 docs: reconcile live slice authorities` | Reconcile implemented local live behavior and preserve external/later gates | Complete; DOC-01 closed pending final review |
| `b7fd79a docs(plan): record final review findings` | Record IOS-06, API-01 and DOC-02 with serialized remediation | Complete |
| `b476a53 fix(live): recover from storage factory failures` | Keep storage construction, discard and account transitions fail-closed and controllable | Complete; IOS-06 closed |
| `5c5954e docs(plan): record IOS-06 completion` | Record accepted factory-failure recovery proof and release API-01 | Complete |
| `3647d61 fix(edge): align join validation status` | Return typed local join-code denial with the frozen HTTP 409 mapping | Complete; API-01 closed |
| `387d704 docs(plan): record API-01 completion` | Record accepted join-status proof and release DOC-02 reconciliation | Complete |
| `c43cf7e docs: reconcile final live authorities` | Reconcile implemented contract, closeout state and local Cron ownership | Complete; DOC-02 closed pending final review |
| `b4080ae docs(plan): record account reversion finding` | Record IOS-07 and DOC-03 with serialized remediation | Complete |
| `eef5789 fix(live): cancel reverted account transition` | Cancel stale account targets without escaping fail-closed current-account storage | Complete; IOS-07 closed |
| `bc53605 docs(plan): record IOS-07 completion` | Record accepted Auth-reversion proof and release final evidence reconciliation | Complete |
| `8654333 docs: update final live evidence` | Record current IOS-07 focused/full iOS evidence while keeping the plan Active | Complete; DOC-03 closed pending final review |
| `dca946f docs(plan): record final recovery findings` | Record IOS-08 and IOS-09 with serialized remediation | Complete |
| `cffedf0 fix(live): accept reveal timestamp inversion` | Accept canonical reveal completion later than an earlier blocked snapshot transaction time | Complete; IOS-08 closed |
| `7363b37 docs(plan): record IOS-08 completion` | Record accepted timestamp-inversion proof and release IOS-09 | Complete |
| `482fa40 fix(account): preserve failed live cleanup` | Surface account cleanup failure while preserving privacy isolation and reachable recovery controls | Complete; IOS-09 closed |
| `1b9ff50 docs(plan): record IOS-09 completion` | Record independent IOS-09 acceptance and release final authority refresh | Complete |
| `fd6ca0b docs: update final account cleanup evidence` | Reconcile final iOS totals and account-cleanup behavior across current authorities | Complete; terminal R-01 remains |
| `46ea818 docs(plan): release terminal review` | Release the eighth fresh read-only R-01 over the complete accepted range | Complete; returned IOS-10/11 |
| `b6051ee chore: update worker roles` | Maintainer updates repository model/role configuration | Complete; preserved |
| `91e1d96 docs(plan): record pending-create findings` | Record accepted IOS-10/11 and the bounded repair | Complete |
| `bec7804 fix(live): resume pending create from home` | Replace saved pointer atomically and resume uncertain create with its original UUID | Complete; IOS-10/11 accepted |
| `1e1f287 docs: record pending-create repair evidence` | Record IOS-10/11 acceptance, current verification and worker model switch | Complete; reviewed, returned IOS-12 |
| `aaf7f81 docs(plan): record hidden recovery finding` | Record IOS-12 and the bounded lifecycle repair | Complete |
| `fc0e918 fix(live): keep recovery closed after home` | Persist late create/join success without reopening hidden recovery | Complete; IOS-12 accepted |
| `e33d46e docs: record Home lifecycle repair evidence` | Record IOS-12 acceptance and exact session/full/build evidence | Complete; closure reviewed, returned IOS-13 |
| `4800552 docs(plan): record saved-match join finding` | Record IOS-13 and complete Join-transition repair scope | Complete |
| `0175c5a docs(plan): record create storage latch finding` | Record IOS-13 proof and the IOS-14 shared error boundary | Complete |
| `057d18f fix(live): preserve selected recovery and storage failures` | Integrate IOS-13/14 with complete affected lifecycle/storage proof | Complete; accepted by main controller |
| `bfbec74 docs: record selection and storage recovery proof` | Reconcile current authorities and exact combined verification evidence | Complete; closure returned IOS-15 |

Planning tracker checkpoint `656c6ba` records content checkpoint `2a8ac34`. Staging was limited
to the eight task-owned documents; the staged whitespace check passed and staged
content matched the reviewed diff. Product implementation and P3-04 local integration
are complete; R-01 and closeout remain, and this plan stays Active.

Implementation-controller bootstrap checkpoint: **this commit** records the current
repository/baseline evidence, the maintainer-authorized single-writer Git exception,
the callback lease protocol, corrected model pairing, and P2-04A as the next unit.

## Milestone exit and checkpoint policy

Phase 2 baseline evidence remains recorded above. **Phase 2 exits only after P2-04A
and P2-04B pass the backend portions of E1–E3 and E8/E10 with no unresolved
material security finding.**
That backend exit gate passed on 2026-09-26. BLK-01 is resolved; Phase 3 remains
subject to its own client/simulator evidence, which Phase 2 completion does not satisfy.

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

- [x] P2-04A/B contract/security gates complete with exact evidence.
- [x] P3 client, real transport, concurrency and two-client gates complete.
- [ ] Implementation review findings adjudicated; accepted fixes verified.
- [ ] Authorities and newly proved commands current; beta limitations explicit.
- [ ] Task-owned changes committed; unrelated work unchanged and unstaged by this task.
- [ ] No remote mutation, push, paid service or unapproved data operation occurred.
- [ ] At live-slice completion only: mark Historical, identify last content checkpoint,
      label tracker closeout “this commit,” and report its SHA.

Stop for more than one active plan, unexpected overlap, a rule/privacy/security/API
choice beyond accepted direction, a proposed paid commitment, or a high-risk gate
that cannot be resolved in scope. Continue independent safe work where possible.
