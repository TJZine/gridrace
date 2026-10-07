# GridRace project profile

Reconciled on 2026-10-04 against `TJZine/gridrace`, branch `dev/classic-mode`, HEAD `a2523ec44654151542b3ceaefb42e28e0ece2ce0`. The kit proposal was prepared at merge `d9bca9b8bde04cc47850db34e3b00a930c57c066`. These are provenance, not pins for future work; rediscover revision, working state and toolchain.

Shared skills own general orchestration and quality procedures. This file owns GridRace-specific context and verification selection.

## Source map

| Question | Read |
| --- | --- |
| Current product behavior and exact rules | `docs/product-spec.md`, `docs/game-rules.md` |
| Owners, lifecycle, trust boundaries | `docs/architecture.md`, `docs/privacy-data-map.md` |
| Live commands, versions, snapshots and typed errors | `docs/live-api-contract.md` |
| Current presentation and navigation | `docs/screen-flow.md` |
| Accepted target presentation | `docs/design-direction.md` and the Active Stamped plan; `docs/screen-flow.md` owns the shipped checkpoint and outstanding acceptance stays in the plan |
| Accepted rationale and revisit conditions | `docs/DECISIONS.md` |
| Current scoped execution | Applicable active plan under `docs/plans/`; historical plans do not reactivate automatically |
| Word-pack transformation and evidence | `shared/word-packs/daily-classic-en-US-v1-SOURCES.md`, `ATTRIBUTION.md`, checker and builder |
| Executable CI/tool versions | `.github/workflows/ci.yml`, `package.json`, lockfiles and Xcode settings |

Start with relevant sections. Do not load all product documents and historical plans for every edit. Active progress belongs in its task record; NOW or backlog pages may link to it but should not duplicate mutable checkpoint details.

The Stamped UI plan is already Active. S0a/S0b and S2/S1/S3 are integrated; S4 owns Phase 4's transferred A9. The plan's current checkpoint records D16's resolved layout approval and the adjudicated independent final review; OS/device acceptance remains human-deferred and closeout remains open. Phase 4 is Historical with software, repaired-scan and review evidence intact. This maintenance does not resume or close that product task.

The kickoff is a continuation entrypoint, not a command to replay completed activation. Preserve D6 prerequisites, D9 isolation and S2-before-S1 integration when interpreting the recorded units. Historical model choices, callback protocols and machine paths describe prior runs; they are not reusable workflow requirements. Existing review-context caches use the selected profile and source state for freshness; do not treat a pre-migration cache as current authority.

## Domain and ownership

Daily Classic remains playable signed out and offline. Its local evaluator, explicit UTC schedule, immutable completion history and account-private synchronization do not establish verified competitive play. Guest and authenticated-account storage remain isolated. Preserve unavailable-storage behavior, account switching/deletion, immutable completion precedence, and generation/cancellation guards that reject late work overwriting newer state or recreating deleted caches.

Live racing uses authenticated commands and PostgreSQL authority. Normal clients never receive private answers before reveal or directly mutate authoritative tables. Preserve bounded command acceptance, authenticated identity, grants/RLS, private projections, transaction/locking/idempotency semantics and original request identities through uncertain responses, retries, relaunches and recovery. Required old receipts and API/build-version compatibility survive representation changes. Server time owns countdowns, deadlines and ranking; client time supports display. Realtime is a change signal and snapshots reconstruct canonical state after entry, reconnect, foregrounding, missed/duplicate events and pending requests.

| Surface | Responsibility and current location |
| --- | --- |
| UI | SwiftUI views render state and send intents in `ios/GridRace/App/`; no direct Supabase access or local authoritative-live evaluation |
| Feature/session | Main-actor Observation models own async work, cancellation and state shared across screens |
| Live transport and recovery | `SupabaseLiveMatchService.swift`, `LiveMatchSession.swift`, `LiveMatchRecoveryStore.swift`; strict wire mapping, account-bound original request identities, snapshot recovery |
| Account/Daily sync | Account services/stores, `DailyAccountCoordinator.swift`, `DailySync.swift`; auth lifecycle, private files and convergent immutable history |
| Edge | `supabase/functions/`; authenticate and validate bounded input/build, invoke transactional behavior, return stable typed results |
| Database | `supabase/migrations/`; constraints, grants/RLS, private data, server time, locking, atomic transitions and idempotency |
| Rule parity | `shared/test-vectors/game-rules-v1.json`, Swift tests, `rules/typescript/` |
| Corpus/build | `shared/word-packs/`, existing Python tools, Xcode resource registration |

