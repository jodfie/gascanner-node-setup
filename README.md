# GaScanner Node Bootstrap

Bootstrap tooling for GaScanner trunk-recorder nodes. This repo is the canonical node setup repo: it provisions a remote Ubuntu/Raspberry Pi scanner node, points it at the central GaScanner VPS, and documents the current VPS architecture that the node feeds.

The application source checkouts (`tr-engine`, `tr-dashboard`, and `ThinLineRadio`) stay outside this repo. This repo keeps node bootstrap, node docs, and VPS reference material only.

## Current Architecture

```
Remote node
  SDR hardware
  trunk-recorder + MQTT plugin
  Uptime Kuma push heartbeats
       |
       | MQTT audio, metadata, units, recorder stats
       v
GaScanner VPS: mqtt.georgiascanner.live
  Bare-metal Mosquitto on TCP 1883
       |
       +--> ThinLine Radio + PostgreSQL
       |    https://thinline.georgiascanner.live
       |
       +--> tr-engine + PostgreSQL
            https://trengine.georgiascanner.live
            https://trdash.georgiascanner.live via tr-dashboard

Ingress and operations:
  Traefik v3 + Cloudflare Tunnel
  Uptime Kuma + AutoKuma
  Dashy homepage
  Dozzle over admin access
  Tailscale for administration
```

### Live VPS Services

| Service | Access | Role |
|---------|--------|------|
| Mosquitto | `mqtt.georgiascanner.live:1883` | Bare-metal MQTT broker for trunk-recorder nodes |
| ThinLine Radio | `https://thinline.georgiascanner.live` | Primary scanner playback, users, alerts |
| TG Manager | `https://tgmanager.georgiascanner.live` | ThinLine talkgroup management UI |
| tr-engine | `https://trengine.georgiascanner.live` | Analytics/API backend consuming the MQTT stream |
| tr-dashboard | `https://trdash.georgiascanner.live` | Real-time monitoring dashboard backed by tr-engine |
| RDIO Scanner | Docker legacy service | Compatibility service, not the primary ingest path |
| Uptime Kuma | `https://uptime.georgiascanner.live` | Health checks and node push monitors |
| AutoKuma | internal | Creates Kuma monitors from Docker labels |
| Dashy | `https://home.georgiascanner.live` | Service homepage |
| Traefik | `https://traefik.georgiascanner.live` | Reverse proxy dashboard |
| Cloudflared | internal | Cloudflare tunnel to Traefik |
| Dozzle | `:8080` / admin access | Docker logs |

See [VPS Architecture](docs/vps-architecture.md) for deployment paths, Docker networks, and routing details.

## Supported Counties

All counties are part of the Southeast Georgia Regional Radio Network (SEGARRN) P25 system.

| County | Short Name | Major City | Bootstrap Status |
|--------|------------|------------|------------------|
| Chatham | `chatham` | Savannah | Active |
| Bryan | `bryan` | Richmond Hill | Ready |
| Bulloch | `bulloch` | Statesboro | Ready |
| Candler | `candler` | Metter | Ready |
| Effingham | `effingham` | Springfield | Ready |
| Emanuel | `emanuel` | Swainsboro | Ready |
| Glynn | `glynn` | Brunswick | Ready |
| Liberty | `liberty` | Hinesville | Ready |
| Long | `long` | Ludowici | Ready |
| McIntosh | `mcintosh` | Darien | Ready |

The county config files in `configs/<county>/system.conf` are bootstrap defaults. Verify control channels for the exact receiver location before starting a node.

## Prerequisites

- Ubuntu 22.04 LTS or 24.04 LTS
- SDR hardware connected to the node (RTL-SDR, Airspy, HackRF, etc.)
- Internet connection
- MQTT credentials from the GaScanner admin
- Three Uptime Kuma push monitor tokens from the GaScanner admin
- Talkgroup CSV for the county or system being monitored

## Quick Start

```bash
git clone https://github.com/jodfie/gascanner-node-setup.git
cd gascanner-node-setup
sudo ./scripts/setup.sh
```

The setup script asks for the county, hostname, MQTT credentials, SDR type, control channels, and three Uptime Kuma push tokens.

## What The Bootstrap Does

1. Installs node dependencies, Docker, SDR tools, and udev rules.
2. Blacklists DVB drivers that conflict with RTL-SDR devices.
3. Creates `/home/<user>/trunk_recorder/`.
4. Generates `docker-compose.yml` using `thegreatcodeholio/trunk-recorder-mqtt:RC5.0_organized`.
5. Generates `tr_config/config.json` with the MQTT plugin enabled.
6. Installs a one-minute heartbeat script for the three required Kuma push monitors.
7. Creates a `trunk-recorder.service` systemd unit.

Generated node layout:

```text
~/trunk_recorder/
|-- docker-compose.yml
|-- tr_config/
|   |-- config.json
|   |-- talkgroups.csv
|   `-- units.csv
|-- tr_audio/
`-- tr_logs/
```

## Required Admin Inputs

Ask the GaScanner admin for:

- MQTT username and password, usually following `tr_<county>`
- Three Uptime Kuma push tokens:
  - node/system heartbeat
  - trunk-recorder container heartbeat
  - transmission activity heartbeat
- `talkgroups.csv` for the county or monitored system
- Any site-specific control channel updates

## Operations

Start or update trunk-recorder:

```bash
cd ~/trunk_recorder
docker compose pull
docker compose up -d
```

Check logs:

```bash
docker logs -f trunk_recorder
```

Test MQTT from a node:

```bash
mosquitto_pub -h mqtt.georgiascanner.live -p 1883 \
  -u "tr_COUNTY" -P "YOUR_PASSWORD" \
  -t "test/node" -m "hello"
```

## Documentation

- [Manual Setup](docs/manual-setup.md)
- [VPS Architecture](docs/vps-architecture.md)
- [MQTT](docs/mqtt.md)
- [Monitoring](docs/monitoring.md)
- [Consolidation Notes](docs/consolidation-notes.md)

## Not In This Bootstrap

The following are not part of node provisioning:

- Building or deploying `tr-engine`
- Building or deploying `tr-dashboard`
- Building or deploying `ThinLineRadio`
- Managing live server secrets
- Vendoring nested app repos into this bootstrap repo

RDIO Scanner still exists on the VPS as a Docker legacy/compatibility service, but new trunk-recorder nodes should feed Mosquitto for ThinLine Radio and tr-engine.

## License

MIT License - see [LICENSE](LICENSE).
