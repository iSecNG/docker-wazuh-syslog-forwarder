#!/usr/bin/env bash
set -euo pipefail

: "${WAZUH_MANAGER:?ERROR: WAZUH_MANAGER env var must be set}"
WAZUH_MANAGER_PORT="${WAZUH_MANAGER_PORT:-1514}"
WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-syslog-forwarder}"

OSSEC_CONF="/var/ossec/etc/ossec.conf"

sed -i "s|WAZUH_MANAGER_ADDR|${WAZUH_MANAGER}|g"          "$OSSEC_CONF"
sed -i "s|WAZUH_MANAGER_PORT_VAL|${WAZUH_MANAGER_PORT}|g" "$OSSEC_CONF"
sed -i "s|WAZUH_AGENT_NAME_VAL|${WAZUH_AGENT_NAME}|g"     "$OSSEC_CONF"

if [ -n "${WAZUH_AGENT_KEY:-}" ]; then
  echo "Importing pre-registered agent key..."
  echo "${WAZUH_AGENT_KEY}" | /var/ossec/bin/manage_agents -i
  # Disable auto-enrollment since we have a key
  sed -i 's|<enabled>yes</enabled>|<enabled>no</enabled>|' "$OSSEC_CONF"
else
  echo "No WAZUH_AGENT_KEY set — using auto-enrollment via ossec.conf"
fi

mkdir -p /var/log/remote
chown syslog:adm /var/log/remote
chmod 755 /var/log/remote

RSYSLOG_PID=""

cleanup() {
  echo "Shutting down..."
  /var/ossec/bin/wazuh-control stop 2>/dev/null || true
  [ -n "$RSYSLOG_PID" ] && kill "$RSYSLOG_PID" 2>/dev/null || true
  wait
}
trap cleanup SIGTERM SIGINT

echo "Starting Wazuh agent..."
/var/ossec/bin/wazuh-control start

echo "Starting rsyslog..."
rsyslogd -n &
RSYSLOG_PID=$!

wait $RSYSLOG_PID
