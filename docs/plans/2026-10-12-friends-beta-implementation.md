# Friends beta: invitation and rematch implementation

Status: **Complete — approved local software scope implemented, verified and independently reviewed.** Human-deferred device/release acceptance remains open; deployment and release were not authorized.

Source: `dev/classic-mode`, `e7db36fb05271a74b5b3246b6286dd03f8554627`, inspected 2026-10-12/13. Planning owner: chat `01a1331a-75a3-7531-8196-b5951a2ca07b`; controller: `01a13318-6ef6-7c83-aa71-92063a6559cd`, local. Existing reviewer configuration changes, controller-owned NOW/roadmap changes and untracked artifacts are outside this assignment.

The [roadmap](2026-10-12-friends-beta-roadmap.md) owns priorities and accepted product decisions, including human acceptance in turn `01a13368-91f4-7672-815d-aaebd8091330`. This companion owns the reviewed implementation contracts and packets. [Stamped S4](2026-10-03-stamped-ui-refresh.md) retains deferred human OS/device acceptance; completed October remediation is not reopened. Source inspection is the evidence for this plan, not executed runtime proof.

## Execution checkpoint — 2026-10-13

**Complete: approved local friends-beta software implemented, verified and
independently reviewed.** Controller accepted the final review with no remaining
material finding or known local verification gap. Release readiness is separate.
The human subsequently authorized proper local commits. Backend, native and
integration changes are recorded in `4616201`, `bd095e9` and `84f037c`, with this
documentation closeout following them. No push, deployment, distribution,
purchase or external-provider change occurred.

Integration/acceptance owner: `01a13399-a6ba-7950-8ebe-0150ff49a59f`, host local.
Original human execution/role/callback authorization: turn
`01a13399-f2be-7182-9cfc-ece4f9685c3c`, message
`01a13399-f495-7cb1-83f1-2cbfbee86eca`, verified from the parent chat.
Human pre-MVP clarification: turn `01a133f4-830b-7681-9bad-5417a8eb4480`, message
`01a133f4-834b-7290-9b12-25ec09f57552`. Active Live supports build3+/snapshot3/
recovery3 only, without older-client readers, adapters, request shapes or migration.
Preserve current original retry identities and existing data. Unsupported recovery
bytes fail closed for explicit Discard. This supersedes historical compatibility
promises in the static kickoff; unrelated Daily/Auth/platform obligations remain.

Reviewed implementation source: `dev/classic-mode`, baseline HEAD
`e7db36fb05271a74b5b3246b6286dd03f8554627`. Final T frozen/current144 inputs match
`8fc49f0b67c19a54adad8eff2c2e6f1f17991c7062728ad78b08e52875c5fbfa`;
nine-file integration harness aggregate
`ed15f79475d0bc58984c5a37895a12d449d0e343dd4c2e626f653c4f52396ec2`.
Exact maps and aggregation recipe are in
`/tmp/gridrace-friends-beta-dn6t3g0z/i5/frozen-20261013t-manifest.json` and
`harness-source-ready.json`. Documentation closeout is outside those runtime inputs.
Unrelated reviewer configuration, October review/dictionary artifacts, cache and
.DS_Store work remain preserved. The kickoff handoff remains static.

| Unit | Chat / exact executor | Accepted outcome |
| --- | --- | --- |
| I1 parser/store | `01a1339b-3e41-7601-8704-0d4dee0ff875`; worker_luna, gpt-5.6-luna/xhigh | Strict configured-origin parser, protected account-independent navigation with fresh UUID generations; focused primitives and integrated consumers verified. |
| I2 backend | `01a1339b-47f1-7861-a64d-ec54fe0057f1`; worker, gpt-6.1-sol/medium | Current-only commands, canonical selection, mutual rematch, private receipts/cursors/exclusions/signals, actor-first locking and forward preservation verified. |
| I3 native | `01a1339e-2787-7223-8a92-c16b5af58f81`; worker, gpt-6.1-sol/medium | Current-only transport/recovery, original retries, marker/account/navigation/viewer fences; two accepted native P2 findings repaired and verified. |
| I4 composition | `01a133ba-f195-7462-8fbd-0184a7c45bdb`; worker, gpt-6.1-sol/medium | Root invitation/Auth/cleanup/confirmation flow, canonical rematch UI, local landing/configuration assets; current native render/lifecycle evidence accepted. |
| I5 integration | `01a13438-f90c-7c43-8aba-3de9ebbf035b`; worker, gpt-6.1-sol/medium | Real Auth/Edge/DB/Realtime/native matrix, controlled race negative, actual credential absence and precise owned cleanup; all source/runtime work stopped. |
| Independent review | `01a1343b-62ed-7112-950b-e284adc03831`; reviewer, gpt-6.1-sol/high | Final bounded source/evidence review complete, read-only throughout; no remaining material finding or known required local software gap. |

Controller owns final integration, Git and disposable backend closeout. No child
source/native/fixture work remains. The uniquely owned unlinked stack
`/tmp/gridrace-friends-beta-dn6t3g0z` uses project `gridrace-friends-beta-dn6t3g0z`,
API55421/DB55422. Initial inventory proved unique containers/volumes, no linked
markers and available ports. Final Auth/match/Daily/deletion-receipt counts are0,
feature off and owned Cron active before shutdown; all owned simulators removed.
Controller stopped only this stack with backup retention (project-ID filter
gridrace-friends-beta-dn6t3g0z), stop exit0. The run-owned Edge serving process
ended after its container stopped; no owned container remains running. Unrelated
retained stacks/volumes stay untouched. Proof and snapshots are retained privately.

