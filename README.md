# 🌐 FDIRV

System-wide VPN tunneling using **Xray's native TUN protocol** — nothing else. Xray creates a TUN device (`xray0`), all system traffic is routed through it, and your public IP becomes the server's IP.

```
┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│  Your System │───▶│ xray0 (TUN) │───▶│  Xray Server │───▶ Internet
│ (IP Hidden)  │    │ 10.10.10.10 │    │ (Your New IP)│
└──────────────┘    └─────────────┘    └──────────────┘
```

## ✨ Features

- ✅ **Pure Xray** — no tun2socks, no SSH, no external tools
- ✅ Native TUN inbound — all system traffic is tunneled
- ✅ **No DNS leaks** — every DNS query (port 53) is captured into `xray0` and resolved over DoH through the proxy
- ✅ Works without touching `/etc/resolv.conf` — no systemd-resolved, no extra packages
- ✅ Bypasses router/ISP DNS filtering (e.g. forced SafeSearch)
- ✅ Smart routing: Iranian sites/IPs go direct (`geoip:ir`, `geosite:category-ir`)
- ✅ Auto interface detection — binds to the active physical interface, never the TUN itself
- ✅ Systemd service with auto-restart and persistent routes
- ✅ Logs cleared on every start

## ⚠️ Requirements

- Linux with systemd
- Kernel 4.17+ and `iproute2` (for port-based `ip rule`, already present on modern distros)
- Xray v1.26.1+ (TUN support)
- `jq` (for interface binding in config)

## 🔧 Configuration

Everything lives in a single file: `xray/config.json`

### 1. Server IP in `dns.hosts` (required)

Because all system DNS goes through Xray, Xray cannot resolve its own server's domain through itself — that would loop and drop the connection. Pin the server's IP:

```json
"dns": {
  "hosts": {
    "your-server-domain.net": ["SERVER_IP"]
  }
}
```

Keep the domain in `serverName` so TLS still works.

### 2. DNS routing (order matters)

```json
"rules": [
  { "type": "field", "inboundTag": ["dns-module"], "outboundTag": "proxy" },
  { "type": "field", "network": "udp,tcp", "port": 53, "outboundTag": "dns-proxy" },
  { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
  ...
]
```

- The `dns-module` rule must come **first**, so Xray's own DNS queries never loop back into `dns-proxy`.
- The port 53 rule must come **before** `geoip:private`, otherwise queries to your router (e.g. `192.168.x.1`) go direct and leak.

### 3. `sockopt.interface` (managed automatically)

You normally never edit this — the setup script keeps it in sync with your active network interface:

```json
"sockopt": {
  "interface": "enp5s0"
}
```

- `proxy` and `direct` get the interface.
- Outbounds with `dialerProxy` (like `dns-proxy`) or `protocol: dns` are left unbound — the script removes any `interface` from them.

## 🚀 Installation

```bash
# 1. Make the setup script executable
chmod +x setup-xray.sh

# 2. Install the service
sudo cp xray.service /etc/systemd/system/
sudo systemctl daemon-reload

# 3. Enable & start (runs on every boot)
sudo systemctl enable --now xray.service
```

### What the service does on every start

1. Detects the active physical interface from the default route (skipping `xray0`, `tun*`, `wg*`) and writes it into `config.json`
2. Clears `access.log` and `error.log`
3. Sets up TUN routes:
   ```bash
   ip addr add 10.10.10.10/24 dev xray0
   ip link set dev xray0 up
   ip route add default via 10.10.10.10 dev xray0 metric 1
   ```
4. Sends all DNS traffic into the TUN with policy routing:
   ```bash
   ip route replace default dev xray0 table 100
   ip rule add pref 100 ipproto udp dport 53 lookup 100
   ip rule add pref 101 ipproto tcp dport 53 lookup 100
   ```
   Your system still thinks it talks to the router's DNS, but the query is intercepted and answered by Xray. If `xray0` disappears, table 100 becomes empty and DNS falls back to normal automatically.
5. Starts Xray, then re-applies routes once the TUN device is up
6. If Xray crashes, systemd restarts everything after 5 seconds

### Keeping routes alive across network changes

To re-run setup whenever the network changes (Wi-Fi ↔ Ethernet, reconnects), add a NetworkManager dispatcher hook:

```bash
sudo tee /etc/NetworkManager/dispatcher.d/fdirv <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == "up" || "$2" == "dhcp4-change" ]]; then
    /path/to/FDIRV/setup-xray.sh
fi
EOF
sudo chmod +x /etc/NetworkManager/dispatcher.d/fdirv
```

The script is idempotent — running it multiple times is safe.

## 🔍 Verifying DNS

```bash
nslookup google.com           # "Server" still shows your router — that's expected;
                              # the answer should be a normal Google IP (not 216.239.38.120)
dig +short whoami.akamai.net  # should be a Cloudflare/Google IP, not your ISP
tail -f xray/error.log        # look for: taking detour [dns-proxy] ... DOH//cloudflare-dns.com got answer
```

Strongest check (if `tcpdump` is installed) — nothing should appear while you run `nslookup`:

```bash
sudo tcpdump -ni <your-interface> port 53
```

## 🛠️ Troubleshooting

**Connection drops after setup** — usually the server IP is missing from `dns.hosts` (see Configuration). Restore the connection by removing the DNS rules:

```bash
sudo ip rule del pref 100
sudo ip rule del pref 101
sudo ip route flush table 100
```

## 📋 Managing the Service

```bash
sudo systemctl status xray     # status
sudo systemctl restart xray    # restart
sudo systemctl stop xray       # stop
journalctl -u xray -f          # live logs
tail -f xray/error.log         # xray error log
```

## 📁 Project Structure

```
FDIRV/
├── setup-xray.sh          # Interface detection, log cleanup, TUN + DNS routing
├── xray.service           # Systemd unit
└── xray/
    ├── config.json        # The single Xray config
    ├── xray               # Xray binary
    ├── geoip.dat          # IP geolocation database
    ├── geosite.dat        # Domain database
    └── *.log              # Logs (cleared on each start)
```

## 💻 Supported Operating Systems

| OS     | Version   | Status    |
| ------ | --------- | --------- |
| Debian | 13.6      | ✅ Tested |
| Ubuntu | 22.04 LTS | ✅ Tested |
| Ubuntu | 24.10     | ✅ Tested |

## 🔗 Tools Used

- [Xray-core](https://github.com/XTLS/Xray-core) — native TUN, DNS and routing

## 📋 License

MIT © 2026 [Erfan Bahramali](https://github.com/ErfanBahramali)
