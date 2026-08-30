# TODO

> Non-authoritative backlog. These are candidates, not approved plans, current
> status, or product contracts. Track current work only in the one active file under
> [`docs/plans/`](plans/); today that is the [Phase 0 and Phase 1 Foundation Plan](plans/2026-08-30-phase-0-1-foundation.md).
> Before starting a candidate, use the planning depth required by the engineering
> runbook. Promote it into a dated plan only when durable tracking is warranted; then
> remove or revise the candidate here.

## First Networked Vertical Slice

- Add the minimum Supabase migrations for authentication, profiles, matches, two
  players, one round, private words/secrets, guesses, and tested RLS boundaries.
- Implement create, join, creator start, idempotent guess submission, canonical match
  snapshots, progress subscriptions, deadline finalization, reconnect, and reveal.
- Prove on two separate clients that results converge, retries create one guess,
  reconnect restores the board, and normal client credentials cannot read the answer
  before reveal.

Everything beyond the two-player, one-round proof remains deferred until that slice
meets its exit criteria.
