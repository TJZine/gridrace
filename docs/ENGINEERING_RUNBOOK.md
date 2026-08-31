# GridRace Engineering Runbook

This is the single authority for GridRace engineering workflow, ownership, risk,
verification, orchestration, review, commits, and handoff. Keep it practical: add
process only when a current product or engineering risk needs it.

## Entrypoint and authority

Start with [`AGENTS.md`](../AGENTS.md), then use this runbook. Consult
[`DECISIONS.md`](DECISIONS.md) for accepted product and architecture decisions,
[`TODO.md`](TODO.md) for the non-authoritative candidate queue, and the one
active file under [`plans/`](plans/) when a task needs durable tracking.

Authority is divided deliberately:

- `AGENTS.md`: short repository entrypoint, invariant summary, and authority map.
- `docs/ENGINEERING_RUNBOOK.md`: this workflow and quality authority.
- `docs/DECISIONS.md`: durable decisions, rationale, consequences, and revisit
  triggers; it is not a task-progress ledger.
- `docs/TODO.md`: non-authoritative candidate backlog; it is not current status, an
  approved plan, or a product contract.
- `docs/plans/**`: one active, decision-complete task ledger when durable tracking
  is warranted. Historical plans are evidence, not current instructions.
- `.agents/rules/general-guidelines.md`: a tool-specific shim only; it must defer
  to `AGENTS.md` and this runbook.
- Product and architecture documents added later: current product contracts for
  their named surfaces, not competing workflow authorities.
- Executable code, migrations, configuration, tests, and successfully run commands:
  evidence of the repository's actual behavior.

Do not create another runbook, current-status ledger, or second active plan.

## Discrepancies

When sources disagree:

1. Follow system, maintainer, and task instructions first.
2. Preserve the non-negotiable product and security invariants in `AGENTS.md` and
   this runbook.
3. Treat executable behavior and reproduced command output as current-state
   evidence, not automatic permission to change an accepted product contract.
4. Use `docs/DECISIONS.md` for the accepted intent behind architecture or product
   choices.
5. Treat active plans as progress records and `docs/TODO.md` as backlog candidates;
   neither may override product or security decisions.
6. Treat historical plans, stale prose, caches, and external examples as context
   only.

Correct clearly stale active documentation in the same change. If the mismatch
could alter game rules, privacy, security, data retention, deployment, a public API,
or an accepted architecture decision, stop and ask instead of guessing.

## Product and engineering invariants

These constraints survive refactors, scheduling pressure, and “simplification”:

- The backend selects answers, validates guesses, computes feedback and scoring,
  timestamps accepted actions, and owns match and round transitions.
- Mobile credentials never receive the answer before reveal, select private answer
  data, or directly mutate authoritative game state.
- Every exposed table uses least-privilege grants and tested Row-Level Security.
  Edge Functions validate the authenticated caller before privileged work.
- Guess submission and finalization are transactional and idempotent. A retried
  `request_id` returns the original result and cannot create a second guess.
- Server time controls countdowns, deadlines, ordering, and solve durations. Device
  time is display input only.
- Realtime events prompt UI updates; canonical snapshots recover state on entry,
  reconnect, foregrounding, timeout, inconsistency, and deadline.
- Swift and TypeScript evaluators consume one versioned set of shared test vectors,
  including duplicate-letter cases.
- Production logs and analytics never contain raw answers or guesses. Identifiers
  use appropriate privacy redaction.
- Accessibility, report/block controls, and complete in-app account deletion are
  product requirements, not polish to trade away.
- Production secrets stay out of the repository and app bundle. Development,
  staging, and production remain separate environments when those environments
  are introduced.
- The initial product remains the focused private live race. Do not introduce a
  generalized game framework, friend graph, chat, public matchmaking, rankings,
  monetization, or speculative compatibility layers without a new decision.

## Ownership and boundaries

Put behavior with the owner that shares its state, lifecycle, and reason to change.
Prefer the smallest design that satisfies a current requirement.

