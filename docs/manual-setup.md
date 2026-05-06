# Manual Node Setup

Use this guide when you do not want to run `scripts/setup.sh`, or when you need to understand exactly what the bootstrap script creates.

## Prerequisites

- Ubuntu 22.04 LTS or 24.04 LTS
- Root/sudo access
- SDR hardware connected to the node
- MQTT credentials from the GaScanner admin
- Three Uptime Kuma push monitor tokens from the GaScanner admin
- `talkgroups.csv` for the county/system

## 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y \
  apt-transport-https ca-certificates curl gnupg lsb-release git jq htop tmux \
  usbutils libusb-1.0-0-dev cmake build-essential bc \
  rtl-sdr librtlsdr-dev sox libsox-fmt-all mosquitto-clients
```

## 2. Install Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Log out and back in so the Docker group membership applies.

## 3. Configure SDR Access

```bash
sudo tee /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
EOF

sudo tee /etc/udev/rules.d/52-airspy.rules << 'EOF'
ATTR{idVendor}=="1d50", ATTR{idProduct}=="60a1", SYMLINK+="airspy-%k", MODE="660", GROUP="plugdev"
EOF

sudo tee /etc/modprobe.d/blacklist-rtlsdr.rules << 'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Verify an RTL-SDR:

```bash
rtl_test -t
```

## 4. Create Node Directories

```bash
mkdir -p ~/trunk_recorder/{tr_config,tr_audio,tr_logs}
cd ~/trunk_recorder
```

Place the admin-provided talkgroup file at:

```text
~/trunk_recorder/tr_config/talkgroups.csv
```

## 5. Create Docker Compose

```bash
cat > docker-compose.yml << 'EOF'
services:
  trunk-recorder:
    image: thegreatcodeholio/trunk-recorder-mqtt:RC5.0_organized
    container_name: trunk_recorder
    restart: unless-stopped
    privileged: true
    volumes:
      - ./tr_config:/app/tr_config:ro
      - ./tr_audio:/app/tr_audio
      - ./tr_logs:/app/tr_logs
      - /dev/bus/usb:/dev/bus/usb
      - /dev/shm:/dev/shm
    devices:
      - /dev/bus/usb:/dev/bus/usb
    environment:
      - TZ=America/New_York
EOF
```

## 6. Create trunk-recorder Config

Replace placeholders before starting the container.

```bash
cat > tr_config/config.json << 'EOF'
{
  "ver": 2,
  "instanceId": "YOUR_COUNTY",
  "sources": [
    {
      "center": 851000000,
      "rate": 2400000,
      "error": 0,
      "gain": 40,
      "digitalRecorders": 8,
      "analogRecorders": 0,
      "driver": "osmosdr",
      "device": "rtl=0"
    }
  ],
  "systems": [
    {
      "control_channels": [851012500, 851262500, 851512500],
      "type": "p25",
      "talkgroupsFile": "/app/tr_config/talkgroups.csv",
      "shortName": "YOUR_COUNTY",
      "audioArchive": true,
      "uploadScript": ""
    }
  ],
  "plugins": [
    {
      "name": "MQTT Status",
      "library": "/usr/local/lib/trunk-recorder/libmqtt_status_plugin.so",
      "broker": "tcp://mqtt.georgiascanner.live:1883",
      "topic": "trunk_recorder/feeds",
      "unit_topic": "trunk_recorder/units",
      "username": "YOUR_MQTT_USER",
      "password": "YOUR_MQTT_PASSWORD",
      "mqtt_audio": true,
      "mqtt_audio_type": "wav",
      "console_logs": true
    }
  ],
  "tempDir": "/dev/shm",
  "captureDir": "/app/tr_audio",
  "logDir": "/app/tr_logs",
  "logLevel": "info",
  "logFile": true
}
EOF
```

Key fields to verify:

| Field | What to set |
|-------|-------------|
| `instanceId` | County or node ID, for example `chatham` |
| `sources[].center` | SDR center frequency in Hz |
| `sources[].gain` | SDR gain; tune for decode rate |
| `systems[].control_channels` | Correct control channels for the receiver location |
| `systems[].shortName` | County/system short name |
| `plugins[].username` | MQTT user from admin |
| `plugins[].password` | MQTT password from admin |

`message_topic` is intentionally omitted by default because trunking messages can be very high volume. Add it only if the admin requests trunking message ingestion.

## 7. Test MQTT

```bash
mosquitto_pub -h mqtt.georgiascanner.live -p 1883 \
  -u "YOUR_MQTT_USER" -P "YOUR_MQTT_PASSWORD" \
  -t "test/node" -m "hello"
```

## 8. Start trunk-recorder

```bash
cd ~/trunk_recorder
docker compose up -d
docker logs -f trunk_recorder
```

## 9. Optional systemd Service

```bash
sudo tee /etc/systemd/system/trunk-recorder.service << EOF
[Unit]
Description=Trunk Recorder
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/trunk_recorder
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable trunk-recorder
sudo systemctl start trunk-recorder
```

## 10. Monitoring

The standard bootstrap also installs `/usr/local/bin/gascanner-heartbeat.sh` and runs it every minute. If setting up manually, either run `scripts/setup.sh` for the monitoring portion or recreate the three push checks described in [Monitoring](monitoring.md).

## Troubleshooting

Check SDR hardware:

```bash
lsusb
rtl_test -t
lsmod | grep -E 'dvb|rtl28'
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

Check MQTT reachability:

```bash
nc -zv mqtt.georgiascanner.live 1883
```
