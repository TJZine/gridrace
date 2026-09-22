# GridRace Live API Contract

This document freezes the Phase 2 backend and Phase 3 two-player live-slice wire
contract. P2-04A now implements the retry-safe create and Boolean deleted-member
identity corrections locally; the remaining backend security/integration checkpoint
must pass before the live client ships.
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

Pending target live recovery stores only the latest match pointer and one pending
intent in account-scoped protected local storage. Relaunch resolves uncertainty and
fetches a snapshot before new input. Clearing it on sign-out does not leave/forfeit a
server match; rejoining by code remains possible. See the active plan for lifecycle,
clock display, storage-failure and verification requirements. There is no offline
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
