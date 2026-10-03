# GridRace Live API Contract

This document freezes the Phase 2 backend and Phase 3 two-player live-slice wire
contract. The local backend and live client implement this fixed contract, including
retry-safe creation, Boolean deleted-member identity, security/RLS integration,
durable recovery and two-client proof. Hosted and broader-MVP gates remain separate.
[`game-rules.md`](game-rules.md) remains authoritative for gameplay;
[`architecture.md`](architecture.md) owns component boundaries. All JSON uses
`snake_case`, UUIDs use canonical lowercase strings, and timestamps use RFC 3339 UTC
with optional fractional seconds (up to microseconds); accept UTC `Z` and
`+00:00` encodings. Do not assume the three-digit examples are the only SQL output.

## Version and build floor

- Snapshot version: `1`.
- Mode: `classic_live_v1`.
- Phase 3 client build: `1`.
- Phase 3 capacity and rounds: exactly two players and one round.
- Lobby expiration: 60 minutes after creation.

Every request includes `client_build`. A build below the match floor returns
`client_update_required`. The iOS `CURRENT_PROJECT_VERSION` and the request value
must remain synchronized.

## Transport envelopes

Success:

```json
{ "data": {} }
```

Failure:

```json
{
  "error": {
    "code": "not_authenticated",
    "message": "Sign in and try again."
  }
}
```

Messages are fixed safe presentation text, never database output. Error codes are:

- `not_authenticated`
- `not_a_match_member`
- `match_not_joinable`
- `room_full`
- `room_expired`
- `not_host`
- `not_enough_players`
- `round_not_active`
- `round_already_finished`
- `invalid_guess_format`
- `word_not_accepted`
- `rate_limited`
- `client_update_required`
- `request_conflict`
- `internal_error`

HTTP methods are POST with JSON content type; current handlers limit bodies to
2048 bytes and reject extra request keys. Success is HTTP 200. Stable failures map
as follows; a gateway/transport failure need not have this envelope.

| HTTP status | Error codes |
| --- | --- |
| 400 | `invalid_guess_format`; malformed requests may use `internal_error` |
| 401 | `not_authenticated` |
| 403 | `not_a_match_member`, `not_host` |
| 409 | `match_not_joinable`, `room_full`, `not_enough_players`, `round_not_active`, `round_already_finished`, `request_conflict` |
| 410 | `room_expired` |
| 422 | `word_not_accepted` |
| 426 | `client_update_required` |
| 429 | `rate_limited` |
| 500 | `internal_error` |

A non-POST request receives 405 with `internal_error` and `Allow: POST`. Decode
known error bodies from non-2xx SDK responses; never show unknown server text or raw
SQL. Definitive validation rejection clears that pending intent and preserves the
draft; an uncertain transport/internal failure retains its UUID. A rate-limit error
consumes no accepted row and leaves an explicit retry using the same intent; current
responses supply no `Retry-After` promise. A request conflict requires canonical
recovery and explicit user action, never an automatic replacement UUID.

## Commands

Game commands require a bearer session. Edge code authenticates it before creating
a separate server-only client; normal credentials cannot execute the transactional
gameplay functions directly. Deletion is the documented exception: a service-only
receipt lookup may confirm/resume an already-authenticated deletion before ordinary
Auth validation. It exposes only deletion status, never account data. Database
preparation and Auth deletion cannot form one cross-service transaction.

### `create-match`

Current request:

```json
{ "client_build": 1, "request_id": "00000000-0000-0000-0000-000000000000" }
```

Response data:

```json
{ "match_id": "00000000-0000-0000-0000-000000000000" }
```

Creation forces two seats, one round, a 60-minute expiration, the current build
floor, creator seat one, and a pending public round. The client then fetches a
snapshot. Current requirements:

- Persist the create intent and UUID before dispatch. Scope its receipt by
  authenticated actor and request ID, separately from guess receipts. Compare the
  saved request payload including `client_build`; changed content is `request_conflict`.
- Verify an active profile and supported build; resolve an identical receipt before
  consuming create quota. The receipt and match/creator/round commit atomically.
  Concurrent retries produce one room; distinct intentional creates use distinct IDs.
