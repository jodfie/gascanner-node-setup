# VPS Architecture Reference

This is the current GaScanner VPS reference for node operators and maintainers. The bootstrap repo uses this document to describe the system that remote trunk-recorder nodes feed; it is not the deployment source for the application containers.

## Server Identity

| Item | Value |
|------|-------|
| Hostname | `mqtt.georgiascanner.live` |
| Public IPv4 | `209.145.49.25` |
| Time zone | `America/New_York` |
| Primary node ingest | MQTT on TCP `1883` |

## Live Service Inventory

Verified on the server on 2026-05-05.

| Service | Container / process | Access | Purpose |
|---------|---------------------|--------|---------|
| Mosquitto | bare metal systemd service | `mqtt.georgiascanner.live:1883` | MQTT broker for trunk-recorder nodes |
| Traefik | `traefik` | `80`, `443`, `traefik.georgiascanner.live` | Reverse proxy and TLS |
| Cloudflared | `cloudflared` | internal tunnel | Cloudflare Tunnel into Traefik |
| ThinLine Radio | `thinline-radio` | `thinline.georgiascanner.live`, local `25915` | Primary scanner playback and user-facing radio UI |
| ThinLine PostgreSQL | `thinline-radio-db` | Docker networks only | ThinLine database |
| TG Manager | `tg-dashboard` | `tgmanager.georgiascanner.live`, local `25916` | ThinLine talkgroup management UI |
| tr-engine | `tr-engine` | `trengine.georgiascanner.live`, local `8070` | Analytics API, MQTT consumer, audio API |
| tr-engine PostgreSQL | `tr-engine-db` | Docker networks only | tr-engine database |
| tr-dashboard | `tr-dashboard` | `trdash.georgiascanner.live` | Monitoring dashboard backed by tr-engine |
| RDIO Scanner | `rdio-scanner` | `scanner.georgiascanner.live`, local `25913` | Legacy/compatibility scanner service |
| RDIO MariaDB | `rdio-scanner-db` | Docker network only | RDIO database |
| Uptime Kuma | `uptimekuma` | `uptime.georgiascanner.live`, local `3001` | Health monitoring |
| AutoKuma | `autokuma` | internal | Creates Kuma monitors from Docker labels |
| Dashy | `gascanner-dashboard` | `home.georgiascanner.live`, local `25914` | Service homepage |
| Dozzle | `dozzle` | local `8080` / admin access | Docker logs |
| Tailscale | bare metal systemd service | tailnet only | Admin access |

## Runtime Paths

| Stack | Compose file | Notes |
|-------|--------------|-------|
| Traefik + Cloudflared | `/home/adminlocal/.docker/traefik/docker-compose.yml` | Traefik config is bind-mounted from `/home/adminlocal/.config/appdata/traefik/` |
| Monitoring | `/home/adminlocal/.docker/compose/docker-compose.yml` | Uptime Kuma, AutoKuma, Dozzle |
| ThinLine Radio | `/home/adminlocal/.docker/thinline-radio/docker-compose.yml` | Builds from `/home/adminlocal/ThinLineRadio` |
| tr-engine + tr-dashboard | `/home/adminlocal/.docker/tr-engine/docker-compose.yml` | Builds from `/home/adminlocal/trunk-reporter/tr-engine` and `/home/adminlocal/trunk-reporter/tr-dashboard` |
| RDIO Scanner | `/home/adminlocal/.docker/rdio-scanner-docker/docker-compose.yml` | Legacy/compatibility service |
| Dashy | `/home/adminlocal/.docker/dashy/docker-compose.yml` | Dashboard config is under `/home/adminlocal/.config/dashy/` |

Persistent app data is stored under `/home/adminlocal/.config/appdata/` where practical. Legacy Docker volumes are still used by RDIO Scanner.

## Network Architecture