These are current responsibilities, not mandatory class counts or abstractions. A redesign may change representation and consolidate layers if trust, lifecycle, version and recovery obligations remain explicit. No new dependency or framework is justified by the skill alone.

### Corpus boundary

Accepted guesses and answer scheduling have separate policies. Current Daily v1 preserves published answer assignments; source policy calls existing positions append-only. A task limited to guess expansion must preserve its scoped answer baseline. Broader authorized schedule/content evolution requires explicit versioning and compatibility evidence rather than an invented permanent no-answer-change rule.

Current accepted data derives from a frozen baseline plus pinned Wiktionary intermediates. Ordinary builds/CI must not download or extract that corpus. Retain transformation provenance and the repository's outstanding release-review status; an attribution file is not a completed distribution clearance.

Production logs and analytics never contain raw answers or guesses; redact identifiers appropriately. Production secrets stay out of source and app bundles. Keep development, staging and production separate when introduced. Bundled Daily/tutorial answer knowledge remains intentional local behavior. Accessibility, report/block controls and complete in-app account deletion remain product obligations in their current owners; this maintenance neither expands approved live scope nor removes later release requirements.

## Verification by affected behavior

| Change | Select evidence |
| --- | --- |
| Workflow/prose | Changed references/precedence, scoped diff check; no unrelated app build |
| Corpus | Portable evidence-chain gate; source regeneration for changed source-derived artifacts/transform when pinned inputs exist; bundle/load check when resource integration changes |
| Rule behavior | Same versioned vectors in Swift and TypeScript; focused duplicate-letter, invalid-input and terminal-state cases |
| UI/feature state | Appropriate build and focused state/lifecycle evidence; OS-assisted VoiceOver, Dynamic Type, Reduce Motion or contrast checks when affected |
| Live command/recovery | Relevant Edge and Swift checks; original retry identity, version mapping, delayed/out-of-order results and canonical convergence |
| RLS/private data | Authorized success and forbidden reads/writes, including pre/post-reveal identities |
| Schema/concurrency | Forward upgrade preserving representative existing fixtures, clean creation on disposable state, constraints/locks/idempotency and database lint |
| Cross-boundary live change | Real independent clients against the relevant Auth/Edge/DB/Realtime path; mocks and SQL assertions are complementary |
| Account deletion/isolation | Storage unavailability, account switch, late responses, deletion and retained survivor-data contract |
| Build/config/CI | Actual relevant build/event, package/resource/config review, secret scan; source configuration alone is not an executed pass |

Use existing focused checks during iteration. Run wider affected gates when the integrated scope warrants them, not after every small edit or solely because another agent ran a check. Repeat for new code, integration effects, a failure, questionable evidence or a remaining concrete risk.

Keep runtime evidence tied to source/build, fixture identity, target and observed result. Preserve useful redacted artifacts after cleaning run-owned state. Missing target proof stays explicitly unverified.

## Commands and prerequisites

Commands below were inspected in repository sources; they were not executed during profile preparation. Run from the repository root. Prefer repository-pinned tools.

### Portable/generated data

```sh
python3 scripts/check_word_pack.py --checked-in-only
npm ci
npm run check:seed
```

For source-derived changes with the exact pinned inputs:

```sh
python3 scripts/check_word_pack.py
```

The full source gate fails nonzero when intermediates are absent or regeneration fails. `--probe-intermediates` is informational and cannot substitute for it. `--write-manifest`, builders and `npm run generate:seed` change artifacts; invoke them only as part of the intended data change, then run plain checks.

### Shared rules and Edge Functions