| Surface | Owner | Boundary |
| --- | --- | --- |
| SwiftUI presentation | Feature views | Render state and send intents; never call Supabase or evaluate authoritative guesses directly. |
| Feature/session state | `@MainActor` Observation models | Own tasks and cancellation; one match session owns shared match state across screens. |
| Domain and transport | Protocol-backed services and DTO mappers | Keep DTOs separate from domain models; centralize typed error mapping. |
| Authentication and notifications | Dedicated services | Keep provider details and token lifecycle outside views and game rules. |
| Realtime | Match realtime service | Deliver change signals and manage subscriptions; never replace snapshot truth. |
| Edge Functions | Explicit authenticated commands | Validate identity/build/input, invoke transactional database behavior, and return stable typed results. |
| PostgreSQL | Constraints, functions, RLS, and migrations | Enforce state, access, idempotency, and atomicity at the data boundary. |
| Private word data | Private schema and server-only code | No client grants and no pre-reveal projection into public data. |
| Shared rules | Versioned vectors plus thin Swift/TypeScript implementations | One algorithmic contract, independently executed in both runtimes. |
| Composition roots | App environment, backend function wiring, project configuration | Keep dependency assembly separate from feature behavior; change serially. |

Do not extract a wrapper, manager, repository, coordinator, protocol, or extension
point solely for symmetry or possible future reuse. Add an abstraction when it owns
a distinct present responsibility or creates a testable trust boundary.

### Shared-write serialization

Concurrent writers must have disjoint file lists. Serialize work that touches any of
these shared or order-sensitive surfaces:

- database migrations, schema ownership, seeds, grants, and RLS policies;
- shared game-rule vectors, their schema, and generated word-pack artifacts;
- API contracts, DTOs shared by commands, and centralized error codes;
- the Xcode project, package resolution, app composition roots, and environment
  configuration;
- CI or deployment workflows;
- authority documents and the active plan's decisions or checkpoint state.

The primary controller resolves overlap before dispatch and integrates all work.

## Command canon

### Available now

These commands are the current proved canon:

```bash
git status --short
git diff --check
git diff --stat
git diff --cached --check
git diff --cached --stat
git log -1 --oneline
python3 scripts/check_word_pack.py
deno fmt --check rules/typescript
deno lint rules/typescript
deno check rules/typescript/evaluator.ts rules/typescript/evaluator_test.ts
deno test --allow-read rules/typescript/evaluator_test.ts
supabase db reset
supabase test db
supabase db lint --local --schema public,private --level warning --fail-on error
xcodebuild -project ios/GridRace.xcodeproj -list
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -showdestinations
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
  -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' \
  -derivedDataPath /tmp/GridRaceDerivedData-test test
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug \
  -destination 'platform=iOS Simulator,id=1BCA3F5A-3228-4888-909E-ED86AE627221' \
  -derivedDataPath /tmp/GridRaceDerivedData-build clean build
```

Use `rg --files` and `rg` for discovery when available, but do not treat search
output as product verification. Scope every diff review by appending `--` and
concrete task-owned paths to `git diff` or `git diff --cached`; do not copy a
placeholder path into the shell. Also inspect overall status for unexpected edits.

The checked-in project currently proves these Deno, local Supabase, and Xcode commands
with Deno 2.9.5, Supabase CLI 2.115.0, Xcode 26.6, the installed iOS 26.5 runtime,
and the named iPhone 17 Pro simulator. The simulator UUID is local toolchain state:
rediscover it with the proved destination commands before reusing the build or test
command on another machine. No remote deployment or CI command is canonical yet.

### Candidate gates to prove and promote

Promote a command into the current canon only after its project/configuration surface
exists, the command succeeds in the supported local environment, and the same change
updates this section. Pin tool versions in repository-controlled configuration when
the relevant toolchain is introduced.

Expected gate families are:

