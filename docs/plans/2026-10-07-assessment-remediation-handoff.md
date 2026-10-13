Status: Software remediation verified — S4/A9 product acceptance remains open
Prepared: 2026-10-07
Scope: Remediation packages from the shared-workflow read-only assessment
Orchestrator: the originating assessment/planning chat

# Assessment remediation implementation handoff

## Task and authority

The user requested a plan using `orchestrate-implementation-chats`, choosing
between the repository's `worker` and `worker_luna` presets for coherent units.
The human authorized execution with “okay you can start since you are the
orchestrator” in parent chat `01a1104d-b403-79a0-8ee9-e1effd692177`, host `local`,
turn `01a11817-66ac-7272-b5a6-bf210be9d9cb`, user message
`01a11817-66f7-7961-b726-58f46b9a2bbd`. This authorizes the selected implementation
units, separate chats, and coordination callbacks under the invoked skill. Verify
the original human turn before callbacks; this recorded quotation alone is not
callback consent. The original execution instruction did not authorize commits.
The human's subsequent “ensure proper commits are created once we are done”
authorizes local commits for the verified remediation. Remote publication/deployment,
unrelated messages and new acceptance claims remain outside this authorization.

The originating chat can remain the orchestrator; a replacement orchestrator can
use this handoff without inheriting its conversation. Use `develop-code` for
implementation, `design-code` for ownership decisions, `review-code` for
independent review/adjudication, and `verify-code` for behavioral evidence.
`orchestrate-implementation-chats` owns chat coordination and executor selection.
This is not a workflow-maintenance assignment.

Read `AGENTS.md` and `.agents/project.md`. Preserve the accepted design in
`docs/design-direction.md`, the product/trust contracts in the profile, and the
current checkpoint of `docs/plans/2026-10-03-stamped-ui-refresh.md`.

The Stamped plan remains the sole Active product plan and sole owner of S4/A9
acceptance. This handoff does not reactivate historical tasks or broaden that
plan's original UI-only assignment. Explicit execution of the remediation scope
is separate authorization for the listed owner changes. Before affected writes,
coordinate any overlap with the active Stamped owner. Record remediation dispatch
and integration status in the executing orchestrator's conversation dispatch map;
do not create a second Active plan or duplicate S4/A9's mutable acceptance ledger.
Directly affected acceptance evidence is linked back to Stamped by its controller.

## Source and work to preserve

Planning snapshot: branch `dev/classic-mode`, HEAD
`1fff974e1e247710a512b065e6b06dbb1e5a31b7`. The index and tracked working tree were
clean before this handoff was added. These facts are provenance, not execution
pins: rediscover the current checkout, branch, revision, and working state.

Existing unrelated untracked material was `.DS_Store`, `.codex/cache/`,
`docs/.DS_Store`, `docs/plans/GridRace-dictionary-finalize-and-integrate.md`, and
`docs/plans/gridrace-corpus-independent-checks.json`. Preserve it; do not stage,
overwrite, or treat it as the remediation authority. Rediscover any newer work.

The assessment was predominantly source tracing plus recorded evidence. Only the
portable pack and seed checks were freshly run, both passing. Native builds,
database checks, SDK timing experiments, hosted CI, and physical acceptance were
not freshly executed. Earlier Stamped geometry and Phase 4 integration evidence
remain qualified by their actual source and environment.

## Executor selection

| Unit | Preset | Resolved model / effort | Why |
| --- | --- | --- | --- |
| G1 Account lifecycle and escape controls | worker | gpt-6.1-sol / medium | Authentication, profile cancellation, coordinator state, persistence, and UI interact |
| G2 Live capabilities and timeout evidence | worker | gpt-6.1-sol / medium | Recovery identities, feature policy, and SDK cancellation require judgment |
| G3 Practice hardware input | worker_luna | gpt-5.6-luna / xhigh | Established model intents and sibling input implementations bound the change |
| G4 Durable native containment proof | worker | gpt-6.1-sol / medium | Target hierarchy geometry and negative controls require careful diagnosis |
| G5 Corpus pin enforcement and generator retirement | worker_luna | gpt-5.6-luna / xhigh | Exact checksum, output-preservation, and consumer-migration contracts |
| G6 Frozen native CI and checkpoint references | worker_luna | gpt-5.6-luna / xhigh | Mechanical changes with explicit existing policy |

