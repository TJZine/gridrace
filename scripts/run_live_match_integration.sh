#!/usr/bin/env bash
set -euo pipefail

# P4-V real two-process proof. Controller must inventory the unlinked loopback
# stack, apply existing migrations, and own a running Edge gateway before use.
# No reset/start/stop of the shared backend. Each run creates two disposable
# simulators and unique Auth/match/non-answer-word fixtures; cleanup owns only those.
# Logs and xcresults remain in the printed /tmp proof directory after cleanup.
# Requires macOS/Xcode, iOS 26.5, cached frozen SourcePackages, Deno, npm and psql.
# Set GRIDRACE_INTEGRATION_STACK_DIR and GRIDRACE_SOURCE_PACKAGES_CACHE; see
# scripts/LOCAL_INTEGRATION.md for receipt admission and owned-stack setup.
# Product 1/3/5 rounds relaunch both clients at every reveal. Cron 1/3 waits the
# original 180-second deadlines with both clients stopped. Deletion restores the
# surviving container at nonfinal and final boundaries. Budget roughly 20 minutes.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
source "$repo_root/scripts/live_integration_selection.sh"
parse_integration_selection "$@"
[[ $selection_action == run ]] || exit 0
[[ ${GRIDRACE_LOCAL_INTEGRATION:-} == 1 ]] || {
  echo "UNAVAILABLE: set GRIDRACE_LOCAL_INTEGRATION=1 after controller inventory" >&2; exit 2;
}
cd "$repo_root"
source "$repo_root/scripts/scan_client_credentials.sh"
stack_dir=${GRIDRACE_INTEGRATION_STACK_DIR:-$repo_root}
[[ -f "$stack_dir/supabase/config.toml" ]] || exit 2
# Names are not ownership evidence; the controller inventories this exact directory.
[[ $(sed -n 's/^project_id = "\([^"]*\)"/\1/p' "$stack_dir/supabase/config.toml") != "" ]] || exit 2
[[ ! -e "$stack_dir/supabase/.temp/project-ref" && ! -e "$stack_dir/.supabase/project-ref" ]] || {
  echo "REFUSED: linked Supabase project" >&2; exit 2;
}
work_dir=$(mktemp -d /tmp/gridrace-live-integration.XXXXXX)
chmod 700 "$work_dir"
: > "$work_dir/owned-fixtures.tsv"
chmod 600 "$work_dir/owned-fixtures.tsv"
echo "PROOF_DIRECTORY $work_dir"
{
  printf 'head=%s\nbranch=%s\n' "$(git rev-parse HEAD)" "$(git branch --show-current)"
  printf 'tracked_diff_sha256=%s\n' "$(git diff HEAD --binary | shasum -a 256 | awk '{print $1}')"
  printf 'scope=%s\nscenarios=%s\n' "$selection_scope" "$selected_scenarios"
  shasum -a 256 scripts/run_live_match_integration.sh scripts/live_integration_selection.sh \
    supabase/tests/integration/live_slice_test.ts supabase/tests/integration/scenario_selection.ts
} > "$work_dir/source-and-scope.txt"
python3 - "$repo_root" "$work_dir/source-manifest.json" <<'MANIFEST'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); files={}
for directory in ['ios','shared','supabase/functions','supabase/migrations','supabase/tests/integration','invitation-landing']:
    for file in sorted((root/directory).rglob('*')):
        if file.is_file() and '.DS_Store' not in file.parts:
            files[str(file.relative_to(root))]=hashlib.sha256(file.read_bytes()).hexdigest()
for path in ['scripts/run_live_match_integration.sh','scripts/live_integration_selection.sh']:
    files[path]=hashlib.sha256((root/path).read_bytes()).hexdigest()
pathlib.Path(sys.argv[2]).write_text(json.dumps(files,sort_keys=True,indent=2)+'\n')
MANIFEST
derived_data="$work_dir/DerivedData"
package_cache=${GRIDRACE_SOURCE_PACKAGES_CACHE:-}
lock=ios/GridRace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
lock_hash=d6b069e121418166c3b844eb1c1b66fc2f0ccb715f0b9808405a14a9a68d0691
check_lock() { [[ $(shasum -a 256 "$lock" | awk '{print $1}') == "$lock_hash" ]]; }
check_lock
if integration_has_native_scenarios; then
  [[ -d "$package_cache" ]] || { echo "UNAVAILABLE: retained SourcePackages cache" >&2; exit 2; }