- An identical retry returns the original match ID even after start/completion or
  lobby expiry; subsequent snapshot determines presentation. It never creates a new
  room merely because the original lobby expired. No receipt for a rejected create.
- Receipt storage is private/service-only and contains only actor, UUID, request
  content and match ID. Remove it during account-deletion preparation; match removal
  removes its receipt. No new retention period or automatic lobby cleanup is selected.
  Serialize create with deletion so an in-flight request cannot recreate deleted data.
- Replace the old service RPC signature/grants in a forward migration and update the
  Edge handler/tests together. This local pre-client change needs no compatibility
  framework; no rollout to existing remote clients is authorized.

### `join-match`

Request:

```json
{ "client_build": 1, "join_code": "ABC234" }
```

The code is ASCII uppercased and must match `[A-HJ-NP-Z2-9]{6}`. Response data is
the same `match_id` shape as create. A caller already rostered receives the existing
match id without creating another seat. Capacity assignment is atomic.

### `start-match`

Request:

```json
{
  "client_build": 1,
  "match_id": "00000000-0000-0000-0000-000000000000"
}
```

Response data is the same `match_id` shape. Only the creator can start with two
members. One database timestamp produces `starts_at = now + 3 seconds` and
`ends_at = starts_at + 180 seconds`; the private answer is never returned.

### `submit-guess`

Request:

```json
{
  "client_build": 1,
  "match_id": "00000000-0000-0000-0000-000000000000",
  "round_number": 1,
  "request_id": "00000000-0000-0000-0000-000000000000",
  "guess": "STONE"
}
```

Successful response data:

```json
{
  "accepted": true,
  "sequence": 1,
  "feedback": [2, 2, 2, 2, 2],
  "player_state": "solved",
  "accepted_guess_count": 1,
  "solve_duration_ms": 1250,
  "efficiency_points": 6,
  "server_time": "2026-08-30T12:00:04.250Z",
  "round_end_time": "2026-08-30T12:03:03.000Z"
}
```

`solve_duration_ms` and `efficiency_points` in this command response are null unless
solved. Snapshot scoring differs: an unsolved terminal player has zero efficiency.
The database normalizes and validates the guess, evaluates feedback, timestamps it, transitions
the player, and finalizes when applicable in one transaction. An identical retry by
an active authenticated actor is resolved before rate limiting and returns the original sequence, feedback, server
timestamp, and result. Reusing the request ID for another round or normalized guess
returns `request_conflict`.

### `match-snapshot`

Request:

```json
{
  "client_build": 1,
  "match_id": "00000000-0000-0000-0000-000000000000"
}
```

Response data is the snapshot below. The command finalizes an elapsed deadline
before shaping the snapshot.

### `delete-account`

Request:

```json
{ "client_build": 1 }
```

Response data:

```json
{ "deleted": true }
```

Database preparation is idempotent: an absent profile is already prepared. Lobby
host deletion removes the unstarted match; lobby guest deletion removes the guest
slot. Active deletion is an explicit authenticated forfeit, and completed results
are retained only under an irreversibly anonymized `Deleted Player` member. The
Edge Function then hard-deletes the Auth identity. An already-absent identity is
success. A service-only receipt keyed by a one-way hash of the initiating bearer lets
the same stale bearer finish or confirm deletion after a lost response. Pending
receipts lose their user reference with Auth deletion; completed receipts contain no
reversible retained user mapping and expose no account data.

## Snapshot v1

Lobby example:

```json
{
  "version": 1,
  "server_time": "2026-08-30T12:00:00.000Z",
  "match": {
    "id": "00000000-0000-0000-0000-000000000000",
    "join_code": "ABC234",
    "creator_member_id": "00000000-0000-0000-0000-000000000001",
    "mode": "classic_live_v1",
    "round_count": 1,
    "current_round": 1,
    "status": "lobby",
    "expires_at": "2026-08-30T13:00:00.000Z",
    "minimum_client_build": 1
  },
  "members": [
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "seat": 1,
      "display_name": "Alex",
      "avatar_seed": "generated-seed",
      "is_self": true,
      "is_deleted": false
    }
  ],
  "round": {
    "number": 1,
    "state": "pending",
    "starts_at": null,
    "ends_at": null,
    "completed_at": null,
    "answer": null,
    "players": []
  }
}
```

