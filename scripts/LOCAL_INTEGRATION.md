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

Before Daily, a separate disposable account exercises real deletion transport:
the backend commits, the client loses that response, an issued Auth refresh is
held, and the original bearer recovers the receipt. The host requires the native
test's proof marker, no skip, and SQL absence of that account. Credentials and
fixture receipts are replaced before the next scenario.

Daily uses its own disposable account and two independent service/local-store
clients, then intentionally deletes that account. The host requires its PASS
marker, no skip, and SQL absence of the UUID. The existing Live matrix follows on
separate users, retaining the original deadlines, replay, recovery, Realtime,
SQL checks, private credential scan and cleanup. A source/syntax check cannot
replace execution of either positive path or the admission sentinel tests.
