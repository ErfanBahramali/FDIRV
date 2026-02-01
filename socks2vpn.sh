#!/bin/bash

# Add executable permission to the script:
# chmod +x /home/user/Desktop/FDIRV/socks2vpn.sh

# Add alias in:
# ~/.bashrc or ~/.zshrc
# # FDIRV
# alias vpn="sudo /home/user/Desktop/FDIRV/socks2vpn.sh"

# Password-free and safe this file in:
# /etc/sudoers
# sudo visudo
# #FDIRV
# user ALL=(ALL) NOPASSWD: /home/user/Desktop/FDIRV/socks2vpn.sh

# Usage:
# sudo bash socks2vpn.sh
# Or with alias:
# vpn                 - with Xray, with proxychains
# vpn --raw           - without Xray, without proxychains (direct SSH)
# vpn --proxy         - without Xray, with proxychains (default proxy)
# vpn --proxy IP:PORT - without Xray, with proxychains (custom proxy)

# script dir for open script in other directory
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Load credentials
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found!"
    exit 1
fi

# Mode detection
RAW_MODE=false
PROXY_MODE=false

if [ "$1" == "--raw" ]; then
    RAW_MODE=true
elif [ "$1" == "--proxy" ]; then
    PROXY_MODE=true
    if [ -n "$2" ]; then
        PROXYCHAINS_PROXY="$2"
    fi
fi

PROXYCHAINS_PROXY_HOST=$(echo "$PROXYCHAINS_PROXY" | cut -d':' -f1)
PROXYCHAINS_PROXY_PORT=$(echo "$PROXYCHAINS_PROXY" | cut -d':' -f2)

# Resolve domains and IPs (common for all modes)
# Unique domains
DOMAINS=$(grep -v '^#' "$DOMAINS_PATH" | grep -v '^$' | sort -u)

