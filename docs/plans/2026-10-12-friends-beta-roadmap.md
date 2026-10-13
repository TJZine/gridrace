# GridRace friends beta roadmap and implementation plan

Status: Approved local friends-beta software implemented, verified and independently reviewed. The implementation plan owns completion evidence; human device/external release acceptance remains separately gated.
Date: 2026-10-12
Decision owner: main chat `01a13318-6ef6-7c83-aa71-92063a6559cd`, host `local`.
Source inspected: `dev/classic-mode`, `e7db36fb05271a74b5b3246b6286dd03f8554627`.

## Current checkpoint

The human selected a **friends-playable beta**, with **two players first and
groups next**, and **same-group rematch with both players accepting in-app**.
Fresh-room creation followed by sharing another invitation does not satisfy the
selected rematch scope. The human accepted the recommended post-match flow,
including reconnect recovery of valid offers, and explicitly deferred the
last-opponent shortcut until later. After the rematch opportunity ends, the first
beta uses the ordinary new-match invitation flow.
Apple Developer/distribution and hosted Supabase setup are
**neither set up nor confirmed**. These are planning inputs, not a verified
inventory of external accounts.

Human execution steering on 2026-10-13 treats this as pre-MVP: legacy new-race
and recovery-format compatibility is unnecessary. Active Live protocol/storage use
v3 only; obsolete client shapes/readers/shims are removed, and older clients require
an update. Current original retries and existing data remain safe. The implementation
plan records the exact human turns; invitation/rematch scope, privacy and
device/release obligations remain intact.

This document owns the roadmap and product decision queue. The
[implementation plan](2026-10-12-friends-beta-implementation.md) owns the execution
checkpoint and child dispatch map. Existing task records retain their acceptance/evidence ownership. In
particular, [Stamped S4/A9](2026-10-03-stamped-ui-refresh.md) remains Active and
human-deferred; this planning document does not resume or close those checks.
The October 8, 10 and 12 remediation checkpoints record completed software work.
Do not recycle their original findings into an outstanding bug list.

The original planning request authorized brainstorming, implementation planning
and separate planning chats. The receiving orchestrator's human kickoff now
authorizes local feature implementation and review; its retrievable authorization
is recorded in the implementation plan. Publishing, deploying, purchasing and
provider account changes remain excluded. New UI behavior below is
governed by the accepted behavior below and the existing Stamped visual direction. Material visual departures still need agreement.

## Outcome and boundaries

A friend should be able to install the beta, sign in, accept an invitation, play
a private two-player match, understand the reveal, and arrange another match
without developer assistance. Daily remains useful offline and signed out.

Retain 1/3/5 rounds, default 3; server-owned answers, scoring, deadlines and
transitions; clue-free opponent progress; original command identities across
uncertain responses; account isolation/deletion; and published Daily assignments.
Daily personal history never becomes verified competition. Preserve current
creator-controlled countdowns and account-deletion behavior unless explicitly
revised. No initial paid commitment is assumed.

## Evidence baseline

| Area | Current evidence | Roadmap implication |
| --- | --- | --- |
| Daily | Offline play, persistence, optional private sync, Hard Mode, statistics and sharing are implemented. | Protect the existing solo experience; do not rebuild it as beta scaffolding. |
| Live | Two players, manual codes, 1/3/5 rounds, recovery, reveal and standings are implemented and have recorded local independent-client proof. | Expand the invitation/replay loop before increasing roster complexity. |
| Reliability | [October 12 checkpoint](2026-10-12-maintainability-remediation.md) records accepted repairs, 375 ordinary native passes, and selected actual client scenarios. Earlier checkpoints retain broader source-bound evidence. | Reuse unaffected proof; run affected checks against each new integrated source. These numbers are historical, not tests run during roadmap planning. |
| Distribution configuration | Staging/Release public backend settings are empty and bundle identifiers remain placeholders in `ios/GridRace.xcodeproj/project.pbxproj`. Apple sign-in entitlement exists. | Shipping configuration/provider/signing need a concrete setup unit; source configuration cannot prove working distribution. |
| Acceptance | S4 owns deferred OS/device interaction. Later remediation records also retain provider/Keychain/cold Auth/outage and hosted acceptance limits. | Track the exact missing observations and fix reproduced failures, without calling an unperformed check a bug. |
| Content | Corpus integration and reproducibility evidence exist; distribution clearance remains unresolved. | Resolve the recorded release gate without restarting dictionary sourcing or altering published answers. |

