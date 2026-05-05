#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?Usage: $0 <instance-name> [compose-command ...]}"
ENV_FILE="instances/${INSTANCE}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: ${ENV_FILE} not found."
  echo "Copy instances/example/.env to instances/${INSTANCE}/.env and edit it."
  exit 1
fi

shift

# Load central config first, then instance config (instance vars take precedence)
set -a
# shellcheck source=/dev/null
source .env
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Use instance-specific rsyslog config if present, otherwise fall back to shared default
if [ -d "instances/${INSTANCE}/rsyslog.d" ]; then
  export RSYSLOG_CONFIG_DIR="instances/${INSTANCE}/rsyslog.d"
else
  export RSYSLOG_CONFIG_DIR="config/rsyslog.d"
fi

exec docker compose --project-name "syslog-${INSTANCE}" "$@"
