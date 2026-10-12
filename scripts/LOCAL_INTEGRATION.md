# Disposable native integration admission

The controller inventories and exclusively owns an **unlinked loopback** Supabase
stack, its Edge gateway and scheduled finalizer before running the harness. The
harness does not reset, start or stop that stack. A project or branch name does not
establish ownership of existing data.

Run from the repository using a controller-inventoried frozen package cache:

```bash
GRIDRACE_LOCAL_INTEGRATION=1 \
GRIDRACE_INTEGRATION_STACK_DIR=/absolute/path/to/owned-stack \
GRIDRACE_SOURCE_PACKAGES_CACHE=/absolute/path/to/SourcePackages \
bash scripts/run_live_match_integration.sh
```

The driver admits any Git branch or detached HEAD using the same runtime guards.
It records HEAD, branch, tracked-diff digest, driver/selector hashes and selected
scope in `source-and-scope.txt` inside the private proof directory. The controller
must keep source stable for the run and record relevant additional untracked inputs.

Omitting arguments preserves the full matrix. Help and the scenario inventory need
no opt-in or running stack:

```bash
bash scripts/run_live_match_integration.sh --help
bash scripts/run_live_match_integration.sh --list-scenarios
# Prefix the same controller-owned environment shown above for a real focused run:
bash scripts/run_live_match_integration.sh --scenarios deletion-receipt,daily,product-3
```

Native names are `deletion-receipt`, `daily`, `product-1`, `product-3`, `product-5`,
`mixed-3`, `cron-1`, `cron-3`, `deletion-1`, `deletion-3`, and `backend`. Product
counts include every round, failed/tie/history SQL checks, both-client relaunch and
real Realtime fault markers. Mixed includes all three solves and terminal relaunch;
Cron and deletion preserve their original deadline waits and survivor checks.
`backend` includes the complete backend harness. Selecting a native group does not
implicitly include backend, Daily or deletion-receipt proof. Native groups share
build/container setup and the final credential scan, and create only their own
account/match fixtures; the non-answer word is created only for Live groups.
Explicit selections always report focused proof, even if every name is supplied.
Empty, unknown, duplicate names and extra arguments fail before runtime admission
or mutation. Focused PASS cannot establish omitted groups or the full matrix.

The backend driver also accepts `--help`, `--list-scenarios`, and `--scenarios`
with its own bounded names. Each backend action owns all its setup and cleanup;
there are no hidden dependencies on earlier actions. For backend-only work, invoke
it directly to avoid native build/container setup, using the existing controller-owned
local environment and original restricted Deno permissions:

```bash
deno run --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts --scenarios auth-create,rls-realtime
```

The complete name inventory is available without environment/network/run permissions:
`deno run --config supabase/functions/deno.json supabase/tests/integration/live_slice_test.ts --list-scenarios`.
Direct backend runs still require controller inventory/exclusive ownership of the
exact unlinked loopback target; record source and preserve sanitized output yourself.
Selection never shortens backend race deadlines or substitutes SQL simulation for
native original-deadline Cron proof.

Hermetic admission/selector controls (no database or simulators) are:

```bash
python3 scripts/test_live_integration_selection.py
deno test --allow-read supabase/tests/integration/scenario_selection_test.ts
```

The stack directory contains `supabase/config.toml`, no linked project-ref marker,
and may use a unique project ID and API/DB ports. CLI status must report exact HTTP
`127.0.0.1` or `localhost` origins with explicit ports and the local postgres DB.
The existing frozen package-lock hash, simulator/runtime and tool prerequisites
still apply. The script retains its private proof directory and cleans only its
new Auth users, matches, non-answer word and two disposable simulators.

For each invocation the host creates a fresh Auth user through the local admin
API, records the returned UUID in `owned-fixtures.tsv`, and verifies the UUID/email
in local SQL. It writes a nonsecret version-1 JSON receipt into the owned app
container's `Library/Application Support/GridRaceIntegration` directory. Fields are `runID` (UUID), `endpoint` (exact origin),
`unlinked: true`, `createdAt` (Unix seconds), `purpose` (`daily` or `live`),
`userID` (returned Auth UUID), and `email`. This is a host provenance attestation,
not an authentication credential or a claim that clients can inspect project links.
Do not manufacture a receipt for existing or unrelated accounts.

The harness sets `GRIDRACE_FIXTURE_RUN_ID` and `GRIDRACE_FIXTURE_RECEIPT` (the exact `fixture-<run UUID>.json`
basename), ordinary local URL/public key and the purpose's credentials and
scenario inputs. Native admission requires explicit opt-in, strict loopback,
no privileged client variables/key, matching fresh receipt (less than six hours),
and valid Live inputs **before constructing a service**. The test resolves that
basename from its own current Application Support directory, so an Xcode
installation can relocate the physical container without retaining a stale host
path. Receipt delivery never uses expendable `tmp` storage or an arbitrary host
path. Fixed refusal-reason markers identify failed prerequisites without printing
credentials, UUIDs, email, file paths or receipt contents. Actual Auth UUIDs must
match the receipt **before feature mutations**. No opt-in explicitly skips;
unsafe opted-in configuration throws and fails the test.

The full default runs deletion-receipt before Daily. Its separate disposable account exercises real deletion transport:
the backend commits, the client loses that response, an issued Auth refresh is
held, and the original bearer recovers the receipt. The host requires the native
test's proof marker, no skip, and SQL absence of that account. Credentials and
fixture receipts are replaced before the next scenario.

Daily uses its own disposable account and two independent service/local-store
clients, then intentionally deletes that account. The host requires its PASS
marker, no skip, and SQL absence of the UUID. In the full default the existing Live matrix follows on
separate users, retaining the original deadlines, replay, recovery, Realtime,
SQL checks, private credential scan and cleanup. A source/syntax check cannot
replace execution of either positive path or the admission sentinel tests.
