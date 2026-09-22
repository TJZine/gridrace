# GridRace Now

Current outcome: Daily Classic remains immediately playable signed out and offline,
and optional accounts now save an owner-private profile, accepted rows, completed
personal results, and derived statistics across devices.

Completed large chunks: production Daily Classic; native Sign in with Apple client
flow and profile experience; account-scoped local storage; explicit guest import;
offline pending/retry and deterministic conflict handling; owner-only sync tables,
RPCs, RLS, and deletion integration. Imported results are personal history only and
cannot enter a verified competitive surface.

Current work: the account and Daily Classic synchronization milestone is complete
locally. The Phase 2 authoritative backend / Phase 3 two-player live-slice plan is
active again; its immediate checkpoint is a current security/RLS review before iOS
live-match implementation begins.

Next large chunk: the first server-backed Blind Race—exactly two authenticated
players and one round, with server-selected answers, server-validated guesses,
clue-free progress, canonical snapshot recovery, and shared reveal. Friends and
broader result sharing remain deferred until this slice is proved.

Genuine blocker: uncommitted dictionary/attribution work overlaps the Xcode project;
preserve and checkpoint or separate it before Phase 3 modifies that project.

Last meaningful verification: fresh clean database reset; 217 pgTAP assertions;
database lint with no errors; 3 shared-rule and 96 Edge tests; previously proved 74
always-on iOS tests plus an opt-in real two-client Supabase Swift integration test;
clean Debug and Release simulator builds; two-user REST/RLS, idempotent
import/conflict, retry-safe account deletion, and account-cache removal proof against
local Supabase; signed-out home visual check at the largest accessibility text size.