Settings were read from `.codex/agents/worker.toml` and
`.codex/agents/worker-luna.toml`. At this snapshot those files have no `name` field;
aliases are the registered `.codex/config.toml` keys and configured-role markers.
Rediscover the current registration rather than inventing an alias or repairing
preset metadata as part of this task. Verify supported model/effort combinations
at dispatch and set both explicitly. No price or measured-savings claim is made.

Include each selected preset's current responsibility instructions in the child
prompt: `create_thread` does not apply role files automatically. Preset permissions
do not override the actual chat environment. Workers own bounded complete owner
seams and return consequential decisions to the controller; Luna owns units with
settled contracts and can make routine local implementation choices. Neither owns
Git integration, dependencies, unrelated abstractions, or scope expansion.

## Package contracts

### G1 — Account lifecycle and escape controls

Assessment items: failed-profile controls, cross-account import flag, and
authentication event consumption blocked by profile I/O.

Own `ios/GridRace/App/AccountModel.swift`, `DailyAccountCoordinator.swift`,
`AccountView.swift`, and related checks in `ios/GridRaceTests/AccountTests.swift`.
Controller owns cross-cutting architecture/screen-flow documentation updates.

Source traces: `AccountView.swift:184,228,243`; `AccountModel.swift:52,207,219,227`;
`DailyAccountCoordinator.swift:19,97,179,272` at the planning snapshot.

Chosen responsibilities:

- Apply authentication identity changes promptly, without awaiting profile I/O.
- Own cancellable profile work in the model, guarded by session generation so
  stale success and failure cannot alter a newer session. Preserve the observable
  loading/error behavior callers actually need; migrate existing callers/tests.
- Render existing Sign out/Delete controls whenever authenticated, including
  profile loading/failure, using the accepted existing presentation. No redesign.
- Bind pending guest import to account/lifecycle ownership, clear it on account
  replacement and failed/canceled staging, and preserve legitimate retry/conflict
  resolution for the account that requested it.

Prefer model-owned profile work over serializing authentication events behind
network calls: the latter cannot promptly isolate a replaced account. Prefer an
account-bound import state over another caller-side reset workaround. Do not add
a general task manager or new persistence format. If coordinator proof needs
injection, use a narrow factory through the existing `DailySyncRemote` seam;
do not invent a parallel service framework.

Required distinguishing observations:

- Suspend A's profile load; emit nil and then B; identity/cache presentation must
  change before A completes. Release late A success/failure; neither applies.
- Exercise initial restore/sign-in, retry, repeated errors, sign-out, deletion,
  and a same-user refresh while maintaining useful loading/error behavior.
- Suspend A's import; switch directly to B; B's successful sync must not mark B
  imported or hide its import offer. Preserve A's legitimate retry and conflicts.
- In an actual rendered signed-in/profile-failed view, lifecycle controls remain
  reachable; model actions preserve guest and survivor data on success/failure.

Existing engine lifecycle tests are complementary; constructing two engines for
the same UUID does not establish coordinator A-to-B behavior. Preserve generation,
late-response, storage-unavailable, deletion, and guest isolation obligations.

### G2 — Live capabilities and timeout evidence

Assessment item: Start/input policy split across feature and presentation.
Additional question: whether actual SDK requests cooperate with timeout cancellation.

Own `LiveMatchSession.swift`, affected callers in `LiveMatchViews.swift`,
`LiveMatchSessionTests.swift`, and capability checks in `LiveMatchViewTests.swift`.
Paths are under `ios/GridRace/App/` and `ios/GridRaceTests/`. Reserve test-file
ownership until G4's explicit handover. Transport changes require controller review
of demonstrated need; no backend/schema changes are included.

