Status: Active
Scope: GridRace Phase 2 backend foundation and Phase 3 two-player live slice
Owner: Primary orchestrator
Started: 2026-08-30
Last updated: 2026-08-30

# Phase 2 and Phase 3 Live Slice Plan

## Goal

Complete GridRace Phase 2 and Phase 3: build and verify the local authoritative
Supabase foundation, authentication/profile boundary, private answer storage, RLS,
transactional commands, deletion path, and database tests; then deliver an
end-to-end two-player, one-round SwiftUI multiplayer race with server-selected
answers, idempotent guess submission, clue-free progress, canonical snapshot
recovery, deadline finalization, and shared reveal.

## Current verified outcome

- The supplied starting point is clean `main` at
  `e7ccb96 docs: close phase 0 and 1 plan`; no newer or unrelated changes exist.
- No other `Status: Active` repository plan existed before this tracker.
- The task, Ponytail full-mode instructions, repository authorities, canonical rule
  and word artifacts, TypeScript evaluator, all iOS sources/tests, Xcode project,
  and shared scheme were read completely before editing.
- The formal goal and live execution plan are active.
- Existing baseline gates pass: the 100-word deterministic pack, all TypeScript
  evaluator gates, 16 XCTest cases, and a clean iOS build.
- The available simulator was rediscovered as iPhone 17 Pro / iOS 26.5 with UUID
  `1BCA3F5A-3228-4888-909E-ED86AE627221`; it was not assumed from prose.
- Wave 1 discovery is complete. The controller reconciled the backend/toolchain,
  schema/RLS/security, iOS integration, and command/test reports into the versioned
  contract at `docs/live-api-contract.md` and the current authority documents.
- Supabase CLI `2.116.0` and Supabase Swift `2.55.1` are frozen from current official
  releases. Node 24.14.0, npm 11.9.0, Docker 29.5.2, Deno 2.9.5, Xcode 26.6, and
  Swift 6.3.3 are locally available.
- Schema ownership, column-level secrecy, nonrecursive RLS helpers, lock ordering,
  deletion/anonymization, fixed rate limits, debug-auth boundary, snapshot v1, safe
  match-row Realtime signals, command envelopes, and negative/concurrency proof are
  frozen. The missing display-name contract is now explicit in the live API authority.
- No Supabase project has been linked, reset, migrated, or deployed. No remote
  Supabase state has been read or mutated.

## Next integration action

Bootstrap the repository-pinned local Supabase toolchain and deterministic canonical
word seed, then prove their exact install/version/drift commands before schema work.

## Scope

- Phase 2: repository-pinned local Supabase CLI, deterministic word seed, public
  and private database schemas, grants/RLS, profiles, local authenticated test
  sessions, Apple-auth production boundary, account deletion, six explicit Edge
  Functions, transactional command functions, database/Edge tests, and local proof.
- Phase 3: exactly two authenticated players and one round through create, join,
  creator start, server-authoritative guess submission, clue-free progress,
  timestamp-driven countdown/deadline, idempotent finalization, versioned canonical
  snapshots, Realtime-triggered recovery, reveal, and two-client simulator proof.
- Same-pass product, architecture, privacy, flow, decision, runbook, and plan updates
  needed to distinguish Phase 2 and Phase 3 and match implemented behavior.
- Fresh security/RLS review after Phase 2 and a fresh final review after Phase 3.

## Non-goals

- More than two players, three/five-round execution, later-round advancement,
  rematch, history, Universal Links, notifications/devices, reports/blocks,
  profanity services, public matchmaking, friends, chat, spectators, rankings/Elo,
  asynchronous play, custom answers, monetization, anti-cheat attestation, staging,
  production deployment, TestFlight, CI/deployment automation, or a generalized
  game/command/repository/coordinator framework.
- Remote Supabase linking, reset, migration, deployment, or secret management.
- Claiming real Apple provider exchange, physical-device proof, remote Cron
  scheduling, or production deployment when those external prerequisites are absent.

