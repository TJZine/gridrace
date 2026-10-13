# GridRace Live API Contract

The supported Live protocol is build 3+ / snapshot v3. The server owns answers,
feedback, timing, scoring and transitions. [`game-rules.md`](game-rules.md) owns
rules; [`architecture.md`](architecture.md) owns component boundaries. Daily and
account deletion retain their separate contracts; this protocol has no obsolete-
client compatibility paths. Hosted and OS/device acceptance remain separate.

All JSON uses snake_case; UUIDs are canonical lowercase. UTC timestamps use
RFC3339 with Z or +00:00 and up to microsecond precision. Commands require remote
bearer validation before a separate service-only RPC client is created. Auth
network/server/quota/unexpected failures remain uncertain internal_error, while
definitive invalid/deleted identity returns not_authenticated. Never expose SQL or
provider error text. Normal clients cannot execute gameplay RPCs directly.

POST JSON bodies are bounded to 2048 bytes, with exact keys. Success is HTTP200
`{"data":{...}}`; failure is `{"error":{"code":"...","message":"fixed safe text"}}`.
A non-POST request returns405/internal_error with Allow:POST; malformed bounded
requests may use400/internal_error. Responses are no-store. Unknown/transport/
internal failures retain the exact current request identity; rate limits retain
explicit Retry with that identity. Request conflict requires explicit recovery,
never an automatic replacement UUID. Snapshots never acknowledge command receipts.

## Current game commands

| Endpoint | Exact request keys in addition to client_build | Success data |
| --- | --- | --- |
| create-match | request_id:UUID, round_count:1/3/5 | match_id:UUID |
| join-match | request_id:UUID, join_code:six-character code, expected_match_id:UUID/null | match_id:UUID |
| start-match | match_id:UUID, round_number:integer1...5 | match_id:UUID |
| submit-guess | match_id:UUID, round_number:integer1...5, request_id:UUID, guess:five ASCII letters | accepted:true, sequence, feedback, player_state, accepted_guess_count, nullable solve_duration_ms/efficiency_points, server_time, round_end_time |
| match-snapshot | match_id:UUID | canonical snapshot v3 |
| rematch-command | request_id, predecessor_match_id, generation, action, expected_participation_epoch | predecessor_match_id, generation, state, successor_match_id |

Create captures count and UUID. Exact current actor/UUID/build/count replay resolves
before quota without allocating/selecting again; changed payload conflicts. Join
is always durable and uses the receipt contract below. Start captures its explicit
target: an already-started target succeeds without mutation, while new target1
requires a full unexpired lobby, and N+1 requires current N revealed and no deletion
block. Never replace a retry target with current+1. Submit normalizes ASCII case;
exact successful actor/UUID/match/round/word replay resolves before current phase
or quota, while changed reuse conflicts. Rejected guesses have no accepted receipt.
Deadline equality rejects and finalizes in the same transaction. New guess receipt
success carries the unchanged accepted row's sequence/feedback/result and original
server_time, which is not clock calibration on replay. No future answer is selected
until explicit Start. Ordinary multiround selection excludes prior match secrets;
rematch successors add copied predecessor exclusions and capacity checks below.

## Account deletion boundary (unchanged)

`delete-account` uses `{ "client_build": 3 }` from the current app and returns
`{ "data": { "deleted": true } }`. Its separate Auth/account contract is unchanged.
Preparation is idempotent; an absent profile is already prepared. Lobby host deletion
removes the unstarted match, while guest deletion removes the guest slot. Started
match deletion follows the round/result matrix below and retains only anonymized
survivor results. Edge then hard-deletes the Auth identity; an already absent identity
is success. A service-only receipt keyed by a one-way initiating-bearer hash lets the
same stale bearer finish or confirm deletion after a lost response. Pending receipts
lose their user reference with Auth deletion; completed receipts expose only status,
no reversible account mapping or account data. Normal Live commands never use this
exception. Daily cleanup/account isolation and deletion operation serialization
remain in their existing owners.

## Snapshot v3 gameplay projection

Required fields: version:3, server_time, match, members, round, revealed_rounds,
standings, selection and nullable rematch. See the complete concrete fixtures below.
Match contains id/join_code/creator_member_id/mode(classic_live_v1), round_count,
current_round, status, expires_at, minimum_client_build, revision, nullable
started_at/completed_at/terminal_reason and admission. Roster members contain
id/seat/display_name/avatar_seed/is_self/is_deleted; no Auth IDs. Exactly one
current viewer is_self; deleted identity is Boolean and anonymized.

