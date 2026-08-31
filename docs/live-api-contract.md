# GridRace Live API Contract

This document freezes the Phase 2 backend and Phase 3 two-player live-slice wire
contract. [`game-rules.md`](game-rules.md) remains authoritative for gameplay;
[`architecture.md`](architecture.md) owns component boundaries. All JSON uses
`snake_case`, UUIDs use canonical lowercase strings, and timestamps use RFC 3339 UTC
with fractional seconds.

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

## Commands

All commands require a bearer session. Edge code authenticates it before creating a
separate server-only client. Mutations invoke one transactional database command;
normal credentials cannot execute those functions directly.

### `create-match`

Request:

```json
{ "client_build": 1 }
```

Response data:

```json
{ "match_id": "00000000-0000-0000-0000-000000000000" }
```

Creation forces two seats, one round, a 60-minute expiration, the current build
floor, creator seat one, and a pending public round. The client then fetches a
snapshot.

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

`solve_duration_ms` and `efficiency_points` are null unless solved. The database
normalizes and validates the guess, evaluates feedback, timestamps it, transitions
the player, and finalizes when applicable in one transaction. An identical retry is
resolved before rate limiting and returns the original sequence, feedback, server
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

The mapper rejects unsupported versions, rosters outside one or two unique seats,
a started match without exactly two members, duplicate IDs or seats, invalid enum
values, counts outside 0–6, noncontiguous guess sequences,
malformed five-letter words or feedback, a revealed answer before `revealed`, any
opponent clue field before reveal, missing reveal fields after reveal, timestamps
that contradict state, or a player/board mismatch.

## Realtime and recovery

The public `matches` row contains no private clue data and has an `updated_at`
revision signal. Every relevant command touches it after committing canonical
member, round, player, or guess changes. The iOS Realtime service subscribes only to
the current rostered match row and emits `Void`; it never treats payload data or
delivery order as state.

The session model coalesces refreshes and fetches a snapshot on entry, after each
create/join/start, after an uncertain command, after a relevant signal, on reconnect,
foreground return, local countdown/deadline expiry, and any inconsistent ordering.

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
