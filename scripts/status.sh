#!/bin/bash
# CyberDeck — CLI status report

echo "=============================="
echo "  CyberDeck Status Report"
echo "=============================="
echo ""

# Network
echo "NETWORK:"
echo "  IP (wlan0):   $(ip -4 addr show wlan0 2>/dev/null | grep inet | awk '{print $2}' || echo 'not assigned')"
echo "  SSID:         $(grep '^ssid=' /etc/hostapd/hostapd.conf 2>/dev/null | cut -d= -f2 || echo 'unknown')"
echo "  Mode:         Isolated"
echo "  AP Clients:   $(iw dev wlan0 station dump 2>/dev/null | grep -c '^Station' || echo '0')"
echo ""

# Services
echo "SERVICES:"
for svc in hostapd dnsmasq mosquitto nginx smbd nmbd cyberdeck.service cyberdeck-status.timer cyberdeck-shutdown.service; do
    STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "not found")
    printf "  %-30s %s\n" "$svc" "$STATE"
done
echo ""

# System
echo "SYSTEM:"
echo "  Hostname:     $(hostname)"
echo "  Uptime:       $(uptime -p 2>/dev/null || echo 'unknown')"
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
echo "  CPU Temp:     $(echo "scale=1; $TEMP / 1000" | bc 2>/dev/null || echo '?')°C"
echo "  Load:         $(awk '{print $1, $2, $3}' /proc/loadavg)"
echo "  Memory:       $(free -m | awk '/^Mem:/ {printf "%d / %d MB (%d%%)", $3, $2, $3/$2*100}')"
echo "  Disk:         $(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
echo ""

# Ports
echo "LISTENING PORTS:"
ss -ltn | grep -E ':(80|1883|9001|445|139|53|8080)\b' | awk '{printf "  %s\n", $4}'
echo ""

# Throttle check
if command -v vcgencmd &>/dev/null; then
    THROTTLE=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    if [ "$THROTTLE" = "0x0" ]; then
        echo "THROTTLE: None (all clear)"
    else
        echo "THROTTLE: WARNING — flags=$THROTTLE (check power/thermals)"
    fi
fi

echo ""
echo "=============================="
