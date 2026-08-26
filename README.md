# 🌐 FDIRV

A tool for tunneling all system traffic and connecting to a remote server via SSH, using Xray's native TUN protocol.

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

This tool is designed for **tunneling all system traffic** and connecting to a destination server using **Xray's native TUN protocol**.

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

**Technical Features:**
- ✅ Xray native TUN protocol (no external tools needed)
- ✅ Built-in DNS with DoH (no DNS leaks)
- ✅ Smart routing with geoip/geosite (Iranian sites go direct)
- ✅ Better performance (native implementation)
- ✅ Clean architecture

**⚠️ Requirements:**
- Xray v1.26.1.23 or higher (TUN support added in this version)

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

When connected to the destination server with all traffic tunneled, you might want to access some sites with your real IP (like Iranian sites).

The tool automatically routes Iranian sites directly using:
- `geoip:ir` - Iranian IP ranges
- `geosite:category-ir` - Iranian domains
- `geoip:private` - Local network IPs
- `geosite:private` - Local domains

All other traffic goes through the tunnel.

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
SOCKS_ADDRESS="127.0.0.1:1090"

# Default Proxy
PROXYCHAINS_PROXY="127.0.0.1:10808"

# Paths
XRAY_PATH="$SCRIPT_DIR/xray"

# Xray SOCKS config (for default mode)
XRAY_SOCKS_BASE_CONFIG_PATH="$XRAY_PATH/config.socks.base.json"
XRAY_SOCKS_OUTBOUNDS_PATH="$XRAY_PATH/config.socks.outbounds.json"
XRAY_SOCKS_CONFIG_PATH="$XRAY_PATH/config.socks.json"

# Xray TUN config (for all modes)
XRAY_TUN_BASE_CONFIG_PATH="$XRAY_PATH/config.tun.base.json"
XRAY_TUN_CONFIG_PATH="$XRAY_PATH/config.tun.json"
```

### Variable Descriptions

| Variable | Description |
|----------|-------------|
| `SERVER_ADDRESS` | SSH server IP or domain |
| `SSH_PORT` | SSH port (usually 22) |
| `SSH_USERNAME` | SSH username |
| `SSH_PASSWORD` | SSH password |
| `SOCKS_ADDRESS` | SOCKS5 address that SSH listens on |
| `PROXYCHAINS_PROXY` | Default SOCKS5 proxy address for proxychains |
| `XRAY_PATH` | Xray folder path |
| `XRAY_SOCKS_BASE_CONFIG_PATH` | Template for SOCKS config (base) |
| `XRAY_SOCKS_OUTBOUNDS_PATH` | Outbounds file to merge with SOCKS base |
| `XRAY_SOCKS_CONFIG_PATH` | Generated SOCKS config (runtime) |
| `XRAY_TUN_BASE_CONFIG_PATH` | Template for TUN config (base) |
| `XRAY_TUN_CONFIG_PATH` | Generated TUN config (runtime) |

> **Note:** You can use `$SCRIPT_DIR` variable instead of absolute paths. This variable is automatically set by the main script and points to the project folder.

> **📝 Config File Architecture:**
> - **`.base.json` files** are templates that never change (e.g., `config.socks.base.json`, `config.tun.base.json`)
> - **Generated configs** are created at runtime by modifying templates (e.g., `config.socks.json`, `config.tun.json`)
> - This approach is cleaner and safer than backup/restore methods - each run starts from pristine templates
> - **SOCKS config**: base + outbounds merged via jq → final config
> - **TUN config**: base + interface binding + routing rules → final config

## 🚀 Usage

**First, make the script executable:**

```bash
chmod +x /path/to/xray2vpn.sh
```

**Then run:**

```bash
# Default mode - SSH through Xray
sudo ./xray2vpn.sh

# Direct mode - SSH without intermediary
sudo ./xray2vpn.sh --raw

# Proxy mode - SSH through SOCKS5 proxy
sudo ./xray2vpn.sh --proxy

# Proxy mode with custom address
sudo ./xray2vpn.sh --proxy 192.168.1.100:10808
```

## ⌨️ Setting up Alias

For easier access, you can define an alias:

```bash
# Add to ~/.bashrc or ~/.zshrc:
alias vpn="sudo /path/to/xray2vpn.sh"
```

To run without entering sudo password:

```bash
sudo visudo
# Add this line (replace 'user' with your username):
user ALL=(ALL) NOPASSWD: /path/to/xray2vpn.sh
```

Now you can use these commands:

```bash
vpn              # Default mode
vpn --raw        # Direct mode
vpn --proxy      # Proxy mode
```

## 🔗 Tools Used

This tool uses Xray's native TUN protocol for system-wide tunneling:

- [Xray-core](https://github.com/XTLS/Xray-core) - Advanced protocols with native TUN support
- [proxychains](https://github.com/haad/proxychains) - Route programs through proxy

**Built-in Features:**
- Xray TUN inbound (native virtual network interface)
- Xray DNS (DoH support with split DNS)
- Xray routing (geoip/geosite for smart routing)

## 📋 License

MIT © 2026 [Erfan Bahramali](https://github.com/ErfanBahramali)

---
