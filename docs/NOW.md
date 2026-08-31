# GridRace Now

Current outcome: Daily Classic remains immediately playable signed out and offline,
and optional accounts now save an owner-private profile, accepted rows, completed
personal results, and derived statistics across devices.

Completed large chunks: production Daily Classic; native Sign in with Apple client
flow and profile experience; account-scoped local storage; explicit guest import;
offline pending/retry and deterministic conflict handling; owner-only sync tables,
RPCs, RLS, and deletion integration. Imported results are personal history only and
cannot enter a verified competitive surface.

Current work: account and Daily Classic synchronization milestone complete locally.
Real Apple-provider/device proof remains external configuration work.

Next large chunk: friends and privacy-controlled Daily Classic result sharing, while
keeping imported personal history separate from future server-verified competition.

Genuine blockers: none.

Last meaningful verification: clean database reset; 146 pgTAP tests; focused database
lint; 74 always-on iOS tests plus an opt-in real two-client Supabase Swift integration
test; clean Debug and Release simulator builds; two-user REST/RLS, idempotent
import/conflict, retry-safe account deletion, and account-cache removal proof against
local Supabase; signed-out home visual check at the largest accessibility text size.