## Accepted software evidence

| Contract | Source-bound evidence |
| --- | --- |
| Backend types, authority/privacy, locks and migration | I2 current172 Edge tests,940 DB assertions/eight files,11 real connection races, typecheck/fmt/lint, clean creation and forward byte-identical canonical/private/receipt/grant preservation. Report `i2-current-report.md`;28-file manifest aggregate `4287a3aacefa6a09f3144659c7558fb0aebed3e31be686045f64ad4996631c3a`. |
| Current native and repaired P2 obligations | `i5/native-gate-d/owner-gates.xcresult`:158pass/0fail/0skip, Session107/service21/recovery6/nonpaintcomposition21/admission3. All eight new distinguishing P2 regressions actually executed. Production inputs remain unchanged through T; later integration helpers compiled in actual focused runs. |
| UI/root/landing | I4 comprehensive222distinct run remains221pass/1fail, not green; corrected full completed-flow1pass and final composition23pass on identical final snapshot close all222 distinct scoped obligations without inflating repeats. Compact375x667/AX5 standings/history/3-round Offer/5-round Accept/Decline and new44pt targets rendered/scroll-reached; Node landing4pass and local unconfigured page inspected. Exact25owned/82frozen hashes matched; report `native/i4-current-report.md`. |
| Ordinary gameplay and original deadlines | D ordinary1/3/5, mixed3 ranking, process relaunch/real signal faults, stopped-client original180s Cron1/3 and deletion1/3 survivor boundaries, Daily/deletion-receipt positives retained. D/J original five-minute accepted-rematch/flag-off recovery proof retained. These earlier whole runners failed later fixtures and remain FAILED. |
| True rematch and cross-device selection | K full3/5 successor rounds, original creator/count, explicit Start, predecessor exclusions/new-match repeats, immutable predecessor, process recovery; one-round D/J proof. K host/third each1pass/0fail/0skip: real predecessor epoch2 → third Create3 → successor3/unselected, predecessor pointer retained, passive epoch unchanged and explicit pinned Resume succeeds. |
| Flag-off closure | K real native Decline1pass/0fail/0skip, HTTP200 unavailable generation1 settles the original pending request; current transport accepts unavailable only for Cancel/Decline. |
| Read finalization and native rematch signal | L snapshot1 after original180s with no clients and owned Cron paused; native Resume finalizes canonically. L isolated production rematch stream host/guest each1pass/0fail/0skip: actual dropped/reordered signals observed before canonical read, closure generation2 and gameplay history unchanged. |
| Actual invitation root | R focused wrapper exit0/cleanup0/run_completed1, native host/root each1pass/0fail/0skip. Real Auth/profile/explicit Join, shared trace of every original request across bound wrappers, newer protected/presented generation, original admission/old-marker acknowledgment, actual SDK retirement/nil → A identity fences and explicit app Sign Out clear. Owner reload is in-process, not whole-app process or OS-link acceptance. |
| Current backend integration | N focused wrapper21 registered scenarios/624requests/211snapshots, exit0/cleanup0/run_completed1. Includes actual authenticated exact rematch signal delivery/safe two-column payload and outsider silence. |
| Distinguishing negative | Current S copied variant differs in ONLY successor selected/epoch guard conjunct across144 inputs. Actual build and third client pass, real predecessor2 → third3 → successor3/unselected reaches exactly two pointer assertion failures552/559, no setup/timeout/probe failures. Expected exit65/completed0/cleanup0 remains FAILED, never a positive/full pass. Positive repository guard remains intact. |
| Actual credential absence and cleanup | R positive host/guest scans and current S expected-failure host/guest/third scans before disposal. Wrapper0 means both nonempty privileged patterns had underlying rg1-only no-match; match/error/unavailable fails cleanup. Earlier deleted D/K/L containers were not scanned and are not retroactively claimed. Sentinel entire row preserved then only owned sentinel removed; exact baseline hashes/counts and final zero inventory verified. |
| Uncertain scheduler result | T arms restore intent before dispatch after exact owned ID/active capture. Actual extracted shell control applies pause41 then returns17; cleanup restores exact41, verifies baseline and preserves nonzero17. All7 controls pass; the same control fails on S's previous order. No gameplay/deadline replay for this two-script-only change. |

Detailed sanitized matrix, exact result/log paths, per-source failure labels and
hash recipes: `/tmp/gridrace-friends-beta-dn6t3g0z/i5/FINAL-INTEGRATION-HANDOFF.md`.
All snapshots/results remain retained. No claim that a single default full-matrix
command finished green: completion rests on adjudicated source-bound scoped
positives, explicit failed historical wrappers and a meaningful expected negative.
No selected actual native case was skipped.

## Review resolutions and limits

The independent reviewer closed two native P2 mechanisms: automatic successor
follow must recheck canonical successor selection/current viewer epoch between
reads; valid Cancel/Decline unavailable receipts must settle instead of retrying
forever. Actual positive and guard-removal negative boundaries distinguish both.
A final fixture P2 armed scheduler restoration before an uncertain pause dispatch;
source and causal negative control close it. Other harness failures were repaired
without changing production: stale API/SQL, result-path collisions, rematch-signal
proof isolation, cold client readiness/relocated containers, premature model probes,
unsupported hot-signin and overly strong nil-snapshot assertions. Historical
failed whole runs remain failed. Two original native mechanisms, fixture ordering
and evidence claims are adjudicated; no remaining material finding was established.