## Product, security, privacy, and state-machine invariants

- Private Blind Race remains five letters and six accepted guesses. Production
  supports 2–8 players and 1/3/5 rounds; this slice forces exactly two and one.
- The creator starts; readiness does not exist. Countdown is three seconds and the
  deadline is 180 seconds. A guess is eligible only while
  `startsAt <= serverNow && serverNow < endsAt`; equality times out.
- Match: `lobby -> inProgress -> completed`. Round:
  `pending -> countdown -> playing -> revealed`. Round player:
  `playing -> solved|failed|timedOut|forfeited`.
- Disconnect never forfeits. Only an explicit authenticated action could forfeit;
  this slice exposes no forfeit UI or command.
- The server selects nonrepeating answers and owns accepted-word validation,
  feedback, timestamps, scoring, placement, and transitions. The sixth correct guess
  solves; only an incorrect sixth guess fails.
- The duplicate-letter algorithm and versioned Swift/TypeScript vector contract do
  not change.
- Normal credentials cannot read the private schema, answer before reveal, an
  unrelated match, or directly mutate authoritative game state.
- Pre-reveal data never exposes opponent words, feedback, keyboard state, starting
  words, or exact solve duration. Logs never contain raw answers, guesses, tokens,
  invite secrets, profile payloads, or credentials.
- Realtime is a refresh signal. Versioned canonical snapshots own recovery and
  convergence after entry, reconnect, foregrounding, command uncertainty, timer
  expiry, and inconsistent events.
- Guess submission, finalization, seat assignment, and account deletion are
  transactional and idempotent where retried. Reused request IDs cannot duplicate a
  guess or silently change request content.
- Account deletion removes the auth identity and owner-only detail, irreversibly
  anonymizes any retained opponent-visible slot as “Deleted Player,” removes
  reversible identity mapping, and preserves the other player's structural result.
- Views never import or call Supabase. The app contains no service-role credential,
  Apple private key, session token, or broad transport-security exception.
- Accessibility, non-color semantics, Reduce Motion, Dynamic Type, Increased
  Contrast, Bold Text, usable targets, and optional native haptics remain intact.

## Frozen cross-stack contract

The normative wire details are in [`../live-api-contract.md`](../live-api-contract.md).
The summaries below are frozen inputs to all implementation units.

### Command boundary

Only `create-match`, `join-match`, `start-match`, `submit-guess`,
`match-snapshot`, and `delete-account` are in scope. Each authenticates a bearer
session, validates build/input, invokes one transactional database command for an
authoritative mutation, maps a centralized stable error subset, and logs no payload
secrets.

### Stable errors

`not_authenticated`, `not_a_match_member`, `match_not_joinable`, `room_full`,
`room_expired`, `not_host`, `not_enough_players`, `round_not_active`,
`round_already_finished`, `invalid_guess_format`, `word_not_accepted`,
`rate_limited`, `client_update_required`, `request_conflict`, and `internal_error`.

### Snapshot v1 visibility

- Pre-reveal: server time; public match/build/expiry state; stable roster snapshots;
  public round timestamps/state; requester's status/count/full accepted board;
  opponents' count/coarse state only.
- Post-reveal: answer; both boards in stable seat order; permitted server submission
  timestamps; guesses used; solve durations; efficiency; competition placement.
- DTO/domain mapping rejects malformed or impossible state combinations.

### Local proof identities

At minimum: two rostered authenticated users, one unrelated authenticated user, one
anonymous context, and internal/service context only where required. Debug local
auth must compile out of Release and use independent sessions without admin access.

## Work units, owners, dependencies, and exclusive write boundaries