fi
# Keep privileged environment private to this orchestrator, never exported to Xcode.
eval "$(npx --no-install supabase --workdir "$stack_dir" status -o env 2>/dev/null)"
export -n API_URL ANON_KEY SERVICE_ROLE_KEY DB_URL JWT_SECRET 2>/dev/null || true
[[ $API_URL =~ ^http://(127\.0\.0\.1|localhost):([1-9][0-9]*)$ ]] || exit 2
api_port=${BASH_REMATCH[2]}
[[ $api_port -gt 0 && $api_port -le 65535 ]] || exit 2
[[ $DB_URL =~ ^postgresql://postgres:postgres@(127\.0\.0\.1|localhost):([1-9][0-9]*)/postgres$ ]] || exit 2
db_port=${BASH_REMATCH[2]}
[[ $db_port -gt 0 && $db_port -le 65535 ]] || exit 2
sql_scalar() {
  PGPASSWORD=postgres /opt/homebrew/opt/libpq/bin/psql --host 127.0.0.1 --port "$db_port" \
    --username postgres --dbname postgres -XAtq -v ON_ERROR_STOP=1 -c "$1" | tail -n 1
}
baseline=$(sql_scalar "select jsonb_build_object('auth',(select count(*) from auth.users),'matches',(select count(*) from public.matches),'daily_progress',(select count(*) from public.daily_progress),'daily_imported',(select count(*) from public.daily_imported_results),'deletion_receipts',(select count(*) from private.account_deletion_receipts))::text")
printf '%s\n' "$baseline" > "$work_dir/baseline-inventory.json"
baseline_receipts=$(sql_scalar "select coalesce(jsonb_agg(token_hash order by token_hash),'[]'::jsonb)::text from private.account_deletion_receipts")
printf '%s\n' "$baseline_receipts" > "$work_dir/baseline-receipt-hashes-private.json"
chmod 600 "$work_dir/baseline-receipt-hashes-private.json"
[[ $(sql_scalar "select allow_new_rematches from private.live_feature_configuration") == f ]] || { echo "REFUSED: expected controller default-off feature baseline" >&2; exit 2; }
host_pid=""; guest_pid=""; third_pid=""; failed_guess=""; cron_paused=0; cron_job_id=""; cron_baseline_active=""; run_completed=0
declare -a created_users=() created_matches=() proof_simulators=() installed_simulators=()
: > "$work_dir/client-credential-scan-status.tsv"
chmod 600 "$work_dir/client-credential-scan-status.tsv"
cleanup() {
  local original_status=$? cleanup_failed=0 scan_container scan_status
  set +e
  if [[ $run_completed != 1 ]]; then
    echo "FAIL: integration did not reach its final completion point" >&2
    [[ $original_status != 0 ]] || original_status=1
  fi
  for pid in "$host_pid" "$guest_pid" "$third_pid"; do
    [[ -z "$pid" ]] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  done
  # Failure paths must observe installed client containers before disposal too.
  # XCTest may relocate the data container, so resolve it again after workers stop.
  for simulator in ${installed_simulators[@]+"${installed_simulators[@]}"}; do
    scan_status=1
    if scan_container=$(xcrun simctl get_app_container "$simulator" com.example.GridRace data 2>/dev/null); then
      scan_client_credentials "$scan_container" "$SERVICE_ROLE_KEY" "$DB_URL"
      scan_status=$?
    fi
    printf '%s\t%s\n' "$simulator" "$scan_status" >> "$work_dir/client-credential-scan-status.tsv"
    [[ $scan_status == 0 ]] || { echo "FAIL: owned client credential scan before disposal" >&2; cleanup_failed=1; }
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
  # The exclusive runtime lease admits only run-owned Auth fixture mutations.
  # Preserve every baseline tombstone and remove only the new private hash delta.
  sql_scalar "select coalesce(jsonb_agg(token_hash order by token_hash),'[]'::jsonb)::text from private.account_deletion_receipts where token_hash not in (select jsonb_array_elements_text('$baseline_receipts'::jsonb))" > "$work_dir/owned-receipt-hashes-private.json" || cleanup_failed=1
  chmod 600 "$work_dir/owned-receipt-hashes-private.json" || cleanup_failed=1
  sql_scalar "delete from private.account_deletion_receipts where token_hash not in (select jsonb_array_elements_text('$baseline_receipts'::jsonb))" >/dev/null || cleanup_failed=1
  after_receipts=$(sql_scalar "select coalesce(jsonb_agg(token_hash order by token_hash),'[]'::jsonb)::text from private.account_deletion_receipts")
  printf '%s\n' "$after_receipts" > "$work_dir/after-receipt-hashes-private.json"
  chmod 600 "$work_dir/after-receipt-hashes-private.json" || cleanup_failed=1
  [[ $after_receipts == "$baseline_receipts" ]] || { echo "FAIL: baseline receipt hashes changed" >&2; cleanup_failed=1; }
  for simulator in ${proof_simulators[@]+"${proof_simulators[@]}"}; do
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || cleanup_failed=1
  done
  if [[ $cron_paused == 1 ]]; then
    sql_scalar "select cron.alter_job($cron_job_id, active:=true)" >/dev/null || cleanup_failed=1
    [[ $(sql_scalar "select active from cron.job where jobid=$cron_job_id and username=current_user") == "$cron_baseline_active" ]] || cleanup_failed=1
  fi
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=false" >/dev/null || cleanup_failed=1
  after=$(sql_scalar "select jsonb_build_object('auth',(select count(*) from auth.users),'matches',(select count(*) from public.matches),'daily_progress',(select count(*) from public.daily_progress),'daily_imported',(select count(*) from public.daily_imported_results),'deletion_receipts',(select count(*) from private.account_deletion_receipts))::text")
  printf '%s\n' "$after" > "$work_dir/after-inventory.json"
  [[ $after == "$baseline" ]] || { echo "FAIL: baseline inventory changed" >&2; cleanup_failed=1; }
  check_lock || { echo "FAIL: protected package lock changed" >&2; cleanup_failed=1; }
  echo "CLEANUP owned fixtures/containers only; proof retained at $work_dir"
  if [[ $cleanup_failed != 0 ]]; then
    echo "FAIL: owned cleanup incomplete; controller must inspect retained proof" >&2
    original_status=1
  fi
  printf 'cleanup_failed=%s\nrun_completed=%s\n' "$cleanup_failed" "$run_completed" > "$work_dir/cleanup-status.txt"
  trap - EXIT
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
status=$(curl --silent --output /dev/null --write-out '%{http_code}' --request POST \
  --header "apikey: $ANON_KEY" --header "Authorization: Bearer $ANON_KEY" \
  --header 'Content-Type: application/json' --data '{"client_build":3}' "$API_URL/functions/v1/create-match")
[[ $status == 400 ]] || { echo "UNAVAILABLE: controller-owned Edge gateway" >&2; exit 2; }
# Do not replace or delete a preexisting non-answer fixture.
if integration_has_live_scenarios; then
for _ in {1..20}; do
  candidate=$(python3 -c 'import secrets,string; print("z"+"".join(secrets.choice(string.ascii_lowercase) for _ in range(4)))')
  failed_guess=$(sql_scalar "insert into private.words(word,is_accepted,is_answer,is_active,pack_version) values('$candidate',true,false,true,1) on conflict do nothing returning word")
  [[ -n "$failed_guess" ]] && break
done
[[ -n "$failed_guess" ]] || { echo "UNAVAILABLE: unique non-answer fixture" >&2; exit 2; }
# Record a digest for controller cleanup inventory without storing the guess word.
printf 'non_answer_word_sha256\t%s\n' "$(printf '%s' "$failed_guess" | shasum -a 256 | awk '{print $1}')" >> "$work_dir/owned-fixtures.tsv"
fi
run_tag=$(uuidgen)
pair_sequence=0
pair_phase=predecessor
if integration_has_native_scenarios; then
roles=(host guest)
if integration_selected friends-3 || integration_selected friends-3-race; then roles+=(third); fi
for role in "${roles[@]}"; do
  simulator=$(xcrun simctl create "GridRace-proof-$run_tag-$role" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
  proof_simulators+=("$simulator")
  printf 'simulator\t%s\n' "$simulator" >> "$work_dir/owned-fixtures.tsv"
  xcrun simctl boot "$simulator"
  xcrun simctl bootstatus "$simulator" -b >/dev/null
done
host_simulator=${proof_simulators[0]}; guest_simulator=${proof_simulators[1]}; third_simulator=${proof_simulators[2]:-}
xcode_flags=(-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates)
xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace "${xcode_flags[@]}" \
  -clonedSourcePackagesDirPath "$package_cache" -destination "platform=iOS Simulator,id=$host_simulator" \
  -derivedDataPath "$derived_data" build-for-testing >"$work_dir/build-for-testing.log" 2>&1
check_lock
# Install the host app before receipt delivery; XCTest uses this same container.
app_path="$derived_data/Build/Products/Debug-iphonesimulator/GridRace.app"
for simulator in "${proof_simulators[@]}"; do
  xcrun simctl install "$simulator" "$app_path"
  installed_simulators+=("$simulator")
done
fi
write_receipt() {
  local simulator=$1 purpose=$2 email=$3 user_id=$4 alternate=${5:-0} owned=0 candidate container
  for candidate in "${created_users[@]}"; do
    [[ $candidate != "$user_id" ]] || owned=1
  done
  [[ $owned == 1 ]] || { echo "REFUSED: unowned Auth fixture" >&2; return 1; }
  [[ $(sql_scalar "select email from auth.users where id='$user_id'") == "$email" ]] || return 1
  container=$(xcrun simctl get_app_container "$simulator" com.example.GridRace data)
  receipt_name="fixture-$run_tag.json"
  receipt_directory="$container/Library/Application Support/GridRaceIntegration"
  [[ $alternate == 0 ]] || receipt_directory+="/Alternate"
  mkdir -p "$receipt_directory"
  chmod 700 "$receipt_directory"
  receipt_path="$receipt_directory/$receipt_name"
  python3 - "$receipt_path" "$run_tag" "$API_URL" "$purpose" "$user_id" "$email" <<'RECEIPT'
import json,os,sys,time
path,run,endpoint,purpose,user,email=sys.argv[1:]
with open(path,'w') as f:
    json.dump(dict(version=1,runID=run,endpoint=endpoint,unlinked=True,
                   createdAt=time.time(),purpose=purpose,userID=user,email=email),f)
os.chmod(path,0o600)
RECEIPT
  cp "$receipt_path" "$work_dir/fixture-$user_id-$purpose-$alternate.json"
}
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
  [[ ! -e "$log" && ! -e "${log%.log}.xcresult" ]] || { echo "REFUSED: existing client proof artifact" >&2; return 1; }
  if [[ -n ${pair_coordination_id:-} && -z $match_id && $simulator == "$guest_simulator" && ( $role == guest || $role == invitation-root ) ]]; then
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_WAIT_FOR_CODE 1
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_COORDINATION_ID "$pair_coordination_id"
  else
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_LIVE_WAIT_FOR_CODE
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_LIVE_COORDINATION_ID
  fi
  if [[ -n ${selection_coordination_id:-} && $role == friends-select ]]; then
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_LIVE_WAIT_FOR_SELECTION 1
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_SELECTION_COORDINATION_ID "$selection_coordination_id"
  else
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_LIVE_WAIT_FOR_SELECTION
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_SELECTION_COORDINATION_ID
  fi
  # These launchd environments belong exclusively to newly created simulators.
  local name value client_status client_pid test_guess=${11:-$failed_guess} user_id
  if [[ $email == "$host_email" ]]; then user_id=$host_id
  elif [[ $email == "$guest_email" ]]; then user_id=$guest_id
  else echo "REFUSED: credentials outside owned pair" >&2; return 1; fi
  write_receipt "$simulator" live "$email" "$user_id"
  if [[ $role == invitation-root ]]; then
    write_receipt "$simulator" live "$host_email" "$host_id" 1
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_ALTERNATE_EMAIL "$host_email"
    xcrun simctl spawn "$simulator" launchctl setenv GRIDRACE_ALTERNATE_PASSWORD "$host_password"
  else
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_ALTERNATE_EMAIL
    xcrun simctl spawn "$simulator" launchctl unsetenv GRIDRACE_ALTERNATE_PASSWORD
  fi
  while IFS='=' read -r name value; do
    xcrun simctl spawn "$simulator" launchctl setenv "$name" "$value"
  done <<ENV
GRIDRACE_LOCAL_INTEGRATION=1
GRIDRACE_FIXTURE_RUN_ID=$run_tag
GRIDRACE_FIXTURE_RECEIPT=$receipt_name
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
  env -u SERVICE_ROLE_KEY -u SUPABASE_SERVICE_ROLE_KEY -u SUPABASE_SECRET_KEY -u DB_URL -u DATABASE_URL -u JWT_SECRET -u SUPABASE_DB_PASSWORD \
    xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace "${xcode_flags[@]}" \
    -clonedSourcePackagesDirPath "$package_cache" -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived_data" \
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
    "$work_dir/$(integration_client_log_basename "$scenario" "$count" "$pair_sequence" "$pair_phase" "$target" "$host_role" host)" "" "$match_id" "$count" "$target" & host_pid=$!
  run_client "$guest_simulator" "$guest_role" "$scenario" "$guest_email" "$guest_password" \
    "$work_dir/$(integration_client_log_basename "$scenario" "$count" "$pair_sequence" "$pair_phase" "$target" "$guest_role" guest)" "$join_code" "$match_id" "$count" "$target" & guest_pid=$!
  wait_clients
}
start_pair() {
  local scenario=$1 count=$2 guest_role=${3:-guest}
  pair_sequence=$((pair_sequence+1)); pair_phase=predecessor
  create_user; host_id=$fixture_user_id; host_email=$fixture_email; host_password=$fixture_password
  create_user; guest_id=$fixture_user_id; guest_email=$fixture_email; guest_password=$fixture_password
  match_id=""; join_code=""; pair_coordination_id=$(uuidgen)
  # Cold guest Xcode startup is outside the host's roster wait. The admitted
  # guest blocks before feature work until the host's real public code arrives.
  run_client "$guest_simulator" "$guest_role" "$scenario" "$guest_email" "$guest_password" \
    "$work_dir/$(integration_client_log_basename "$scenario" "$count" "$pair_sequence" "$pair_phase" 1 "$guest_role" guest)" "" "" "$count" 1 & guest_pid=$!
  guest_ready=0
  for _ in {1..1800}; do
    current_container=$(xcrun simctl get_app_container "$guest_simulator" com.example.GridRace data)
    coordination_root="$current_container/Library/Application Support/GridRaceIntegration/Coordination/$pair_coordination_id"
    [[ ! -f "$coordination_root/ready" ]] || { guest_ready=1; break; }
    sleep 0.1
  done
  [[ $guest_ready == 1 ]] || { echo "FAIL: admitted native guest readiness absent" >&2; return 1; }
  echo "BARRIER admitted native guest ready before host domain create"
  run_client "$host_simulator" host "$scenario" "$host_email" "$host_password" \
    "$work_dir/$(integration_client_log_basename "$scenario" "$count" "$pair_sequence" "$pair_phase" 1 host host)" "" "" "$count" 1 & host_pid=$!
  for _ in {1..600}; do
    match_id=$(sql_scalar "select match_id from public.match_members where auth_user_id='$host_id' order by joined_at desc limit 1")
    [[ -n "$match_id" ]] && break
    sleep 0.1
  done
  [[ $match_id =~ ^[0-9a-f-]{36}$ ]] || { echo "FAIL: no owned Create" >&2; return 1; }
  created_matches+=("$match_id")
  printf 'match\t%s\n' "$match_id" >> "$work_dir/owned-fixtures.tsv"
  join_code=$(sql_scalar "select join_code from public.matches where id='$match_id'")
  current_container=$(xcrun simctl get_app_container "$guest_simulator" com.example.GridRace data)
  coordination_root="$current_container/Library/Application Support/GridRaceIntegration/Coordination/$pair_coordination_id"
  python3 - "$coordination_root/public-code.json" "$join_code" <<'PUBLIC_CODE'
import json,os,sys
path,code=sys.argv[1:]
with open(path+'.pending','w') as file: json.dump({'code':code},file)
os.chmod(path+'.pending',0o600)
os.replace(path+'.pending',path)
PUBLIC_CODE
  pair_coordination_id=""
  wait_clients
}
assert_sql_reveal() {
  local target=$1 count=$2 expected=in_progress
  [[ $target == "$count" ]] && expected=completed
  [[ $(sql_scalar "select concat(status,'|',current_round,'|',round_count) from public.matches where id='$match_id'") == "$expected|$target|$count" ]]
  [[ $(sql_scalar "select count(*) from public.rounds where match_id='$match_id' and state='revealed'") == "$target" ]]
  [[ $(sql_scalar "select count(distinct answer) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='$match_id'") == "$target" ]]
}
# Each destructive native proof owns a distinct newly created disposable account.
run_disposable_daily_test() {
  local selector=$1 slug=$2 user_id method skip_status
  create_user
  user_id=$fixture_user_id
  method=${selector##*/}
  write_receipt "$host_simulator" daily "$fixture_email" "$user_id"
  while IFS='=' read -r name value; do
    xcrun simctl spawn "$host_simulator" launchctl setenv "$name" "$value"
  done <<ENV
GRIDRACE_LOCAL_INTEGRATION=1
GRIDRACE_FIXTURE_RUN_ID=$run_tag
GRIDRACE_FIXTURE_RECEIPT=$receipt_name
GRIDRACE_LOCAL_SYNC_EMAIL=$fixture_email
GRIDRACE_LOCAL_SYNC_PASSWORD=$fixture_password
GRIDRACE_LOCAL_SUPABASE_URL=$API_URL
GRIDRACE_LOCAL_SUPABASE_KEY=$ANON_KEY
ENV
  env -u SERVICE_ROLE_KEY -u SUPABASE_SERVICE_ROLE_KEY -u SUPABASE_SECRET_KEY \
    -u DB_URL -u DATABASE_URL -u JWT_SECRET -u SUPABASE_DB_PASSWORD \
    xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace "${xcode_flags[@]}" \
    -clonedSourcePackagesDirPath "$package_cache" -destination "platform=iOS Simulator,id=$host_simulator" -derivedDataPath "$derived_data" \
    -resultBundlePath "$work_dir/$slug.xcresult" test-without-building \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 150 \
    -maximum-test-execution-time-allowance 180 -collect-test-diagnostics never \
    -only-testing:"$selector" >"$work_dir/$slug.log" 2>&1
  rg -q "$method.*passed" "$work_dir/$slug.log"
  if rg -qi "$method.*skipped" "$work_dir/$slug.log" 2>/dev/null; then
    echo "FAIL: disposable $slug skipped" >&2
    return 1
  else
    skip_status=$?
    if [[ $skip_status != 1 ]]; then
      echo "FAIL: disposable $slug skip inspection unavailable" >&2
      return 1
    fi
  fi
  [[ $(sql_scalar "select count(*) from auth.users where id='$user_id'") == 0 ]]
  xcrun simctl terminate "$host_simulator" com.example.GridRace >/dev/null 2>&1 || true
  check_lock
  for name in GRIDRACE_LOCAL_SYNC_EMAIL GRIDRACE_LOCAL_SYNC_PASSWORD; do
    xcrun simctl spawn "$host_simulator" launchctl unsetenv "$name"
  done
  echo "PASS disposable $slug Auth deletion verified by host"
}
if integration_selected deletion-receipt; then
run_disposable_daily_test \
  GridRaceTests/AccountAuthLifecycleTests/testLocalCommittedDeletionReceiptAfterLostResponseAndIssuedRefreshWhenConfigured \
  deletion-receipt
rg -q 'GRIDRACE_P4_ORIGINAL_BEARER_RECEIPT_PASS' "$work_dir/deletion-receipt.log"
fi
if integration_selected daily; then
run_disposable_daily_test \
  GridRaceTests/DailySyncTests/testLocalSupabaseTwoClientSyncAndDeletionWhenConfigured daily
rg -q 'PASS disposable Daily two-client sync and deletion' "$work_dir/daily.log"
fi
for count in 1 3 5; do
  integration_selected "product-$count" || continue
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
if integration_selected mixed-3; then
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
fi
# Each test process exits at playing; only SQL observations occur until Cron reveals.
# No timestamp mutation, snapshot request or manual finalize is used during the wait.
for count in 1 3; do
  integration_selected "cron-$count" || continue
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
  integration_selected "deletion-$count" || continue
  start_pair deletion "$count"
  sql_scalar "select public.delete_account('$guest_id',3)" >/dev/null
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
if integration_selected product-1 || integration_selected product-3 || integration_selected product-5; then
rg -q 'INJECTION dropped real Realtime signal' "$work_dir"/product-*-host.log
rg -q 'INJECTION duplicated and reordered real Realtime signals' "$work_dir"/product-*-host.log
fi
# Each friends unit uses independent native Auth/Edge/Realtime sessions in two
# owned containers. Count 3 adds a third process signed into the host account.
for count in 1 3 5; do
  if ! integration_selected "friends-$count"; then
    [[ $count == 3 ]] && integration_selected friends-3-race || continue
  fi
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=true" >/dev/null
  start_pair friends "$count"
  for ((target=1;target<=count;target++)); do
    [[ $target == 1 ]] || launch_round advance-host advance-guest friends "$count" "$target"
    assert_sql_reveal "$target" "$count"
  done
  predecessor=$match_id
  original_facts=$(sql_scalar "select md5(jsonb_build_object('match',to_jsonb(m),'rounds',(select jsonb_agg(to_jsonb(r) order by round_number) from public.rounds r where r.match_id=m.id),'players',(select jsonb_agg(to_jsonb(p) order by p.round_id,p.member_id) from public.player_rounds p join public.rounds r on r.id=p.round_id where r.match_id=m.id))::text) from public.matches m where id='$predecessor'")
  if [[ $count == 1 ]]; then
    for consent_role in friends-offer friends-decline friends-offer friends-cancel; do
      consent_simulator=$host_simulator; consent_email=$host_email; consent_password=$host_password
      [[ $consent_role != friends-decline ]] || { consent_simulator=$guest_simulator; consent_email=$guest_email; consent_password=$guest_password; }
      consent_sequence=${consent_sequence:-0}; consent_sequence=$((consent_sequence+1))
      run_client "$consent_simulator" "$consent_role" friends "$consent_email" "$consent_password" \
        "$work_dir/friends-1-consent-$consent_sequence-$consent_role.log" "" "$predecessor" 1 1
    done
  fi
  launch_round friends-both friends-both friends "$count" "$count"
  successor=$(sql_scalar "select successor_match_id from private.rematch_contexts where predecessor_match_id='$predecessor'")
  [[ $successor =~ ^[0-9a-f-]{36}$ ]] || exit 1
  created_matches+=("$successor")
  printf 'match\t%s\n' "$successor" >> "$work_dir/owned-fixtures.tsv"
  [[ $(sql_scalar "select concat(status,'|',round_count) from public.matches where id='$successor'") == "lobby|$count" ]]
  [[ $(sql_scalar "select count(*) from private.rematch_successors where match_id='$successor' and predecessor_match_id='$predecessor'") == 1 ]]
  [[ $(sql_scalar "select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='$successor'") == 0 ]]
  # Keep original server deadlines. Accepted allocation must remain recoverable
  # after its five-minute opportunity ends with both app processes stopped.
  if [[ $count == 3 ]] && integration_selected friends-3; then
    wait_sql "select clock_timestamp()>=deadline from private.rematch_contexts where predecessor_match_id='$predecessor'" t 330
    echo 'PASS original rematch opportunity expiry with accepted clients stopped'
  fi
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=false" >/dev/null
  launch_round friends-recover friends-recover friends "$count" "$count"
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=true" >/dev/null
  if [[ $count == 3 ]]; then
    # Native predecessor read pauses before returning its accepted projection.
    # The third same-account process changes selection before the successor read.
    # Admit the third process before pausing a real read; cold XCTest startup
    # is not part of the deliberate between-read barrier.
    selection_coordination_id=$(uuidgen)
    run_client "$third_simulator" friends-select friends "$host_email" "$host_password" \
      "$work_dir/friends-3-selection-third.log" "" "$successor" 3 3 & third_pid=$!
    third_ready=0
    for _ in {1..1800}; do
      third_container=$(xcrun simctl get_app_container "$third_simulator" com.example.GridRace data)
      selection_root="$third_container/Library/Application Support/GridRaceIntegration/Coordination/$selection_coordination_id"
      [[ ! -f "$selection_root/ready" ]] || { third_ready=1; break; }
      sleep 0.1
    done
    [[ $third_ready == 1 ]] || { echo 'FAIL: admitted third native readiness absent' >&2; exit 1; }
    host_container=$(xcrun simctl get_app_container "$host_simulator" com.example.GridRace data)
    barrier_root="$host_container/Library/Application Support/GridRaceIntegration"
    rm -f "$barrier_root/selection-read-barrier" "$barrier_root/selection-read-release"
    run_client "$host_simulator" friends-race friends "$host_email" "$host_password" \
      "$work_dir/friends-3-selection-race-host.log" "" "$predecessor" 3 3 & host_pid=$!
    barrier_ready=0
    for _ in {1..900}; do
      current_container=$(xcrun simctl get_app_container "$host_simulator" com.example.GridRace data)
      barrier_root="$current_container/Library/Application Support/GridRaceIntegration"
      [[ ! -f "$barrier_root/selection-read-barrier" ]] || { barrier_ready=1; break; }
      sleep 0.1
    done
    [[ $barrier_ready == 1 ]] || { echo 'FAIL: real predecessor read barrier absent' >&2; exit 1; }
    third_container=$(xcrun simctl get_app_container "$third_simulator" com.example.GridRace data)
    touch "$third_container/Library/Application Support/GridRaceIntegration/Coordination/$selection_coordination_id/select-now"
    wait "$third_pid"; third_pid=""
    selection_coordination_id=""
    current_container=$(xcrun simctl get_app_container "$host_simulator" com.example.GridRace data)
    touch "$current_container/Library/Application Support/GridRaceIntegration/selection-read-release"
    wait "$host_pid"; host_pid=""
    rg -q 'INJECTION third-account selection between real predecessor and successor reads' "$work_dir/friends-3-selection-race-host.log"
    rg -q 'PASS live client stale pointer passive epoch unchanged then explicit pinned Resume' "$work_dir/friends-3-selection-race-host.log"
  fi
  match_id=$successor
  pair_phase=successor
  join_code=$(sql_scalar "select join_code from public.matches where id='$successor'")
  for ((target=1;target<=count;target++)); do
    launch_round advance-host advance-guest friends "$count" "$target"
    assert_sql_reveal "$target" "$count"
  done
  [[ $(sql_scalar "select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id join private.rematch_successors x on x.match_id=r.match_id where r.match_id='$successor' and s.answer=any(x.excluded_answers)") == 0 ]]
  [[ $(sql_scalar "select md5(jsonb_build_object('match',to_jsonb(m),'rounds',(select jsonb_agg(to_jsonb(r) order by round_number) from public.rounds r where r.match_id=m.id),'players',(select jsonb_agg(to_jsonb(p) order by p.round_id,p.member_id) from public.player_rounds p join public.rounds r on r.id=p.round_id where r.match_id=m.id))::text) from public.matches m where id='$predecessor'") == "$original_facts" ]]
  launch_round friends-resume friends-resume friends "$count" "$count"
  if [[ $count == 3 ]] && integration_selected friends-3-race; then
    echo 'PASS focused three-round actual selection race (original expiry is separately proved; no expiry claim in this unit)'
  fi
  echo "PASS two-process friends $count completion consent relaunch creator-start exclusions immutable predecessor"
done
if integration_selected friends-closure; then
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=true" >/dev/null
  start_pair friends 1
  run_client "$host_simulator" friends-offer friends "$host_email" "$host_password" \
    "$work_dir/friends-1-rollback-offer.log" "" "$match_id" 1 1
  guest_container=$(xcrun simctl get_app_container "$guest_simulator" com.example.GridRace data)
  closure_root="$guest_container/Library/Application Support/GridRaceIntegration"
  rm -f "$closure_root/closure-read-barrier" "$closure_root/closure-read-release"
  run_client "$guest_simulator" friends-close-disabled friends "$guest_email" "$guest_password" \
    "$work_dir/friends-1-rollback-decline.log" "" "$match_id" 1 1 & guest_pid=$!
  closure_ready=0
  for _ in {1..900}; do
    current_container=$(xcrun simctl get_app_container "$guest_simulator" com.example.GridRace data)
    closure_root="$current_container/Library/Application Support/GridRaceIntegration"
    [[ ! -f "$closure_root/closure-read-barrier" ]] || { closure_ready=1; break; }
    sleep 0.1
  done
  [[ $closure_ready == 1 ]] || { echo 'FAIL: real closure request barrier absent' >&2; exit 1; }
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=false" >/dev/null
  current_container=$(xcrun simctl get_app_container "$guest_simulator" com.example.GridRace data)
  touch "$current_container/Library/Application Support/GridRaceIntegration/closure-read-release"
  wait "$guest_pid"; guest_pid=""
  rg -q 'PASS live client explicit decline definitive unavailable' "$work_dir/friends-1-rollback-decline.log"
fi
if integration_selected snapshot-1; then
  [[ $(sql_scalar "select count(*) from cron.job where jobname='gridrace-finalize-rounds' and username=current_user") == 1 ]] || { echo 'REFUSED: unique owned finalizer job absent' >&2; exit 1; }
  cron_job_id=$(sql_scalar "select jobid from cron.job where jobname='gridrace-finalize-rounds' and username=current_user")
  [[ $cron_job_id =~ ^[0-9]+$ ]] || exit 1
  cron_baseline_active=$(sql_scalar "select active from cron.job where jobid=$cron_job_id and username=current_user")
  [[ $cron_baseline_active == t ]] || { echo 'REFUSED: finalizer baseline inactive' >&2; exit 1; }
  printf 'job_id=%s\nowner=current_postgres_role\nbaseline_active=%s\n' "$cron_job_id" "$cron_baseline_active" > "$work_dir/cron-owned-baseline.txt"
  # Arm restoration before dispatch: pause may commit even if its reply is lost.
  cron_paused=1
  sql_scalar "select cron.alter_job($cron_job_id, active:=false)" >/dev/null
  [[ $(sql_scalar "select active from cron.job where jobid=$cron_job_id and username=current_user") == f ]] || exit 1
  start_pair cron 1
  wait_sql "select clock_timestamp()>=ends_at from public.rounds where match_id='$match_id' and round_number=1" t 250
  [[ $(sql_scalar "select state from public.rounds where match_id='$match_id' and round_number=1") == countdown ]]
  launch_round resume resume cron 1 1
  assert_sql_reveal 1 1
  sql_scalar "select cron.alter_job($cron_job_id, active:=true)" >/dev/null
  [[ $(sql_scalar "select active from cron.job where jobid=$cron_job_id and username=current_user") == "$cron_baseline_active" ]] || exit 1
  cron_paused=0
  echo 'PASS original deadline canonical native snapshot-triggered finalization with Cron paused'
fi
if integration_selected friends-signal; then
  sql_scalar "update private.live_feature_configuration set allow_new_rematches=true" >/dev/null
  start_pair friends 1
  signal_container=$(xcrun simctl get_app_container "$host_simulator" com.example.GridRace data)
  signal_root="$signal_container/Library/Application Support/GridRaceIntegration"
  rm -f "$signal_root/rematch-signal-listening"
  run_client "$host_simulator" friends-signal-host friends "$host_email" "$host_password" \
    "$work_dir/friends-rematch-signal-host.log" "" "$match_id" 1 1 & host_pid=$!
  signal_ready=0
  for _ in {1..600}; do
    current_container=$(xcrun simctl get_app_container "$host_simulator" com.example.GridRace data)
    signal_root="$current_container/Library/Application Support/GridRaceIntegration"
    [[ ! -f "$signal_root/rematch-signal-listening" ]] || { signal_ready=1; break; }
    sleep 0.1
  done
  [[ $signal_ready == 1 ]] || { echo 'FAIL: native rematch signal subscription absent' >&2; exit 1; }
  run_client "$guest_simulator" friends-signal-guest friends "$guest_email" "$guest_password" \
    "$work_dir/friends-rematch-signal-guest.log" "" "$match_id" 1 1 & guest_pid=$!
  wait_clients
  rg -q 'PASS live client real native rematch-only Realtime delivery before canonical polling' "$work_dir/friends-rematch-signal-host.log"
  rg -q 'PASS live client dropped reordered real rematch signals canonical closure recovery' "$work_dir/friends-rematch-signal-host.log"
fi
if integration_selected friends-invitation; then
  start_pair invitation 1 invitation-root
  rg -q 'PASS live client actual root signedout profile confirmed Join replacement owner reload clear account transition fences' \
    "$work_dir"/invitation-*-invitation-root-guest.log
fi
if integration_selected backend; then
GRIDRACE_LOCAL_INTEGRATION=1 API_URL="$API_URL" ANON_KEY="$ANON_KEY" \
  SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" DB_URL="$DB_URL" deno run \
  --config supabase/functions/deno.json \
  --allow-env=GRIDRACE_LOCAL_INTEGRATION,API_URL,ANON_KEY,SERVICE_ROLE_KEY,DB_URL \
  --allow-net=127.0.0.1,localhost --allow-run=/opt/homebrew/opt/libpq/bin/psql \
  supabase/tests/integration/live_slice_test.ts >"$work_dir/backend.log" 2>&1
fi
for simulator in ${proof_simulators[@]+"${proof_simulators[@]}"}; do
  container=$(xcrun simctl get_app_container "$simulator" com.example.GridRace data)
  scan_client_credentials "$container" "$SERVICE_ROLE_KEY" "$DB_URL"
done
rg 'PASS live client|INJECTION|Executed [0-9]+ test' "$work_dir"/*.log || true
if [[ $selection_scope == full ]]; then
  echo "PASS real independent-client matrix and reused exact backend standings/races"
else
  echo "PASS focused integration scenarios: $selected_scenarios (full matrix not run)"
fi

run_completed=1
