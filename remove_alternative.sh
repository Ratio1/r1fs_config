#!/bin/bash
# remove_alternative.sh - Remove IPFS Kubo relay node setup
# This script removes the IPFS installation, systemd service, user, and data created by r1fs_setup_alternative.sh
# It can be safely re-run; it will not fail if components are already removed.
# Usage: sudo remove_alternative.sh
# 
# The script removes:
# - IPFS systemd service and configuration
# - IPFS repository directory (/var/lib/ipfs)
# - IPFS system user and group
# - IPFS Kubo binary installation
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

info "Starting IPFS Relay Remove Alternative script (version $VER)..."

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Stop and disable IPFS systemd service
if systemctl is-active --quiet ipfs 2>/dev/null; then
    info "Stopping IPFS service..."
    systemctl stop ipfs
fi

if systemctl is-enabled --quiet ipfs 2>/dev/null; then
    info "Disabling IPFS service..."
    systemctl disable ipfs
fi

# Remove systemd service file
SERVICE_FILE=/etc/systemd/system/ipfs.service
if [[ -f "$SERVICE_FILE" ]]; then
    info "Removing systemd service file..."
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
fi

# Kill any remaining IPFS processes
if pgrep -x ipfs >/dev/null; then
    info "Terminating any remaining IPFS daemon processes..."
    pkill -9 -x ipfs || true
    sleep 2
fi

# Remove IPFS repository directory
if [[ -d "/var/lib/ipfs" ]]; then
    info "Removing IPFS repository directory (/var/lib/ipfs)..."
    rm -rf /var/lib/ipfs
fi

# Remove IPFS user and group
if id -u ipfs &>/dev/null; then
    info "Removing 'ipfs' system user..."
    userdel ipfs 2>/dev/null || true
fi

if getent group ipfs &>/dev/null; then
    info "Removing 'ipfs' system group..."
    groupdel ipfs 2>/dev/null || true
fi

# Remove IPFS binary
if [[ -f "/usr/local/bin/ipfs" ]]; then
    info "Removing IPFS binary from /usr/local/bin..."
    rm -f /usr/local/bin/ipfs
fi

# Remove any other IPFS-related binaries that might have been installed
for binary in ipfs-update ipfs; do
    if command -v "$binary" &>/dev/null && [[ "$(which "$binary")" == "/usr/local/bin/$binary" ]]; then
        info "Removing additional IPFS binary: $binary"
        rm -f "/usr/local/bin/$binary"
    fi
done

# Remove any IPFS configuration directories that might exist
if [[ -d "/etc/ipfs" ]]; then
    info "Removing /etc/ipfs directory..."
    rm -rf /etc/ipfs
fi

# Check if there are any remaining IPFS processes or files
REMAINING_PROCESSES=$(pgrep -f ipfs || true)
if [[ -n "$REMAINING_PROCESSES" ]]; then
    warn "Some IPFS processes may still be running. PIDs: $REMAINING_PROCESSES"
    warn "You may need to manually terminate them."
fi

# Check for any remaining IPFS-related files in common locations
REMAINING_FILES=""
for path in /var/lib/ipfs /etc/ipfs /usr/local/bin/ipfs ~/.ipfs /root/.ipfs; do
    if [[ -e "$path" ]]; then
        REMAINING_FILES="$REMAINING_FILES $path"
    fi
done

if [[ -n "$REMAINING_FILES" ]]; then
    warn "Some IPFS-related files may still exist:$REMAINING_FILES"
    warn "You may need to manually remove them if desired."
fi

info "IPFS Kubo relay node removal complete."
info "The following components have been removed:"
info "  - IPFS systemd service (ipfs.service)"
info "  - IPFS repository directory (/var/lib/ipfs)"
info "  - IPFS system user and group (ipfs)"
info "  - IPFS binary (/usr/local/bin/ipfs)"
info "System cleanup finished successfully." 