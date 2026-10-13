# Friends beta implementation — orchestrator handoff

Prepared 2026-10-13. This is a kickoff packet, not an execution checkpoint.
Preparing it has not started implementation or authorized child dispatch in the
planning chat. The human's kickoff in the receiving chat supplies execution,
role/model-selection and callback authorization.

## Mission and authority

Implement the accepted two-player friends-beta invitation and rematch scope in
`/Users/tristan/Software/gridrace`, using
[orchestrate-implementation-chats](/Users/tristan/.codex/skills/orchestrate-implementation-chats/SKILL.md).
Keep the receiving orchestrator responsible for consequential decisions, finding
adjudication, integration, task state and truthful acceptance. Use separate local
implementation chats for the bounded units below.

Read first:

1. [AGENTS.md](../../AGENTS.md) and [.agents/project.md](../../.agents/project.md).
2. [Reviewed implementation plan](2026-10-12-friends-beta-implementation.md),
   including its controller-review resolutions. This owns implementation contracts.
3. [Roadmap](2026-10-12-friends-beta-roadmap.md), especially accepted product
   decisions and remaining release prerequisites. This owns product scope.
4. Shared `develop-code` for implementation; `design-code`, `review-code` and
   `verify-code` when their responsibilities apply. Load deeper guidance only
   for the affected responsibility.

The feature choices and engineering plan are already settled and reviewed.
Start implementation after current-state checks; do not replay brainstorming or
commission a new broad audit. Resolve routine implementation details within the
contract. Return a concrete conflict with evidence if source drift or execution
shows the plan needs a consequential change; continue independent work.

Planning provenance: source chat `01a13318-6ef6-7c83-aa71-92063a6559cd`, local;
accepted defaults in human turn `01a13368-91f4-7672-815d-aaebd8091330`, user message
`01a13368-921c-77a1-842b-41e2d9953b7c`. Planning child
`01a1331a-75a3-7531-8196-b5951a2ca07b` completed its assignment. These are evidence
references, not callback targets or active implementation workers. Do not message
the planning chat merely because its ID is here.

## Current source and preservation

Last observed: branch `dev/classic-mode`, HEAD
`e7db36fb05271a74b5b3246b6286dd03f8554627`. Rediscover status/revision and inspect
relevant drift; never reset or switch to this historical hash to fit the plan.

Planning-owned work is currently uncommitted:

- Modified `docs/NOW.md`.
- New `docs/plans/2026-10-12-friends-beta-roadmap.md`.
- New `docs/plans/2026-10-12-friends-beta-implementation.md`.
- This handoff.

Preserve the unrelated modified `.codex/agents/reviewer.toml` and all existing
untracked review prompts/reports, dictionary planning artifacts, `.codex/cache/`
and `.DS_Store` files. Refresh the actual inventory. Do not stage all, clean,
stash, delete or adopt these unrelated changes. Do not rewrite role presets.

Use this actual local checkout with explicit disjoint ownership. Do not create
worktree chats unless the human specifically requests that environment. The
plan files are untracked today: confirm every child can read them at the supplied
absolute paths rather than assuming another checkout/cloud host contains them.

## Accepted behavior — preserve the full scope

- HTTPS invitations with strict configured-origin validation and code fallback.
  Explicit Join confirmation; preserve navigation through sign-in/profile setup
  and relaunch. Never silently replace another race or an unresolved command.
  No-app page provides installation guidance and the code; reopen after install.
- True same-group post-match rematch with both players' consent, same round
  count and original creator. Return to a new lobby; creator starts explicitly.
  Previous results remain immutable. No manual resharing to reconnect the pair.
- Completed matches only, with eligible participants and a five-minute window
  from authoritative completion. Background/reconnect preserves valid offers.
  Cancel/decline closes an offer; any explicit re-offer uses fresh consent within
  the same original window. No persistent Home/last-opponent shortcut.
- Exclude every answer from the immediate predecessor and repeats within the new
  match. No series-wide ban, answer preselection, or change to Daily assignments.
- Preserve offline/account-optional Daily, account cleanup/isolation, server-owned
  game rules/state, secrecy, grants/RLS, original retry identities and canonical
  recovery. Larger groups, history, notifications and friends graphs remain later.

