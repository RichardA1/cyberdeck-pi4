#!/bin/bash
# CyberDeck — Automated Setup Script
# Runs all installation stages from the README with verification.
# Usage: sudo bash setup.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Must run as root (sudo bash setup.sh)"
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

log()   { echo -e "\n\033[36m[STAGE] $1\033[0m"; }
ok()    { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail()  { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() {
  local desc="$1"; shift
  if eval "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

echo "======================================"
echo "  CyberDeck Automated Setup"
echo "======================================"
echo "  Repo: $REPO_DIR"
echo "  Date: $(date)"
echo "======================================"

# -------------------------------------------------------
log "1 — System Update & Packages"
# -------------------------------------------------------
apt-get update -qq
apt-get install -y -qq \
  hostapd dnsmasq mosquitto mosquitto-clients \
  nginx-light samba iptables git jq bc iw >/dev/null

for pkg in hostapd dnsmasq mosquitto mosquitto-clients nginx-light samba iptables jq; do
  check "$pkg installed" "dpkg -s $pkg 2>/dev/null | grep -q 'Status: install ok installed'"
done

# Stop services during setup
systemctl stop hostapd dnsmasq mosquitto nginx smbd nmbd 2>/dev/null || true
systemctl disable hostapd dnsmasq 2>/dev/null || true

# -------------------------------------------------------
log "3 — Network Stack & Static IP"
# -------------------------------------------------------
rfkill unblock wifi 2>/dev/null || true

if systemctl list-unit-files NetworkManager.service 2>/dev/null | grep -q enabled; then
  echo "  NetworkManager detected"
  cp "$REPO_DIR/config/networkmanager-unmanaged.conf" \
     /etc/NetworkManager/conf.d/99-unmanaged.conf
  systemctl restart NetworkManager
  sleep 2
  check "wlan0 unmanaged" "nmcli device status | grep wlan0 | grep -q unmanaged"

  ip addr flush dev wlan0 2>/dev/null || true
  ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
  ip link set wlan0 up

elif systemctl list-unit-files dhcpcd.service 2>/dev/null | grep -q enabled; then
  echo "  dhcpcd detected"
  cp "$REPO_DIR/config/dhcpcd.conf" /etc/dhcpcd.conf
  systemctl restart dhcpcd
  sleep 2
else
  echo "  WARNING: Unknown network stack, applying IP manually"
  ip addr flush dev wlan0 2>/dev/null || true
  ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
  ip link set wlan0 up
fi

# Wait for IP
RETRIES=0
while ! ip addr show wlan0 2>/dev/null | grep -q "192.168.4.1"; do
  RETRIES=$((RETRIES + 1))
  [ "$RETRIES" -gt 10 ] && { fail "Static IP assignment"; break; }
  ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
  sleep 1
done
check "wlan0 has 192.168.4.1" "ip addr show wlan0 | grep -q 192.168.4.1"

# -------------------------------------------------------
log "4 — hostapd"
# -------------------------------------------------------
cp "$REPO_DIR/config/hostapd.conf" /etc/hostapd/hostapd.conf
systemctl unmask hostapd 2>/dev/null || true
systemctl start hostapd
check "hostapd active" "systemctl is-active --quiet hostapd"

# -------------------------------------------------------
log "5 — dnsmasq"
# -------------------------------------------------------
[ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
cp "$REPO_DIR/config/dnsmasq.conf" /etc/dnsmasq.conf
killall dnsmasq 2>/dev/null || true
sleep 1
systemctl start dnsmasq
check "dnsmasq active" "systemctl is-active --quiet dnsmasq"

# -------------------------------------------------------
log "6 — Mosquitto MQTT"
# -------------------------------------------------------
cp "$REPO_DIR/config/mosquitto.conf" /etc/mosquitto/conf.d/cyberdeck.conf
systemctl restart mosquitto
sleep 3
check "mosquitto active" "systemctl is-active --quiet mosquitto"
check "No duplicate persistence_location" \
  "[ \$(grep -r 'persistence_location' /etc/mosquitto/ 2>/dev/null | wc -l) -le 1 ]"
check "WebSocket port 9001" "ss -ltn | grep -q ':9001 '"

# -------------------------------------------------------
log "7 — Nginx & Web Files"
# -------------------------------------------------------
mkdir -p /var/www/html
cp -r "$REPO_DIR/web/"* /var/www/html/
chown -R www-data:www-data /var/www/html

rm -f /etc/nginx/sites-enabled/default
cp "$REPO_DIR/config/nginx-cyberdeck" /etc/nginx/sites-available/cyberdeck
ln -sf /etc/nginx/sites-available/cyberdeck /etc/nginx/sites-enabled/cyberdeck

check "nginx config valid" "nginx -t"
systemctl restart nginx
check "nginx active" "systemctl is-active --quiet nginx"
check "index.html serves 200" \
  "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/) = '200' ]"

# -------------------------------------------------------
log "8 — iptables"
# -------------------------------------------------------
mkdir -p /etc/cyberdeck
cp "$REPO_DIR/config/iptables-captive.sh" /etc/cyberdeck/iptables-captive.sh
chmod +x /etc/cyberdeck/iptables-captive.sh
bash /etc/cyberdeck/iptables-captive.sh
check "iptables NAT rules" "iptables -t nat -L PREROUTING -n | grep -q REDIRECT"

# -------------------------------------------------------
log "9 — Samba"
# -------------------------------------------------------
groupadd -f webedit
usermod -aG webedit pi 2>/dev/null || true
usermod -aG webedit www-data 2>/dev/null || true
chown -R www-data:webedit /var/www/html
chmod -R 2775 /var/www/html
find /var/www/html -type f -exec chmod 0664 {} \;

cp "$REPO_DIR/config/smb-cyberdeck.conf" /etc/samba/smb-cyberdeck.conf
if ! grep -q "include = /etc/samba/smb-cyberdeck.conf" /etc/samba/smb.conf 2>/dev/null; then
  echo "include = /etc/samba/smb-cyberdeck.conf" >> /etc/samba/smb.conf
fi

systemctl restart smbd nmbd
check "smbd active" "systemctl is-active --quiet smbd"

echo ""
echo "  NOTE: Run 'sudo smbpasswd -a pi' after setup to set the Samba password."
echo ""

# -------------------------------------------------------
log "10 — Status Collector"
# -------------------------------------------------------
cp "$REPO_DIR/scripts/collect-status.sh" /usr/local/bin/collect-status.sh
chmod +x /usr/local/bin/collect-status.sh
cp "$REPO_DIR/config/cyberdeck-status.service" /etc/systemd/system/
cp "$REPO_DIR/config/cyberdeck-status.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cyberdeck-status.timer
/usr/local/bin/collect-status.sh 2>/dev/null || true
check "status timer active" "systemctl is-active --quiet cyberdeck-status.timer"
check "status.json exists" "[ -f /var/www/html/status.json ]"

# -------------------------------------------------------
log "11 — Shutdown Handler"
# -------------------------------------------------------
cp "$REPO_DIR/scripts/shutdown-handler.sh" /usr/local/bin/shutdown-handler.sh
chmod +x /usr/local/bin/shutdown-handler.sh
cp "$REPO_DIR/config/cyberdeck-shutdown.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cyberdeck-shutdown.service
sleep 1
check "shutdown handler active" "systemctl is-active --quiet cyberdeck-shutdown.service"

# -------------------------------------------------------
log "12 — Boot Persistence"
# -------------------------------------------------------
# Copy NM unmanaged config to /etc/cyberdeck for start-ap.sh fallback
cp "$REPO_DIR/config/networkmanager-unmanaged.conf" /etc/cyberdeck/ 2>/dev/null || true

cp "$REPO_DIR/scripts/start-ap.sh" /usr/local/bin/cyberdeck-start-ap.sh
chmod +x /usr/local/bin/cyberdeck-start-ap.sh
cp "$REPO_DIR/config/cyberdeck.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable cyberdeck.service
check "cyberdeck.service enabled" "systemctl is-enabled --quiet cyberdeck.service"

# -------------------------------------------------------
echo ""
echo "======================================"
echo "  Setup Complete: $PASS passed, $FAIL failed"
echo "======================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  Some checks failed — review the output above."
  echo "  Fix issues before rebooting."
else
  echo "  All checks passed!"
fi

echo ""
echo "  Next steps:"
echo "    1. Set Samba password:  sudo smbpasswd -a pi"
echo "    2. Reboot:              sudo reboot"
echo "    3. Connect to CyberDeck WiFi (password: ChangeMe123!)"
echo "    4. Open http://192.168.4.1/"
echo "    5. Run verify:          sudo bash scripts/verify.sh"
echo ""
