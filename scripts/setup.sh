#!/bin/bash
#
# GAScanner Node Setup Script
# Sets up a bare Ubuntu server as a trunk-recorder node
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MQTT_HOST="mqtt.georgiascanner.live"
MQTT_PORT="1883"
UPTIME_KUMA_HOST="uptime.georgiascanner.live"
TR_IMAGE="thegreatcodeholio/trunk-recorder-mqtt:RC5.0_organized"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Functions
print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           GAScanner Trunk-Recorder Node Setup             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

get_county() {
    echo ""
    echo -e "${YELLOW}Available SEGARRN Counties:${NC}"
    echo "  1) chatham    - Chatham County (Savannah)"
    echo "  2) bryan      - Bryan County"
    echo "  3) bulloch    - Bulloch County (Statesboro)"
    echo "  4) candler    - Candler County"
    echo "  5) effingham  - Effingham County"
    echo "  6) emanuel    - Emanuel County"
    echo "  7) glynn      - Glynn County (Brunswick)"
    echo "  8) liberty    - Liberty County (Hinesville)"
    echo "  9) long       - Long County"
    echo " 10) mcintosh   - McIntosh County"
    echo ""
    read -p "Select county (1-10): " county_choice

    case $county_choice in
        1) COUNTY="chatham" ;;
        2) COUNTY="bryan" ;;
        3) COUNTY="bulloch" ;;
        4) COUNTY="candler" ;;
        5) COUNTY="effingham" ;;
        6) COUNTY="emanuel" ;;
        7) COUNTY="glynn" ;;
        8) COUNTY="liberty" ;;
        9) COUNTY="long" ;;
        10) COUNTY="mcintosh" ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac

    print_info "Selected county: $COUNTY"
}

get_radioreference_info() {
    echo ""
    echo -e "${YELLOW}RadioReference System Configuration${NC}"
    echo "Enter the RadioReference System ID for your county."
    echo "Example: For https://www.radioreference.com/db/sid/2644"
    echo "         The System ID is: 2644"
    echo ""
    read -p "RadioReference System ID: " RR_SYSTEM_ID

    if [[ -z "$RR_SYSTEM_ID" ]]; then
        print_error "RadioReference System ID is required"
        exit 1
    fi

    print_info "Will fetch control channels from RadioReference system $RR_SYSTEM_ID"
}

fetch_control_channels() {
    print_step "Fetching control channels from RadioReference..."

    # Fetch the RadioReference page and extract control channel frequencies
    local rr_url="https://www.radioreference.com/db/sid/${RR_SYSTEM_ID}"
    local page_content

    page_content=$(curl -s "$rr_url" 2>/dev/null) || {
        print_warn "Could not fetch RadioReference page"
        print_warn "You will need to manually configure control channels"
        CONTROL_CHANNELS="[851000000]"
        return
    }

    # Try to extract control channel frequencies from the page
    # RadioReference format varies, so we provide a fallback
    local freqs=$(echo "$page_content" | grep -oP '\d{3}\.\d{4,5}' | head -10 | sort -u)

    if [[ -n "$freqs" ]]; then
        # Convert MHz to Hz and format as JSON array
        local hz_array=""
        while IFS= read -r freq; do
            local hz=$(echo "$freq * 1000000" | bc | cut -d. -f1)
            if [[ -n "$hz_array" ]]; then
                hz_array="${hz_array},${hz}"
            else
                hz_array="${hz}"
            fi
        done <<< "$freqs"

        if [[ -n "$hz_array" ]]; then
            CONTROL_CHANNELS="[${hz_array}]"
            print_info "Found control channels: $CONTROL_CHANNELS"
        else
            CONTROL_CHANNELS="[851000000]"
            print_warn "Could not parse frequencies, using default"
        fi
    else
        print_warn "No frequencies found on page"
        print_warn "You will need to manually configure control channels"
        CONTROL_CHANNELS="[851000000]"
    fi

    echo ""
    echo -e "${YELLOW}Verify Control Channels${NC}"
    echo "Extracted: $CONTROL_CHANNELS"
    read -p "Enter control channels manually (or press Enter to use above): " manual_channels

    if [[ -n "$manual_channels" ]]; then
        # Validate it looks like a JSON array
        if [[ "$manual_channels" =~ ^\[.*\]$ ]]; then
            CONTROL_CHANNELS="$manual_channels"
        else
            CONTROL_CHANNELS="[$manual_channels]"
        fi
        print_info "Using manual control channels: $CONTROL_CHANNELS"
    fi
}

get_mqtt_credentials() {
    echo ""
    echo -e "${YELLOW}MQTT Credentials${NC}"
    echo "Contact admin to get MQTT credentials for your node."
    echo ""
    read -p "MQTT Username (e.g., tr_$COUNTY): " MQTT_USER
    read -s -p "MQTT Password: " MQTT_PASS
    echo ""

    if [[ -z "$MQTT_USER" || -z "$MQTT_PASS" ]]; then
        print_error "MQTT credentials are required"
        exit 1
    fi
}