Members are always stable seat order:

```json
{
  "id": "00000000-0000-0000-0000-000000000001",
  "seat": 1,
  "display_name": "Alex",
  "avatar_seed": "generated-seed",
  "is_self": true,
  "is_deleted": false
}
```

Round players are stable member-seat order:

```json
{
  "member_id": "00000000-0000-0000-0000-000000000001",
  "state": "playing",
  "accepted_guess_count": 1,
  "solve_duration_ms": null,
  "efficiency_points": null,
  "placement": null,
  "board": [
    {
      "sequence": 1,
      "guess": "crane",
      "feedback": [0, 0, 0, 2, 2],
      "submitted_at": "2026-08-30T12:00:04.250Z"
    }
  ]
}
```

Before reveal:

- `answer` is null.
- The requesting player's complete accepted board is present.
- Opponent `board`, `solve_duration_ms`, `efficiency_points`, and `placement` are
  null. Only opponent count and coarse state are present.
- A rostered player may see only this match; an unrelated or anonymous caller gets
  no snapshot.

After reveal:

- `answer` is the five-letter answer.
- Both boards, solve durations, efficiency points, and competition placements are
  present in stable seat order.
- A deleted member remains as nonidentifying presentation and retained result data
  only when required for the other player's immutable reveal.

### Enums, nullability and validation

Wire match statuses are `lobby`, `in_progress`, `completed`; effective round states
are `pending`, `countdown`, `playing`, `revealed`; player states are `playing`,
`solved`, `failed`, `timed_out`, `forfeited`. These are not Swift case spellings.
The stored round remains `countdown` until reveal; `playing` is snapshot-derived.

`is_self` and `is_deleted` are required Booleans; exactly one member is self. A
deleted member is never self and retains its stable member ID/seat. The SQL projection
coalesces a deleted member's null auth comparison to false; survivor fixtures prove
both members remain Boolean with exactly one self. Do not weaken the mapper into
accepting arbitrary missing identity fields.

For every player whose fields are visible:

| State | Accepted count | Solve duration | Efficiency | Placement |
| --- | --- | --- | --- | --- |
| `playing` | 0–5 | null | null | null |
| `solved` | 1–6 | nonnegative integer milliseconds | 7 minus count | null before reveal; 1–2 after |
| `failed` | 6 | null | 0 | null before reveal; 1–2 after |
| `timed_out` / `forfeited` | 0–5 | null | 0 | null before reveal; 1–2 after |

Pre-reveal opponents always have null board, duration, efficiency and placement,
regardless of coarse state. Visible boards contain exactly the accepted count, with
contiguous sequences starting at one. A solved board ends all-correct; a failed board
has six rows without a solve. The client does not use the Daily dictionary/evaluator
to accept/reject authoritative live rows. Server `placement` is final: SQL compares
microseconds while the wire truncates durations to milliseconds, so equal displayed
times do not necessarily mean a tie. Phase 3 presents round placement only, not a
locally recomputed match ranking.

A lobby has one/two members, a pending round, empty players and null round times.
Started snapshots have exactly two members and matching player IDs, nonnull start/end
with a 180-second interval. Before reveal completion/answer are null; at reveal all
players are terminal, completion/answer are present and both boards visible. A
completed match and revealed round agree. Countdown may contain a forfeited player
following account deletion; do not reject that valid state. No client clock controls
these validation rules. Required nullable fields must exist; null is not the same as
missing. Unsupported states fail closed with a recoverable update/error presentation.

The mapper rejects unsupported versions, rosters outside one or two unique seats,
a started match without exactly two members, duplicate IDs or seats, invalid enum
values, counts outside 0–6, noncontiguous guess sequences,
malformed five-letter words or feedback, a revealed answer before `revealed`, any
opponent clue field before reveal, missing reveal fields after reveal, timestamps
that contradict state, or a player/board mismatch.

## Realtime and recovery