Do not weaken the reviewed engineering resolutions: passive reconnect never
selects a server race; explicit stale-pointer Resume uses a durable member join
pinned to the known match; backend-first rollout preserves old client/request
behavior without silently downgrading new commands; all v3 snapshots follow the
actor-first lock contract even when the read itself finalizes the match.
Read the complete plan for state transitions, receipts, signals, selection
epochs, admission, answer-pool failures, deletion and rollback.

## Role selection

The current repository TOMLs were inspected when preparing this packet. They
have no `name` field; the aliases below are the explicit registrations in
`.codex/config.toml`, not inferred filenames. Re-read the files on activation.
If they now provide `name`, use that name; if settings differ from this human
kickoff's selected pairs or are unsupported, report the mismatch without silently
substituting. Do not treat TOML sandbox fields as enforced chat permissions.

| Unit | Role and inspected settings | Why / ownership |
| --- | --- | --- |
| I1 invitation parser/store | `worker_luna`: `gpt-5.6-luna`, `xhigh`; `.codex/agents/worker-luna.toml` | Bounded deterministic parser, protected navigation store and focused tests with settled contracts. New owned files only; no route/project/session edits. |
| I2 backend | `worker`: `gpt-6.1-sol`, `medium`; `.codex/agents/worker.toml` | Transaction, locking, privacy, migration and compatibility judgment. One cohesive backend owner; stable wire fixtures first. |
| I3 native transport/recovery | `worker`: `gpt-6.1-sol`, `medium` | Cross-device lifetime, original receipts, generations, durable pointer changes and Realtime/snapshot composition. Own the plan's native service/session/recovery files. |
| I4 composition/UI/landing | `worker`: `gpt-6.1-sol`, `medium` | Routing, account/startup hooks and recovery presentation cross boundaries; this is more than isolated visual styling. Sole writer of assigned composition/project assets. |
| I5 integration verification | `worker`: `gpt-6.1-sol`, `medium` | Extend the real-client harness and diagnose observed failures with one runtime owner. Do not mark stubbed/static checks as integration proof. |
| Independent final review | `reviewer`: `gpt-6.1-sol`, `high`; `.codex/agents/reviewer.toml` | Read-only review of actual integrated source, requirements, security/privacy, concurrency, recovery, architecture and proof. |

Use these exact pairs when the human kickoff authorizes them. Preserve the
receiving orchestrator's user-selected model/effort; high reasoning or above is
appropriate. Do not launch a planner routinely: the plan is ready. Reuse a worker
for focused correction. Escalate an I1 problem to the stronger `worker` only with
a concrete reason within the kickoff's allowed role choices, preserving the scope.
No measured cost/token saving is claimed.

For every child, include its preset's actual responsibility instructions in the
prompt, including its configured-role first-response line. `create_thread` has
no `agent_type` and does not automatically load a TOML. Explicit `model` and
`thinking` arguments are required when the kickoff authorizes these pairs.
Read-only review is an instruction unless the actual tool environment enforces it.

## Activation, sequencing and shared resources

Use the implementation plan as the **single execution checkpoint**: add current
owner/source, unit status, dispatch IDs, active resource ownership, evidence and
remaining work there. Keep this handoff static and the roadmap for product
decisions; `NOW.md` remains navigation. Do not create another parallel status log.
Preserve Stamped S4/A9's existing acceptance owner and human deferral. Historical
activation text does not authorize moving or closing its checks. Reconcile actual
overlapping write ownership before dispatch without reopening completed repairs.

1. Refresh source/instructions and capture unrelated work. Resolve the receiving
   orchestrator's actual thread ID/host and human kickoff turn. Read current role
   settings and supported models, then `list_projects` to resolve this checkout.
2. Dispatch I1 and I2 in parallel with their exclusive ownership from the plan.
   I2 produces concrete v3 request/response fixtures and command/error contracts
   first. Review those against the accepted plan before I3 consumes them.
3. Start I3 after that contract is stable; it may overlap remaining backend work.
   Keep one native session/API owner and one migration/backend owner.
4. The controller handles early Xcode registration for new I1/I3 files so focused
   native tests can actually run. Workers do not compete for project-file writes.
   Explicitly transfer that ownership to I4 for final composition; do not defer
   every native check until the final UI unit or substitute a demo harness.
5. Integrate I1/I3 before I4's feature composition. I4 prepares landing/association
   assets and configuration inputs locally without inventing a real domain or
   publishing. Update current product/API/privacy docs under explicit ownership.
