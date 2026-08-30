# ADR 0001: Native SwiftUI with Authoritative Supabase

- Status: Accepted
- Date: 2026-08-30

## Context

GridRace is a private synchronous word race. A production result is trustworthy only
if every player receives the same server-timed answer validation, feedback, score,
and state transition while the answer stays unavailable to normal client credentials
before reveal.

The first client is iPhone-only, and the initial team benefits from a small stack
whose trust boundaries can be inspected directly.

## Decision

Use a native Swift 6 and SwiftUI iPhone client. Use Supabase as the later production
backend, with PostgreSQL transactions and RLS as the canonical data boundary and
authenticated server commands for authoritative game mutations.

Phase 1 remains local. It proves the interaction and shared evaluator contract
without presenting bundled tutorial data as a production security design.

## Rationale

SwiftUI and Apple concurrency cover the required lifecycle, accessibility, and
platform integration without a third-party client architecture. PostgreSQL provides
explicit constraints, transactions, and policy-enforced reads for secret-bearing
multiplayer state. Supabase supplies those database capabilities with authentication,
server functions, and change notifications while allowing snapshots—not event
delivery—to remain recovery truth.

## Alternatives not selected

**Game Center with CloudKit:** Game Center's matchmaking and leaderboard strengths do
not own GridRace's private answer evaluation or transactional match state. CloudKit
could store Apple-platform data, but this product still needs a deliberately designed
server command and secret-isolation boundary. Selecting it would not remove that work
and would couple the core to Apple account and record-sharing semantics.

**Firebase:** Firebase can support a realtime mobile backend, but GridRace's critical
rules map directly to relational constraints, transactional functions, private
schemas, and row policies. Choosing Firebase would require expressing those same
invariants through a different data and rules model without a present product gain.

These are selection reasons, not claims that either alternative is incapable of
building the product.

## Consequences

- The server, not the app, owns production answers, time, rules, scores, and
  transitions.
- Normal client credentials receive least-privilege projections and cannot mutate
  canonical game rows directly.
- Realtime remains a refresh signal; canonical snapshots recover state.
- Native accessibility and lifecycle behavior remain first-class client work.
- A future backend introduces operational responsibility for migrations, RLS tests,
  functions, secrets, backups, and environment separation.
- No generalized rules engine, backend-provider layer, or speculative integration is
  added before a current phase needs it.

Implementation details and phase boundaries live in
[`../architecture.md`](../architecture.md), not in this rationale record.