The public `matches` row contains no private clue data and carries a
timestamp-free monotonically increasing `revision` signal. Every canonical
mutation advances it in the same transaction as member, round, player, or
guess changes (not as a separate post-commit write); idempotent replays perform no
write and leave it untouched. The
exact-action `updated_at` timestamp is service-only: authenticated clients hold
no `SELECT` grant on it and the Realtime publication column list excludes it, so
it can be neither selected nor received. The iOS Realtime service subscribes only to
the current rostered match row for update signals and emits `Void`; it never treats
payload data or delivery order as state.

The session model coalesces refreshes and fetches a snapshot on entry, after each
create/join/start, after an uncertain command, after a relevant signal, on reconnect,
foreground return, local countdown/deadline expiry, and any inconsistent ordering.
It also refreshes after accepted guesses and after 5 seconds without a successful
snapshot while an unfinished match is open in the foreground. Failure backoff is
5/10/20/30 seconds, capped; stop on background/exit/reveal/expired lobby/invalid
membership or unavailable Auth. No polling continues for hidden or completed rooms.
One fetch is in flight; events during it request a trailing refresh. Subscribe before
the catch-up fetch and refresh after the subscription becomes ready. This covers
missed updates and host-lobby deletion without relying on delete-event payloads.

Snapshot v1 carries no canonical state revision. `server_time` is a transaction time,
not a snapshot sequence number. Serialize application with commands and discard stale
responses using account/match generations; never compare delivery order or use a
replayed command time to establish freshness. Refresh auth once, use a 10-second
request timeout, and preserve uncertainty if cancellation occurs after server commit.
Unknown HTTP/gateway/non-JSON failures remain transport errors, not typed game denial.

| Operation with uncertain response | Recovery |
| --- | --- |
| Create | Retry the persisted payload/UUID; persist returned match ID and fetch snapshot |
| Join | Retry same code; existing member returns same match, subject to join rate limit |
| Start | Fetch known match; repeated start in progress is idempotent; completed returns `round_already_finished`, then refresh |
| Submit | Retry same persisted match/round/word/UUID, including after deadline/reveal; receipt returns original success; snapshot alone cannot identify the request |
| Snapshot | Safe to repeat, including its idempotent deadline finalization |
| Delete account | Preserve the initiating SDK-held bearer for receipt retry; never persist it in live recovery files or expose it to views; do not clear owned caches or claim completion before success |

Implemented live recovery stores only the latest match pointer and one pending
intent in account-scoped protected local storage. Relaunch resolves uncertainty and
fetches a snapshot before new input. Durable clearing on sign-out does not leave or
forfeit a server match; failed reads or deletion require explicit recovery-data discard
and never claim local cleanup success. Signed-out Home keeps that remediation reachable
while hiding former-account Daily/account presentation. Rejoining by code remains
possible. See the active plan for
lifecycle, clock display, storage-failure and verification evidence. There is no offline
submission queue, opponent presence, competitive history, or authoritative board cache.

## Profiles and local authentication

An Auth-user trigger creates a private-by-default profile with a generated avatar
seed. The owner may directly update only display name and avatar seed under RLS.
Display names are 2–16 ASCII characters: letters or digits at both ends, with
letters, digits, single spaces, apostrophes, and hyphens internally. Consecutive
spaces are rejected. Email never enters the public profile or match domain.

Release authentication is Sign in with Apple through Supabase. Debug builds may
show a local email/password sign-in for test accounts; that implementation and its
labels compile out of Release. Credentials and service keys are never bundled.

## Rate limits

Fixed transactional windows are intentionally specific:

| Action | Per authenticated user | Per keyed trusted IP |
| --- | ---: | ---: |
| Create | 5 / 10 minutes | 30 / 10 minutes |
| Join/code lookup | 20 / 10 minutes | 100 / 10 minutes |
| Submit guess | 30 / minute | 120 / minute |

Create/join consume before room lookup. An identical submit retry resolves before
consumption. Only a platform-documented trusted address may be HMAC-SHA-256 hashed
with a server pepper and passed to the database; raw addresses are never stored or
logged. The local slice has no verified trusted-address provenance, so per-user
limits and the keyed-IP database path are tested while live IP extraction remains
documented-only.

## Phase 4 accepted contract — implemented and verified locally

