# GridRace Architecture

This document is the current architecture authority. It separates the permanent
local Daily Classic mode, the Phase 1 tutorial, and the active Phase 2/3 backend
and planned live-race client.

## Daily Classic architecture

Daily Classic is a native local vertical slice. A main-actor observable model owns
today's board, input, terminal presentation, settings, and persistence calls. Pure
values own UTC puzzle identity, deterministic answer selection, Hard Mode checks,
result records, statistics, and spoiler-safe sharing. SwiftUI views render that
state and send intents.

The bundled word pack has separately versioned accepted guesses and an explicitly
ordered answer schedule. Codable storage is sufficient for the small current state,
settings, and completed-result history. Completed puzzle records are immutable and
statistics are derived idempotently from history. This shape can later map to cloud
records without adding a local database framework or speculative repository layer.

The daily boundary is 00:00 UTC. Device time chooses which published puzzle to show.
This local mode makes no secrecy claim for bundled answers.

## Daily account and synchronization boundary

Accounts are optional. Guest Codable files remain the immediate gameplay source while
signed out. Each authenticated UUID has a separate local directory; changing or
deleting an account swaps away from that directory before another account can render
it. Supabase Auth sessions use the SDK's Apple-platform Keychain storage and never
enter Daily Classic files or `UserDefaults`.

After sign-in, a small sync coordinator pulls owner-private state and continues using
the account's local files for gameplay. It marks the current compact snapshot pending
after an accepted row or completion and retries on sign-in, foreground, and explicit
retry. Draft letters remain device-local. Exact records deduplicate; an immutable
completion always dominates active progress; a longer exact-prefix active attempt
advances; divergent active attempts and distinct terminal results are shown as choices
rather than silently combined. Statistics are always recalculated from the merged
immutable results.

`public.daily_progress` is mutable only through `sync_daily_progress` and carries a
monotonic revision. `public.daily_imported_results` is an immutable client-originated
personal-history table written only through `import_daily_result`. Both are owner-only
under grants and RLS. There is deliberately no verified column, verified-results
table, promotion RPC, or competitive statistics path. A future verified Daily result
must come from a separate server-owned evaluator that selects the answer, accepts and
timestamps guesses, controls attempts, and finalizes the result.

## Phase 1 local architecture

Phase 1 is a native, local iPhone app built with Swift 6, SwiftUI, Observation, and
Apple frameworks. Its deployment target is iOS 18. It contains no authentication,
networking, Supabase SDK, push notifications, or local SQL database.

The local tutorial owns one bundled answer, accepted-word data, and deterministic
ghost behavior. That answer is intentionally present in the app bundle and makes no
production secrecy claim. Tutorial types and fixtures do not implement or impersonate
production services.

Phase 1 contains only the seams needed now:

| Seam | Responsibility |
| --- | --- |
| SwiftUI views | Render feature state and send user intents. Views do not evaluate authoritative production guesses or call Supabase. |
| `@MainActor` Observation model | Own the tutorial session, board, countdown, opponent progress, reveal decisions, and cancellable tasks. |
| Pure game rules | Normalize and validate input, evaluate duplicate letters, aggregate keyboard evidence, and transition local board state without UI, network, or persistence knowledge. |
| Absolute-time countdown | Derive the displayed state from start/end instants and an injected current-time seam. Backgrounding does not extend or pause the interval. |
| Resources | Bundle the development word pack with the app. Swift and TypeScript tests load the one canonical rule-vector JSON directly from the repository. |

There is no generalized rules engine, coordinator framework, repository layer, or
empty future-feature structure. Later phases add a boundary only when its production
responsibility exists.

## iOS ownership and lifecycle

Feature views remain passive. A session-scoped, `@MainActor` observable model owns
state shared across its tutorial screens and is the only UI-facing owner of async
work. Pure rule values remain independent of actor, presentation, persistence, and
transport concerns.

The model stores any unstructured task it starts, cancels the prior task before
replacement, and cancels session work when the session ends. Task bodies check
cancellation before applying results. Structured child work stays inside its parent
operation. View appearance may request work but does not become the lifetime owner
of match state.

Scene changes never alter a countdown deadline. In Phase 1 the model recomputes from
the absolute local fixture timestamps. In a networked phase, foregrounding triggers
a canonical snapshot refresh and the server timestamps remain authoritative.

