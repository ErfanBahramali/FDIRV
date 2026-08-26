# SSH Configuration
SERVER_ADDRESS=""
SSH_PORT=
SSH_USERNAME=""
SSH_PASSWORD=""
SOCKS_ADDRESS="127.0.0.1:1090"

# ProxyChains proxy
PROXYCHAINS_PROXY="127.0.0.1:10808"

# Paths
# Uses $SCRIPT_DIR from parent script (set before sourcing this file)
# You can also use absolute paths like: XRAY_PATH="/home/user/FDIRV/xray"

# Xray
XRAY_PATH="$SCRIPT_DIR/xray"

# Xray SOCKS (for mode 1)
XRAY_SOCKS_BASE_CONFIG_PATH="$XRAY_PATH/config.socks.base.json"
XRAY_SOCKS_OUTBOUNDS_PATH="$XRAY_PATH/config.socks.outbounds.json"
XRAY_SOCKS_CONFIG_PATH="$XRAY_PATH/config.socks.json"

# Xray TUN (for all modes)
XRAY_TUN_BASE_CONFIG_PATH="$XRAY_PATH/config.tun.base.json"
XRAY_TUN_CONFIG_PATH="$XRAY_PATH/config.tun.json"