The preceding v1 contract remains the supported legacy local contract. The backend
implements this accepted Phase 4 extension in migration
`202610020001_blind_race_multiround.sql` and the existing Edge commands. Local
forward/reset, grants/RLS, scoring, concurrency and real gateway proof are recorded
in the active plan. Swift transport, recovery and UI are implemented; real
independent-client product integration and the independent implementation review
are complete. Required OS-assisted accessibility proof remains pending; this is
not a complete Phase 4 or hosted rollout.
The human approved the UI and freeze-on-either-account-deletion policy on
2026-10-02. Independent plan review and targeted corrections were checkpointed
at `3a01d9a` before product writes. The sole
[Active Phase 4 plan](plans/2026-10-02-phase-4-blind-race.md) owns packages and proof;
this section owns the frozen wire/recovery extension. Existing game rules own
unchanged scoring and deadlines. No hosted rollout or compatibility framework is
introduced; bounded v1 support preserves real local rooms and protected pending
request identities while upgrading the current client.

### Commands and bounded local compatibility

Use existing POST/data/error envelopes, 2048-byte exact-key validation, authentication and safe typed errors.

- Current Swift Join/Start/snapshot use the current build (2 by default) and require snapshot2, including legacy floor1 rooms. Original build1 create/guess replay uses explicit saved arguments, not a parallel Swift v1 snapshot mapper.
- New current app build 2; CURRENT_PROJECT_VERSION = 2 in Debug/Staging/Release, with SupabaseAccountService/SupabaseLiveMatchService request values synchronized. Existing matches remain floor 1; new build-2 creations have floor 2, including one-round. Keep mode classic_live_v1; snapshot version changes independently to 2.
- build >= 2 create-match: {client_build, request_id, round_count}, round_count exactly integer 1/3/5; no implicit API default (UI defaults 3). Return {match_id}. Receipt compares actor+UUID and original build+count; duplicate resolves before quota, including started/completed/expired room. Changed payload is request_conflict. Reuse account advisory serialization.
- build >= 2 start-match: {client_build, match_id, round_number}, integer 1...5. Return existing {match_id}; receipt truth is the target's persisted start, so no extra request UUID/table. Authorize active profile, build, membership and creator before any success. Lock match, target/prior round as applicable. If target has already started, success without writes even if it is revealed, a later round is current, or match is final. If not started: target 1 requires full unexpired lobby; target current_round+1 requires current revealed, within configured count and accepted D4 guard. All other targets -> round_not_active; blocked not-yet-started target -> match_incomplete. A captured target is never replaced by current+1 during retry. Concurrent target N starts once and shares timestamps/answer. New first-start timestamps use one transaction time; only first Start sets match.started_at.
- submit-guess keeps {client_build, match_id, round_number, request_id, guess} and existing receipt response exactly. Permit integers 1...5 at Edge, enforce configured/existing/current started round in SQL. Resolve identical successful actor/UUID receipt before current-round/final-state/rate checks, as today; changed match/round/normalized word -> request_conflict. No receipt for rejected guesses. New unreceipted submissions to an old revealed round -> round_already_finished; pending/future/out-of-config -> round_not_active. Deadline equality still rejects and finalizes in the same transaction.
- join-match, match-snapshot and delete-account request shapes unchanged. Snapshot responds with v2 for build >= 2, v1 for build 1 compatible one-round rooms. Initial lobby expiry never prevents rostered recovery or later starts.
- Add invalid_match_configuration (400, "Choose 1, 3, or 5 rounds.") and match_incomplete (409, "This match cannot continue because a player account was deleted.") to SQL safe error helper, Edge map, Swift enum/status/presentation tests. Retain existing error meanings, unknown failures as transport uncertainty, conflict/rate-limit as explicit original-intent Retry/Discard.
- Compatibility is for actual local existing rooms/intents, not a hosted rollout: build-1 create exact old keys means one round; build-1 Start exact old keys permanently means target 1 and retains old completed error behavior; build-1 submit still only round 1. Deny build 1 against floor-2 rooms. Keep legacy RPC create_match(uuid,integer,text,uuid) and start_match(uuid,integer,uuid) as bounded one-round entries; new service-only overloads add smallint count/target. Revoke PUBLIC/anon/authenticated execution on every new signature; retain no obsolete broad grants. Snapshot shares shaping, with the old v1 response branch restricted to legacy one-round rooms.
- Existing create_requests backfill round_count=1; new comparison includes it. New v2 client retries migrated pending create with original build=1/count=1/UUID and old shape, not build2/count3. Guess receipt JSON remains unchanged; original server_time is not freshness or clock calibration.