Optional haptics use native APIs and respect the user's in-app preference. SwiftUI
environment values drive Reduce Motion, Increased Contrast, Bold Text, and Dynamic
Type behavior; domain rules do not depend on those presentation choices.

## Phase 2 backend and Phase 3 live boundary

The production design is a native SwiftUI client backed by authoritative Supabase.
Phase 2 implements the local backend/authentication trust boundary. Phase 3 connects
the fixed two-player, one-round client slice to it. The complete 2–8 player,
multi-round MVP remains later work.

The client eventually displays server-owned state and submits authenticated intents.
The backend selects answers, validates accepted words, computes feedback and scores,
timestamps actions, and advances matches, rounds, and players. A normal authenticated
client cannot read a round answer before reveal or directly mutate authoritative game
state. All Supabase access stays behind service boundaries; SwiftUI views never import
or call the SDK.

Phase 2/3 responsibilities are intentionally narrow:

| Component | Phase 2/3 responsibility |
| --- | --- |
| Supabase Auth | Establish identity and sessions, including Sign in with Apple. Auth identity is not a public profile and email is never shown to other players. |
| PostgreSQL | Own canonical profiles, rosters, rounds, guesses, timestamps, scores, and state transitions. Reports/blocks are later responsibilities. Constraints and transactional functions enforce valid, idempotent changes. Private schemas own answers and other server-only data. |
| Grants and RLS | Give each exposed table the least privilege needed for the authenticated player and game phase. They deny private-answer reads and direct authoritative mutations. |
| Edge Functions | Authenticate callers, validate build and input, invoke explicit transactional commands, and map stable typed results. Service credentials stay here and never ship in the app. |
| Realtime | Signal that relevant state may have changed. It does not carry secret clues or replace a canonical snapshot. |
| Cron | Ask server-owned finalization commands to resolve elapsed deadlines and other scheduled game transitions. It does not introduce a second clock or transition implementation. |
| APNs | Deliver optional, clue-free notification prompts. A notification causes a snapshot refresh; it is not game state. Device tokens remain server-only. |

Phase 2 implements the local backend rows above; Phase 3 client integration remains
pending. APNs, reports/blocks and opponent presence are later. The exact six-command and
versioned snapshot shapes live in [`live-api-contract.md`](live-api-contract.md).
The client uses only create, join, creator start, guess submission, snapshot, and
account deletion commands; profile updates remain owner-scoped RLS writes.

Public rows contain no answer. The secret-bearing `private` schema has no grant for
anonymous or authenticated roles. A separate narrowly executable RLS-helper schema
may answer membership predicates without granting access to private words or round
secrets. Normal clients receive safe column grants: opponent timing, efficiency,
and placement are not available through the base match row and are returned only
by the conditional snapshot after reveal; member auth identifiers and the
exact-action `matches.updated_at` timestamp remain unavailable to authenticated
clients.

Every canonical change transactionally increments the timestamp-free monotonic
`matches.revision`. Phase 3 Realtime publishes only that roster-authorized row's
timing-free column projection and emits a refresh signal, avoiding
secret or timing-bearing change payloads. A snapshot remains mandatory after the
signal.

PostgreSQL owns canonical match and round state. Explicit transitions are
transactional commands; the countdown-to-playing state is interpreted from the
stored server timestamps without a client write. Deadline finalization is the same
idempotent server operation whether invoked by a player request or Cron. Connection
observations may affect the displayed connection state, but disconnection does not
itself forfeit or rewrite canonical results.

## DTO and domain separation

Transport DTOs represent the versioned wire contract and are decoded only at the
service boundary. Mappers reject malformed or impossible combinations before
creating domain values. Domain models express the states the UI may render and do not
contain Supabase row types, database naming, raw JSON, or credentials. Views receive
domain values and stable feature errors, never DTOs.

Service protocols are added with the first network slice at real trust or lifecycle
boundaries: authentication, match commands/snapshots, and realtime signals. A
protocol does not exist merely to wrap a local value or create theoretical provider
choice.

## Snapshot recovery

The canonical snapshot is recovery truth. The client refreshes it on session entry,
reconnect, foreground return, a relevant Realtime signal, uncertain command outcome,
local inconsistency, and countdown or round deadline. A validated snapshot fetched
under the current account/match generation replaces the feature's derived match state as one main-actor update.

