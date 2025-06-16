#!/bin/bash
# r1fs_check.sh - Enhanced diagnostic script for the IPFS Kubo relay node.
# This script checks the health of the IPFS daemon and relay configuration, including:
# - Daemon running status
# - Relay service configuration (circuit relay v2)
# - Private network enforcement (swarm.key presence and permissions)
# - Bootstrap peers configuration and connectivity
# - Number of connected peers
# - Network connectivity and port accessibility
# - Detailed peer connection analysis
# - Enhanced log analysis with timestamps
# - IPFS node identity and addressing information
# It outputs color-coded results for easy reading. Use --json for machine-readable output.
#
# Usage: r1fs_check.sh [--json] [--verbose]
VER="0.2.0"

set -e

# Color codes for output
RED="\033[0;31m"    # Red for errors/no
GREEN="\033[0;32m"  # Green for OK/yes
YELLOW="\033[0;33m" # Yellow for warnings
BLUE="\033[0;34m"   # Blue for info
CYAN="\033[0;36m"   # Cyan for commands
NC="\033[0m"       # No color

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
        cyan)
            color_code="0;36" # Cyan
            ;;
        *)
            color_code="0" # Default color
            ;;
    esac

    echo -e "\e[${color_code}m${text}\e[0m"
}

# Helper function to run commands and log them
run_and_log() {
    local cmd="$1"
    local description="$2"
    local show_output="${3:-true}"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_with_color "Running: $cmd" "cyan"
    fi
    
    if [[ "$show_output" == "true" ]]; then
        log_with_color "$description:" "blue"
        eval "$cmd" 2>&1 | sed 's/^/  /'
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

log_with_color "Starting Enhanced IPFS Check script (version $VER)..." "green"

JSON_OUTPUT=false
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Usage: $0 [--json] [--verbose]"
            exit 1
            ;;
    esac
done

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

log_with_color "=== BASIC SYSTEM INFORMATION ===" "blue"
run_and_log "date" "Current timestamp"
run_and_log "hostname -I" "Server IP addresses"
run_and_log "uname -a" "System information"

log_with_color "=== IPFS SERVICE STATUS ===" "blue"
# Check if IPFS is running
daemon_running=false
service_status=""
if systemctl is-active --quiet ipfs 2>/dev/null; then
    daemon_running=true
    service_status="active"
else
    service_status="inactive"
fi

run_and_log "systemctl status ipfs --no-pager -l" "IPFS service status"
run_and_log "ps aux | grep -i ipfs | grep -v grep" "IPFS processes"

# Check IPFS version
if command -v ipfs &> /dev/null; then
    run_and_log "ipfs --version" "IPFS version"
else
    log_with_color "IPFS binary not found in PATH" "red"
fi

log_with_color "=== IPFS REPOSITORY INFORMATION ===" "blue"
if [[ -d "/var/lib/ipfs" ]]; then
    run_and_log "ls -la /var/lib/ipfs/" "IPFS repository contents"
    run_and_log "stat /var/lib/ipfs" "Repository directory permissions"
    
    if [[ -f "/var/lib/ipfs/config" ]]; then
        log_with_color "Configuration file exists" "green"
        run_and_log "stat /var/lib/ipfs/config" "Config file permissions"
    else
        log_with_color "Configuration file missing!" "red"
    fi
else
    log_with_color "IPFS repository directory not found!" "red"
fi

log_with_color "=== NETWORK CONNECTIVITY ===" "blue"
# Test basic network connectivity
run_and_log "ping -c 3 8.8.8.8" "Internet connectivity test"
run_and_log "netstat -tlnp | grep :4001" "IPFS port 4001 listening status"
run_and_log "netstat -tlnp | grep :5001" "IPFS API port 5001 listening status"

# Test if we can reach the relay IP mentioned in the error
relay_ip="163.172.143.5"
log_with_color "Testing connectivity to problematic relay: $relay_ip" "blue"
run_and_log "ping -c 3 $relay_ip" "Ping test to $relay_ip"
run_and_log "telnet $relay_ip 4001 < /dev/null" "Port 4001 connectivity to $relay_ip" false

log_with_color "=== IPFS NODE IDENTITY ===" "blue"
if $daemon_running && command -v ipfs &> /dev/null; then
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs id'" "Node identity information"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs id -f=\"<id>\"'" "Peer ID only"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs id -f=\"<addrs>\"'" "Node addresses"
else
    log_with_color "Cannot get node identity - daemon not running or ipfs command unavailable" "yellow"
fi

log_with_color "=== SWARM AND PEER INFORMATION ===" "blue"
# Check swarm key presence and permissions
swarm_key_present=false
swarm_key_perms_ok=false
if [[ -f "/var/lib/ipfs/swarm.key" ]]; then
    swarm_key_present=true
    run_and_log "stat /var/lib/ipfs/swarm.key" "Swarm key file permissions"
    run_and_log "head -c 100 /var/lib/ipfs/swarm.key" "Swarm key content (first 100 chars)"
    
    # Check permissions (expect 600)
    perm="$(stat -c %a /var/lib/ipfs/swarm.key)" 
    owner="$(stat -c %U /var/lib/ipfs/swarm.key)" 
    if [[ "$perm" == "600" ]]; then
        swarm_key_perms_ok=true
        log_with_color "Swarm key permissions OK (600)" "green"
    else
        log_with_color "Swarm key permissions incorrect: $perm (should be 600)" "red"
    fi
    log_with_color "Swarm key owner: $owner" "blue"
else
    log_with_color "Swarm key not found - running on public IPFS network" "yellow"
fi

# Get detailed peer information
if $daemon_running && command -v ipfs &> /dev/null; then
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm peers'" "Connected peers"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm peers | wc -l'" "Number of connected peers"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm addrs'" "Peer addresses"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs stats bitswap'" "Bitswap statistics"
else
    log_with_color "Cannot get swarm information - daemon not running" "yellow"
fi

log_with_color "=== BOOTSTRAP CONFIGURATION ===" "blue"
# Get bootstrap peers from config
if $daemon_running && command -v ipfs &> /dev/null; then
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs bootstrap list'" "Bootstrap peers list"
    
    # Test connectivity to each bootstrap peer
    bootstrap_peers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && bootstrap_peers+=("$line")
    done < <(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs bootstrap list' 2>/dev/null || echo "")
    
    if [[ ${#bootstrap_peers[@]} -gt 0 ]]; then
        log_with_color "Testing bootstrap peer connectivity:" "blue"
        for addr in "${bootstrap_peers[@]}"; do
            if [[ -n "$addr" ]]; then
                peer_id=$(echo "$addr" | awk -F/ '{print $NF}')
                ip_addr=$(echo "$addr" | awk -F/ '{print $3}')
                port=$(echo "$addr" | awk -F/ '{print $5}')
                log_with_color "  Testing $addr" "cyan"
                log_with_color "    IP: $ip_addr, Port: $port, Peer ID: $peer_id" "gray"
                
                # Test if this peer is currently connected
                if sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs swarm peers" 2>/dev/null | grep -q "$peer_id"; then
                    log_with_color "    Status: CONNECTED" "green"
                else
                    log_with_color "    Status: NOT CONNECTED" "red"
                fi
                
                # Try to connect to this peer
                log_with_color "    Attempting connection..." "cyan"
                if sudo -u ipfs -H sh -c "IPFS_PATH=/var/lib/ipfs ipfs swarm connect '$addr'" 2>/dev/null; then
                    log_with_color "    Connection attempt: SUCCESS" "green"
                else
                    log_with_color "    Connection attempt: FAILED" "red"
                fi
            fi
        done
    else
        log_with_color "No bootstrap peers configured" "yellow"
    fi
else
    log_with_color "Cannot check bootstrap configuration - daemon not running" "yellow"
fi

log_with_color "=== RELAY CONFIGURATION ===" "blue"
# Check relay service configuration
if $daemon_running && command -v ipfs &> /dev/null; then
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Swarm.RelayService'" "Relay service configuration"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Swarm.RelayClient'" "Relay client configuration"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Swarm.Transports'" "Transport configuration"
    run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Addresses'" "Address configuration"
    
    # Show full swarm configuration
    if [[ "$VERBOSE" == "true" ]]; then
        run_and_log "sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Swarm'" "Full swarm configuration"
    fi
else
    log_with_color "Cannot check relay configuration - daemon not running" "yellow"
fi

log_with_color "=== ENHANCED LOG ANALYSIS ===" "blue"
# Get comprehensive log analysis
if command -v journalctl &> /dev/null; then
    log_with_color "Recent IPFS service logs (last 50 lines):" "blue"
    journalctl -u ipfs -n 50 --no-pager | sed 's/^/  /'
    
    log_with_color "Relay-specific log entries:" "blue"
    journalctl -u ipfs -b --no-pager | grep -i "relay" | tail -20 | sed 's/^/  /' || log_with_color "  No relay-specific log entries found" "gray"
    
    log_with_color "Connection-related log entries:" "blue"
    journalctl -u ipfs -b --no-pager | grep -i -E "(connect|disconnect|peer|swarm)" | tail -20 | sed 's/^/  /' || log_with_color "  No connection-related log entries found" "gray"
    
    log_with_color "Error log entries:" "blue"
    journalctl -u ipfs -b --no-pager | grep -i -E "(error|fail|warn)" | tail -20 | sed 's/^/  /' || log_with_color "  No error log entries found" "green"
    
    log_with_color "Circuit relay log entries:" "blue"
    journalctl -u ipfs -b --no-pager | grep -i "circuit" | tail -20 | sed 's/^/  /' || log_with_color "  No circuit relay log entries found" "gray"
else
    log_with_color "journalctl not available for log analysis" "yellow"
fi

log_with_color "=== FIREWALL AND SECURITY ===" "blue"
# Check firewall status
if command -v ufw &> /dev/null; then
    run_and_log "ufw status" "UFW firewall status"
fi

if command -v iptables &> /dev/null; then
    run_and_log "iptables -L -n | grep -E '(4001|5001)'" "iptables rules for IPFS ports" false
fi

# Check if SELinux is affecting operations
if command -v getenforce &> /dev/null; then
    run_and_log "getenforce" "SELinux status"
fi

log_with_color "=== DIAGNOSTIC SUMMARY ===" "blue"
log_with_color "Daemon running: $($daemon_running && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
log_with_color "Private network: $($swarm_key_present && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
log_with_color "Swarm key permissions: $($swarm_key_perms_ok && echo -e "${GREEN}OK${NC}" || echo -e "${RED}NOT OK${NC}")"

if $daemon_running && command -v ipfs &> /dev/null; then
    connected_peers_count=$(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm peers' 2>/dev/null | wc -l || echo "0")
    bootstrap_peers_count=$(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs bootstrap list' 2>/dev/null | wc -l || echo "0")
    
    log_with_color "Connected peers: $connected_peers_count" "blue"
    log_with_color "Bootstrap peers configured: $bootstrap_peers_count" "blue"
    
    # Check if relay service is enabled
    relay_enabled=$(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs config Swarm.RelayService.Enabled' 2>/dev/null || echo "false")
    log_with_color "Relay service enabled: $([[ "$relay_enabled" == "true" ]] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
fi

log_with_color "=== TROUBLESHOOTING RECOMMENDATIONS ===" "yellow"
if ! $daemon_running; then
    log_with_color "• IPFS daemon is not running. Start it with: systemctl start ipfs" "yellow"
fi

if [[ "$connected_peers_count" -eq 0 ]]; then
    log_with_color "• No peers connected. Check network connectivity and bootstrap configuration." "yellow"
fi

if ! $swarm_key_present; then
    log_with_color "• No swarm key found. If this should be a private network, ensure swarm.key is present." "yellow"
fi

if $swarm_key_present && ! $swarm_key_perms_ok; then
    log_with_color "• Swarm key permissions incorrect. Fix with: chmod 600 /var/lib/ipfs/swarm.key" "yellow"
fi

log_with_color "• For the specific relay error (163.172.143.5 not found), check if this relay is:" "yellow"
log_with_color "  - Added to bootstrap peers: ipfs bootstrap add /ip4/163.172.143.5/tcp/4001/p2p/PEER_ID" "yellow"
log_with_color "  - Accessible via network (ping and port 4001)" "yellow"
log_with_color "  - Using the same swarm key (for private networks)" "yellow"

log_with_color "=== SPECIFIC RELAY ERROR DEBUGGING ===" "blue"
# Specific debugging for the relay error from the terminal output
relay_error_ip="163.172.143.5"
log_with_color "Debugging relay error for IP: $relay_error_ip" "blue"

# Check if this IP is in bootstrap peers
if $daemon_running && command -v ipfs &> /dev/null; then
    log_with_color "Checking if $relay_error_ip is in bootstrap peers:" "blue"
    if sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs bootstrap list' 2>/dev/null | grep -q "$relay_error_ip"; then
        log_with_color "  $relay_error_ip found in bootstrap peers" "green"
        # Show the exact bootstrap entry
        bootstrap_entry=$(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs bootstrap list' 2>/dev/null | grep "$relay_error_ip")
        log_with_color "  Bootstrap entry: $bootstrap_entry" "cyan"
    else
        log_with_color "  $relay_error_ip NOT found in bootstrap peers" "red"
        log_with_color "  This is likely the cause of the error!" "red"
    fi
    
    # Try to detect the expected peer ID for this relay
    log_with_color "Checking current peer connections for $relay_error_ip:" "blue"
    if sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm peers' 2>/dev/null | grep -q "$relay_error_ip"; then
        relay_peer_conn=$(sudo -u ipfs -H sh -c 'IPFS_PATH=/var/lib/ipfs ipfs swarm peers' 2>/dev/null | grep "$relay_error_ip")
        log_with_color "  Current connection to $relay_error_ip: $relay_peer_conn" "green"
    else
        log_with_color "  No current connection to $relay_error_ip" "yellow"
    fi
    
    # Check recent attempts to connect to this relay
    log_with_color "Recent connection attempts to $relay_error_ip:" "blue"
    recent_attempts=$(journalctl -u ipfs --no-pager --since "1 hour ago" | grep "$relay_error_ip" | tail -5 || echo "No recent attempts found")
    if [[ "$recent_attempts" != "No recent attempts found" ]]; then
        echo "$recent_attempts" | sed 's/^/  /'
    else
        log_with_color "  No recent connection attempts found" "gray"
    fi
fi

log_with_color "=== CLIENT-SIDE DEBUGGING COMMANDS ===" "yellow"
log_with_color "To fix the relay error on the CLIENT side, try these commands:" "yellow"
log_with_color "1. Check if relay is configured as bootstrap peer:" "cyan"
log_with_color "   ipfs bootstrap list | grep $relay_error_ip" "gray"
log_with_color "2. Add relay to bootstrap (replace PEER_ID with actual peer ID):" "cyan"
log_with_color "   ipfs bootstrap add /ip4/$relay_error_ip/tcp/4001/p2p/PEER_ID" "gray"
log_with_color "3. Try manual connection to relay:" "cyan"
log_with_color "   ipfs swarm connect /ip4/$relay_error_ip/tcp/4001/p2p/PEER_ID" "gray"
log_with_color "4. Check if client can reach relay:" "cyan"
log_with_color "   ping $relay_error_ip" "gray"
log_with_color "   telnet $relay_error_ip 4001" "gray"
log_with_color "5. Restart IPFS daemon after adding bootstrap:" "cyan"
log_with_color "   systemctl restart ipfs" "gray"

log_with_color "Enhanced IPFS diagnostic check complete!" "green"
log_with_color "If issues persist, check both client and relay node configurations" "yellow"