Frozen Swift service signatures: createMatch(requestID:roundCount:clientBuild:), startMatch(id:roundNumber:), submitGuess(matchID:roundNumber:requestID:guess:clientBuild:); Join/snapshot retain signatures. Explicit original build arguments are only for durable create/guess replay, new intents capture build2. The service selects exact legacy create encoding for saved build1; snapshots always use current build2. Add roundCount/currentRound to LiveMatch, number to LiveRound, revision/revealedRounds/standings to LiveMatchSnapshot. Reuse existing feature/service/storage owners.

### Snapshot v2 and disclosure

Retain all existing required fields/nullability, member Boolean identity, stable seats and player board/result shape. New required fields:

```text
version: 2
match: existing fields plus revision: positive Int64,
       started_at: RFC3339 UTC | null,
       completed_at: RFC3339 UTC | null,
       terminal_reason: null | "account_deleted"
       status: "lobby" | "in_progress" | "completed" | "incomplete"
round: existing RoundDTO, number == match.current_round
revealed_rounds: [RoundDTO] // unique contiguous ascending 1...last revealed
standings: null | {
  through_round: integer 1...round_count,
  is_final: Boolean,
  players: [{
    member_id: UUID,
    rounds_solved: integer 0...through_round,
    efficiency_points: integer 0...6*through_round,
    total_solve_duration_ms: nonnegative integer,
    placement: integer 1...2
  }] // stable member-seat order, canonical SQL placement
}
```

Lobby: current_round=1, round pending, no players/times/answer; revealed_rounds=[], standings=null. At nonfinal reveal current round remains N, status=in_progress, history contains rounds 1...N including identical current reveal; standings.through_round=N, is_final=false. Starting N+1 changes current_round and round to that countdown; history/standings stay through N. Completed iff configured final round revealed; history 1...round_count, standings.is_final=true. Incomplete after a nonfinal reveal has partial standings is_final=false, terminal_reason=account_deleted and no future countdown. During a deletion-blocked active round status remains in_progress with terminal_reason until reveal.

Preserve own current board/result visibility and null opponent clue/scoring fields before reveal. Aggregate only rounds.state='revealed', not solved outcomes from the current unrevealed round. Compute total milliseconds by flooring SUM(solve_duration_us)/1000 once; SQL rank uses exact SUM microseconds. Stable seat order is transport/presentation order, never a ranking tie-breaker. Exact ties share placement. No client recomputation from truncated rows.

Mapper fails closed on malformed required/null/enum/count/identity/timestamps/history/standings, unsupported version, noncontiguous or future history, current/history mismatch, duplicate IDs, pre-reveal opponent leakage, final mismatch or premature final totals. Preserve delayed Cron completion and lock-wait transaction timestamp cases covered in LiveMatchTests; do not tighten timestamps to response-delivery order. Preserve valid countdown forfeits. Validate SQL placements structurally, not by recreating their comparator from milliseconds.

### Canonical match status, timestamps and deletion reason

Snapshot v2 adds required nullable `match.started_at` and `match.completed_at`
(RFC 3339 UTC), alongside required nullable `match.terminal_reason`. These are
canonical match fields; v1 shaping stays unchanged. `completed_at` retains its
existing meaning: actual completion after the configured final round, never a
partial/incomplete result.

| Match state | started_at | completed_at | terminal_reason | Current round / condition |
| --- | --- | --- | --- | --- |
| lobby | null | null | null | Round 1 pending; no deleted slot retained in a lobby. |
| in_progress, ordinary | nonnull | null | null | Current round started; may be nonfinal reveal waiting for creator. |
| in_progress, deletion-blocked | nonnull | null | account_deleted | Current round N is active, N < round_count, at least one member is deleted, and all future starts are blocked. |
| incomplete | nonnull | null | account_deleted | Current round N is revealed, N < round_count, at least one member is deleted; standings partial, is_final=false. |
| completed | nonnull | nonnull | null | Configured final round revealed; completed_at equals that round's completed_at; standings is_final=true. |

