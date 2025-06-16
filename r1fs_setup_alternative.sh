#!/bin/bash
# r1fs_setup.sh - Set up an IPFS Kubo relay node (Kubo v0.35.0) with improved reliability, portability, and security.
# This script installs Kubo, configures a private network (if a swarm key is provided), enables relay v2, and sets up a systemd service.
# It can be safely re-run; it will not overwrite existing configurations or reinstall if not needed.
# Usage: sudo r1fs_setup.sh [-k /path/to/swarm.key]
# Options:
#   -k /path/to/swarm.key   Path to an IPFS private network swarm key to use. If provided, the node will be part of a private network.
# 
# The script ensures:
# - Proper user privileges (run as root or via sudo).
# - Installation of IPFS Kubo v0.35.0 binary.
# - Creation of an 'ipfs' system user and repository directory (/var/lib/ipfs).
# - Integration of the swarm key (for private networks).
# - Enabling of circuit relay v2 service in IPFS config.
# - Idempotent systemd service setup for running the IPFS daemon on startup.
# - Logging messages with consistent format for clarity.
VER="0.1.0"

set -e

# Logging functions (with colors for consistency)
info() {
    # Print informational messages in cyan
    echo -e "\033[1;36m[INFO] $1\033[0m"
}
warn() {
    echo -e "\033[1;33m[WARN] $1\033[0m"
}
error() {
    echo -e "\033[1;31m[ERROR] $1\033[0m" >&2
}

info "Starting IPFS Relay Install Alternative script (version $VER)..."

# Capture original working directory before any sudo re-execution
ORIGINAL_DIR="$(pwd)"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo bash -c "cd '$(pwd)' && bash '$0' $*"
fi

# Parse options
SWARM_KEY_FILE=""
while getopts "k:" opt; do
    case "$opt" in
        k) SWARM_KEY_FILE="$OPTARG" ;;
        *) echo "Usage: $0 [-k /path/to/swarm.key]"; exit 1 ;;
    esac
done

# If no -k provided, check common locations for a swarm.key or base64 encoded file
if [[ -z "$SWARM_KEY_FILE" ]]; then
    if [[ -f "$ORIGINAL_DIR/swarm.key" ]]; then
        SWARM_KEY_FILE="$ORIGINAL_DIR/swarm.key"
    elif [[ -f "$ORIGINAL_DIR/swarm_key_base64.txt" ]]; then
        SWARM_KEY_FILE="$ORIGINAL_DIR/swarm_key_base64.txt"
    elif [[ -f "/etc/ipfs/swarm.key" ]]; then
        SWARM_KEY_FILE="/etc/ipfs/swarm.key"
    fi
fi

# Validate swarm key file if specified
if [[ -n "$SWARM_KEY_FILE" ]]; then
    if [[ ! -f "$SWARM_KEY_FILE" ]]; then
        error "Specified swarm key file not found: $SWARM_KEY_FILE"
        exit 1
    fi
    info "Using swarm key file: $SWARM_KEY_FILE"
else
    warn "No swarm key provided. Node will run on the public IPFS network (not a private network)."
fi

# Stop running IPFS daemon if active (to avoid conflicts during installation/config)
if systemctl is-active --quiet ipfs 2>/dev/null; then
    info "Stopping running IPFS service..."
    systemctl stop ipfs
elif pgrep -x ipfs >/dev/null; then
    info "Terminating existing ipfs daemon process..."
    pkill -9 -x ipfs || true
    sleep 2
fi

# Variables for Kubo version and architecture
KUBO_VERSION_BASE="0.35.0"
KUBO_VERSION="v${KUBO_VERSION_BASE}"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH="arm64"
else
    error "Unsupported architecture: $(uname -m). Only x86_64 (amd64) or arm64 are supported."
    exit 1
fi

# Download Kubo binary if not already present or version mismatch
# Check if ipfs is already installed and at correct version
if command -v ipfs &> /dev/null; then
    INSTALLED_VER="$(ipfs --version || true)"
    info "Detected existing IPFS installation: $INSTALLED_VER"
else
    INSTALLED_VER=""
fi
if [[ "$INSTALLED_VER" == *"$KUBO_VERSION_BASE"* ]]; then
    info "Kubo $KUBO_VERSION is already installed. Skipping download."
else
    DOWNLOAD_URL="https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-${ARCH}.tar.gz"
    info "Downloading Kubo $KUBO_VERSION for $ARCH..."
    TMP_DIR="$(mktemp -d)" 
    trap "rm -rf $TMP_DIR" EXIT
    cd "$TMP_DIR"
    # Use curl or wget to download
    if command -v curl &> /dev/null; then
        curl -fSL "$DOWNLOAD_URL" -o kubo.tar.gz
    elif command -v wget &> /dev/null; then
        wget -q "$DOWNLOAD_URL" -O kubo.tar.gz
    else
        error "Neither curl nor wget is available to download Kubo."
        exit 1
    fi
    if [[ ! -f kubo.tar.gz ]]; then
        error "Failed to download Kubo archive from $DOWNLOAD_URL"
        exit 1
    fi
    info "Download complete. Verifying checksum..."
    if command -v sha512sum &> /dev/null; then
        EXPECTED_HASH="$(curl -fsSL ${DOWNLOAD_URL}.sha512 | awk '{print $1}')"
        DOWNLOADED_HASH="$(sha512sum kubo.tar.gz | awk '{print $1}')"
        if [[ -n "$EXPECTED_HASH" && "$DOWNLOADED_HASH" != "$EXPECTED_HASH" ]]; then
            error "Checksum verification failed! The downloaded archive may be corrupted."
            exit 1
        fi
    fi
    info "Extracting Kubo archive..."
    tar -xzf kubo.tar.gz
    cd kubo
    info "Installing Kubo binaries..."
    bash install.sh  # installs ipfs to /usr/local/bin
    cd ~
    # Cleanup temp files
    rm -rf "$TMP_DIR"
    trap - EXIT
    
    # Ensure IPFS is accessible in PATH by creating symlink if needed
    if [[ ! -L "/usr/bin/ipfs" && -f "/usr/local/bin/ipfs" ]]; then
        info "Creating symlink to make ipfs command available in PATH..."
        ln -sf /usr/local/bin/ipfs /usr/bin/ipfs
    fi