```
Internet
  |
  v
Cloudflare DNS + Cloudflare Tunnel
  |
  v
Traefik on compose_default
  |
  +-- thinline.georgiascanner.live  -> thinline-radio:3000
  +-- tgmanager.georgiascanner.live -> tg-dashboard:80
  +-- trengine.georgiascanner.live  -> tr-engine:8080
  +-- trdash.georgiascanner.live    -> tr-dashboard:3000
  |                                  -> /api, /audio, /health proxied to tr-engine:8080
  +-- scanner.georgiascanner.live   -> rdio-scanner:3000
  +-- uptime.georgiascanner.live    -> uptimekuma:3001
  +-- home.georgiascanner.live      -> gascanner-dashboard:8080
```

Docker networks:

| Network | Purpose |
|---------|---------|
| `compose_default` | Shared proxy/operations network used by Traefik and public services |
| `tr-net` | tr-engine, tr-dashboard, and tr-engine PostgreSQL |
| `thinline-net` | ThinLine Radio, TG Manager, and ThinLine PostgreSQL |
| `rdio-scanner_network` | RDIO Scanner and MariaDB |

## MQTT Data Flow

```
trunk-recorder node
  publishes trunk_recorder/# over MQTT
       |
       v
Mosquitto on mqtt.georgiascanner.live:1883
       |
       +-- ThinLine Radio subscribes for scanner playback/storage
       |
       +-- tr-engine subscribes for analytics, units, talkgroups, audio API
```

The broker is a bare-metal systemd service, not a Docker container. Docker services reach it through `host.docker.internal` from their compose files.

Recommended trunk-recorder MQTT plugin topic roots:

| Plugin field | Value |
|--------------|-------|
| `topic` | `trunk_recorder/feeds` |
| `unit_topic` | `trunk_recorder/units` |
| `message_topic` | omit unless trunking messages are needed |

tr-engine currently subscribes to `trunk_recorder/#`.

## Node Monitoring Contract

Each node must have three Uptime Kuma push monitors:

1. System online heartbeat
2. trunk-recorder container heartbeat
3. Transmission activity heartbeat

The bootstrap script installs `/usr/local/bin/gascanner-heartbeat.sh` and runs it every minute through cron. Tokens are created in Uptime Kuma by the admin and entered during node setup.

## Reverse Proxy Notes

Traefik v3 handles public HTTPS routing with Cloudflare DNS challenge certificates. Public routes are added through Docker labels on the service containers.

The tr-dashboard host has two routes:

- `Host(trdash.georgiascanner.live)` with low priority serves the static dashboard.
- `Host(trdash.georgiascanner.live) && (PathPrefix(/api) || PathPrefix(/audio) || PathPrefix(/health))` with higher priority proxies API/audio traffic to tr-engine.

## Service Status Notes

- ThinLine Radio and tr-engine are the primary current ingestion and user-facing path.
- RDIO Scanner Docker is still running for compatibility and monitoring, but new nodes should not be documented as RDIO-first.
- Legacy bare-metal RDIO is inactive.
- Historical SWAG, iCAD, Grafana, Telegraf, InfluxDB, Elasticsearch, DIUN, Trunk-Player NG, and static-image nginx references should not be used for new node bootstrap docs unless explicitly restoring one of those services.

## Adding A New Public Service

1. Attach the service to `compose_default`.
2. Add Traefik labels for host, entrypoint, TLS resolver, and service port.
3. Add AutoKuma labels if it should be monitored.
4. Add or verify the Cloudflare tunnel/DNS hostname.
5. Restart the service and confirm through Uptime Kuma.

Example labels:

```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.example.rule: "Host(`example.georgiascanner.live`)"
  traefik.http.routers.example.entrypoints: "websecure"
  traefik.http.routers.example.tls.certresolver: "cloudflare"
  traefik.http.services.example.loadbalancer.server.port: "3000"
  traefik.docker.network: "compose_default"
  kuma.example.docker.name: "Example (Container)"
  kuma.example.docker.dockerHost: "local"
  kuma.example.docker.interval: "60"
  kuma.example.docker.tag_name: "tag-infra"
```
