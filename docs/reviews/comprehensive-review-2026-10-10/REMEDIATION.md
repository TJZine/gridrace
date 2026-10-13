# GridRace production remediation — completed checkpoint

**P1–P7 completed 2026-10-11:** implemented, conventionally committed on
`dev/classic-mode`, with scoped software verification and independent review
accepted and no unresolved material findings. This file owns current task status.
The [historical companion](REMEDIATION-HISTORY.md) preserves the full approved plan,
authorizations, failed/prefix diagnosis, repairs, source identities and evidence.
Its proposed/in-progress labels and instructions are superseded and do not activate work.

## Accepted scope and authorization

| Package | Accepted correction / dated finding |
| --- | --- |
| P1 | Durable accepted Daily state across date changes and selected-puzzle reconciliation — F-001/F-002 |
| P2 | Durable captured-account local cleanup, cold retry and independent Daily/Live obligations — F-003 |
| P3 | Throwing filesystem inspection/cleanup; distinguish genuine absence from unavailable storage — F-004 |
| P4 | Secure original deletion authorization and receipt ancestry through refresh, uncertainty and explicit same-A recovery — F-007 |
| P5 | Fail-closed native integration admission and owned loopback fixture/credential isolation — F-006 |
| P6 | Strict required nullable vector keys in Swift, matching TypeScript — F-005 |
| P7 | Readable/scrollable startup recovery at constrained accessibility sizes — F-008 |

Original implementation approval: parent/local chat
`01a12830-6ad0-73f3-b71e-dae7b45a3080`, human turn
`01a12848-98ec-78b2-ba4a-ebeeec0dfcf6`. The human invoked
`orchestrate-implementation-chats` for bounded roles/callbacks and additionally
approved proper local commits on October 11. The controller owned Git; push,
deployment and publication remained outside authorization. The companion retains
all subsequent account-lineage, test-fixture and verification decisions.

## Source-bound evidence and preservation

These are historical observations for the recorded source/targets, not fresh passes
from this documentation edit. Dispatch baseline was
`22ad5cf428d1de0da568809331d776cabbceccc2`. Accepted commits include `3934e71`,
`d30bdd2`, `54a38bd`, `417276f`, `c11137b`, `62fa13a` and `2b63a9e`; the
companion records their scope and closeout. Temporary diagnostic hooks/prefix mode
were retired. Private evidence remains in `.codex/runs/remediation-20261010-p1-p7`.

- Final ordinary native suite: exit 0, 652.534 seconds; 373 cases, 369 passes,
  zero failures, three intentional integration opt-in skips and one expected
  clipped-board negative control. Skipped methods separately passed in the real
  matrix. Frozen 65-file manifest:
  `4b3149529d24f4d6b691cf689dabdd098c5eaca7f25dd1ff0b96c3626f6586c4`.
- Original real matrix: exit 0, 2190.264 seconds; 60 Live plus P4/Daily = 62
  passes, zero failures/skips, all expected role/round/deadline/receipt/recovery/
  survivor scenarios, 19 backend markers and four privileged-pattern absence checks.
  Reviewer examined every xcresult and role set. Stable 34-file feature manifest:
  `a144c46031b602ccffb9d29e4cbfef87b214cb62cb039aef4649f89f23832d3e`;
  historical proof path `/tmp/gridrace-live-integration.k46hch`.
- Other gates: DB 776/776 and lint, Edge 107, TypeScript rules four, native rules
  and lifecycle/storage regressions, clean Debug build, portable corpus/seed
  identity, actual macOS storage fault proof, simulator SE/Pro recovery rendering
  and programmatic scrolling. A separate server-controlled predecessor-expiry
  receipt race passed. Failed and partial runs remain in the companion as diagnosis.
- Final disposable DB: Auth/matches/receipts zero, words 100, active Cron one.
  Twelve owned receipts removed under guards; fresh Edge and 12 fresh containers
  stopped; run-owned simulators removed. Twenty historical simulators and 12
  historical stopped containers preserved. Final 34 executable hashes and 129
  unrelated tracked hashes matched; reviewer-preset and untracked inputs preserved.

Daily/account/Live trust decisions, published content, corpus, Stamped D15/D16,
original retry identities and account isolation remain preserved. No remote action.

## Remaining observations

Protected iOS files on a signed supported device (lock/before-first-unlock/unlock),
unavailable Security storage and real Keychain/Apple-provider lifecycle, including
A→B→A consent/replacement timing, remain unobserved. Simulator Keychain, macOS
fault injection and synthetic/URLProtocol tests do not establish those paths.
Actual touch/VoiceOver scrolling, focus/action activation, Reduce Motion, haptics,
contrast/Bold Text and device/iPad presentation remain human-deferred in
[Stamped S4/A9](../../plans/2026-10-03-stamped-ui-refresh.md).

The driver signs in each process; cold Live recovery proof does not establish
cold persisted Auth restoration. O-001 exact provider/UI replacement reachability
and O-002 stalled non-cooperative SDK transport beyond the advertised timeout with
Home/account exit/cancellation remain unperformed. Hosted pinned-toolchain CI,
signed archive/install, staging/provider launch and distribution remain unobserved.
Local Xcode 27/iOS 26.5 results do not close those gates or corpus release review.

### CI follow-up — 2026-10-13 (UTC)