Realtime events may be delayed, duplicated, dropped, or reordered without changing
the result. If a command response is lost, the client follows the command-specific
retry/snapshot rules rather than guessing whether a transition succeeded. Pre-reveal snapshots omit answers, opponent words,
opponent feedback, keyboard evidence, starting words, and exact solve times.

The pending Phase 3 session serializes/coalesces refreshes with commands, rejects
late results from another account/match, and requests a trailing fetch for signals
received during a fetch. Snapshot v1 has no state revision; neither delivery order
nor its transaction timestamp is a revision. An open foreground unfinished match
also refreshes after five seconds without a successful snapshot, with bounded
failure backoff. Stop on background/exit/reveal/expiry or loss of authorization.
This covers silent event loss; subscriptions alone do not prove convergence.

The client owns no offline live guess queue. Implemented P2-04A creation receipts and
planned Phase 3 account-scoped recovery storage preserve request IDs across lost
responses and relaunch; the client resolves uncertainty before accepting another intent.
It saves no authoritative board, answer, opponent payload or credential. Exact retry,
nullability, timing, error and recovery rules live in the live API contract.

Use the existing authenticated SDK client through service composition. One live
session owns live state; the Daily coordinator continues to own Daily/account
synchronization. Reuse passive presentation and pure keyboard evidence from accepted
rows, but never use a bundled evaluator/dictionary to decide live acceptance.

Opponent presence is deferred in this slice. Only local transport status is known;
opponent inactivity or local socket connectivity is not an opponent online signal.

Snapshot version 1 uses stable member-seat order. A lobby has a pending public round
with no timestamps or players. A started round includes the requester's full board
and only coarse opponent state/count until reveal; reveal adds the answer, both
boards, server timing, efficiency, and competition placement. Mapping rejects
impossible combinations before they become feature state.

## Phase 2/3 account deletion

The authenticated deletion command first prepares canonical data transactionally,
then the server hard-deletes the Supabase Auth identity. An unstarted host lobby is
removed; an unstarted guest slot is removed. Deletion during play is an explicit
authenticated forfeit. A result needed by the surviving participant retains only a
detached member slot named `Deleted Player` and its canonical result rows. The
profile and auth link are removed, no reversible user mapping remains, and every
other command requires an active profile/member mapping so a previously issued JWT
cannot regain access.

Database preparation treats an absent profile as already complete. An already
absent Auth identity is also success. To converge after a lost success response, the
deletion function hashes the initiating bearer and stores a private service-only
receipt. A pending receipt temporarily references the user so a retry can finish Auth
deletion; the Auth foreign key clears that reference, and completion retains only the
one-way hash and terminal state. The narrow function route bypasses gateway JWT
rejection so the handler can validate a stale bearer against this receipt; it grants
no account access and returns only deletion success. Raw bearers never enter the
database or logs. Real Apple provider-token revocation remains a production-hardening
proof when provider credentials are unavailable locally.

Daily progress and imported personal results are deleted in the same authenticated
database preparation transaction. The iOS client removes only that UUID's local
account cache after the Edge Function reports successful server deletion, then drops
the active session and returns to the untouched guest store.

## Secrets, privacy, and logs

- Production answers live in a private schema with no authenticated-client grant and
  enter a client-visible snapshot only at reveal.
- Supabase service credentials, Apple private keys, APNs credentials, and database
  administrative credentials never enter source control or the app bundle.
- Public client configuration is environment-specific when networking is introduced;
  development, staging, and production do not share secrets or data.
- Production logs and analytics never contain raw answers, guesses, auth tokens,
  service credentials, invite secrets, or push tokens. Identifiers use privacy
  redaction appropriate to the logging system.
- User-visible failures are typed and actionable without exposing internal queries,
  policies, credentials, or private opponent data.

The detailed collection and deletion requirements live in
[`privacy-data-map.md`](privacy-data-map.md). Exact retention periods remain explicit
pre-production decisions rather than defaults inferred by the client.

## Phase boundary

Phase 2 proves the local backend, authentication/profile boundary, private storage,
RLS, commands, deletion, seed, and database/Edge tests before the client relies on
them. Phase 3 proves the smallest two-player, one-round live race, including server
authority, idempotency, deadline finalization, snapshot recovery, Realtime
convergence, and answer secrecy. Later phases must not generalize the implementation
until that proof is complete.
