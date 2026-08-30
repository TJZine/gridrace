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

- `main` contains the clean starting baseline and the committed active tracker at
  `4caf8f0 docs: track phase 0 and 1 foundation`.
- The required repository authorities and Ponytail full-mode instructions have been
  read completely.
- The repository has no other `Status: Active` plan.
- The formal goal and live execution plan are active.
- Wave 1 completed with no authority contradiction. Xcode 26.6, Swift 6.3.3, and
  Deno 2.9.5 are available; iOS 26.5 and standard simulator devices are installed.
- The product gaps and artifact contracts are frozen below.
- All Phase 0 authority and artifact write units are integrated in the worktree.
  Controller inspection and the deterministic word/manifest check pass. The shared
  artifact and authority checkpoints are committed. Independent contract review
  found six issues; all accepted fixes passed focused closure with no new findings.

## Next integration action

Freeze Phase 1 iOS and TypeScript write paths and dispatch the two disjoint writers.

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
| D-01 Rules/authority audit | `rules_authority_audit` | Repository and supplied task; no writes | Required reads | Complete: four gaps reconciled |
| D-02 Local toolchain audit | `local_toolchain_audit` | Toolchain and simulator inspection; no writes | Required reads | Complete: runtime installation needed |
| D-03 Word/vector audit | `word_vector_audit` | Artifact design; no writes | Required reads | Complete: four-artifact layout frozen |
| P0-01 Product/rules/flow authorities | `rules_authority_audit` | `docs/product-spec.md`, `docs/game-rules.md`, `docs/screen-flow.md` | D-01, D-03 | Complete; controller-read |
| P0-02 Architecture/privacy/ADR | `local_toolchain_audit` | `docs/architecture.md`, `docs/privacy-data-map.md`, `docs/adr/0001-native-swiftui-authoritative-supabase.md` | D-01 | Complete; controller-read |
| P0-03 Word pack/vectors | `word_vector_audit` | `shared/word-packs/**`, `shared/test-vectors/game-rules-v1.json`, `scripts/check_word_pack.py` | D-03 and frozen shapes | Complete; checker passed |
| P0-04 Contract review and checkpoint | Controller + `phase0_contract_review` | Integrated Phase 0 diff | P0-01..03 | Complete; CR-01..06 closed |
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
| DEC-02 | Use `shared/test-vectors/game-rules-v1.json` as the sole vector source with typed runtime decoders; add no JSON Schema. | Accepted | Both runtimes consume the checked-in file directly |
| DEC-03 | Use one iOS writer for the project and composition root. | Accepted | Shared-write serialization boundary |
| DEC-04 | The match creator starts the first and later countdowns when 2–8 players are rostered; MVP has no readiness state. | Accepted | Smallest explicit server-owned advancement; reveal is not auto-dismissed |
| DEC-05 | Submissions are eligible only while `serverNow < endsAt`; equality times out. | Accepted | Removes deadline ambiguity |
| DEC-06 | Exact ties use competition placements (`1, 1, 3`); the supplied unsolved comparator remains literal. | Accepted | Makes shared placement numbering exact without changing ranking keys |
| DEC-07 | Disconnect never forfeits; only an explicit authenticated action forfeits. Answers do not repeat within one match. | Accepted | Preserves recovery and prevents a known-answer replay |
| DEC-08 | Reveal order is local player first, then stable roster order; accepted rows reveal top-to-bottom, one complete row at a time. Reduce Motion exposes the same complete state immediately. | Accepted | Deterministic and accessible |
| DEC-09 | The word pack lives at `shared/word-packs/development-en-US-v1.json` with generated manifest beside it; Phase 1 accepted guesses equal the 100 answers. | Accepted | Minimal deterministic development resource |
| DEC-10 | The original word compilation has no standalone license grant; repository copyright applies until the owner adopts a license. | Accepted | Records actual licensing status without inferring permission |
| DEC-11 | Validation precedence is non-ASCII, ASCII lowercase mapping, invalid length, invalid character, then unknown word; invalid input consumes no row and solve beats sixth-guess failure. | Accepted | Stable cross-runtime error contract |
| BLK-01 | No simulator runtime was installed at discovery time. | Resolved | `xcodebuild -downloadPlatform iOS` installed iOS 26.5 and standard devices |
| BLK-02 | Canonical vector and word layouts were unfrozen. | Resolved | DEC-02, DEC-09, and DEC-11 |