The earlier local checkpoint and its then-unobserved hosted CI remain historical.
[PR CI 38343347018](https://github.com/TJZine/gridrace/actions/runs/38343347018)
checked merge `c1004308178546d80d126eae2ef6b16343476c0d` for head
`e7db36fb05271a74b5b3246b6286dd03f8554627` and base
`d9bca9b8bde04cc47850db34e3b00a930c57c066`;
[push CI 38343345438](https://github.com/TJZine/gridrace/actions/runs/38343345438)
checked that head directly. Actual checkout and job logs confirm both backend jobs
and native Test/clean Debug builds passed on Xcode 26.6. Both native logs record
379 tests, three explicit integration skips, zero failures and remaining warnings;
the declared clipped-board negative control remains. Backend jobs passed generated
checks, corpus 12 tests with one real-input skip, four shared-rule tests, 131 Edge
tests and 776 database assertions.

The skipped deletion-receipt, Daily two-client sync/deletion and orchestrated Live
paths do not establish full-matrix acceptance or the then-pending PR guidance/skip-guard
repairs. Historical local results remain scoped to their recorded sources. The
[October 12 maintainability checkpoint](../../plans/2026-10-12-maintainability-remediation.md#final-checkpoint--2026-10-12)
records omitted full/Cron/mixed/survivor coverage. Cold persisted Auth, device,
provider/locked-Keychain, signed archive/install, staging, distribution/corpus
clearance and Stamped S4/A9 limits above remain open. This addendum records inspected
CI evidence; it does not claim a new local execution or CI for later fixes.

### PR #2 correction checkpoint — 2026-10-13

The human approved the three adjudicated corrections, planned verification,
independent auth review and proper local commits. Import-sheet copy stays deferred.
Verification below was originally run in an isolated checkout from `e7db36f`.
The corrections were then integrated onto the requested `dev/classic-mode` working
branch above friends-beta checkpoint `55c4856`, preserving those commits and local
edits. Auth is now `7f4a1ad`; harness correction is `e1cb417`, with its test fixture
adapted to the newer cleanup owner. The original verification commits below retain
their source provenance. No publication, hosted action or bot run.

- `605baf0` retains unresolved signed-out guidance without bypassing profile/session
  fences or Daily/Live callbacks. Credential and captured-user Live notices evaluate
  current cleanup eligibility; dismissal/new intent/identity clears presentation.
  Three new subscribed lifecycle cases and two extended coordinator cases cover
  post-intent nil/duplicate-nil delivery, pending dismissal, recovery updates,
  replacement identity, cleanup resolution and successful silence. Existing stale
  restore/profile cases remain. Independent read-only auth review's correctness and
  coverage findings were repaired; targeted rereview reported no material finding.
- `c924295` enforces no-skip inspection status: match rejects, only no-match continues,
  scanner error rejects. Positive/Auth/caller proof markers and owned cleanup remain.
  Existing Python machinery executes the actual checking/EXIT cleanup functions with
  dummy external operations: passed-only, pass-plus-skip, missing-positive and scanner
  error controls pass. Five Python tests, Bash syntax, existing credential-scan controls
  and `git diff --check` passed. These controls are simulated proof, not real clients.
- Fresh ordinary native suite: original exit 0, 624.827 seconds, **382 tests: 378
  ordinary passes, three explicit opt-in integration skips, one expected clipped-board
  negative control, zero unexpected failures**. Clean Debug build passed. Discovered
  iPhone 17 Pro/iOS 26.5; a new owned simulator was used and removed. Local Xcode 27.0
  differs from hosted 26.6. Both commands used the runbook's frozen package flags and
  unique DerivedData; Test additionally used an inventoried copied package cache,
  `-resultBundlePath` and `-parallel-testing-enabled NO` for owned evidence/resources.
  Native source manifest SHA256:
  `e0e3c800fd082a1d346d4f9fd3d1da9816721586124096d2aec5fe4a79f1ecc5`.
- Fresh **full-default integration passed**, original exit 0: **62 native invocations,
  62 passes, zero skips/failures**, all xcresults inspected. The real backend passed
  429 requests/142 snapshots, including exact standings and deletion races. Product
  1/3/5, mixed solved/nonzero, original-deadline Cron with both clients stopped and
  completed/incomplete survivor relaunch all passed; real Realtime fault markers
  and both client-container credential scans passed. No scenario selectors were
  supplied. Controller used the documented libpq PATH, explicit opt-in, a newly
  created inventoried exclusively owned unlinked loopback stack and copied frozen
  eight-package cache. Source/diff identity remained exact through final acceptance.
- Driver cleanup reported `cleanup_failed=0`; Auth/matches/Daily/import rows returned
  to zero, words 100 and active Cron one. Two deletion receipts remain as
  retained contract evidence. The controller then stopped only the owned gateway
  and stack, retaining its volume/proof, and removed only the three new simulators.
  Original container/device identities and states, original checkout files and
  working status were preserved. Private logs, xcresults, inventories and source
  receipts remain in task-owned proof directories; no broader restoration is claimed.

Working-branch integration proof: all eight harness tests and Bash syntax/diff
checks passed. Fresh frozen-resolution native checks on an owned iPhone 17 Pro/iOS
26.5 simulator passed **80 tests, zero skips/failures**: AccountModel 26, Daily/account
coordinator 30, and friends-beta composition 24, including layout captures. The owned
simulator was removed with existing device identities/states unchanged. This focused
combined-source proof does not re-execute the earlier full native/integration matrix.
The temporary checkout was removed; its original commits remain recoverable. Existing
reviewer-preset and research edits remain outside the correction commits.

The dated CI addendum above remains evidence for `e7db36f`, not these new fixes.
Physical/provider/locked-Keychain, persisted-Auth, signed-release/staging,
distribution/corpus and Stamped S4/A9 limits remain open.

Archived optional local-only finding report (original repository-relative path):
`docs/reviews/comprehensive-review-2026-10-10/REPORT.md`. Its exact local copy was
archived outside the project on 2026-10-13 before removal; see the
[archive location and manifest](../../NOW.md#archived-local-only-artifacts).
This checkpoint and its tracked companion are understandable without that report
or private run artifacts.