During the configured final round, account deletion still anonymizes/forfeits only
eligible current state, but no future round exists to block: retain in_progress
with terminal_reason null and let ordinary finalization complete the match. Deletion
after completed never changes status, match completed_at, standings or reason. During
an active nonfinal round deletion sets the block reason in its transaction; that
round finishes normally and its finalizer transitions to incomplete without setting
match completed_at. Deletion between nonfinal rounds transitions directly from
in_progress/revealed to incomplete. An already incomplete match remains incomplete
when the other identity is deleted. No unplayed round receives a result or answer.

Migration replaces the old status/timestamp CHECK with this matrix, preserving
actual-completion timestamp meaning. Cross-row round/member guards are enforced by
transactional commands under match/round locks. Snapshot mapping rejects impossible
state/timestamp/reason/round/deleted-member combinations and rejects mismatched
final match/round completion times. Preserve existing delayed-finalizer and countdown-
forfeit timestamp behavior; do not compare completion to snapshot transaction time
or assume completion must follow the scheduled round start.

The existing trigger increments revision once per canonical match-row UPDATE in the
same transaction; deletion plus finalization may produce more than one increment.
New reason/status changes and all-round anonymization advance that signal atomically;
identical receipts, already-started target retries, repeated finalization and repeat
deletion preparation make no canonical UPDATE and leave revision unchanged. The
snapshot reports the final revision after any finalization. Never publish updated_at
or introduce a new exact-action timestamp for incomplete matches. Existing safe
started_at/completed_at columns retain their grants/publication meanings; the new
reason is returned only in roster-authorized v2 snapshots. Its new table column
remains service-only: no authenticated SELECT grant or Realtime publication entry.
Existing status and revision signals suffice for canonical refresh.

Required proof: positive and negative SQL CHECK/command cases for every matrix row;
host/guest deletion while active nonfinal, between nonfinal rounds, during final,
after completed, and after already incomplete; concurrent deletion/Start/finalizer
in both orders; exact timestamps/reason/status, idempotent revision behavior, and
matching valid/invalid Swift mapper and lifecycle recovery fixtures. Include both
one-round and 3/5-round cases; no historical count substitutes for this proof.

### SQL migration, deletion, locking and revision

One forward migration (supabase/migrations/202610020001_blind_race_multiround.sql); never edit applied history. Widen match round_count to 1/3/5, current_round to 1...round_count, rounds/guess_requests round numbers to 1...5; preserve two-seat, uniqueness, result and timing constraints. Create configured pending round rows atomically; private secrets/player rows are created only when that target starts. Select random active answer excluding all previously selected match secrets under the match lock. Fail internal_error without partial transition if eligible pool exhausted. Existing one-round fixtures require no ID/answer/result changes.

finalize_round retains exact round comparator and reveals atomically. Nonfinal reveal leaves match in_progress; final reveal completes; accepted D4 blocked nonfinal reveal becomes incomplete. Standings are transactionally consistent SQL aggregation of immutable revealed results under the same match lock, requiring no persisted aggregate cache. Repeated finalization performs no update. All canonical mutations update match/revision in the same transaction; idempotent Start/create/guess/join/snapshot repeats do not. Snapshot includes revision after finalization, never pre-finalizer revision.

Maintain account advisory lock (hashtextextended(user UUID,1)) before account/profile checks and actor receipt/rate work where needed, especially Start versus deletion; recheck profile after acquiring the lock, including submit's existing precheck. Preserve join/create/guess/deletion serialization. Multi-match deletion and Cron enumerate match IDs ascending (202609260004), then rounds ascending, players stable seat order. Under a match lock there can be at most one active round; finalizers must never acquire an actor lock after taking game locks. Audit receipt/rate row ordering and independent barrier races, not just a nominal lock list. Do not regress 202609260001–004 repairs.

