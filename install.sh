#!/bin/bash

# ============================================================
#   NetWatch Pi - Interactive Network Monitor Installer
#   For Raspberry Pi 5 | Personal/Authorized Use Only
# ============================================================

set -e

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ███╗   ██╗███████╗████████╗██╗    ██╗ █████╗ ████████╗ ██████╗██╗  ██╗"
  echo "  ████╗  ██║██╔════╝╚══██╔══╝██║    ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║"
  echo "  ██╔██╗ ██║█████╗     ██║   ██║ █╗ ██║███████║   ██║   ██║     ███████║"
  echo "  ██║╚██╗██║██╔══╝     ██║   ██║███╗██║██╔══██║   ██║   ██║     ██╔══██║"
  echo "  ██║ ╚████║███████╗   ██║   ╚███╔███╔╝██║  ██║   ██║   ╚██████╗██║  ██║"
  echo "  ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Raspberry Pi 5 Network Monitor | Personal Testing Tool${NC}"
  echo -e "  ${YELLOW}⚠  Only use on networks you own or have explicit permission to test${NC}"
  echo ""
}

step() { echo -e "\n${BLUE}${BOLD}▶  $1${NC}"; }
ok()   { echo -e "  ${GREEN}✔  $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠  $1${NC}"; }
err()  { echo -e "\n  ${RED}✘  ERROR: $1${NC}\n"; exit 1; }

ask() {
  local prompt="$1" default="$2" var
  if [[ -n "$default" ]]; then
    printf "  \033[0;36m%s\033[0m \033[2m[%s]\033[0m: " "$prompt" "$default" >/dev/tty
  else
    printf "  \033[0;36m%s\033[0m: " "$prompt" >/dev/tty
  fi
  read -r var </dev/tty
  printf '%s' "${var:-$default}"
}

ask_secret() {
  local prompt="$1" var
  printf "  \033[0;36m%s\033[0m: " "$prompt" >/dev/tty
  read -rs var </dev/tty
  printf '\n' >/dev/tty
  printf '%s' "$var"
}

