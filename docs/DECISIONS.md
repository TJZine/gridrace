# Historical Decisions

This file preserves stable product and architecture decisions whose rationale should
survive individual implementation plans. It is not a status log or current-task
tracker. Current execution is summarized in [`NOW.md`](NOW.md). The detailed
[Phase 4 Blind Race Plan](plans/2026-10-02-phase-4-blind-race.md)
tracks the accepted expansion. The Phase 2/3 plan is Historical evidence.

## 2026-10-03 — Adopt the Stamped Scorecard Visual Direction

**Decision:** Replace the indigo/coral/teal lane-edge presentation with the
stamped scorecard direction in [`design-direction.md`](design-direction.md):
warm paper and ink, claret round-seal tiles (filled correct, double-ring present,
unfilled dimmed absent), serif plus monospaced system type, a program-schedule
Home, Live Create/Join off Home, and gameplay limited to header, board, and
keyboard.

**Rationale:** A simulator audit showed absent feedback dominating the board,
indigo overloaded across action and feedback, a meaningless lane-edge bar, a
form-like Home, and the sixth row clipped in the tutorial race.

**Consequences/revisit:** Accessibility, secrecy, and original-identity invariants
are unchanged. Passport-stamp tiles are the designated fallback only if testing
shows round tiles hurt legibility. All surfaces were designed on 2026-10-03;
[`plans/2026-10-03-stamped-ui-refresh.md`](plans/2026-10-03-stamped-ui-refresh.md)
implements them after the human-approved rescope moves Phase 4's OS-assisted
accessibility proof into that plan.

## 2026-10-02 — Expand Private Blind Race to Two-Player Multi-Round Matches

**Decision:** Keep exactly two authenticated players and manual room codes. Offer
1, 3, or 5 rounds, default 3, with private randomly server-selected nonrepeating
answers. The creator starts every countdown after the preceding reveal. Preserve
canonical reveals and show server-owned round, cumulative and final standings using
the existing exact scoring and tie rules. This anytime live mode stays separate
from Daily Classic and is not solo practice.

**Rationale:** The two-player authoritative slice is proved locally. Multi-round
racing expands the existing loop without wider rosters, a generalized engine or
new social/distribution surfaces.

**Consequences/revisit:** Reuse current UI: native rounds selection at Create,
Round N of M, existing reveal followed by standings and creator-only Start next,
final standings with Home and access to prior reveals. Ordinary creator absence
leaves a reveal waiting. After either account deletes, finish any started round
under existing forfeit/deadline rules, anonymize survivor-required reveals and
freeze unstarted rounds with an explicit incomplete-match presentation. Do not
transfer host, cancel, automatically advance or finish the match against a deleted
guest. The human accepted both presentation and deletion recommendations with
“use both recs.” Independent plan review and the accepted-plan checkpoint precede
implementation; this decision does not claim shipped behavior. Broader rosters,
rematch, competitive history, links, notifications, presence, moderation, hosting,
retention and distribution remain later requirements. Revisit the deletion policy
only under a new explicit product decision.

## 2026-09-22 — Keep the Focused Native/Supabase Slice With Bounded Recovery

**Decision:** Retain SwiftUI and the PostgreSQL/RLS, authenticated Edge, Realtime
signal and canonical-snapshot ownership split. Before the live client, make creation
retry-safe with a persisted request ID. Use account-bound pending intents and bounded
foreground snapshot refresh to recover silent event loss. Defer opponent presence
labels for this slice; show only this client's transport status and opponent game
progress. Presence remains a later MVP responsibility.

**Rationale:** The existing stack fits low-frequency private races. Replacing it would
repeat authentication, transaction, privacy and recovery verification without a
current product benefit. Lost create responses and silently missed events are real
holes the client must resolve. A local socket does not establish opponent presence.

**Consequences/revisit:** The retry-safe create API change is implemented locally and
the backend security/integration checkpoint must precede Swift integration. No generic
command framework, polling of completed rooms or presence channel is introduced.
Revisit transport after measured contention/fan-out,
and platform choice only for a concrete additional-platform requirement. The
maintainer owns the later presence decision after the local slice is proved.

## 2026-09-22 — Validate With No Initial Spend

**Decision:** Use local development and free services while validating with the owner
and friends. Traction outside that group is a reason to reconsider spending, not
permission to upgrade automatically. Every paid commitment requires maintainer approval.

**Rationale:** The product needs evidence of use before recurring infrastructure cost.
Free-tier capacity/availability and native distribution must be checked explicitly;
security, deletion, retention and recovery are not traded away to fit a quota.

**Consequences/revisit:** This plan authorizes no hosted deployment or purchase.
Before friend distribution the maintainer resolves Apple membership/distribution and
hosted retention, backups and provider setup. Native TestFlight may require a paid
membership even when hosting is free; do not promise zero-cost distribution or change
the client stack silently. Revisit that boundary at distribution planning or evidence
of external users, with a concrete cost proposal.

## 2026-08-31 — Separate Imported Daily History From Verified Competition

**Decision:** All Daily Classic results produced by the bundled client evaluator are
stored only as immutable `daily_imported_results` for the owner's history, backup,
streaks, and statistics. No client-writable verification flag or promotion path
exists. Future competitive results require a separate server-owned attempt flow and
result surface.

**Rationale:** Recomputing a bundled puzzle does not prove when or how a client played.
A hard database provenance boundary lets personal synchronization ship now without
creating counterfeit evidence for friends or leaderboards later.

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