| Unit | Owner | Write boundary | Depends on | Status |
| --- | --- | --- | --- | --- |
| D-01 Backend/toolchain audit | `backend_audit` | Read-only repository/toolchain/official docs | Required reads | Complete: CLI 2.116.0 and local gates frozen |
| D-02 Schema/RLS/security audit | `schema_security_audit` | Read-only repository/official docs | Required reads | Complete: schema/policies/deletion/locks/tests frozen |
| D-03 iOS integration audit | `ios_audit` | Read-only iOS/project/official docs | Required reads | Complete: SDK 2.55.1 and minimum seams frozen |
| D-04 Contract/test audit | Primary orchestrator | Read-only task/contracts/proof design | Required reads | Complete: wire/privacy/concurrency/two-client proof frozen |
| C-01 Contract and authority freeze | Primary orchestrator | This plan and shared authority/contract docs | D-01..04 | Complete; controller diff audit pending checkpoint |
| P2-01 Local toolchain and deterministic seed | Assigned after freeze | `package.json`, lockfile, Supabase config, seed generator/derived seed, ignores/examples | C-01 | Pending |
| P2-02 Schema, transactions, grants, RLS, database tests | Assigned after freeze | One serialized migration/test boundary under `supabase/migrations/**` and `supabase/tests/database/**` | C-01, P2-01 | Pending |
| P2-03 Edge command functions and focused tests | Assigned after SQL freeze | `supabase/functions/**` only | P2-02 SQL/API freeze | Pending |
| P2-04 Phase 2 integration/security review/checkpoint | Primary + fresh reviewer | Integrated backend diff, docs, plan, Git | P2-01..03 | Pending |
| P3-01 SwiftUI live slice | One iOS writer | `ios/**`; project/composition serialized to this writer/controller | P2 checkpoint | Pending |
| P3-02 Disjoint backend integration/recovery tests | Assigned after freeze if useful | Exact test-only paths, no SQL/API/project overlap | P2 checkpoint | Pending |
| P3-03 Two-client integration proof | Primary orchestrator | Local stack and simulator containers only | P3-01..02 | Pending |
| R-01 Final independent review | Fresh read-only reviewer | Final task-owned diff and evidence | Integrated Phase 3 | Pending |
| C-02 Closeout | Primary orchestrator | Findings, authorities, runbook, plan, Git | All accepted fixes verified | Pending |

Only the primary orchestrator edits this plan, shared contracts after freeze,
authority integration, the Git index, or commits. Migrations, grants/RLS, seeds,
shared API/snapshot contracts, Xcode project/package resolution, and composition
roots are serialized. Workers inspect broadly, write only within exact assigned
paths, never mutate Git, never nest delegation, and return assumptions/blockers.

## Dependencies and serialization points

- Official Supabase local-development, Cron, CLI, Edge, Swift SDK, and Apple
  authentication guidance must be consulted before dependency/API syntax is frozen.
- SQL command signatures, error names, snapshot JSON, account-deletion semantics,
  build number, debug identities, and rate limits freeze before Edge/iOS writers.
- The migration/schema owner freezes SQL before the Edge writer starts.
- Local stack reset/seed/database proof precedes the Phase 2 security review.
- Phase 2 security findings close before iOS integration depends on the backend.
- One iOS writer owns package/project/composition changes; no overlapping iOS writer.
- The controller integrates and commits every checkpoint after rerunning proof.

## Risk tier and verification matrix

Risk: **High** — authentication, RLS, secrets, migrations, deletion, APIs,
concurrency/idempotency, timers, state machines, Realtime, project dependencies, and
cross-stack contracts are all touched.

