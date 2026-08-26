#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo -e "${RED}✗ config.sh not found${NC}"
    exit 1
fi

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Please run as root (use sudo)${NC}"
    exit 1
fi

# Mode detection
RAW_MODE=false
PROXY_MODE=false
XRAY_MODE=false

if [ "$1" == "--raw" ]; then
    RAW_MODE=true
elif [ "$1" == "--proxy" ]; then
    PROXY_MODE=true
    [ -n "$2" ] && PROXYCHAINS_PROXY="$2"
else
    XRAY_MODE=true
fi

PROXYCHAINS_PROXY_HOST=$(echo "$PROXYCHAINS_PROXY" | cut -d':' -f1)
PROXYCHAINS_PROXY_PORT=$(echo "$PROXYCHAINS_PROXY" | cut -d':' -f2)

# Network detection
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
[ -z "$INTERFACE" ] && { echo -e "${RED}✗ Network interface not found${NC}"; exit 1; }

GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

# TUN settings
TUN_NAME="xray0"
TUN_ADDRESS="10.10.10.10"

# Process IDs
XRAY_SOCKS_PID=""
SSH_PID=""
XRAY_TUN_PID=""

# Stop flag to prevent double execution
STOP_EXECUTED=false

# ProxyChains config path
PROXYCHAINS_CONFIG="$SCRIPT_DIR/proxychains.conf"

# Display header
echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}       xray2vpn - Xray TUN VPN      ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
echo ""

if [ "$XRAY_MODE" == true ]; then
    echo -e "${YELLOW}Mode:${NC} Xray + SSH"
elif [ "$RAW_MODE" == true ]; then
    echo -e "${YELLOW}Mode:${NC} Raw SSH"
elif [ "$PROXY_MODE" == true ]; then
    echo -e "${YELLOW}Mode:${NC} Proxy ($PROXYCHAINS_PROXY_HOST:$PROXYCHAINS_PROXY_PORT)"
fi

echo -e "${YELLOW}Interface:${NC} $INTERFACE"
echo -e "${YELLOW}Gateway:${NC} $GATEWAY"
echo ""