confirm() {
  local prompt="$1" answer
  printf "  \033[1;33m%s [y/N]\033[0m: " "$prompt" >/dev/tty
  read -r answer </dev/tty
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ─── Root check ──────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Please run as root: sudo bash install.sh"

# ════════════════════════════════════════════════════════════
#   BANNER + DISCLAIMER
# ════════════════════════════════════════════════════════════
print_banner

echo -e "${BOLD}  This script will install:${NC}"
echo -e "  ${DIM}• Hotspot on your USB WiFi adapter (admin access point)${NC}"
echo -e "  ${DIM}• Client connection on built-in WiFi (target network)${NC}"
echo -e "  ${DIM}• DNS & traffic logger (dnsmasq)${NC}"
echo -e "  ${DIM}• Web dashboard (Flask) auto-launching on boot${NC}"
echo ""

if ! confirm "I confirm this is for my own network or I have explicit permission to test"; then
  echo -e "\n  ${RED}Installer aborted.${NC}\n"
  exit 0
fi

# ════════════════════════════════════════════════════════════
#   STEP 1: Detect interfaces
# ════════════════════════════════════════════════════════════
step "Detecting WiFi interfaces..."

mapfile -t IFACES < <(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')

if [[ ${#IFACES[@]} -lt 2 ]]; then
  err "Need at least 2 WiFi interfaces (built-in + USB adapter). Found: ${IFACES[*]:-none}"
fi

echo ""
echo -e "  ${DIM}Available WiFi interfaces:${NC}"
for i in "${!IFACES[@]}"; do
  MAC=$(cat "/sys/class/net/${IFACES[$i]}/address" 2>/dev/null || echo "unknown")
  echo -e "  ${BOLD}[$i]${NC} ${IFACES[$i]}  ${DIM}(MAC: $MAC)${NC}"
done
echo ""

AP_IF_IDX=$(ask "Index for HOTSPOT interface (USB adapter)" "1")
CLIENT_IF_IDX=$(ask "Index for TARGET NETWORK interface (built-in)" "0")

AP_IF="${IFACES[$AP_IF_IDX]}"
CLIENT_IF="${IFACES[$CLIENT_IF_IDX]}"

[[ -z "$AP_IF" ]]     && err "Invalid hotspot interface index: $AP_IF_IDX"
[[ -z "$CLIENT_IF" ]] && err "Invalid client interface index: $CLIENT_IF_IDX"
[[ "$AP_IF" == "$CLIENT_IF" ]] && err "Hotspot and client interfaces must be different"

ok "Hotspot interface:        $AP_IF"
ok "Target network interface: $CLIENT_IF"

# ════════════════════════════════════════════════════════════
#   STEP 2: Hotspot config
# ════════════════════════════════════════════════════════════
step "Hotspot configuration..."
echo ""

AP_SSID=$(ask "Hotspot SSID" "NetWatch-Admin")
while true; do
  AP_PASS=$(ask_secret "Hotspot password (min 8 chars)")
  [[ ${#AP_PASS} -ge 8 ]] && break
  echo -e "  ${RED}Password must be at least 8 characters. Try again.${NC}" >/dev/tty
done
AP_CHANNEL=$(ask "WiFi channel" "6")
AP_IP=$(ask "Hotspot static IP" "192.168.99.1")
AP_DHCP_START=$(ask "DHCP range start" "192.168.99.10")
AP_DHCP_END=$(ask "DHCP range end" "192.168.99.50")
DASHBOARD_PORT=$(ask "Dashboard port" "8080")

ok "SSID: $AP_SSID  |  IP: $AP_IP  |  Port: $DASHBOARD_PORT"

# ════════════════════════════════════════════════════════════
#   STEP 3: Target network
# ════════════════════════════════════════════════════════════
step "Target network..."
echo ""
echo -e "  ${DIM}Pre-configure a target network now, or connect later via the dashboard.${NC}"
echo ""

PRECONFIGURE_TARGET=false
TARGET_SSID=""
TARGET_PASS=""
if confirm "Pre-configure target network now?"; then
  PRECONFIGURE_TARGET=true
  TARGET_SSID=$(ask "Target network SSID")
  TARGET_PASS=$(ask_secret "Target network password (leave blank if open)")
fi

# ════════════════════════════════════════════════════════════
#   STEP 4: Summary + confirm
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}  ── Configuration Summary ─────────────────────────────────${NC}"
echo -e "  Hotspot:    ${BOLD}$AP_IF${NC}  SSID: ${BOLD}$AP_SSID${NC}  IP: ${BOLD}$AP_IP${NC}"
echo -e "  Client:     ${BOLD}$CLIENT_IF${NC}"
echo -e "  Dashboard:  http://$AP_IP:$DASHBOARD_PORT"
echo -e "  Target net: $PRECONFIGURE_TARGET ${TARGET_SSID:+($TARGET_SSID)}"
echo -e "${CYAN}${BOLD}  ───────────────────────────────────────────────────────────${NC}"
echo ""

if ! confirm "Proceed with installation?"; then
  echo -e "\n  ${YELLOW}Aborted.${NC}\n"
  exit 0
fi

# ════════════════════════════════════════════════════════════
#   STEP 5: Packages
# ════════════════════════════════════════════════════════════
step "Installing packages..."

echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive

apt-get update -q
apt-get install -y -q \
  hostapd \
  dnsmasq \
  iptables \
  iptables-persistent \
  tcpdump \
  arp-scan \
  net-tools \
  python3 \
  python3-pip \
  python3-venv \
  curl \
  jq \
  iw \
  wireless-tools \
  rfkill

rfkill unblock all
ok "Packages installed"

# ════════════════════════════════════════════════════════════
#   STEP 6: Python venv
# ════════════════════════════════════════════════════════════
step "Setting up Python dashboard..."

INSTALL_DIR="/opt/netwatch"
mkdir -p "$INSTALL_DIR"/{logs,static,templates}

python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -q --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -q flask flask-socketio scapy requests

ok "Python venv ready at $INSTALL_DIR"

# ════════════════════════════════════════════════════════════
#   STEP 7: Config file
# ════════════════════════════════════════════════════════════
step "Writing config..."

cat > "$INSTALL_DIR/config.json" <<EOF
{
  "ap_interface": "$AP_IF",
  "client_interface": "$CLIENT_IF",
  "ap_ssid": "$AP_SSID",
  "ap_ip": "$AP_IP",
  "dashboard_port": $DASHBOARD_PORT,
  "dhcp_start": "$AP_DHCP_START",
  "dhcp_end": "$AP_DHCP_END",
  "log_dir": "$INSTALL_DIR/logs"
}
EOF

ok "Config written"

# ════════════════════════════════════════════════════════════
#   STEP 8: hostapd
# ════════════════════════════════════════════════════════════
step "Configuring hostapd..."

systemctl unmask hostapd 2>/dev/null || true
systemctl stop hostapd 2>/dev/null || true

cat > /etc/hostapd/netwatch.conf <<EOF
interface=$AP_IF
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

sed -i 's|#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/netwatch.conf"|' /etc/default/hostapd

ok "hostapd configured"

# ════════════════════════════════════════════════════════════
#   STEP 9: dnsmasq
# ════════════════════════════════════════════════════════════
step "Configuring dnsmasq..."

[[ -f /etc/dnsmasq.conf ]] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
echo "" > /etc/dnsmasq.conf

cat > /etc/dnsmasq.d/netwatch.conf <<EOF
interface=$AP_IF
bind-interfaces
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,12h
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
log-queries
log-facility=$INSTALL_DIR/logs/dns_queries.log
domain-needed
bogus-priv
no-resolv
server=8.8.8.8
server=1.1.1.1
EOF

ok "dnsmasq configured"

# ════════════════════════════════════════════════════════════
#   STEP 10: Tell NetworkManager to leave AP interface alone
# ════════════════════════════════════════════════════════════
step "Configuring NetworkManager..."

mkdir -p /etc/NetworkManager/conf.d/
cat > /etc/NetworkManager/conf.d/netwatch-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:$AP_IF
EOF

systemctl restart NetworkManager 2>/dev/null || true
sleep 2

ok "NetworkManager will not touch $AP_IF"

# ════════════════════════════════════════════════════════════
#   STEP 11: AP interface static IP
# ════════════════════════════════════════════════════════════
step "Setting static IP on $AP_IF..."

ip link set "$AP_IF" up
ip addr flush dev "$AP_IF" 2>/dev/null || true
ip addr add "$AP_IP/24" dev "$AP_IF" 2>/dev/null || true

cat > /etc/systemd/network/10-netwatch-ap.network <<EOF
[Match]
Name=$AP_IF

[Network]
Address=$AP_IP/24
EOF

systemctl enable systemd-networkd 2>/dev/null || true
ok "Static IP $AP_IP on $AP_IF"

# ════════════════════════════════════════════════════════════
#   STEP 12: IP forwarding + NAT
# ════════════════════════════════════════════════════════════
step "Enabling IP forwarding and NAT..."

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-netwatch.conf
sysctl -p /etc/sysctl.d/99-netwatch.conf -q

AP_SUBNET=$(echo "$AP_IP" | cut -d'.' -f1-3).0/24

iptables -t nat -D POSTROUTING -s "$AP_SUBNET" -o "$CLIENT_IF" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "$AP_IF" -o "$CLIENT_IF" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$CLIENT_IF" -o "$AP_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

iptables -t nat -A POSTROUTING -s "$AP_SUBNET" -o "$CLIENT_IF" -j MASQUERADE
iptables -A FORWARD -i "$AP_IF" -o "$CLIENT_IF" -j ACCEPT
iptables -A FORWARD -i "$CLIENT_IF" -o "$AP_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

netfilter-persistent save
ok "NAT enabled"

# ════════════════════════════════════════════════════════════
#   STEP 13: Pre-connect to target network
# ════════════════════════════════════════════════════════════
if $PRECONFIGURE_TARGET && [[ -n "$TARGET_SSID" ]]; then
  step "Connecting to $TARGET_SSID..."
  if [[ -n "$TARGET_PASS" ]]; then
    nmcli dev wifi connect "$TARGET_SSID" password "$TARGET_PASS" ifname "$CLIENT_IF" 2>/dev/null \
      && ok "Connected to $TARGET_SSID" \
      || warn "Could not connect now — use dashboard after reboot"
  else
    nmcli dev wifi connect "$TARGET_SSID" ifname "$CLIENT_IF" 2>/dev/null \
      && ok "Connected to $TARGET_SSID" \
      || warn "Could not connect now — use dashboard after reboot"
  fi
fi

# ════════════════════════════════════════════════════════════
#   STEP 14: Dashboard HTML
# ════════════════════════════════════════════════════════════
step "Writing dashboard..."

cat > "$INSTALL_DIR/templates/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>NetWatch Dashboard</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.7.2/socket.io.min.js"></script>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#0a0e1a;color:#c9d1e0;font-family:'Segoe UI',monospace;min-height:100vh}
  header{background:#0d1221;border-bottom:1px solid #1e2d4a;padding:16px 24px;display:flex;align-items:center;gap:16px}
  header h1{font-size:1.3rem;color:#4fc3f7;letter-spacing:2px}
  .dot{width:10px;height:10px;border-radius:50%;background:#4caf50;animation:pulse 2s infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px;padding:20px}
  .card{background:#0d1221;border:1px solid #1e2d4a;border-radius:10px;padding:20px}
  .card h2{font-size:.75rem;color:#4fc3f7;letter-spacing:2px;text-transform:uppercase;margin-bottom:14px}
  .stat{font-size:2rem;font-weight:700;color:#fff}
  .stat-sub{font-size:.8rem;color:#5a7a9a;margin-top:2px}
  table{width:100%;border-collapse:collapse;font-size:.82rem}
  th{text-align:left;color:#4fc3f7;font-weight:600;padding:8px 10px;border-bottom:1px solid #1e2d4a;font-size:.7rem;letter-spacing:1px;text-transform:uppercase}
  td{padding:9px 10px;border-bottom:1px solid #111827;color:#c9d1e0;word-break:break-all}
  tr:hover td{background:#111827}
  .badge{display:inline-block;padding:2px 8px;border-radius:20px;font-size:.7rem;font-weight:600}
  .badge-green{background:#1a3a2a;color:#4caf50}
  .badge-blue{background:#1a2a3a;color:#4fc3f7}
  .log-box{background:#060a14;border:1px solid #1e2d4a;border-radius:8px;height:220px;overflow-y:auto;padding:12px;font-size:.75rem;color:#7a9abf;font-family:monospace}
  .log-line{padding:3px 0;border-bottom:1px solid #0d1221}
  .log-line .ts{color:#4fc3f7}
  .log-line .domain{color:#81d4fa}
  .section{padding:0 20px 20px}
  .section-title{font-size:.75rem;color:#4fc3f7;letter-spacing:2px;text-transform:uppercase;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid #1e2d4a;display:flex;align-items:center}
  form.wifi-form{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px}
  form.wifi-form input{background:#060a14;border:1px solid #1e2d4a;color:#c9d1e0;border-radius:6px;padding:8px 12px;font-size:.85rem;flex:1;min-width:140px}
  form.wifi-form button{background:#1565c0;color:#fff;border:none;border-radius:6px;padding:8px 18px;cursor:pointer;font-size:.85rem;font-weight:600}
  form.wifi-form button:hover{background:#1976d2}
  #wifi-status{margin-top:8px;font-size:.8rem}
  .refresh-btn{background:none;border:1px solid #1e2d4a;color:#4fc3f7;padding:4px 12px;border-radius:6px;font-size:.72rem;cursor:pointer;margin-left:auto}
  .refresh-btn:hover{background:#1e2d4a}
  .header-right{margin-left:auto;display:flex;align-items:center;gap:14px;font-size:.8rem;color:#5a7a9a}
</style>
</head>
<body>
<header>
  <div class="dot"></div>
  <h1>⚡ NETWATCH</h1>
  <div class="header-right">
    <span id="clock"></span>
    <span id="hostname-badge" class="badge badge-blue">-</span>
  </div>
</header>

<div class="grid">
  <div class="card">
    <h2>Devices on Network</h2>
    <div class="stat" id="device-count">-</div>
    <div class="stat-sub">detected via ARP scan</div>
  </div>
  <div class="card">
    <h2>DNS Queries Today</h2>
    <div class="stat" id="dns-count">-</div>
    <div class="stat-sub">logged queries</div>
  </div>
  <div class="card">
    <h2>Target Network</h2>
    <div class="stat" id="target-ssid" style="font-size:1.1rem">-</div>
    <div class="stat-sub" id="target-ip">not connected</div>
  </div>
  <div class="card">
    <h2>Pi Info</h2>
    <div class="stat" id="pi-mac" style="font-size:1rem">-</div>
    <div class="stat-sub" id="pi-hostname">-</div>
  </div>
</div>

<div class="section">
  <div class="section-title">Connect to Target Network</div>
  <form class="wifi-form" id="wifi-form">
    <input id="ssid" placeholder="Network SSID" autocomplete="off"/>
    <input id="password" type="password" placeholder="Password"/>
    <button type="submit">Connect</button>
  </form>
  <div id="wifi-status"></div>
</div>

<div class="section">
  <div class="section-title">
    Connected Devices
    <button class="refresh-btn" onclick="loadDevices()">↻ Refresh</button>
  </div>
  <table>
    <thead><tr><th>IP Address</th><th>MAC Address</th><th>Hostname</th><th>Status</th></tr></thead>
    <tbody id="devices-tbody"><tr><td colspan="4" style="color:#5a7a9a;text-align:center;padding:20px">Click Refresh to scan</td></tr></tbody>
  </table>
</div>

<div class="section">
  <div class="section-title">Live DNS Log</div>
  <div class="log-box" id="dns-log"><span style="color:#5a7a9a">Waiting for DNS queries...</span></div>
</div>

<script>
const socket = io();
let dnsCount = 0;

setInterval(() => {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString();
}, 1000);

async function loadStats() {
  try {
    const r = await fetch('/api/stats');
    const d = await r.json();
    document.getElementById('device-count').textContent = d.device_count ?? '-';
    document.getElementById('dns-count').textContent = d.dns_count ?? '-';
    document.getElementById('target-ssid').textContent = d.target_ssid || 'Not connected';
    document.getElementById('target-ip').textContent = d.target_ip || '';
    document.getElementById('pi-mac').textContent = d.pi_mac || '-';
    document.getElementById('pi-hostname').textContent = d.pi_hostname || '-';
    document.getElementById('hostname-badge').textContent = d.pi_hostname || '-';
  } catch(e) {}
}

async function loadDevices() {
  const tbody = document.getElementById('devices-tbody');
  tbody.innerHTML = '<tr><td colspan="4" style="color:#5a7a9a;text-align:center;padding:20px">Scanning...</td></tr>';
  try {
    const r = await fetch('/api/devices');
    const d = await r.json();
    if (!d.length) {
      tbody.innerHTML = '<tr><td colspan="4" style="color:#5a7a9a;text-align:center;padding:20px">No devices found</td></tr>';
      return;
    }
    tbody.innerHTML = d.map(dev => `
      <tr>
        <td>${dev.ip}</td>
        <td style="font-family:monospace;font-size:.78rem">${dev.mac}</td>
        <td>${dev.hostname || '<span style="color:#5a7a9a">unknown</span>'}</td>
        <td><span class="badge badge-green">Online</span></td>
      </tr>`).join('');
    document.getElementById('device-count').textContent = d.length;
  } catch(e) {
    tbody.innerHTML = '<tr><td colspan="4" style="color:#ef5350;text-align:center;padding:20px">Scan failed</td></tr>';
  }
}

socket.on('dns_event', data => {
  dnsCount++;
  document.getElementById('dns-count').textContent = dnsCount;
  const box = document.getElementById('dns-log');
  if (box.querySelector('span')) box.innerHTML = '';
  const div = document.createElement('div');
  div.className = 'log-line';
  const parts = data.line.match(/^(\w+\s+\d+\s+[\d:]+).*query\[.*?\]\s+(\S+)/);
  if (parts) {
    div.innerHTML = `<span class="ts">${parts[1]}</span> → <span class="domain">${parts[2]}</span>`;
  } else {
    div.textContent = data.line;
  }
  box.insertBefore(div, box.firstChild);
  if (box.children.length > 200) box.removeChild(box.lastChild);
});

document.getElementById('wifi-form').addEventListener('submit', async e => {
  e.preventDefault();
  const ssid = document.getElementById('ssid').value.trim();
  const pass = document.getElementById('password').value;
  const status = document.getElementById('wifi-status');
  if (!ssid) { status.textContent = 'Enter an SSID'; status.style.color = '#ef5350'; return; }
  status.textContent = 'Connecting...';
  status.style.color = '#ffca28';
  try {
    const r = await fetch('/api/connect', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ssid, password: pass})
    });
    const d = await r.json();
    status.textContent = d.success ? `✔ Connected to ${ssid}` : `✘ Failed: ${d.error || 'unknown'}`;
    status.style.color = d.success ? '#4caf50' : '#ef5350';
    if (d.success) { loadStats(); loadDevices(); }
  } catch(err) {
    status.textContent = '✘ Request failed';
    status.style.color = '#ef5350';
  }
});

loadStats();
setInterval(loadStats, 15000);
</script>
</body>
</html>
HTMLEOF

ok "Dashboard HTML written"

# ════════════════════════════════════════════════════════════
#   STEP 15: Flask app
# ════════════════════════════════════════════════════════════
cat > "$INSTALL_DIR/app.py" <<'PYEOF'
#!/usr/bin/env python3
"""NetWatch - Network Monitor Dashboard"""
import os, json, subprocess, re, threading, time
from flask import Flask, jsonify, request, render_template
from flask_socketio import SocketIO

CONFIG_PATH = os.path.join(os.path.dirname(__file__), 'config.json')
with open(CONFIG_PATH) as f:
    CONFIG = json.load(f)

LOG_DIR   = CONFIG['log_dir']
DNS_LOG   = os.path.join(LOG_DIR, 'dns_queries.log')
CLIENT_IF = CONFIG['client_interface']
AP_IF     = CONFIG['ap_interface']

app = Flask(__name__, template_folder='templates')
app.config['SECRET_KEY'] = os.urandom(24).hex()
socketio = SocketIO(app, cors_allowed_origins='*')


def run_cmd(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ''


def get_connected_ssid():
    out = run_cmd('nmcli -t -f active,ssid dev wifi')
    for line in out.splitlines():
        if line.startswith('yes:'):
            return line.split(':', 1)[1]
    return ''


def get_ip(iface):
    out = run_cmd(f'ip -4 addr show {iface}')
    m = re.search(r'inet (\S+)', out)
    return m.group(1) if m else ''


def get_mac(iface):
    try:
        with open(f'/sys/class/net/{iface}/address') as f:
            return f.read().strip()
    except Exception:
        return 'unknown'


def arp_scan():
    devices = []
    seen = set()
    out = run_cmd(f'arp-scan --interface={CLIENT_IF} --localnet 2>/dev/null', timeout=20)
    for line in out.splitlines():
        m = re.search(r'(\d+\.\d+\.\d+\.\d+)\s+([\da-f:]{17})', line, re.I)
        if m:
            ip, mac = m.group(1), m.group(2).lower()
            if ip not in seen:
                seen.add(ip)
                host = run_cmd(f'getent hosts {ip}')
                hostname = host.split()[1] if host else ''
                devices.append({'ip': ip, 'mac': mac, 'hostname': hostname})
    return devices


def count_dns_today():
    try:
        count = 0
        with open(DNS_LOG, 'r', errors='ignore') as f:
            for line in f:
                if 'query[' in line:
                    count += 1
        return count
    except Exception:
        return 0


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/stats')
def stats():
    return jsonify({
        'target_ssid':  get_connected_ssid(),
        'target_ip':    get_ip(CLIENT_IF),
        'pi_mac':       get_mac(CLIENT_IF),
        'pi_hostname':  run_cmd('hostname'),
        'device_count': len(arp_scan()),
        'dns_count':    count_dns_today(),
    })


@app.route('/api/devices')
def devices():
    return jsonify(arp_scan())


@app.route('/api/connect', methods=['POST'])
def connect_wifi():
    data     = request.get_json() or {}
    ssid     = data.get('ssid', '').strip()
    password = data.get('password', '').strip()
    if not ssid:
        return jsonify({'success': False, 'error': 'SSID required'})
    run_cmd(f'nmcli dev disconnect {CLIENT_IF}')
    time.sleep(1)
    if password:
        result = run_cmd(f'nmcli dev wifi connect "{ssid}" password "{password}" ifname {CLIENT_IF}', timeout=25)
    else:
        result = run_cmd(f'nmcli dev wifi connect "{ssid}" ifname {CLIENT_IF}', timeout=25)
    success = 'successfully activated' in result.lower() or 'connected' in result.lower()
    return jsonify({'success': success, 'error': '' if success else result})


def tail_dns_log():
    os.makedirs(LOG_DIR, exist_ok=True)
    open(DNS_LOG, 'a').close()
    with open(DNS_LOG, 'r', errors='ignore') as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if line and 'query[' in line:
                socketio.emit('dns_event', {'line': line.strip()})
            else:
                time.sleep(0.25)


if __name__ == '__main__':
    t = threading.Thread(target=tail_dns_log, daemon=True)
    t.start()
    port = CONFIG.get('dashboard_port', 8080)
    socketio.run(app, host='0.0.0.0', port=port, allow_unsafe_werkzeug=True)
PYEOF

ok "Flask app written"

# ════════════════════════════════════════════════════════════
#   STEP 16: Systemd services
# ════════════════════════════════════════════════════════════
step "Creating systemd services..."

# AP setup script runs before hostapd to configure the interface
cat > /usr/local/bin/netwatch-ap-setup.sh <<APEOF
#!/bin/bash
AP_IF="$AP_IF"
AP_IP="$AP_IP"
ip link set "\$AP_IF" up
ip addr flush dev "\$AP_IF" 2>/dev/null || true
ip addr add "\$AP_IP/24" dev "\$AP_IF" 2>/dev/null || true
APEOF
chmod +x /usr/local/bin/netwatch-ap-setup.sh

cat > /etc/systemd/system/netwatch-ap.service <<EOF
[Unit]
Description=NetWatch - Configure AP Interface
Before=hostapd.service dnsmasq.service
After=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/netwatch-ap-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/netwatch.service <<EOF
[Unit]
Description=NetWatch Dashboard
After=network.target hostapd.service dnsmasq.service
Wants=hostapd.service dnsmasq.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl unmask hostapd 2>/dev/null || true
systemctl enable netwatch-ap.service
systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable netwatch.service

ok "Services registered and enabled"

# ════════════════════════════════════════════════════════════
#   STEP 17: Start everything now
# ════════════════════════════════════════════════════════════
step "Starting services..."

/usr/local/bin/netwatch-ap-setup.sh

systemctl restart hostapd  && ok "hostapd started"   || warn "hostapd failed — run: journalctl -u hostapd -n 30"
systemctl restart dnsmasq  && ok "dnsmasq started"   || warn "dnsmasq failed — run: journalctl -u dnsmasq -n 30"
sleep 2
systemctl restart netwatch && ok "Dashboard started" || warn "Dashboard failed — run: journalctl -u netwatch -n 30"

# ════════════════════════════════════════════════════════════
#   DONE
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║         ✔  NETWATCH INSTALLED SUCCESSFULLY             ║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Hotspot SSID:${NC}  $AP_SSID"
echo -e "  ${BOLD}Dashboard:${NC}     ${CYAN}http://$AP_IP:$DASHBOARD_PORT${NC}"
echo ""
echo -e "  ${DIM}1. Connect your phone/laptop to WiFi: '${AP_SSID}'${NC}"
echo -e "  ${DIM}2. Open http://$AP_IP:$DASHBOARD_PORT in your browser${NC}"
echo -e "  ${DIM}3. Use the Connect form to join your target network${NC}"
echo -e "  ${DIM}4. Watch devices and DNS queries appear live${NC}"
echo ""
echo -e "  ${DIM}Logs:    tail -f $INSTALL_DIR/logs/dns_queries.log${NC}"
echo -e "  ${DIM}Status:  systemctl status netwatch hostapd dnsmasq${NC}"
echo ""