| Surface | Required evidence |
| --- | --- |
| Toolchain/config | Lockfile install, pinned CLI version, config parse, ignored local state, secret scan |
| Seed | Deterministic generation/check, exact 100 canonical words, reset-from-zero |
| Schema | Constraints/indexes/FKs, lint, clean forward migration/reset |
| Grants/RLS | Positive and negative pgTAP for anonymous, rostered, unrelated, private schema, direct mutations, before/after reveal |
| Transactions | Parallel seat-two joins, duplicate/conflicting requests, simultaneous submissions/finalizers, deadline race, rollback/idempotency |
| Evaluator | Canonical vectors and duplicate-letter equivalence in server runtime |
| Edge commands | Auth/build/input/error contract tests; no sensitive logging |
| Deletion | Authenticated retry, data removal/anonymization, auth identity deletion, survivor integrity |
| Snapshot | Pre/post reveal field audit, impossible-state rejection, stable ordering |
| Realtime/recovery | Duplicate/dropped/reordered signal coalescing, snapshot convergence, foreground/relaunch/deadline refresh |
| iOS | Focused service/mapper/session tests, Release debug-auth exclusion, clean dependency resolution, tests/build |
| Accessibility/UI | Tutorial regression, two-player flow, VoiceOver/non-color/Reduce Motion/Dynamic Type inspection |
| End to end | Independent client sessions create/join/start/race/finalize/reveal identically |

## Decisions and blockers

| ID | Decision or blocker | State | Evidence / resolution |
| --- | --- | --- | --- |
| DEC-01 | Use Ponytail full mode and stop at native/database/platform mechanisms that securely satisfy the requested slice. | Accepted | User direction and skill contract |
| DEC-02 | Restore Phase 2 backend / Phase 3 live-slice naming without changing product behavior. | Accepted | User correction |
| DEC-03 | Phase 3 forces exactly two players, one round, 60-minute lobby expiration, build floor matching app build. | Accepted | Explicit task authorization |
| DEC-04 | Keep the canonical evaluator and 100-word development pack unchanged; generated SQL is derived and drift-checked. | Accepted | Product/task contract |
| DEC-05 | Local automated identities are debug-only, independent authenticated sessions; production remains Apple through Supabase Auth. | Accepted | Task contract |
| DEC-06 | Real Apple provider exchange, external token revocation, and physical-device proof may be documented-only when credentials/hardware are unavailable. | Accepted | Task contract |
| DEC-07 | Pin Supabase CLI `2.116.0` and Supabase Swift `2.55.1`; use the CLI's Docker matrix and no custom Compose stack. | Accepted | Official release/source audits D-01/D-03 |
| DEC-08 | Use service-only security-invoker command RPCs, a separate safe definer-helper schema for nonrecursive RLS, column grants for timing/auth IDs, and a public match revision as the only Realtime signal. | Accepted | D-02/D-03 reconciliation |
| DEC-09 | Use one fixed lock order: match, round, player rows in seat order, then guesses/receipts. Expected business errors return typed results so rate counters commit. | Accepted | D-02 concurrency audit |
| DEC-10 | Delete invalid lobbies, treat active account deletion as explicit forfeit, and retain only irreversibly anonymized survivor-required results before hard Auth deletion. | Accepted | Architecture/privacy decision and D-02 |
| DEC-11 | Display names are 2–16 ASCII characters with alphanumeric ends and internal letters, digits, single spaces, apostrophes, or hyphens. | Accepted assumption | The supplied “documented” set was absent; narrow trust-boundary rule now documented |
| DEC-12 | Local trusted client-IP provenance is unavailable. Prove transactional per-user limits and the keyed-IP database path; keep live address extraction documented-only. | Accepted limitation | Current official deployment material does not identify a trustworthy local header |
| BLK-01 | Exact Supabase CLI/SDK versions and current API syntax. | Resolved | DEC-07 and official source inspection |
| BLK-02 | Final SQL/deletion/rate-limit/RLS structure. | Resolved | DEC-08..12 and live API contract |

## Review findings and dispositions

No findings yet. Material findings will use:

`ID | severity | location | claim | evidence | disposition | action | verification`

Allowed dispositions: `accepted`, `modified`, `rejected`, or `deferred`.

