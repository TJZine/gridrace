#!/usr/bin/env bash
scan_client_credentials() {
  local container=$1 credential scan_status
  shift
  if [[ ! -d "$container" || $# != 2 ]]; then
    echo "FAIL: client credential scan inputs are unavailable" >&2
    return 1
  fi
  for credential in "$@"; do
    if [[ -z "$credential" ]]; then
      echo "FAIL: client credential scan inputs are unavailable" >&2
      return 1
    fi
    if command rg --no-config --hidden --no-ignore -a -q --fixed-strings -f - \
      -- "$container" <<< "$credential" >/dev/null 2>&1; then
      echo "FAIL: privileged credential found in client container" >&2
      return 1
    else
      scan_status=$?
      if [[ $scan_status != 1 ]]; then
        echo "FAIL: client credential scan could not complete" >&2
        return 1
      fi
    fi
  done
}
