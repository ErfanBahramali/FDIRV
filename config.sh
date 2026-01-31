# SSH Configuration
SERVER_ADDRESS=""
SSH_PORT=
SSH_USERNAME=""
SSH_PASSWORD=""
UDPGW_PORT=
SOCKS_ADDRESS="127.0.0.1:1090"

# DNS
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_PRIMARY_V6="2606:4700:4700::1111"
DNS_SECONDARY_V6="2606:4700:4700::1001"

# ProxyChains proxy
PROXYCHAINS_PROXY="127.0.0.1:10808"

# Paths
# Uses $SCRIPT_DIR from parent script (set before sourcing this file)
# You can also use absolute paths like: XRAY_PATH="/home/user/FDIRV/Xray"

# Xray
XRAY_PATH="$SCRIPT_DIR/Xray"
XRAY_BASE_CONFIG_PATH="$XRAY_PATH/config.base.json"
XRAY_OUTBOUNDS_PATH="$XRAY_PATH/outbounds.json"
XRAY_CONFIG_PATH="$XRAY_PATH/config.json"

# Domains and IPs lists
DOMAINS_PATH="$SCRIPT_DIR/domains.txt"
IPS_PATH="$SCRIPT_DIR/ips.txt"
