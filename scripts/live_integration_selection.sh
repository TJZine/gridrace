#!/usr/bin/env bash
# Pure admission parser: no runtime commands, credentials or fixture mutations.
integration_scenarios=(deletion-receipt daily product-1 product-3 product-5 mixed-3 cron-1 cron-3 deletion-1 deletion-3 friends-1 friends-3 friends-5 snapshot-1 friends-signal friends-invitation friends-closure friends-3-race backend)
integration_client_log_basename() {
  # scenario, count, pair sequence, match phase, round, role, process
  printf '%s-%s-pair%s-%s-round%s-%s-%s.log' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}
integration_selected() {
  [[ ,$selected_scenarios, == *,$1,* ]]
}
integration_has_live_scenarios() {
  local name
  for name in product-1 product-3 product-5 mixed-3 cron-1 cron-3 deletion-1 deletion-3 friends-1 friends-3 friends-5 snapshot-1 friends-signal friends-invitation friends-closure friends-3-race; do
    integration_selected "$name" && return 0
  done
  return 1
}
integration_has_native_scenarios() {
  local name
  for name in "${integration_scenarios[@]}"; do
    [[ $name == backend ]] || { integration_selected "$name" && return 0; }
  done
  return 1
}
parse_integration_selection() {
  selection_action=run
  selection_scope=full
  selected_scenarios=$(IFS=,; echo "${integration_scenarios[*]}")
  case ${1:-} in
    --help|--list-scenarios)
      [[ $# == 1 ]] || { echo 'REFUSED: help/list takes no other arguments' >&2; return 2; }
      selection_action=info
      if [[ $1 == --help ]]; then
        echo 'Usage: bash scripts/run_live_match_integration.sh [--scenarios NAME[,NAME...]]'
        echo 'Omitted selection runs the full matrix. --list-scenarios lists names.'
        echo 'Requires controller-owned unlinked loopback stack, frozen packages and disposable fixtures; see scripts/LOCAL_INTEGRATION.md.'
      else
        printf '%s\n' "${integration_scenarios[@]}"
      fi
      return 0
      ;;
    '') [[ $# == 0 ]] || return 2; return 0 ;;
    --scenarios)
      [[ $# == 2 && -n $2 ]] || { echo 'REFUSED: --scenarios requires one nonempty comma-separated selection' >&2; return 2; }
      ;;
    *) echo 'REFUSED: unknown integration argument' >&2; return 2 ;;
  esac
  [[ $2 =~ ^[a-z0-9,-]+$ ]] || { echo 'REFUSED: invalid scenario characters' >&2; return 2; }
  local name known candidate seen=,
  local -a names
  [[ $2 != ,* && $2 != *, && $2 != *,,* ]] || { echo 'REFUSED: empty scenario name' >&2; return 2; }
  IFS=, read -r -a names <<< "$2"
  for name in "${names[@]}"; do
    known=0
    for candidate in "${integration_scenarios[@]}"; do
      [[ $name != "$candidate" ]] || known=1
    done
    [[ $known == 1 && $seen != *,$name,* ]] || { echo 'REFUSED: unknown or duplicate scenario name' >&2; return 2; }
    seen+="$name,"
  done
  selected_scenarios=$2
  selection_scope=focused
}
