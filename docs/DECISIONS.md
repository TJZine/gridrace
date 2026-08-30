# Historical Decisions

This file preserves stable product and architecture decisions whose rationale should
survive individual implementation plans. It is not a status log or current-task
tracker. Current execution lives in the one active file under [`docs/plans/`](plans/);
today that is the [Phase 0 and Phase 1 Foundation Plan](plans/2026-08-30-phase-0-1-foundation.md).

## 2026-08-30 — Focus the Product on Blind Race

**Decision:** Build one private, synchronous five-letter mode for 2–8 friends. A
match supports 1, 3, or 5 rounds, defaults to 3, and exposes opponent progress but
not letters or feedback until the shared reveal.

**Rationale:** The create → invite → race → reveal → rematch loop is the product
claim that needs validation. More modes would dilute that test and increase
moderation, synchronization, and interface scope.

## 2026-08-30 — Use a Native SwiftUI Client

**Decision:** Build the initial client for iPhone with Swift 6, SwiftUI, Swift
concurrency, Observation-based feature models, and protocol-backed services. Do not
introduce a third-party application architecture for the initial scope.

**Rationale:** Native frameworks cover the required UI and lifecycle behavior while
keeping the client small enough to reason about during multiplayer recovery work.

## 2026-08-30 — Make Supabase Authoritative

**Decision:** The server selects answers, validates and evaluates guesses,
timestamps results, scores players, and advances match state. Answers remain in a
private schema until reveal; authenticated clients receive constrained reads through
RLS and use explicit server commands for game mutations.

**Rationale:** Keeping secrets and transitions server-side prevents normal client
credentials from leaking answers or forging game state and provides one result for
all participants.

## 2026-08-30 — Recover From Canonical Snapshots

**Decision:** Realtime events prompt UI updates, but canonical match snapshots are
the source of truth on entry, reconnect, foreground return, command uncertainty, and
timer expiry.

**Rationale:** Correctness cannot depend on every realtime event arriving exactly
once or in order.

## 2026-08-30 — Prove the Smallest End-to-End Slice First

**Decision:** The first networked milestone is exactly two players, one round,
server-selected answers, server-validated guesses, progress updates, reconnection,
and reveal. Rematches, notifications, history, and the wider match loop follow only
after that slice works.

**Rationale:** This is the smallest build that tests the distinctive live product
loop and its security and synchronization boundaries.

## 2026-08-30 — Defer Broad Social and Game Systems

**Decision:** Public matchmaking, chat, a friend graph, asynchronous modes, custom
words, ranked competition, monetization, spectators, and a generalized game-plugin
architecture are outside the initial build.

**Rationale:** None is required to validate private live races, and each adds product
or operational complexity before demand is established.
