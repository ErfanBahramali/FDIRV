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
- ✅ Built-in DNS with DoH (no DNS leaks)
- ✅ Smart routing: Iranian sites/IPs go direct (`geoip:ir`, `geosite:category-ir`)
- ✅ Auto interface detection — binds to the active network interface automatically
- ✅ Systemd service with auto-restart and persistent routes
- ✅ Logs cleared on every start

## ⚠️ Requirements

- Linux with systemd
- Xray v1.26.1+ (TUN support)
- `jq` (for interface binding in config)

## 🔧 Configuration

Everything lives in a single file: `xray/config.json`

The only thing you normally never edit manually is the outbound `sockopt.interface` — the setup script keeps it in sync with your active network interface:

```json
"sockopt": {
  "interface": "enp5s0"
}
```

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

1. Detects the active network interface (default route) and writes it into `config.json` (`sockopt.interface`)
2. Clears `access.log` and `error.log`
3. Sets up TUN routes:
   ```bash
   ip addr add 10.10.10.10/24 dev xray0
   ip link set dev xray0 up
   ip route add default via 10.10.10.10 dev xray0 metric 1
   ```
4. Starts Xray, then re-applies routes once the TUN device is up
5. If Xray crashes, systemd restarts everything after 5 seconds

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
├── setup-xray.sh          # Interface detection, log cleanup, route setup
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
