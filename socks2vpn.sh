#!/bin/bash

# https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/dns-over-https-client/

if ! command -v route &> /dev/null; then
    echo "net-tools is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y net-tools
    echo "net-tools installed successfully!"
fi

if ! command -v sshpass &> /dev/null; then
    echo "sshpass is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y sshpass
    echo "sshpass installed successfully!"
fi

if ! command -v autossh &> /dev/null; then
    echo "autossh is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y autossh
    echo "autossh installed successfully!"
fi

if ! command -v proxychains &> /dev/null; then
    echo "proxychains is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y proxychains
    echo "proxychains installed successfully!"
fi

# For add exception:
# sudo ip route add 172.217.18.14 via 192.168.0.254 dev enp5s0

# set proxy in:
# /etc/proxychains.conf (127.0.0.1:2080)
IP=$(nslookup example.com | grep 'Address: ' | awk '{print $2}')
#IP=$(proxychains curl 'https://api.ipify.org' | sed -n '2,$p')
PROXY_ADDRESS=$IP
#PROXY_ADDRESS=''

echo "Ip: $IP"

DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_PRIMARY_V6="2606:4700:4700::1111"
DNS_SECONDARY_V6="2606:4700:4700::1001"

# SSH
SERVER_ADDRESS=""
SSH_PORT=
SSH_USERNAME=""
SSH_PASSWORD=""
UDPGW_PORT=

GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
INTERFACE=$(ip addr show | awk '/inet.*brd/{print $NF; exit}')
TUN_NAME="tun0"
TUN_ADDRESS="10.10.10.10"
SOCKS_ADDRESS="0.0.0.0:1090"

# RESOLV_CONF_PATH="/etc/resolv.conf"

# if ! grep -q "nameserver 127.0.0.1" $RESOLV_CONF_PATH; then
#     sed -i "s/nameserver/# nameserver/g" $RESOLV_CONF_PATH
#     sed -i "s/options/# options/g" $RESOLV_CONF_PATH
#     sed -i "s/search/# search/g" $RESOLV_CONF_PATH
#     # echo -e "\nnameserver 127.0.0.1" >> $RESOLV_CONF_PATH
#     echo -e "\nnameserver 1.1.1.1" >> $RESOLV_CONF_PATH
# fi

proxychains sshpass -p "$SSH_PASSWORD" ssh $SSH_USERNAME@$SERVER_ADDRESS -p $SSH_PORT -ND $SOCKS_ADDRESS & SSH_PID=$!

sleep 2

PROXY_ROUTE="$PROXY_ADDRESS via $GATEWAY"
SERVER_ROUTE="$SERVER_ADDRESS via $GATEWAY"
TUN_ROUTE="default via $TUN_ADDRESS dev $TUN_NAME metric 1"

setupTunDevice() {
    TUN_DEVICE=$(ip address | grep "$TUN_NAME")
    if [ -z "$TUN_DEVICE" ]
    then
        ip tuntap add mode tun dev "$TUN_NAME"
        ip address add "$TUN_ADDRESS/24" dev "$TUN_NAME"
        ip link set dev "$TUN_NAME" up
    fi
}

addRoute() {
    FIND=$(ip route | grep "$1")
    if [ -z "$FIND" ]
    then
        ip route add $1
    fi
}

delRoute() {
    FIND=$(ip route | grep "$1")
    if [ -n "$FIND" ]
    then
        ip route del $1
    fi
}

start() {
    setupTunDevice
    addRoute "$PROXY_ROUTE"
    addRoute "$SERVER_ROUTE"
    addRoute "$TUN_ROUTE"

    # echo "Handle DNS"
    resolvectl domain $TUN_NAME "~."
    resolvectl default-route $TUN_NAME true
    resolvectl dns $TUN_NAME $DNS_PRIMARY $DNS_SECONDARY $DNS_PRIMARY_V6 $DNS_SECONDARY_V6
    resolvectl default-route $INTERFACE false

    # tun2socks -device "tun://$TUN_NAME" -proxy "socks5://$SOCKS_ADDRESS" -interface "$INTERFACE" -mtu 1500 -tcp-sndbuf 2048k -tcp-rcvbuf 2048k -tcp-auto-tuning
    # ./badvpn-tun2socks --tundev $TUN_NAME --netif-ipaddr $TUN_ADDRESS --netif-netmask 255.255.255.0 --socks-server-addr $SOCKS_ADDRESS
    ./badvpn-tun2socks --tundev $TUN_NAME --netif-ipaddr $TUN_ADDRESS --netif-netmask 255.255.255.0 --socks-server-addr $SOCKS_ADDRESS --udpgw-remote-server-addr 127.0.0.1:$UDPGW_PORT
}

stop() {
    kill -9 "$SSH_PID"
    delRoute "$PROXY_ROUTE"
    delRoute "$TUN_ROUTE"
    delRoute "$SERVER_ROUTE"

    echo "Restore DNS"
    resolvectl default-route $INTERFACE true

    # # sed -i "s/nameserver 127.0.0.1//g" $RESOLV_CONF_PATH
    # sed -i "s/nameserver 1.1.1.1//g" $RESOLV_CONF_PATH
    # sed -i '/^$/d' $RESOLV_CONF_PATH
    # sed -i "s/# nameserver/\nnameserver/g" $RESOLV_CONF_PATH
    # sed -i "s/# options/options/g" $RESOLV_CONF_PATH
    # sed -i "s/# search/search/g" $RESOLV_CONF_PATH
}

if [ "$EUID" -ne 0 ]
then
    echo "Please run as root"
    exit
fi

trap stop EXIT
start


