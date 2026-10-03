#!/usr/bin/env bash
# Sourced by the integration harness and its isolated regression check.
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
    # Patterns arrive on stdin, outside process arguments. Search hidden/ignored
    # files too; neither matching content nor scanner diagnostics may escape.
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