get_sdr_info() {
    echo ""
    echo -e "${YELLOW}SDR Configuration${NC}"
    echo "  1) RTL-SDR"
    echo "  2) Airspy Mini"
    echo "  3) Airspy R2"
    echo "  4) HackRF"
    echo ""
    read -p "Select SDR type (1-4): " sdr_choice

    case $sdr_choice in
        1) SDR_TYPE="rtlsdr"; SDR_DRIVER="osmosdr" ;;
        2) SDR_TYPE="airspy"; SDR_DRIVER="osmosdr" ;;
        3) SDR_TYPE="airspy"; SDR_DRIVER="osmosdr" ;;
        4) SDR_TYPE="hackrf"; SDR_DRIVER="osmosdr" ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac

    # Check for multiple SDRs
    read -p "How many SDRs will this node use? (1-4): " SDR_COUNT
    SDR_COUNT=${SDR_COUNT:-1}

    print_info "SDR Type: $SDR_TYPE, Count: $SDR_COUNT"
}

get_uptime_kuma_token() {
    echo ""
    echo -e "${YELLOW}Uptime Kuma Monitoring (Required)${NC}"
    echo "Enter the Uptime Kuma push token for this node."
    echo "Get this from the GAScanner admin - they will create a push monitor for you."
    echo ""
    read -p "Push Token: " KUMA_TOKEN

    if [[ -z "$KUMA_TOKEN" ]]; then
        print_error "Uptime Kuma push token is required for monitoring"
        exit 1
    fi
}

get_hostname() {
    echo ""
    read -p "Enter hostname for this node (e.g., trunk-$COUNTY): " NEW_HOSTNAME
    NEW_HOSTNAME=${NEW_HOSTNAME:-"trunk-$COUNTY"}
}

install_dependencies() {
    print_step "Installing system dependencies..."

    apt-get update
    apt-get install -y \
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
        build-essential \
        bc
}

install_docker() {
    print_step "Installing Docker..."

    if command -v docker &> /dev/null; then
        print_info "Docker already installed"
        return
    fi

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
    fi
}

install_sdr_tools() {
    print_step "Installing SDR tools..."

    apt-get install -y \
        rtl-sdr \
        librtlsdr-dev \
        sox \
        libsox-fmt-all

    # Create udev rules for SDR
    cat > /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
EOF

    cat > /etc/udev/rules.d/52-airspy.rules << 'EOF'
ATTR{idVendor}=="1d50", ATTR{idProduct}=="60a1", SYMLINK+="airspy-%k", MODE="660", GROUP="plugdev"
EOF

    # Blacklist DVB drivers
    cat > /etc/modprobe.d/blacklist-rtlsdr.rules << 'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF

    udevadm control --reload-rules
    udevadm trigger
}

setup_trunk_recorder() {
    print_step "Setting up trunk-recorder..."

    # Create directories
    TR_DIR="/home/${SUDO_USER:-root}/trunk_recorder"
    mkdir -p "$TR_DIR"/{tr_config,tr_audio,tr_logs}

    # Generate docker-compose.yml with correct image
    generate_docker_compose "$TR_DIR/docker-compose.yml"

    # Generate config.json based on county
    generate_tr_config "$TR_DIR/tr_config/config.json"

    # Copy talkgroups file if exists
    if [[ -f "$REPO_DIR/configs/$COUNTY/talkgroups.csv" ]]; then
        cp "$REPO_DIR/configs/$COUNTY/talkgroups.csv" "$TR_DIR/tr_config/"
    else
        print_warn "No talkgroups.csv found - request from admin"
    fi

    # Set ownership
    if [[ -n "$SUDO_USER" ]]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$TR_DIR"
    fi

    print_info "Trunk-recorder directory: $TR_DIR"
}

generate_docker_compose() {
    local compose_file="$1"

    cat > "$compose_file" << EOF
version: "3.8"

services:
  trunk-recorder:
    image: ${TR_IMAGE}
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
}