Current retries, original identities, existing data, PostgreSQL authority, RLS/
grants/secrecy, account isolation/deletion, offline/account-optional Daily and
published content/rule vectors remain intact. Live v3-only profile/API docs agree.
Final package lock remains
`d6b069e121418166c3b844eb1c1b66fc2f0ccb715f0b9808405a14a9a68d0691`.
Actual native target was Xcode27.0/iPhone17Pro/iOS26.5; source/render/tablet or
fixture evidence is not OS-assisted interaction or physical-device acceptance.

**Human-deferred release acceptance is unchanged:** real signed universal-link/
domain association and no-app installation, Apple-provider restoration/deletion,
physical-device/protected-storage/VoiceOver/hit-region/keyboard/haptics behavior,
intended hosted environment/scheduling/log policy, content clearance and retention/
operations decisions remain with their documented owners. Stamped S4/A9 is neither
closed nor resumed by this task. Existing toolbar36pt observation remains calibrated
render-only/S4. Actual host/team/provider identifiers are not invented; default
origin configuration remains empty and manual code fallback works. No deployment,
distribution, tester messages, provider changes or purchases are authorized.
Local commits were subsequently authorized as recorded in the checkpoint above.

The contracts below remain the accepted implementation design. Original planning
review text is provenance, not outstanding software work.

## Scope and architecture

B2 delivers HTTPS invitations, explicit Join, installation guidance/code fallback and durable navigation through authentication, profile setup and relaunch. B3 delivers a true two-person rematch: both opt in, same round count/original creator, fresh lobby, explicit host start. Only completed matches with eligible existing accounts qualify. The opportunity ends five minutes after authoritative completion. Exclude predecessor answers and repeats within the successor. Daily, larger groups, history, notifications, persistent Home challenges and a friends graph are unchanged/out of scope.

Keep app ingress separate from account-owned commands. Keep rematch authority in private PostgreSQL state, expose it through versioned canonical snapshots, and reuse the Live session's lease, recovery and signal machinery. A client-only Create shortcut cannot provide mutual consent. Rewriting completed match rows as a new game would destroy result identity. Neither alternative satisfies the selected scope.

Current source owners, relative to the repository root:

| Responsibility | Existing owner and decisive baseline |
| --- | --- |
| Routing/account return | [AppRouting.swift](../../ios/GridRace/App/AppRouting.swift), `DailyAppView`, profile-ready account-sheet dismissal; [GridRaceApp.swift](../../ios/GridRace/App/GridRaceApp.swift), startup recovery |
| Live operations/lifetime | [LiveMatchSession.swift](../../ios/GridRace/App/LiveMatchSession.swift):344 create, :365 join, :752 guarded snapshot application; [LiveMatchRecoveryStore.swift](../../ios/GridRace/App/LiveMatchRecoveryStore.swift), protected account file |
| Wire/events/presentation | [SupabaseLiveMatchService.swift](../../ios/GridRace/App/SupabaseLiveMatchService.swift), [SupabaseMatchRealtimeService.swift](../../ios/GridRace/App/SupabaseMatchRealtimeService.swift), [LiveMatchViews.swift](../../ios/GridRace/App/LiveMatchViews.swift), [LiveResultViews.swift](../../ios/GridRace/App/LiveResultViews.swift) |
| Admission/results/deletion | [latest join replacement](../../supabase/migrations/202609260003_join_delete_serialization.sql); [multiround migration](../../supabase/migrations/202610020001_blind_race_multiround.sql):64 create, :205 finalize, :299 start, :685 snapshot, :880 deletion |
| Edge/permissions | [shared command boundary](../../supabase/functions/_shared/command.ts), existing function handlers; [safe revision projection](../../supabase/migrations/202609040001_match_revision_signal.sql) |

## B2: invitation contract

Use `https://<configured-invite-host>/join/<CODE>` with exactly six ASCII characters from `[A-HJ-NP-Z2-9]`; accept ASCII lowercase and canonicalize uppercase. Each build has an explicit environment-specific origin allowlist. Reject HTTP, credentials, nondefault ports, unrelated hosts, extra path segments, percent-encoded separators/code characters, query strings and fragments. Do not follow redirects to discover an invitation. Actual domain/team/application identifiers are B0 inputs, never invented constants. The same parser contract applies to the minimal static landing page; it displays the code and installation instructions without calling a roster/preview API, analytics or third-party resources. Tester reopens the link after installation; no deferred-install continuation is promised. Keep manual code entry.

Add one bounded `PendingLiveInvitation` navigation value: format, normalized origin/code and replacement generation, with no identity, bearer, roster, consent or command UUID. Store atomically in a protected app-level file outside account caches. Persist before claiming the invitation is saved; on unavailable/corrupt storage show Retry/Discard without losing existing recovery. App ingress owns it even while startup/account UI is unavailable. It survives sign-in/profile completion and process death, but never constitutes consent under any account. Confirmation names the code and current account, not an unjoined roster. Server join decides expiry/admission; local receipt time never grants validity or invents a room expiry.

