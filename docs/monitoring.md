# Monitoring Reference

GaScanner uses Uptime Kuma for service and node health. Docker services are discovered by AutoKuma from labels, and remote trunk-recorder nodes use push monitors.

## VPS Monitoring

| Component | Role |
|-----------|------|
| Uptime Kuma | Health-check UI at `https://uptime.georgiascanner.live` |
| AutoKuma | Reads Docker labels and creates/updates monitors |
| Dozzle | Docker log viewer on local/admin access |

AutoKuma label pattern:

```yaml
labels:
  kuma.service-name.docker.name: "Display Name (Container)"
  kuma.service-name.docker.dockerHost: "local"
  kuma.service-name.docker.interval: "60"
  kuma.service-name.docker.tag_name: "tag-scanner"
```

HTTP monitor label pattern:

```yaml
labels:
  kuma.service-name-web.http.name: "Display Name (Web)"
  kuma.service-name-web.http.url: "https://service.georgiascanner.live"
  kuma.service-name-web.http.interval: "60"
  kuma.service-name-web.http.tag_name: "tag-scanner"
```

## Tag Conventions

| Tag | Services |
|-----|----------|
| `tag-infra` | Traefik, Cloudflared, Uptime Kuma, AutoKuma |
| `tag-radio` | ThinLine Radio and ThinLine database |
| `tag-scanner` | tr-engine, tr-dashboard, RDIO compatibility services, scanner nodes |
| `tag-util` | Dozzle and support utilities |

## Required Node Push Monitors

Each remote node needs three push monitors created by the admin:

| Monitor | Purpose | Bootstrap check |
|---------|---------|-----------------|
| System | Node is online and cron is running | Always sends `up` when heartbeat script runs |
| Container | trunk-recorder container is running | Checks `docker ps` for `trunk_recorder` |
| Transmissions | Node is receiving radio traffic | Checks recent audio files, then recent logs |

The bootstrap script installs `/usr/local/bin/gascanner-heartbeat.sh` and a one-minute cron entry.

## Heartbeat Behavior

The transmission monitor checks for recent `.wav` files in `~/trunk_recorder/tr_audio` from the last five minutes. If no files are found, it checks recent trunk-recorder logs for call activity. This catches both normal audio writes and cases where the container logs activity before files are visible.

## Useful Node Commands

Check cron:

```bash
crontab -l
```

Run heartbeat manually:

```bash
sudo /usr/local/bin/gascanner-heartbeat.sh
```

Check trunk-recorder:

```bash
docker ps --filter name=trunk_recorder
docker logs --since 10m trunk_recorder
```

Check recent audio:

```bash
find ~/trunk_recorder/tr_audio -type f -name "*.wav" -mmin -10
```
