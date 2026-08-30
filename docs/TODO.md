# TODO

> Non-authoritative backlog. These are candidates, not approved plans, current
> status, or product contracts. Track current work only in the one active file under
> [`docs/plans/`](plans/); today that is the [Repository Foundation Plan](plans/2026-08-30-repository-foundation.md).
> Before starting a candidate, use the planning depth required by the engineering
> runbook. Promote it into a dated plan only when durable tracking is warranted; then
> remove or revise the candidate here.

## Phase 0 Follow-ons

- Consolidate the supplied product rules and server-owned state transitions into
  focused product, architecture, and game-rule references.
- Prototype the create → invite → race → reveal → rematch screen flow, including an
  original visual direction and accessible, reduced-motion reveal.
- Record the privacy data map and backend ADR before client or schema implementation.
- Curate a 100-answer development pack and create the shared evaluator test-vector
  schema and fixtures.
- Bootstrap only the repository surfaces needed for the native iOS app, local
  Supabase stack, word-pack build, and their tests; pin tool versions as introduced.

## First Vertical Slice

- Implement the duplicate-letter evaluator in Swift and TypeScript against the same
  vectors, then build the accessible local board, keyboard, and injected-clock timer.
- Add the minimum Supabase migrations for authentication, profiles, matches, two
  players, one round, private words/secrets, guesses, and tested RLS boundaries.
- Implement create, join, ready/start, idempotent guess submission, canonical match
  snapshots, progress subscriptions, deadline finalization, reconnect, and reveal.
- Prove on two separate clients that results converge, retries create one guess,
  reconnect restores the board, and normal client credentials cannot read the answer
  before reveal.

Everything beyond the two-player, one-round proof remains deferred until that slice
meets its exit criteria.
