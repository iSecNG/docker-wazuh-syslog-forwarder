#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_instance() {
  local instance="$1"
  shift
  local env_file="${SCRIPT_DIR}/instances/${instance}/.env"

  if [ ! -f "$env_file" ]; then
    echo "ERROR: ${env_file} not found."
    echo "Copy instances/example/.env to instances/${instance}/.env and edit it."
    exit 1
  fi

  # Load central config first, then instance config (instance vars take precedence)
  set -a
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/.env"
  # shellcheck source=/dev/null
  source "$env_file"
  set +a

  # Use instance-specific rsyslog config if present, otherwise fall back to shared default
  if [ -d "${SCRIPT_DIR}/instances/${instance}/rsyslog.d" ]; then
    export RSYSLOG_CONFIG_DIR="${SCRIPT_DIR}/instances/${instance}/rsyslog.d"
  else
    export RSYSLOG_CONFIG_DIR="${SCRIPT_DIR}/config/rsyslog.d"
  fi

  docker compose \
    --project-directory "$SCRIPT_DIR" \
    --project-name "syslog-${instance}" \
    "$@"
}

all_instances() {
  local instances=()
  for dir in "${SCRIPT_DIR}/instances"/*/; do
    local name
    name="$(basename "$dir")"
    [ "$name" = "example" ] && continue
    [ -f "${dir}.env" ] || continue
    instances+=("$name")
  done

  if [ ${#instances[@]} -eq 0 ]; then
    echo "No instances found in instances/ (excluding example)."
    exit 0
  fi

  echo "Running '$*' for instances: ${instances[*]}"
  for instance in "${instances[@]}"; do
    echo "--- ${instance} ---"
    run_instance "$instance" "$@"
  done
}

COMMAND="${1:?Usage: $0 <instance-name|all> [compose-command ...]}"
shift

if [ "$COMMAND" = "all" ]; then
  all_instances "$@"
else
  run_instance "$COMMAND" "$@"
fi