Accepted D4 policy: lobby host/guest deletion stays unchanged. After start, detach/anonymize the member across all reveals; forfeit only their current nonterminal player, never rewrite solved/failed/timedOut outcomes. Mark subsequent advancement blocked. If current nonfinal active, set the reason and finish under ordinary all-terminal/deadline rules; if between nonfinal rounds, become incomplete immediately. In the configured final round there is no block reason and finalization completes normally, as defined in the matrix. Final configured reveal still completes normally; deletion after completion never changes results/status. Both deleted removes all reversible mappings; preserve established survivor-retention behavior, no new history/retention rule. Preparation/Auth/completion receipts and stale-bearer denial remain unchanged.

The new block reason is snapshot-only/service-readable, while existing status
reads/publication remain clue-free; keep aggregate fields out of authenticated base-table column grants/Realtime. Keep matches.updated_at/member auth/selected_at/private schemas hidden. Direct revealed round/guess access remains roster-authorized; future pending rows carry no answer/players. No new public result table is needed.

Forward proof must precede any destructive reset: inventory actual local data/linked refs and prove fixture disposability. If current rooms are user data, stop reset and preserve them; obtain a controller-selected disposable local target. On a confirmed disposable baseline fixture, retain legacy lobby/active/revealed rooms, create receipts and accepted-guess receipts, apply the migration forward and assert exact old identities/results/grants plus new contracts. P4-B proved `npx --no-install supabase migration up --local` against the pinned local CLI and recorded its output before promotion to the engineering runbook. Every later use still requires the documented inventory and disposability checks. Do not substitute a clean reset for forward proof. Then clean reset/test/lint on confirmed disposable local state. A migration failure rolls back its transaction; after applied product changes use a reviewed forward repair, not destructive reset of retained rooms or down-migration guesswork.

### Recovery-file and session boundaries

Keep the existing protected account path live-recovery-v1.json to avoid stranding actual files; formatVersion=2 denotes the new payload. Decode format1 explicitly: create becomes original build1/count1/UUID; guess becomes original match/round1/build1/word/UUID. A pointer alone remains the same pointer. Atomically save v2 before any migrated intent dispatch. Reject unknown/corrupt/inconsistent versions without deleting data; explicit existing Retry/Discard and cleanup remain available. New create includes count/build/UUID; new guess includes match/round/build/word/UUID. Save no board/answer/opponent/credential; no new queue or history. Sign-out/deletion clears this same file; migration save/read/clear failures preserve storageUnavailable and account isolation.

Start captures its target at the button intent boundary. Uncertain Start fetches a snapshot; retries of that captured action use the same target. No durable Start queue is necessary: relaunch fetches current state and a new deliberate Start is a new user action. Disable duplicate Start while a command/pending guess/storage recovery is unresolved.

Retain one command/one fetch, trailing refresh, Auth refresh once, 10s timeout and 5/10/20/30s backoff. Add presentation/match-selection generations (or extend existing epoch guards) for Home, background, Resume and room switches: cancel cannot alone prevent delayed application. Durable command completion may save the current-account pointer/receipt after Home, but cannot open hidden UI or restart recovery. On canonical round advance clear only the old round's draft/animation selection and render new board atomically. An old pending guess remains original and blocks new input until receipt or definitive error is durably resolved. Old success clears that exact pending identity and requests current snapshot; old error never repopulates the new round's draft or overwrites new errors. Snapshot alone cannot acknowledge a request.

Use revision to reject lower canonical mutation state within the same match/account, plus existing command epochs and selection generations; server_time is not a revision. Equal revision may legitimately change countdown to playing with time, so apply serialized fresh snapshots using existing clock rules; never freeze effective phase merely because revision is equal. Replayed receipts never calibrate display time.

Nonfinal revealed in_progress must retain subscription and bounded watchdog while open/foreground, including a surviving creator waiting for ordinary absent guest and a guest waiting for creator. Completion/incomplete stops ordinary recovery only after pending receipt resolution; explicit Resume starts a fresh catch-up even for finals, then stops. Reveals/history are fetched snapshots, not local history. A selected prior reveal is display-only; it cannot supply guess/start targets. New current countdown exits old reveal presentation; pending/D4-blocked/current statuses remain canonical.