6. On stable integrated source, run I5 and one independent final review. Review
   can overlap checks on the same stable inputs if resources permit. Adjudicate
   findings, return focused corrections to their owner, and rerun affected checks.

One integration owner controls shared files and Git. One runtime owner controls
DB/Edge gateways, fixture changes, simulator processes and integrated builds.
Read the profile's actual resource precautions before any mutations. A project
name or historical run is not proof of a disposable database. Do not reset a
preserved stack or touch remote services implicitly. Use unique owned fixtures,
run-owned outputs and frozen package-resolution flags. No dependency refresh,
global workflow rewrite, broad refactor or paid commitment is part of this unit.

Keep Git changes local and uncommitted unless the human separately authorizes
commits; do not push, merge, deploy, distribute, purchase, send tester messages or
change external provider accounts. If commits are later requested, the controller
uses conventional commits with explicit owned paths and preserves unrelated work.

## Self-contained child packets and callbacks

Use the orchestration skill's handoff reference when composing each assignment.
Each packet must include the absolute plan path, exact unit, current source and
drift, chosen role/model/effort, approved decisions, owned files, adjacent owners,
frozen interfaces/fixtures, relevant tests, excluded resources, escalation rules
and completion contract. Do not send only “implement I2.” Supply contextual facts
from this packet and the plan; do not require children to scan the whole history.

The receiving chat's original **human kickoff** must explicitly authorize child
creation, selected model pairs and callbacks to that orchestrator. Record its
retrievable turn/message reference. This document or an orchestrator quotation
alone is not proof of human callback authorization. Each child verifies the human
source with `read_thread` before messaging the actual receiving orchestrator.
Do not guess a parent ID, reuse the ideation parent ID, or treat a queued
`clientThreadId` as a usable thread ID.

Children send one terminal completion/blocked report after their unit and checks:
identity, exact source/diff, changed files, actual commands/results, risks,
unresolved decisions and unavailable acceptance. They also leave their final
report in their own chat. Meaningful blockers may be escalated within scope;
avoid acknowledgment/no-op callback loops. No recursive child delegation.

Use local project-targeted `create_thread` with the actual `projectId`, the
selected `model`/`thinking`, and `environment: {type: "local"}`. Record returned
identifiers in the execution checkpoint and emit required created-chat directives.
Treat registration/setup failure as pending/failed, not permission to duplicate.

Continue useful independent work while children run. When exhausted, checkpoint
pending IDs/callback routes and end the turn. Do not keep the chat alive with
polling or sleeps. On callback or the next activation, use source reports and
nonblocking `wait_threads(timeoutMs: 0)` with cursors as needed, inspect the real
diff/evidence, and adjudicate rather than automatically accepting a child's claim.
If original callback authorization cannot be verified, the child leaves its
report for retrieval; do not invent consent or promise automatic continuation.

## Completion evidence and release boundary

Execute the implementation plan's verification matrix. In particular retain:

- Forward-preservation and clean-creation proof on properly owned local state;
  old receipts, result timestamps, RLS/privacy and v1/v2 compatibility.
- Real concurrent DB connections for offer/accept/cancel/deletion/selection races
  and snapshot-triggered finalization; serial assertions alone are insufficient.
- Native parser/storage/lifecycle proof, exact retry payloads, sign-in/profile
  return, invalid link/storage paths and stale cross-device pointers.
- Actual independent-client race → consent → successor lobby → next race,
  dropped/reordered signals and reply loss; a third client using one player's
  account for the specified stale-pointer case.
- Same predecessor exclusions, within-match nonrepetition and safe pool failure;
  no future answer disclosure or changes to Daily content/rules.
- Independent review and focused repair closure, with source-bound evidence and
  honest failed/skipped/unavailable observations.

Hosting/domain/Apple membership/provider identifiers are not yet confirmed. Finish
all feasible local source, assets, configuration templates and proof. Record exact
external prerequisites and keep external operations separate. Stamped S4's
human-deferred device checks, real link activation/signing/provider proof, corpus
distribution clearance, retention/backup/operations choices and broader report/block
beta-exit responsibilities are not satisfied by local software completion.

Final handoff must distinguish implemented/local-verified behavior from these
release gates, list relevant changed files and actual checks, give Git status and
remaining limitations, and identify any unfinished required local work. Do not
declare the whole friends beta launched, distributed or device-accepted.