Duplicate same-code links are no-ops. A different link while one is pending offers Keep current/Replace invitation; replacement is persisted before presentation. No deep-link queue. An invalid link leaves all saved state intact. Successful join, explicit dismissal and explicit sign-out/account deletion clear navigation intent; a clear failure remains actionable and hidden from the departed account's automatic presentation. Account switching leaves a pending external invitation only as an unconfirmed code, requiring a new Join confirmation; prior account-owned join consent cannot transfer. Arrival while account cleanup is blocked is stored as navigation only and waits for cleanup.

Opening or authenticating never joins. Join waits for profile readiness and durable resolution of any existing create/guess/rematch/join request. If another race is selected, confirmation explicitly switches races; cancel preserves both the race and invitation. Starting the confirmed join persists an account-bound join request before network dispatch. Keep the old selected pointer until join success and successful local persistence; failure does not pretend a switch occurred. After a lost reply/relaunch, retry the exact request, then subscribe/fetch the admitted room. Clear the matching navigation generation only; a later arriving invitation must survive an older join response. Existing presentation/account/command generations fence all late work.

## B3: authoritative lifetime and states

`matches.completed_at` already exists and current finalization writes it together with the final round's completion. Current schema requires it for completed matches, including legacy one-round matches. Use that exact timestamp; never migration time, first offer time, client time or last activity. Eligibility requires a completed final revealed round, matching nonnull authoritative completion timestamps, exactly two nondeleted members backed by current profiles, and complete predecessor answers. No timestamp backfill is needed for valid current rows. Migration audits representative legacy rows; unexplained inconsistent rows stop migration for adjudication rather than being made recently eligible. The new private context is created lazily from validated existing facts, so an old completed match's deadline stays in the past.

Deadline is `completed_at + 5 minutes`. Sample server wall time **after acquiring all eligibility locks**; accept only while `now < deadline`. Lock-wait transactions cannot use an earlier transaction timestamp to extend consent. Existing gameplay timestamp semantics remain unchanged. Return evaluation time/deadline only in the roster-authorized completed-result rematch projection. They are not new pre-reveal action timestamps.

Store a private context keyed by predecessor match: current offer generation, state/reason, initiator member ID, consenting member IDs and captured participation epochs for **both** players (including the invitee before consent), revision, immutable deadline, and eventual successor UUID. Member IDs reference the existing anonymizable roster, never reveal Auth IDs. Persist only the current generation; request receipts preserve old outcomes. A unique predecessor-to-successor relationship allows at most one successor for that predecessor. It does **not** constrain the user pair or a successor's own later rematch. Keep an accepted successor UUID as a tombstone if ordinary deletion later removes its lobby; never manufacture a replacement successor for the old result.

| State / action | Atomic meaning |
| --- | --- |
| Eligible, generation 1 | No consent yet; Rematch sends an explicit `offer` for generation 1. |
| Offered | Initiator's action is their consent. Other participant's `accept`, or simultaneous `offer` for the same generation, records their own consent. |
| Accepted | Second consent atomically creates exactly one successor with both members and returns its identity. Both clients discover the same lobby. |
| Cancel / decline | Consenting player may cancel; nonconsenting player may decline. First committed close wins over an uncommitted accept. Clear consent and close this generation. |
| Explicit re-offer | Before the original deadline, either player may choose Offer again for the next generation exposed by the closed-state snapshot. Only that new action supplies consent. No automatic resend, inherited consent or reopened generation. |
| Expired / ineligible / moved | Deadline, deletion or a consent epoch invalidation closes the current offer. Expiry/deletion cannot be re-offered; moved/cancelled/declined can be freshly offered while eligibility/window still hold. |
| Accepted before cancel/departure | Successor remains real. Return canonical accepted state; cancellation cannot roll back it or its results. Explicit later navigation may leave it through existing behavior. |

Backgrounding, disconnect and Home do not decline. Keep bounded final-result recovery while visible/foreground until deadline or terminal resolution; Resume fetches afresh, even after the window, to discover an acceptance committed before expiry. No background polling or inbox. Home is not reopened by late replies. On canonical acceptance, follow the successor only when still in that post-match flow and no newer navigation/pending command intervened; otherwise preserve recovery for explicit Resume.

## Commands and serialization

Active Live APIs use the current build-3-or-newer request grammar and snapshot v3 only.
All new rooms have floor 3. Obsolete command shapes, non-durable Join, legacy RPC
adapters and v1/v2 projections are removed; obsolete clients get an update error.
Current original receipts resolve idempotently, without supporting old-client
payloads. Existing match/result/receipt data remains intact and current v3 reads
preserve gameplay facts. There is no old-client or old-backend play target.

There is no command negotiation, shape fallback or obsolete payload replay. A
wrong-version response, missing current endpoint or exact-key rejection of a
locally validated current command is a deployment failure: show “Live service needs
an update”, retain the current original request/pointer/navigation intent, suspend
automatic retries and allow explicit Retry against a corrected service. A
compatible canonical snapshot clears that fence. Network/internal failures retain
ordinary current original-request recovery. Unsupported saved formats remain an
explicit storage failure, with bytes preserved until user Discard; no migration or
synthesized old intent is needed pre-MVP.