generate_tr_config() {
    local config_file="$1"

    print_step "Generating trunk-recorder configuration..."

    # Load county-specific settings if available
    if [[ -f "$REPO_DIR/configs/$COUNTY/system.conf" ]]; then
        source "$REPO_DIR/configs/$COUNTY/system.conf"
    fi

    # Use fetched control channels or default
    CONTROL_CHANNELS=${CONTROL_CHANNELS:-"[851000000]"}
    TALKGROUPS_FILE=${TALKGROUPS_FILE:-"/app/tr_config/talkgroups.csv"}

    cat > "$config_file" << EOF
{
  "ver": 2,
  "instanceId": "$COUNTY",
  "sources": [
    {
      "center": 851000000,
      "rate": 2400000,
      "error": 0,
      "gain": 40,
      "digitalRecorders": 8,
      "analogRecorders": 0,
      "driver": "$SDR_DRIVER",
      "device": "rtl=0"
    }
  ],
  "systems": [
    {
      "control_channels": $CONTROL_CHANNELS,
      "type": "p25",
      "talkgroupsFile": "$TALKGROUPS_FILE",
      "shortName": "$COUNTY",
      "audioArchive": true,
      "uploadScript": ""
    }
  ],
  "plugins": [
    {
      "name": "MQTT Status",
      "library": "/usr/local/lib/trunk-recorder/libmqtt_status_plugin.so",
      "broker": "tcp://$MQTT_HOST:$MQTT_PORT",
      "topic": "trunk_recorder/feeds",
      "unit_topic": "trunk_recorder/units",
      "username": "$MQTT_USER",
      "password": "$MQTT_PASS",
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

    print_info "Config generated with control channels: $CONTROL_CHANNELS"
    print_warn "IMPORTANT: Verify config and adjust SDR settings as needed"
}

setup_monitoring() {
    print_step "Setting up Uptime Kuma heartbeat..."

    # Create heartbeat script
    local heartbeat_script="/usr/local/bin/gascanner-heartbeat.sh"

    cat > "$heartbeat_script" << EOF
#!/bin/bash
# GAScanner Node Heartbeat
# Sends status to Uptime Kuma every run

# Check if trunk-recorder container is running
if docker ps --format '{{.Names}}' | grep -q trunk_recorder; then
    STATUS="up"
    MSG="trunk-recorder running"
else
    STATUS="down"
    MSG="trunk-recorder not running"
fi

curl -s "https://${UPTIME_KUMA_HOST}/api/push/${KUMA_TOKEN}?status=\${STATUS}&msg=\${MSG}" > /dev/null 2>&1
EOF

    chmod +x "$heartbeat_script"

    # Add cron job for heartbeat (every minute)
    local cron_entry="* * * * * $heartbeat_script"

    # Install cron job
    (crontab -l 2>/dev/null | grep -v gascanner-heartbeat; echo "$cron_entry") | crontab -

    # Run initial heartbeat
    $heartbeat_script

    print_info "Heartbeat monitoring configured"
    print_info "Sending to: https://${UPTIME_KUMA_HOST}/api/push/${KUMA_TOKEN}"
}

set_hostname() {
    print_step "Setting hostname to $NEW_HOSTNAME..."

    hostnamectl set-hostname "$NEW_HOSTNAME"

    # Update /etc/hosts
    if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
    fi
}

create_service() {
    print_step "Creating systemd service..."

    TR_DIR="/home/${SUDO_USER:-root}/trunk_recorder"

    cat > /etc/systemd/system/trunk-recorder.service << EOF
[Unit]
Description=Trunk Recorder
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=${SUDO_USER:-root}
WorkingDirectory=$TR_DIR
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable trunk-recorder.service

    print_info "Service created: trunk-recorder.service"
}

print_summary() {
    TR_DIR="/home/${SUDO_USER:-root}/trunk_recorder"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete!                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo "  Hostname:         $NEW_HOSTNAME"
    echo "  County:           $COUNTY"
    echo "  SDR Type:         $SDR_TYPE"
    echo "  Docker Image:     $TR_IMAGE"
    echo "  MQTT User:        $MQTT_USER"
    echo "  MQTT Host:        $MQTT_HOST:$MQTT_PORT"
    echo "  Control Channels: $CONTROL_CHANNELS"
    echo "  RadioRef SID:     $RR_SYSTEM_ID"
    echo ""
    echo -e "${YELLOW}Monitoring:${NC}"
    echo "  Uptime Kuma:      https://${UPTIME_KUMA_HOST}"
    echo "  Push Token:       ${KUMA_TOKEN:0:8}..."
    echo "  Heartbeat:        Every minute via cron"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Request talkgroups.csv from admin and place in:"
    echo "     $TR_DIR/tr_config/talkgroups.csv"
    echo ""
    echo "  2. Verify/edit trunk-recorder config:"
    echo "     nano $TR_DIR/tr_config/config.json"
    echo ""
    echo "  3. Start trunk-recorder:"
    echo "     cd $TR_DIR && docker compose up -d"
    echo ""
    echo "  4. Check logs:"
    echo "     docker logs -f trunk_recorder"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  Start:   systemctl start trunk-recorder"
    echo "  Stop:    systemctl stop trunk-recorder"
    echo "  Status:  systemctl status trunk-recorder"
    echo "  Logs:    docker logs -f trunk_recorder"
    echo ""
    echo -e "${GREEN}Monitoring: Heartbeat configured and active${NC}"
    echo ""
}

# Main
main() {
    print_header
    check_root

    # Gather information
    get_county
    get_radioreference_info
    fetch_control_channels
    get_mqtt_credentials
    get_sdr_info
    get_uptime_kuma_token
    get_hostname

    # Confirm
    echo ""
    echo -e "${YELLOW}Ready to install with the following settings:${NC}"
    echo "  County:           $COUNTY"
    echo "  Hostname:         $NEW_HOSTNAME"
    echo "  SDR Type:         $SDR_TYPE"
    echo "  MQTT User:        $MQTT_USER"
    echo "  Control Channels: $CONTROL_CHANNELS"
    echo "  Docker Image:     $TR_IMAGE"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "Aborted"
        exit 1
    fi

    # Run installation
    install_dependencies
    install_docker
    install_sdr_tools
    set_hostname
    setup_trunk_recorder
    setup_monitoring
    create_service

    print_summary
}

main "$@"
