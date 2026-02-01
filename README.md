# 🌐 FDIRV

A tool for tunneling all system traffic and connecting to a remote server via SSH.

---

## 📑 Table of Contents

- [Introduction](#-introduction)
- [Advantages](#-advantages)
- [Connection Modes](#-connection-modes)
- [Excluding Sites](#-excluding-sites)
- [Supported Operating Systems](#-supported-operating-systems)
- [Installing Dependencies](#-installing-dependencies)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Setting up Alias](#️-setting-up-alias)
- [Tools Used](#-tools-used)
- [License](#-license)

---

## 🎯 Introduction

This tool is designed for **tunneling all system traffic** and connecting to a destination server.

All system requests are routed through the final server (which you connect to via SSH), and your IP on the internet will be the server's IP.

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  Your System │ ──SSH──▶│ Remote Server│ ───────▶│   Internet   │
│  (IP Hidden) │         │ (Your New IP)│         │              │
└──────────────┘         └──────────────┘         └──────────────┘
```

## ✅ Advantages

Why is system-wide tunneling better than setting proxies on individual applications?

| Regular Proxy Problem | System Tunnel Advantage |
|----------------------|-------------------------|
| Some apps don't use the proxy | **All** system traffic goes through the tunnel |
| Risk of real IP leakage | Real IP never leaks |
| Proxy is detectable | Traffic appears completely normal |
| Each app needs separate configuration | Configure once, affects all apps |

## 🔌 Connection Modes

Three different modes implemented for connecting to the server:

### 1️⃣ Default Mode (Xray)

```bash
vpn
```

SSH traffic is routed through Xray config.

**Advantages:**
- Your IP is hidden from the network you're connected to
- If the destination server IP is blocked, you can connect through this method

### 2️⃣ Direct Mode (Raw)

```bash
vpn --raw
```

Direct SSH connection without any intermediary.

### 3️⃣ Proxy Mode (Proxy)

```bash
vpn --proxy
vpn --proxy 192.168.1.100:10808
```

SSH traffic is routed through a SOCKS5 proxy. This proxy can be either on the local network or external.

**Example 1 - Proxy on Phone:**
Suppose your phone is connected to an Xray config and you want your system to use the same config:

1. Share the config on your local network in the Xray app
2. Find your phone's local IP (e.g., `192.168.1.100`)
3. Check the inbound port in settings (e.g., `10808`)
4. Run:
   ```bash
   vpn --proxy 192.168.1.100:10808
   ```

**Example 2 - External Proxy:**
```bash
vpn --proxy 1.2.3.4:1080
```

## 🔓 Excluding Sites

When connected to the destination server with all traffic tunneled, you might want to access some sites with your real IP (like local sites).

To do this, add them to the following files:

**`domains.txt`** - Domains to access directly:
```
example1.com
example2.com
```

**`ips.txt`** - IPs to access directly:
```
1.2.3.4
5.6.7.0/24
```

These sites and IPs will **not** go through the tunnel and will be accessed directly.

## 💻 Supported Operating Systems

This tool has only been tested on the following operating systems and no support is provided for other versions:

| OS | Version | Status |
|----|---------|--------|
| Ubuntu | 22.04 LTS | ✅ Tested |
| Ubuntu | 24.10 | ✅ Tested |

## 📦 Installing Dependencies

```bash
./install-dependencies.sh
```

This script installs the following packages:

| Package | Description |
|---------|-------------|
| `net-tools` | Network tools |
| `jq` | JSON processor |
| `sshpass` | SSH with password authentication |
| `autossh` | Persistent SSH connection |
| `proxychains4` | Run programs through proxy |

Other tools are included in the project.

## 🔧 Configuration

Edit the `config.sh` file:

```bash
# SSH Server Information
SERVER_ADDRESS="1.2.3.4"
SSH_PORT=22
SSH_USERNAME="user"
SSH_PASSWORD="pass"
UDPGW_PORT=8301
SOCKS_ADDRESS="127.0.0.1:1090"

# DNS
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_PRIMARY_V6="2606:4700:4700::1111"
DNS_SECONDARY_V6="2606:4700:4700::1001"

# Default Proxy
PROXYCHAINS_PROXY="127.0.0.1:10808"

# Paths
XRAY_PATH="$SCRIPT_DIR/xray"
XRAY_BASE_CONFIG_PATH="$XRAY_PATH/config.base.json"
XRAY_OUTBOUNDS_PATH="$XRAY_PATH/outbounds.json"
XRAY_CONFIG_PATH="$XRAY_PATH/config.json"

DOMAINS_PATH="$SCRIPT_DIR/domains.txt"
IPS_PATH="$SCRIPT_DIR/ips.txt"
```

### Variable Descriptions

| Variable | Description |
|----------|-------------|
| `SERVER_ADDRESS` | SSH server IP or domain |
| `SSH_PORT` | SSH port (usually 22) |
| `SSH_USERNAME` | SSH username |
| `SSH_PASSWORD` | SSH password |
| `UDPGW_PORT` | UDP Gateway port for UDP support |
| `SOCKS_ADDRESS` | SOCKS5 address that SSH listens on |
| `DNS_PRIMARY` | Primary DNS IPv4 |
| `DNS_SECONDARY` | Secondary DNS IPv4 |
| `DNS_PRIMARY_V6` | Primary DNS IPv6 |
| `DNS_SECONDARY_V6` | Secondary DNS IPv6 |
| `PROXYCHAINS_PROXY` | Default SOCKS5 proxy address for proxychains |
| `XRAY_PATH` | Xray folder path |
| `DOMAINS_PATH` | Domains list file path |
| `IPS_PATH` | IPs list file path |

> **Note:** You can use `$SCRIPT_DIR` variable instead of absolute paths. This variable is automatically set by the main script and points to the project folder.

## 🚀 Usage

```bash
# Default mode - SSH through Xray
sudo ./socks2vpn.sh

# Direct mode - SSH without intermediary
sudo ./socks2vpn.sh --raw

# Proxy mode - SSH through SOCKS5 proxy
sudo ./socks2vpn.sh --proxy

# Proxy mode with custom address
sudo ./socks2vpn.sh --proxy 192.168.1.100:10808
```

## ⌨️ Setting up Alias

For easier access, you can define an alias:

```bash
# Add to ~/.bashrc or ~/.zshrc:
alias vpn="sudo /path/to/socks2vpn.sh"
```

To run without entering sudo password:

```bash
sudo visudo
# Add this line (replace 'user' with your username):
user ALL=(ALL) NOPASSWD: /path/to/socks2vpn.sh
```

Now you can use these commands:

```bash
vpn              # Default mode
vpn --raw        # Direct mode
vpn --proxy      # Proxy mode
```

## 🔗 Tools Used

The following tools are included in the project. For updates and more information:

- [tun2socks](https://github.com/xjasonlyu/tun2socks) - Convert TUN traffic to SOCKS5
- [badvpn-tun2socks](https://github.com/ambrop72/badvpn) - Convert TUN traffic to SOCKS5 (with UDP support)
- [dns-tcp-socks-proxy](https://github.com/jtripper/dns-tcp-socks-proxy) - DNS proxy through SOCKS
- [proxychains](https://github.com/haad/proxychains) - Run programs through proxy
- [Xray-core](https://github.com/XTLS/Xray-core) - Advanced protocols for bypassing filters

## 📋 License

MIT © 2026 [Erfan Bahramali](https://github.com/ErfanBahramali)

---