New `rematch-command` has exact bounded fields: `client_build`, `request_id`, `predecessor_match_id`, `generation`, `action` (`offer`, `accept`, `cancel`, `decline`), `expected_participation_epoch`. For `offer`, generation is current offered/eligible generation or explicitly advertised next generation after closure. `accept/cancel/decline` target the exact existing generation. Simultaneous offers against the same eligible generation converge; any command from a closed generation is stale. Join build 3 has exactly `client_build`, `request_id`, `join_code`, `expected_match_id`: the last is null for a confirmed external/manual invitation, or the known match UUID for explicit member Resume. A nonnull target requires existing membership in that exact match and matching code; it cannot admit a new member or join a later room reusing the code. Existing-member recovery remains allowed after ordinary lobby expiry/start. Persist new receipts keyed by actor and request UUID with command kind and exact normalized payload; changed reuse is `request_conflict`. Replays return the original receipt without recreating consent, changing selection, extending deadline or spending another quota. A receipt is an acknowledgment, not current UI state: always obtain the canonical snapshot before following a successor.

Use existing authenticated/bounded Edge wrappers and service-only RPCs. Add stable errors `rematch_unavailable` (409: ineligible/closed generation), `rematch_expired` (410), `answer_pool_unavailable` (409), and `participation_changed` (409); keep existing authentication, membership, configuration, quota and conflict errors. Unauthorized actors get no eligibility/roster/answer detail. After locking and validating the actor, check existing receipts before current eligibility, epoch, expiry or pool checks: an old successful receipt still resolves after the other player deletes. Record successful outcomes and definitive domain failures; explicit retry of a domain failure is a fresh user action/new UUID after refresh. Network/internal failures retry the original UUID; rate limits do not record a terminal receipt or silently create another request. New offer/accept requests use the existing create rate bucket, joins the join bucket; replay and cancel/decline do not consume quota. Re-offer remains bounded without a new invitation service.

To serialize departure without imposing a user-wide busy restriction, add a
private participation cursor per account: selected match ID and monotonic epoch.
It records explicit selection, not presence or exclusive membership. Successful
Create, Join to a different match, first Start or a newly accepted Guess targeting
another selected match changes it atomically. Current receipt replays and already-
started target replay do not select again. Offer/Accept intentionally select the
predecessor and capture the resulting epoch; successor allocation selects it for
both accounts. Another membership alone forbids no command.

**Resume versus reconnect:** baseline `resumeSavedMatch()` (:525), `beginRecovery()` (:566), `open(matchID:)` (:582), and startup `loadRecovery()` (:1015) only choose a local pointer, subscribe or fetch. Existing pointer replacement comes from create/join resolution (:344, :959); first-beta scope has no arbitrary history navigation, but another device can make the saved pointer stale. Add viewer-only `selection: {epoch, is_selected}` to every v3 snapshot, without exposing another selected match ID. Fetch/subscribe/foreground/startup never change this cursor. If the known pointer is still selected, even explicit Resume is ordinary recovery with no new request/epoch. If a completed result has an accepted successor and the viewer has not since selected outside that predecessor/successor, recover that successor first without reselecting the predecessor.

Otherwise an unselected saved pointer is read-only recovery with a “Resume this race instead” confirmation; passive foreground/relaunch cannot claim the selection or restore consent. Only that explicit action, after pending requests resolve, durably saves the pinned build-3 member-join request above. Successful member join selects that target and invalidates any old offer through the cursor transaction; a later canonical snapshot enables interaction. Failed admission keeps the prior state. If another selection races with this explicit action, actor-lock commit order applies: an acceptance committed first keeps its successor, while member Resume may select its target afterward; Resume committed first invalidates the old offer before acceptance. A lost-reply retry returns the original receipt and does not reselect a target after a still-later action. Refetch before enabling interaction; if it is unselected again, show the confirmation rather than replaying selection. This reuses membership admission/recovery, not a generic navigation or presence API. Any later history-based explicit switch must adopt this contract separately; it is not implemented here.

An offer is valid only while both captured cursor epochs remain unchanged. Creating/joining/starting another race closes the old offer even if the departing invitee has not consented. Acceptance first checks both captures, then may update the accepting player's capture for its own intentional selection in the same transaction. Commands racing with acceptance are serialized by actor locks. If departure commits first, acceptance closes the stale offer. If acceptance commits first, the successor exists and the later selection proceeds normally. Canonical old-result projection exposes only whether this viewer has subsequently selected elsewhere, never that other match's ID. A later fresh offer requires a fresh snapshot epoch. An other-race attempt that fails admission leaves consent unchanged.

Lock order: discover candidate member identities without trusting that read; acquire all needed existing actor advisory lock keys in sorted **signed numeric key** order (deduplicated), then account cursor rows, then match rows in UUID order, then rematch context/round/member/player rows in established order. Re-read profiles, membership, completion and cursor eligibility under locks. Rematch commands lock both actors before the predecessor. They never acquire another actor after a match lock. Existing create/join/start/submit keep actor-before-match order; lock cursors before matches, but change them only on successful commands. Deletion keeps its actor lock and sorted match traversal, removes its cursor/receipts and closes affected offers while retaining existing survivor anonymization. Finalizers remain match-first and never acquire actor locks. Ordinary other-race commands invalidate by epoch only: they must not lock or update a second old match to notify it. Existing bounded snapshot polling observes that invalidation. These rules avoid cross-room lock cycles and preserve join/delete/finalize ordering.

**Snapshot finalization branch:** apply actor-first entry to **all v3 snapshots**, not only those initially seen as completed. Perform an unlocked membership/identity discovery for authorization and lock keys; acquire the caller and all currently attached roster actors in sorted order, then cursor and match locks. Revalidate membership and the discovered actor set. If that set changed (for example a lobby join or account deletion), abort the entire RPC transaction with an internal serialization-retry signal; Edge retries the read in a fresh transaction at most twice, then returns ordinary `internal_error` without a partial snapshot. Never append missing actor locks after taking a match lock. Only after stable revalidation run the existing round-lock/finalization path and build the snapshot. Thus a deadline snapshot that becomes completed already holds the pair locks needed for rematch projection; it neither upgrades a match-first transaction nor changes completion timestamps to accommodate locks. Canonical reads may finalize/normalize as before, but never select a race or increment participation epochs.