Source traces: session `:97,239,294,658`; presentation `:312,816`.

The feature exposes complete Start/input capabilities; views consume them without
repeating domain policy. Keep the captured original Start target internal and
preserve pending-intent recovery, watchdogs, version mapping, canonical revision
guards, server time, and server authority. Do not conflate a new Start capability
with eligibility to retry an already captured Start.

Verify creator/guest, incomplete/deleted roster, lobby expiry, later-round reveal,
terminal requester, deadline, in-flight command, pending guess, and original Start
retry cases. Existing capability tests may move to the owner; preserve distinct
rendering and request-dispatch obligations rather than blindly duplicating them.

Timeout work is initially verification: inspect the current SDK and observe a
controlled stalled real request where possible. Required observations are settled
command state, actual transport cancellation, retained original identity, and
rejection of late results after Home/account change. Cooperative `Task.sleep`
mocks do not establish a real hard deadline. Do not replace structured work with
unowned background requests merely to make a timer return. If a defect is proven,
return the correction design to the controller before materially changing lifetime
or retry semantics. If runtime proof is unavailable, return exact limits without
claiming a defect was reproduced or resolved.

### G3 — Practice hardware input

Assessment item: missing tutorial letters/Delete/Return handling.

Own `TutorialViews.swift` and directly related `TutorialModelTests.swift` checks.
Do not change tutorial rules, countdown/reveal ownership, or accepted geometry.

Connect hardware input to the same existing `TutorialModel.typeLetter`,
`deleteLetter`, and submission/error-event path as touch input. Use sibling
Daily/Live patterns without copying their domain state. Focus belongs to the
active playing route; release it at completion/exit, retain touch input, and do
not let hardware submission bypass repeated-error focus or terminal gating.

Required evidence: focused tutorial behavior, a frozen native build, and actual
letters/Delete/Return interaction including invalid/repeated errors and route
exit when target input is available. Model tests/builds alone leave attached-keyboard
acceptance open. Hand over test-file ownership to G4 if its collector needs it.

### G4 — Durable native containment proof

Assessment item: scroll-height/image-width assertions do not observe clipped
landscape board/keyboard/action regions.

Depends on settled G2/G3 inputs. Own native rendering/containment checks in
`DailyClassicModelTests.swift`, `LiveMatchViewTests.swift`, and tutorial test
fixtures only after explicit ownership transfer. Coordinate any shared test helper
or project registration with the controller. Do not change app design/layout
unless a reproduced defect is separately assigned to its owner.

Observe the real hosted view hierarchy, scene/safe-area/navigation geometry,
visible tiles, keys, actions, and full error/status notices. Prioritize default
SE portrait/landscape, adjacent Pro layouts, and accessibility reachability.
Preserve D15/D16 floors, full errors, six rows, and non-color feedback. At AX sizes
observe usable scroll reachability rather than demanding default containment.

Extend suitable existing native checks; do not replace them with screenshots or
an implementation-derived arithmetic oracle. Add a small native assertion helper
only if it serves these concrete checks. Prefer no new snapshot framework.

Demonstrate that a controlled clipping case fails the actual containment gate,
then restore and pass. Use an isolated fixture/source variant coordinated by the
controller, not concurrent mutation of shared app inputs. Preserve recorded S4
negative/positive proof; do not call simulated accessibility traits VoiceOver
acceptance. Return any actual defect with source, dimensions, and failing controls.

### G5 — Corpus pin enforcement and generator retirement

Assessment item: revision-index pin is asserted without verifying consumed bytes.
Included cleanup: superseded executable generator with one remaining denylist use.

Own `scripts/build_accepted_guesses.py`, `scripts/check_word_pack.py`,
`scripts/generate_daily_word_pack.py`, directly necessary Python fixtures, and
`shared/word-packs/daily-classic-en-US-v1-SOURCES.md` reference corrections.

