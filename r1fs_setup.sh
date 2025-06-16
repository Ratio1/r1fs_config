#!/bin/bash

log_with_color() {
    local text="$1"
    local color="$2"
    local color_code=""

    case $color in
        red)
            color_code="0;31" # Red
            ;;
        green)
            color_code="0;32" # Green
            ;;
        blue)
            color_code="0;36" # Blue
            ;;
        yellow)
            color_code="0;33" # Yellow
            ;;
        light)
            color_code="1;37" # Light (White)
            ;;
        gray)
            color_code="2;37" # Gray (White)
            ;;
        *)
            color_code="0" # Default color
            ;;
    esac

    echo -e "\e[${color_code}m${text}\e[0m"
}

# Exit on any error
set -e

KUBO_VERSION="v0.35.0"

ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH="arm64"
else
    error "Unsupported architecture: $(uname -m). Only x86_64 (amd64) or arm64 are supported."
    exit 1
fi

log_with_color "Setting up IPFS Relay Node with Kubo $KUBO_VERSION for $ARCH..." "blue"

# Stop running IPFS daemon if active (to avoid conflicts during installation/config)
if systemctl is-active --quiet ipfs 2>/dev/null; then
    log_with_color "Stopping running IPFS service..." "blue"
    systemctl stop ipfs
elif pgrep -x ipfs >/dev/null; then
    log_with_color "Terminating existing ipfs daemon process..." "yellow"
    pkill -9 -x ipfs || true
    sleep 2
fi

# Step 1: Install Kubo
wget -c "https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-${ARCH}.tar.gz"
if [ $? -ne 0 ]; then
    log_with_color "wget failed to download Kubo. Exiting." "red"
    exit 1
fi

if [ -f "kubo_${KUBO_VERSION}_linux-amd64.tar.gz" ]; then
    log_with_color "Extracting Kubo package..." "blue"
    tar -xvzf "kubo_${KUBO_VERSION}_linux-amd64.tar.gz" 
else
    log_with_color "Kubo package not found. Please check the download." "red"
    exit 1
fi
cd kubo
sudo bash install.sh
cd ..

# Step 2: Initialize with server profile
log_with_color "Initializing IPFS with server profile..." "blue"
ipfs init --profile server

# Step 3: Configure Circuit Relay v2 Service
ipfs config --json Swarm.RelayService.Enabled true
ipfs config --json Swarm.RelayService.MaxReservations 512
ipfs config --json Swarm.RelayService.MaxCircuits 64
ipfs config --json Swarm.RelayClient.Enabled false

# Step 4: Set up swarm key for private network
log_with_color "Setting up swarm key for private network..." "blue"
if [ -f "swarm_key_base64.txt" ]; then
    cat swarm_key_base64.txt | base64 -d > ~/.ipfs/swarm.key
    log_with_color "Swarm key installed from base64 file"
else
    log_with_color "swarm_key_base64.txt not found. Please provide a valid swarm key file."
    exit 1
fi

# Step 5: Configure for private network
log_with_color "Configuring IPFS for private network. Current bootstrap peers:" "blue"
ipfs bootstrap list
log_with_color "Removing all bootstrap peers..." "blue"
ipfs bootstrap rm --all
# unless false the Multicast DNS (mDNS) will broadcast queries on UDP port 5353 to the multicast address
log_with_color "Disabling mDNS discovery..." "blue"
ipfs config --json Discovery.MDNS.Enabled false 

# Display node information for bootstrap configuration
PEER_ID=$(ipfs id -f='<id>')
log_with_color "Node Peer ID: $PEER_ID" "blue"
MY_IP=$(hostname -I | awk '{print $1}') 
log_with_color "Node IP: $MY_IP" "blue"
MY_BOOTSTRAP="/ip4/$MY_IP/tcp/4001/p2p/$PEER_ID" "blue"
log_with_color "Bootstrap address: $MY_BOOTSTRAP" "blue"
log_with_color "Please run the following command on the other relay servers:" "blue"
log_with_color "ipfs bootstrap add $MY_BOOTSTRAP" "green"

# Step 6: Create systemd service
sudo tee /etc/systemd/system/ipfs.service > /dev/null <<EOF
[Unit]
Description=InterPlanetary File System (IPFS) daemon
Documentation=https://docs.ipfs.tech/
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/ipfs daemon --migrate
ExecStop=/usr/local/bin/ipfs shutdown
Restart=on-failure
RestartSec=5
KillSignal=SIGINT
User=root
Environment=IPFS_PATH=/root/.ipfs

[Install]
WantedBy=multi-user.target
EOF

log_with_color "Systemd service file created at /etc/systemd/system/ipfs.service" "blue"
cat /etc/systemd/system/ipfs.service
# Step 7: Start service
log_with_color "Reloading systemd and enabling IPFS service..." "blue"
sudo systemctl daemon-reload
log_with_color "Starting IPFS service..." "blue"
sudo systemctl enable ipfs
sudo systemctl start ipfs

log_with_color "IPFS Relay Node setup complete!" "blue"
log_with_color "Remember to manually add the other relay node as bootstrap peer." "yellow"
