Status: Active
Scope: Adversarial review remediation for synchronization, data safety, backend privacy, verification, and delivery controls
Owner: Primary orchestrator
Started: 2026-09-04
Last updated: 2026-09-05

# Goal

Implement and verify the ten adjudicated GridRace findings without broadening the
product or introducing speculative architecture. Bounded implementation workers use
isolated worktrees and independent read-only reviewers challenge each completed
slice. The primary orchestrator owns integration, commits, verification, and review
adjudication. U-01..07 began with Muse Code Spark 1.3; after its provider quota was
exhausted, native Codex worker/reviewer roles took over the remaining work.

# Current snapshot

- Review verdicts: five Accept, four Accept with modification, one Defer.
- GR-01..09 are implemented and locally accepted through U-07.
- Live multiplayer remains paused until CI, integrated review, and closeout gates
  complete; the formal hosted/credential-dependent proofs remain explicit.
- GR-09 is a horizon defect but is included at maintainer direction.
- GR-10 has no tracked workflow; GitHub reports the default branch unprotected.
- The superseded UI plan retains an unperformed formal visual/VoiceOver matrix for
  later revalidation; this plan does not claim or alter that evidence.

# Invariants and implementation policy

- Preserve every product boundary in `AGENTS.md` and the engineering runbook.
- Ponytail full: fix root causes at existing seams, use native/current facilities,
  add no dependency or generalized framework, and leave one focused runnable proof
  for every non-trivial branch or failure mode.
- Durable local/cloud state, RLS, privacy, idempotency, cancellation, and deletion
  safety may not be simplified away.
- Use forward migrations only. Do not rewrite migration history.
- Prior Muse agents committed only their assigned slices. Native Codex workers follow
  the runbook: they edit only assigned paths and never stage, commit, push, or change
  tracking or remote repository settings.
- The orchestrator cherry-picks/integrates commits serially, resolves shared
  contracts, runs canonical gates, and records evidence.

# Work units

| Unit | Findings | Boundary | Dependency | Status |
| --- | --- | --- | --- | --- |
| U-01 Sync convergence | GR-01, GR-02, GR-04 | `DailySync.swift`, `DailyAccountCoordinator.swift`, directly required account callback/store code, `DailySyncTests.swift`, `AccountTests.swift` | — | Accepted |
| U-02 Guest recovery | GR-03 | `DailyClassicModel.swift`, `GridRaceApp.swift`, `DailyClassicModelTests.swift` | — | Accepted |
| U-03 Seed tooling | GR-05 | `check_word_pack.py`, `generate_supabase_seed.py`, `package.json`, seed-focused tests/docs only | — | Accepted |
| U-04 Realtime privacy | GR-06 | `202609040001_match_revision_signal.sql`, a new focused pgTAP file, live privacy/API/architecture docs | — | Accepted |
| U-05 Edge assurance | GR-07 | Edge handler tests and Edge command canon in the runbook | U-03 for final gate set | Accepted |
| U-06 Daily identity | GR-08 | `202609040002_daily_identity_v1.sql`, a new focused pgTAP file, Swift identity validation and focused tests | U-01 integrated first | Accepted |
| U-07 Pagination | GR-09 | `SupabaseDailySyncRemote.swift` and focused remote/sync tests | U-01 integrated first | Accepted |
| U-08 CI | GR-10 | minimal `.github/workflows` and command documentation only | U-03, U-05, U-04, U-06, U-07 | Ready |
| R-01 Integrated review | all | read-only net-diff and contract audit | U-01..08 | Pending |
| C-01 Closeout | all | plan, final gates, commit record | R-01 | Pending |

# Integration order and serialization

1. Integrate U-01, U-02, and U-03 after isolated review.
2. Integrate U-04, then U-05, then U-06 because migrations, database tests,
   authority docs, and the runbook are serialized surfaces.
3. Rebase or freshly dispatch U-07 after U-01 so its tests target the final sync seam.
4. Dispatch U-08 only after every command it invokes is proved locally.
5. Run one fresh integrated review, remediate accepted findings through bounded
   native workers, then execute the complete affected gate set.

# Acceptance and verification

- GR-01: locally durable progress/results converge without pending metadata; ignored
  conflicts do not re-upload.
- GR-02: immutable identity excludes Hard Mode; mismatched-mode attempts never hide
  a longer attempt or silently combine divergent non-empty attempts.
- GR-03: guest reset removes only guest Daily files and preserves every account path.
- GR-04: cancellation/stale responses cannot clear newer pending work or recreate a
  deleted account cache; deletion cannot hang indefinitely on transport cooperation.
- GR-05: word-pack, seed check, seed write, and clean seed diff all pass.
- GR-06: authenticated roster members cannot select or receive exact action timing;
  canonical idempotent mutations increment only a safe revision signal.
- GR-07: all six handlers pass fmt/lint/check/test with success, malformed input,
  auth/build/identifier, RPC mapping, typed database error, and malformed-envelope
  coverage appropriate to each handler.
- GR-08: SQL and Swift reject inconsistent v1 identity tuples and out-of-range days.
- GR-09: a 1,001-result pull returns every result exactly once in stable order.
- GR-10: a minimal workflow runs only proved commands; branch-protection mutation is
  not authorized by this code task and remains an explicit external follow-up.

