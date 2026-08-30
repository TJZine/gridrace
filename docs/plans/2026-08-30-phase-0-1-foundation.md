Status: Active
Scope: GridRace Phase 0 product baseline and Phase 1 local SwiftUI foundation
Owner: Primary orchestrator
Started: 2026-08-30
Last updated: 2026-08-30

# Phase 0 and Phase 1 Foundation Plan

## Goal

Complete GridRace Phase 0 and Phase 1: establish the authoritative product,
game-rule, architecture, privacy, screen-flow, word-pack, and shared evaluator
contracts; then deliver and verify a native SwiftUI local tutorial race with an
accessible board, keyboard, countdown, opponent progress, and minimal reveal
prototype.

## Current verified outcome

- `main` is clean at `699dd14 docs: close repository foundation plan`.
- The required repository authorities and Ponytail full-mode instructions have been
  read completely.
- The repository has no other `Status: Active` plan.
- The formal goal and live execution plan are active.
- Phase 0 and Phase 1 implementation has not started.

## Next integration action

Run and reconcile the three bounded Wave 1 discovery audits, then freeze file
ownership and the shared-vector path and shape before delegating writes.

## Scope

- Phase 0 current product, rule, architecture, privacy, screen-flow, ADR, word-pack,
  provenance, deterministic check, manifest, and shared-vector authorities.
- Phase 1 Swift 6 / iOS 18 SwiftUI app, pure Swift and TypeScript evaluators, local
  tutorial race, accessible board and keyboard, absolute-time countdown, private
  opponent progress, and deterministic reveal prototype.
- Focused native and standard-library tests, simulator launch and interaction proof,
  authority updates, review, verification, and conventional commits.

## Non-goals

- Supabase setup, migrations, RLS implementation, authentication, networking,
  production rooms, Realtime, Edge Functions, APNs, Universal Links, production
  profiles, history, rematch networking, moderation persistence, or account deletion
  backend.
- Public matchmaking, chat, friends, rankings, monetization, custom words,
  asynchronous play, generalized modes, speculative folders, or generalized rules
  and plugin architectures.
- Third-party architecture, state-management, testing, snapshot, project-generation,
  or CI dependencies.

## Product and security invariants

- Blind Race is private and synchronous for 2–8 players, with 1, 3, or 5 rounds
  (default 3), five-letter words, six accepted guesses, a server-owned three-second
  countdown, and a 180-second deadline.
- The duplicate-letter evaluator uses the two-pass remaining-frequency algorithm and
  encodes absent/present/correct as 0/1/2.
- Backend authority eventually owns answers, validation, feedback, timestamps,
  scoring, and transitions. The Phase 1 fixture is explicitly local and makes no
  production secrecy or authority claim.
- Production clients never receive pre-reveal answers, service credentials, raw
  opponent clues, or direct authoritative state mutation rights. Realtime remains a
  refresh signal and canonical snapshots own convergence.
- Views do not call Supabase. Pure evaluators have no UI, networking, or persistence.
- Live opponent progress reveals only identity, accepted guess count, connection,
  and coarse playing/terminal state; clues and exact solve time remain hidden.
- Tile and opponent meaning never depends on color alone. VoiceOver, Reduce Motion,
  Increased Contrast, Bold Text, Dynamic Type, usable hit targets, and optional
  native haptics remain required.
- Swift and TypeScript decode and execute one checked-in canonical JSON vector file
  directly. There is no checked-in duplicate fixture.
- Branding remains original and does not imitate Wordle naming, iconography,
  typography, or its green/yellow/gray system.

## Work units, owners, dependencies, and write boundaries