# Resolve domains in parallel
DOMAINS_IPS=$(echo "$DOMAINS" | xargs -n1 -P25 dig +short +time=6 +tries=1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

# Unique IPs
IPS=$(grep -v '^#' "$IPS_PATH" | grep -v '^$' | sort -u)

PROXY_ADDRESSES="$DOMAINS_IPS $IPS"

# Build PROXY_ADDRESSES based on mode
if [ "$RAW_MODE" == true ]; then
    # RAW mode: route SERVER_ADDRESS + domains + IPs
    PROXY_ADDRESSES="$SERVER_ADDRESS $PROXY_ADDRESSES"
elif [ "$PROXY_MODE" == true ]; then
    # PROXY mode: add proxy IP + domains + IPs
    PROXY_IP=$PROXYCHAINS_PROXY_HOST

    # Resolve proxy IP if it's a domain
    if [[ ! $PROXY_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PROXY_IP=$(dig +short $PROXY_IP | xargs)
    fi

    PROXY_ADDRESSES="$PROXY_IP $PROXY_ADDRESSES"
else
    # Normal mode (Xray): add Xray address + domains + IPs
    jq --slurpfile outs $XRAY_OUTBOUNDS_PATH '.outbounds = $outs[0]' $XRAY_BASE_CONFIG_PATH > $XRAY_CONFIG_PATH

    XRAY_ADDRESS=$(jq '.[0].settings.[].[0].address' $XRAY_OUTBOUNDS_PATH | cut -d "\"" -f 2)

    if [[ $XRAY_ADDRESS != null && ! $XRAY_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # is domain, resolve it
        XRAY_ADDRESS=$(dig +short $XRAY_ADDRESS | xargs)
    fi

    PROXY_ADDRESSES="$XRAY_ADDRESS $PROXY_ADDRESSES"
fi

# Unique all addresses
PROXY_ADDRESSES=$(echo "$PROXY_ADDRESSES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

# Network
GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
INTERFACE=$(ip addr show | awk '/inet.*brd/{print $NF; exit}')

# Tun
TUN_NAME="tun0"
TUN_ADDRESS="10.10.10.10"

# Route
TUN_ROUTE="default via $TUN_ADDRESS dev $TUN_NAME metric 1"

# ProxyChains config (for normal mode and proxy mode)
if [ "$RAW_MODE" == false ]; then
    # Create temporary proxychains config
    PROXYCHAINS_CONFIG="$SCRIPT_DIR/proxychains.conf"

    echo -e "strict_chain
quiet_mode
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 $PROXYCHAINS_PROXY_HOST $PROXYCHAINS_PROXY_PORT" > "$PROXYCHAINS_CONFIG"
fi

executeXray() {

    $XRAY_PATH/xray run -c $XRAY_CONFIG_PATH >/dev/null &
    XRAY_PID=$!

    echo "Xray Executed ..."

    sleep 2
}

executeSSH() {

    if [ "$RAW_MODE" == false ]; then
        {
            proxychains -f "$PROXYCHAINS_CONFIG" sshpass -p "$SSH_PASSWORD" ssh $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS
        } &>/dev/null &
    else
        {
            sshpass -p "$SSH_PASSWORD" ssh $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS
        } &>/dev/null &
    fi
    SSH_PID=$!

    echo "SSH Executed ..."

    sleep 2

}

executeDNS() {

    # resolvectl domain $TUN_NAME "~."
    # resolvectl default-route $TUN_NAME true
    # resolvectl dns $TUN_NAME $DNS_PRIMARY $DNS_SECONDARY $DNS_PRIMARY_V6 $DNS_SECONDARY_V6
    # resolvectl default-route $INTERFACE false

    CURRENT_DNS=$(cat /etc/resolv.conf)

    truncate --size 0 $SCRIPT_DIR/dns-tcp-socks-proxy/proxy.log

    $SCRIPT_DIR/dns-tcp-socks-proxy/dns_proxy $SCRIPT_DIR/dns-tcp-socks-proxy/dns_proxy.conf &>/dev/null &

    echo "DNS Executed ..."

}

stopSSH() {

    if ps -p $SSH_PID >/dev/null; then

        kill -9 $SSH_PID

    fi

    echo "SSH Killed."

}

stopXray() {

    if ps -p $XRAY_PID >/dev/null; then

        kill -9 $XRAY_PID

    fi

    echo "Xray Killed."
}

stopDNS() {

    # resolvectl default-route $INTERFACE true

    DNS_PID=$(pgrep -x dns_proxy | xargs)

    kill -9 $DNS_PID

    echo "DNS Killed."

    echo "$CURRENT_DNS" >/etc/resolv.conf

    echo "DNS Restored."

}

addTuntap() {

    TUN_DEVICE=$(ip address | grep "$TUN_NAME")

    if [ -z "$TUN_DEVICE" ]; then

        ip tuntap add mode tun dev "$TUN_NAME"

        ip address add "$TUN_ADDRESS/24" dev "$TUN_NAME"

        ip link set dev "$TUN_NAME" up

        echo "Tuntap Added."

    fi
}

deleteTuntap() {

    TUN_DEVICE=$(ip address | grep "$TUN_NAME")

    if [ "$TUN_DEVICE" ]; then

        ip tuntap del mode tun dev $TUN_NAME

        echo "Tuntap Deleted."

    fi
}

start() {

    echo "Starting ..."

    if [ "$RAW_MODE" == true ]; then
        echo "RAW mode (without Xray, direct SSH)..."
    elif [ "$PROXY_MODE" == true ]; then
        echo "PROXY mode (without Xray, with proxychains: $PROXYCHAINS_PROXY_HOST:$PROXYCHAINS_PROXY_PORT)..."
    else
        echo "Xray mode (with Xray and proxychains)..."
        executeXray
    fi

    executeSSH

    executeDNS

    addTuntap

    for PROXY_ADDRESS in $PROXY_ADDRESSES; do

        ip route add $PROXY_ADDRESS via $GATEWAY

    done

    echo "PROXY_ROUTE Added."

    ip route add $TUN_ROUTE

    echo "TUN_ROUTE Added."

    # $SCRIPT_DIR/tun2socks -device "tun://$TUN_NAME" -proxy "socks5://$SOCKS_ADDRESS" -interface "$INTERFACE" -mtu 1500 -tcp-sndbuf 2048k -tcp-rcvbuf 2048k -tcp-auto-tuning

    $SCRIPT_DIR/badvpn-tun2socks --tundev $TUN_NAME --netif-ipaddr $TUN_ADDRESS --netif-netmask 255.255.255.0 --socks-server-addr $SOCKS_ADDRESS --udpgw-remote-server-addr 127.0.0.1:$UDPGW_PORT

    echo "Success."
}

stop() {

    echo "Stoping ..."

    ip route del $TUN_ROUTE

    echo "TUN_ROUTE Deleted."

    for PROXY_ADDRESS in $PROXY_ADDRESSES; do

        ip route del $PROXY_ADDRESS via $GATEWAY

    done

    echo "PROXY_ROUTE Deleted."

    deleteTuntap

    stopDNS

    stopSSH

    if [ "$RAW_MODE" == false ] && [ "$PROXY_MODE" == false ]; then
        stopXray
    fi

    # Clean up temporary proxychains config
    if [ "$RAW_MODE" == false ]; then
        rm -f "$PROXYCHAINS_CONFIG"
    fi

    echo "Success."

}

if [ "$EUID" -ne 0 ]; then

    echo "Please run as root"

    exit
fi

trap stop EXIT

start
