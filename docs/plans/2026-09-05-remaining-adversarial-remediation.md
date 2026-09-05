Status: Active
Scope: Remediate the remaining validated Daily persistence, synchronization, Edge request, and hosted CI findings
Owner: Primary orchestrator
Started: 2026-09-05
Last updated: 2026-09-05

# Goal

Fix the five validated adversarial findings and the adjacent GitHub Actions runtime
warning without changing branch protection, product scope, or established security
and synchronization boundaries.

# Current snapshot

- Reviewed source is `912827c` on `dev/classic-mode`.
- Hosted run 33959896444 passed `ios` and failed `backend` during generated-data
  verification; later backend gates were skipped.
- No other plan is active and `.codex/` is pre-existing generated review context.

# Invariants and decisions

- Completed Daily puzzles and result history remain immutable. A cloud active attempt
  cannot reopen or delete a local completion.
- Failed account-cache activation must never reveal guest data or accept gameplay
  into non-durable storage. Retry and sign-out remain available.
- Guest import validates terminal recovery separately from cloud active progress;
  terminal state is never weakened into active state.
- The Edge request limit is 2,048 UTF-8 bytes and must stop reading once exceeded.
- Portable CI validates checked-in artifacts and deterministic seeds. Full word-pack
  regeneration continues to require the exact pinned source corpus.
- Use only standard Swift, Web/Deno, Python, and GitHub Actions facilities; add no
  dependency or generalized persistence/sync framework.
- Do not mutate GitHub branch protection or other repository administration.

# Work units

| Unit | Scope | Primary files | Status |
| --- | --- | --- | --- |
| R-01 Daily durability | Account activation availability and immutable completion | `DailyAccountCoordinator.swift`, Daily/account views, focused tests | Complete |
| R-02 Guest recovery | Normalize terminal guest progress/results | `DailySync.swift`, `DailySyncTests.swift` | Complete |
| R-03 Edge boundary | Bounded UTF-8 byte reader and focused tests | `_shared/command.ts`, shared Edge tests | Complete |
| R-04 Portable CI | Split checked-in validation from source regeneration; update action runtimes | word scripts, workflow, runbook | Complete |
| R-05 Integration | Full affected gates, adversarial net-diff review, commits, closeout | all task-owned files | In progress |

# Finding ledger

| ID | Severity | Evidence | Disposition | Action | Verification |
| --- | --- | --- | --- | --- | --- |
| AR-01 | High | Failed activation leaves interactive model on no-op store | Accepted | Expose storage availability and gate Daily play | Coordinator and view-state tests; full iOS suite/build |
| AR-02 | High | `.useCloud` removes terminal history despite immutable contract | Modified | Make completed local state dominate cloud active progress | Sync/relaunch/statistics/conflict tests |
| AR-03 | Medium-high | Guest terminal progress fails active-only validation | Accepted | Normalize terminal progress into history before reconcile | Solved/failed, matching/missing history, repeated import tests |
| AR-04 | Medium-high | Multibyte body bypasses limit; stream is fully buffered | Accepted | Read and cancel body by bytes | Exact/over/multibyte/misleading-length/early-stop tests; Edge gates |
| AR-05 | High | Ubuntu CI requires macOS `/usr/share/dict/web2` | Accepted | Add portable checked-in mode and preserve explicit source gate | Python/seed gates and hosted workflow run |
| AR-06 | Low | Official actions run on deprecated forced Node runtime | Accepted follow-up | Pin current official runtime-compatible releases | Official release/SHA inspection and hosted workflow run |
| AR-07 | Medium-low | Branch is unprotected | Excluded by maintainer | No change | None |

# Risk and verification

This is high-risk work because it changes persistence failure behavior, sync state
transitions, a shared untrusted-input boundary, and CI. Required proof:

- focused account, model, and sync tests plus full iOS test and clean Debug build;
- Edge fmt, lint, explicit type-check, and complete Edge tests;
- portable and full local word-pack checks plus deterministic seed check;
- workflow syntax/action provenance inspection and a hosted run after pushing;
- structural Git checks, complete task-owned diff review, and fresh adversarial
  inspection of durability, convergence, byte counting, and verification gaps.

# Stop conditions

- A second active plan appears or unrelated tracked changes overlap task files.
- A fix would require weakening completion immutability, guest/account isolation,
  validation, accessibility, RLS, idempotency, or provenance.
- A new dependency, generalized framework, corpus substitution, or remote
  administrative mutation becomes necessary.

# Commit record

Pending.

# Verification record

- `python3 scripts/check_word_pack.py --checked-in-only`: passed.
- `python3 scripts/check_word_pack.py`: passed against the checksum-pinned source.
- `npm run check:seed`: passed.
- Shared TypeScript fmt, lint, check, and 3 tests: passed.
- Edge fmt, lint, explicit check, and 96 tests: passed.
- Clean local Supabase reset, 217 pgTAP assertions, and error-level database lint:
  passed. Existing extra-warning diagnostics remain outside this change.
- Full iOS suite: 115 tests passed with the credential-gated local Supabase test
  skipped; the changed guest relaunch tests then passed again after final tightening.
- Clean iOS Debug build: passed.
- Workflow YAML parsing and official action release/SHA inspection: passed.
- Hosted workflow execution: pending the implementation push.

# Closeout checklist

- [ ] All accepted findings implemented with focused regression coverage.
- [ ] Affected canonical gates and clean build pass.
- [ ] Hosted `ios` and `backend` jobs pass through every intended step.
- [ ] Full task-owned diff receives a fresh critical review.
- [ ] Logical conventional commits are created and recorded.
- [ ] Plan is marked Historical in the closeout commit.
