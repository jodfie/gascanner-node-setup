# GAScanner Node Setup

Automated setup for GAScanner trunk-recorder nodes. This repo helps you configure a bare Ubuntu server as a trunk-recorder node that feeds into the centralized GAScanner VPS infrastructure.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   YOUR NEW NODE                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Trunk-Recorder                               │   │
│  │  • SDR hardware (RTL-SDR, Airspy, etc.)                  │   │
│  │  • MQTT plugin → sends audio & metrics to VPS            │   │
│  │  • Uptime Kuma heartbeats (3 monitors required)          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ MQTT (audio + metadata + metrics)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GAScanner VPS                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Data Pipeline                                             │  │
│  │  • iCAD processing (compression, tone detection)           │  │
│  │  • Telegraf → InfluxDB (metrics collection)                │  │
│  │  • Elasticsearch (call indexing & search)                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Web Services                                              │  │
│  │  • ThinLineRadio   → thinline.georgiascanner.live         │  │
│  │  • RDIO Scanner    → scanner.georgiascanner.live          │  │
│  │  • Grafana Stats   → stats.georgiascanner.live            │  │
│  │  • Uptime Kuma     → uptime.georgiascanner.live           │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Monitoring & Dashboards

All node metrics are available at **https://stats.georgiascanner.live**:

- **System Overview** - Total transmissions, active nodes, call distribution
- **Node Performance** - Per-node transmission rates, recorder status, call duration
- **Talkgroup Analytics** - Top talkgroups, activity heatmaps, group breakdowns
- **Uptime Kuma Monitors** - Node health, response times, uptime percentages

Each node sends metrics via MQTT which are collected by Telegraf and stored in InfluxDB for visualization.

## Supported Counties (SEGARRN)

All counties are part of the [Southeast Georgia Regional Radio Network (SEGARRN)](https://www.radioreference.com/db/sid/6694) P25 system.

| County | Short Name | Major City | Status |
|--------|------------|------------|--------|
| Chatham | chatham | Savannah | Active |
| Bryan | bryan | Richmond Hill | Ready |
| Bulloch | bulloch | Statesboro | Ready |
| Candler | candler | Metter | Ready |
| Effingham | effingham | Springfield | Ready |
| Emanuel | emanuel | Swainsboro | Ready |
| Glynn | glynn | Brunswick | Ready |
| Liberty | liberty | Hinesville | Ready |
| Long | long | Ludowici | Ready |
| McIntosh | mcintosh | Darien | Ready |

## Prerequisites

- Ubuntu 22.04 LTS (or 24.04)
- SDR hardware connected (RTL-SDR, Airspy, HackRF, etc.)
- Internet connection
- MQTT credentials (request from admin)

## Quick Start

### Option 1: Interactive Setup Script

```bash
# Clone the repo
git clone https://github.com/jodfie/gascanner-node-setup.git
cd gascanner-node-setup

# Run interactive setup
sudo ./scripts/setup.sh
```

### Option 2: Claude Code Setup

If you have Claude Code installed:

```bash
# Clone the repo
git clone https://github.com/jodfie/gascanner-node-setup.git
cd gascanner-node-setup

# Run Claude Code and ask it to set up the node
claude

# Then say: "Set up this server as a GAScanner trunk-recorder node for [COUNTY] county"
```

## What the Setup Does

1. **System Updates** - Updates packages and installs dependencies
2. **Docker Installation** - Installs Docker and Docker Compose
3. **RadioReference Fetch** - Scrapes control channel frequencies from RadioReference
4. **Trunk-Recorder Setup** - Pulls `thegreatcodeholio/trunk-recorder-mqtt:RC5.0_organized` image
5. **SDR Configuration** - Configures udev rules for SDR hardware
6. **MQTT Configuration** - Sets up connection to GAScanner VPS
7. **Monitoring Setup** - Configures required Uptime Kuma heartbeat (sends status every minute)
8. **Systemd Service** - Creates auto-start service

## Configuration

### Required Information

You'll need to provide:
- **County name** - One of the 10 SEGARRN counties
- **RadioReference System ID** - The script will fetch control channels automatically
- **MQTT credentials** (username/password from admin)
- **SDR device info** (type, serial number if multiple)
- **3 Uptime Kuma push tokens** (required for monitoring):
  1. **Node System Monitor** - Reports node health every minute
  2. **TR Container Monitor** - Reports trunk-recorder container status
  3. **Transmissions Monitor** - Reports transmission activity (alerts if no audio in 30min)

### Files from Admin

Request these from the GAScanner admin:
- **talkgroups.csv** - Talkgroup definitions for your county
- **MQTT credentials** - Username and password for broker connection
- **3 Uptime Kuma push tokens** - Create 3 push monitors at uptime.georgiascanner.live

### Configuration Files

After setup, your configuration will be in:
```
~/trunk_recorder/
├── docker-compose.yml      # Docker configuration
├── tr_config/
│   ├── config.json         # Main trunk-recorder config
│   ├── talkgroups.csv      # Talkgroup definitions
│   └── units.csv           # Unit ID definitions (optional)
└── tr_audio/               # Temporary audio storage
```

## Manual Setup Steps

If you prefer manual setup, see [docs/manual-setup.md](docs/manual-setup.md).

## Updating

To update trunk-recorder:

```bash
cd ~/trunk_recorder
docker compose pull
docker compose up -d
```

## Troubleshooting

### Check trunk-recorder logs
```bash
docker logs -f trunk_recorder
```

### Check MQTT connectivity
```bash
# Test MQTT connection (from node)
mosquitto_pub -h mqtt.georgiascanner.live -p 1883 \
  -u "tr_COUNTY" -P "YOUR_PASSWORD" \
  -t "test" -m "hello"
```

### Check SDR detection
```bash
# For RTL-SDR
rtl_test

# For Airspy
airspy_info
```

### Verify audio is being sent
Check the GAScanner VPS iCAD logs or Uptime Kuma for heartbeat activity.

## Hardware Recommendations

### Entry Level
- Raspberry Pi 4 (4GB+) or Intel NUC
- RTL-SDR Blog V3 or V4
- Outdoor antenna with LNA

### Recommended
- Intel NUC or Mini PC (i5+)
- Airspy Mini or Airspy R2
- Bandpass filter for your frequency range
- Quality outdoor antenna

### Multi-System
- Full PC with multiple USB ports
- Multiple SDRs (one per frequency range)
- USB hub with external power

## Support

- **Issues**: Open a GitHub issue
- **Admin Contact**: Request MQTT credentials and system configuration

## License

MIT License - See [LICENSE](LICENSE) file
