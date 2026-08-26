#!/usr/bin/env bash
#
# setup-xray.sh
# Prepares the system for Xray TUN mode:
#   1. Detects the active network interface and binds it into xray config.json
#   2. Clears access.log / error.log on every run
#   3. Sets up TUN routes (idempotent — safe to re-run)
#
# Designed to be run by systemd (xray.service) before/alongside xray,
# and re-run automatically whenever the network changes (NetworkManager dispatcher).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XRAY_DIR="$SCRIPT_DIR/xray"
CONFIG="$XRAY_DIR/config.json"
TUN_NAME="xray0"
TUN_ADDR="10.10.10.10"

log() { echo "[setup-xray] $*"; }

# ---------------------------------------------------------------
# 1. Detect active network interface (default route, excluding tun)
# ---------------------------------------------------------------
detect_interface() {
    local iface
    iface=$(ip -4 route show default | awk '{print $5; exit}')
    if [[ -z "$iface" ]]; then
        # Fallback: first non-loopback, non-tun interface that is UP
        iface=$(ip -o link show up | awk -F': ' '$2 !~ /^(lo|xray0|tun|wg)/ {print $2; exit}')
    fi
    echo "$iface"
}

IFACE=$(detect_interface)
if [[ -z "$IFACE" ]]; then
    log "ERROR: no active network interface found"
    exit 1
fi
log "Active interface: $IFACE"

# ---------------------------------------------------------------
# 2. Bind detected interface into config.json (all sockopt.interface)
# ---------------------------------------------------------------
update_config() {
    command -v jq >/dev/null || { log "ERROR: jq not installed"; exit 1; }
    local current
    current=$(jq -r '[.outbounds[].streamSettings.sockopt.interface // empty] | unique | join(",")' "$CONFIG")
    if [[ "$current" == *"$IFACE"* ]]; then
        log "Config already bound to $IFACE"
    else
        local tmp="$CONFIG.tmp"
        jq --arg iface "$IFACE" \
           '(.outbounds[] | select(.streamSettings.sockopt) | .streamSettings.sockopt.interface) = $iface' \
           "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
        log "Config updated: sockopt.interface -> $IFACE"
    fi
}
update_config

# ---------------------------------------------------------------
# 3. Clear logs
# ---------------------------------------------------------------
: > "$XRAY_DIR/access.log" 2>/dev/null || true
: > "$XRAY_DIR/error.log"  2>/dev/null || true
log "Logs cleared"

# ---------------------------------------------------------------
# 4. Ensure TUN device routes are set (idempotent)
# ---------------------------------------------------------------
setup_routes() {
    if ! ip link show "$TUN_NAME" &>/dev/null; then
        log "TUN device $TUN_NAME not up yet (xray will create it); routes will be applied on next run"
        return 1
    fi

    ip addr show "$TUN_NAME" | grep -q "$TUN_ADDR/" || {
        ip addr add "$TUN_ADDR/24" dev "$TUN_NAME"
        log "Added address $TUN_ADDR/24 to $TUN_NAME"
    }

    ip link set dev "$TUN_NAME" up

    if ! ip route show | grep -q "default via $TUN_ADDR dev $TUN_NAME"; then
        ip route add default via "$TUN_ADDR" dev "$TUN_NAME" metric 1
        log "Added default route via $TUN_ADDR dev $TUN_NAME metric 1"
    else
        log "Default route already present"
    fi
}

# Try once now; if xray hasn't created the TUN yet, retry briefly in background
if ! setup_routes; then
    (
        for i in $(seq 1 30); do
            sleep 1
            ip link show "$TUN_NAME" &>/dev/null && setup_routes && exit 0
        done
        log "WARNING: $TUN_NAME never appeared; routes not applied"
    ) &
fi

log "Setup complete"
