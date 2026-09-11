# docker-wazuh-syslog-forwarder

Receives remote syslog (UDP/TCP), stores logs to a persistent Docker volume, and forwards them to a Wazuh manager via an in-container Wazuh agent.

## Architecture

Both rsyslog and the Wazuh agent run inside a single container. The Wazuh agent monitors the log directory with a glob pattern and forwards new entries to the manager.


## Configuration

Configuration is split across two files. Copy `.env.example` to `.env` and fill in the values.

**Root `.env`** — shared across all instances (gitignored, not committed):

| Variable | Default | Description |
|---|---|---|
| `WAZUH_VERSION` | `4.14.7` | Agent version — must match the manager |
| `WAZUH_MANAGER` | *(required)* | Hostname or IP of the Wazuh manager |
| `WAZUH_MANAGER_PORT` | `1514` | Agent communication port |
| `WAZUH_PROTOCOL` | `tcp` | Agent protocol (`tcp` or `udp`) |
| `WAZUH_REGISTRATION_SERVER` | `WAZUH_MANAGER` | Enrollment server (if different from manager) |
| `WAZUH_REGISTRATION_PORT` | `1515` | Enrollment port |
| `WAZUH_REGISTRATION_PASSWORD` | *(unset)* | Enrollment password |
| `WAZUH_KEEP_ALIVE_INTERVAL` | `10` | Seconds between manager keep-alive checks |
| `WAZUH_TIME_RECONNECT` | `60` | Seconds before reconnect attempt |
| `WAZUH_REGISTRATION_CA` | *(unset)* | CA cert path inside the container |
| `WAZUH_REGISTRATION_CERTIFICATE` | *(unset)* | Agent cert path inside the container |
| `WAZUH_REGISTRATION_KEY` | *(unset)* | Agent key path inside the container |

**`instances/<name>/.env`** — per-instance settings:

| Variable | Description |
|---|---|
| `SYSLOG_PORT` | Host port to receive syslog on (must be unique per instance) |
| `WAZUH_AGENT_NAME` | Agent name shown in the Wazuh dashboard (must be unique per instance) |
| `WAZUH_AGENT_GROUP` | Optional: comma-separated Wazuh group names |
| `WAZUH_AGENT_KEY` | Optional: pre-registered agent key — skips auto-enrollment if set |
| `WAZUH_AGENT_LABELS` | Optional: extra fields added to every event from this container, `key=value,key2=value2` — appear as `agent.labels.*` in alerts. Dot-separated keys nest (`device.type` → `agent.labels.device.type`) |

**`instances/<name>/rsyslog.d/`** — optional per-instance rsyslog config directory. If present, `spawn.sh` mounts it over `/etc/rsyslog.d/` in the container, replacing the shared default. If absent, the shared `config/rsyslog.d/` is used. See `instances/example/rsyslog.d/remote.conf` for the default as a starting point.

> When using a local Wazuh manager running in Docker, set `WAZUH_MANAGER=wazuh-manager` — the compose file maps that hostname to the host's bridge gateway via `extra_hosts`. For remote managers set the hostname or IP directly.

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

**4. Run a Compose command across all instances at once:**

```bash
./spawn.sh all up -d     # start every instance
./spawn.sh all down      # stop every instance
./spawn.sh all pull      # pull updated images for all instances
```

The `all` target discovers every folder under `instances/` that contains a `.env` file, skipping the `example` template.

**Example: two instances running side by side**

`.env` (root, shared):
```
WAZUH_VERSION=4.14.7
WAZUH_MANAGER=wazuh.example.com
WAZUH_MANAGER_PORT=1514
WAZUH_REGISTRATION_PORT=1515
WAZUH_REGISTRATION_PASSWORD=secret
WAZUH_PROTOCOL=tcp
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
WAZUH_AGENT_GROUP=corp,linux
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

## License

This project is licensed under the **Business Source License 1.1** (BUSL-1.1).

- Free to use for personal/non-commercial use, non-profit organizations, and customers of iSecNG GmbH under a current service agreement.
- Commercial use by other entities requires a separate license.
- On **2030-05-05** the license converts to the **Apache License 2.0**.

See [LICENSE](LICENSE) for the full terms or contact [sales@isecng.de](mailto:sales@isecng.de) for commercial licensing.

## Credits

This project builds on the following open-source software:

- **[Wazuh](https://wazuh.com/)** — open-source security platform providing the agent used to forward logs to the Wazuh manager. Licensed under the GNU General Public License v2.0.
- **[rsyslog](https://www.rsyslog.com/)** — high-performance syslog processing daemon used to receive and store incoming log messages. Licensed under the GNU General Public License v3.0 / Apache License 2.0 (dual-licensed).
- **[Ubuntu](https://ubuntu.com/)** — base container image. Trademarks of Canonical Ltd.
- **[Docker](https://www.docker.com/)** — container runtime and Compose tooling used for deployment.

Claude was partly used to create / test / quality assure this project. Every line of code was at least double-checked by a human.
