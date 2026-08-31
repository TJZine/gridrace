# Historical Decisions

This file preserves stable product and architecture decisions whose rationale should
survive individual implementation plans. It is not a status log or current-task
tracker. Current execution is summarized in [`NOW.md`](NOW.md). The detailed
[Phase 2 and Phase 3 Live Slice Plan](plans/2026-08-30-phase-2-3-live-slice.md)
is paused and preserved for later adaptation.

## 2026-08-31 — Ship Daily Classic Before Accounts and Live Racing

**Decision:** Daily Classic is GridRace's first complete permanent mode. It uses a
fixed 00:00 UTC boundary, an explicit versioned answer schedule, local Codable
progress and immutable result history, and idempotently derived statistics. Accounts,
friends, and the live backend follow after this local experience is complete.

**Rationale:** A polished daily loop proves the core rules, content, persistence,
accessibility, and result model now. It creates a useful product and sync-ready data
without making unfinished authentication or multiplayer infrastructure a launch
dependency.

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

## 2026-08-30 — Split Backend Foundation From the Live Slice

**Decision:** Phase 2 establishes the local Supabase, authentication/profile,
private-data, RLS, command, seed, deletion, and database-test foundation. Phase 3
uses that foundation for exactly two authenticated players and one round through
create, join, creator start, authoritative guessing, snapshot recovery, deadline
finalization, and shared reveal.

**Rationale:** The split makes the trust boundary independently reviewable before
the client relies on it without expanding or changing the focused product slice.

## 2026-08-30 — Retain Only Anonymized Survivor Results on Deletion

**Decision:** Account deletion removes the profile and Auth identity. An unstarted
host lobby is removed; an unstarted guest slot is removed. Active deletion is an
explicit authenticated forfeit. A completed or otherwise survivor-visible result
may retain the deleted slot and accepted rows only after the auth link and profile
are removed and its presentation becomes nonidentifying `Deleted Player` data.

**Rationale:** Hard deletion must leave no reversible user mapping while preserving
the other participant's structurally valid immutable result.
