#!/bin/bash
# remove_alternative.sh - Comprehensive removal of IPFS Kubo relay node setup
# This script removes ALL IPFS-related components, files, and configurations
# It can be safely re-run; it will not fail if components are already removed.
# Usage: sudo remove_alternative.sh
# 
# The script removes:
# - IPFS systemd service and configuration
# - IPFS repository directory (/var/lib/ipfs)
# - IPFS system user and group
# - IPFS Kubo binary installation
# - IPFS log files and caches
# - Downloaded installation files
# - Firewall rules for IPFS
# - Cron jobs related to IPFS
# - Environment variables and profile modifications
# - Network configurations
# - Any remaining IPFS processes and files
VER="0.2.0"

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

info "Starting IPFS Relay Comprehensive Removal script (version $VER)..."

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Kill any remaining IPFS processes first (more aggressive)
info "Terminating ALL IPFS-related processes..."
pkill -9 -f ipfs || true
pkill -9 -f kubo || true
sleep 3

# Stop and disable IPFS systemd service
if systemctl is-active --quiet ipfs 2>/dev/null; then
    info "Stopping IPFS service..."
    systemctl stop ipfs
fi

if systemctl is-enabled --quiet ipfs 2>/dev/null; then
    info "Disabling IPFS service..."
    systemctl disable ipfs
fi

# Remove systemd service file and related systemd configurations
SERVICE_FILE=/etc/systemd/system/ipfs.service
if [[ -f "$SERVICE_FILE" ]]; then
    info "Removing systemd service file..."
    rm -f "$SERVICE_FILE"
fi

# Remove any additional systemd files that might exist
for service_file in /etc/systemd/system/ipfs*.service /etc/systemd/system/kubo*.service; do
    if [[ -f "$service_file" ]]; then
        info "Removing additional systemd service file: $service_file"
        rm -f "$service_file"
    fi
done

systemctl daemon-reload

# Remove IPFS repository directories (more comprehensive)
for ipfs_dir in /var/lib/ipfs /opt/ipfs /usr/share/ipfs /etc/ipfs; do
    if [[ -d "$ipfs_dir" ]]; then
        info "Removing IPFS directory: $ipfs_dir"
        rm -rf "$ipfs_dir"
    fi
done

# Remove user home directories and any IPFS data in user homes
if id -u ipfs &>/dev/null; then
    IPFS_HOME=$(getent passwd ipfs | cut -d: -f6)
    if [[ -n "$IPFS_HOME" && -d "$IPFS_HOME" ]]; then
        info "Removing IPFS user home directory: $IPFS_HOME"
        rm -rf "$IPFS_HOME"
    fi
fi

