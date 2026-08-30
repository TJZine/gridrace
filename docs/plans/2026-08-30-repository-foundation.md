Status: Historical
Scope: GridRace repository agent instructions, workflow rules, and durable task tracking
Owner: Primary Codex session
Started: 2026-08-30
Last updated: 2026-08-30

# Repository Foundation Plan

## Goal

Create a small, authoritative operating system for this repository by adapting the
useful agent, workflow, review, verification, and handoff conventions from
`frame-compare` to GridRace's SwiftUI and Supabase boundaries.

## Current snapshot

- Phase: complete
- State: verified and committed
- Next action: promote the Phase 0 product/architecture/game-rule/privacy authority-doc candidate from `docs/TODO.md` when implementation resumes
- Blockers: none
- Working branch: `main`
- Latest content commit: `f75934c docs: establish GridRace engineering workflow`

## Scope

- `AGENTS.md` as the short repository entrypoint.
- `docs/ENGINEERING_RUNBOOK.md` as the workflow, risk, verification, orchestration,
  planning, review, and handoff authority.
- `.agents/rules/general-guidelines.md` as a thin tool-specific shim that defers to
  the two authorities above.
- This tracked plan as the durable record of progress, decisions, review findings,
  verification evidence, and commits for the task.
- Only additional workflow or tracking files that a concrete present need justifies.

## Non-goals

- Implementing the iOS app, Supabase schema, Edge Functions, or word pack in this task.
- Copying Frame Compare's Python, Docker, Windows, release, or CLI-specific rules.
- Adding speculative repo-local skills, agent roles, workflow automation, or CI before
  executable project scaffolding exists.
- Claiming verification for Xcode, Supabase, or Deno surfaces that do not exist yet.

## Product and engineering invariants

- The backend remains authoritative for answers, validation, feedback, timestamps,
  scoring, and state transitions.
- Mobile credentials cannot read private answer data or directly mutate game state.
- Swift and TypeScript evaluators consume the same versioned test vectors.
- Realtime is a UI update channel; canonical snapshots remain the recovery authority.
- Security boundaries, RLS, secret handling, accessibility, and destructive production
  operations are never simplified away.
- The repository does not grow generalized architecture or automation before the
  current vertical slice requires it.

## Work breakdown

| ID | Work unit | Owner | Status | Evidence / output |
| --- | --- | --- | --- | --- |
| FND-01 | Audit Frame Compare instruction and orchestration patterns | `source_rules_audit` | Complete | Structure retained; Python/CLI/release machinery excluded |
| FND-02 | Adapt authority and verification model to GridRace | `gridrace_adaptation` | Complete | GridRace invariants, ownership, and staged command guidance delivered |
| FND-03 | Audit tracking, PR, and commit conventions | `tracking_commit_audit` | Complete | Single-plan, conventional-commit, and evidence-ledger guidance delivered |
| FND-04 | Implement repository authority files | Primary controller + bounded writer(s) | Complete | Entrypoint, shim, runbook, decisions, and backlog integrated |
| FND-05 | Independent review and finding adjudication | Fresh read-only reviewer | Complete | FAR-01 through FAR-05 closed in the closure review |
| FND-06 | Final verification and commits | Primary controller | Complete | Content committed as `f75934c`; tracker closes in this commit |

## Decision log

| ID | Decision | Rationale | Status |
| --- | --- | --- | --- |
| D-001 | Use one short entrypoint, one canonical runbook, and one thin rule shim. | Prevents competing workflow authorities. | Accepted |
| D-002 | Keep this plan as the single live task ledger. | The maintainer explicitly requested durable tracking; a second progress document would duplicate state. | Accepted |
| D-003 | Defer executable CI until executable project surfaces exist. | A workflow with invented commands would provide false confidence and immediate maintenance debt. | Accepted |
| D-004 | The primary controller alone stages and commits. | Avoids concurrent Git state changes while subagents share the worktree. | Accepted |
| D-005 | Do not copy Frame Compare's Zensical search front matter. | GridRace has no documentation search index, so the metadata has no current function. | Accepted |

## Agent ledger

