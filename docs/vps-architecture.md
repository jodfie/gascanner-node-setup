# VPS Architecture Reference

This document describes the current GAScanner VPS stack for reference when adding nodes, troubleshooting, or onboarding new contributors.

## Services Overview

The VPS runs 14 containers plus a bare-metal Mosquitto MQTT broker.

| Service | Container | Subdomain | Backend |
|---------|-----------|-----------|---------|
| ThinLine Radio | thinline | thinline.georgiascanner.live | PostgreSQL |
| TR Engine | tr-engine | — (internal) | PostgreSQL + MQTT |
| TR Dashboard | tr-dashboard | trdash.georgiascanner.live | PostgreSQL + MQTT |
| RDIO Scanner | rdio-scanner | scanner.georgiascanner.live | MariaDB |
| Traefik | traefik | — (ports 80/443) | — |
| Cloudflared | cloudflared | — (Cloudflare tunnel) | — |
| Uptime Kuma | uptime-kuma | uptime.georgiascanner.live | — |
| AutoKuma | autokuma | — (internal) | — |
| Dashy | dashy | home.georgiascanner.live | — |
| Dozzle | dozzle | — (internal) | — |
| Mosquitto | bare metal | — (port 1883) | — |

## Reverse Proxy: Traefik + Cloudflare Tunnel

All public HTTPS traffic is handled by Traefik (reverse proxy) running on ports 80 and 443, paired with a standalone Cloudflared container that maintains a persistent Cloudflare tunnel (tunnel ID: `230f663c-4c10-46a3-bfd7-267629d2777b`).

The domain `georgiascanner.live` uses a wildcard certificate provisioned via Cloudflare DNS challenge. DNS records for subdomains are CNAME entries pointing to the Cloudflare tunnel.

Traefik picks up routing configuration automatically from Docker labels on each container. No manual Traefik config file changes are needed for new services — just add the correct labels to the container.

### Adding a New Subdomain

1. Add Traefik labels to the new container in its `docker-compose.yml`:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.SERVICENAME.rule=Host(`SUBDOMAIN.georgiascanner.live`)"
  - "traefik.http.routers.SERVICENAME.entrypoints=websecure"
  - "traefik.http.routers.SERVICENAME.tls.certresolver=cloudflare"
  - "traefik.http.services.SERVICENAME.loadbalancer.server.port=CONTAINER_PORT"
```

2. Add a DNS CNAME record in Cloudflare: `SUBDOMAIN.georgiascanner.live` → the tunnel hostname (e.g., `230f663c-4c10-46a3-bfd7-267629d2777b.cfargotunnel.com`). Set proxy status to proxied.

3. Update the Cloudflare tunnel ingress config to route the new hostname to Traefik. The tunnel forwards all traffic to Traefik, so in most cases no tunnel config change is needed — Traefik handles routing from there.

4. Restart the container. AutoKuma will automatically create an Uptime Kuma monitor if the container has the appropriate AutoKuma labels.

## Mosquitto MQTT Broker

Mosquitto runs on the VPS bare metal (not in Docker) and listens on port 1883 with authentication required.

Config location: `/etc/mosquitto/`

Key files:
- `/etc/mosquitto/mosquitto.conf` - Main config (includes conf.d/)
- `/etc/mosquitto/conf.d/` - Drop-in config files
- `/etc/mosquitto/passwd` - Hashed password file (managed with `mosquitto_passwd`)

To add a new MQTT user:
```bash
sudo mosquitto_passwd /etc/mosquitto/passwd NEW_USERNAME
sudo systemctl reload mosquitto
```

Each trunk-recorder node authenticates with its own MQTT user (convention: `tr_COUNTY`).

## Data Flow

```
Trunk-Recorder Node
        │
        │ MQTT publish (audio + metadata)
        │ tcp://VPS_IP:1883  (auth required)
        ▼
Mosquitto MQTT Broker (bare metal)
        │
        ├─── ThinLine Radio subscribes
        │         → stores audio, serves playback
        │         → thinline.georgiascanner.live
        │
        └─── TR Engine subscribes
                  → real-time call processing
                  → talkgroup management
                  → TR Dashboard (trdash.georgiascanner.live)
```

Audio and metadata originate from the trunk-recorder MQTT plugin. ThinLine Radio and TR Engine each subscribe to the relevant MQTT topics independently. There is no single ingest pipeline — both services consume from the broker directly.

## Monitoring

- **Uptime Kuma** ([uptime.georgiascanner.live](https://uptime.georgiascanner.live)) monitors node heartbeats and container health
- **AutoKuma** reads Docker labels and automatically creates/updates Kuma monitors when containers start
- **Dozzle** provides a Docker log viewer for all containers (internal access only)

Node operators must configure 3 Uptime Kuma push monitors per node (system health, container status, transmission activity). Push tokens are provided by the admin.

## Removed Services

The following services have been decommissioned and are no longer part of the stack:

- SWAG (replaced by Traefik + Cloudflare tunnel)
- iCAD Dispatch + Elasticsearch
- Grafana + Telegraf + InfluxDB
- RDIO Scanner bare metal install
- Trunk-Player NG
- DIUN
- Static image nginx

Do not reference these in node setup documentation or troubleshooting guides.
