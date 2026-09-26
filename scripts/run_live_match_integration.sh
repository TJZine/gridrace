#!/usr/bin/env bash
set -euo pipefail

# Reproducible P3-04 local proof. Prerequisites: macOS/Xcode 26.6, two unused iOS
# 26.5 simulators, Docker, Deno, Node/npm, psql, and the lockfile-pinned Supabase
# CLI. The run resets only the confirmed unlinked loopback GridRace stack, creates
# disposable Auth users, runs two separate XCTest processes/containers, proves the
# local pg_cron path with both clients stopped, reruns the backend race harness, and
# removes only its users, app containers, temporary build data, and function server.
# Client processes receive the public URL/key and their own credentials only.
if [[ ${1:-} == "--help" ]]; then
  sed -n '4,12p' "$0"
  exit 0
fi

[[ ${GRIDRACE_LOCAL_INTEGRATION:-} == "1" ]] || {
  echo "UNAVAILABLE: set GRIDRACE_LOCAL_INTEGRATION=1 to allow disposable local proof" >&2
  exit 2
}

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
[[ $(git branch --show-current) == "dev/classic-mode" ]] || {
  echo "REFUSED: wrong branch" >&2
  exit 2
}
[[ $(sed -n 's/^project_id = "\([^"]*\)"/\1/p' supabase/config.toml) == "gridrace" ]] || {
  echo "REFUSED: unexpected Supabase project" >&2
  exit 2
}
[[ ! -e supabase/.temp/project-ref && ! -e .supabase/project-ref ]] || {
  echo "REFUSED: linked Supabase project detected" >&2
  exit 2
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/gridrace-live-integration.XXXXXX")
derived_data="$work_dir/DerivedData"
function_pid=""
host_pid=""
guest_pid=""
failed_guess=""
declare -a created_users=()
declare -a created_matches=()
declare -a proof_simulators=()
declare -a client_environment_names=(
  GRIDRACE_LOCAL_INTEGRATION GRIDRACE_LIVE_ROLE GRIDRACE_LIVE_SCENARIO
  GRIDRACE_LIVE_EMAIL GRIDRACE_LIVE_PASSWORD GRIDRACE_LIVE_JOIN_CODE
  GRIDRACE_LIVE_MATCH_ID GRIDRACE_LIVE_DISABLE_REALTIME
  GRIDRACE_LIVE_FAILED_GUESS
  GRIDRACE_LOCAL_SUPABASE_URL GRIDRACE_LOCAL_SUPABASE_KEY
)

cleanup() {
  set +e
  [[ -z "$host_pid" ]] || kill "$host_pid" 2>/dev/null
  [[ -z "$guest_pid" ]] || kill "$guest_pid" 2>/dev/null
  [[ -z "$function_pid" ]] || kill "$function_pid" 2>/dev/null
  for match_id in ${created_matches[@]+"${created_matches[@]}"}; do
    sql_scalar "delete from public.matches where id = '$match_id' returning id" >/dev/null
  done
  [[ -z "$failed_guess" ]] || \
    sql_scalar "delete from private.words where word = '$failed_guess' returning word" >/dev/null
  for user_id in ${created_users[@]+"${created_users[@]}"}; do
    sql_scalar "delete from auth.users where id = '$user_id' returning id" >/dev/null
  done
  for simulator in ${proof_simulators[@]+"${proof_simulators[@]}"}; do
    for name in "${client_environment_names[@]}"; do
      xcrun simctl spawn "$simulator" launchctl unsetenv "$name" >/dev/null 2>&1
    done
    xcrun simctl uninstall "$simulator" com.example.GridRace >/dev/null 2>&1
  done
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

npx --no-install supabase --version >/dev/null
npx --no-install supabase start >"$work_dir/supabase-start.log" 2>&1
set -a
eval "$(npx --no-install supabase status -o env 2>/dev/null)"
set +a
[[ $API_URL == "http://127.0.0.1:54321" || $API_URL == "http://localhost:54321" ]] || {
  echo "REFUSED: API URL is not the disposable loopback port" >&2
  exit 2
}
[[ $DB_URL == "postgresql://postgres:postgres@127.0.0.1:54322/postgres" || \
   $DB_URL == "postgresql://postgres:postgres@localhost:54322/postgres" ]] || {
  echo "REFUSED: database URL is not the disposable loopback GridRace database" >&2
  exit 2
}
npx --no-install supabase db reset --local >"$work_dir/db-reset.log" 2>&1

npx --no-install supabase functions serve --log-level error \
  >"$work_dir/functions.log" 2>&1 &
function_pid=$!
for _ in {1..100}; do
  status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --request POST --header "apikey: $ANON_KEY" \
    --header "Authorization: Bearer $ANON_KEY" \
    --header 'Content-Type: application/json' --data '{}' \
    "$API_URL/functions/v1/create-match" || true)
  [[ $status == "400" ]] && break
  sleep 0.1
done
[[ ${status:-} == "400" ]] || { echo "UNAVAILABLE: local Edge gateway did not start" >&2; exit 2; }

select_simulators() {
  while IFS= read -r line; do
    simulator=$(awk -F'[()]' '{print $2}' <<<"$line")
    [[ -n "$simulator" ]] || continue
    if ! xcrun simctl get_app_container "$simulator" com.example.GridRace data \
      >/dev/null 2>&1; then
      proof_simulators+=("$simulator")
    fi
    [[ ${#proof_simulators[@]} -eq 2 ]] && return
  done < <(xcrun simctl list devices available | awk '/-- iOS 26\.5 --/{found=1; next} found && /iPhone/ {print}')
}
select_simulators
[[ ${#proof_simulators[@]} -eq 2 ]] || {
  echo "UNAVAILABLE: two simulator containers not already holding GridRace are required" >&2
  exit 2
}
host_simulator=${proof_simulators[0]}
guest_simulator=${proof_simulators[1]}
xcrun simctl boot "$host_simulator" >/dev/null 2>&1 || true
xcrun simctl boot "$guest_simulator" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$host_simulator" -b >/dev/null
xcrun simctl bootstatus "$guest_simulator" -b >/dev/null

xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
  -destination "platform=iOS Simulator,id=$host_simulator" \
  -derivedDataPath "$derived_data" build-for-testing \
  >"$work_dir/build-for-testing.log" 2>&1

sql_scalar() {
  PGPASSWORD=postgres /opt/homebrew/opt/libpq/bin/psql \
    --host 127.0.0.1 --port 54322 --username postgres --dbname postgres \
    -XAtq -v ON_ERROR_STOP=1 -c "$1" | tail -n 1
}

[[ $(sql_scalar "select count(*) from private.words where word = 'zzzzz'") == "0" ]] || {
  echo "REFUSED: deterministic failed-guess fixture already exists" >&2
  exit 2
}
failed_guess=$(sql_scalar \
  "insert into private.words (word, is_accepted, is_answer, is_active, pack_version) values ('zzzzz', true, false, true, 1) returning word")
[[ $(sql_scalar \
  "select concat(word ~ '^[a-z]{5}$', '|', is_accepted, '|', is_active, '|', is_answer) from private.words where word = '$failed_guess'") == "true|true|true|false" ]]
echo "PASS deterministic failed-guess fixture is valid, accepted, active, and non-answer"

wait_sql() {
  local query=$1 expected=$2 result=""
  for _ in {1..900}; do
    result=$(sql_scalar "$query")
    [[ $result == "$expected" ]] && return 0
    sleep 0.1
  done
  return 1
}

create_user() {
  local label=$1 suffix response
  suffix=$(uuidgen | tr '[:upper:]' '[:lower:]')
  fixture_email="$label-$suffix@example.test"
  fixture_password="GridRace-${suffix//-/}"
  response=$(curl --fail --silent --show-error --request POST \
    --header "apikey: $SERVICE_ROLE_KEY" \
    --header "Authorization: Bearer $SERVICE_ROLE_KEY" \
    --header 'Content-Type: application/json' \
    --data "{\"email\":\"$fixture_email\",\"password\":\"$fixture_password\",\"email_confirm\":true}" \
    "$API_URL/auth/v1/admin/users")
  fixture_user_id=$(plutil -extract id raw -o - - <<<"$response")
  created_users+=("$fixture_user_id")
}

run_client() {
  local simulator=$1 role=$2 scenario=$3 email=$4 password=$5 log=$6
  local code=${7:-} match_id=${8:-} realtime=${9:-1} status
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LOCAL_INTEGRATION 1
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_ROLE "$role"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_SCENARIO "$scenario"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_EMAIL "$email"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_PASSWORD "$password"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_JOIN_CODE "$code"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_MATCH_ID "$match_id"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_DISABLE_REALTIME "$realtime"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_FAILED_GUESS "$failed_guess"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LOCAL_SUPABASE_URL "$API_URL"
  xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LOCAL_SUPABASE_KEY "$ANON_KEY"
  set +e
  xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$derived_data" test-without-building \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 150 \
    -maximum-test-execution-time-allowance 180 \
    -collect-test-diagnostics never \
    -only-testing:GridRaceTests/LiveMatchIntegrationTests/testTwoClientProcess \
    >"$log" 2>&1
  status=$?
  for name in "${client_environment_names[@]}"; do
    xcrun simctl spawn "$simulator" launchctl unsetenv "$name" >/dev/null 2>&1
  done
  set -e
  return "$status"
}

run_pair() {
  local scenario=$1 host_id host_email host_password guest_id guest_email guest_password
  local match_id join_code host_log guest_log host_status guest_status
  create_user "$scenario-host"
  host_id=$fixture_user_id
  host_email=$fixture_email
  host_password=$fixture_password
  create_user "$scenario-guest"
  guest_id=$fixture_user_id
  guest_email=$fixture_email
  guest_password=$fixture_password
  host_log="$work_dir/$scenario-host.log"
  guest_log="$work_dir/$scenario-guest.log"

  run_client "$host_simulator" host "$scenario" "$host_email" "$host_password" \
    "$host_log" "" "" 0 &
  host_pid=$!
  for _ in {1..600}; do
    match_id=$(sql_scalar "select match_id from public.match_members where auth_user_id = '$host_id' order by joined_at desc limit 1")
    [[ -n "$match_id" ]] && break
    sleep 0.1
  done
  if [[ -z ${match_id:-} ]]; then
    grep -E 'error:|failed|skipped|Executed [0-9]+ test' "$host_log" >&2 || true
    echo "FAIL: host did not create a match" >&2
    return 1
  fi
  created_matches+=("$match_id")
  join_code=$(sql_scalar "select join_code from public.matches where id = '$match_id'")

  run_client "$guest_simulator" guest "$scenario" "$guest_email" "$guest_password" \
    "$guest_log" "$join_code" "" 1 &
  guest_pid=$!
  set +e
  wait "$host_pid"; host_status=$?
  wait "$guest_pid"; guest_status=$?
  set -e
  host_pid=""
  guest_pid=""
  grep -E 'PASS live client|Executed [0-9]+ test' "$host_log" || true
  grep -E 'PASS live client|Executed [0-9]+ test' "$guest_log" || true
  [[ $host_status -eq 0 && $guest_status -eq 0 ]] || return 1

  if [[ $scenario == "product" ]]; then
    [[ $(sql_scalar "select count(*) from public.player_rounds player join public.rounds round on round.id = player.round_id where round.match_id = '$match_id' and player.state = 'failed' and player.accepted_guess_count = 6 and player.efficiency_points = 0") == "2" ]]
    [[ $(sql_scalar "select count(*) from public.guesses guess join public.rounds round on round.id = guess.round_id where round.match_id = '$match_id' and guess.normalized_guess = '$failed_guess'") == "12" ]]
    [[ $(sql_scalar "select status from public.matches where id = '$match_id'") == "completed" ]]
    echo "PASS both clients stored six failed guesses with zero efficiency"
    echo "PASS two-process product loop"
    return
  fi

  [[ $(sql_scalar "select status from public.matches where id = '$match_id'") == "in_progress" ]]
  local prior_run
  prior_run=$(sql_scalar "select coalesce(max(runid),0) from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'gridrace-finalize-rounds')")
  sql_scalar "update public.rounds set starts_at = transaction_timestamp() - interval '181 seconds', ends_at = transaction_timestamp() - interval '1 second' where match_id = '$match_id' returning id" >/dev/null
  wait_sql "select status from public.matches where id = '$match_id'" "completed" || return 1
  [[ $(sql_scalar "select count(*) from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'gridrace-finalize-rounds') and runid > $prior_run and status = 'succeeded'") != "0" ]]
  [[ $(sql_scalar "select private.finalize_expired_rounds()") == "0" ]]

  run_client "$host_simulator" resume "$scenario" "$host_email" "$host_password" \
    "$work_dir/$scenario-host-resume.log" "" "$match_id" 0 &
  host_pid=$!
  run_client "$guest_simulator" resume "$scenario" "$guest_email" "$guest_password" \
    "$work_dir/$scenario-guest-resume.log" "" "$match_id" 1 &
  guest_pid=$!
  set +e
  wait "$host_pid"; host_status=$?
  wait "$guest_pid"; guest_status=$?
  set -e
  host_pid=""
  guest_pid=""
  [[ $host_status -eq 0 && $guest_status -eq 0 ]] || return 1
  grep -E 'PASS live client|Executed [0-9]+ test' "$work_dir/$scenario-host-resume.log" || true
  grep -E 'PASS live client|Executed [0-9]+ test' "$work_dir/$scenario-guest-resume.log" || true
  echo "PASS no-client scheduled finalization and two-container relaunch"
}

run_pair product
run_pair cron

GRIDRACE_LOCAL_INTEGRATION=1 deno run \
  --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost \
  --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts

for simulator in "$host_simulator" "$guest_simulator"; do
  container=$(xcrun simctl get_app_container "$simulator" com.example.GridRace data)
  ! rg -a -q --fixed-strings "$SERVICE_ROLE_KEY" "$container"
  ! rg -a -q --fixed-strings "$DB_URL" "$container"
done
echo "PASS privileged credentials absent from both client containers"