| Unit | Owner | Boundary | Depends on | Status |
| --- | --- | --- | --- | --- |
| D-01 Rules/authority audit | Bounded read-only worker | Repository and supplied task; no writes | Required reads | In progress |
| D-02 Local toolchain audit | Bounded read-only worker | Toolchain and simulator inspection; no writes | Required reads | In progress |
| D-03 Word/vector audit | Bounded read-only worker | Artifact design; no writes | Required reads | In progress |
| P0-01 Product/rules/flow authorities | To assign after contract freeze | Exact disjoint docs paths | D-01, D-03 | Pending |
| P0-02 Architecture/privacy/ADR | To assign after contract freeze | Exact disjoint docs paths | D-01 | Pending |
| P0-03 Word pack/vectors | Single bounded writer | Frozen artifact paths only | D-03 and controller approval | Pending |
| P0-04 Contract review and checkpoint | Controller + fresh read-only reviewer | Integrated Phase 0 diff | P0-01..03 | Pending |
| P1-01 Native iOS implementation | Single bounded iOS writer | `ios/**` only | Phase 0 checkpoint | Pending |
| P1-02 TypeScript evaluator | Separate bounded writer | Frozen TypeScript paths only | Phase 0 checkpoint | Pending |
| P1-03 Integration and end-to-end proof | Primary orchestrator | Shared contracts, project, docs, Git | P1-01..02 | Pending |
| R-01 Final independent review | Fresh read-only reviewer | Final diff and proof packet; no writes | Integrated Phase 1 | Pending |
| C-01 Closeout | Primary orchestrator | Findings, plan, authorities, commits, handoff | R-01 closure | Pending |

Only the primary orchestrator edits this plan, shared contracts after freeze, the
Xcode project/composition root during integration, the Git index, or commits. Workers
do not nest delegation, change Git state, or write outside their explicit boundary.

## Decisions and unresolved blockers

| ID | Decision or blocker | State | Evidence / resolution |
| --- | --- | --- | --- |
| DEC-01 | Use Ponytail full mode: standard library and native Apple frameworks first. | Accepted | User direction and skill contract |
| DEC-02 | Use one canonical vector JSON file with typed runtime decoders; add no unused JSON Schema. | Provisional | Freeze after Wave 1 audit |
| DEC-03 | Use one iOS writer for the project and composition root. | Accepted | Shared-write serialization boundary |
| BLK-01 | Installed Xcode, available simulator, and TypeScript runner are not yet proved. | Open | Wave 1 toolchain audit |
| BLK-02 | Canonical vector path/shape and word artifact layout are not yet frozen. | Open | Wave 1 contract reconciliation |

## Review findings and dispositions

No review findings yet. Material findings will be recorded with severity, exact
location and evidence, disposition (`accepted`, `modified`, `rejected`, or
`deferred`), action, and closure proof.

## Verification evidence

| Surface | Exact command or inspection | Result |
| --- | --- | --- |
| Starting state | `git status --short --branch` | Passed: clean `main` |
| Starting HEAD | `git log --oneline -8` | Passed: `699dd14`, `f75934c`, `758caef` match the supplied baseline |
| Active-plan uniqueness before creation | `rg -l '^Status: Active$' docs/plans` | Passed: no result |
| Required authority reads | Complete chunked reads of all named files | Passed |

## Integrated commits

No task commits yet.

## Unrun or unavailable gates

- Xcode project discovery, build, XCTest, simulator launch, UI inspection, VoiceOver,
  Reduce Motion, TypeScript tests, word-pack validation, manifest validation, and
  final Git gates remain unrun because their implementation surfaces or discovery
  work are not complete.

## Stop conditions

Stop for an actual game-rule contradiction, a required product/security choice not
authorized by the supplied contract, unexpected overlapping writes, unrelated
worktree mutation, a dependency request, or a failed high-risk gate that cannot be
resolved inside the requested scope.

## Closeout state

- [ ] Phase 0 exit criteria all have evidence.
- [ ] Phase 1 exit criteria all have evidence.
- [ ] Phase 0 contract review findings are adjudicated.
- [ ] Final independent review findings are adjudicated and closed.
- [ ] Successful exact commands are promoted into the runbook.
- [ ] Content checkpoints are committed with conventional subjects.
- [ ] The working tree is clean and no push is performed.
- [ ] This plan is marked `Historical`, names the latest content commit, and records
      tracker closeout as “this commit”; its SHA is reported in the final handoff.
