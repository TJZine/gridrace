#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/scan_client_credentials.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
service_key='fixture-service-key-[literal]'
db_url='postgresql://fixture:private@localhost/example'
mkdir -p "$work_dir/container/.hidden" "$work_dir/scanner"
printf 'ignored\n' > "$work_dir/container/.ignore"

check_scan() {
  local expected=$1 output status
  if output=$(scan_client_credentials "$work_dir/container" "$service_key" "$db_url" 2>&1 && echo 'PASS final success'); then
    status=0
  else
    status=$?
  fi
  [[ ( -z "$service_key" || $output != *"$service_key"* ) && $output != *"$db_url"* ]] || {
    echo 'FAIL: credential escaped diagnostic output' >&2; exit 1;
  }
  if [[ $expected == clean ]]; then
    [[ $status == 0 && $output == 'PASS final success' ]]
  else
    [[ $status != 0 && $output != *'PASS final success'* ]]
  fi
}

printf 'ordinary data\n' > "$work_dir/container/data"
check_scan clean
printf '%s\n' "$service_key" > "$work_dir/container/.hidden/data"
check_scan failure
rm "$work_dir/container/.hidden/data"
printf '%s\n' "$db_url" > "$work_dir/container/ignored"
check_scan failure
rm "$work_dir/container/ignored"
# A substring that would match the service key as a regex must remain clean.
printf 'fixture-service-key-l\n' > "$work_dir/container/data"
check_scan clean

cat > "$work_dir/scanner/rg" <<'SCANNER'
#!/bin/bash
IFS= read -r credential
echo "$credential" >&2
exit 2
SCANNER
chmod +x "$work_dir/scanner/rg"
original_path=$PATH
PATH="$work_dir/scanner:$PATH" check_scan failure
# No rg executable; the shell's diagnostic must also remain private.
rm "$work_dir/scanner/rg"
PATH="$work_dir/scanner" check_scan failure
PATH=$original_path
service_key=''
check_scan failure
echo 'PASS client credential scan: clean, both matches, hidden/ignored, fixed strings, errors and unavailable scanner'