```sh
deno fmt --check rules/typescript
deno lint rules/typescript
deno check rules/typescript/evaluator.ts rules/typescript/evaluator_test.ts
deno test --allow-read rules/typescript/evaluator_test.ts
deno fmt --check supabase/functions
deno lint supabase/functions
deno test --config supabase/functions/deno.json supabase/functions/
```

For Edge type checking, use the explicit handler/test list in `.github/workflows/ci.yml`. Keep that list authoritative rather than copying it into every skill.

### Native build

Discover the actual project and installed destinations:

```sh
xcodebuild -project ios/GridRace.xcodeproj \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -list
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -showdestinations
```

The inspected CI target is Xcode 26.6 and iOS 26.5, iPhone 17 Pro. Only use the following destination if discovery confirms it on the current machine; otherwise substitute the discovered supported simulator and record the deviation:

```sh
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/GridRaceDerivedData-test test
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/GridRaceDerivedData-build clean build
```

Use run-owned derived-data paths when multiple sessions may coexist. Do not reuse a historical simulator UUID or delete another run's output. Swift language mode is 6 and the app deployment target is iOS 18 at the audited snapshot. Preserve the checked-in package resolution unless the authorized change needs a reviewed update; use the conditional frozen-resolution procedure below when diagnosing accidental pin changes.

### Local database and live integration

Prerequisites include Docker, Deno, Node/npm and the lockfile-pinned Supabase CLI. Native two-client proof additionally needs macOS/Xcode, two suitable simulator containers and the required psql tool.

Useful existing non-reset gates once the task's local stack is ready:

```sh
npx --no-install supabase test db
npx --no-install supabase db lint --local --schema public,private,app_rls --level warning --fail-on error
```

**Reset and fixture mutation are destructive.** Before any such action establish the actual unlinked loopback project, inventory existing data, prove the target is disposable or preserve its required state, and obtain exclusive database/process ownership. A branch name is not proof of disposability. Never adapt these local steps into remote operations implicitly.

The historical Phase 4 forward-upgrade sequence uses local baseline `202609260004`, representative legacy fixtures, then `npx --no-install supabase migration up --local`. The later Daily convergence repair has its own `202610020001` forward baseline and preserved-stack application record. Select the actual affected migration's baseline and assertions from its plan; do not replay either reset for a workflow refresh. A clean reset cannot replace forward-preservation proof.

### Existing independent-client driver

The following procedure is preserved from the current runbook. Recorded past execution is evidence for its named source and environment, not an execution by this workflow migration. Read the actual script before use; do not rerun the full matrix for unrelated instruction edits.

```bash
PATH=/opt/homebrew/opt/libpq/bin:$PATH GRIDRACE_LOCAL_INTEGRATION=1 \
  bash scripts/run_live_match_integration.sh
```

First inventory the current unlinked loopback GridRace stack: ownership of existing
accounts, Daily rows and live rooms cannot be inferred from its name or an earlier
run. The controller starts the existing local stack and separate Edge gateway,
checks applied migrations and active scheduled finalizer, and owns the sole runtime
verification lease. This harness does not reset, start or stop the shared backend.
It uses unique owned Auth/match/non-answer fixtures and creates/deletes only its own
two simulators, preserving unrelated containers and data. It requires the installed
iPhone17Pro/iOS26.5 type/runtime and retained frozen SourcePackages cache at
`/tmp/gridrace-phase4-client-derived-test/SourcePackages`; keep the accepted lock
SHA256 `d6b069e121418166c3b844eb1c1b66fc2f0ccb715f0b9808405a14a9a68d0691` exact.
All Xcode checks, including discovery, use the frozen flags shown above.
The sourced credential scan searches hidden/ignored container files, supplies
fixed-string patterns on stdin and suppresses raw diagnostics. Only scanner status
1 establishes no match; matches, scanner errors and unavailable inputs fail.
`bash scripts/test_client_credential_scan.sh` proves these paths with dummy values.
A full integration PASS before this repair does not establish credential absence.

