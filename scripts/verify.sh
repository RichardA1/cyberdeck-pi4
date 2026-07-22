#!/bin/bash
# CyberDeck — Full system verification
# Runs every check from the README setup stages. Exit 0 if all pass.

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if eval "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=============================="
echo "  CyberDeck Verification"
echo "=============================="
echo ""

echo "[Stage 1] Base Packages"
for pkg in hostapd dnsmasq mosquitto mosquitto-clients nginx-light samba iptables jq; do
    check "$pkg installed" "dpkg -s $pkg 2>/dev/null | grep -q 'Status: install ok installed'"
done
echo ""

echo "[Stage 3] Network & Static IP"
check "wlan0 has 192.168.4.1" "ip addr show wlan0 | grep -q 192.168.4.1"
echo ""

echo "[Stage 4] hostapd"
check "hostapd active" "systemctl is-active --quiet hostapd"
echo ""

echo "[Stage 5] dnsmasq"
check "dnsmasq active" "systemctl is-active --quiet dnsmasq"
check "DNS hijack resolves to Pi" "dig @192.168.4.1 anything.test +short | grep -q 192.168.4.1"
echo ""

echo "[Stage 6] Mosquitto MQTT"
check "mosquitto active" "systemctl is-active --quiet mosquitto"
# Check it stays up (not crash-looping)
sleep 3
check "mosquitto still active after 3s" "systemctl is-active --quiet mosquitto"
check "WebSocket port 9001 listening" "ss -ltn | grep -q ':9001 '"
# MQTT round-trip
(
    timeout 5 mosquitto_sub -h 192.168.4.1 -t "cyberdeck/verify" -C 1 &
    SUB_PID=$!
    sleep 1
    mosquitto_pub -h 192.168.4.1 -t "cyberdeck/verify" -m "verify-ok"
    wait $SUB_PID
) >/dev/null 2>&1
check "MQTT pub/sub round-trip" "timeout 5 mosquitto_sub -h 192.168.4.1 -t 'cyberdeck/verify2' -C 1 & sleep 1 && mosquitto_pub -h 192.168.4.1 -t 'cyberdeck/verify2' -m 'ok' && wait"
echo ""

echo "[Stage 7] Nginx"
check "nginx active" "systemctl is-active --quiet nginx"
check "index.html serves 200" "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/) = '200' ]"
check "devices.html serves 200" "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/devices.html) = '200' ]"
check "mqtt.html serves 200" "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/mqtt.html) = '200' ]"
check "captive /generate_204 returns 302" "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/generate_204) = '302' ]"
check "captive /hotspot-detect.html returns 302" "[ \$(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1/hotspot-detect.html) = '302' ]"
echo ""

echo "[Stage 8] iptables"
check "NAT PREROUTING rules exist" "iptables -t nat -L PREROUTING -n | grep -q REDIRECT"
echo ""

echo "[Stage 9] Samba"
check "smbd active" "systemctl is-active --quiet smbd"
check "nmbd active" "systemctl is-active --quiet nmbd"
echo ""

echo "[Stage 10] Status Collector"
check "status timer active" "systemctl is-active --quiet cyberdeck-status.timer"
check "status.json exists" "[ -f /var/www/html/status.json ]"
check "status.json is valid JSON" "jq . /var/www/html/status.json"
check "clients.json exists" "[ -f /var/www/html/clients.json ]"
check "clients.json is valid JSON" "jq . /var/www/html/clients.json"
# Check freshness (status.json should be < 30s old)
if [ -f /var/www/html/status.json ]; then
    AGE=$(( $(date +%s) - $(jq -r .timestamp /var/www/html/status.json 2>/dev/null || echo 0) ))
    check "status.json is fresh (< 30s)" "[ $AGE -lt 30 ]"
fi
echo ""

echo "[Stage 11] Shutdown Handler"
check "shutdown handler active" "systemctl is-active --quiet cyberdeck-shutdown.service"
echo ""

echo "[Stage 12] Boot Persistence"
check "cyberdeck.service enabled" "systemctl is-enabled --quiet cyberdeck.service"
check "cyberdeck-status.timer enabled" "systemctl is-enabled --quiet cyberdeck-status.timer"
check "cyberdeck-shutdown.service enabled" "systemctl is-enabled --quiet cyberdeck-shutdown.service"
echo ""

echo "=============================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
    echo "  Some checks failed. Review the output above."
    exit 1
else
    echo "  All checks passed!"
    exit 0
fi