## Review findings and dispositions

| ID | Severity | Location and evidence | Disposition | Action | Verification |
| --- | --- | --- | --- | --- | --- |
| CR-01 | High | `docs/game-rules.md` named no owner for round-player transitions. | Accepted | Add transactional PostgreSQL/Edge Function owners for solve, fail, timeout, and forfeit. | Closed by focused reviewer |
| CR-02 | Medium | `docs/product-spec.md` labeled beta-exit gates as conditions for beta start. | Accepted | Say the production beta exits only when all listed gates pass. | Closed by focused reviewer |
| CR-03 | Medium | `docs/screen-flow.md` showed an undefined summary both before and after staged rows. | Accepted | Show only the answer before rows; keep summary after rows. | Closed by focused reviewer |
| CR-04 | Medium | Product/architecture labels overstated Phase 1 as already implemented. | Accepted | Use neutral Phase 1 scope and local-architecture labels. | Closed by focused reviewer |
| CR-05 | Low | `docs/TODO.md` reintroduced readiness despite the no-readiness decision. | Accepted | Replace `ready/start` with `creator start`. | Closed by focused reviewer |
| CR-06 | Low | Plan omitted the authority commit and contained stale simulator/verification state. | Accepted | Refresh outcome, commit ledger, and unavailable-gate list. | Closed by focused reviewer |

## Verification evidence

| Surface | Exact command or inspection | Result |
| --- | --- | --- |
| Starting state | `git status --short --branch` | Passed: clean `main` |
| Starting HEAD | `git log --oneline -8` | Passed: `699dd14`, `f75934c`, `758caef` match the supplied baseline |
| Active-plan uniqueness before creation | `rg -l '^Status: Active$' docs/plans` | Passed: no result |
| Required authority reads | Complete chunked reads of all named files | Passed |
| Toolchain | `xcodebuild -version`; `swift --version`; `deno --version` | Passed: Xcode 26.6, Swift 6.3.3, Deno 2.9.5 |
| TypeScript execution | `deno eval --no-config 'const value: number = 6; ...'` | Passed: `deno-typescript-ok` |
| Simulator discovery | `xcrun simctl list runtimes`; `xcrun simctl list devices available` | No runtimes/devices before authorized installation |
| Simulator installation | `xcodebuild -downloadPlatform iOS` | Passed: iOS 26.5 (23F77) and standard devices installed |
| Word pack | `python3 scripts/check_word_pack.py` | Passed: 100 words and deterministic manifest |
| Manifest hash | Independent SHA-256 comparison | Passed: `7c4bdd9281e3bf6d6b45013772c9bb104f0779499cb576c7384f5b649405cbcf` |
| Phase 0 whitespace | `git diff --check` | Passed before checkpoint staging |
| Phase 0 contract closure | Focused re-review of CR-01..06 | Passed: all closed, no new findings |

## Integrated commits

| Commit | Purpose | Status |
| --- | --- | --- |
| `4caf8f0 docs: track phase 0 and 1 foundation` | Activate durable task tracking | Complete |
| `ac8ebe2 test(rules): add shared evaluator contract` | Add the canonical vectors, word pack, manifest, and checker | Complete |
| `5c60f7a docs: define GridRace product foundation` | Add and map the Phase 0 authority set | Complete |

## Unrun or unavailable gates

- Xcode project discovery, build, XCTest, simulator launch, UI inspection, VoiceOver,
  Reduce Motion, TypeScript tests, and final Git gates remain unrun because their
  implementation surfaces are not complete.

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