fi

# Ensure ipfs user and group exist
if ! id -u ipfs &>/dev/null; then
    info "Creating 'ipfs' system user..."
    # Create group if it doesn't exist
    if ! getent group ipfs &>/dev/null; then
        groupadd -r ipfs
    fi
    useradd -r -d /var/lib/ipfs -g ipfs -s /usr/sbin/nologin ipfs
fi

# Ensure repository directory exists with correct ownership
mkdir -p /var/lib/ipfs
chown -R ipfs:ipfs /var/lib/ipfs
chmod 750 /var/lib/ipfs

# Initialize IPFS repository if not already initialized
export IPFS_PATH=/var/lib/ipfs
if [[ ! -f "/var/lib/ipfs/config" ]]; then
    info "Initializing IPFS repository (profile: server, empty repo)..."
    # --profile server will add connection filters.
    sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs init"
fi

# If a swarm key is provided, copy it into place
if [[ -n "$SWARM_KEY_FILE" ]]; then
    info "Integrating swarm key for private network..."
    
    # Check if it's a base64 encoded file
    if [[ "$SWARM_KEY_FILE" == *"base64"* ]] || [[ "$SWARM_KEY_FILE" == *"_base64.txt" ]]; then
        info "Decoding base64 swarm key file: $SWARM_KEY_FILE"
        if [[ ! -f "$SWARM_KEY_FILE" ]]; then
            error "Base64 swarm key file not found: $SWARM_KEY_FILE"
            exit 1
        fi
        # Decode base64 file and write to swarm.key
        base64 -d "$SWARM_KEY_FILE" > "/var/lib/ipfs/swarm.key"
        chown ipfs:ipfs "/var/lib/ipfs/swarm.key"
        chmod 600 "/var/lib/ipfs/swarm.key"
    else
        # Handle regular swarm key file
        # Only copy if not already in place or differs
        if [[ ! -f "/var/lib/ipfs/swarm.key" || $(diff -q "$SWARM_KEY_FILE" "/var/lib/ipfs/swarm.key") ]]; then
            cp -f "$SWARM_KEY_FILE" "/var/lib/ipfs/swarm.key"
            chown ipfs:ipfs "/var/lib/ipfs/swarm.key"
            chmod 600 "/var/lib/ipfs/swarm.key"
        fi
    fi
fi

# IPFS configuration adjustments
info "Configuring IPFS node settings..."
# Enable circuit relay v2 service (RelayService)
sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs config --json Swarm.RelayService.Enabled true"
# Disable client auto-relay unless explicitly needed (optional, default is false)
sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs config --json Swarm.RelayClient.Enable false" || true

# Remove default bootstrap nodes if using a private network (to avoid trying public bootstraps)
if [[ -f "/var/lib/ipfs/swarm.key" ]]; then
    info "Removing default bootstrap nodes for private network..."
    sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs bootstrap rm --all" >/dev/null 2>&1 || true
fi

# Create systemd service for IPFS
info "Setting up systemd service 'ipfs.service'..."
SERVICE_FILE=/etc/systemd/system/ipfs.service
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=IPFS Kubo daemon (relay node)
After=network.target

[Service]
Type=simple
User=ipfs
Group=ipfs
Environment=IPFS_PATH=/var/lib/ipfs
Environment=IPFS_FD_MAX=8192
$( [[ -f /var/lib/ipfs/swarm.key ]] && echo "Environment=LIBP2P_FORCE_PNET=1" )
ExecStart=/usr/local/bin/ipfs daemon
LimitNOFILE=8192
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd configuration and enable service
systemctl daemon-reload
systemctl enable ipfs

# Start (or restart) the IPFS service
systemctl restart ipfs

# Post-setup status check
sleep 3
if systemctl is-active --quiet ipfs; then
    info "IPFS Kubo relay node setup complete. Service 'ipfs' is active and running (version: $(ipfs --version))."
    
    # Display bootstrap information for other relay nodes
    info "Generating bootstrap information for other relay nodes..."
    PEER_ID=$(sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs id -f='<id>'")
    MY_IP=$(hostname -I | awk '{print $1}')
    MY_BOOTSTRAP="/ip4/$MY_IP/tcp/4001/p2p/$PEER_ID"
    
    info "Node Peer ID: $PEER_ID"
    info "Node IP: $MY_IP"
    echo -e "\033[1;36m[INFO] Bootstrap address: $MY_BOOTSTRAP\033[0m"
    echo -e "\033[1;36m[INFO] Please run the following command on the other relay servers:\033[0m"
    echo -e "\033[1;32mipfs bootstrap add $MY_BOOTSTRAP\033[0m"
else
    error "IPFS service failed to start. Please check 'journalctl -u ipfs' for details."
fi