| Agent | Mode | Assignment | Write boundary | Status |
| --- | --- | --- | --- | --- |
| Primary Codex session | Controller | Scope, decisions, integration, verification, commits | Whole task scope | Complete |
| `source_rules_audit` | Read-only explorer | Source instruction and orchestration audit | None | Complete |
| `gridrace_adaptation` | Read-only explorer | GridRace-specific authority adaptation | None | Complete |
| `tracking_commit_audit` | Read-only explorer | Tracking and commit convention audit | None | Complete |
| `implement_entrypoint_rules` | Bounded writer | `AGENTS.md` and thin rule shim | Assigned files only | Complete |
| `implement_runbook` | Bounded writer | Canonical engineering runbook | `docs/ENGINEERING_RUNBOOK.md` | Complete |
| `implement_decisions_backlog` | Bounded writer | Durable decisions and non-authoritative backlog | `docs/DECISIONS.md`, `docs/TODO.md` | Complete |
| `final_authority_review` | Read-only reviewer | Integrated authority consistency and risk review | None | Complete; five findings closed |

## Review findings

| ID | Severity | Evidence | Disposition | Action | Verification |
| --- | --- | --- | --- | --- | --- |
| FAR-01 | High | `AGENTS.md` allowed explicitly assigned workers to use Git, conflicting with controller-only Git ownership. | Accepted | Removed the exception; bounded workers never mutate Git. | Closed by reviewer |
| FAR-02 | Medium | Plan updates after every commit made a closeout commit's own hash impossible to record without another commit. | Accepted | Record the latest content checkpoint, label closeout “this commit,” and report its SHA in the handoff. | Closed by reviewer |
| FAR-03 | Medium | `docs/TODO.md` required durable plans for every candidate despite the runbook's lighter inline path. | Accepted | Made durable-plan promotion conditional on the runbook threshold. | Closed by reviewer |
| FAR-04 | Low | Angle-bracket path placeholders in the current command canon were not shell-safe copyable commands. | Accepted | Removed placeholder commands and explained scoped diff syntax in prose. | Closed by reviewer |
| FAR-05 | Low | Completed audits conflicted with an unchecked reconciliation item. | Accepted | Marked the reconciliation checklist item complete. | Direct plan inspection |

## Verification record

Risk: medium (workflow and authority changes only)

| Surface | Command / check | Result |
| --- | --- | --- |
| Whitespace and source leakage | `rg` scans across the authority set | Passed; no trailing whitespace or source-specific tooling outside this plan's audit history |
| Authority uniqueness | Count active-plan markers and runbook files | Passed; one active plan and one runbook |
| Markdown structure | `/usr/bin/awk` fence count | Passed; 10 balanced fences |
| Rule shim | `/usr/bin/ruby` YAML parse | Passed; `trigger: always_on` |
| Local references | `/usr/bin/ruby` Markdown-link existence scan | Passed; all local targets exist |
| Independent review | Fresh read-only review plus focused closure review | Passed; FAR-01 through FAR-05 closed with no remaining defects |
| Staged change | `git diff --cached --check`, stat, status, and full diff inspection | Passed; six task-owned authority/tracking files, no unrelated paths |

The first combined structural helper used unqualified `awk` and `ruby`, which were
not on the non-login command path. The same checks passed with their absolute system
paths. Product gates are not applicable because this task creates no executable
Swift, Supabase, Deno, database, word-pack, or CI surface.

## Commit checkpoints

| Commit | Purpose | Verification | Status |
| --- | --- | --- | --- |
| `758caef` | Track repository foundation work | `git diff --cached --check` | Complete |
| `f75934c` | Repository instruction, workflow, and decision baseline | Structural checks + independent review | Complete |
| This commit | Mark the foundation plan historical | `git diff --cached --check` and direct plan inspection | Ready to commit; SHA reported in handoff |

## Stop conditions

Stop and ask the maintainer before introducing a product invariant that conflicts
with the supplied specification, selecting a deployment/release policy not already
authorized, adding a dependency, or expanding this foundation task into product code.

## Closeout checklist

- [x] All three audits reconciled.
- [x] Authority files implemented with no broken references.
- [x] Tracking snapshot and ledgers updated.
- [x] Independent review findings adjudicated.
- [x] Risk-matched verification passes.
- [x] Task-owned files committed with conventional commit messages.
- [x] This plan marked `Historical`; closeout SHA reported in the final handoff.

## Closeout

The repository now has one short agent entrypoint, one canonical engineering
runbook, one thin rule shim, durable decision history, a non-authoritative backlog,
and a completed evidence-bearing plan. Executable product and CI gates remain
intentionally deferred until their real Swift and Supabase surfaces exist.