## Verification record

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
| Simulator discovery | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -showdestinations` | Passed: live UUID recorded above |
| iOS tests | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' -derivedDataPath /tmp/GridRaceDerivedData-baseline-test test` | Passed: 16 tests, 0 failed |
| iOS clean build | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' -derivedDataPath /tmp/GridRaceDerivedData-baseline-build clean build` | Passed |

## Integrated commits

Phase 2/3 commits to date:

| Commit | Purpose | Status |
| --- | --- | --- |
| `70c0339 docs: track phase 2 and 3 live slice` | Activate durable task tracking | Complete |

Remaining intended checkpoints are adjusted only when the real dependency graph
makes units inseparable:

1. `build(backend): bootstrap local Supabase`
2. `feat(backend): add private game schema and RLS`
3. `feat(auth): add Supabase authentication and profiles`
4. `feat(backend): add match commands and snapshots`
5. `feat(backend): add idempotent guessing and finalization`
6. `feat(ios): add two-player live race`
7. `test(integration): prove authoritative live slice`
8. `docs: record phase 2 and 3 verification`
9. `docs: close phase 2 and 3 plan`

## Unavailable or documented-only proof

- Supabase/database/Edge/Cron commands remain unavailable until the pinned local
  toolchain and implementation exist. They are not claimed as passed.
- Real Apple provider exchange and Apple token revocation require external provider
  credentials and are expected to remain documented-only if unavailable locally.
- Physical-device proof and remote Cron delivery are not required for this local
  simulator slice. Database finalizer behavior must still be proved directly.
- No remote deployment or remote Supabase proof is authorized.

## Phase 2 exit criteria

- [ ] Pinned local stack installs and recreates migrations/seed from zero.
- [ ] Private words/answers are denied to anonymous and normal authenticated users.
- [ ] Unrelated users cannot read matches; normal clients cannot mutate game tables.
- [ ] Positive/negative RLS tests pass for every exposed table.
- [ ] Server evaluator passes the canonical contract.
- [ ] Local auth/session/profile setup works with independent test identities.
- [ ] Account deletion removes/anonymizes Phase 2/3 data and deletes local auth identity.
- [ ] Exact proved backend commands are promoted into the runbook.
- [ ] Fresh security/RLS review has no unresolved high-severity finding.

## Phase 3 exit criteria

- [ ] Two independent authenticated clients create/join the same room and roster.
- [ ] Creator start produces the same server-timestamp countdown/deadline.
- [ ] Server guesses, clue-free progress, timeout/finalization, and shared reveal converge.
- [ ] Pre-reveal answer and unrelated-match denial are proved.
- [ ] Duplicate request IDs create one guess; conflicting reuse returns `request_conflict`.
- [ ] Reconnect/relaunch restores the exact accepted board from a snapshot.
- [ ] Foregrounding, creator disconnect, and reordered/dropped/duplicate signals converge.
- [ ] Repeated finalization works with clients closed; both clients agree on results.
- [ ] The Phase 1 tutorial and all existing gates remain green.
- [ ] Fresh final review findings are adjudicated and closed.

## Stop conditions

Stop for a game-rule, privacy, security, retention, public-contract, or architecture
contradiction; more than one active plan; unexpected overlapping writes; unrelated
worktree mutation; a required dependency/API decision unsupported by current
official documentation; unavailable local infrastructure that prevents secure
proof; or a failed high-risk gate that cannot be resolved inside scope.

## Closeout checklist

- [ ] Phase 2 and Phase 3 exit criteria have exact evidence.
- [ ] Security/RLS and final independent reviews are adjudicated.
- [ ] Successful commands are promoted into the runbook.
- [ ] Product, architecture, privacy, flow, decision, and phase naming are current.
- [ ] All content checkpoints are committed with conventional subjects.
- [ ] No remote Supabase project was mutated; no push occurred.
- [ ] The worktree is clean.
- [ ] This plan is `Historical`, identifies the latest content checkpoint, labels
      tracker closeout as “this commit,” and its closeout SHA is reported.