Canonical expiry/epoch invalidation may be materialized while holding these locks. Only actual state changes increment rematch revision. Add one safe public `match_rematch_signals` row per materialized context, containing predecessor ID and revision only, with membership RLS, column-limited SELECT, no authenticated writes and the same limited Realtime publication. Private contexts/cursors/receipts/successor exclusions have no authenticated grants or publication; privileged RPC EXECUTE is service-role only. Extend the existing match event stream to merge this row's INSERT/UPDATE into refresh signals. Do not update completed match/result columns just to notify.

Snapshot v3 retains current game fields, adds viewer-only `selection` above, `match.admission` (`code` or `rematch`), and nullable `rematch`: revision, eligibility/state/reason, generation/next generation, initiator and consenting **member** IDs, selected-elsewhere indicator (outside predecessor and accepted successor), deadline/evaluation time and accepted successor ID/availability. `rematch` is absent for noncompleted matches. A snapshot read normalizes stale state and returns a consistent projection under the actor-first lock order above. Compare match revision, rematch revision and viewer selection epoch independently; a lower stored dimension cannot overwrite newer state, including selected-elsewhere changes after acceptance. Old/equal gameplay revisions cannot erase newer rematch state. Before reveal, the new projection supplies no opponent selection, guessed words, action timing, consent or future answers.

## Admission, answer selection and deletion

No match exists before both consents. Second consent creates a normal floor-3 lobby atomically, inserts both prior participants with fresh member IDs/current profile snapshots and the original creator role, creates 1/3/5 pending rounds, records successor linkage and receipts. Allocate its normal 60-minute lobby expiry from creation. No countdown starts. Mark successor admission as private/rematch-only in private metadata: `join_match` allows existing members to recover, but denies all new members even if a later lobby deletion frees a seat. Codes/links cannot steal or replace a seat. Existing lobby host deletion removes the lobby; guest deletion leaves it unstartable. The prior context then reports accepted-but-unavailable rather than reopening. The rematch lobby suppresses invitation sharing and explains unavailable membership instead of soliciting a replacement. Started successor deletion follows unchanged Phase 4 policy.

Preflight eligible active answer count minus **all** predecessor answers against configured round count before the first offer and again before committing second consent. Insufficiency leaves no new consent or successor; an existing first consent remains as it was. Store the exact predecessor exclusion set in private successor metadata atomically with allocation, so future predecessor retention cannot silently change the policy. This is a copy of already revealed exclusions, not selected future answers. At each explicit successor start, check eligible remaining capacity for all remaining rounds, then randomly select only that round's answer excluding this set and the successor's already selected secrets. Selection and checks share the match transaction; take ordered `FOR SHARE` locks on eligible pool rows through selection so concurrent deactivation cannot invalidate that operation. Later corpus deactivation may make a later start unavailable: return the pool error with no start/secret/round advance, allow explicit retry after pool repair, never weaken exclusion or extend consent deadlines. Ordinary old-room selection/errors, Daily schedule, accepted guesses and shared scoring vectors do not change.

Deletion purges actor-indexed receipts/cursor, detaches any identity-bearing new state and closes open consent. Retained result-member IDs and successor exclusion sets follow existing anonymized survivor purposes; no new retention duration is selected here. Account deletion must race safely with second consent: either it precedes eligibility and prevents allocation, or follows allocation and applies ordinary lobby/started deletion. A created successor is never erased merely to make an old request look unaccepted.

## Native recovery and presentation

Use the existing protected account recovery file with format 3 only. Decode and
save the current complete payload before dispatch; unsupported formats fail closed
without overwriting bytes. Current Join includes original UUID/build, null or pinned
expected match, source pointer and invitation/navigation UUIDs. Current rematch
retains exact UUID/action/generation/epoch and predecessor until receipt resolution,
canonical successor discovery and atomic pointer replacement. Failed persistence
keeps the original pointer/request retryable. Passive restoration creates no
selection command; follow one canonical accepted successor at a time with existing
guards. No history traversal or backward-format writer is introduced.

The completed invitation UUID is stored in the same atomic save as admitted pointer
and pending-Join clear, and restored with its account owner. Root clears only a
matching navigation generation or proves it already absent/replaced, completes its
journal work, then acknowledges the captured UUID/account. Failed acknowledgment
retains bytes and the retryable marker. Unrelated operations preserve the marker;
a different external Join waits for consumption. No queue or separate marker file.

Only the current application/recovery contract is supported. Feature rollback
keeps its readers installed and disables new allocation rather than supporting an
older binary. Cleanup/Discard/sign-out/deletion cover the protected account file and
navigation store with existing lease, journal and generation fences. Unknown or
unsupported formats remain recoverable storage failures with explicit Discard.

UI adds Join confirmation and concise rematch states/actions within Stamped components: Offer, waiting/Cancel, incoming Accept/Decline, closed/Offer again when eligible, expired, unavailable, accepted/loading lobby. Server state owns action eligibility; local deadline display only schedules refresh. Never block already accepted successor recovery because five minutes has since elapsed. VoiceOver announces meaningful state transitions once and focus goes to the new notice/lobby, not repeated countdown ticks. Long copy and all actions remain reachable at accessibility sizes. Material visual departures return to the controller.

