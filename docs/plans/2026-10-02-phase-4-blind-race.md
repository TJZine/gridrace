Status: Active
Scope: GridRace Phase 4 private two-player multi-round Blind Race
Owner: GridRace Phase 4 kickoff controller, 01a0fc7c-88b3-7f80-9631-504b4baffc45
Started: 2026-10-02
Last updated: 2026-10-03

# Phase 4 Blind Race

## Current checkpoint and authority gate

Human accepted D3 and D4 on 2026-10-02 with “use both recs.” The agreed UI
is the native 1/3/5 Create selector (3 selected), Round N of M, existing reveals
with canonical standings and creator-only Start next, and final standings/Home/
prior reveals. After either account deletes, any already-started round completes
under existing forfeit/deadline rules; preserve anonymized reveals and freeze all
unstarted remaining rounds with an explicit incomplete-match presentation.

Independent read-only P4-PR completed with two concrete planning findings. The
controller traced both, accepted them and corrected the contract matrix and account
test lease below. Targeted planning closure is complete; there is no unresolved
material product or contract choice. The accepted-plan checkpoint is
`3a01d9ab7772dbfa158d7ffcba2df13b7958694c`, committed before product writes.
P4-B backend checkpoint is `ba65af9c41c1a940758010a39d7038ef81a3225e`. Worker
leases/processes are released, controller audit and independent backend proof
passed, and all 21 owned files were committed with six unrelated files preserved.
Controller prepared build-2 account/live composition defaults and Debug/Staging/
Release app build settings for the integrated P4-C/I checkpoint. First P4-C
returned BLOCKED_PARTIAL after an automatic missing-transitive-pin lockfile change.
Controller adjudicated that concrete requirement and proved frozen native package
resolution. After the human resumed on 2026-10-03, fresh P4-C3 finished the
preserved client seam, proved latest focused/full/build gates and released all
leases. Controller source audit, exact fixture/preservation inspection and independent
87/87 focused proof passed. P4-C/I is checkpointed at `335f210a5a287ada4994657e8f574ceeff4dcb7b`; substantive UI,
real independent-client product proof and final review remain required. This plan
stays Active.

## Repository snapshot and authority

- Branch: `dev/classic-mode`; HEAD: `7e413aca62c58e555d768f37fe8ed22a6778b4fd`.
- Phase 2/3 plan is Historical. No Active plan existed before this file.
- Tracked tree and index were clean. Six unrelated untracked files are preserved:
  `.DS_Store`, `docs/.DS_Store`, `.codex/cache/review-context.json`,
  `.codex/cache/review-context.md`,
  `docs/plans/GridRace-dictionary-finalize-and-integrate.md`, and
  `docs/plans/gridrace-corpus-independent-checks.json`.
- Exact byte baseline is outside the repository at
  `/Users/tristan/.codex/automations/gridrace-phase-4-kickoff/unrelated-baseline.json`.
  Verify it at lease transfers/closeout; never stage, reset, stash, or overwrite it.
- Read AGENTS, engineering runbook, NOW, product/rules/architecture/privacy/flow,
  live API, durable decisions, TODO, repository roles and Phase 2/3 closure evidence.
  DECISIONS/TODO/NOW now distinguish the Historical Phase 2/3 proof from accepted
  Phase 4 scope and pending implementation; later scope remains preserved.
- Prior proof is historical evidence, not a fresh Phase 4 run: 290 pgTAP assertions,
  100 Edge tests, full iOS 183 executed/181 passed/two expected opt-in skips,
  clean Debug build and real two-client local integration. Reuse meaningful harnesses.

## Outcome and decisions

Complete anytime private Blind Race for exactly two authenticated players: manual code, 1/3/5 rounds (default 3), creator-started three-second countdowns, 180-second server deadlines, randomly selected private nonrepeating answers, preserved reveals, SQL round/cumulative/final placement, and canonical recovery through every boundary and final. Daily remains the primary signed-out/offline action. Preserve tutorial, accounts and one-round behavior. Exclude wider rosters, rematch, competitive history, links, notifications, moderation persistence, presence, generic engine, remote/hosted operations, push, spend and distribution. Do not infer cancellation, creator transfer or automatic advancement.

| Decision | State | Proposal and bounded consequence |
| --- | --- | --- |
| D1 scope | Accepted | Implement the entire accepted two-player multi-round outcome; no new scope approval. |
| D2 absent creator | Accepted | Nonfinal reveal waits indefinitely for the creator; no presence inference, transfer or automatic start. Lobby expiry applies only before the first countdown. |
| D3 presentation | Accepted by human, 2026-10-02 | Native 1/3/5 picker with 3 selected, Round N of M, existing reveal followed by canonical standings and creator-only Start next, final standings/Home/prior reveals. Preserve existing palette, semantic order and accessible reveal. The human said “use both recs”; no repeated layout approval within this direction. |
| D4 deletion | Accepted by human, 2026-10-02 | Finish/reveal an already-started round, anonymize retained survivor data, prohibit new countdowns after either identity is deleted, and show incomplete match/Home when configured rounds remain. No guest-only continuation, host transfer, cancellation command or automatic advance. |
| D5 technical contracts | Accepted by controller after P4-PR adjudication | Round-targeted Start, bounded v1 migration, snapshot v2, revealed-only SQL standings and recovery rules below. Controller owns acceptance. |

D3/D4 settle the remaining material product decisions. The technical representation below includes the accepted independent-review corrections; incomplete denotes the accepted deletion boundary and never finalizes unplayed rounds or invents final match results. Ordinary absence preserves waiting behavior.

## Existing owners and consequential evidence

All paths in this plan are relative to /Users/tristan/Software/gridrace unless explicitly absolute.

