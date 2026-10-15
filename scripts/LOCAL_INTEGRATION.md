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
must keep source stable for the run. `source-manifest.json` records all native, shared,
Edge, migration, landing and integration inputs, including untracked files.

Omitting arguments preserves the full matrix. Help and the scenario inventory need
no opt-in or running stack:

```bash
bash scripts/run_live_match_integration.sh --help
bash scripts/run_live_match_integration.sh --list-scenarios
# Prefix the same controller-owned environment shown above for a real focused run:
bash scripts/run_live_match_integration.sh --scenarios deletion-receipt,daily,product-3
```

Native names are `deletion-receipt`, `daily`, `product-1`, `product-3`, `product-5`,
`mixed-3`, `cron-1`, `cron-3`, `deletion-1`, `deletion-3`,
`friends-1`, `friends-3`, `friends-5`, `snapshot-1`, `friends-signal`, `friends-invitation`, `friends-closure`, `friends-3-race`, and `backend`. Product
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
there are no hidden dependencies on earlier actions. `--scenarios backend` runs without native packages, builds or simulators. Direct
backend selections also use the existing controller-owned
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
new Auth users, matches, non-answer word and disposable simulators. Native proof
uses two containers; `friends-3` additionally owns a third same-account process.
`baseline-inventory.json`, `after-inventory.json` and `cleanup-status.txt` establish
account/match/Daily baseline preservation and feature restoration to default off.

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

Friends scenarios use current build 3, snapshot 3 and recovery format 3 exclusively.
Each 1/3/5 unit completes both predecessor and successor through real native
Auth/Edge/DB clients, retains real Realtime plus snapshot recovery, obtains both
consents without resharing, checks the private lobby before creator Start, replays
lost consent across independent process launches, and verifies answer exclusions
and immutable predecessor gameplay facts. Guest ingress exercises the configured
HTTPS parser, protected navigation restore while signed out, real profile return,
explicit Join, service-update fencing, original-request Retry and the admission
marker's root-clear crash window. These are local owner/composition calls inside
a real native test process; they do not prove installed OS link dispatch or GUI
interaction. Hosted linking, Apple sign-in, protected storage while physically
locked and OS-assisted accessibility remain separate human-deferred acceptance.

`friends-3` waits the original server five-minute rematch opportunity with accepted
clients stopped, then recovers accepted receipts with the service flag off. Its
third process selects another race between the host's real predecessor and
successor snapshots using an explicit owned-container read barrier. The host must
retain its predecessor pointer and require confirmation before pinned Resume;
passive reads must leave the private participation epoch unchanged. Barrier timeout,
missing fault/PASS marker, XCTest skip, failed cleanup or source lock drift fails.

Backend names now use `current-*` for ordinary current-protocol multiround proof;
obsolete builds are rejection tests only. `friends-rematch`, `friends-selection`,
`friends-lifecycle` and `friends-pool` cover simultaneous consent, exact receipts,
private admission, 1/3/5 exclusions, pinned selection/replay, cancel/decline fresh
generations, expiry/deletion, insufficient pool and definitive flag-off closure.
Pool mutation belongs solely to the inventoried exclusive disposable stack and
restores its exact prior activation map in `finally`. Backend expiry fixtures alter
only their owned completion/context timestamps; native Cron/rematch waits retain
original server deadlines. SQL/unit/concurrency proofs complement the native
clients and cannot substitute for their process/lifecycle observations.

`snapshot-1` pauses only the owned stack's finalizer job, starts a real native pair,
stops both clients, and waits the original 180-second deadline. SQL must still
observe an unrevealed round before two native Resume processes request canonical
snapshots and trigger finalization. The exact existing job is reenabled on success
and by cleanup after failure. Cron groups separately prove scheduled finalization.

`friends-signal` isolates rematch-only offer/cancel/fresh-offer/cancel changes with
no gameplay mutation. The native observer opens the production Realtime stream
without opening a session/polling timer, asserts actual signal delivery and real
drop/reorder injection before its canonical snapshot read, then checks closure,
generation and immutable gameplay revision/history. Removing the rematch-specific
production subscription therefore fails instead of silently passing via polling.
The backend `friends-signal` separately observes the exact authenticated new-table
payload (`predecessor_match_id`, `revision`) for both members and outsider silence.

