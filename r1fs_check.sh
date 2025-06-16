#!/bin/bash
# r1fs_check.sh - Diagnostic script for the IPFS Kubo relay node.
# This script checks the health of the IPFS daemon and relay configuration, including:
# - Daemon running status
# - Relay service configuration (circuit relay v2)
# - Private network enforcement (swarm.key presence and permissions)
# - Bootstrap peers configuration and connectivity
# - Number of connected peers
# - Recent log entries for relay-related warnings or errors
# It outputs color-coded results for easy reading. Use --json for machine-readable output.
#
# Usage: r1fs_check.sh [--json]

set -e

# Color codes for output
RED="\033[0;31m"    # Red for errors/no
GREEN="\033[0;32m"  # Green for OK/yes
YELLOW="\033[0;33m" # Yellow for warnings
NC="\033[0m"       # No color

JSON_OUTPUT=false
if [[ "$1" == "--json" ]]; then
    JSON_OUTPUT=true
fi

# Ensure running as root to access IPFS repo and journal logs
if [[ $EUID -ne 0 ]]; then
    if $JSON_OUTPUT; then
        echo "{\"error\":\"Root privileges required to run this script.\"}"
    else
        echo -e "${RED}Error: This script must be run as root (or via sudo).${NC}" >&2
    fi
    exit 1
fi

# Use the system IPFS repository path
export IPFS_PATH=/var/lib/ipfs

# Check if IPFS is running
daemon_running=false
if systemctl is-active --quiet ipfs 2>/dev/null; then
    daemon_running=true
fi

# Check relay service configuration
relay_enabled="unknown"
if ipfs config Swarm.RelayService.Enabled &> /dev/null; then
    relay_enabled=$(ipfs config Swarm.RelayService.Enabled)
    # Normalize to true/false strings
    [[ "$relay_enabled" == "True" || "$relay_enabled" == "true" ]] && relay_enabled=true || relay_enabled=false
else
    # If config key is not present, assume default (true for publicly reachable nodes)
    relay_enabled=true
fi

# Check swarm key presence and permissions
swarm_key_present=false
swarm_key_perms_ok=false
if [[ -f "/var/lib/ipfs/swarm.key" ]]; then
    swarm_key_present=true
    # Check permissions (expect 600)
    perm="$(stat -c %a /var/lib/ipfs/swarm.key)" 
    owner="$(stat -c %U /var/lib/ipfs/swarm.key)" 
    if [[ "$perm" == "600" ]]; then
        swarm_key_perms_ok=true
    fi
else
    swarm_key_present=false
    swarm_key_perms_ok=false
fi

# Get bootstrap peers from config
bootstrap_peers=()
while IFS= read -r line; do
    [[ -n "$line" ]] && bootstrap_peers+=("$line")
done < <(ipfs bootstrap list || echo "")

# Determine connectivity of bootstrap peers (if daemon is running)
bootstrap_status=()
connected_peers_list=""
connected_peers_count=0
if $daemon_running; then
    connected_peers_list="$(ipfs swarm peers || echo "")"
    # Count connected peers
    if [[ -n "$connected_peers_list" ]]; then
        connected_peers_count=$(echo "$connected_peers_list" | sed '/^$/d' | wc -l)
    else
        connected_peers_count=0
    fi
    # Check each bootstrap peer for connection status
    for addr in "${bootstrap_peers[@]}"; do
        if [[ -n "$addr" ]]; then
            peer_id=$(echo "$addr" | awk -F/ '{print $NF}')
            if echo "$connected_peers_list" | grep -q "$peer_id"; then
                bootstrap_status+=("$addr|true")
            else
                bootstrap_status+=("$addr|false")
            fi
        fi
    done
else
    connected_peers_count=0
    for addr in "${bootstrap_peers[@]}"; do
        [[ -n "$addr" ]] && bootstrap_status+=("$addr|false")
    done
fi