- Authority: AGENTS.md; docs/ENGINEERING_RUNBOOK.md (ownership, canon, High-risk proof, review and explicit staging); sole Active docs/plans/2026-10-02-phase-4-blind-race.md. Read product-spec, game-rules, architecture, privacy-data-map, screen-flow, live-api-contract, NOW, DECISIONS, TODO and .agents/rules/general-guidelines.md.
- Historical docs/plans/2026-08-30-phase-2-3-live-slice.md: contract/lock graph at lines 163–234; E1–E11 at 259–301; real two-process/Cron evidence at 717–746; terminal closeout at 1356–1382. Counts in NOW are historical: 290 pgTAP, 100 Edge, iOS 183 executed/181 passed/two opt-in skips, clean Debug, real 122-request/30-snapshot backend proof. None was rerun here.
- Foundation migration 202608300001 owns rounds/player_rounds/guesses/private secrets and microsecond scoring; finalize_round at 577 always completes the match; start_match at 889 targets round 1. Round/count/current/guess-receipt constraints all fix 1. Seats already enforce two. Grants/RLS near 1460 enforce roster reads, own guesses before reveal, public revealed answers only, no direct game writes.
- Effective replacements, not foundation alone: 202609220001 owns create receipts/create_match, snapshot and delete_account; 202609260002 is the latest submit_guess (including 202609260001 lock-order repair and failed-receipt null efficiency); 202609260003 is latest join_match; 202609260004 is latest finalize_expired_rounds ordering by match ID then round ID. 202609040001 owns revision trigger, column grants and Realtime projection. 202608310002 owns deletion receipts and preparation/Auth/completion retry. Preserve all repairs.
- Edge existing six commands: create/start reject extra keys; submit hardcodes round 1. _shared/command.ts owns safe messages/status mapping/auth/body bounds. No new endpoint or general command bus is needed.
- Swift LiveMatch.swift drops configured/current/round numbers; SupabaseLiveMatchService.swift hardcodes build 1 and round 1 and requires reveal iff completed. LiveMatchRecoveryStore.swift persists v1 create UUID or guess match/UUID/word, without original build/count/round. LiveMatchSession.swift owns one account-bound command and coalesced snapshot, generations/epochs, disk failure handling, pending intent resolution and monotonic display time; shouldRecover currently stops at every reveal.
- DailyViews.swift owns live Create/Join entry; LiveMatchViews.swift owns lobby/countdown/round/reveal, stable self-first board order and accessibility. Reuse reveal and keyboard evidence, never a local evaluator for live acceptance. DailyAccountCoordinator owns composition/account handoffs; SupabaseAccountService shares its SDK Auth client with live transport; SupabaseMatchRealtimeService already emits signals only.
- Existing proof owners: supabase/tests/database/*.sql; supabase/tests/integration/live_slice_test.ts with independent SQL barrier races and actual Auth/Edge/Realtime; ios/GridRaceTests/LiveMatchTests.swift, LiveMatchSessionTests.swift and LiveMatchViewTests.swift with existing controllable services/storage/clocks; LiveMatchIntegrationTests.swift and scripts/run_live_match_integration.sh run separate simulators/containers.
- Product/architecture/flow still describe the implemented fixed slice; DECISIONS/TODO/NOW distinguish the accepted pending Phase 4 expansion. Controller reconciles implemented behavior and commands at content checkpoints. Do not alter historical evidence.
- Read .codex/agents/planner.toml, worker.toml and reviewer.toml: planner Sol/high, fresh workers Sol/medium, read-only reviewer daybreak/high. No subdelegation is needed for this preparation.

## Observable acceptance and ownership

A1: Create selection is durable before dispatch; 1/3/5 matches retain exactly two seats and immutable configuration. Manual Join and first-countdown roster lock retain existing denial/reconnect behavior.
A2: Creator alone starts a specified immutable round; nonfinal reveal waits for explicit Start next. Duplicated/concurrent/stale Start cannot start any different round. Same configured answer never repeats; no answer is selected for an unstarted future round.
A3: Same rules/limits/deadline equality and round competition placement; cumulative/final ranking uses rounds solved descending, efficiency descending, exact total solved microseconds ascending. Display rounding never decides placement.
A4: Before current reveal, snapshots/direct reads/Realtime contain no current answer or opponent words/feedback/keyboard/exact times. Prior reveals remain readable; cumulative standings include revealed rounds only. No future-round secret/clue projection.
A5: Retry preserves original match, round, word, UUID and successful receipt across later starts/finals. Original create payload is replayed. Delayed responses and snapshots cannot restore an old board, draft, reveal selection or clock.
A6: Reconnect/relaunch/foreground/Home/Resume reconstruct canonical current state, reveals and standings. Nonfinal reveal recovers later advancement with all signals dropped. Background/hidden/final/incomplete sessions do no watchdog work; final explicit Resume still fetches once.
A7: Server snapshot/submit/Cron share idempotent finalization. Both apps closed still reaches reveal; Cron never starts the next round.
A8: Accepted D4 behavior, all-round irreversible survivor anonymization, full Auth/profile/Daily deletion and existing deletion-receipt/storage isolation guarantees.
A9: D3 presentation and existing VoiceOver, Dynamic Type, Reduce Motion, Contrast/Bold Text, hardware input, non-color feedback/hit targets/haptic preference. Daily/tutorial/account regressions stay intact.

Database canonical: match configuration/current/status/block reason/revision, immutable started round timestamps/secrets, accepted rows, player outcomes, round placements. SQL owns aggregate standings over finalized rows in the locked snapshot transaction (no client aggregation and no extra totals table). Snapshot-derived: countdown versus playing and revealed-only cumulative totals. Client-derived: monotonic display clock, draft, selected prior reveal, animation/focus and request UI. Realtime payloads are signals only.

## Accepted commands and local compatibility

Use existing POST/data/error envelopes, 2048-byte exact-key validation, authentication and safe typed errors.

- Current Swift Join/Start/snapshot use the current build (2 by default) and require snapshot version 2, including legacy floor-1 rooms. Legacy create/guess intent replay uses explicit original build1 arguments; that does not authorize accepting v1 snapshots in the current client. No parallel Swift v1 mapper is needed.
- New current app build 2; CURRENT_PROJECT_VERSION = 2 in Debug/Staging/Release, with SupabaseAccountService/SupabaseLiveMatchService request values synchronized. Existing matches remain floor 1; new build-2 creations have floor 2, including one-round. Keep mode classic_live_v1; snapshot version changes independently to 2.
- build >= 2 create-match: {client_build, request_id, round_count}, round_count exactly integer 1/3/5; no implicit API default (UI defaults 3). Return {match_id}. Receipt compares actor+UUID and original build+count; duplicate resolves before quota, including started/completed/expired room. Changed payload is request_conflict. Reuse account advisory serialization.
- build >= 2 start-match: {client_build, match_id, round_number}, integer 1...5. Return existing {match_id}; receipt truth is the target's persisted start, so no extra request UUID/table. Authorize active profile, build, membership and creator before any success. Lock match, target/prior round as applicable. If target has already started, success without writes even if it is revealed, a later round is current, or match is final. If not started: target 1 requires full unexpired lobby; target current_round+1 requires current revealed, within configured count and accepted D4 guard. All other targets -> round_not_active; blocked not-yet-started target -> match_incomplete. A captured target is never replaced by current+1 during retry. Concurrent target N starts once and shares timestamps/answer. New first-start timestamps use one transaction time; only first Start sets match.started_at.
- submit-guess keeps {client_build, match_id, round_number, request_id, guess} and existing receipt response exactly. Permit integers 1...5 at Edge, enforce configured/existing/current started round in SQL. Resolve identical successful actor/UUID receipt before current-round/final-state/rate checks, as today; changed match/round/normalized word -> request_conflict. No receipt for rejected guesses. New unreceipted submissions to an old revealed round -> round_already_finished; pending/future/out-of-config -> round_not_active. Deadline equality still rejects and finalizes in the same transaction.
- join-match, match-snapshot and delete-account request shapes unchanged. Snapshot responds with v2 for build >= 2, v1 for build 1 compatible one-round rooms. Initial lobby expiry never prevents rostered recovery or later starts.
- Add invalid_match_configuration (400, "Choose 1, 3, or 5 rounds.") and match_incomplete (409, "This match cannot continue because a player account was deleted.") to SQL safe error helper, Edge map, Swift enum/status/presentation tests. Retain existing error meanings, unknown failures as transport uncertainty, conflict/rate-limit as explicit original-intent Retry/Discard.
- Compatibility is for actual local existing rooms/intents, not a hosted rollout: build-1 create exact old keys means one round; build-1 Start exact old keys permanently means target 1 and retains old completed error behavior; build-1 submit still only round 1. Deny build 1 against floor-2 rooms. Keep legacy RPC create_match(uuid,integer,text,uuid) and start_match(uuid,integer,uuid) as bounded one-round entries; new service-only overloads add smallint count/target. Revoke PUBLIC/anon/authenticated execution on every new signature; retain no obsolete broad grants. Snapshot shares shaping, with the old v1 response branch restricted to legacy one-round rooms.
- Existing create_requests backfill round_count=1; new comparison includes it. New v2 client retries migrated pending create with original build=1/count=1/UUID and old shape, not build2/count3. Guess receipt JSON remains unchanged; original server_time is not freshness or clock calibration.

Frozen Swift service signatures: createMatch(requestID:roundCount:clientBuild:), startMatch(id:roundNumber:), submitGuess(matchID:roundNumber:requestID:guess:clientBuild:); Join/snapshot retain signatures. Explicit original build arguments are only for durable create/guess replay, new intents capture build2. The service selects exact legacy create encoding for saved build1; snapshots always use current build2. Add roundCount/currentRound to LiveMatch, number to LiveRound, revision/revealedRounds/standings to LiveMatchSnapshot. Reuse existing feature/service/storage owners.

## Snapshot v2 and disclosure

Retain all existing required fields/nullability, member Boolean identity, stable seats and player board/result shape. New required fields:

```text
version: 2
match: existing fields plus revision: positive Int64,
       started_at: RFC3339 UTC | null,
       completed_at: RFC3339 UTC | null,
       terminal_reason: null | "account_deleted"
       status: "lobby" | "in_progress" | "completed" | "incomplete"
round: existing RoundDTO, number == match.current_round
revealed_rounds: [RoundDTO] // unique contiguous ascending 1...last revealed
standings: null | {
  through_round: integer 1...round_count,
  is_final: Boolean,
  players: [{
    member_id: UUID,
    rounds_solved: integer 0...through_round,
    efficiency_points: integer 0...6*through_round,
    total_solve_duration_ms: nonnegative integer,
    placement: integer 1...2
  }] // stable member-seat order, canonical SQL placement
}
```

Lobby: current_round=1, round pending, no players/times/answer; revealed_rounds=[], standings=null. At nonfinal reveal current round remains N, status=in_progress, history contains rounds 1...N including identical current reveal; standings.through_round=N, is_final=false. Starting N+1 changes current_round and round to that countdown; history/standings stay through N. Completed iff configured final round revealed; history 1...round_count, standings.is_final=true. Incomplete after a nonfinal reveal has partial standings is_final=false, terminal_reason=account_deleted and no future countdown. During a deletion-blocked active round status remains in_progress with terminal_reason until reveal.

Preserve own current board/result visibility and null opponent clue/scoring fields before reveal. Aggregate only rounds.state='revealed', not solved outcomes from the current unrevealed round. Compute total milliseconds by flooring SUM(solve_duration_us)/1000 once; SQL rank uses exact SUM microseconds. Stable seat order is transport/presentation order, never a ranking tie-breaker. Exact ties share placement. No client recomputation from truncated rows.

Mapper fails closed on malformed required/null/enum/count/identity/timestamps/history/standings, unsupported version, noncontiguous or future history, current/history mismatch, duplicate IDs, pre-reveal opponent leakage, final mismatch or premature final totals. Preserve delayed Cron completion and lock-wait transaction timestamp cases covered in LiveMatchTests; do not tighten timestamps to response-delivery order. Preserve valid countdown forfeits. Validate SQL placements structurally, not by recreating their comparator from milliseconds.

### Canonical match status, timestamps and deletion reason

Snapshot v2 adds required nullable `match.started_at` and `match.completed_at`
(RFC 3339 UTC), alongside required nullable `match.terminal_reason`. These are
canonical match fields; v1 shaping stays unchanged. `completed_at` retains its
existing meaning: actual completion after the configured final round, never a
partial/incomplete result.

| Match state | started_at | completed_at | terminal_reason | Current round / condition |
| --- | --- | --- | --- | --- |
| lobby | null | null | null | Round 1 pending; no deleted slot retained in a lobby. |
| in_progress, ordinary | nonnull | null | null | Current round started; may be nonfinal reveal waiting for creator. |
| in_progress, deletion-blocked | nonnull | null | account_deleted | Current round N is active, N < round_count, at least one member is deleted, and all future starts are blocked. |
| incomplete | nonnull | null | account_deleted | Current round N is revealed, N < round_count, at least one member is deleted; standings partial, is_final=false. |
| completed | nonnull | nonnull | null | Configured final round revealed; completed_at equals that round's completed_at; standings is_final=true. |

During the configured final round, account deletion still anonymizes/forfeits only
eligible current state, but no future round exists to block: retain in_progress
with terminal_reason null and let ordinary finalization complete the match. Deletion
after completed never changes status, match completed_at, standings or reason. During
an active nonfinal round deletion sets the block reason in its transaction; that
round finishes normally and its finalizer transitions to incomplete without setting
match completed_at. Deletion between nonfinal rounds transitions directly from
in_progress/revealed to incomplete. An already incomplete match remains incomplete
when the other identity is deleted. No unplayed round receives a result or answer.

Migration replaces the old status/timestamp CHECK with this matrix, preserving
actual-completion timestamp meaning. Cross-row round/member guards are enforced by
transactional commands under match/round locks. Snapshot mapping rejects impossible
state/timestamp/reason/round/deleted-member combinations and rejects mismatched
final match/round completion times. Preserve existing delayed-finalizer and countdown-
forfeit timestamp behavior; do not compare completion to snapshot transaction time
or assume completion must follow the scheduled round start.

The existing trigger increments revision once per canonical match-row UPDATE in the
same transaction; deletion plus finalization may produce more than one increment.
New reason/status changes and all-round anonymization advance that signal atomically;
identical receipts, already-started target retries, repeated finalization and repeat
deletion preparation make no canonical UPDATE and leave revision unchanged. The
snapshot reports the final revision after any finalization. Never publish updated_at
or introduce a new exact-action timestamp for incomplete matches. Existing safe
started_at/completed_at columns retain their grants/publication meanings; the new
reason is returned only in roster-authorized v2 snapshots. Its new table column
remains service-only: no authenticated SELECT grant or Realtime publication entry.
Existing status and revision signals suffice for canonical refresh.

Required proof: positive and negative SQL CHECK/command cases for every matrix row;
host/guest deletion while active nonfinal, between nonfinal rounds, during final,
after completed, and after already incomplete; concurrent deletion/Start/finalizer
in both orders; exact timestamps/reason/status, idempotent revision behavior, and
matching valid/invalid Swift mapper and lifecycle recovery fixtures. Include both
one-round and 3/5-round cases; no historical count substitutes for this proof.

## SQL migration, deletion, locking and revision

One forward migration (supabase/migrations/202610020001_blind_race_multiround.sql); never edit applied history. Widen match round_count to 1/3/5, current_round to 1...round_count, rounds/guess_requests round numbers to 1...5; preserve two-seat, uniqueness, result and timing constraints. Create configured pending round rows atomically; private secrets/player rows are created only when that target starts. Select random active answer excluding all previously selected match secrets under the match lock. Fail internal_error without partial transition if eligible pool exhausted. Existing one-round fixtures require no ID/answer/result changes.

finalize_round retains exact round comparator and reveals atomically. Nonfinal reveal leaves match in_progress; final reveal completes; accepted D4 blocked nonfinal reveal becomes incomplete. Standings are transactionally consistent SQL aggregation of immutable revealed results under the same match lock, requiring no persisted aggregate cache. Repeated finalization performs no update. All canonical mutations update match/revision in the same transaction; idempotent Start/create/guess/join/snapshot repeats do not. Snapshot includes revision after finalization, never pre-finalizer revision.

Maintain account advisory lock (hashtextextended(user UUID,1)) before account/profile checks and actor receipt/rate work where needed, especially Start versus deletion; recheck profile after acquiring the lock, including submit's existing precheck. Preserve join/create/guess/deletion serialization. Multi-match deletion and Cron enumerate match IDs ascending (202609260004), then rounds ascending, players stable seat order. Under a match lock there can be at most one active round; finalizers must never acquire an actor lock after taking game locks. Audit receipt/rate row ordering and independent barrier races, not just a nominal lock list. Do not regress 202609260001–004 repairs.

Accepted D4 policy: lobby host/guest deletion stays unchanged. After start, detach/anonymize the member across all reveals; forfeit only their current nonterminal player, never rewrite solved/failed/timedOut outcomes. Mark subsequent advancement blocked. If current nonfinal active, set the reason and finish under ordinary all-terminal/deadline rules; if between nonfinal rounds, become incomplete immediately. In the configured final round there is no block reason and finalization completes normally, as defined in the matrix. Final configured reveal still completes normally; deletion after completion never changes results/status. Both deleted removes all reversible mappings; preserve established survivor-retention behavior, no new history/retention rule. Preparation/Auth/completion receipts and stale-bearer denial remain unchanged.

The new block reason is snapshot-only/service-readable, while existing status
reads/publication remain clue-free; keep aggregate fields out of authenticated base-table column grants/Realtime. Keep matches.updated_at/member auth/selected_at/private schemas hidden. Direct revealed round/guess access remains roster-authorized; future pending rows carry no answer/players. No new public result table is needed.

Forward proof must precede any destructive reset: inventory actual local data/linked refs and prove fixture disposability. If current rooms are user data, stop reset and preserve them; obtain a controller-selected disposable local target. On a confirmed disposable baseline fixture, retain legacy lobby/active/revealed rooms, create receipts and accepted-guess receipts, apply the migration forward and assert exact old identities/results/grants plus new contracts. P4-B proved npx --no-install supabase migration up --local against pinned CLI 2.116.0 with legacy fixtures; controller promoted it to runbook canon with the disposable-only precondition. Do not substitute a clean reset for forward proof. Then clean reset/test/lint on confirmed disposable local state. A migration failure rolls back its transaction; after applied product changes use a reviewed forward repair, not destructive reset of retained rooms or down-migration guesswork.

## Recovery-file and session boundaries

Keep the existing protected account path live-recovery-v1.json to avoid stranding actual files; formatVersion=2 denotes the new payload. Decode format1 explicitly: create becomes original build1/count1/UUID; guess becomes original match/round1/build1/word/UUID. A pointer alone remains the same pointer. Atomically save v2 before any migrated intent dispatch. Reject unknown/corrupt/inconsistent versions without deleting data; explicit existing Retry/Discard and cleanup remain available. New create includes count/build/UUID; new guess includes match/round/build/word/UUID. Save no board/answer/opponent/credential; no new queue or history. Sign-out/deletion clears this same file; migration save/read/clear failures preserve storageUnavailable and account isolation.

Start captures its target at the button intent boundary. Uncertain Start fetches a snapshot; retries of that captured action use the same target. No durable Start queue is necessary: relaunch fetches current state and a new deliberate Start is a new user action. Disable duplicate Start while a command/pending guess/storage recovery is unresolved.

Retain one command/one fetch, trailing refresh, Auth refresh once, 10s timeout and 5/10/20/30s backoff. Add presentation/match-selection generations (or extend existing epoch guards) for Home, background, Resume and room switches: cancel cannot alone prevent delayed application. Durable command completion may save the current-account pointer/receipt after Home, but cannot open hidden UI or restart recovery. On canonical round advance clear only the old round's draft/animation selection and render new board atomically. An old pending guess remains original and blocks new input until receipt or definitive error is durably resolved. Old success clears that exact pending identity and requests current snapshot; old error never repopulates the new round's draft or overwrites new errors. Snapshot alone cannot acknowledge a request.

Use revision to reject lower canonical mutation state within the same match/account, plus existing command epochs and selection generations; server_time is not a revision. Equal revision may legitimately change countdown to playing with time, so apply serialized fresh snapshots using existing clock rules; never freeze effective phase merely because revision is equal. Replayed receipts never calibrate display time.

Nonfinal revealed in_progress must retain subscription and bounded watchdog while open/foreground, including a surviving creator waiting for ordinary absent guest and a guest waiting for creator. Completion/incomplete stops ordinary recovery only after pending receipt resolution; explicit Resume starts a fresh catch-up even for finals, then stops. Reveals/history are fetched snapshots, not local history. A selected prior reveal is display-only; it cannot supply guess/start targets. New current countdown exits old reveal presentation; pending/D4-blocked/current statuses remain canonical.

## Sequential packages and leases

Product writes require independent plan review/adjudication and controller accepted-plan commit first. D3/D4 are accepted. Workers read broadly, never modify Git/tracking/cache; controller owns contracts, composition, integration, authorities, process scheduling, staging and commits. Fresh Sol/medium workers, configured reviewer daybreak/high. Lease one package at a time; shared paths may appear in later leases only after release.

| Package | Exact writes | Prerequisite / checkpoint and proof |
| --- | --- | --- |
| P4-PR / controller acceptance | Reviewer repository READ ONLY. Controller writes docs/plans/2026-10-02-phase-4-blind-race.md, docs/live-api-contract.md, docs/DECISIONS.md, docs/TODO.md, docs/NOW.md | D3/D4 recorded; freeze full contract/matrix, adjudicate one independent plan review, commit accepted plan before product writes. Authority owner cannot be delegated. |
| P4-B backend/Edge | supabase/migrations/202610020001_blind_race_multiround.sql; supabase/tests/database/blind_race_multiround.sql; supabase/functions/_shared/command.ts and command_test.ts; create-match/index.ts and index_test.ts; start-match/index.ts and index_test.ts; submit-guess/index.ts and index_test.ts; match-snapshot/index_test.ts; supabase/tests/integration/live_slice_test.ts (all function paths under supabase/functions/) | Accepted-plan commit and sole database/process lease. Existing legacy tests retained. Deliver forward/reset/RLS/secrecy/scoring/Start/receipt/deletion/lock proof and captured real v2 fixtures. Edge unchanged Join/delete handlers reused; stop before expanding lease if their behavior needs code changes. Controller integrates backend before Swift. |
| P4-C Swift contract/session/storage | ios/GridRace/App/LiveMatch.swift, SupabaseLiveMatchService.swift, LiveMatchRecoveryStore.swift, LiveMatchSession.swift; ios/GridRace/App/LiveMatchViews.swift (only new error-case exhaustiveness/compatibility needed to keep this package buildable); ios/GridRaceTests/LiveMatchTests.swift, LiveMatchSessionTests.swift, LiveMatchViewTests.swift, LiveMatchIntegrationTests.swift; ios/GridRaceTests/AccountTests.swift (only recovery fixture/buildability adaptation and v1/v2 sign-out/deletion/account-isolation cleanup proof) | Backend contract/security checkpoint, captured fixtures. LiveMatchViewTests/LiveMatchIntegrationTests and the view error mapping are only protocol/fixture/exhaustiveness adaptation for buildability in this package; substantive UI/integration behavior gets later leases. Session createMatch retains a default-3 entry until P4-U supplies the explicit selector value; transport protocol callers are adapted inside this lease. Prove v1 migration, v2 validation, every transition/pending/delayed/lifecycle/storage/account boundary and existing repairs. |
| P4-I controller composition | ios/GridRace/App/SupabaseAccountService.swift; ios/GridRace/App/DailyAccountCoordinator.swift only if necessary; ios/GridRace.xcodeproj/project.pbxproj; ios/GridRace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved (only adjudicated missing swift-issue-reporting pin) | Serialized with P4-C integration: build2 composition and target settings; adjust project only if required. No new file registration/dependency expected. Controller owns shared assembly, workers return necessary changes as evidence. |
| P4-U UI | ios/GridRace/App/DailyViews.swift (only live Create selector/action and related live entry presentation); ios/GridRace/App/LiveMatchViews.swift; ios/GridRaceTests/LiveMatchViewTests.swift | Agreed D3/D4 plus integrated client contracts. Reuse existing UI/reveal; add picker, labels, standings, Start next, prior reveals and incomplete/final routes. Focused tests and accessibility inspection; no Daily redesign. |
| P4-C4 pending-Start presentation seam | ios/GridRace/App/LiveMatchSession.swift; ios/GridRaceTests/LiveMatchSessionTests.swift | Controller-traced UI-SESSION-UNRESOLVED-START. Expose read-only observable hasPendingStart from existing pendingStart; prove unchanged snapshots/Home/Resume and original-target Retry. No command/storage/contract behavior change. Release before fresh P4-U2. |
| P4-V integration/proof | scripts/run_live_match_integration.sh; ios/GridRaceTests/LiveMatchIntegrationTests.swift; supabase/tests/integration/live_slice_test.ts | Integrated B/C/I/U, released earlier leases. Extend existing independent two-client product/Cron/relaunch harness for all counts, nonfinal boundaries, secrecy and pending retries. Controller sole database/simulator process coordinator runs full gates; mocks supplement. Controller adds proved host/candidate command to runbook only after success. |
| P4-R final review | Repository READ ONLY | One fresh independent reviewer over integrated owned diff/contracts/proof/risk. Findings require reproduction or concrete invariant trace; controller records disposition. |
| P4-F repair, conditional | Exact finding-owned file list set by controller | Bounded accepted repairs, affected proof rerun; controller targeted closure, no recursive whole reviews. |
| P4-X authorities/closeout | Controller: docs/product-spec.md, docs/game-rules.md, docs/architecture.md, docs/privacy-data-map.md, docs/screen-flow.md, docs/live-api-contract.md, docs/DECISIONS.md, docs/TODO.md, docs/NOW.md, docs/ENGINEERING_RUNBOOK.md, sole Active plan | Current authorities updated alongside checkpoints, not postponed as justification for stale contracts. Full scope/proof/review/repairs complete before Historical closeout. Explicit owned staging/conventional commits, six unrelated byte baselines unchanged. |

All paths are exact leases, not directory-wide permission. Shared DTOs/API/error signatures are controller-frozen and worker changes cannot redefine them. P4-C and P4-I can be one integrated sequential checkpoint, avoiding a deliberately broken build. Database/simulator/host server/reset processes never overlap other packages. No new files/config/CI changes outside these leases without controller adjudication of a concrete need.

## Verification matrix and exact command families

P4-B backend evidence is recorded below; Swift/UI/product integration rows remain pending. Record named scenario/output/fixture/toolchain, not counts alone.

| Acceptance | Existing harness and required scenarios |
| --- | --- |
| A1/A2 | pgTAP new file + real live_slice_test.ts: 1/3/5 and default UI; invalid counts/builds/keys; full two seats; outsider/guest Start denial; target1..5 concurrent duplicates; old revealed/completed target retry after later reveal never advances; future/skipped/stale actions; exhaustion rollback; unique answers and absent future secrets. |
| A3 | pgTAP + real SQL fixtures: all counts; each solve efficiency; unsolved fewer-count ties across failed/timeout/forfeit; round comparator; match solved-count/points/exact SUM microseconds; two durations equal in displayed ms but distinct placement, exact ties and stable seats; sum-floor vs sum-of-floors; final idempotency. |
| A4 | Existing RLS identities/grants tests + live gateway/direct PostgREST/Realtime: anon/unrelated/rostered/deleted/service; private secrets/RPC/direct writes denied; opponent current time/word/feedback null before reveal; history readable; future absent; revealed-only totals while next round active; no action timestamp or aggregate leakage in base/publication. |
| A5/A6 | LiveMatchTests/SessionTests existing scripted continuations/clocks/storage + independent clients: legacy pending create/guess migration and failed atomic save; same payload/UUID retries through multiple rounds/final; conflict and rate limits retained; old rejected/accepted replies after advance/Home/account switch; lower/equal revisions, precommand/trailing snapshot, lost/duplicate/reordered signals, handshake recovery, hidden tasks stopped, storage load/save/clear/factory failures and explicit discard; real relaunch at nonfinal reveal/countdown/play/final. |
| A7 | live_slice_test.ts independent transaction barriers + run_live_match_integration.sh: last/sixth guess versus finalizer/deletion; deadline equality/countdown and lock-wait timestamps; both apps stopped, actual local Cron job-run success reveals N without starting N+1; reopen/start next/final; repeated finalizer no mutations. |
| A8 | Existing deletion SQL/Edge/account harnesses extended: host/guest lobby, countdown/play/solved/at nonfinal reveal/at later start/final/completed; accepted D4 matrix and v1/v2 AccountTests cleanup; all reveal identities anonymized; both removed, no recoverable auth mapping; stale JWT denial; deletion versus Start/submit/join/Cron across two matches in opposite deadline order, bounded barrier completion; lost preparation/Auth/completion responses; Daily/account/live cleanup failure remains recoverable. |
| A9 | LiveMatchViewTests plus simulator inspection of every new state: largest Dynamic Type, VoiceOver semantic focus/order, nonanimated reveal, contrast/Bold Text/non-color feedback, 44pt targets, hardware keyboard/haptic preference; all existing Daily, tutorial, account and shared-vector tests. Physical-device proof remains an external gate. |

Runbook command families (forward migration now promoted after P4-B proof):

```bash
python3 scripts/check_word_pack.py --checked-in-only
npm run check:seed
deno fmt --check rules/typescript
deno lint rules/typescript
deno check rules/typescript/evaluator.ts rules/typescript/evaluator_test.ts
deno test --allow-read rules/typescript/evaluator_test.ts
deno fmt --check supabase/functions
deno lint supabase/functions
deno check --config supabase/functions/deno.json \
  supabase/functions/_shared/command.ts \
  supabase/functions/_shared/command_test.ts \
  supabase/functions/create-match/index.ts \
  supabase/functions/create-match/index_test.ts \
  supabase/functions/join-match/index.ts \
  supabase/functions/join-match/index_test.ts \
  supabase/functions/start-match/index.ts \
  supabase/functions/start-match/index_test.ts \
  supabase/functions/submit-guess/index.ts \
  supabase/functions/submit-guess/index_test.ts \
  supabase/functions/match-snapshot/index.ts \
  supabase/functions/match-snapshot/index_test.ts \
  supabase/functions/delete-account/index.ts \
  supabase/functions/delete-account/index_test.ts
deno test --config supabase/functions/deno.json supabase/functions/
npx --no-install supabase --version
npx --no-install supabase start
# ONLY after disposability proof and separate forward-migration proof:
npx --no-install supabase db reset
npx --no-install supabase test db
npx --no-install supabase db lint --local --schema public,private,app_rls --level warning --fail-on error
# Separate owned server terminal:
npx --no-install supabase functions serve --log-level error
# Obtain local status environment using the runbook's exported set -a/eval/set +a sequence.
GRIDRACE_LOCAL_INTEGRATION=1 deno run \
  --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost \
  --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts
xcodebuild -project ios/GridRace.xcodeproj -list
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -showdestinations
```

Use the rediscovered UUID in the runbook's full xcodebuild test and Debug clean build commands, with /tmp/GridRaceDerivedData-test and /tmp/GridRaceDerivedData-build respectively; record the literal expanded command. Focused owner tests may add -only-testing:GridRaceTests/LiveMatchTests, LiveMatchSessionTests or LiveMatchViewTests to the same test invocation, but full suite and clean Debug remain required. Shared Swift vectors run in the full suite. Source word-pack regeneration is only affected if source artifacts change (none planned); do not download intermediates/dependencies in this scope.

Existing historically proved host invocation: GRIDRACE_LOCAL_INTEGRATION=1 bash scripts/run_live_match_integration.sh. It is not in the runbook's current command list; after extension and success controller promotes its exact prerequisites/results. Its script performs a reset: loopback/unlinked checks alone do not prove actual current data disposable. Require disposability before invocation; avoid running it concurrently with a separately served gateway/database writer. Preserve deterministic accepted non-answer fixture and privileged-credential exclusion from client environments/containers. Optional Swift integration skips in normal full suite do not satisfy the opt-in run.

Rediscover Xcode/runtime/destinations during implementation. Historical local proof used Xcode 27.0/iOS26.5 versus runbook Xcode26.6; this proposal did not inspect or run the toolchain. Record actual deviation without claiming CI/distribution equivalence. Hosted CI/Cron/retention/Apple provider/physical device are outside this local task.

Controller runs scoped git diff --check/stat and cached checks over concrete owned paths, reads complete net diff, inspects secret/config/grant/publication/lockfile changes, verifies overall status and six unrelated hashes at lease boundaries. No refresh/stage/stash/discard of cache/scratch. Review receives full baseline-to-current owned diff, final contracts, matrix evidence and limitations. Accept a finding only with reproduced failure or concrete invariant trace; repair once in bounded packages and rerun affected gates. No Historical status or final completion claim until all local accepted criteria have proof.

## Controller planning inspection and review ledger

P4-P planner chat `01a0fc81-59ad-7d73-bccf-bc6e8d2a17ff` returned its single authorized
callback, released its only proposal-file lease, and reported no owned process or
repository write. Controller read the entire proposal and checked its consequential
contracts against existing domain/storage, effective create/submit SQL, Edge request
validation and actual UI entry callers. That preparation preceded independent review. P4-PR then completed as recorded
below; D3/D4 remain explicitly accepted by the human.

| ID | Severity | Location | Claim/evidence | Disposition | Action/proof |
| --- | --- | --- | --- | --- | --- |
| P4-P-01 | Planning completeness | P4-U lease; ios/GridRace/App/DailyViews.swift:348 | Existing live Create invokes live.createMatch here; a selector/action confined to LiveMatchViews cannot cover the entry flow. Concrete caller traced. | Modified | Add DailyViews.swift to P4-U, restricted to live Create and entry presentation. Daily behavior/design stays intact. |
| P4-P-02 | Buildability | P4-C lease; ios/GridRace/App/LiveMatchViews.swift:62 | New server-error cases require this exhaustive UI switch to compile before substantive P4-U. Actual switch traced. | Modified | Add only new typed-error mapping/exhaustiveness adaptations to P4-C; later layout stays P4-U. |
| P4-PR-01 | High planning blocker | Foundation match CHECK at supabase/migrations/202608300001_phase_2_3_foundation.sql:58; planned incomplete state | Existing CHECK permits completed_at only for completed; proposed incomplete/reason combinations were unspecified. Controller read the exact CHECK and traced deletion/finalizer paths. | accepted | Freeze status/timestamps/reason matrix in plan/API; incomplete has null completed_at, completed has null reason even during/after final-round deletion; add v2 match timestamp fields and exact SQL/mapper/race proof. Targeted two-document closure inspected. |
| P4-PR-02 | Medium package blocker | ios/GridRaceTests/AccountTests.swift:331; P4-C lease | Account cleanup fixture constructs existing pending create and owns deletion/sign-out recovery failure assertions; it needs v2 adaptation/proof but was excluded from leases. Concrete caller and fixture read. | accepted | Add AccountTests.swift to P4-C for narrowly scoped recovery fixture/buildability and v1/v2 account cleanup/isolation proof. No substantive UI ownership changes. Lease and A8 matrix closure inspected. |

Independent P4-PR reviewer chat `01a0fdc7-aee8-79e0-8d90-3327c97e4d66` returned
its one read-only callback: two blockers above, otherwise decision-complete within
its inspected bounds. Controller accepted both on concrete traces, repaired only
their seams, and performed targeted closure; no second plan-review loop or renewed
human choice is required. Review is not a product-test pass or implementation review.

Human decision checkpoint: user “use both recs” accepts D3/D4 as explained in this
controller on 2026-10-02. Unselected deletion alternative is removed from this plan.

Original proposal (not authority):
`/Users/tristan/.codex/automations/gridrace-phase-4-kickoff/phase4-planner-proposal.md`,
SHA256 `73827b8a68a1500fb712a1486c44359ee38bb2b544a3d68b10a350efc518d127`.
Controller owns this integrated draft and all tracking/authority updates.

## Callback coordination and lease state

Current controller: `01a0fc7c-88b3-7f80-9631-504b4baffc45`, host `local`.
Planner and P4-PR read-only leases released; neither started owned processes. P4-B
worker `01a0fdd9-3876-7cf3-8c85-bef9083a6745` returned its single callback and released
all file/database/gateway leases, with no later writes. Controller independent local backend proof is complete and its database/gateway
processes are stopped. P4-C next receives the exact client/simulator lease after
backend checkpoint `ba65af9` and controller P4-I preparation. Controller prepared
SupabaseAccountService defaults and project app build numbers. P4-C worker
`01a0fdff-16ca-74e1-9c2b-d9edf00813ed` returned one BLOCKED_PARTIAL callback and
released all file/process leases. Controller now retains its partial work, the
adjudicated missing transitive lock pin and tracking changes for C/I integration.
P4-C2 released its ten-file/process lease on the human pause. Fresh P4-C3
`01a1005b-19f3-7133-8101-ca18dcf11590` returned its single completion callback
and released all ten file and Swift/simulator leases. Controller independent
focused verification exited successfully; no process remains. P4-U next receives
only the agreed three-file UI lease. Composition/contracts stay protected. Worker and
reviewer packets explicitly authorize exactly one callback to this controller after
finishing all owned processes and releasing leases; no later writes. Callback must
include RESULT, FILES, PROOF, ASSUMPTIONS, BLOCKERS and HEAD/status even when blocked
or without a commit. End dispatch turns; use no waits/polling. Never restart Phase 3
chats or callback to the old controller. Human scheduling authorization covers this
workflow; callback messages do not settle product choices.

## Verification and commit record

Planning-only proof: original proposal and five P4-PR input hashes verified;
reviewer reported untouched input bytes, clean index and all six unrelated hashes.
Controller independently read the existing match CHECK and AccountTests caller,
then inspected corrected matrix/lease/proof in plan and API. Scoped documentation
whitespace, exact path/reference inspection, full owned diff audit and unrelated hash
checks were the applicable planning gate. At that checkpoint no product test/reset/build or remote action had occurred;
prior Phase 2/3 counts are historical only.

Accepted-plan checkpoint: **3a01d9ab7772dbfa158d7ffcba2df13b7958694c**, limited to this plan, live-api-contract,
DECISIONS, NOW and TODO. Reviewer did not independently re-review the repairs;
controller targeted closure satisfies the bounded review policy. Implementation
packages and final full-scope proof/review remain pending. Record subsequent
implementation SHAs at meaningful checkpoints without tracking-only commits.

## P4-B backend integration and proof

Worker `01a0fdd9-3876-7cf3-8c85-bef9083a6745` delivered all 12 leased paths,
2,377 added/30 removed lines, no Git/tracking/composition change and no blockers.
All worker product SHA256 values match the handoff; the controller read the entire
migration, Edge diff, new SQL tests and expanded real integration harness, tracing
receipt order, actor/profile recheck, match/round/player locks, timestamp/reason
matrix, exact SQL aggregation, secrecy, grants and unchanged effective repairs.
No new dependency, base-table client grant or Realtime field was added. This is
controller integration inspection; the fresh final independent review remains due.

Worker proof, exact commands and logs are in
`/tmp/gridrace-phase4-backend-result.json`. Local startup was unlinked with zero
Auth/profile/match/Daily rows and no GridRace containers/volumes; all later data was
synthetic. Before its forward reset, the worker confirmed disposability, then used
`npx --no-install supabase db reset --version 202609260004`, actual legacy
lobby/active/revealed fixtures and successful create/guess receipts, and
`npx --no-install supabase migration up --local`. Before/after snapshots (excluding
server_time), IDs, results, receipt replay, RLS roster/outsider visibility and
existing grant/publication hashes matched. New RPCs and terminal reason remain
client-denied. These successful local candidate commands are now runbook canon
under the same disposable-only precondition; no applied history was edited.

Clean reset and `npx --no-install supabase test db`: seven SQL files, **739 pgTAP**
assertions (290 retained plus 449 new), all pass. Three-schema lint passes with only
unchanged join/random-code/normalizer/evaluator warnings. Edge fmt/lint, explicit
shared/six-handler check and **107 tests** pass. Seed, shared TypeScript vectors
(three tests) and portable checked-in word-pack chain pass. Dictionary artifacts
are unchanged; source regeneration is unaffected. Worker real Auth/Edge/RLS/
Realtime harness: **429 requests, 142 snapshots, 6,881 bytes maximum snapshot,
5,016ms maximum request** (deliberate barrier). All legacy scenarios remain;
1/3/5 target/guess duplicates and stale/final receipts, exact sums and ties,
post-lock deletion/profile checks, queued deletion/Start for both actors and
multi-match lock order pass. Actual scheduled pg_cron reveals ordinary nonfinal,
deleted nonfinal and final rounds without client finalization; never starts next.
Ordinary reveal accepts the creator's later Start after initial lobby expiry.

Controller independently restarted the stopped local backup and checked counts:
Auth=0, profiles=0, Daily=0, live identity links=0, 20 retained synthetic matches
(15 completed/5 incomplete), 40 anonymized Deleted Player members. This matched
the released worker ownership record before any controller reset. Controller then
reran clean reset, all **739 pgTAP**, three-schema lint, Edge **107 tests**, and
Edge/integration formatting plus Edge lint. Logs use
`/tmp/gridrace-phase4-controller-{reset,db,db-lint,edge,format,lint}.log`.
Controller also reran the full real gateway harness: **429 requests, 142 snapshots,
6,882 bytes maximum snapshot, 5,011ms maximum request** (deliberate barrier), all
legacy and v2 scenarios pass. Its 51 actual gateway snapshots separately pass the
same structural/disclosure/matrix/exact-timestamp validation; artifacts are
`/tmp/gridrace-phase4-controller-snapshots-v2.json` and
`/tmp/gridrace-phase4-controller-snapshot-inventory.json`. Real integration log is
`/tmp/gridrace-phase4-controller-integration.log`, with raw fixture lines extracted
into the artifact; validation log is
`/tmp/gridrace-phase4-controller-snapshot-validation.log`.
Final inventory Auth/profile/live auth links/Daily=0, 20 fully anonymized synthetic
matches, no barrier SQL sessions, `gridrace-finalize-rounds` active. Owned gateway
PID93094 was verified in this checkout, SIGINT/exited0; local stack stopped with
`npx --no-install supabase stop --project-id gridrace`, retaining only its backup
volumes. No owned process or container remains. Startup credential summaries were
omitted; no service key/client credential enters repository evidence or Swift inputs.

Actual worker gateway JSON is preserved in
`/tmp/gridrace-phase4-backend-snapshots-v2.json` (root.snapshots, 51 labels), inventory
`/tmp/gridrace-phase4-backend-snapshot-inventory.json`. Validation covers required
fields, current/history equality, disclosure, revealed-only totals, every match
matrix, first countdown, board eligibility and solved timing. Exact-time/tie rows
are coherent privileged synthetic SQL fixtures, copied unchanged from gateway.
These are P4-C mapper inputs, not a substitute for later two-simulator proof.

Toolchain: pinned repository Supabase CLI 2.116.0; Deno 2.9.7 versus runbook 2.9.5;
Node 24.14/npm 11.9 versus CI Node20.20.2; psql18.6/PostgreSQL17.6/pg_cron1.6.4;
Docker29.8. No pins/dependencies changed. Swift/Xcode proof is still pending.
Controller verified all six unrelated byte baselines and empty index at transfer;
worker leases/processes were released before callback. No remote or release action.

## P4-C partial handoff and controller adjudication

First P4-C worker `01a0fdff-16ca-74e1-9c2b-d9edf00813ed` stopped with
BLOCKED_PARTIAL and released all 10 file and simulator-process leases. Eight
leased files changed (1,077 added/201 removed lines), no Git/tracking write.
AccountTests and LiveMatchViewTests are untouched. Xcode27/iOS26.5 focused run
compiled, executed65/passed64/failed1: requestConflict was cleared by the initial
snapshot. A correction and 23 actual v2 fixture literals plus tests were added
AFTER the run and are uncompiled/unexecuted. Full suite/clean Debug are NOT RUN;
none of this client seam is accepted yet. Result and exact hashes/commands are
`/tmp/gridrace-phase4-client-result.json`, copied to automation
`client-partial-result.json`; focused log is
`/tmp/gridrace-phase4-client-focused.log`. Controller independently verified
all returned/previous protected inputs, HEAD/index and six unrelated hashes.
No owned test/build process remains; no database/remote operation occurred.

Native Xcode resolution automatically added outside-lease Package.resolved pin
swift-issue-reporting2.1.1 at75b000cea2ca6d7527a57e1b9cc0bdf21a9abe9f. Controller
ACCEPTS retaining only that missing transitive pin, a present dependency requirement:
clean exact locked swift-clocks82440fa and xctest-dynamic-overlayd9308ad manifests
both require/use IssueReporting from2.1.0. Original pins, originHash, project root
Supabase declaration and package manifests are unchanged. The added checkout is
clean/exact75b000c, MIT, iOS13 minimum within app18; no root dependency or existing
pin upgrade is introduced. This is controller-owned P4-I lockfile repair, not a
worker-expanded lease. Scope excludes dependencies without a concrete need; this
trace supplies the need. No material human product/UX decision is reopened.
Controller proved `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace
-derivedDataPath /tmp/gridrace-phase4-client-derived-test
-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
-skipPackageUpdates -resolvePackageDependencies`: exit0, exact accepted lock bytes
unchanged. Log `/tmp/gridrace-phase4-controller-client-resolve.log`; durable exact
adjudication in automation `client-lock-adjudication.json`. Further verification
uses these frozen native flags and preserves all pins; any new lock delta must
return to controller before affected work. Resolve is not full-suite/build proof.

Controller preliminary trace also finds an unnecessary Swift v1 fallback:
SupabaseLiveMatchService currently sends snapshot build2 but accepts version1 and
synthesizes revision1 while omitting canonical history/standings. The frozen current
client requires snapshot2 even for legacy floor1 rooms. P4-C2 removes that fallback,
adapts old meaningful fixture scenarios to valid v2, and proves a downgraded response
is rejected. Original durable build1 intents and backend legacy RPC/snapshot support
remain preserved; no new runtime compatibility surface is needed for old test JSON.
This is an integration correction, not the final independent implementation review.

Fresh P4-C2 finishes the entire original seam, AccountTests v1/v2 same-file cleanup/
isolation, all new fixture tests and generation/revision/old-pending/uncertain-Start/
equal-revision/coalescing/lifecycle/storage verification, full suite and Debug build.
Do not retain a failing expectation by weakening validation or automatic retries.
Any local UI draft/animation identity seam beyond compatibility returns to P4-U;
this package still excludes substantive layout. No final Phase4 proof is claimed.

## Human pause and resumed client handoff

P4-C2 `01a0fe0d-1e5d-7f43-86f0-e8dfdab2c121` released all ten file and
Swift/simulator process leases on the human pause. Its focused run passed 79/79,
but preceded further service/session/account tests and the terminal-pending receipt
watchdog correction. Those latest edits remain uncompiled/unexecuted; full iOS
and clean Debug were not run. The immutable handoff is
`/tmp/gridrace-phase4-client-continuation-result.json`. No client completion is
claimed from the earlier run.

The human explicitly resumed on 2026-10-03. Controller compared all ten source
hashes, fourteen protected inputs and six original unrelated byte baselines to
the paused callback: every file matched, HEAD remained `ba65af9`, index was empty,
and no owned verification process remained. Missing external automation notes
were reconstructed from this plan and retained callback artifacts; no schedule
or configuration was recreated. This recovery does not change repository scope.

Fresh P4-C3 receives the same exact ten-file lease and sole Swift/simulator proof
lease, preserving current partial work. Current build-2 snapshot decoding requires
v2 even for legacy floor-1 rooms; original durable build-1 retries stay unchanged.
Finish the full original client acceptance and affected focused/full/build gates
with frozen native package flags. Substantive UI and real two-client integration
remain P4-U/P4-V. Do not restart either released client worker.

## P4-C/I completion and controller acceptance

Fresh P4-C3 `01a1005b-19f3-7133-8101-ca18dcf11590` completed the original
client owner seam and released all leases/processes before its single callback.
Latest-source focused proof passed **87/87**, full iOS executed **205**, passed
**203**, with two expected opt-in integration skips and zero failures; clean Debug
passed. The skips are DailySyncTests/testLocalSupabaseTwoClientSyncAndDeletionWhenConfigured
and LiveMatchIntegrationTests/testTwoClientProcess; neither proves P4-V.

Controller audited the complete owned source diff and meaningful test additions,
verified ten returned source hashes, fourteen protected inputs, original six
unrelated hashes, unchanged HEAD/empty index, final log/result success markers and
**23/23 exact gateway fixture JSON comparisons**. Independently repeated latest
focused proof **87/87, zero failures**. Exact commands/logs/xcresults and hashes:
`/tmp/gridrace-phase4-client-resume-result.json` and
`/tmp/gridrace-phase4-controller-client-result.json`; controller log/result:
`/tmp/gridrace-phase4-controller-client-focused.log` and
`/tmp/gridrace-phase4-controller-client-focused.xcresult`.

The seam keeps count/round/build/UUID durable, requires strict snapshot v2 even in
legacy floor1 rooms, atomically migrates the existing account-private v1 filename,
preserves SQL standings and original build1 retries, retains explicit pending
conflict/rate-limit decisions across lifecycle, rejects lower revisions including
Home/Resume, and resolves terminal pending receipts before ending ordinary polling.
C3 fixed resumed-round draft clearing, create decisions across Home/foreground,
legacy-format/v2-payload mismatch rejection and invalid countdown timeout/rank shapes.
Controller finds no remaining package blocker; this is integration inspection,
not the required final independent implementation review.

All Xcode calls used frozen package flags and retained the exact accepted lock
hash. Actual Xcode27.0(27A266a), Swift6.4, iOS26.5(23F77), iPhone17Pro destination
1BCA3F5A-3228-4888-909E-ED86AE627221. No hosted/physical-device equivalence.
No DB/gateway/reset or remote operation in C3/controller client proof.

P4-U owns local draft/error/animation/focus identity by match+round, only hydrates
saved guesses belonging to the current round, and wires picker, canonical standings,
creator advancement, final/incomplete presentation and prior reveal selection.
Selection must never retarget commands. C/I build2 composition and the concretely
required missing transitive pin are accepted with client checkpoint
`335f210a5a287ada4994657e8f574ceeff4dcb7b` (16 owned files).

## UI presentation seam adjudication

P4-U `01a10069-197b-7551-9eea-2d8ec847ad51` released all three file and
Swift/simulator leases with BLOCKED_NO_WRITES. Its existing immutable-Start test
passed 1/1; no substantive UI, accessibility or full/build proof is claimed.
Result `/tmp/gridrace-phase4-ui-result.json`; empty owned diff. Controller verified
three UI baselines, all 128 protected tracked bytes, six original unrelated hashes,
HEAD/index/status against the transfer manifest: exact, no repository writes.

Controller ACCEPTS UI-SESSION-UNRESOLVED-START after concrete source trace:
LiveMatchSession pendingStart is private; an unchanged canonical snapshot retains
the target but sets ready and clears lastError. canRetry also covers ordinary
nonfinal recovery, so it cannot identify that unresolved action. Home preserves
pendingStart while removing the view. A view-local latch would lose authority at
Home/Resume. Existing server/session idempotency is intact, but enabled inert Start
and missing original-target Retry would fail accepted UI behavior.

Freeze the minimal internal presentation contract: read-only observable
`hasPendingStart: Bool` reflects existing `pendingStart != nil`. Do not expose or
mutate its target, add persisted state, or change command/retry/timestamp behavior.
P4-C4 has exactly session/source-tests leases above. Prove first and subsequent
uncertain Starts remain observable after unchanged refresh/Home/Resume, Retry uses
the captured target, and success/canonical advancement/definitive denial/account
reset removes the signal. Then checkpoint and send fresh P4-U2 the original UI
package plus this signal. No human scope/UX decision is reopened.

## P4-C4 targeted closure

Fresh worker `01a1006f-ba82-7352-9213-f42de9b5d29d` completed the two-file
seam, released all leases/processes and returned one callback. Product diff is
exactly the read-only computed `hasPendingStart` getter over existing observed
state. Two parameterized regressions prove native Observation invalidation,
first/next target preservation through unchanged refresh and Home/Resume, new
Start suppression, explicit Retry of the original match/round, no durable Start
intent, and clearing on success, canonical target/later advancement, definitive
denial and account reset. Existing behavior remains unchanged.

Worker affected proof passed **62/62** (58 session, four recovery store), zero
failures/skips. Initial new-test fixture typo referenced a nonexistent later
countdown; corrected to the actual later final reveal before the complete rerun.
Full suite/clean Debug are due after UI implementation; no new broad proof claim.
Result `/tmp/gridrace-phase4-start-seam-result.json`; final worker log/result
`/tmp/gridrace-phase4-start-seam-focused-rerun.log` and `.xcresult`.

Controller inspected the entire narrow diff and independently verified two source
hashes, all 129 protected tracked files, original six unrelated hashes, HEAD/index/
status and latest gate evidence. Independently executed both new regressions:
**2/2 passed**, zero failures; `/tmp/gridrace-phase4-controller-start-seam.log`
and `.xcresult`. Frozen native flags/exact lock preserved. The accepted integration
finding is closed; final independent implementation review is still required later.
Fresh P4-U2 uses `hasPendingStart` to disable new Start and offer original-target
Retry even after an error-free unchanged snapshot or Home/Resume. No view-local
command latch and no widened UI source lease.

## Blockers, stop conditions and next action

D3/D4 resolved; P4-PR-01/02 accepted and repaired; no outstanding planning blocker.
P4-B is committed/proved at `ba65af9`. P4-C/I is committed at `335f210` after latest-source
focused/full/clean Debug and controller audit/independent focused proof. P4-U
returned a traced presentation seam before writes. P4-C4 is accepted after narrow
closure proof; checkpoint it, then dispatch fresh Sol/medium P4-U2 within the
agreed three-file UI lease.
No product/UX decision is missing. Real independent-client V, one fresh final
independent R, bounded accepted repairs and Historical closeout remain.

Stop for multiple Active plans, unexpected overlap, material authority/contract gaps,
unknown fixture ownership/disposability, unavailable required proof or any remote,
spend/distribution proposal. Preserve unrelated files and keep this plan Active until
complete implementation, proof, review and required repairs.

## Closeout checklist

- [x] Accepted scope/baseline inspected; sole Active controller ledger created.
- [x] Fresh configured planner proposal received; lease released; controller draft integrated.
- [x] Human D3/D4 answers recorded; unselected alternative removed.
- [x] Independent plan review adjudicated; corrected contract/leases frozen for this accepted-plan commit.
- [ ] Bounded packages integrated, all counts/recovery/deletion/UI acceptance proved.
- [ ] Real independent-client multi-round proof and full affected gates complete.
- [ ] Fresh independent final review complete; accepted fixes/targeted closure proved.
- [ ] Authorities current; unrelated hashes preserved; owned changes committed.
- [ ] Only then Historical closeout, commit report and explicit external release gates.