The EXIT cleanup also requires `run_completed=1`, set only after selected checks,
credential scans and the final completion output. Incomplete parsing/nounset runs
fail even when Bash supplies exit status zero to the trap. The hermetic completion
control executes the actual cleanup function with clean completion, missing final
completion and a deliberate nounset error; its SQL/lock stubs are shell controls,
not backend or native acceptance. `cleanup-status.txt` must show both
`cleanup_failed=0` and `run_completed=1` for a successful real run.

Completed account-deletion tombstones created by native fixtures are also owned
cleanup. Before any fixture mutation the controller records a mode-600 private
baseline of exact receipt hashes; teardown records/removes only the new hash delta
under the exclusive runtime lease and verifies every baseline hash is unchanged.
The public before/after inventory includes the receipt count. Private receipt
inventories contain no raw Auth token/email, never go to clients or public output,
and remain with the private proof directory. A preexisting receipt is preserved;
completed fixture receipts are not retained as application data after the run.

`friends-invitation` exercises the actual native DailyAccountCoordinator root with
real Auth/profile/Live services and protected files: signed-out/cold navigation,
profile prerequisite, explicit Join, original unresolved Join retained across an
explicit URL replacement, owner reload and admission acknowledgment preserving newer intent,
real SDK service retirement followed by another authenticated identity preserving
unconfirmed code, explicit root signout clearing that code, and old-user
acknowledgment fencing. The alternate account has a separately host-attested receipt
in the owned container's fixed Alternate directory; both identities must match
actual Auth before their feature operations. This is local composition/transport
proof; the owner reload stays inside one process and does not establish a whole-app
relaunch. OS Universal Link dispatch, Apple provider and physical interaction
remain separate acceptance obligations.

Pair startup launches the admitted guest test first, waits for its actual readiness
in a fresh run/coordination UUID directory, then launches the host. The guest waits
before feature construction for an atomic file containing only the host's real
public code. The controller queries the current app container after Xcode install;
no credential, private answer or database value enters this coordination file.
This keeps cold simulator/XCTest launch delays outside the host's roster wait.
Production request timers and authoritative gameplay/rematch deadlines are unchanged.

The third same-account process likewise reaches admitted readiness before the
host's controlled predecessor read begins; only then does the controller release
its actual new-match selection. Cold XCTest startup cannot consume that read's
90-second barrier. The race role alone uses a bounded 120-second request timer
and 130-second recovery wait; ordinary/production request timers remain 10 seconds,
and the test's 180-second maximum and server deadlines are unchanged.

`friends-closure` independently owns the feature-disable/Decline race and a fresh
one-round predecessor. It is separate from the already-complete `friends-1`
rematch gameplay unit so focused repairs need not replay unrelated successful
consent/gameplay cases. Default full selection includes both; the closure unit
explicitly enables its setup flag and restores off in cleanup.

`friends-3-race` is an explicit focused selection-repair unit. It creates/plays the
same real three-round predecessor, consent, third-account-process selection race
and successor through ordinary current APIs, but makes no opportunity-expiry claim
and does not wait the unrelated five-minute boundary already proved by
`friends-3`. No server timestamp, deadline or acceptance is changed. Default full
selection includes `friends-3` and therefore retains its original expiry wait;
all explicit selections remain focused proof, never a full-matrix PASS.

Snapshot finalization inventories exactly one named Cron job owned by the current
local PostgreSQL role and requires its active baseline. It pauses/restores that
captured job ID through `cron.alter_job`, immediately records restoration ownership,
checks inactive state before waiting, and verifies the same active baseline after
success or failure cleanup. It does not update Cron tables or loosen permissions.

Every successfully installed run-owned simulator is scanned again during cleanup,
after driver processes stop and before container disposal, including failed runs.
The current data container is resolved afresh. The existing scanner requires both
nonempty privileged patterns and treats only ripgrep status1 as absence; any match,
error or unavailable container makes cleanup fail. The private sanitized
`client-credential-scan-status.tsv` records simulator/status pairs without patterns
or contents. Old failed-run containers already deleted have no retrospective scan
claim. Backend-only runs install no containers.

## Friends-beta forward migration and clean-database checks

