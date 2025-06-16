#!/bin/bash
# r1fs_update.sh - Update the Kubo (go-ipfs) binary for the IPFS relay node.
# This script downloads and installs a new Kubo version (defaults to latest release or a specific version if provided),
# preserving the existing IPFS configuration and swarm key. It will gracefully restart the IPFS service and verify the upgrade.
# Usage: sudo r1fs_update.sh [version]
#   version (optional) - The Kubo version to install (e.g., 0.36.0 or v0.36.0). If not provided, the latest stable version is used.
#
# The script ensures:
# - It is run with root privileges.
# - IPFS daemon is stopped cleanly before upgrade.
# - The specified (or latest) version of Kubo is downloaded and installed.
# - Existing config and data under IPFS_PATH (e.g., /var/lib/ipfs) remain intact.
# - The IPFS systemd service is restarted, and the new version is confirmed.
# - Temporary files are cleaned up and the script can be re-run safely.

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

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

TARGET_VER="$1"  # desired version argument (could be empty)
if ! command -v ipfs &> /dev/null; then
    error "IPFS is not installed on this system. Run r1fs_setup.sh first."
    exit 1
fi

CURRENT_VER="$(ipfs --version | awk '{print $NF}')"
# Determine target version (if not provided, fetch latest)
if [[ -z "$TARGET_VER" ]]; then
    info "No version specified, checking for latest Kubo release..."
    # Use GitHub API to get latest version tag
    if command -v curl &> /dev/null; then
        TARGET_VER="$(curl -fsSL https://api.github.com/repos/ipfs/kubo/releases/latest | grep -oP '\"tag_name\":\s*\"\K[^\"]+')"
    elif command -v wget &> /dev/null; then
        TARGET_VER="$(wget -qO- https://api.github.com/repos/ipfs/kubo/releases/latest | grep -oP '\"tag_name\":\s*\"\K[^\"]+')"
    else
        error "Neither curl nor wget is available to check latest version. Please provide a version argument."
        exit 1
    fi
    if [[ -z "$TARGET_VER" ]]; then
        error "Failed to fetch the latest Kubo version. Please provide a version manually."
        exit 1
    fi
    info "Latest Kubo release is $TARGET_VER"
fi

# Normalize version format (ensure it starts with 'v')
if [[ "$TARGET_VER" != v* ]]; then
    TARGET_VER="v${TARGET_VER}"
fi

# Compare with current version
if [[ "$CURRENT_VER" == "${TARGET_VER#v}" ]]; then
    info "IPFS is already at version ${CURRENT_VER}. No update needed."
    exit 0
fi

info "Preparing to update IPFS from version $CURRENT_VER to $TARGET_VER..."

# Stop IPFS service if running
if systemctl is-active --quiet ipfs; then
    info "Stopping IPFS service..."
    systemctl stop ipfs
elif pgrep -x ipfs >/dev/null; then
    info "Terminating running ipfs daemon..."
    pkill -9 -x ipfs || true
    sleep 2
fi

# Determine OS and architecture for download
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH="arm64"
else
    error "Unsupported architecture: $(uname -m). Cannot update."
    exit 1
fi

DOWNLOAD_URL="https://dist.ipfs.tech/kubo/${TARGET_VER}/kubo_${TARGET_VER}_linux-${ARCH}.tar.gz"
info "Downloading Kubo ${TARGET_VER#v} for $ARCH..."
TMP_DIR="$(mktemp -d)"
trap "rm -rf $TMP_DIR" EXIT
cd "$TMP_DIR"
if command -v curl &> /dev/null; then
    curl -fSL "$DOWNLOAD_URL" -o kubo.tar.gz
elif command -v wget &> /dev/null; then
    wget -q "$DOWNLOAD_URL" -O kubo.tar.gz
else
    error "Neither curl nor wget is available for downloading the update."
    exit 1
fi
if [[ ! -f kubo.tar.gz ]]; then
    error "Download failed for $DOWNLOAD_URL"
    exit 1
fi

info "Download complete. Verifying archive..." 
if command -v sha512sum &> /dev/null; then
    EXPECTED_HASH="$(curl -fsSL ${DOWNLOAD_URL}.sha512 | awk '{print $1}')"
    DOWNLOADED_HASH="$(sha512sum kubo.tar.gz | awk '{print $1}')"
    if [[ -n "$EXPECTED_HASH" && "$DOWNLOADED_HASH" != "$EXPECTED_HASH" ]]; then
        error "Checksum verification failed for $TARGET_VER archive."
        exit 1
    fi
fi

info "Installing Kubo $TARGET_VER..." 
tar -xzf kubo.tar.gz
cd kubo
bash install.sh
cd ~
# Clean up temporary files
rm -rf "$TMP_DIR"
trap - EXIT

# Clear shell command cache in case path was cached
hash -r

# Start or restart the IPFS service with new binary
info "Starting IPFS service with new version..."
systemctl start ipfs

sleep 3
NEW_VER="$(ipfs --version | awk '{print $NF}')"
if systemctl is-active --quiet ipfs && [[ "$NEW_VER" == "${TARGET_VER#v}" ]]; then
    info "Update successful: IPFS is now running version $NEW_VER."
else
    error "Update may have failed: IPFS service is not running the expected version. (Current: $NEW_VER, Expected: ${TARGET_VER#v}). Check logs with 'journalctl -u ipfs'."
    exit 1
fi