Round contains number/state/nullable starts_at/ends_at/completed_at/answer and
players. Player rows contain member_id/state/accepted_guess_count/nullable
solve_duration_ms/efficiency_points/placement/board. Board rows contain
sequence/guess/feedback/submitted_at. Before reveal, answer and opponent boards,
solve duration, efficiency and placement are null. Own board/result remains visible.
Pending rounds have no answer/player rows/times. Revealed history is contiguous
ascending through the last revealed round and contains the identical current
reveal when applicable. Future rounds and aggregate clues remain undisclosed.

Standings are null until first reveal, then through_round/is_final and stable-seat
players with member_id/rounds_solved/efficiency_points/total_solve_duration_ms/
placement. Only revealed rounds contribute. SQL ranks exact summed microseconds;
transport floors the total milliseconds once. Exact ties share placement. Seat order
is transport order, never a ranking tie-breaker. Clients do not recalculate ranking.

Lobby has no start/completion/reason; current round1 is pending. In-progress has
started_at and no completed_at; current round may be countdown/playing or a nonfinal
reveal waiting for explicit Start. Completed requires final configured reveal,
matching match/final-round completed_at and final standings. Account deletion during
active nonfinal play sets terminal_reason:account_deleted and blocks future starts;
that round finishes normally then becomes incomplete with partial standings and
no match completion timestamp. Deletion between nonfinal rounds becomes incomplete
immediately. Final-round deletion follows ordinary finalization with no block reason.
Completed-result deletion anonymizes identities without changing results/status/time.
No unplayed round receives a result/answer. Snapshot may finalize elapsed play;
canonical snapshot revision reflects that transition. Replayed/duplicate commands
and repeated finalizers do not mutate gameplay revision. Every v3 snapshot follows
the actor-first read/roster-restart contract below and never selects a match.

## Stable errors

| HTTP | Codes |
| --- | --- |
| 400 | invalid_match_configuration, invalid_guess_format; malformed requests may use internal_error |
| 401 | not_authenticated |
| 403 | not_a_match_member, not_host |
| 409 | match_not_joinable, room_full, not_enough_players, round_not_active, round_already_finished, match_incomplete, request_conflict, rematch_unavailable, answer_pool_unavailable, participation_changed |
| 410 | room_expired, rematch_expired |
| 422 | word_not_accepted |
| 426 | client_update_required |
| 429 | rate_limited |
| 500 | internal_error |

Messages are the fixed safe texts in the Edge shared command map. No Retry-After
promise is made. In-app account deletion retains its service-only deletion receipt,
preparation/Auth-deletion/completion sequence and stale-bearer receipt exception;
see [`privacy-data-map.md`](privacy-data-map.md). This does not authorize Live commands
under stale/deleted identities or alter Daily/Auth compatibility policy.

## Friends beta: build 3 / snapshot v3

The concrete wire fixtures are [friends-beta-v3.json](../shared/test-vectors/live-api/friends-beta-v3.json).
Only client builds >= 3 and snapshot version 3 are supported. Every Live command
uses its exact current shape; obsolete builds return `client_update_required`.
No old request encoding, receipt exception, version negotiation or shape fallback
is supported. All newly allocated lobbies have floor 3. Existing floor values and
stored result/receipt identities remain data, readable through the current v3
projection by authorized current clients. Historical migrations are provenance.

`join-match` requires exactly `client_build`, `request_id`, `join_code`,
`expected_match_id`. The last is null for external/manual confirmed Join, or the
known UUID for explicit member Resume. A pinned join requires existing membership
and matching code; it never joins a later room reusing that code. Success remains
`{data:{match_id:UUID}}`. Existing members can recover expired/started rooms;
rematch admission denies every new member, including after a guest leaves.