The staged SQL lives in [`supabase/fixtures`](../supabase/fixtures/), outside
`supabase/tests`: `supabase test db` recursively discovers SQL there and expects
standalone TAP output. The before/after scripts need an ordered upgrade and the
capture script emits JSON. Keep the before script's intentional v1/v2 calls;
running it against an already migrated v3 database is invalid.

Use the repository-pinned CLI (`npm ci` if needed), Docker, Python 3 and `psql`.
Run from the repository root in one Bash session with exclusive ownership of a
fresh, disposable, **unlinked loopback** stack. Inventory existing containers,
volumes and data first. Create a separate stack directory, copy
`supabase/config.toml`, `supabase/migrations`, `supabase/seed.sql`, the current
`supabase/tests` and `supabase/functions` (without local `.env` files) into its
`supabase/` directory, and assign a new `project_id` and
unused ports in the copied configuration. Do not copy `.temp/project-ref`, reuse
retained volumes, or reset the default/shared stack. Set the two variables below
to that inventoried directory and its configured local database port. Keep the
source and copied migration/test inputs stable throughout the run.

```bash
set -euo pipefail
umask 077
: "${GRIDRACE_UPGRADE_STACK_DIR:?Set the exclusively owned disposable stack directory}"
: "${GRIDRACE_UPGRADE_DB_PORT:?Set its configured loopback database port}"
test ! -e "$GRIDRACE_UPGRADE_STACK_DIR/supabase/.temp/project-ref"
upgrade_proof=$(mktemp -d "${TMPDIR:-/tmp}/gridrace-forward-proof.XXXXXX")
git rev-parse HEAD > "$upgrade_proof/source-head.txt"
git diff --binary -- supabase/fixtures scripts/LOCAL_INTEGRATION.md \
  > "$upgrade_proof/source.diff"
shasum -a 256 supabase/fixtures/friends_beta_forward_*.sql \
  "$GRIDRACE_UPGRADE_STACK_DIR"/supabase/migrations/*.sql \
  "$GRIDRACE_UPGRADE_STACK_DIR"/supabase/tests/database/*.sql \
  "$GRIDRACE_UPGRADE_STACK_DIR"/supabase/seed.sql \
  "$GRIDRACE_UPGRADE_STACK_DIR"/supabase/config.toml \
  > "$upgrade_proof/input-sha256.txt"
export PGPASSWORD=postgres
upgrade_psql=(psql -X -h 127.0.0.1 -p "$GRIDRACE_UPGRADE_DB_PORT" \
  -U postgres -d postgres -v ON_ERROR_STOP=1)

# Startup output can contain local credentials; retain it privately.
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" start \
  > "$upgrade_proof/start.log" 2>&1
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" \
  db reset --local --version 202610080002 \
  > "$upgrade_proof/baseline-reset.log" 2>&1

# Require the exact pre-friends-beta baseline and an empty fixture database.
"${upgrade_psql[@]}" <<'SQL'
do $$ begin
  if (select max(version) from supabase_migrations.schema_migrations) <> '202610080002'
    or exists(select 1 from auth.users)
    or exists(select 1 from public.matches)
    or exists(select 1 from private.guess_requests) then
    raise exception 'expected empty owned pre-friends-beta baseline';
  end if;
end $$;
SQL

# Freeze only this disposable stack's finalizer during byte-preservation proof.
# This avoids elapsed gameplay deadlines changing the retained live rows.
"${upgrade_psql[@]}" <<'SQL'
do $$ declare job bigint; begin
  if (select count(*) from cron.job
    where jobname='gridrace-finalize-rounds' and username=current_user and active) <> 1 then
    raise exception 'expected one active owned finalizer';
  end if;
  select jobid into job from cron.job
    where jobname='gridrace-finalize-rounds' and username=current_user;
  perform cron.alter_job(job, active:=false);
end $$;
SQL
"${upgrade_psql[@]}" -f supabase/fixtures/friends_beta_forward_before.sql \
  > "$upgrade_proof/fixture-setup.log" 2>&1
"${upgrade_psql[@]}" -At -f supabase/fixtures/friends_beta_forward_capture.sql \
  > "$upgrade_proof/before.json"
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" migration up --local \
  > "$upgrade_proof/migration-up.log" 2>&1
"${upgrade_psql[@]}" -f supabase/fixtures/friends_beta_forward_after.sql \
  > "$upgrade_proof/fixture-assertions.log" 2>&1
"${upgrade_psql[@]}" -At -f supabase/fixtures/friends_beta_forward_capture.sql \
  > "$upgrade_proof/after.json"
python3 - "$upgrade_proof" <<'PY'
import json, sys
from pathlib import Path
proof = Path(sys.argv[1])
before = json.loads((proof / 'before.json').read_text())
after = json.loads((proof / 'after.json').read_text())
expected = {'matches', 'members', 'rounds', 'players', 'secrets', 'guesses',
            'create_receipts', 'guess_receipts', 'columns'}
if set(before) != expected or any(not before[key] for key in expected):
    raise SystemExit('FAIL: missing retained fixture evidence')
if len(before['matches']) != 7 or before != after:
    raise SystemExit('FAIL: retained fixture facts changed')
print('PASS: seven legacy/v2 matches; gameplay, secrets, receipts and grants preserved')
PY

# Only after forward proof succeeds, discard these owned synthetic fixtures.
# Clean creation also restores the scheduled finalizer's normal active state.
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" db reset --local \
  > "$upgrade_proof/clean-reset.log" 2>&1
"${upgrade_psql[@]}" <<'SQL'
do $$ begin
  if (select count(*) from cron.job
    where jobname='gridrace-finalize-rounds' and username=current_user and active) <> 1 then
    raise exception 'clean reset did not restore the active finalizer';
  end if;
end $$;
SQL
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" test db \
  > "$upgrade_proof/database-tests.log" 2>&1
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" \
  db lint --local --schema public,private,app_rls --level warning --fail-on error \
  > "$upgrade_proof/database-lint.log" 2>&1
npx --no-install supabase --workdir "$GRIDRACE_UPGRADE_STACK_DIR" stop --no-backup \
  > "$upgrade_proof/stop.log" 2>&1
printf 'PASS: forward upgrade, clean database tests and lint; private proof: %s\n' "$upgrade_proof"
```