Validate the actual revision-index bytes against the existing pin before parsing
or expensive transformation/output mutation. Do not attest the expected constant
without proving it equals the input. Test valid, mismatched, absent/unreadable
input and meaningful nonzero failure before outputs change. Keep other input-pin
obligations intact; do not broaden into corpus extraction or answer evolution.

Move `BANNED_ANSWERS` into its current validation owner, preserving the exact
policy and dependent seed checks; then retire the obsolete generator entrypoint
and update live references. Preserve historical provenance in Git/docs. Avoid
introducing a constants module solely to hold an already-owned small policy.

Run `python3 -B scripts/check_word_pack.py --checked-in-only` and
`python3 -B scripts/generate_supabase_seed.py`. Run the plain source gate when
exact pinned inputs are available. Compare existing pack/manifest/provenance/seed
bytes before and after: unchanged data is required here. Do not run manifest
writers, seed writers, corpus downloads, or extraction. Missing source inputs
are an unverified source gate, not a portable pass substituting for it.

### G6 — Frozen native CI and checkpoint references

Assessment item: native CI omits the existing frozen-resolution controls.
Included documentation correction: stale pending layout/review summaries.

Own `.github/workflows/ci.yml`, the targeted checkpoint references in `AGENTS.md`,
`.agents/project.md`, and `docs/plans/2026-10-03-stamped-ui-refresh-kickoff.md`.
Do not alter shared skills, host presets, hooks, dependencies, or active-plan status.

Use `-disableAutomaticPackageResolution`,
`-onlyUsePackageVersionsFromResolvedFile`, and `-skipPackageUpdates` in both native
CI commands. Preserve pinned tools/actions, CI events, and checkout credential
settings. Confirm the lockfile is unchanged during relevant frozen execution.
No weakening or package refresh is authorized to make the frozen check pass.

Replace stale mutable checkpoint summaries with authoritative plan references.
D16 layout approval and the earlier final review are completed; OS/device
acceptance remains open. Keep historical evidence and qualified prior passes.
Do not replay activation or imply the new remediation review was already done.

Check YAML/command wiring, references, and scoped diff. A current hosted execution
is a separate evidence requirement: no manual remote trigger is implied by this
handoff, and a local pass is not a hosted pass.

## Dependencies, checks, and shared resources

The five disjoint implementation units G1/G2/G3/G5/G6 can write concurrently.
G4 follows G2/G3's test-file handover and stable gameplay source. This is a
dependency graph, not a mandatory six-stage sequence. Limit concurrent chats to
actual useful ownership and host capacity; optional roles are not a fixed panel.

In the default local shared checkout, each writer owns only its assigned files.
The controller owns Git, integration, this handoff, cross-cutting documentation,
the Xcode project/lockfile, shared components, and shared runtime scheduling.
Children inspect their scoped diffs and leave changes unstaged. They do not
commit, stash, reset, push, recursively delegate, or edit another unit's files.
Ownership refinements return to the controller rather than forcing a fresh chat.
Worktree execution requires the user's explicit environment request.

Native checks must observe stable source: do not launch Xcode while other writers
change its app/test/project inputs. The controller schedules stable check windows
and run-owned simulator/derived-data outputs. Source work can overlap; shared
simulator/app/database work cannot silently overlap. G5 can run its read-only
portable checks independently because app source changes do not affect them.

Use profile discovery commands with frozen flags and record the actual destination.
Focused selectors initially include `AccountModelTests`, `DailyAccountCoordinatorTests`,
`DailySyncTests`, `LiveMatchSessionTests`, `LiveMatchViewTests`,
`TutorialModelTests`, and `DailyClassicModelTests`, choosing the affected subset.
After integrated native changes, run the relevant combined suite and clean Debug
build once on stable inputs. Recheck repaired failures; do not repeat full gates
merely because a different child ran them. Ordinary opt-in integration skips are
reported explicitly.