| Future surface | Candidate command family; not yet executable canon | Promotion proof |
| --- | --- | --- |
| iOS build and tests | Proved above for the checked-in `GridRace` project and scheme | Rediscover the destination UUID when the supported local simulator changes. |
| Swift format/lint | Repository-selected Swift formatter/linter invocation | Checked-in config, pinned installation policy, and a clean run. Do not add a tool only to satisfy this row. |
| Supabase local stack | Pinned local CLI start, reset-from-zero, database lint, and database tests | Migrations and seed rebuild a clean local database; pgTAP/RLS tests pass, including negative users. |
| Edge Functions | Supabase function-specific Deno gates | Phase 1 proves only the pure TypeScript evaluator commands above; no Edge Function exists. |
| Word pack | `python3 scripts/check_word_pack.py` | Proved locally against the curated source and deterministic manifest. |
| Full vertical slice | Coordinated client/backend smoke procedure | Two independent clients converge, cannot read the answer early, reconnect exactly, and deduplicate a retried guess. |

Exact Supabase, database, Edge Function, and CI command spellings remain undefined
until those surfaces exist. Never invent them in a plan or CI workflow. Record a
missing gate as “not available” or “documented only,” not passed.

## Risk tiers and verification

Choose the highest tier triggered by any touched surface. Passing tests is necessary
evidence, not the whole definition of done.

| Tier | Typical changes | Planning and review | Minimum verification |
| --- | --- | --- | --- |
| Low | Prose, comments, or non-behavioral cleanup outside authority/security surfaces | Inline plan; controller diff audit | Structural Git checks, reference/path inspection, and rendered/manual inspection when presentation matters. |
| Medium | Workflow/authority changes, focused UI behavior, internal model/service logic, tests, a contained Edge Function, or non-contract refactor | Explicit task plan; independent review when novel, broad, or weakly covered | Low-tier checks plus focused tests and the available owner-specific build/lint/type gates. |
| High | Game rules, scoring, timers, state machines, auth, RLS, secrets, data deletion, migrations, API contracts, concurrency/idempotency, realtime recovery, shared vectors, project/composition roots, CI/deploy, or cross-boundary architecture | Durable active plan, checkpointed implementation, same-pass authority updates, and fresh independent final review | All available affected-surface gates, negative/edge/concurrency proof, clean rebuild where relevant, full owned diff audit, and explicit evidence for any unavailable gate. |

### Verification matrix

| Changed surface | Required proof once the surface exists |
| --- | --- |
| SwiftUI view/layout | Build; focused model/view tests; Dynamic Type, VoiceOver, contrast/color independence, and Reduce Motion inspection as applicable. |
| Game board/evaluator | Shared vectors in Swift and TypeScript; duplicate-letter properties; invalid input and final-guess cases. |
| Timer or ordering | Injected-clock tests; server timestamp/offset behavior; background, reconnect, and deadline recovery. |
| Feature/session model | Focused state-transition tests; task cancellation; duplicate/out-of-order realtime events; snapshot reconstruction. |
| Command/API | Auth and build validation; stable typed errors; success/error contract tests; retry with the same request ID. |
| Migration/schema | Clean reset from zero; constraints/indexes; forward path; database lint; task-owned SQL review. |
| RLS/private data | Positive and negative pgTAP identities; before/after reveal visibility; authenticated-client denial for private tables and direct writes. |
| Transaction/concurrency | Concurrent submissions/finalizers; row locking and uniqueness; rollback/partial-failure behavior; idempotent result. |
| Realtime | Event-driven refresh plus dropped/duplicate/out-of-order event recovery from a canonical snapshot. |
| Account deletion/moderation | End-to-end deletion/anonymization and token revocation contract; report/block authorization and blocked-room behavior. |
| Word pack | Deterministic regeneration; source/license record; normalization, duplicate and banned-term checks; manifest checksum. |
| Project/dependency/config | Clean resolve/build; lockfile/config diff; secret scan; minimum deployment target and environment separation review. |
| CI/deployment | Local equivalent gates first; configuration parse; least-privilege secrets; failure-path inspection; remote execution evidence before calling it verified. |
| Workflow/docs only | `git diff --check`; inspect every referenced path/command; confirm future commands are labeled; read the full changed authority set. |