The command prints and retains a private `/tmp/gridrace-live-integration.*` proof
directory with logs, per-process xcresults, owned-fixture inventory and cleanup
status. Require exit0, no real-client skip/failure, all scenario markers and owned
cleanup success; inspect baseline preservation afterward. Budget about 40 minutes
for cold simulator/build setup, independent launches, original 180-second deadlines
and backend barriers; do not translate timestamps in the client deadline cases.
The current proof is 60 real client invocations plus 429 backend requests/142
snapshots, all passing. This is local Xcode27/iOS26.5 proof, separate from hosted CI,
OS-assisted/physical-device accessibility and distribution gates. Ordinary full
suite opt-in skips cannot substitute for this command.


## Conditional procedures preserved from the prior runbook

These procedures are loaded only for the affected task. They were documented at the audited baseline; this instruction migration did not run them.

### Frozen native dependency resolution

Use a task-owned derived-data directory. The following path is an example; choose an unused run-owned path before executing, and retain the same path for that run.

```sh
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
  -derivedDataPath /tmp/GridRaceDerivedData-resolve \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates -resolvePackageDependencies
```

Inspect the lockfile diff. A missing required transitive pin is a diagnosis to resolve, not permission to update unrelated packages or weaken the frozen check.

### Local forward migration and fresh creation

The disposal and ownership preconditions above apply before every reset. The retained Phase 4 baseline sequence uses:

```sh
npx --no-install supabase --version
npx --no-install supabase start
npx --no-install supabase db reset --version 202609260004
```

After that reset, create the representative legacy lobby/active/revealed fixtures described by the applicable migration plan and record their identities, successful receipts, grants/RLS and safe Realtime projections. Only then apply:

```sh
npx --no-install supabase migration up --local
```

Assert the preserved identities/results and changed contract before any fresh reset. When those fixtures are confirmed disposable, `npx --no-install supabase db reset` establishes clean creation from zero, followed by the affected database checks. A failed migration needs a diagnosis; retained user data needs a reviewed forward repair rather than a guessed destructive rollback. No hosted or remote deployment command is authorized by these recipes.

### Local gateway harness

The existing backend harness can run separately from native integration. It needs the same exclusively owned loopback stack and fixture controls. Serve Edge Functions in a separately owned terminal with:

```sh
npx --no-install supabase functions serve --log-level error
```

The existing local controller setup loads `API_URL`, `ANON_KEY`, `SERVICE_ROLE_KEY` and `DB_URL` from `npx --no-install supabase status -o env`. Do not echo or persist those values. Inspect the current target and environment-loading procedure before use; never substitute a linked or hosted project.

The inspected harness invocation is:

```sh
GRIDRACE_LOCAL_INTEGRATION=1 deno run \
  --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost \
  --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts
```

The psql path reflects the inspected macOS harness. Confirm that path and the script's actual subprocess invocation on the target machine; a path change requires a coherent harness/permission adjustment, not broad process permissions. This is privileged local fixture proof, not proof of native client integration or hosted acceptance.

### Tools, data and documentation

The prior command record identifies Deno 2.9.5, lockfile-pinned Supabase CLI 2.116.0, Node 20.20.2 in CI and the native target above. Recheck executable configuration before a run. No Swift formatter/linter gate is established by this profile; introduce one only for a demonstrated benefit with configured tooling and observed execution.

The obsolete `scripts/generate_daily_word_pack.py` entrypoint has been retired; its denylist validation now belongs to `scripts/check_word_pack.py`. The current portable check validates the frozen baseline, ordered answers, provenance/revision references and hash chain. The source gate additionally regenerates from pinned intermediates into temporary output and compares artifacts. Ordinary builds do not fetch the corpus.

Preserve raw-answer/guess privacy in production logs, environment separation, and the accepted no-initial-spend decision in `docs/DECISIONS.md`. Product scope, remote deployment, distribution and paid commitments do not expand merely because workflow instructions are rewritten.

Before integration, inspect overall working state and the complete owned diff. One owner stages explicit owned paths, inspects the staged diff, and avoids unrelated changes or rewriting published history. Update changed current product/contract documentation in the same change; archived plans remain historical evidence. Existing authorization carries across task handoffs.

## Current verification owners and evidence

The former workflow findings were repaired in later source before this refresh:

