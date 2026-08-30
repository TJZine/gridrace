---
search:
  exclude: true
---

Status: Active
Scope: GridRace repository agent instructions, workflow rules, and durable task tracking
Owner: Primary Codex session
Last updated: 2026-08-30

# Repository Foundation Plan

## Goal

Create a small, authoritative operating system for this repository by adapting the
useful agent, workflow, review, verification, and handoff conventions from
`frame-compare` to GridRace's SwiftUI and Supabase boundaries.

## Current snapshot

- Phase: source audit
- State: in progress
- Next action: reconcile the three read-only audits into a GridRace authority map
- Blockers: none
- Working branch: `main`
- Commits created: none

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
| FND-01 | Audit Frame Compare instruction and orchestration patterns | `source_rules_audit` | In progress | Pending agent report |
| FND-02 | Adapt authority and verification model to GridRace | `gridrace_adaptation` | In progress | Pending agent report |
| FND-03 | Audit tracking, PR, and commit conventions | `tracking_commit_audit` | In progress | Pending agent report |
| FND-04 | Implement repository authority files | Primary controller + bounded writer(s) | Pending | File diff and structural checks |
| FND-05 | Independent review and finding adjudication | Fresh read-only reviewer | Pending | Finding ledger below |
| FND-06 | Final verification and commits | Primary controller | Pending | Verification and commit records below |

## Decision log

| ID | Decision | Rationale | Status |
| --- | --- | --- | --- |
| D-001 | Use one short entrypoint, one canonical runbook, and one thin rule shim. | Prevents competing workflow authorities. | Accepted |
| D-002 | Keep this plan as the single live task ledger. | The maintainer explicitly requested durable tracking; a second progress document would duplicate state. | Accepted |
| D-003 | Defer executable CI until executable project surfaces exist. | A workflow with invented commands would provide false confidence and immediate maintenance debt. | Provisional; review after audits |
| D-004 | The primary controller alone stages and commits. | Avoids concurrent Git state changes while subagents share the worktree. | Accepted |

## Agent ledger

| Agent | Mode | Assignment | Write boundary | Status |
| --- | --- | --- | --- | --- |
| Primary Codex session | Controller | Scope, decisions, integration, verification, commits | Whole task scope | Active |
| `source_rules_audit` | Read-only explorer | Source instruction and orchestration audit | None | Running |
| `gridrace_adaptation` | Read-only explorer | GridRace-specific authority adaptation | None | Running |
| `tracking_commit_audit` | Read-only explorer | Tracking and commit convention audit | None | Running |

## Review findings

No findings yet. Record each finding with severity, evidence, disposition, action,
and verification before closeout.

## Verification record

Risk: medium (workflow and authority changes only)

Planned proof:

- `git diff --check`
- parse any edited YAML with an available native or already-installed parser
- verify every path and command named by an authority file exists or is explicitly
  marked as future/not yet available
- inspect `git status --short`, the diff stat, and the full task-owned diff
- independent read-only review of the final authority set

## Commit checkpoints

| Commit | Purpose | Verification | Status |
| --- | --- | --- | --- |
| Pending | Repository instruction, workflow, and tracking baseline | Structural checks + independent review | Pending |

## Stop conditions

Stop and ask the maintainer before introducing a product invariant that conflicts
with the supplied specification, selecting a deployment/release policy not already
authorized, adding a dependency, or expanding this foundation task into product code.

## Closeout checklist

- [ ] All three audits reconciled.
- [ ] Authority files implemented with no broken references.
- [ ] Tracking snapshot and ledgers updated.
- [ ] Independent review findings adjudicated.
- [ ] Risk-matched verification passes.
- [ ] Task-owned files committed with conventional commit messages.
- [ ] This plan marked `Historical` with the final commit and next product action.
