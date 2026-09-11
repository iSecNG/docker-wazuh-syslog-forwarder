#!/usr/bin/env bash
set -euo pipefail

: "${WAZUH_MANAGER:?ERROR: WAZUH_MANAGER env var must be set}"

WAZUH_MANAGER_PORT="${WAZUH_MANAGER_PORT:-1514}"
WAZUH_PROTOCOL="${WAZUH_PROTOCOL:-tcp}"
WAZUH_REGISTRATION_SERVER="${WAZUH_REGISTRATION_SERVER:-${WAZUH_MANAGER}}"
WAZUH_REGISTRATION_PORT="${WAZUH_REGISTRATION_PORT:-1515}"
WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-syslog-forwarder}"
WAZUH_KEEP_ALIVE_INTERVAL="${WAZUH_KEEP_ALIVE_INTERVAL:-10}"
WAZUH_TIME_RECONNECT="${WAZUH_TIME_RECONNECT:-60}"

OSSEC_CONF="/var/ossec/etc/ossec.conf"

# Required substitutions
sed -i "s|WAZUH_MANAGER_ADDR|${WAZUH_MANAGER}|g"                     "$OSSEC_CONF"
sed -i "s|WAZUH_MANAGER_PORT_VAL|${WAZUH_MANAGER_PORT}|g"            "$OSSEC_CONF"
sed -i "s|WAZUH_PROTOCOL_VAL|${WAZUH_PROTOCOL}|g"                    "$OSSEC_CONF"
sed -i "s|WAZUH_REGISTRATION_SERVER_VAL|${WAZUH_REGISTRATION_SERVER}|g" "$OSSEC_CONF"
sed -i "s|WAZUH_REGISTRATION_PORT_VAL|${WAZUH_REGISTRATION_PORT}|g"  "$OSSEC_CONF"
sed -i "s|WAZUH_AGENT_NAME_VAL|${WAZUH_AGENT_NAME}|g"                "$OSSEC_CONF"
sed -i "s|WAZUH_KEEP_ALIVE_VAL|${WAZUH_KEEP_ALIVE_INTERVAL}|g"       "$OSSEC_CONF"
sed -i "s|WAZUH_TIME_RECONNECT_VAL|${WAZUH_TIME_RECONNECT}|g"        "$OSSEC_CONF"

# Optional: agent group
if [ -n "${WAZUH_AGENT_GROUP:-}" ]; then
  sed -i "s|WAZUH_AGENT_GROUP_VAL|${WAZUH_AGENT_GROUP}|g" "$OSSEC_CONF"
else
  sed -i "/<groups>WAZUH_AGENT_GROUP_VAL<\/groups>/d" "$OSSEC_CONF"
fi

# Optional: custom labels — "key=value,key2=value2" → <label key="key">value</label>
# Labels are attached to every event this agent sends and show up as agent.labels.*
if [ -n "${WAZUH_AGENT_LABELS:-}" ]; then
  : > /tmp/labels.xml
  printf '%s\n' "${WAZUH_AGENT_LABELS}" | tr ',' '\n' | while IFS='=' read -r key value; do
    key="${key//[[:space:]]/}"
    value="${value# }"; value="${value% }"
    [ -n "$key" ] || continue
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    printf '    <label key="%s">%s</label>\n' "$key" "$value" >> /tmp/labels.xml
  done
  sed -i -e "/WAZUH_AGENT_LABELS_VAL/r /tmp/labels.xml" -e "/WAZUH_AGENT_LABELS_VAL/d" "$OSSEC_CONF"
  rm -f /tmp/labels.xml
else
  sed -i "/<labels>/,/<\/labels>/d" "$OSSEC_CONF"
fi

# Optional: enrollment password — written to the file ossec.conf references
if [ -n "${WAZUH_REGISTRATION_PASSWORD:-}" ]; then
  echo "${WAZUH_REGISTRATION_PASSWORD}" > /var/ossec/etc/enrollment-pass
  chmod 640 /var/ossec/etc/enrollment-pass
  chown root:wazuh /var/ossec/etc/enrollment-pass
else
  sed -i "/<authorization_pass_path>/d" "$OSSEC_CONF"
fi

# Optional: SSL certificates — remove elements if paths not provided
if [ -n "${WAZUH_REGISTRATION_CA:-}" ]; then
  sed -i "s|WAZUH_REGISTRATION_CA_VAL|${WAZUH_REGISTRATION_CA}|g" "$OSSEC_CONF"
else
  sed -i "/<server_ca_path>WAZUH_REGISTRATION_CA_VAL<\/server_ca_path>/d" "$OSSEC_CONF"
fi

if [ -n "${WAZUH_REGISTRATION_CERTIFICATE:-}" ]; then
  sed -i "s|WAZUH_REGISTRATION_CERTIFICATE_VAL|${WAZUH_REGISTRATION_CERTIFICATE}|g" "$OSSEC_CONF"
else
  sed -i "/<agent_certificate_path>WAZUH_REGISTRATION_CERTIFICATE_VAL<\/agent_certificate_path>/d" "$OSSEC_CONF"
fi

if [ -n "${WAZUH_REGISTRATION_KEY:-}" ]; then
  sed -i "s|WAZUH_REGISTRATION_KEY_VAL|${WAZUH_REGISTRATION_KEY}|g" "$OSSEC_CONF"
else
  sed -i "/<agent_key_path>WAZUH_REGISTRATION_KEY_VAL<\/agent_key_path>/d" "$OSSEC_CONF"
fi

# Pre-registered key overrides auto-enrollment
if [ -n "${WAZUH_AGENT_KEY:-}" ]; then
  echo "Importing pre-registered agent key..."
  echo "${WAZUH_AGENT_KEY}" | /var/ossec/bin/manage_agents -i
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
