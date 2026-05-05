# docker-wazuh-syslog-forwarder

Receives remote syslog (UDP/TCP), stores logs to a persistent Docker volume, and forwards them to a Wazuh manager via an in-container Wazuh agent.

## Architecture

Both rsyslog and the Wazuh agent run inside a single container. The Wazuh agent monitors the log directory with a glob pattern and forwards new entries to the manager.


## Configuration

Environment variables for the `syslog-forwarder` service:

| Variable | Default | Description |
|---|---|---|
| `WAZUH_MANAGER` | *(required)* | Hostname or IP of the Wazuh manager |
| `WAZUH_MANAGER_PORT` | `1514` | Wazuh agent connection port |
| `WAZUH_AGENT_NAME` | `syslog-forwarder` | Agent name shown in the Wazuh dashboard |
| `WAZUH_AGENT_KEY` | *(unset)* | Pre-registered agent key — skips auto-enrollment if set |

The default `docker-compose.yml` uses `extra_hosts: wazuh-manager:host-gateway` so the container reaches the host's Wazuh manager without host networking.

## Usage

### Build and start

```bash
docker compose build
docker compose up -d
```

On first start the Wazuh agent auto-enrolls with the manager (takes ~20-30 seconds). Watch the logs:

```bash
docker compose logs -f syslog-forwarder
```

### Send test syslog messages

```bash
# UDP (default)
python3 test/send_syslog.py --host 127.0.0.1 --port 5514 --count 10 --hostname my-firewall

# TCP
python3 test/send_syslog.py --host 127.0.0.1 --port 5514 --proto tcp --count 5 --hostname my-switch

# All options
python3 test/send_syslog.py --help
```

### Verify log storage

```bash
# List log files in the volume
docker compose exec syslog-forwarder find /var/log/remote -type f

# Read a specific host's log
docker compose exec syslog-forwarder cat /var/log/remote/my-firewall/$(date +%Y-%m-%d).log
```

Log files are organized as `/var/log/remote/<HOSTNAME>/<YYYY-MM-DD>.log`. New hostname directories are picked up by the Wazuh agent within ~60 seconds without a restart.

### Verify forwarding to Wazuh

In the Wazuh dashboard go to **Security Events** and filter by `agent.name: syslog-forwarder`. Events should appear within 30-60 seconds of log files being written.

### Deploy test decoder and rules

The `test/` directory includes a Wazuh decoder and matching rules for messages sent by `send_syslog.py`. Decoders and rules run on the manager, not the agent.

```bash
docker cp test/decoder_test_syslog.xml single-node-wazuh.manager-1:/var/ossec/etc/decoders/
docker cp test/rules_test_syslog.xml single-node-wazuh.manager-1:/var/ossec/etc/rules/
docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control restart
```

| Rule ID | Level | Triggered when |
|---|---|---|
| 100100 | 3 | Tag `test` with a custom `--message` |
| 100101 | 3 | Default message, `--count 1` |
| 100102 | 3 | Default message, `--count N>1` (description includes N/M counter) |

### Stop and clean up

```bash
docker compose down           # stop containers, keep volume
docker compose down -v        # stop containers and delete log volume
```
