#!/bin/bash
VER="0.1.0"

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

log_with_color "Starting IPFS Relay Remove script (version $VER)..." "green"

log_with_color "Starting IPFS removal process..." "blue"

# Step 1: Stop and disable IPFS service
if systemctl is-active --quiet ipfs 2>/dev/null; then
    log_with_color "Stopping IPFS service..." "blue"
    sudo systemctl stop ipfs
else
    log_with_color "IPFS service is not running" "gray"
fi

if systemctl is-enabled --quiet ipfs 2>/dev/null; then
    log_with_color "Disabling IPFS service..." "blue"
    sudo systemctl disable ipfs
else
    log_with_color "IPFS service is not enabled" "gray"
fi

# Kill any remaining IPFS processes
if pgrep -x ipfs >/dev/null; then
    log_with_color "Terminating remaining IPFS processes..." "yellow"
    pkill -9 -x ipfs || true
    sleep 2
fi

# Step 2: Remove systemd service file
if [ -f "/etc/systemd/system/ipfs.service" ]; then
    log_with_color "Removing systemd service file..." "blue"
    sudo rm -f /etc/systemd/system/ipfs.service
    sudo systemctl daemon-reload
else
    log_with_color "Systemd service file not found" "gray"
fi

# Step 3: Remove IPFS binary
if [ -f "/usr/local/bin/ipfs" ]; then
    log_with_color "Removing IPFS binary..." "blue"
    sudo rm -f /usr/local/bin/ipfs
else
    log_with_color "IPFS binary not found in /usr/local/bin/" "gray"
fi

# Step 4: Remove IPFS data directory
if [ -d "/root/.ipfs" ]; then
    log_with_color "Removing IPFS data directory (/root/.ipfs)..." "blue"
    sudo rm -rf /root/.ipfs
else
    log_with_color "IPFS data directory not found" "gray"
fi

# Step 5: Clean up installation files
log_with_color "Cleaning up installation files..." "blue"
rm -f kubo_v*.tar.gz 2>/dev/null || true
rm -rf kubo/ 2>/dev/null || true
rm -f swarm_key_base64.txt 2>/dev/null || true

# Step 6: Verify removal
log_with_color "Verifying removal..." "blue"

if command -v ipfs >/dev/null 2>&1; then
    log_with_color "Warning: IPFS command still available in PATH" "yellow"
    which ipfs
else
    log_with_color "IPFS binary successfully removed" "green"
fi

if [ -d "/root/.ipfs" ]; then
    log_with_color "Warning: IPFS data directory still exists" "yellow"
else
    log_with_color "IPFS data directory successfully removed" "green"
fi

if systemctl list-unit-files | grep -q "ipfs.service"; then
    log_with_color "Warning: IPFS systemd service still registered" "yellow"
else
    log_with_color "IPFS systemd service successfully removed" "green"
fi

log_with_color "IPFS removal completed!" "blue"
log_with_color "Note: If IPFS was installed via package manager, you may need to use that method to fully remove it." "yellow" 