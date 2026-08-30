# Privacy and Data Map

Phase 1 collects no account, device, match, report, or analytics data. Its tutorial
fixtures and guesses remain in memory for the local session; its development answer
and ghost data are bundled resources, not production secrets.

The table below defines requirements for later production phases. A row marked
"later" is not current behavior.

## Production data requirements

| Data | Source | Purpose | Storage owner | Authorized readers | Deletion behavior | Log treatment |
| --- | --- | --- | --- | --- | --- | --- |
| Auth identity (later) | Sign in with Apple and Supabase Auth | Establish an account and authenticated session | Supabase Auth | The account owner and privileged authentication services | Complete in-app account deletion must revoke sessions and remove the identity through a documented production process. Exact provider/audit retention is required before launch. | Never log tokens, authorization codes, private relay email, or credentials. Redact the auth identifier. |
| Profile (later) | Account owner plus server defaults | Represent the player in private rooms | PostgreSQL behind RLS | The owner; participants who share an authorized room or result; privileged support only when required | Delete with the account or anonymize only where a documented retained game record requires it. The choice and retention period are required before launch. | Do not log display names or profile payloads. Redact identifiers. |
| Display name (later) | Account owner | Provide the visible name for invited opponents | Profile record in PostgreSQL | Same readers as the profile | Follows profile deletion/anonymization. | Treat as personal data; do not include it in operational logs. |
| Generated avatar (later) | App/server generation from non-photo style inputs | Give players a recognizable, non-uploaded visual identity | Avatar descriptor in the PostgreSQL profile record | Same readers as the profile | Delete with the profile. | Do not log avatar descriptors or generation inputs. |
| Device registration (later) | App instance and APNs | Route optional notifications and associate a registration with its account | Server-only PostgreSQL table; token is not client-readable after registration | Privileged notification service; the owner may register or remove only their own device | Remove on explicit device removal and account deletion. Stale-token expiry is a required retention decision before APNs launch. | Never log full push tokens or notification credentials; redact device identifiers. |
| Match, room, roster, and result records (later) | Players' authenticated commands plus server transitions | Operate a private synchronous match and show authorized results | PostgreSQL behind RLS | Rostered players according to game phase; privileged server and narrowly authorized support | Account-deletion handling and the match-history retention period are required before production hardening. Retained records must not preserve an unnecessary direct identity link. | Do not log invite secrets, answers, or full snapshots. Redact room, match, and player identifiers. |
| Guesses and feedback (later) | Player submission; authoritative server validation and evaluation | Enforce attempts, reconstruct the player's board, rank the round, and reveal permitted results | PostgreSQL; answers remain in a separate private schema | During play, the submitting player and privileged server; after reveal, rostered players receive only the defined reveal projection | Guess retention and account-deletion treatment are required before production hardening. | Raw guesses, answers, feedback arrays, and keyboard evidence never enter production logs or analytics. |
| Round answers and starting words (later) | Private curated pack and server selection | Run and score an authoritative round | Private PostgreSQL schema and server-only code | Privileged server before reveal; rostered players only through the reveal projection afterward | Word-pack lifecycle follows content versioning; per-round secret retention is a required pre-production decision. | Never log answers or starting words, including on errors. |
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

- Sign in with Apple is a later authentication requirement; it is not implemented in
  Phase 1.
- Report and block controls are later product requirements. There is no persistence
  or moderation system in Phase 1.
- Complete in-app account deletion is required before production release. It must
  revoke sessions, remove profile/avatar/device data, and apply the documented
  deletion or anonymization rule to matches, guesses, reports, and blocks.
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
