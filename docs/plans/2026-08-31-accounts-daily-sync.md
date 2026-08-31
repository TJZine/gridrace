Status: Historical
Scope: Optional accounts and local-first Daily Classic cloud synchronization
Owner: Primary orchestrator
Started: 2026-08-31
Last updated: 2026-08-31

# Goal

Let players optionally sign in, own a private profile, import guest Daily Classic
history, synchronize accepted progress and immutable completed results across devices,
derive personal statistics from synchronized history, sign out safely, and delete the
account without changing signed-out or offline play.

# Boundaries and decisions

- Guest play remains the immediate, offline-capable gameplay path.
- `daily_imported_results` is a client-originated personal-history surface. It has no
  verification field and no path into future competitive data.
- Completed imports are immutable and exact-repeat idempotent. Same-puzzle payload
  differences are typed conflicts.
- Progress advances only by exact-prefix extension. Completed results dominate
  compatible progress; divergent attempts require a user choice.
- Guest files and per-account files are isolated. Guest data survives import until
  server persistence is confirmed.
- Statistics remain derived from immutable completed results.
- Native Sign in with Apple uses a secure raw nonce, its SHA-256 value for Apple, and
  the raw nonce for Supabase. Debug local auth contains no committed credentials and
  is absent from Release.
- No friends, leaderboards, verified Daily path, generalized job system, or live-match
  UI is part of this milestone.

# Large chunks

1. **Trust boundary and backend — complete.** Add storage, constraints, narrow merge
   RPCs, grants/RLS, deletion integration, and positive/negative pgTAP coverage.
2. **Authentication and profile experience — complete.** Pin official Supabase Swift, add
   environment configuration, session/auth/profile services, Apple flow, avatar, and
   focused account UI.
3. **Local/cloud synchronization — complete.** Add account-scoped stores, deterministic merge,
   import confirmation, pending/retry/conflict behavior, lifecycle hooks, and tests.
4. **Integration and finish — complete.** Rebuild/reset/lint/test, exercise local two-account and
   two-client scenarios, perform one final read-only review, adjudicate once, update
   affected docs, and close the plan.

# Risk and verification

High risk: authentication, RLS, immutable provenance, conflict handling, deletion,
and Xcode composition. Required gates are clean Supabase reset/lint/pgTAP, Deno
checks, complete iOS tests and clean simulator build, secret scan, focused two-user
and two-client proof, account deletion proof, and one final integrated review.

# Blockers

None for local implementation. Real Sign in with Apple and provider-token revocation
proof require an Apple team/bundle capability and configured Supabase Apple provider;
they must remain explicitly unproved unless those external prerequisites are present.

# Closure

The milestone closed locally with a clean database rebuild, 146 passing pgTAP tests,
six passing Edge deletion tests, 75 iOS tests with only the credential-gated integration
test skipped in the ordinary run, a separately passing real two-client local Supabase
integration flow, and clean Debug and Release simulator builds. The single integrated
review found conflict-publication, account-activation isolation, deletion-retry, and
local-cleanup issues; all were accepted, fixed, and covered by targeted verification.
Real Apple-provider/device verification and provider-token revocation remain launch
prerequisites because the required external configuration was not available.
