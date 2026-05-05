# docker-wazuh-syslog-forwarder

Receives remote syslog (UDP/TCP), stores logs to a persistent Docker volume, and forwards them to a Wazuh manager via an in-container Wazuh agent.

## Architecture

Both rsyslog and the Wazuh agent run inside a single container. The Wazuh agent monitors the log directory with a glob pattern and forwards new entries to the manager.


## Configuration

Configuration is split across two files:

**Root `.env`** — shared across all instances (gitignored, not committed):

| Variable | Description |
|---|---|
| `WAZUH_MANAGER` | Hostname or IP of the Wazuh manager |
| `WAZUH_MANAGER_PORT` | Wazuh agent connection port (default: `1514`) |

**`instances/<name>/.env`** — per-instance settings:

| Variable | Description |
|---|---|
| `SYSLOG_PORT` | Host port to receive syslog on (must be unique per instance) |
| `WAZUH_AGENT_NAME` | Agent name shown in the Wazuh dashboard (must be unique per instance) |
| `WAZUH_AGENT_KEY` | Optional: pre-registered agent key — skips auto-enrollment if set |

**`instances/<name>/rsyslog.d/`** — optional per-instance rsyslog config directory. If present, `spawn.sh` mounts it over `/etc/rsyslog.d/` in the container, replacing the shared default. If absent, the shared `config/rsyslog.d/` is used. See `instances/example/rsyslog.d/remote.conf` for the default as a starting point.

The default `docker-compose.yml` uses `extra_hosts: wazuh-manager:host-gateway` so the container reaches the host's Wazuh manager without host networking.

## Usage

### Single instance

```bash
docker compose build
docker compose up -d
docker compose logs -f syslog-forwarder
```

### Multiple instances in parallel

Each instance lives in its own directory under `instances/`. The `spawn.sh` wrapper sets the Compose project name and env file, so every instance gets an isolated port, agent name, and volume.

**1. Create an instance config:**

```bash
cp -r instances/example instances/my-instance
# edit instances/my-instance/.env — set a unique SYSLOG_PORT and WAZUH_AGENT_NAME
# optionally edit instances/my-instance/rsyslog.d/remote.conf for custom syslog handling
# or remove instances/my-instance/rsyslog.d/ entirely to use the shared default
```

**2. Start it:**

```bash
./spawn.sh my-instance up -d
```

**3. Run any Compose command against a specific instance:**

```bash
./spawn.sh my-instance logs -f
./spawn.sh my-instance down
./spawn.sh my-instance down -v   # also removes the volume
```

**Example: two instances running side by side**

`.env` (root, shared):
```
WAZUH_MANAGER=wazuh-manager
WAZUH_MANAGER_PORT=1514
```

`instances/dmz/.env`:
```
SYSLOG_PORT=5514
WAZUH_AGENT_NAME=syslog-dmz
```

`instances/corp/.env`:
```
SYSLOG_PORT=5515
WAZUH_AGENT_NAME=syslog-corp
```

```bash
./spawn.sh dmz up -d
./spawn.sh corp up -d
```

Each instance gets its own Docker volume (`syslog-dmz_syslog_remote_logs`, `syslog-corp_syslog_remote_logs`) and appears as a separate agent in the Wazuh dashboard.

> The root `.env` + `docker compose` (no `spawn.sh`) still works for a single default instance.

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