# Get relay-related log lines (warnings/errors)
relay_warnings=()
relay_errors=()
# Only gather logs if journalctl is available
if command -v journalctl &> /dev/null; then
    # Retrieve logs since last boot and filter for 'relay'
    # Then separate warnings and errors
    while IFS= read -r line; do
        [[ -n "$line" ]] && relay_warnings+=("$line")
    done < <(journalctl -u ipfs -b --no-pager | grep -i "relay" | grep -i "warn" || echo "")
    while IFS= read -r line; do
        [[ -n "$line" ]] && relay_errors+=("$line")
    done < <(journalctl -u ipfs -b --no-pager | grep -i "relay" | grep -i "error" || echo "")
fi

# Output results
if $JSON_OUTPUT; then
    # Build JSON output
    printf "{"
    printf "\"daemonRunning\": %s, " "$([[ $daemon_running == true ]] && echo true || echo false)"
    printf "\"relayEnabled\": %s, " "$([[ $relay_enabled == true ]] && echo true || echo false)"
    printf "\"swarmKeyPresent\": %s, " "$([[ $swarm_key_present == true ]] && echo true || echo false)"
    printf "\"swarmKeyPermsOK\": %s, " "$([[ $swarm_key_perms_ok == true ]] && echo true || echo false)"
    printf "\"connectedPeers\": %d, " "$connected_peers_count"
    printf "\"bootstrapPeers\": ["
    for ((i=0; i<${#bootstrap_status[@]}; i++)); do
        IFS='|' read -r addr connected <<< "${bootstrap_status[i]}"
        # Escape backslashes and quotes in address
        safe_addr=$(echo -n "$addr" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf "{\"\%s\": \"%s\", \"connected\": %s}" "address" "$safe_addr" "$([[ $connected == true ]] && echo true || echo false)"
        [[ $i -lt $((${#bootstrap_status[@]}-1)) ]] && printf ", "
    done
    printf "], "
    printf "\"relayLogs\": {\"warnings\": ["
    for ((i=0; i<${#relay_warnings[@]}; i++)); do
        # Escape special characters in log line
        safe_line=$(echo -n "${relay_warnings[i]}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf "\"%s\"" "$safe_line"
        [[ $i -lt $((${#relay_warnings[@]}-1)) ]] && printf ", "
    done
    printf "], \"errors\": ["
    for ((i=0; i<${#relay_errors[@]}; i++)); do
        safe_line=$(echo -n "${relay_errors[i]}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf "\"%s\"" "$safe_line"
        [[ $i -lt $((${#relay_errors[@]}-1)) ]] && printf ", "
    done
    printf "]}}\n"
else
    # Human-readable output
    echo -e "Daemon running: $($daemon_running && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
    echo -e "Relay service enabled: $([[ $relay_enabled == true ]] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
    if $swarm_key_present; then
        if $swarm_key_perms_ok; then
            echo -e "Private network: ${GREEN}YES${NC} (swarm.key present with correct permissions)"
        else
            echo -e "Private network: ${YELLOW}YES${NC} (swarm.key present, but permissions ${RED}not secure${NC})"
        fi
    else
        echo -e "Private network: ${RED}NO${NC} (swarm.key not found)"
    fi
    echo -e "Connected peers: ${connected_peers_count}"
    echo -e "Bootstrap peers:"
    if [[ ${#bootstrap_status[@]} -gt 0 ]]; then
        for entry in "${bootstrap_status[@]}"; do
            IFS='|' read -r addr connected <<< "$entry"
            status_str=$([[ $connected == true ]] && echo -e "${GREEN}connected${NC}" || echo -e "${RED}not connected${NC}")
            echo -e "  $addr - $status_str"
        done
    else
        echo "  (none)"
    fi
    # Relay-related logs
    echo -e "Relay logs (recent):"
    if [[ ${#relay_warnings[@]} -eq 0 && ${#relay_errors[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}No relay-related warnings or errors found in logs.${NC}"
    else
        for line in "${relay_warnings[@]}"; do
            echo -e "  ${YELLOW}${line}${NC}"
        done
        for line in "${relay_errors[@]}"; do
            echo -e "  ${RED}${line}${NC}"
        done
    fi
fi