For security or privacy boundaries, prove denial as well as success. For distributed
state, prove recovery and convergence, not only the happy event stream. If a required
environment is unavailable, state exactly what was not run, what substitute evidence
exists, the resulting confidence, and who must complete the remaining proof.

## Planning and progress tracking

Use one active plan for the repository. Create a durable dated file under `docs/plans/`
when the maintainer asks for tracking, the work spans sessions, or the risk/seams are
too substantial for an inline checklist. Otherwise keep the plan in the current task.
If a different plan is already active, stop and let the primary controller integrate,
finish, or explicitly supersede it before another plan is activated.

An active plan begins with:

```text
Status: Active
Scope: <bounded outcome>
Owner: <primary controller>
Started: YYYY-MM-DD
Last updated: YYYY-MM-DD
```

It must contain:

- goal, current snapshot, scope, and non-goals;
- invariants and accepted decisions that constrain implementation;
- checkpointed work units with owner, write boundary, status, and evidence;
- dependencies and serialization points;
- risk tier and verification matrix for the actual change;
- decision log, review-finding ledger, verification record, and commit record;
- blockers, stop conditions, next action, and closeout checklist.

Update the plan at checkpoint boundaries, after material decisions, when a blocker
appears, after review adjudication, and after each content checkpoint commit. Do not
narrate every shell command. `docs/TODO.md` may point to the active plan, but current
state, next action, blockers, evidence, and ownership belong only in the plan.

At completion, set `Status: Historical`, record the latest completed content
checkpoint and remaining follow-ups, and identify the tracker closeout as “this
commit.” Report the resulting closeout commit hash in the final handoff instead of
creating another tracking-only commit. Update `docs/TODO.md` only when the candidate
backlog itself changed. Historical plans must not silently reactivate.

## Checkpointed orchestration

The primary controller owns the goal, plan, decisions, integration, verification,
review adjudication, progress updates, staging, commits, and final handoff. Keep the
agent tree shallow; delegation is a means to isolate bounded work, not a target.

Default flow:

1. **Frame:** inspect authorities and current state; state goal, exclusions,
   invariants, risk, acceptance, and stop conditions.
2. **Partition:** split only along clear owner seams. Mark shared surfaces for serial
   work and assign exact disjoint write boundaries.
3. **Implement:** dispatch bounded units; the controller continues integration work
   and prevents overlapping edits.
4. **Checkpoint:** collect result packets, inspect every owned diff, run focused proof,
   update the plan, and resolve dependencies before the next wave.
5. **Integrate:** reconcile contracts and shared surfaces serially. No worker stages or
   commits.
6. **Review:** give a fresh read-only reviewer the final task/diff/proof/risk packet,
   not the implementation transcript.
7. **Adjudicate and verify:** reproduce valid findings, fix accepted ones, rerun the
   affected gates, audit the net diff and status, update tracking, then commit.

One implementation wave plus one final review is the default even for high-risk work.
Add another wave only for a material dependency or accepted finding. Do not create
recursive reviewer loops or parallelize tightly coupled changes.

### Compact worker packet

Every delegated unit receives a packet in this shape:

```text
UNIT | <bounded name>
OBJECTIVE | <decision-complete outcome>
OWNER / WRITE BOUNDARY | <exact files or read-only>
DEPENDENCIES | <authorities, inputs, prerequisite checkpoint>
INVARIANTS | <contracts that cannot change>
ACCEPTANCE | <observable result>
VERIFICATION | <commands or inspections the worker can run>
OUTPUT | RESULT | FILES CHANGED | PROOF | ASSUMPTIONS | BLOCKERS
STOP CONDITIONS | <questions returned to controller>
```

Workers may inspect broadly but write only inside their boundary. They must preserve
unrelated changes, never stage or commit, and return assumptions rather than burying
them in implementation. The controller reads the actual diff and reruns proportionate
proof; a worker's success report is not integration proof.

## Review and adjudication

