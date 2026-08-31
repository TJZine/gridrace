# Privacy and Data Map

Phase 1 collects no account, device, match, report, or analytics data. Its tutorial
fixtures and guesses remain in memory for the local session; its development answer
and ghost data are bundled resources, not production secrets.

Phase 2 introduces local-only auth/profile/backend data, and Phase 3 introduces the
local two-player live-match data described below. Device, report, block, analytics,
remote deployment, and broader history remain later work.

## Production data requirements

| Data | Source | Purpose | Storage owner | Authorized readers | Deletion behavior | Log treatment |
| --- | --- | --- | --- | --- | --- | --- |
| Auth identity (Phase 2 local) | Sign in with Apple and Supabase Auth; debug local credentials only in Debug | Establish an account and authenticated session | Supabase Auth | The account owner and privileged authentication services | In-app deletion hard-deletes the local Auth identity. Real Apple provider revocation remains required before production launch. | Never log tokens, authorization codes, private relay email, or credentials. Redact the auth identifier. |
| Profile (Phase 2 local) | Account owner plus server defaults | Represent the player in private rooms | PostgreSQL behind RLS | Owner fields directly; presentation snapshots for participants in an authorized match | Delete the profile. Retained survivor results use detached member snapshots, never the profile. | Do not log display names or profile payloads. Redact identifiers. |
| Display name (Phase 2 local) | Account owner | Provide the visible name for invited opponents | Profile record and roster snapshot | Same readers as the profile/snapshot | Delete the profile; replace retained roster presentation with `Deleted Player`. | Treat as personal data; do not include it in operational logs. |
| Generated avatar (Phase 2 local) | Server generation plus owner choice from non-photo descriptors | Give players a recognizable, non-uploaded visual identity | Profile record and roster snapshot | Same readers as the profile/snapshot | Delete the profile; replace retained roster presentation with a neutral descriptor. | Do not log avatar descriptors or generation inputs. |
| Device registration (later) | App instance and APNs | Route optional notifications and associate a registration with its account | Server-only PostgreSQL table; token is not client-readable after registration | Privileged notification service; the owner may register or remove only their own device | Remove on explicit device removal and account deletion. Stale-token expiry is a required retention decision before APNs launch. | Never log full push tokens or notification credentials; redact device identifiers. |
| Match, room, roster, and result records (Phase 3 local) | Players' authenticated commands plus server transitions | Operate the private two-player race and show authorized results | PostgreSQL behind RLS | Rostered players according to game phase; privileged server | Lobby rows are removed when deletion leaves no valid lobby. Retained results detach the auth link and use `Deleted Player`; broader production retention remains undecided. | Do not log invite secrets, answers, or full snapshots. Redact room, match, and player identifiers. |
| Guesses and feedback (Phase 3 local) | Player submission; authoritative server validation and evaluation | Enforce attempts, reconstruct the player's board, rank the round, and reveal permitted results | PostgreSQL; answers remain in a separate private schema | During play, submitting player and privileged server; after reveal, rostered players through the defined snapshot/direct policy | Retain only when needed for the survivor's canonical reveal, under an irreversibly anonymized member; broader retention remains undecided. | Raw guesses, answers, feedback arrays, and keyboard evidence never enter production logs or analytics. |
| Round answers (Phase 2/3 local) | Canonical development pack and server selection | Run and score an authoritative round | Private PostgreSQL schema until atomic reveal | Privileged server before reveal; rostered players only through reveal afterward | Private secret follows the match lifecycle; broader production retention remains undecided. | Never log answers or starting words, including on errors. |
| Reports (later requirement) | Authenticated reporting player using the product's defined report fields | Support safety review and enforcement | Restricted PostgreSQL records | Authorized moderation operators and privileged enforcement code | Moderation retention, deletion/anonymization, and any legal preservation need require an explicit policy before report launch. Account deletion must follow that policy rather than silently discarding or retaining reports. | Do not log report content. Redact involved account and match identifiers. |
| Blocks (later requirement) | Authenticated blocking player | Prevent disallowed contact or room participation | PostgreSQL behind owner-scoped RLS | Blocking player and privileged enforcement code; the blocked player does not receive the relationship record | Remove on unblock. Account-deletion handling and any short enforcement retention require a decision before launch. | Do not log block relationships; redact identifiers in enforcement diagnostics. |

## Collection limits

GridRace does not upload contacts or photos and does not provide chat. Other players
never see an email address, including an Apple private relay address. A generated
avatar is not derived from a contact list or uploaded photo.

There is no Phase 1 analytics or advertising collection. Any future telemetry needs
a named purpose, minimum fields, authorized readers, retention, deletion behavior,
and log-redaction review before implementation. Production logs are diagnostic data,
not a shadow event store.

Private invite links and six-character room codes grant no data access by themselves.
The backend still authenticates and authorizes the caller, enforces room phase and
roster membership, and prevents late joining after countdown begins.

## Required later product controls

- Sign in with Apple is the Phase 2 production boundary; a real provider exchange
  remains external proof until bundle/team/provider credentials exist. Debug local
  credentials compile out of Release.
- Report and block controls are later product requirements. There is no persistence
  or moderation system in Phase 1.
- Complete in-app account deletion for implemented Phase 2/3 data removes the local
  Auth identity and profile, removes invalid lobbies, and irreversibly anonymizes
  only survivor-required results. Later device/report/block data must extend this
  rule before those surfaces launch.
- Deletion operations must be authenticated, idempotent where retried, and safe under
  partial failure. Completion is not claimed until owned data and credentials have
  reached their documented terminal state.

## Decisions required before production hardening

No retention period is selected by this document. Before the relevant production
surface launches, the owner must approve and document periods and deletion handling
for authentication/audit records, match history, guesses, per-round secrets, device
registrations, moderation records, blocks, operational logs, and any telemetry. The
decision must account for product need, safety, legal obligations, backups, and user
disclosure without expanding collection by default.