`rematch-command` requires build >= 3 and exactly `client_build`, `request_id`,
`predecessor_match_id`, `generation`, `action`, `expected_participation_epoch`.
Generation is a positive signed 32-bit integer; epoch is an integer 0...9007199254740991.
Actions are `offer`, `accept`, `cancel`, `decline`. UUIDs are canonical lowercase;
join codes normalize ASCII case. Success data has exactly `predecessor_match_id`,
`generation`, `state` and nullable `successor_match_id`. These are receipt-time
acknowledgments; fetch a canonical snapshot before changing the selected pointer.
Receipts key actor + UUID across join/rematch; changed kind or normalized payload
is `request_conflict`. Receipt lookup precedes current membership/epoch/deadline/
pool checks after actor validation. Successful and definitive domain outcomes
persist; rate limits, internal/transport failures do not. Replay changes no
selection, quota, consent or deadline. Offer/accept use the create bucket; new
joins use join. Cancel/decline and all replays spend no quota.

Every snapshot includes required `selection:{epoch,is_selected}`,
`match.admission` (`code` or `rematch`) and nullable `rematch` (null unless completed).
Only the viewer's selection is exposed; passive reads never select. Rematch fields:
`revision` (positive integer), `is_eligible` (Boolean), `state` (`eligible`, `offered`,
`closed`, `expired`, `unavailable`, `accepted`), nullable `reason` (`cancelled`,
`declined`, `participation_changed`, `expired`, `account_deleted`, `ineligible`,
`feature_disabled`), positive `generation`, nullable positive `next_generation`,
nullable `initiator_member_id`, `consenting_member_ids` (seat-ordered member UUIDs),
`selected_elsewhere` (viewer only), `deadline`, `evaluated_at`, nullable
`successor_match_id`, and Boolean `successor_available`. Deadline/evaluation are
UTC timestamps; no Auth IDs, other selected match ID, future answers or consent
appear before completed reveal. Accepted tombstones persist when a lobby disappears.

Eligibility requires exactly two current profiles/nondeleted members and every
configured round revealed, complete answers, matching final/match completion time,
and server wall time strictly before completion + five minutes. Generation 1 is
eligible. Offer records initiator consent; accept or the other player's same-
generation offer atomically creates the sole successor and selects it for both.
Cancel (consenting actor) and decline (nonconsenting actor) close and clear consent.
Closed cancelled/declined/moved generations advertise next_generation while still
eligible. Explicit offer of that fresh generation starts fresh consent. Expired,
deleted, disabled or otherwise ineligible generations cannot be re-offered.
Accepted state wins over subsequent cancellation/departure; availability may change.
Pool insufficiency records a failure without adding consent or allocating a lobby.

Participation epochs change only on successful explicit selection: new create,
join to a different room, first target start/new accepted guess selecting another
room, offer/accept selecting predecessor, and atomic successor allocation. Existing
receipt and started-target replays never select. Both actors' captured epochs fence
an offer, including the nonconsenting invitee. Canonical reads normalize invalidated
consent without changing gameplay revision or result rows. Compare gameplay revision,
rematch revision and viewer epoch independently.

Every v3 read discovers actors, locks signed sorted actor keys, cursors, then match,
revalidates roster, and only then finalizes/shapes. Roster drift aborts the whole SQL
transaction with SQLSTATE `40001` / message `snapshot_roster_changed`; Edge retries
only this read at most twice in fresh RPC transactions, then maps to internal_error.
Finalizers never acquire actor locks.

Realtime retains the existing per-match channel and `matches` UPDATE subscription,
and merges `match_rematch_signals` INSERT/UPDATE with filter
`predecessor_match_id=eq.<UUID>` into refresh signals. Payload contains only
`predecessor_match_id` and `revision`; it is never a canonical snapshot. Membership
RLS and column grants allow SELECT only; private contexts/cursors/receipts/exclusions
have no client grants or publication. No timestamp is added to the safe signal.

New safe errors (existing error/status meanings remain):

| Code | HTTP | Message |
| --- | --- | --- |
| rematch_unavailable | 409 | This rematch is unavailable. |
| rematch_expired | 410 | This rematch opportunity has expired. |
| answer_pool_unavailable | 409 | There are not enough available answers for this rematch. |
| participation_changed | 409 | Your selected race changed. Refresh and try again. |

Domain denial is definitive and receipted for bounded authenticated new join/rematch
commands. Unauthorized actors receive no eligibility/roster/pool detail. Explicit
retry after domain failure uses a fresh UUID after refresh; uncertain failures retain
UUID. `allow_new_rematches` is service-only and defaults off. Disabling it closes
unaccepted offers as unavailable; receipts, accepted recovery, cancel/decline,
deletions and ordinary gameplay remain available. No down migration or purge.
