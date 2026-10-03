#!/usr/bin/env bash
set -euo pipefail

# P4-V real two-process proof. Controller must inventory the unlinked loopback
# stack, apply existing migrations, and own a running Edge gateway before use.
# No reset/start/stop of the shared backend. Each run creates two disposable
# simulators and unique Auth/match/non-answer-word fixtures; cleanup owns only those.
# Logs and xcresults remain in the printed /tmp proof directory after cleanup.
# Requires macOS/Xcode, iOS 26.5, cached frozen SourcePackages, Deno, npm and psql.
# Product 1/3/5 rounds relaunch both clients at every reveal. Cron 1/3 waits the
# original 180-second deadlines with both clients stopped. Deletion restores the
# surviving container at nonfinal and final boundaries. Budget roughly 20 minutes.
if [[ ${1:-} == "--help" ]]; then
  sed -n '4,12p' "$0"
  exit 0
fi
[[ ${GRIDRACE_LOCAL_INTEGRATION:-} == 1 ]] || {
  echo "UNAVAILABLE: set GRIDRACE_LOCAL_INTEGRATION=1 after controller inventory" >&2; exit 2;
}
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
source "$repo_root/scripts/scan_client_credentials.sh"
[[ $(git branch --show-current) == dev/classic-mode ]] || exit 2
[[ $(sed -n 's/^project_id = "\([^"]*\)"/\1/p' supabase/config.toml) == gridrace ]] || exit 2
[[ ! -e supabase/.temp/project-ref && ! -e .supabase/project-ref ]] || {
  echo "REFUSED: linked Supabase project" >&2; exit 2;
}
work_dir=$(mktemp -d /tmp/gridrace-live-integration.XXXXXX)
chmod 700 "$work_dir"
: > "$work_dir/owned-fixtures.tsv"
chmod 600 "$work_dir/owned-fixtures.tsv"
echo "PROOF_DIRECTORY $work_dir"
derived_data="$work_dir/DerivedData"
package_cache=/tmp/gridrace-phase4-client-derived-test/SourcePackages
lock=ios/GridRace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
lock_hash=d6b069e121418166c3b844eb1c1b66fc2f0ccb715f0b9808405a14a9a68d0691
check_lock() { [[ $(shasum -a 256 "$lock" | awk '{print $1}') == "$lock_hash" ]]; }
check_lock
[[ -d "$package_cache" ]] || { echo "UNAVAILABLE: retained SourcePackages cache" >&2; exit 2; }
# Keep privileged environment private to this orchestrator, never exported to Xcode.
eval "$(npx --no-install supabase status -o env 2>/dev/null)"
export -n API_URL ANON_KEY SERVICE_ROLE_KEY DB_URL JWT_SECRET 2>/dev/null || true
[[ $API_URL == http://127.0.0.1:54321 || $API_URL == http://localhost:54321 ]] || exit 2
[[ $DB_URL == postgresql://postgres:postgres@127.0.0.1:54322/postgres || \
   $DB_URL == postgresql://postgres:postgres@localhost:54322/postgres ]] || exit 2
sql_scalar() {
  PGPASSWORD=postgres /opt/homebrew/opt/libpq/bin/psql --host 127.0.0.1 --port 54322 \
    --username postgres --dbname postgres -XAtq -v ON_ERROR_STOP=1 -c "$1" | tail -n 1
}
host_pid=""; guest_pid=""; failed_guess=""
declare -a created_users=() created_matches=() proof_simulators=()
cleanup() {
  local original_status=$? cleanup_failed=0
  set +e
  for pid in "$host_pid" "$guest_pid"; do
    [[ -z "$pid" ]] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  done
  # Also capture a Create whose response/process failed before normal registration.
  for user_id in ${created_users[@]+"${created_users[@]}"}; do
    sql_scalar "delete from public.matches where id in (select match_id from public.match_members where auth_user_id='$user_id')" >/dev/null || cleanup_failed=1
  done
  for match_id in ${created_matches[@]+"${created_matches[@]}"}; do
    sql_scalar "delete from public.matches where id='$match_id'" >/dev/null || cleanup_failed=1
  done
  for user_id in ${created_users[@]+"${created_users[@]}"}; do
    sql_scalar "delete from auth.users where id='$user_id'" >/dev/null || cleanup_failed=1
  done
  if [[ -n "$failed_guess" ]]; then
    sql_scalar "delete from private.words where word='$failed_guess' and not is_answer" >/dev/null || cleanup_failed=1
  fi
  for simulator in ${proof_simulators[@]+"${proof_simulators[@]}"}; do
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || cleanup_failed=1
  done
  check_lock || { echo "FAIL: protected package lock changed" >&2; cleanup_failed=1; }
  echo "CLEANUP owned fixtures/containers only; proof retained at $work_dir"
  if [[ $cleanup_failed != 0 ]]; then
    echo "FAIL: owned cleanup incomplete; controller must inspect retained proof" >&2
    original_status=1
  fi
  printf 'cleanup_failed=%s\n' "$cleanup_failed" > "$work_dir/cleanup-status.txt"
  trap - EXIT
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
status=$(curl --silent --output /dev/null --write-out '%{http_code}' --request POST \
  --header "apikey: $ANON_KEY" --header "Authorization: Bearer $ANON_KEY" \
  --header 'Content-Type: application/json' --data '{}' "$API_URL/functions/v1/create-match")
[[ $status == 400 ]] || { echo "UNAVAILABLE: controller-owned Edge gateway" >&2; exit 2; }
# Do not replace or delete a preexisting non-answer fixture.
for _ in {1..20}; do
  candidate=$(python3 -c 'import secrets,string; print("z"+"".join(secrets.choice(string.ascii_lowercase) for _ in range(4)))')
  failed_guess=$(sql_scalar "insert into private.words(word,is_accepted,is_answer,is_active,pack_version) values('$candidate',true,false,true,1) on conflict do nothing returning word")
  [[ -n "$failed_guess" ]] && break
done
[[ -n "$failed_guess" ]] || { echo "UNAVAILABLE: unique non-answer fixture" >&2; exit 2; }
# Record a digest for controller cleanup inventory without storing the guess word.
printf 'non_answer_word_sha256\t%s\n' "$(printf '%s' "$failed_guess" | shasum -a 256 | awk '{print $1}')" >> "$work_dir/owned-fixtures.tsv"
run_tag=$(uuidgen)
for role in host guest; do
  simulator=$(xcrun simctl create "GridRace-proof-$run_tag-$role" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
  proof_simulators+=("$simulator")
  printf 'simulator\t%s\n' "$simulator" >> "$work_dir/owned-fixtures.tsv"
  xcrun simctl boot "$simulator"
  xcrun simctl bootstatus "$simulator" -b >/dev/null
done
host_simulator=${proof_simulators[0]}; guest_simulator=${proof_simulators[1]}
xcode_flags=(-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates)
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace "${xcode_flags[@]}" \
  -clonedSourcePackagesDirPath "$package_cache" -destination "platform=iOS Simulator,id=$host_simulator" \
  -derivedDataPath "$derived_data" build-for-testing >"$work_dir/build-for-testing.log" 2>&1
check_lock
create_user() {
  local suffix response
  suffix=$(uuidgen | tr '[:upper:]' '[:lower:]')
  fixture_email="proof-$suffix@example.test"; fixture_password="GridRace-${suffix//-/}"
  response=$(curl --fail --silent --show-error --request POST \
    --header "apikey: $SERVICE_ROLE_KEY" --header "Authorization: Bearer $SERVICE_ROLE_KEY" \
    --header 'Content-Type: application/json' \
    --data "{\"email\":\"$fixture_email\",\"password\":\"$fixture_password\",\"email_confirm\":true}" \
    "$API_URL/auth/v1/admin/users")
  fixture_user_id=$(plutil -extract id raw -o - - <<<"$response")
  [[ $fixture_user_id =~ ^[0-9a-f-]{36}$ ]] || return 1
  created_users+=("$fixture_user_id")
  printf 'auth_user\t%s\n' "$fixture_user_id" >> "$work_dir/owned-fixtures.tsv"
}
run_client() {
  local simulator=$1 role=$2 scenario=$3 email=$4 password=$5 log=$6 code=$7 match_id=$8 count=$9 target=${10}
  # These launchd environments belong exclusively to newly created simulators.
  local name value client_status client_pid test_guess=${11:-$failed_guess}
  while IFS='=' read -r name value; do
    xcrun simctl spawn "$simulator" launchctl setenv "$name" "$value"
  done <<ENV
GRIDRACE_LOCAL_INTEGRATION=1
GRIDRACE_LIVE_ROLE=$role
GRIDRACE_LIVE_SCENARIO=$scenario
GRIDRACE_LIVE_EMAIL=$email
GRIDRACE_LIVE_PASSWORD=$password
GRIDRACE_LIVE_JOIN_CODE=$code
GRIDRACE_LIVE_MATCH_ID=$match_id
GRIDRACE_LIVE_ROUND_COUNT=$count
GRIDRACE_LIVE_ROUND_NUMBER=$target
GRIDRACE_LIVE_DISABLE_REALTIME=$([[ $simulator == "$guest_simulator" ]] && echo 1 || echo 0)
GRIDRACE_LIVE_FAILED_GUESS=$failed_guess
GRIDRACE_LIVE_TEST_GUESS=$test_guess
GRIDRACE_LOCAL_SUPABASE_URL=$API_URL
GRIDRACE_LOCAL_SUPABASE_KEY=$ANON_KEY
ENV
  set +e
  env -u SERVICE_ROLE_KEY -u SUPABASE_SERVICE_ROLE_KEY -u SUPABASE_SECRET_KEY -u DB_URL -u JWT_SECRET \
    xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace "${xcode_flags[@]}" \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived_data" \
    -resultBundlePath "${log%.log}.xcresult" test-without-building \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 150 \
    -maximum-test-execution-time-allowance 180 -collect-test-diagnostics never \
    -only-testing:GridRaceTests/LiveMatchIntegrationTests/testTwoClientProcess >"$log" 2>&1 &
  client_pid=$!
  trap 'kill "$client_pid" 2>/dev/null; wait "$client_pid" 2>/dev/null; exit 130' INT TERM
  wait "$client_pid"
  client_status=$?
  trap - INT TERM
  if [[ $client_status == 0 ]] && {
    ! rg -q 'PASS live client' "$log" || rg -q 'testTwoClientProcess.*skipped' "$log";
  }; then
    echo "FAIL: real client proof absent or skipped" >&2
    client_status=1
  fi
  # XCTest's host application must also be stopped before the no-client Cron wait.
  xcrun simctl terminate "$simulator" com.example.GridRace >/dev/null 2>&1
  check_lock || client_status=1
  set -e
  return "$client_status"
}
wait_clients() {
  local host_status guest_status
  set +e
  wait "$host_pid"; host_status=$?
  wait "$guest_pid"; guest_status=$?
  set -e
  host_pid=""; guest_pid=""
  [[ $host_status == 0 && $guest_status == 0 ]]
}
wait_sql() {
  local query=$1 expected=$2 timeout=${3:-90} result
  for ((attempt=0; attempt<timeout*10; attempt++)); do
    result=$(sql_scalar "$query")
    [[ $result == "$expected" ]] && return
    sleep 0.1
  done
  echo "FAIL: owned fixture SQL wait timed out" >&2; return 1
}
launch_round() {
  local host_role=$1 guest_role=$2 scenario=$3 count=$4 target=$5
  run_client "$host_simulator" "$host_role" "$scenario" "$host_email" "$host_password" \
    "$work_dir/$scenario-$count-$target-$host_role-host.log" "" "$match_id" "$count" "$target" & host_pid=$!
  run_client "$guest_simulator" "$guest_role" "$scenario" "$guest_email" "$guest_password" \
    "$work_dir/$scenario-$count-$target-$guest_role-guest.log" "$join_code" "$match_id" "$count" "$target" & guest_pid=$!
  wait_clients
}
start_pair() {
  local scenario=$1 count=$2
  create_user; host_id=$fixture_user_id; host_email=$fixture_email; host_password=$fixture_password
  create_user; guest_id=$fixture_user_id; guest_email=$fixture_email; guest_password=$fixture_password
  match_id=""; join_code=""
  run_client "$host_simulator" host "$scenario" "$host_email" "$host_password" \
    "$work_dir/$scenario-$count-1-host.log" "" "" "$count" 1 & host_pid=$!
  for _ in {1..600}; do
    match_id=$(sql_scalar "select match_id from public.match_members where auth_user_id='$host_id' order by joined_at desc limit 1")
    [[ -n "$match_id" ]] && break
    sleep 0.1
  done
  [[ $match_id =~ ^[0-9a-f-]{36}$ ]] || { echo "FAIL: no owned Create" >&2; return 1; }
  created_matches+=("$match_id")
  printf 'match\t%s\n' "$match_id" >> "$work_dir/owned-fixtures.tsv"
  join_code=$(sql_scalar "select join_code from public.matches where id='$match_id'")
  run_client "$guest_simulator" guest "$scenario" "$guest_email" "$guest_password" \
    "$work_dir/$scenario-$count-1-guest.log" "$join_code" "" "$count" 1 & guest_pid=$!
  wait_clients
}
assert_sql_reveal() {
  local target=$1 count=$2 expected=in_progress
  [[ $target == "$count" ]] && expected=completed
  [[ $(sql_scalar "select concat(status,'|',current_round,'|',round_count) from public.matches where id='$match_id'") == "$expected|$target|$count" ]]
  [[ $(sql_scalar "select count(*) from public.rounds where match_id='$match_id' and state='revealed'") == "$target" ]]
  [[ $(sql_scalar "select count(distinct answer) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='$match_id'") == "$target" ]]
}
for count in 1 3 5; do
  start_pair product "$count"
  for ((target=1;target<=count;target++)); do
    [[ $target == 1 ]] || launch_round advance-host advance-guest product "$count" "$target"
    assert_sql_reveal "$target" "$count"
    [[ $(sql_scalar "select count(*) from public.player_rounds p join public.rounds r on r.id=p.round_id where r.match_id='$match_id' and p.state='failed' and p.accepted_guess_count=6 and p.efficiency_points=0 and p.placement=1") == "$((target*2))" ]]
    echo "PASS two-process product $count round $target SQL failed/tie/history"
  done
  launch_round resume resume product "$count" "$count"
done
# Controlled privileged fixture knowledge becomes a test input only. Neither
# authenticated client reads secrets or gets a privileged credential.
start_pair mixed 3
for target in 1 2 3; do
  [[ $target == 1 ]] || launch_round advance-host advance-guest mixed 3 "$target"
  test_word=$(sql_scalar "select answer from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='$match_id' and r.round_number=$target")
  [[ $test_word =~ ^[a-z]{5}$ ]]
  run_client "$host_simulator" solve-host mixed "$host_email" "$host_password" \
    "$work_dir/mixed-3-$target-solve-host.log" "" "$match_id" 3 "$target" "$test_word" & host_pid=$!
  run_client "$guest_simulator" solve-guest mixed "$guest_email" "$guest_password" \
    "$work_dir/mixed-3-$target-solve-guest.log" "" "$match_id" 3 "$target" & guest_pid=$!
  wait_clients
  unset test_word
  assert_sql_reveal "$target" 3
  [[ $(sql_scalar "select count(*) from public.player_rounds p join public.rounds r on r.id=p.round_id where r.match_id='$match_id' and p.state='solved' and p.accepted_guess_count=1 and p.efficiency_points=6 and p.placement=1") == "$target" ]]
  echo "PASS two-process mixed solved/nonzero count 3 round $target"
done
launch_round resume resume mixed 3 3
# Each test process exits at playing; only SQL observations occur until Cron reveals.
# No timestamp mutation, snapshot request or manual finalize is used during the wait.
for count in 1 3; do
  start_pair cron "$count"
  for ((target=1;target<=count;target++)); do
    [[ $target == 1 ]] || launch_round advance-host advance-guest cron "$count" "$target"
    prior_run=$(sql_scalar "select coalesce(max(runid),0) from cron.job_run_details where jobid=(select jobid from cron.job where jobname='gridrace-finalize-rounds')")
    wait_sql "select state from public.rounds where match_id='$match_id' and round_number=$target" revealed 250
    [[ $(sql_scalar "select count(*) from cron.job_run_details where jobid=(select jobid from cron.job where jobname='gridrace-finalize-rounds') and runid>$prior_run and status='succeeded'") != 0 ]]
    assert_sql_reveal "$target" "$count"
    launch_round resume resume cron "$count" "$target"
    echo "PASS original deadline/Cron with both clients stopped count $count round $target"
  done
done
# Delete a stopped guest through the existing privileged deletion preparation, then
# remove only that owned Auth identity. Real API deletion/concurrency uses B below.
for count in 1 3; do
  start_pair deletion "$count"
  sql_scalar "select public.delete_account('$guest_id',2)" >/dev/null
  curl --fail --silent --show-error --request DELETE --header "apikey: $SERVICE_ROLE_KEY" \
    --header "Authorization: Bearer $SERVICE_ROLE_KEY" "$API_URL/auth/v1/admin/users/$guest_id" >/dev/null
  wait_sql "select state from public.rounds where match_id='$match_id' and round_number=1" revealed 250
  run_client "$host_simulator" survivor deletion "$host_email" "$host_password" \
    "$work_dir/deletion-$count-survivor.log" "" "$match_id" "$count" 1 & host_pid=$!
  wait "$host_pid"; host_pid=""
  expected=incomplete; [[ $count == 1 ]] && expected=completed
  [[ $(sql_scalar "select status from public.matches where id='$match_id'") == "$expected" ]]
  echo "PASS survivor relaunch $expected after guest deletion"
done
rg -q 'INJECTION dropped real Realtime signal' "$work_dir"/product-*-host.log
rg -q 'INJECTION duplicated and reordered real Realtime signals' "$work_dir"/product-*-host.log
GRIDRACE_LOCAL_INTEGRATION=1 API_URL="$API_URL" ANON_KEY="$ANON_KEY" \
  SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" DB_URL="$DB_URL" deno run \
  --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts >"$work_dir/backend.log" 2>&1
for simulator in "$host_simulator" "$guest_simulator"; do
  container=$(xcrun simctl get_app_container "$simulator" com.example.GridRace data)
  scan_client_credentials "$container" "$SERVICE_ROLE_KEY" "$DB_URL"
done
rg 'PASS live client|INJECTION|Executed [0-9]+ test' "$work_dir"/*.log || true
echo "PASS real independent-client matrix and reused exact backend standings/races"