The dependency investigator completed read-only analysis against the same HEAD.
The controller checked the decisive join/create/recovery/service/result paths and
accepted the missing-capability and dependency conclusions. No new defect was
established and no runtime checks were performed for this roadmap.

| Capability | Decisive current owner / evidence at the inspected revision |
| --- | --- |
| Invitations | `LiveMatchViews.swift:422,691` holds manual entry and code sharing; `AppRouting.swift:107,117` owns account presentation/return; `LiveMatchSession.swift:365` joins through account-generation guards. Native URL ingress is absent. |
| Rematch | `LiveResultViews.swift:61–78` has final actions but no rematch. `LiveMatchSession.swift:344` creates with a durable request; `LiveMatch.swift:142` has no rematch service command. |
| Groups | `202609260003_join_delete_serialization.sql:85–106` caps membership at two and assigns seat 2. Foundation seat/placement constraints, multiround start/deletion policy and strict Swift decoders also need coordinated change. |
| History | `LiveMatchRecoveryStore.swift:3` retains one selected match pointer; canonical snapshots already contain revealed rounds/standings. `LiveMatch.swift:142` has no account-wide list operation. |

Swift paths above are under `ios/GridRace/App/`; SQL paths are under
`supabase/migrations/`. The child chat retains the fuller evidence and existing
test map; these are revision-bound references, not stable future line numbers.

## Roadmap

| Order | Milestone | Player benefit | Completion boundary |
| --- | --- | --- | --- |
| Now | Friends beta foundation | Friends can actually install, authenticate and race across separate devices/networks. | Approved distribution/hosting path; signed build; real provider, deletion and recovery proof; applicable device/content/privacy gates. |
| Now, alongside foundation | Invitations and replay | Less code typing and less work to play again. | Agreed link flow and rematch semantics implemented with truthful recovery and accessible UI. |
| Next | Small-group racing, 2–8 | A whole group can play together. | Versioned roster/state/scoring contract, usable multi-player presentation, deletion/block behavior and independent-client proof across roster sizes. |
| Next, guided by beta feedback | Useful results and retention | Players can find previous races and understand their progress. | Owner-private Live history with explicit retention and deletion, separate from imported Daily history. |
| Later, evidence-dependent | Solo depth and helpful reminders | More reasons to return between live sessions. | Select among varied practice, personal Daily history browsing, or opt-in reminders only after observing demand. Each gets its own product contract. |

Group expansion does not require building Live history first. Invitations and
rematch should be useful independently of larger groups. Opponent presence may
join the group milestone if beta sessions show confusion about who is connected;
it must not infer online status from a local socket or imply readiness.

Report/block remains a required MVP/beta-exit responsibility. Design its join,
rematch and deletion rules before broader group access; do not treat private
invitations as a permanent substitute. Public matchmaking, chat, friends graphs,
public rankings, monetization, custom words, spectators and extra platforms remain
outside this roadmap's approved first milestone.

## Proposed implementation units

### B0 — Establish the release path

First unit: inventory available Apple membership/team, bundle identity, test
devices, distribution route, hosted project/region and invite-domain ownership.
Use read-only inspection and user-supplied account status; never request secrets
in a chat or plan. Produce a concrete setup checklist identifying existing versus
missing resources and any cost decision. Verify current official requirements
when selecting providers/distribution; this plan quotes no prices or quotas.