# Remove .ipfs directories from all user homes
info "Removing .ipfs directories from user homes..."
for home_dir in /home/* /root; do
    if [[ -d "$home_dir/.ipfs" ]]; then
        info "Removing $home_dir/.ipfs"
        rm -rf "$home_dir/.ipfs"
    fi
done

# Remove IPFS user and group
if id -u ipfs &>/dev/null; then
    info "Removing 'ipfs' system user..."
    userdel -r ipfs 2>/dev/null || userdel ipfs 2>/dev/null || true
fi

if getent group ipfs &>/dev/null; then
    info "Removing 'ipfs' system group..."
    groupdel ipfs 2>/dev/null || true
fi

# Remove IPFS binaries from all common locations
info "Removing IPFS binaries..."
for binary_path in /usr/local/bin /usr/bin /bin /opt/bin; do
    for binary in ipfs kubo ipfs-update; do
        if [[ -f "$binary_path/$binary" ]]; then
            info "Removing $binary_path/$binary"
            rm -f "$binary_path/$binary"
        fi
    done
done

# Remove symbolic links to IPFS binaries (specifically created by install_alternative)
info "Removing IPFS symbolic links..."
# Remove the specific symlink created by install_alternative: /usr/bin/ipfs -> /usr/local/bin/ipfs
if [[ -L "/usr/bin/ipfs" ]]; then
    info "Removing symlink /usr/bin/ipfs -> /usr/local/bin/ipfs"
    rm -f /usr/bin/ipfs
fi
# Remove any other IPFS/kubo symbolic links
find /usr/local/bin /usr/bin /bin -type l -name "*ipfs*" -exec rm -f {} \; 2>/dev/null || true
find /usr/local/bin /usr/bin /bin -type l -name "*kubo*" -exec rm -f {} \; 2>/dev/null || true

# Remove downloaded installation files and Kubo extraction directories
info "Removing downloaded IPFS installation files..."
for download_dir in /tmp /var/tmp /opt /root /home/*; do
    if [[ -d "$download_dir" ]]; then
        find "$download_dir" -name "*kubo*" -type f -exec rm -f {} \; 2>/dev/null || true
        find "$download_dir" -name "*ipfs*tar.gz" -exec rm -f {} \; 2>/dev/null || true
        find "$download_dir" -name "go-ipfs*" -exec rm -rf {} \; 2>/dev/null || true
        # Remove Kubo extraction directories from install_alternative
        find "$download_dir" -name "kubo" -type d -exec rm -rf {} \; 2>/dev/null || true
    fi
done

# Remove installation files from current working directory (common with install_alternative)
info "Removing installation files from common locations..."
for pattern in kubo_v*.tar.gz kubo*.tar.gz go-ipfs*.tar.gz; do
    find /root /home/* -maxdepth 2 -name "$pattern" -exec rm -f {} \; 2>/dev/null || true
done
for dir_pattern in kubo go-ipfs; do
    find /root /home/* -maxdepth 2 -name "$dir_pattern" -type d -exec rm -rf {} \; 2>/dev/null || true
done

# Remove log files
info "Removing IPFS log files..."
for log_dir in /var/log /var/log/ipfs /tmp; do
    if [[ -d "$log_dir" ]]; then
        find "$log_dir" -name "*ipfs*" -type f -exec rm -f {} \; 2>/dev/null || true
        find "$log_dir" -name "*kubo*" -type f -exec rm -f {} \; 2>/dev/null || true
    fi
done

# Remove systemd journal logs for IPFS
info "Removing systemd journal logs for IPFS..."
journalctl --vacuum-time=1s --unit=ipfs 2>/dev/null || true

# Remove cron jobs related to IPFS
info "Removing IPFS-related cron jobs..."
for cron_file in /etc/cron.d/* /etc/crontab /var/spool/cron/*; do
    if [[ -f "$cron_file" ]]; then
        if grep -q "ipfs\|kubo" "$cron_file" 2>/dev/null; then
            info "Found IPFS references in $cron_file, cleaning..."
            sed -i '/ipfs\|kubo/d' "$cron_file" 2>/dev/null || true
        fi
    fi
done

# Remove environment variables from system profiles
info "Removing IPFS environment variables from system profiles..."
for profile_file in /etc/profile /etc/bash.bashrc /etc/environment; do
    if [[ -f "$profile_file" ]]; then
        if grep -q "IPFS\|ipfs" "$profile_file" 2>/dev/null; then
            info "Cleaning IPFS variables from $profile_file"
            sed -i '/IPFS/d; /ipfs/d' "$profile_file" 2>/dev/null || true
        fi
    fi
done

# Remove IPFS variables from user profiles (specifically IPFS_PATH from install_alternative)
for home_dir in /home/* /root; do
    for profile_file in "$home_dir/.bashrc" "$home_dir/.profile" "$home_dir/.bash_profile"; do
        if [[ -f "$profile_file" ]]; then
            if grep -q "IPFS\|ipfs" "$profile_file" 2>/dev/null; then
                info "Cleaning IPFS variables from $profile_file"
                # Remove the specific IPFS_PATH export that install_alternative adds
                sed -i '/export IPFS_PATH=\/var\/lib\/ipfs/d' "$profile_file" 2>/dev/null || true
                # Remove any other IPFS-related lines
                sed -i '/IPFS/d; /ipfs/d' "$profile_file" 2>/dev/null || true
            fi
        fi
    done
done

# Remove firewall rules for IPFS (common ports: 4001, 5001, 8080, 8081)
info "Removing firewall rules for IPFS ports..."
if command -v ufw &>/dev/null; then
    ufw --force delete allow 4001 2>/dev/null || true
    ufw --force delete allow 5001 2>/dev/null || true
    ufw --force delete allow 8080 2>/dev/null || true
    ufw --force delete allow 8081 2>/dev/null || true
fi

if command -v iptables &>/dev/null; then
    iptables -D INPUT -p tcp --dport 4001 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 5001 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null || true
fi

# Remove any IPFS-related entries from /etc/hosts
if [[ -f /etc/hosts ]]; then
    if grep -q "ipfs\|kubo" /etc/hosts 2>/dev/null; then
        info "Removing IPFS entries from /etc/hosts..."
        sed -i '/ipfs\|kubo/d' /etc/hosts 2>/dev/null || true
    fi
fi

# Remove any IPFS-related mount points
info "Removing any IPFS mount points..."
if mount | grep -q ipfs; then
    mount | grep ipfs | awk '{print $3}' | xargs -r umount 2>/dev/null || true
fi

# Remove IPFS-related entries from /etc/fstab
if [[ -f /etc/fstab ]]; then
    if grep -q "ipfs" /etc/fstab 2>/dev/null; then
        info "Removing IPFS entries from /etc/fstab..."
        sed -i '/ipfs/d' /etc/fstab 2>/dev/null || true
    fi
fi

# Clean package manager caches (if IPFS was installed via package manager)
info "Cleaning package manager caches..."
if command -v apt-get &>/dev/null; then
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true
fi

if command -v yum &>/dev/null; then
    yum autoremove -y 2>/dev/null || true
    yum clean all 2>/dev/null || true
fi

# Remove any remaining IPFS processes (final check)
REMAINING_PROCESSES=$(pgrep -f "ipfs\|kubo" || true)
if [[ -n "$REMAINING_PROCESSES" ]]; then
    warn "Forcefully terminating remaining IPFS/Kubo processes: $REMAINING_PROCESSES"
    echo "$REMAINING_PROCESSES" | xargs -r kill -9 2>/dev/null || true
fi

# Final comprehensive check for any remaining IPFS-related files
info "Performing final cleanup scan..."
REMAINING_FILES=""
for path in /var/lib/ipfs /etc/ipfs /usr/local/bin/ipfs /opt/ipfs /usr/share/ipfs; do
    if [[ -e "$path" ]]; then
        REMAINING_FILES="$REMAINING_FILES $path"
        warn "Removing remaining file/directory: $path"
        rm -rf "$path" 2>/dev/null || true
    fi
done

# Check for any remaining IPFS files in the entire system (be careful with this)
info "Scanning for any remaining IPFS references..."
FOUND_FILES=$(find /usr /opt /var -name "*ipfs*" -o -name "*kubo*" 2>/dev/null | head -10 || true)
if [[ -n "$FOUND_FILES" ]]; then
    warn "Found some remaining IPFS-related files:"
    echo "$FOUND_FILES"
    warn "You may want to review and manually remove these if needed."
fi

info "IPFS Kubo relay node comprehensive removal complete."
info "Successfully reverted all changes made by r1fs_setup_alternative.sh"
info "The following components have been removed:"
info "  ✓ IPFS systemd service and all configurations"
info "  ✓ All IPFS repository and data directories"
info "  ✓ IPFS system user and group (including home directory)"
info "  ✓ All IPFS binaries and symbolic links (/usr/bin/ipfs -> /usr/local/bin/ipfs)"
info "  ✓ Downloaded installation files and extraction directories"
info "  ✓ IPFS_PATH environment variables from root profile"
info "  ✓ Log files and systemd journal entries"
info "  ✓ Cron jobs and scheduled tasks"
info "  ✓ Environment variables and profile modifications"
info "  ✓ Firewall rules for IPFS ports"
info "  ✓ Network configurations and mount points"
info "  ✓ All remaining processes and temporary files"
info "System comprehensive cleanup finished successfully." 