# Add direct routing rule for specific address (IP or domain)
addDirectRoutingRule() {
    local address=$1

    # Check if it's IP or domain
    if [[ $address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # It's an IP address
        jq --arg ip "$address" '
            .routing.rules = [{"type": "field", "outboundTag": "direct", "ip": [$ip]}] + .routing.rules
        ' "$XRAY_TUN_CONFIG_PATH" > "$XRAY_TUN_CONFIG_PATH.tmp" && mv "$XRAY_TUN_CONFIG_PATH.tmp" "$XRAY_TUN_CONFIG_PATH"
    else
        # It's a domain
        jq --arg domain "$address" '
            .routing.rules = [{"type": "field", "outboundTag": "direct", "domain": [$domain]}] + .routing.rules
        ' "$XRAY_TUN_CONFIG_PATH" > "$XRAY_TUN_CONFIG_PATH.tmp" && mv "$XRAY_TUN_CONFIG_PATH.tmp" "$XRAY_TUN_CONFIG_PATH"
    fi
}

executeXraySocks() {
    echo -e "${YELLOW}⚙${NC}  Starting Xray SOCKS..."
    jq --slurpfile outs "$XRAY_SOCKS_OUTBOUNDS_PATH" '.outbounds = $outs[0]' "$XRAY_SOCKS_BASE_CONFIG_PATH" > "$XRAY_SOCKS_CONFIG_PATH"

    # Add interface binding to all outbounds so Xray SOCKS doesn't use TUN
    jq --arg iface "$INTERFACE" '
        .outbounds |= map(
            .streamSettings.sockopt.interface = $iface
        )
    ' "$XRAY_SOCKS_CONFIG_PATH" > "$XRAY_SOCKS_CONFIG_PATH.tmp" && mv "$XRAY_SOCKS_CONFIG_PATH.tmp" "$XRAY_SOCKS_CONFIG_PATH"

    (cd "$XRAY_PATH" && ./xray run -c "$XRAY_SOCKS_CONFIG_PATH") &>/dev/null &
    XRAY_SOCKS_PID=$!
    echo -e "${GREEN}✓${NC} Xray SOCKS running (PID: $XRAY_SOCKS_PID)"
    sleep 1
}

createProxychainsConfig() {
    cat > "$PROXYCHAINS_CONFIG" << EOF
strict_chain
quiet_mode
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 $PROXYCHAINS_PROXY_HOST $PROXYCHAINS_PROXY_PORT
EOF
}

executeSSH() {
    echo -e "${YELLOW}⚙${NC}  Starting SSH tunnel..."

    # SSH options for connection stability
    local SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes -o ConnectTimeout=30 -o ExitOnForwardFailure=no"

    if [ "$RAW_MODE" == true ]; then
        # Direct SSH (no proxy)
        sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS &>/dev/null &
    else
        # SSH via ProxyChains
        proxychains -f "$PROXYCHAINS_CONFIG" sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS &>/dev/null &
    fi

    SSH_PID=$!
    echo -e "${GREEN}✓${NC} SSH tunnel running (PID: $SSH_PID)"
    sleep 1
}

updateTunConfig() {
    # Start from base config and update interface in direct outbound only
    jq --arg iface "$INTERFACE" '
        .outbounds |= map(if .tag == "direct" then .streamSettings.sockopt.interface = $iface else . end)
    ' "$XRAY_TUN_BASE_CONFIG_PATH" > "$XRAY_TUN_CONFIG_PATH"

    # Add routing rules to bypass TUN for server addresses (only for RAW mode)
    # Note: In Xray mode, we don't need this because Xray SOCKS has interface binding
    if [ "$RAW_MODE" == true ]; then
        # In raw mode, SSH server must bypass TUN
        addDirectRoutingRule "$SERVER_ADDRESS"
    fi
}

executeXrayTun() {
    echo -e "${YELLOW}⚙${NC}  Starting Xray TUN..."

    (cd "$XRAY_PATH" && ./xray run -c "$XRAY_TUN_CONFIG_PATH") &>/dev/null &
    XRAY_TUN_PID=$!
    echo -e "${GREEN}✓${NC} Xray TUN running (PID: $XRAY_TUN_PID)"
    sleep 1

    # Configure TUN interface
    ip addr add $TUN_ADDRESS/24 dev $TUN_NAME 2>/dev/null
    ip link set dev $TUN_NAME up
    echo -e "${GREEN}✓${NC} TUN interface up: $TUN_NAME ($TUN_ADDRESS)"

    # Add default route via TUN (all traffic goes through TUN)
    # Note: This causes existing connections to drop, so we start SSH AFTER this
    ip route add default via $TUN_ADDRESS dev $TUN_NAME metric 1

    # Direct DNS queries to TUN so Xray sniffing can capture them
    resolvectl dns $TUN_NAME 1.1.1.1 8.8.8.8
    resolvectl domain $TUN_NAME "~."
    echo -e "${GREEN}✓${NC} DNS directed to TUN (Xray will handle via DoH)"
}

stopXrayTun() {
    if [ -n "$XRAY_TUN_PID" ] && ps -p $XRAY_TUN_PID >/dev/null 2>&1; then
        kill -9 $XRAY_TUN_PID
        echo -e "${GREEN}✓${NC} Xray TUN stopped"
    fi

    # Remove TUN route
    ip route del default via $TUN_ADDRESS dev $TUN_NAME 2>/dev/null || true

    # Restore DNS settings
    resolvectl revert $TUN_NAME 2>/dev/null || true

    echo -e "${GREEN}✓${NC} Routes and DNS cleaned"
}

stopSSH() {
    if [ -n "$SSH_PID" ] && ps -p $SSH_PID >/dev/null 2>&1; then
        kill -9 $SSH_PID
        echo -e "${GREEN}✓${NC} SSH stopped"
    fi
}

stopXraySocks() {
    if [ -n "$XRAY_SOCKS_PID" ] && ps -p $XRAY_SOCKS_PID >/dev/null 2>&1; then
        kill -9 $XRAY_SOCKS_PID
        echo -e "${GREEN}✓${NC} Xray SOCKS stopped"
    fi
}

# Clean up ProxyChains config file
cleanupProxychains() {
    if [ -f "$PROXYCHAINS_CONFIG" ]; then
        rm -f "$PROXYCHAINS_CONFIG"
    fi
}

# ============================================
# Main Flow
# ============================================

start() {
    updateTunConfig

    # Start services based on mode
    if [ "$XRAY_MODE" == true ]; then
        executeXraySocks
        createProxychainsConfig
        executeXrayTun
        executeSSH
    elif [ "$RAW_MODE" == true ]; then
        executeXrayTun
        executeSSH
    elif [ "$PROXY_MODE" == true ]; then
        createProxychainsConfig
        executeXrayTun
        executeSSH
    fi

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          VPN Connected! ✓          ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to disconnect${NC}"
    echo ""

    # Wait for Xray TUN process
    wait $XRAY_TUN_PID
}

stop() {
    # Prevent double execution
    if [ "$STOP_EXECUTED" == true ]; then
        return
    fi
    STOP_EXECUTED=true

    echo ""
    echo -e "${YELLOW}Disconnecting...${NC}"

    stopXrayTun
    stopSSH

    [ "$XRAY_MODE" == true ] && stopXraySocks
    [ "$RAW_MODE" == false ] && cleanupProxychains

    echo -e "${RED}╔════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}        VPN Disconnected            ${RED}║${NC}"
    echo -e "${RED}╚════════════════════════════════════╝${NC}"
}

trap stop EXIT INT TERM

start