Review for correctness and failure modes first, then security/privacy, contract and
state-machine drift, data/realtime convergence, accessibility, test quality, and
maintainability. Give extra scrutiny to trust boundaries, migrations, shared vectors,
composition roots, and generated/project files.

A review finding is not accepted by volume or authority. Record each material finding
in the active plan with:

```text
ID | severity | location | claim | evidence | disposition | action | verification
```

Allowed dispositions are `accepted`, `modified`, `rejected`, and `deferred`.

- Accept only after reproducing the issue or tracing a concrete violated invariant.
- Modify when the issue is valid but the proposed repair is broader than necessary.
- Reject with specific counter-evidence, not preference.
- Defer only when it is outside scope or needs a product decision; name an owner and
  revisit trigger in `docs/TODO.md` or `docs/DECISIONS.md` as appropriate.
- After an accepted review fix, the orchestrator performs targeted inspection of the
  changed seam and reruns affected proof. Do not commission a second reviewer cycle.

High-risk work needs one fresh independent final review after integration. A clean
review does not replace verification, and repeated clean reviews do not add evidence.

## Commit and handoff policy

Only the primary controller may alter the Git index or create commits during
orchestrated work. Workers must not run `git add`, `git commit`, reset, checkout,
stash, rebase, or other worktree-wide Git mutations.

Before staging:

1. inspect `git status --short` and separate task-owned from unrelated changes;
2. read the complete task-owned diff and run `git diff --check`;
3. run the risk-matched gates and record exact results or omissions;
4. adjudicate review findings and update the active plan/authorities;
5. stage explicit task-owned paths only;
6. inspect the staged diff and staged stat, then run `git diff --cached --check`.

Use small conventional commits with an imperative subject, for example
`docs: establish engineering workflow` or `feat(backend): add idempotent guess
submission`. A commit should represent one coherent, verified checkpoint. Do not mix
unrelated user changes, conceal generated artifacts, or rewrite published history.

The final handoff leads with outcome and includes:

- files and behavior changed;
- decisions and assumptions;
- verification commands and results;
- review findings and dispositions;
- commits created;
- unverified surfaces, blockers, and precise next action.

Never claim completion while required work remains only planned, an acceptance
criterion lacks evidence, or a high-risk omission has no named follow-up.

## Documentation freshness

Update active documentation in the same pass when changing:

- game rules, ranking, visible/hidden opponent information, or reveal behavior;
- backend/client ownership, trust boundaries, schema/RLS, state machines, command
  contracts, realtime recovery, or environment/deployment policy;
- public invite, notification, privacy, moderation, retention, or deletion behavior;
- supported Xcode/iOS/Swift/Supabase/Deno/tool versions and canonical commands;
- risk routing, verification, plan activation, orchestration, review, or commit
  policy in this runbook;
- the candidate backlog or active-plan link in `docs/TODO.md`;
- an accepted durable choice or superseded choice in `docs/DECISIONS.md`.

Delete stale references instead of leaving half-live guidance. Do not document a
future command, file, environment, or feature as present. Record source/licensing
provenance with word-list artifacts when that surface is introduced.

## Stop and ask

Stop and obtain maintainer direction before:

- changing an exact game rule, ranking tie-breaker, visible/hidden information rule,
  or MVP scope boundary;
- weakening backend authority, RLS, private-answer isolation, authentication,
  transactional/idempotent behavior, server-time ownership, log privacy,
  accessibility, moderation, or account deletion;
- selecting or changing production deployment, retention, telemetry, licensing,
  legal/branding, or secret-management policy beyond an accepted decision;
- introducing a dependency, architecture framework, generalized plugin/rules engine,
  compatibility layer, or CI/release system without a present requirement;
- resolving a destructive or irreversible data operation whose target or recovery
  path is unclear;
- proceeding through overlapping writes, unexpected worktree changes, an authority
  conflict, a failed high-risk gate, or an unowned required verification gap.

When stopping, preserve the active plan, state the evidence and exact decision
needed, and identify any safe work that can continue independently.