Canonical proof includes structural Git checks, Python word/seed determinism, rules
and Edge Deno gates, clean Supabase reset/pgTAP/lint, focused and full iOS tests,
Debug build, and denial-path inspection. Rediscover simulator destinations before
Xcode execution. Record unavailable external credentials or hosted behavior exactly.

# Stop conditions

- A second active plan appears.
- A Muse slice touches another slice's assigned paths without orchestrator approval.
- A proposed fix changes game rules, scoring, share semantics, or product scope.
- A migration would require rewriting deployed history or a privacy/RLS denial cannot
  be proved.
- A new dependency, generalized persistence/sync framework, or remote settings change
  becomes necessary.

# Decision log

| ID | Decision | Rationale |
| --- | --- | --- |
| REM-01 | Supersede UI plan without claiming its matrix passed | Preserves evidence honesty while unblocking higher-risk remediation |
| REM-02 | Keep GR-01/02/04 together | They share reconciliation, metadata, cancellation, and deletion lifecycle seams |
| REM-03 | Use forward migrations with preassigned filenames | Prevents worktree collision and preserves deployed history |
| REM-04 | Implement GR-09 now | Maintainer explicitly requested all adjudicated issues despite its horizon priority |
| REM-05 | Do not mutate GitHub branch settings | Repository implementation does not imply authority for external administrative state |
| REM-06 | Replace quota-blocked Muse work with native Codex workers and reviewers | Maintainer directed the takeover; the runbook keeps implementation, review, integration, and commits separated |

# Muse sessions and commit record

| Unit | Session | Worktree/branch | Commit | Status |
| --- | --- | --- | --- | --- |
| U-01 | `01a06dd2-71fe-7992-9759-caba8fee138f` | `.muse/worktrees/20260904-c922` | `f9b31d6` (integrated as `0d16f4b`) | Accepted after three follow-ups; session retained |
| U-02 | `01a06dd2-71e6-7493-8611-32fb5e01de38` | `.muse/worktrees/20260904-8e26` | `5296fdb` (integrated as `85f1484`) | Accepted; session retained |
| U-03 | `01a06dd2-71ef-7140-9c8c-9c2c4d30f70d` | `.muse/worktrees/20260904-113d` | `f54b589` (integrated as `2a49631`) | Accepted; session retained |
| U-04 | `01a06dd2-7227-72e1-886c-a7828f012b2c` | `.muse/worktrees/20260904-972f` | `eddad03` (integrated as `f0b7b5f`) | Accepted after docs follow-up; session retained |
| U-05 | `01a06dd2-7210-76a1-a6b0-32f43e917425` | `.muse/worktrees/20260904-315a` | `6b07074` (integrated as `ddde194`) | Accepted after test-name follow-up; session retained |
| U-06 | `01a06e0e-592c-70e0-9299-54be34b87361` | `.muse/worktrees/20260904-7c02` | `e991dd7` (integrated as `ecf7ae4`) | Accepted; session retained |
| U-07 | Muse `01a06ef9-4ccf-7b43-9425-d07b8b51c5db`; Codex `/root/u07_worker`; review `/root/u07_reviewer` | `.muse/worktrees/20260904-cc66` | `e565580` (integrated as `85764de`) | Accepted after native takeover; reviewer reported no findings |
| U-08 | Pending | Pending | Pending | Not dispatched |

# Verification record

- U-02: reviewed the three-file commit and ran the canonical simulator-focused
  `DailyClassicModelTests`: 11 tests passed, including the new scoped-reset proof.
- U-03: reviewed the two-file commit; `check_word_pack.py`, `check:seed`,
  `generate:seed`, and a clean `supabase/seed.sql` diff all passed.
- U-01: primary review rejected the first commit for non-compiling async XCTest
  autoclosures and a lifecycle check/write race. After same-session remediation and
  a mode-conflict correction, canonical `DailySyncTests` and `AccountTests` pass.
- U-04: clean Supabase reset passed; all four pgTAP files passed (190 assertions);
  local public/private lint completed with only pre-existing historical warnings.
- U-05: reviewed the six-handler test expansion and runbook command; from
  `supabase/functions`, fmt checked 14 files, lint checked 13 files, explicit type
  checking passed, and all 89 Edge tests passed. The root-level Deno invocation is
  intentionally non-canonical because it does not discover the functions import map.
- U-06: reviewed the SQL/Swift identity diff; clean Supabase reset, five pgTAP files
  with 212 assertions, and database lint passed. The focused iOS identity suite passed
  65 tests with one expected local-credentials skip after one unrelated flaky
  cancellation test passed in isolation and on a full rerun.
- U-07: the native worker replaced the interrupted offset patch with strict
  `(puzzle_day, puzzle_id)` keyset pagination and a 1,001-result drift regression.
  The fresh reviewer reported no actionable findings. Primary focused proof passed,
  then all 38 `DailySyncTests` passed with one expected local-credentials skip.

# Next action

Implement U-08 with a bounded native worker after proving its fresh-runner bootstrap
commands, then run one fresh integrated read-only review and the complete canonical
closeout gate set.
