# ⚡ NetWatch Pi

> A self-contained network monitoring dashboard for Raspberry Pi 5. Plug in a USB WiFi adapter, run one script, and get a live web dashboard showing every device and DNS query on your network.

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%205-red?style=flat-square)
![OS](https://img.shields.io/badge/OS-Raspberry%20Pi%20OS-green?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## 🧠 How It Works

```
Your Phone/Laptop
      │
      │  connects to hotspot
      ▼
┌─────────────────────┐
│   Raspberry Pi 5    │
│                     │
│  wlan1 (USB) = AP   │◄── you connect here to access dashboard
│  wlan0 (built-in)   │──► connects to your target network
│                     │
│  Flask Dashboard    │
│  dnsmasq (DNS log)  │
│  arp-scan (devices) │
└─────────────────────┘
      │
      │  monitors
      ▼
 Target WiFi Network
```

The Pi hosts its own hotspot on the USB WiFi adapter. You connect your phone or laptop to that hotspot, then open the dashboard in a browser. From the dashboard you connect the Pi to any target network — the Pi bridges the two and starts logging DNS queries and devices in real time.

---

## ✨ Features

- **One-script install** — fully interactive, asks for everything it needs
- **Live device list** — IP address, MAC address, hostname of every device on the network
- **Live DNS log** — see every domain being looked up in real time via WebSocket
- **Connect to networks via dashboard** — no SSH needed after setup
- **Auto-starts on boot** — all services managed by systemd
- **Dark web UI** — works great on mobile

---

## 🛒 Requirements

| Item | Notes |
|---|---|
| Raspberry Pi 5 | Other Pi models may work but untested |
| Raspberry Pi OS (fresh install) | Bookworm or later recommended |
| USB WiFi adapter | Must support AP mode — e.g. TP-Link TL-WN722N |
| MicroSD card | 8GB+ |

---

## 🚀 Installation

**1. Flash a fresh Raspberry Pi OS** using Raspberry Pi Imager. Enable SSH in the imager settings.

**2. Copy the install script to your Pi:**
```bash
scp install.sh pi@pi.local:~/install.sh
```

**3. SSH into your Pi:**
```bash
ssh pi@pi.local
```

**4. Run the installer:**
```bash
chmod +x install.sh && sudo bash install.sh
```

**5. Answer the prompts:**

| Prompt | Example |
|---|---|
| Hotspot interface (USB adapter) | `1` |
| Target network interface (built-in) | `0` |
| Hotspot SSID | `NetWatch-Admin` |
| Hotspot password | `yourpassword` |
| WiFi channel | `6` |
| Hotspot IP | `192.168.99.1` |
| Dashboard port | `8080` |
| Pre-configure target network? | `y` / `n` |

The installer will set everything up and start all services automatically.

---

## 📱 Using the Dashboard

1. On your phone or laptop, connect to the hotspot SSID you configured (e.g. `NetWatch-Admin`)
2. Open your browser and go to `http://192.168.99.1:8080`
3. Use the **Connect to Target Network** form to connect the Pi to a WiFi network
4. Watch devices and DNS queries populate in real time

---

## 🗂 What Gets Installed

| Component | Purpose |
|---|---|
| `hostapd` | Runs the admin hotspot on the USB adapter |
| `dnsmasq` | DHCP server + DNS query logger |
| `arp-scan` | Discovers devices on the network |
| `iptables` | NAT — routes traffic from hotspot through to target network |
| `Flask + SocketIO` | Web dashboard with live updates |

All services are registered with systemd and start automatically on every boot.

---

## 🔧 Useful Commands

```bash
# Check service status
systemctl status netwatch hostapd dnsmasq

# Watch dashboard logs live
journalctl -u netwatch -f

# Watch DNS queries live
tail -f /opt/netwatch/logs/dns_queries.log

# Restart everything
systemctl restart netwatch hostapd dnsmasq
```

---

## ⚠️ Legal Notice

This tool is intended for use on networks you own or have **explicit permission** to monitor. Unauthorized interception of network traffic is illegal in most countries. The author assumes no responsibility for misuse.

---

## 📁 File Structure

```
/opt/netwatch/
├── app.py              # Flask backend
├── config.json         # Generated config (interfaces, IPs, ports)
├── venv/               # Python virtual environment
├── templates/
│   └── index.html      # Dashboard UI
└── logs/
    └── dns_queries.log # dnsmasq DNS log
```
