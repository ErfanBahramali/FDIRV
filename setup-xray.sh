#!/usr/bin/env bash
#
# setup-xray.sh
# Prepares the system for Xray TUN mode:
#   1. Detects the active physical interface (never the TUN) and binds it into config.json
#      - outbounds with dialerProxy or protocol "dns" are left unbound
#   2. Clears access.log / error.log on every run
#   3. Sets up TUN routes (idempotent — safe to re-run)
#   4. Sends all DNS traffic (port 53) into the TUN so Xray resolves it via the proxy
#
# Designed to be run by systemd (xray.service) before/alongside xray,
# and re-run automatically whenever the network changes (NetworkManager dispatcher).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XRAY_DIR="$SCRIPT_DIR/xray"
CONFIG="$XRAY_DIR/config.json"
TUN_NAME="xray0"
TUN_ADDR="10.10.10.10"
DNS_TABLE=100

log() { echo "[setup-xray] $*"; }

# ---------------------------------------------------------------
# 1. Detect active physical interface (default route, excluding TUN/VPNs)
# ---------------------------------------------------------------
detect_interface() {
    local iface
    iface=$(ip -4 route show default \
        | awk -v tun="$TUN_NAME" '{
            d = ""
            for (i = 1; i <= NF; i++) if ($i == "dev") { d = $(i+1); break }
            if (d != "" && d != tun && d !~ /^(tun|wg)/) { print d; exit }
          }' || true)
    if [[ -z "$iface" ]]; then
        # Fallback: first non-loopback, non-tun interface that is UP
        iface=$(ip -o link show up \
            | awk -F': ' -v tun="$TUN_NAME" '{ sub(/@.*/, "", $2) }
                $2 != "lo" && $2 != tun && $2 !~ /^(tun|wg)/ { print $2; exit }' || true)
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
# 2. Bind detected interface into config.json
#    - outbounds with sockopt and no dialerProxy  -> interface = $IFACE
#    - outbounds with dialerProxy or protocol dns -> interface removed
# ---------------------------------------------------------------
update_config() {
    command -v jq >/dev/null || { log "ERROR: jq not installed"; exit 1; }
    local tmp="$CONFIG.tmp"

    jq --arg iface "$IFACE" '
      .outbounds |= map(
        if (.streamSettings.sockopt? // null) == null then .
        elif ((.streamSettings.sockopt.dialerProxy // "") != "") or (.protocol == "dns")
          then del(.streamSettings.sockopt.interface)
        else .streamSettings.sockopt.interface = $iface
        end
      )' "$CONFIG" > "$tmp"

    if cmp -s "$tmp" "$CONFIG"; then
        rm -f "$tmp"
        log "Config already bound to $IFACE"
    else
        mv "$tmp" "$CONFIG"
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
# 4. Send all DNS traffic (port 53) into the TUN
#    If xray0 disappears, DNS falls back to normal automatically.
# ---------------------------------------------------------------
setup_dns() {
    ip route replace default dev "$TUN_NAME" table "$DNS_TABLE"
    ip rule show | grep -q "ipproto udp dport 53 lookup $DNS_TABLE" || ip rule add pref 100 ipproto udp dport 53 lookup "$DNS_TABLE"
    ip rule show | grep -q "ipproto tcp dport 53 lookup $DNS_TABLE" || ip rule add pref 101 ipproto tcp dport 53 lookup "$DNS_TABLE"
    log "DNS traffic -> $TUN_NAME"
}

# ---------------------------------------------------------------
# 5. Ensure TUN device routes are set (idempotent)
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

    setup_dns
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