Every failed command is a failed gate. On failure, preserve the private proof and
inspect the owned stack before any further reset; once diagnosis is complete,
stop **only that disposable project** with the final `stop --no-backup` command.
Its paused finalizer must never be left in a reused stack. Verify that the owned
containers/volumes are removed and the original inventory is unchanged. Captures
include synthetic answers and receipts: share only sanitized summaries, not raw
JSON or startup logs. Passing this procedure proves local forward preservation
and clean creation; it does not establish hosted or independent-native-client
acceptance. At the friends-beta migration, ordinary discovery runs eight standalone
pgTAP suites and 940 assertions. The later private-contract migration adds eighteen
assertions in a ninth suite. Staged forward fixtures stay outside test discovery.

## Private-contract forward preservation

For `202610140001_rematch_and_deletion_contracts.sql`, use the same exclusive,
disposable, unlinked loopback ownership and private-log precautions above, with
baseline `202610130001`. Copy the current migration, tests and fixture inputs into
the owned stack and record their hashes. Require an empty baseline and one active
owned finalizer before creating fixtures. Pause that exact job for the preservation
sequence and restore its prior active state even if a command fails.

Run these files with `psql -X -v ON_ERROR_STOP=1` against that owned database, in
this order: `sql_contracts_forward_before.sql`, then
`sql_contracts_forward_capture.sql`; apply `supabase migration up --local` to the
owned workdir; then run `sql_contracts_forward_after.sql`. These files are under
`supabase/fixtures/`. Unlike the older capture script, this capture stores its
baseline in a private fixture table. The after script compares full rows and
metadata, including helper OIDs and ACLs, replays original requests, compares
again, and only then probes canonical recovery and member-keyed consent
invalidation. Its probes roll back. No timestamps or revisions are excluded from
comparison; only the sanctioned column and helper names are normalized.

Require every command to succeed before discarding the synthetic fixtures with a
clean local reset. Then run the current database tests and lint, the deletion
receipt race, and the friends-beta concurrency fixture. Keep the latter two
serialized on the owned database. The focused `friends-3-race` native scenario
adds independent Auth/Edge/DB/Realtime/client evidence after those checks.
