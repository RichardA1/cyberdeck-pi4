#!/bin/bash
# CyberDeck — Stop the AP stack

set -e

echo "[cyberdeck] Stopping services..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop mosquitto 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop smbd nmbd 2>/dev/null || true

# Flush iptables rules
iptables -t nat -F PREROUTING 2>/dev/null || true

# Remove static IP
ip addr flush dev wlan0 2>/dev/null || true

echo "[cyberdeck] All services stopped"
