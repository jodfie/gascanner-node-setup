# Manual Setup Guide

If you prefer to set up your node manually instead of using the interactive script, follow these steps.

## Prerequisites

- Ubuntu 22.04 LTS or 24.04 LTS
- Root/sudo access
- SDR hardware (RTL-SDR, Airspy, HackRF)
- Internet connection

## Step 1: System Updates

```bash
sudo apt update && sudo apt upgrade -y
```

## Step 2: Install Dependencies

```bash
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    htop \
    tmux \
    usbutils \
    libusb-1.0-0-dev \
    cmake \
    build-essential
```

## Step 3: Install Docker

```bash
# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to docker group
sudo usermod -aG docker $USER
```

Log out and back in for group changes to take effect.

## Step 4: Install SDR Tools

```bash
sudo apt install -y rtl-sdr librtlsdr-dev sox libsox-fmt-all
```

### Create udev rules

```bash
# RTL-SDR rules
sudo tee /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0666"
EOF

# Airspy rules
sudo tee /etc/udev/rules.d/52-airspy.rules << 'EOF'
ATTR{idVendor}=="1d50", ATTR{idProduct}=="60a1", SYMLINK+="airspy-%k", MODE="660", GROUP="plugdev"
EOF

# Blacklist DVB drivers
sudo tee /etc/modprobe.d/blacklist-rtlsdr.rules << 'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF

# Reload rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Step 5: Create Trunk-Recorder Directory Structure

```bash
mkdir -p ~/trunk_recorder/{tr_config,tr_audio,tr_logs}
cd ~/trunk_recorder
```

## Step 6: Create docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  trunk-recorder:
    image: robotastic/trunk-recorder:latest
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

## Step 7: Create config.json

Contact the GAScanner admin to get:
- Your MQTT credentials (username/password)
- Control channel frequencies for your county
- Talkgroups CSV file

Create your config:

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

**Important**: Replace:
- `YOUR_COUNTY` with your county name (e.g., chatham, bryan)
- `YOUR_MQTT_USER` and `YOUR_MQTT_PASSWORD` with credentials from admin
- Control channel frequencies with correct values for your area

## Step 8: Add Talkgroups File

Request `talkgroups.csv` from the GAScanner admin and place it in:
```
~/trunk_recorder/tr_config/talkgroups.csv
```

## Step 9: Test SDR Hardware

```bash
# Test RTL-SDR
rtl_test -t

# You should see your device detected
```

## Step 10: Start Trunk-Recorder

```bash
cd ~/trunk_recorder
docker compose up -d

# Check logs
docker logs -f trunk_recorder
```

## Step 11: Create Systemd Service (Optional)

For automatic startup:

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

## Troubleshooting

### SDR Not Detected

1. Check USB connection: `lsusb`
2. Check kernel driver not loaded: `lsmod | grep dvb`
3. If DVB driver loaded, unload it: `sudo rmmod dvb_usb_rtl28xxu`

### No Audio Being Sent

1. Check trunk-recorder logs: `docker logs trunk_recorder`
2. Verify control channel frequencies are correct
3. Check MQTT connectivity with mosquitto_pub test
4. Verify credentials with admin

### Docker Permission Denied

Log out and back in after adding user to docker group, or run:
```bash
newgrp docker
```

## Support

Contact the GAScanner admin for:
- MQTT credentials
- Talkgroups files
- Control channel frequencies
- Uptime Kuma push tokens