## Units, packets and integration

The controller activates work explicitly, owns Git and source authority, and supplies each packet with this plan, current HEAD/drift and no unrelated-write authority. One person owns each row; no parallel shared-file writers.

| Unit | Exclusive files / packet contract | Dependencies and acceptance |
| --- | --- | --- |
| I1 invitation values/store | New native invitation parser/store and focused tests only. Input/output and lifecycle are B2 above; inject configured origins/storage. | Can begin with I2 after adjudication. Prove allowlist, malformed/duplicate/replacement, relaunch and unavailable persistence; no routing/project writes. |
| I2 backend contract | One forward migration after current HEAD; new rematch handler/tests; existing create/join/start/snapshot/deletion RPC replacements and Edge mappings; DB tests. Own `live-api-contract.md` updates only after controller transfers that file. | Implement B3 plus pinned member-join selection, viewer selection projection and all-v3 actor-first snapshot/restart semantics; reuse generation/receipt fixtures. Deliver request/response fixtures first to I3. Acceptance includes current-build play, receipt/data preservation and migration proof; obsolete new-race creation requires update per human steering. No shared runtime without controller lease. |
| I3 native transport/recovery | `LiveMatch.swift`, service, session, recovery store, Realtime service and corresponding tests. Own these throughout B2/B3 integration. | Stable I2 wire fixtures required; may overlap I2 implementation thereafter. Prove exact retries, passive vs explicit/stale-pointer Resume, two revision streams/viewer epoch, backend mismatch retention, pointer/consent/URL races, cleanup and current/unsupported storage. No route/UI/project edits. |
| I4 composition/UI/landing | AppRouting/startup/coordinator hooks, Live views, new landing assets, Info/entitlements/project file, UI tests. One integration writer owns project/resource registration for I1/I3. | I1 + I3 integrated. Wire agreed controls; signed-out intent remains separate. Prepare domain association/config templates with named external inputs, no publication. |
| I5 integrated verification/review | Controller-assigned integration driver/scenario/test changes; one runtime owner; independent reviewer read-only. | Stable I2–I4 source. Run matrix below, adjudicate material findings, update scoped evidence. Parent updates roadmap/NOW/decisions/product docs; do not create another Active checkpoint. |

Integration order: adjudicate this contract; integrate I1 and I2 protocol/fixtures; integrate I2 backend and I3 client; integrate I4; run I5. Backend/client implementation can overlap only after fields and fixtures freeze. Serialize migration/seed/database, project/lockfile, session/API and simulator/build work. Packet completion requires changed-file list, exact source, focused evidence, remaining acceptance and one terminal callback. Stop affected writes for contract drift, conflicting file ownership, missing disposable runtime ownership or a genuine product contradiction; continue independent authorized work. External identifiers gate actual linking/signing, not local parser/state work. No further unresolved feature preference is assumed.

## Verification and preservation

Reuse [LiveMatchSessionTests](../../ios/GridRaceTests/LiveMatchSessionTests.swift) join/Home/Resume and account-switch cases, create persistence/retry cases, terminal receipt recovery and lower-revision guards; [AccountTests](../../ios/GridRaceTests/AccountTests.swift) profile setup/failure and cleanup; [LiveMatchTests](../../ios/GridRaceTests/LiveMatchTests.swift) current v3 payload/secrecy and unsupported-response fixtures; [LiveMatchViewTests](../../ios/GridRaceTests/LiveMatchViewTests.swift) canonical presentation/ranking; existing SQL foundation, recovery, multiround and deletion suites. Extend rather than replace these distinct proofs.

New deterministic coverage: every state/action pair and exact deadline boundary after lock waits; simultaneous offers, accept/cancel, accept/departure and accept/deletion in both commit orders; fresh re-offer vs replay; changed UUID payload; unauthorized/private-table/Realtime denial; third-party successor join before/after lobby deletion; predecessor immutability under rematch operations including gameplay revision and old receipts (existing deletion anonymization remains); successor-chain eligibility; pool insufficiency at offer/accept/later start; copied exclusions and no future secrets; selected-other-room epoch races; URL generation/account/persistence failures and lost successor-switch writes. Prove no deadlocks with real concurrent database connections, not only serial pgTAP assertions.

Controller-review regression cases: same-pointer passive reconnect leaves epochs
unchanged; a second device restores an older pointer read-only, then explicitly
confirms pinned member Resume. Test acceptance before/after that selection and
replay after a later selection; pinned-code reuse/missing membership; unavailable
persistence; receipt-first relaunch; accepted-successor discovery without implicit
reselection. Wrong-version/shape/missing-endpoint responses retain current payloads
without fallback or automatic retry storms. Force snapshot-triggered finalization,
roster drift and concurrent deletion; prove actor-first order, bounded whole-
transaction restart and no read-driven epoch changes.

Forward-upgrade proof preserves representative existing completed/live/incomplete
1/3/5-round data, result IDs/timestamps/boards/ranks, private secrets, receipt rows and
grants. Compare canonical gameplay facts through the current v3 projection, not
obsolete response versions or old-client endpoints. Existing deadlines do not reopen.
Current account recovery and unsupported-byte safety have native proof. Also prove
clean creation on owned disposable state and no broader grants. Historical applied
migration source remains immutable.

