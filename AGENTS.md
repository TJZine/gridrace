# GridRace agent entrypoint

GridRace contains native SwiftUI Daily Classic, optional private account synchronization, and Supabase-authoritative live racing.

Read [the project profile](.agents/project.md) for ownership, verification commands, local-runtime precautions, and the authority map. Inspect the current revision and working state; a prior plan's source hash or passing result is historical evidence.

Run independent investigation, checks, and implementation in parallel when ownership,
contracts, and working state permit it. A plan is not a mandatory sequential
pipeline. Serialize only actual dependencies or conflicting shared resources.

## Workflow

Use the shared `develop-code` workflow for scoped implementation. Load `design-code` for unresolved domain or ownership decisions, `review-code` for independent review and suggestion adjudication, and `verify-code` for diagnosis and behavioral evidence. These are conditional procedures, not four mandatory agents or sequential ceremonies.

Use `maintain-workflow` only for explicitly requested workflow cleanup or evaluation; it is not an automatic phase of every code change.

Give each coherent implementation unit one owner. Parallel writers may use isolated worktrees or explicit disjoint ownership in a shared tree when contracts and test inputs are stable. Read-only specialists should answer distinct questions. Keep one Git/integration owner for shared state; coordinate shared files, databases and simulators explicitly. Disjoint files do not make shared runtime mutations independent.

Existing implementation and process are evidence to assess. Consolidate or replace them when the authorized change demonstrates a clearer owner, smaller caller contract, or lower maintenance burden while preserving required behavior. Do not preserve an abstraction, model assignment, historical lease, or test merely because it exists.

## Product and trust boundaries

- Daily Classic is local-first and account-optional. Bundled Daily/tutorial answers make no secrecy claim. Imported personal history cannot become verified competition.
- Live answers, feedback, timestamps, scoring and transitions are server-owned. Normal clients cannot read private answers before reveal or directly mutate authoritative game state.
- Preserve authenticated command validation, grants/RLS, transaction/idempotency semantics, original retry identities, account isolation/deletion, and log privacy.
- Realtime signals request refresh; canonical snapshots own recovery and convergence.
- Swift and TypeScript rule implementations follow the shared versioned vector contract.
- Published Daily v1 puzzle assignments remain stable. Content evolution needs explicit schedule/version and provenance handling; there is no blanket ban on all future answer changes.
- Accessibility belongs to affected behavior. Source/render evidence does not establish OS-assisted interaction or physical-device acceptance.

Load the applicable product contract from the profile when changing these areas. The current task can revise workflow and implementation policy; consequential unresolved changes to product or trust contracts require an explicit decision.

## Task state and completion

Use one authoritative record for each task that needs durable tracking. Read the applicable active plan's current checkpoint, accepted decisions and remaining work; load detailed historical evidence only when needed. Resolve overlapping authority before affected writes without blocking independent work.

Match checks and review depth to the changed risk. Reuse useful existing proof, add or replace it when needed, and do not impose universal TDD or a no-tests rule. Record exact unverified requirements when the necessary environment is unavailable. Completion requires evidence for the scoped result, adjudicated material findings, and an accurate handoff.

## Accepted presentation work

The accepted target visual direction is in [docs/design-direction.md](docs/design-direction.md). Its applicable implementation plan owns product scope and dependencies. A workflow refresh does not implement that design, activate its kickoff, or mark it accepted at runtime. Preserve recorded human authorizations and outstanding acceptance. The Stamped plan is already Active; its current checkpoint records D16's resolved layout approval and the adjudicated independent final review, while OS/device acceptance remains human-deferred. S4 owns the transferred Phase 4 A9 checks. This maintenance does not resume product implementation or close that product task.
