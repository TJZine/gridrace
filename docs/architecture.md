# GridRace Architecture

This document is the current architecture authority. It separates the local Phase 1
tutorial from the production architecture selected for later phases.

## Current system: Phase 1

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

## Selected production boundary: later phases

The production design is a native SwiftUI client backed by authoritative Supabase.
It is selected now but is not implemented in Phase 1.

The client eventually displays server-owned state and submits authenticated intents.
The backend selects answers, validates accepted words, computes feedback and scores,
timestamps actions, and advances matches, rounds, and players. A normal authenticated
client cannot read a round answer before reveal or directly mutate authoritative game
state. All Supabase access stays behind service boundaries; SwiftUI views never import
or call the SDK.

Future responsibilities are intentionally narrow:

| Component | Later production responsibility |
| --- | --- |
| Supabase Auth | Establish identity and sessions, including Sign in with Apple. Auth identity is not a public profile and email is never shown to other players. |
| PostgreSQL | Own canonical profiles, rosters, rounds, guesses, timestamps, scores, reports, blocks, and state transitions. Constraints and transactional functions enforce valid, idempotent changes. Private schemas own answers and other server-only data. |
| Grants and RLS | Give each exposed table the least privilege needed for the authenticated player and game phase. They deny private-answer reads and direct authoritative mutations. |
| Edge Functions | Authenticate callers, validate build and input, invoke explicit transactional commands, and map stable typed results. Service credentials stay here and never ship in the app. |
| Realtime | Signal that relevant state may have changed. It does not carry secret clues or replace a canonical snapshot. |
| Cron | Ask server-owned finalization commands to resolve elapsed deadlines and other scheduled game transitions. It does not introduce a second clock or transition implementation. |
| APNs | Deliver optional, clue-free notification prompts. A notification causes a snapshot refresh; it is not game state. Device tokens remain server-only. |

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
local inconsistency, and countdown or round deadline. A validated newer snapshot
replaces the feature's derived match state as one main-actor update.

Realtime events may be delayed, duplicated, dropped, or reordered without changing
the result. If a command response is lost, the client refreshes rather than guessing
whether a transition succeeded. Pre-reveal snapshots omit answers, opponent words,
opponent feedback, keyboard evidence, starting words, and exact solve times.

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

The next network phase may add the smallest two-player, one-round vertical slice.
It must preserve the contracts above and prove server authority, RLS denial,
idempotency, snapshot recovery, and answer secrecy. Phase 1 adds none of that future
code.