The full independent-client harness is selected if actual transport/recovery
changes or unresolved integration risk require it, not automatically for every
capability or presentation edit. Before any fixture/network experiment, inspect
the actual unlinked loopback target and obtain resource ownership. No database
reset, remote target, migration application, credential mutation, or destructive
cleanup is included. Preserve unrelated data and redacted evidence.

For each child, distinguish assigned implementation/check completion from
controller-owned combined verification and OS acceptance. If a check window is
unavailable, report that exact pending check, not a complete verified unit. A
meaningful scheduling blocker can return to the controller; no no-op callback loop.

## Independent review and completion

Commission one independent read-only `worker` chat after the integrated source is
stable, using `review-code` for requirements/correctness and design/standards.
Supply the complete owned diff, approved contracts, current source identity, and
actual evidence. Review account isolation, cancellation, durable retry semantics,
capability equivalence, native input/focus, and corpus fail-closed enforcement.
The role preset is not an enforced read-only sandbox; verify actual permissions
and prohibit writes in the review assignment. Reuse original writers for accepted
repairs and obtain targeted rereview when their risk warrants it.

Software closure requires adjudicated material findings, meaningful passing
checks, unchanged protected data/dependencies, and an accurate evidence handoff.
Record implemented, verified, and accepted separately. Deferred target gates can
leave software work ready while S4/A9 and release readiness remain incomplete.

Not scheduled: a forward migration solely to remove the duplicate SQL receipt
lookup; a separate test-slimming pass solely to remove the repeated evaluator
example. Their small benefit does not currently justify their migration or proof
cost. Retain them unless later authorized work provides a coherent reason.

Outstanding iOS acceptance stays with Stamped: actual VoiceOver order/repeated
errors/conflicts, OS Reduce Motion/grayscale, attached keyboard across all three
gameplay flows, physical haptic preference, Pro Max geometry/activation, native
Discard confirmation, Cancel targeting, Account outer import/conflict callbacks,
and deletion input. Honor the existing human deferral; do not schedule hands-on
checks or mark them passed implicitly. Windows app acceptance is inapplicable.

## Dispatch packet and callback procedure

At execution, resolve the actual parent thread ID/host through trusted context or
supported thread tools. Do not use the historical Stamped controller ID or infer
an ID from a title/path. Read the original human execution turn, retain its
retrievable reference, and include that authorization source in every packet.

Call `list_projects`, identify the actual GridRace checkout, and confirm the child
can access this handoff and its selected preset. Create local project chats with
explicit supported `model` and `thinking`; do not guess project IDs or silently
switch branches. Include in each prompt:

1. Exact unit, outcome, exclusions, current source/dirty state, and owned files.
2. This handoff's relevant section, current instructions, role responsibility
   text, rationale, and protected product/design/trust decisions.
3. Verification responsibilities, stable-input/runtime scheduling, existing
   useful proof, and exact outstanding target obligations.
4. Permitted local side effects, controller-owned Git/integration, escalation,
   and one terminal report contract.
5. Verified parent identity and original human callback authorization reference.

Record unit, real child ID, preset/model/effort, input source, owned paths,
dependencies, check ownership, and callback route in the parent dispatch map.
Pending client IDs are not real thread IDs; verify setup without duplicating
creation or sending to guessed destinations.

The child verifies human callback authorization through `read_thread` if not in
trusted context, then sends one terminal completion/blocked report containing
unit/child identity, exact source/diff identity, changed files, observed checks,
pending controller checks, limits, and consequential decisions. Also retain the
final report in the child chat. If authorization cannot be established, finish
there and leave the report for parent retrieval; do not invent callback consent.

The parent continues useful independent work, then ends idle turns with pending
IDs recorded. Authorized callbacks resume coordination; no polling/sleep loop.
On reactivation collect bounded reports via `read_thread` or nonblocking
`wait_threads`, inspect actual changes, and accept evidence rather than trusting
completion labels. Callback authorization never expands to unrelated chats,
Slack/email, publication, deployment, or Git operations.