Real two-player matrix: (1) cold/warm signed-out link and profile return; (2) confirmed switch while old request is unresolved, lost join reply/relaunch; (3) three-round completion → offer/accept → same lobby/host start without resharing; (4) simultaneous offers and lost second-consent response/relaunch; (5) cancel/decline, explicit fresh re-offer, deadline expiry and reconnect after pre-expiry acceptance; (6) account switch/deletion and other-race selection races, including a third client process signed into one player's account with a stale pointer; (7) 1/5-round exclusions, current independent clients on the current backend, dropped/reordered signals and snapshot-triggered finalization. Observe independent Auth/Edge/DB/Realtime clients and server state. External app link handling, no-app landing, signed Apple provider flow, protected storage and OS-assisted actions require separately identified device evidence.

Commands for the execution owner, not run during planning:

```sh
deno fmt --check supabase/functions
deno lint supabase/functions
deno test --config supabase/functions/deno.json supabase/functions/
npx --no-install supabase test db
npx --no-install supabase db lint --local --schema public,private,app_rls --level warning --fail-on error
python3 scripts/check_word_pack.py --checked-in-only
npm run check:seed
```

Extend the explicit Edge `deno check` list in [CI](../../.github/workflows/ci.yml) for the new handler. Use the [project profile](../../.agents/project.md)'s frozen Xcode discovery/test commands, a discovered destination and run-owned derived data; select the named affected XCTest classes during iteration, then the affected integrated suite. Use `PATH=/opt/homebrew/opt/libpq/bin:$PATH GRIDRACE_LOCAL_INTEGRATION=1 bash scripts/run_live_match_integration.sh` only after its documented runtime inventory/lease and new scenario registration. Do not reset or commandeer an existing stack. Shared rule vectors need rerunning only if rule code actually changes.

Rollback is additive: one service-only `allow_new_rematches` configuration defaults off during deployment; v3 eligibility and offer/accept enforce it. Disabling it closes unaccepted offers as unavailable, while snapshot/receipt resolution, cancel/decline, accepted successors, deletion and ordinary play continue. Invitation sharing is enabled only for configured origins and may fall back to codes. No down migration, result reset, receipt purge or secret relaxation. New starts failing pool checks remain retryable. Rollback acceptance includes an outstanding join/rematch receipt and an accepted successor, not merely a hidden button.

## B0/B1/B4 release preflight

- **B0 inventory/preparation:** identify actual Apple team/membership, bundle/signing identities, devices/TestFlight route, environment-specific hosted Supabase and HTTPS domain ownership; prepare secrets/configuration and association-file templates. Verify then-current official provider requirements before changing accounts. Purchases, provider changes, deployment and publication remain separately authorized actions.
- **B0 actual integration:** prove signed installed app/domain association, no-app installation/code page, real Apple sign-in/restoration and deletion/revocation, intended hosted environment, migrations/seed/grants, finalizer scheduling and compatibility. No local test substitutes for these observations.
- **B1:** use Stamped S4 and completed remediation's remaining acceptance records; perform deferred human checks when authorized. Verify VoiceOver, Dynamic Type, Reduce Motion, contrast/Bold Text, targets and new confirmation/rematch focus; record actual build/device and repair reproduced failures only.
- **B4 before friends:** obtain recorded content distribution/provenance clearance, retention/deletion/backup/restore and operational-owner decisions covering new receipts/cursors/consent/exclusions and landing access logs. Disable/redact invitation paths in hosting logs and use a no-referrer landing policy so codes do not enter unrelated requests. Preserve broader report/block beta-exit obligations; this plan neither implements nor waives them. Agree trial feedback criteria without automatic analytics. Run independent installation/join/three-round/rematch session, offline Daily and 1/5-round regressions on separate devices/networks. Keep every unperformed hosted/provider/OS requirement explicit.

## Controller-review resolutions, 2026-10-13

- **R1:** source inspection confirmed that local Resume/reconnect never selects server state. Added only an explicit stale-pointer member-join variant with a pinned match ID, durable receipt and fresh confirmation; passive reads remain nonselecting. Added cross-device/acceptance/replay proof and the future-history boundary.
- **R2:** the original review retained older-client behavior. The human explicitly superseded that contract pre-MVP: active Live uses current v3 shapes/readers only, with no compatibility adapters or format migration. Preserve existing data and current original receipt identities. Protocol failure retains current requests and blocks interaction until v3 is available; unsupported recovery files fail closed for explicit Discard.
- **Snapshot locking:** every v3 read takes actor locks before match locks, even while initially in progress. Roster discovery drift restarts the entire RPC transaction with a bounded read retry; finalization never triggers late actor acquisition.

Controller adjudication on 2026-10-13: accepted R1, R2 and snapshot-lock corrections after tracing the existing Resume/recovery, strict join request and finalizing snapshot paths at the recorded HEAD. The revised contracts address the identified gaps; no material planning finding or unresolved feature-level product decision remains. The private selection cursor is justified by cross-device consent invalidation, without exclusive membership; the separate signal projection preserves completed-result immutability. Format-3 downgrade fails closed; rollback retains new recovery readers and disables allocation rather than downgrading pending commands.

This is source-based engineering-plan acceptance, not evidence that the future implementation is correct. The listed concurrency, security, migration, native and real-client checks must still run on implementation. Planning checks passed for local links, whitespace and source drift. No app/runtime test, deployment or release readiness is asserted.