Official references checked during planning: Apple's
[distribution introduction](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-app-distribution)
states that uploading for TestFlight requires Apple Developer Program membership;
the [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
owns the current beta workflow. Apple's
[account-deletion technical note](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
is the implementation reference for provider-token revocation. Account membership,
provider configuration and successful revocation have not been inspected or proved.

Then prepare environment-specific configuration, signing/provider setup steps,
backend migration/seed/finalizer deployment procedure, compatibility checks and
rollback/recovery instructions. Preserve development/staging/production isolation,
the pinned toolchain, privileged-secret boundaries and Debug-only credentials.
Do not add a general deployment platform without a demonstrated need.

Acceptance: an identified signed build connects to the intended environment on
two real devices; actual Apple sign-in, cold Auth restoration, sign-out/deletion,
server deadlines and recovery work end to end. Inspect the actual bundle for
configuration and credential separation. Hosted setup, publication and spending
are separately authorized concrete actions after preparation, not effects of
writing this plan.

### B1 — Close applicable acceptance gaps and repair reproduced defects

Reconcile current source with S4's remaining checklist and the completed repair
records. Retain each original owner; link evidence instead of duplicating mutable
status. Prepare a focused device session covering VoiceOver actions/focus, Dynamic
Type, Reduce Motion, contrast/Bold Text, hardware input/haptics, Account flows and
Live recovery/Discard. Include real protected-storage/Keychain, cold persisted
Auth and non-cooperative network observations where the existing records leave
those requirements unverified.

The human-deferred hands-on checks wait for the human's readiness. Independent
software preparation may proceed. For each failure, record a reproduction,
affected owner and smallest coherent repair, then verify that behavior and any
cross-boundary consequence. Do not create a speculative general hardening pass.

Acceptance: exact build/device/action/results and any remaining limitations are
recorded in their owning task; affected failures are adjudicated. A screenshot,
mock, simulator geometry result or source review cannot close OS-assisted input.

### B2 — Invite links that survive sign-in and recovery

Accepted experience: share a private link from the lobby, keep the six-character
code as fallback, and show the intended room before joining. Retain the intended
invitation through account setup; never silently replace an unresolved saved race
or pending command. Handle malformed/unavailable/full/started rooms explicitly.
Opening a link grants no roster membership or private match access.

Accepted: HTTPS links, confirmation before joining, persistence through sign-in
and relaunch, and installation guidance plus room-code fallback when the app is
absent. Preserve an existing race and resolve pending commands before an explicit
switch. The engineering plan owns URL/state details; the actual domain remains a
release prerequisite. No automatic continuation through installation is promised.

Owner boundary: app routing owns external entry; session/recovery owns command
lifetime; the existing authenticated join operation owns admission. Preserve
account binding and validate all external input. Universal-link configuration
depends on B0's chosen domain/environment; parser and state behavior can be built
and checked locally once the contract is settled.

Acceptance: cold/warm open, signed-out and profile-setup return, duplicate taps,
account switching, active recovery, invalid/closed/full rooms and offline retry;
real link activation on installed devices plus the agreed uninstalled fallback.
Reuse join/recovery/security coverage and add only the missing entry-path proof.

### B3 — Same-group rematch with mutual in-app consent

**Selected by the human:** both players accept a same-group rematch in-app.
No manual resharing or code entry is required to reconnect those participants.
The previous result stays immutable and the successor match has a new identity.
One player's action cannot silently enroll the other player or start a countdown.

Accepted flow: either participant chooses Rematch from the final result; that
action records their own consent and presents the other participant with an
in-app offer. When the other player accepts, both converge on the same successor
lobby. Retain the round count and original creator, with the creator explicitly
starting the countdown as today. Decline/cancel leaves the completed result
available. The human accepted these defaults on 2026-10-12.

The server owns prior-member eligibility, offer/consent state and the successor
relationship. Derive the prior group server-side without exposing opponents'
Auth identifiers. Provide an authenticated, retry-safe command contract and
canonical read path; Realtime only requests refresh. Concurrent Rematch actions
must converge on one successor for the same accepted offer. Original request
identity survives lost replies and relaunch, with account-bound cleanup and
backward-compatible recovery storage. Do not replace an unrelated unresolved
create/guess intent to make space for a rematch.

Split implementation only at stable contracts: first settle the state/API,
deletion and recovery contract; then the transactional backend and native flow
may have separate owners, followed by integrated independent-client proof.
Reuse current create/lobby/standings facilities where compatible. Calling the
existing create operation from a result button alone is not this feature.
Invite links are not a prerequisite for the in-app same-group rematch.

The selected primary flow is post-match, for completed matches with both accounts
still eligible. The opportunity lasts five minutes from server-recorded final
completion; reconnect preserves a still-valid offer, and decline/cancel closes it.
The accepted new answer policy excludes the immediately preceding match's answers
as well as repeats within the successor. It does not exclude the entire series
or affect Daily. The engineering plan resolves cancellation/acceptance races,
explicit re-offer behavior, pool availability and old-client compatibility. A
persistent Home or last-opponent shortcut is deferred.

Acceptance: both players explicitly opt in and reach the same new lobby without
sharing a code; simultaneous actions, double taps, dropped/reordered signals,
lost replies and relaunch create no duplicate successor or consent. Decline,
cancel/expiry, account switch and deletion cannot enroll an ineligible player or
restore stale consent. Prove prior result/receipt immutability, unauthorized
offer/read/accept denial, old recovery compatibility, and unchanged countdown
authority. Reuse current create/recovery/standings proof plus actual two-client
offer, acceptance and replay; add affected OS-assisted action/focus acceptance.

#### Comparable-game evidence and last-opponent recommendation

Official product documentation checked on 2026-10-12:

- [Chess.com post-game actions](https://support.chess.com/en/articles/10328363-how-do-i-use-game-review-on-the-app)
  include rematch, a new game and review. Its
  [friend-challenge guidance](https://support.chess.com/en/articles/8588467-how-do-i-play-a-friend)
  distinguishes live challenges, which require the opponent online and expire
  after a few minutes, from Daily challenges that remain until accepted.
- [Lichess's official accessibility guide](https://lichess.org/page/blind-mode-tutorial)
  documents post-game rematch and a recent-opponents picker for a new friend
  challenge. This establishes a documented pattern, not identical UI on every client.
- [Words With Friends Classic support](https://zyngasupport.helpshift.com/hc/en/26-words-with-friends-classic/faq/20967-how-do-i-create-another-game-with-the-same-opponent/)
  documents rematch both at the conclusion screen and under Completed Games.

Inference: immediate rematch and later re-challenge are both established patterns;
their invitation lifetime needs to fit synchronous versus asynchronous play.
GridRace's live format favors a bounded post-match offer for the first beta.

Accepted first-beta direction: preserve reconnect
recovery of a still-valid post-match offer, and do not equate a background event
with declining it. After that opportunity ends, use the ordinary new-match flow
in the first beta. If sessions show players repeatedly seeking the same opponent
later, consider “Play again with [name]” under Live/recent results. It should issue a
fresh mutually accepted challenge with current eligibility and clear expiry;
it must not revive old consent or imply that the opponent is available. This
does not inherently require a friends graph, but it does require a reliable way
for the opponent to discover the offer. No global Home button, notifications or
persistent invitation inbox is approved by this comparison.

### B4 — Controlled friends trial

Integrate the selected B2/B3 scope with B0 and applicable B1 evidence. Resolve
content distribution, data retention/deletion, provider revocation and minimum
operational ownership before exposing the corresponding hosted data/service.
Broader report/block and beta-exit obligations remain explicit release gates.
Approve concrete backup/restore and failure-response arrangements; do not promise
that free hosting alone establishes operational readiness.

Acceptance session: two friends install independently, sign in, join a shared
invitation, finish a three-round match, see identical final standings and play
again. Include 1- and 5-round regression coverage, foreground/reconnect and lost
response recovery, deletion and offline Daily continuity. Confirm finalization
works without a creator actively driving the deadline, using the existing rules.

Start with direct session feedback: where help was needed, whether the reveal
was understood and whether players chose another match. Agree success criteria
before the trial. Do not add analytics by default; any telemetry needs its own
minimum-data, retention and deletion decision. No trial invitations are sent by
this planning task.

### G1 — Expand to 2–8 players after the two-player beta

Treat this as one coordinated contract change across database constraints,
authenticated commands, wire validation, session logic, roster/standings UI and
independent-client proof. It is not just changing a maximum-player constant.

Decide minimum start count/capacity selection, join-versus-start races, ties and
standings, host absence, and deletion when two or more survivors remain. Retain
pre-reveal secrecy. Agree compact and accessible roster/reveal layouts before
implementation. Define report/block effects on join and rematch with a usable
moderation and retention policy before the corresponding release.
Lobby deletion can leave gaps in seat numbers: preserve stable membership identity
and agree the decoder/ordering contract instead of assuming contiguous seats.

Evidence must cover 2/3/8-player boundaries, concurrent last-slot joins and
start/join, reconnect/late-join rejection, deadline/forfeit/deletion outcomes,
old-client compatibility, negative RLS and multi-client convergence. Use forward
migrations preserving representative existing results and original receipts.

### H1 — Personal Live history when feedback warrants it

Expose paginated server-owned past matches for the authenticated participant,
with canonical standings and authorized revealed detail. Do not copy Live results
into client-originated Daily history or present imported Daily results as ranked
evidence. Decide retained data and duration before promising an archive.

Reuse the existing canonical result/snapshot model where it fits. Add an
account-scoped listing boundary with query/index and privacy evidence, then an
accessible list/detail UI. Prove pagination, account switching, survivor
anonymization, deletion and forbidden cross-account access. Cached presentation
must not become a second authoritative score store.
History browsing must also leave the active race's recovery pointer and pending
command untouched; a read-only detail should not hijack the command session.

## Sequence, ownership and verification

B0 inventory and B2/B3 product decisions can proceed together. B1 preparation can
also proceed; hands-on acceptance retains the existing human deferral. Once
contracts are selected, disjoint invitation/replay work can overlap, but one
owner coordinates shared routing/session/project changes. B4 depends on the
integrated chosen feature scope and the actual release gates, not merely passing
local unit tests. G1 follows two-player beta feedback; H1 is independently selectable.

Each implementation child receives the current source, exact unit, approved
decisions, owned files, invariants, proof and escalation points. The main chat
owns priorities, consequential choices, finding adjudication, Git/integration
and this checkpoint. One runtime owner coordinates DB, simulator, generated
output and builds against stable inputs. Reuse a child for focused corrections.

Use shared develop/design/review/verify skills by responsibility. Apply one
independent review to consequential integrated changes and validate its findings.
Risk-matched gates include focused native lifecycle/routing/UI tests, Edge and
DB/RLS/idempotency proof when those boundaries change, shared rule vectors if
rules change, and actual independent clients for cross-boundary Live behavior.
No calendar estimates are committed before B0 and feature semantics are settled.

Feature rollback must preserve completed results, account data, published Daily
assignments and accepted retry receipts. Disable new entry UI if needed; do not
revert a deployed migration destructively or erase old receipts to simplify recovery.

## Accepted first-beta product decisions

The human accepted all three recommendations with “all three look good” in
parent turn `01a13368-91f4-7672-815d-aaebd8091330`, user message
`01a13368-921c-77a1-842b-41e2d9953b7c`, responding to the preceding three-option
summary in turn `01a13348-694d-71e3-b44a-9cfa8516628c`. These settle the remaining
feature-level choices. API shapes, database
locking, request identities, source ownership and test selection belong to the
engineering plan and do not require separate user preferences.

| Decision | Accepted first-beta behavior / engineering elaboration |
| --- | --- |
| Invitation entry and interruption | HTTPS app links plus room-code fallback. Opening a link shows a join confirmation, retains the intended code through sign-in/profile setup and relaunch, and does not automatically switch an active or unresolved race. Resolve pending commands and obtain an explicit switch choice before replacing the selected race. If the app is absent, show installation guidance and the code; ask the tester to reopen the link after installation. Do not promise automatic continuation across installation. |
| Rematch eligibility and lifetime | Completed matches with both accounts still eligible; same round count and original creator; both consent, then return to the creator-started lobby. A five-minute opportunity measured from server-recorded final completion, with no extension from repeated taps or requests. Background/reconnect alone does not decline; cancellation/decline closes that offer with no automatic resend. Eligibility is rechecked on acceptance, and explicitly moving to another race ends the player's old offer/consent. Serialize races between acceptance/cancellation; a created successor is recovered rather than retroactively erased. |
| Answers in an immediate rematch | Exclude answers from the immediately preceding match as well as duplicates within the new match, so the new race does not immediately reuse a revealed puzzle. This is accepted new scope; current source does not yet provide it. No lifetime/whole-series exclusion or new Daily policy. The engineering plan must establish available-pool handling without silently breaking the accepted rule. |

Acceptance of these behaviors makes B2/B3 ready for a concrete engineering plan; it
does not establish release readiness. Domain/team/project values can be named
prerequisites for external integration rather than invented now. Before friend
distribution, B0/B4 still require actual provider/signing/hosting setup, approved
retention/content/operations policies and applicable device acceptance. Report/block
remains mandatory for the documented broader MVP/beta-exit scope. No additional
spend or remote action is authorized by choosing the feature defaults.

## Decision queue

| Decision | State / recommendation | Needed for |
| --- | --- | --- |
| Target milestone | Selected: friends-playable beta. | Roadmap priority |
| First roster size | Selected: two players first, groups next. | Beta scope |
| External setup | Human: neither ready / not sure; inventory next. | B0 |
| Invitation contract | Accepted: confirmed link entry, durable pending code, explicit race switch and installation/code fallback. Domain selection belongs to B0. | B2 plan |
| Rematch experience | Selected: same-group rematch, both players accept in-app; no resharing requirement. | B3 scope |
| Rematch lifecycle | Accepted post-match/reconnect flow, same rounds/creator/lobby, completed-match eligibility and five-minute server window, with explicit cancel/decline behavior above. | B3 plan |
| Rematch answers | Accepted exclusion of immediately preceding answers; current behavior only excludes repeats within a match. | B3 plan |
| Last-opponent shortcut | Human explicitly deferred until later. First beta uses ordinary new-match invitations after the post-match opportunity ends. | Later product selection |
| OS/device checks | Existing human deferral remains; schedule when ready. | B1/B4 acceptance |
| Hosted policy and spend | Concrete provider, retention, content and distribution decisions remain open; no paid commitment assumed. | External setup / B4 |
| Beta success | Agree qualitative session criteria and feedback method; no automatic telemetry. | B4 |

## Historical planning dispatch and handoff

The [implementation orchestrator handoff](2026-10-13-friends-beta-orchestrator-handoff.md)
is the prepared kickoff packet with inspected role/model assignments. It is not
an execution checkpoint and its preparation has not dispatched implementation.

Original human request is retrievable in the main chat, turn
`01a13319-4a02-7831-92a0-2c9dffdbafa3`, user message
`01a13319-4b5e-7380-a856-9d30c826c003`. It explicitly invokes
`orchestrate-implementation-chats` for roadmap/planning while this main chat owns
judgment. Each child verifies the original human source before a terminal callback.

| Unit | Chat / executor | Ownership | State |
| --- | --- | --- | --- |
| Feature dependency investigation | `01a1331a-75a3-7531-8196-b5951a2ca07b`, local; user-configured default model, high reasoning (no model override) | Read-only source evidence for invitations, rematch, groups and history; no runtime/Git writes. Callback to this plan's main chat. | Complete; verified terminal callback received; controller accepted source-bound conclusions. No files changed or runtime proof claimed. |
| Feature implementation planning | `01a1331a-75a3-7531-8196-b5951a2ca07b`, reused local chat; unchanged configured model, high reasoning | Owns only `2026-10-12-friends-beta-implementation.md`; parent retains this roadmap/NOW/Git. Defines accepted B2/B3 contracts and unit handoffs; no implementation/runtime work. | Complete; focused revision adjudicated and accepted 2026-10-13. Engineering plan is ready for implementation; source review and document checks only, no runtime proof. No child work remains pending. |

The planning handoff above is historical. The human activated local implementation
on 2026-10-13; the [implementation plan](2026-10-12-friends-beta-implementation.md)
now records completed I1–I5 software, exact executor chats, independent review and
source-bound verification. B0/B1/B4 external/provider/device/release decisions remain
separate; Stamped S4/A9's owner and human deferral are unchanged. Do not redispatch
completed units from this historical planning map. New groups/history/report-block
candidates remain later roadmap work, not part of this completed two-player scope.
