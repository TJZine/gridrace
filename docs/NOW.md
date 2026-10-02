# GridRace Now

Current outcome: Daily Classic remains immediately playable signed out and offline,
optional accounts synchronize owner-private personal history, and the fixed local
Blind Race slice now runs two authenticated players through create/join, lobby,
countdown, one authoritative round, recovery, and shared reveal.

Completed large chunks: production Daily Classic; native Sign in with Apple client
flow and profile experience; account-scoped local storage; explicit guest import;
owner-only Daily sync and deletion; authoritative live database/Edge commands, RLS,
answer secrecy, idempotency and concurrency proof; native live transport, durable
request recovery, Realtime-triggered canonical refresh, complete fixed-slice UI, and
real two-client local integration. Imported Daily results remain personal history only
and cannot enter a verified competitive surface.

Current checkpoint: the Phase 2/3 local slice is complete, all accepted repairs have
passed verification, and terminal closure review passed on 2026-10-02. The execution
plan is Historical; no implementation package remains open in that local scope.

Phase 4 is active: anytime private two-player Blind Race with 1/3/5 rounds
(default 3), creator-controlled countdowns, nonrepeating private server answers,
canonical round/match standings and cross-round recovery. UI and freeze-after-either-
account-deletion decisions are accepted. Independent plan review was adjudicated
and checkpointed at `3a01d9a` before product writes. P4-B backend/Edge is implemented
and locally verified; Swift contract/session/storage, build-2 composition, UI,
real independent-client product proof and fresh final review remain pending.
Current execution belongs to the
[Active Phase 4 plan](plans/2026-10-02-phase-4-blind-race.md).

Broader 2–8 players, rematch, history, links, moderation, presence, notifications,
hosting and retention remain later work. Preserve the proved components and all
Daily/tutorial/account behavior.

No confirmed local implementation defect remains. Hosted deployment,
Cron, backup/retention proof, hosted CI, Apple provider/distribution credentials,
physical-device accessibility, production word provenance, trusted hosted client-IP
provenance, and the broader MVP remain explicit external or later gates.
No paid commitment is authorized.

Latest backend Phase 4 proof: forward migration preserves legacy lobby/active/
revealed identities, snapshots, successful receipts and grants; clean reset;
739 pgTAP assertions (290 existing plus 449 new); three-schema lint with no new
errors; Edge format/lint/check and 107 tests. Real gateway proof covers 1/3/5
rounds, exact standings/ties, private nonrepeating answers, duplicate/stale command
barriers, deletion boundaries and scheduled finalization without auto advance.
Controller independently repeated database/Edge/gateway gates; details and remaining
client gates live in the Active plan. No Phase 4 iOS proof is claimed yet.

Historical Phase 2/3 verification: clean database reset; 290 pgTAP assertions; three-schema
database lint; Edge format/lint/check and 100 tests; full iOS suite with 183 executed,
181 passed, two expected opt-in integration skips and zero failures; clean Debug build;
focused live-session/presentation proof 50/50 (44 session, six presentation) independently
repeated after the Retry repair; prior account/recovery proof 48/48; and the recorded
real two-client Auth/Edge/RLS/Realtime/Cron/relaunch run with 122 requests and
30 canonical snapshots.
Local Xcode 27.0/iOS 26.5 is a forward-toolchain deviation and does not satisfy hosted,
distribution, or physical-device gates.