## Software execution evidence — 2026-10-07

This is a completed-run evidence snapshot. Dispatch and adjudication belong to the
originating orchestrator chat; Stamped remains the sole S4/A9 acceptance owner.

All six packages were implemented using the selected presets. The same worker
performed one independent integrated review and a focused review of the later
Account test-fixture correction. No app correction was needed after verification;
the Account repair changed test fixtures and hierarchy observation only. Both reviews
established no material findings.

The integrated run used baseline HEAD
`1fff974e1e247710a512b065e6b06dbb1e5a31b7`, Xcode 27.0 and iOS 26.5 on
run-owned SE (3rd generation) and iPhone 17 Pro simulators. Before the subsequent
commit authorization, no commit or index mutation had been made. Published data,
rule vectors, SQL, project resources and the
accepted package resolution were preserved; 125 untouched tracked hashes and six
unrelated file hashes remained exact.

| Obligation | Observed evidence |
| --- | --- |
| Corpus pin enforcement and retirement | Two Python regression methods passed; portable pack and seed gates passed; full regeneration from exact pinned intermediates reproduced checked-in artifacts. The retired generator's exact denylist moved to the checker, and the regression command is wired into CI. |
| Gameplay geometry | Same-source SE and Pro runs passed four methods per device. Sixty product observations plus restored and deliberately clipped controls established actual hosted containment/reachability. Each clipped control rejected all five last-row regions; restored controls passed. |
| SDK cancellation/currentness | Three isolated real-SDK loopback methods passed. Both stalled requests closed their sockets at about 1.01 seconds with the same retry identity. Home completion saved recovery without reopening presentation; account replacement rejected a late attempted response. |
| Combined native scope | 240 methods completed: 231 passed, one expected clipping failure, two opt-in integration skips and six new Account fixture/render failures. Those failures were diagnosed and repaired in AccountTests only; all 27 AccountModel/coordinator methods then passed with zero failures/skips. Other tested source remained unchanged; the long unaffected capture matrix was not repeated. |
| Clean Debug | Frozen clean Debug build exited 0. Discovery, resolution, native tests and build used all three frozen flags; the package lock remained exact. |
| Configuration/docs | CI wiring/YAML and scoped diff checks passed. The active-plan pointers preserve resolved D16 and adjudicated earlier review while keeping deferred acceptance open. |

The first combined run's automatic owned simulator diagnostic collector stalled
after all methods had finished. The controller interrupted only that collector;
the completed failing test result, logs, process sample and interruption record
were retained. This does not convert that run into a pass. Later focused Account
verification and clean Debug completed normally. Earlier failed fixture/collector
runs remain retained alongside the final results.

Geometry observations use public UIKit hierarchy/frame APIs after a test-only
private accessibility automation bootstrap, which restores prior state and fails
on unsupported runtimes. Scene orientation, safe areas and navigation were
OS-derived; large/AX5 text size was injected. AX scrolling and screenshots do not
establish actual VoiceOver interaction. No portrait 44pt semantic-tile floor is
claimed; D16's landscape 48pt, letter 32×48pt and action 44pt obligations remain.

The SDK experiment used dummy configuration, a local fake Functions responder and
the existing in-memory recovery seam. It does not establish real Auth refresh
stall behavior, filesystem durability, real Auth/Edge/DB/Realtime acceptance, or a
separate measurement of the production ten-second budget. The two opt-in native
integration cases were skipped; earlier independent-client evidence is historical.
Hosted CI was not triggered.

S4/A9's existing human-deferred gates remain open: actual VoiceOver sequence and
repeated errors/conflicts, OS Reduce Motion/grayscale, attached keyboard in all
three gameplay flows, physical haptic preference, Pro Max geometry/activation,
native Discard, Cancel targeting, Account outer import/conflict callbacks and
deletion input. Software remediation does not close Stamped or release readiness.
Both run-owned simulators and owned responder processes were cleaned up; useful
private artifacts remain retained with the orchestrator.
