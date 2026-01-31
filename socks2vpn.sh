#!/bin/bash

# Add executable permission to the script:
# chmod +x ~/Desktop/FDIRV/socks2vpn.sh

# Add alias in:
# ~/.zshrc
# # FDIRV
# alias vpn="sudo ~/Desktop/FDIRV/socks2vpn.sh"

# Password-free and safe this file in:
# /etc/sudoers
# sudo visudo
# #FDIRV
# user ALL=(ALL) NOPASSWD: ~/Desktop/FDIRV/socks2vpn.sh

# script dir for open script in other directory
SCRIPT_DIR=$(dirname "$(realpath "$0")")

XRAY_PATH="$SCRIPT_DIR/Xray"
XRAY_BASE_CONFIG_PATH="$XRAY_PATH/config.base.json"
XRAY_OUTBOUNDS_PATH="$XRAY_PATH/outbounds.json"
XRAY_CONFIG_PATH="$XRAY_PATH/config.json"
DOMAINS_PATH="$SCRIPT_DIR/domains.txt"
IPS_PATH="$SCRIPT_DIR/ips.txt"

jq --slurpfile outs $XRAY_OUTBOUNDS_PATH '.outbounds = $outs[0]' $XRAY_BASE_CONFIG_PATH > $XRAY_CONFIG_PATH

PROXY_ADDRESSES=$(jq '.[0].settings.[].[0].address' $XRAY_OUTBOUNDS_PATH | cut -d "\"" -f 2)
# PROXY_ADDRESSES=''

if [[ $PROXY_ADDRESSES != null && ! $PROXY_ADDRESSES =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

    # is not ip
    # is domain
    PROXY_ADDRESSES=$(dig +short $PROXY_ADDRESSES | xargs)
fi

# Unique domains
DOMAINS=$(grep -v '^#' "$DOMAINS_PATH" | grep -v '^$' | sort -u)

# Resolve domains in parallel
DOMAINS_IPS=$(echo "$DOMAINS" | xargs -n1 -P25 dig +short +time=6 +tries=1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

# Unique IPs
IPS=$(grep -v '^#' "$IPS_PATH" | grep -v '^$' | sort -u)

# Add IPs to PROXY_ADDRESSES
PROXY_ADDRESSES="$PROXY_ADDRESSES $DOMAINS_IPS $IPS"

# Unique all addresses
PROXY_ADDRESSES=$(echo "$PROXY_ADDRESSES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

# SSH
SERVER_ADDRESS=""
SSH_PORT=
SSH_USERNAME=""
SSH_PASSWORD=""
UDPGW_PORT=
SOCKS_ADDRESS="127.0.0.1:1090"

DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_PRIMARY_V6="2606:4700:4700::1111"
DNS_SECONDARY_V6="2606:4700:4700::1001"

# Network
GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
INTERFACE=$(ip addr show | awk '/inet.*brd/{print $NF; exit}')

# Tun
TUN_NAME="tun0"
TUN_ADDRESS="10.10.10.10"

# Route
TUN_ROUTE="default via $TUN_ADDRESS dev $TUN_NAME metric 1"

# ProxyChains proxy
PROXYCHAINS_PROXY_HOST="127.0.0.1"
PROXYCHAINS_PROXY_PORT="10808"

# Create temporary proxychains config
PROXYCHAINS_CONFIG="$SCRIPT_DIR/proxychains.conf"

cat > "$PROXYCHAINS_CONF" << EOF
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 $PROXYCHAINS_PROXY_HOST $PROXYCHAINS_PROXY_PORT
EOF

executeXray() {

    $XRAY_PATH/xray run -c $XRAY_CONFIG_PATH >/dev/null &
    XRAY_PID=$!

    echo "Xray Executed ..."

    sleep 2
}

executeSSH() {

    {
        proxychains -f "$PROXYCHAINS_CONF" sshpass -p "$SSH_PASSWORD" ssh $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS
    } &>/dev/null &
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

    executeXray

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

    stopXray

    # Clean up temporary proxychains config
    rm -f "$PROXYCHAINS_CONFIG"

    echo "Success."

}

if [ "$EUID" -ne 0 ]; then

    echo "Please run as root"

    exit
fi

trap stop EXIT

start