- `.github/workflows/ci.yml` includes PR targets `main` and `dev/classic-mode`, keeps the development push policy, provides an explicit manual trigger, and sets `persist-credentials: false` on both pinned checkouts. Inspect current configuration and the actual event/revision before claiming hosted coverage.
- `scripts/scan_client_credentials.sh` is the single sourced scan owner. It checks both nonempty privileged values using literal patterns on stdin, hidden/ignored file coverage and suppressed raw diagnostics. Only scanner exit 1 means no match; match/error/unavailable input fails.
- `bash scripts/test_client_credential_scan.sh` is the existing isolated dummy-fixture check. Reuse it when scan behavior or invocation changes instead of adding a second implementation or framework.
- The independent-client driver retains a private proof directory, original command status and cleanup status, and removes only run-owned fixtures/containers. Share sanitized evidence; retained raw artifacts remain private.
- The Phase 4 plan's approved PR repair section records later software and repaired-scan proof, retained-data validation and independent review. Do not replace that record with this kit's older report conclusions. OS-assisted A9, hosted/device acceptance and distribution remain distinct requirements.

These scripts, CI configuration and existing proof are unchanged by the instruction patch. Reuse valid evidence when its relevant inputs have not changed. Confirm current owners before proposing another repair. If current source has regressed, repair the existing mechanism with focused pass/fail/error evidence and preserve the same ownership and privacy boundaries.

## Resource and host policy

Use common skill routing rather than per-repository model names or a fixed agent count. Run independent investigation, checks and implementation concurrently when ownership, contracts and working state permit it. Give each coherent unit one implementation owner. Parallel writers use isolated worktrees or explicit disjoint shared-tree ownership, with stable test inputs and one owner for shared Git/integration state. A writer may discover adjacent files within its authorized responsibility; coordinate an ownership refinement instead of forcing a fresh agent for every file. Crossed trust/contracts, overlapping ownership, conflicting work or new external effects return to the controller.

Serialize database/migration/seed work, shared rule vectors, generated artifacts, API/DTO contracts, Xcode/project/lock configuration, composition and Git integration only where dependencies or concurrent changes would conflict. A check must observe a stable source/build/fixture state; run it in an isolated snapshot or coordinate writes to its inputs. Read-only reviewers do not write through shell tools. Keep Codex and Claude settings as thin host adapters with validated loading behavior.

### Host discovery and permissions

On this Mac the canonical shared skills are personal Codex sources under `~/.agents/skills/` and derived Claude deployments under `~/.claude/skills/`. Four coding skills permit normal selection; `maintain-workflow` is explicit-only. There are no project skill copies. The separate global owner manages those installations, global instructions and plugin/hooks; repository work does not rewrite them.

The user restored the project's `planner`, `worker`, `worker_luna` and `reviewer` presets on 2026-10-04. Codex registrations and model/effort defaults live in `.codex/config.toml` and `.codex/agents/`; Claude counterparts live in `.claude/agents/`. These are optional useful roles, not a compulsory roster or stage sequence. Use the shared skills for general procedure and choose relevant roles for bounded work. Personal `code_reviewer`/`code_investigator` (Codex) and `code-reviewer`/`code-investigator` (Claude) remain available alongside them. Root `CLAUDE.md` imports `AGENTS.md`; the Claude rule maps host-specific role and permission behavior.

Inspect effective restrictions for each invocation. Codex role defaults request a read-only sandbox, but a parent/runtime override can supersede them. Current full-access sessions cannot claim enforced read-only merely from role prose. Personal Claude specialists use Read/Grep/Glob; supply their Git diffs and command evidence through the controller. The restored project Claude reviewer disallows editing tools but may have shell access; its read-only instruction does not itself enforce a filesystem sandbox. Inspect the actual tool and permission controls for the chosen role. Do not loosen permissions to complete acceptance. Local installation does not establish Windows, WSL, SSH, cloud or CI discovery, nor unavailable authenticated Claude execution or GUI acceptance.

Use one independent final review for consequential integrated changes. Targeted rereview is appropriate when a repair materially changes security, contracts or architecture. Do not repeat full reviews solely for reassurance, and do not categorically prohibit a necessary second look.
