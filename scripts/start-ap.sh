#!/bin/bash
# CyberDeck — Boot startup script
# Detects dhcpcd vs NetworkManager, assigns static IP, starts services,
# applies iptables captive portal rules.
#
# Called by cyberdeck.service at boot.

set -e
LOG_TAG="cyberdeck"

log() { logger -t "$LOG_TAG" "$1"; echo "[cyberdeck] $1"; }

log "=== CyberDeck boot sequence starting ==="

# --- Step 1: Unblock WiFi ---
rfkill unblock wifi 2>/dev/null || true
sleep 1

# --- Step 2: Detect network stack ---
if systemctl list-unit-files NetworkManager.service 2>/dev/null | grep -q enabled; then
    NET_STACK="networkmanager"
    log "Detected NetworkManager"

    # Ensure wlan0 is unmanaged
    if [ -f /etc/NetworkManager/conf.d/99-unmanaged.conf ]; then
        log "wlan0 unmanaged config present"
    else
        log "WARNING: NetworkManager unmanaged config missing, copying..."
        cp /etc/cyberdeck/networkmanager-unmanaged.conf \
           /etc/NetworkManager/conf.d/99-unmanaged.conf 2>/dev/null || true
        systemctl restart NetworkManager
        sleep 2
    fi

    # Assign static IP
    ip addr flush dev wlan0 2>/dev/null || true
    ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
    ip link set wlan0 up

elif systemctl list-unit-files dhcpcd.service 2>/dev/null | grep -q enabled; then
    NET_STACK="dhcpcd"
    log "Detected dhcpcd"

    # dhcpcd handles the static IP from /etc/dhcpcd.conf
    systemctl restart dhcpcd
    sleep 2
else
    NET_STACK="unknown"
    log "WARNING: Neither NetworkManager nor dhcpcd detected, applying IP manually"
    ip addr flush dev wlan0 2>/dev/null || true
    ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
    ip link set wlan0 up
fi

# --- Step 3: Verify static IP before proceeding ---
# dnsmasq MUST start AFTER the IP is assigned or it binds to the wrong address
RETRIES=0
while ! ip addr show wlan0 | grep -q "192.168.4.1"; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -gt 10 ]; then
        log "FATAL: Could not assign 192.168.4.1 to wlan0 after 10 retries"
        exit 1
    fi
    log "Waiting for 192.168.4.1 on wlan0 (attempt $RETRIES)..."
    ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
    sleep 1
done
log "Static IP 192.168.4.1 confirmed on wlan0"

# --- Step 4: Start hostapd ---
systemctl unmask hostapd 2>/dev/null || true
systemctl restart hostapd
log "hostapd started"

# --- Step 5: Start dnsmasq (AFTER static IP) ---
# Kill any stale dnsmasq processes first
killall dnsmasq 2>/dev/null || true
sleep 1
systemctl restart dnsmasq
log "dnsmasq started"

# --- Step 6: Start Mosquitto ---
systemctl restart mosquitto
log "mosquitto started"

# --- Step 7: Start Nginx ---
systemctl restart nginx
log "nginx started"

# --- Step 8: Start Samba ---
systemctl restart smbd nmbd
log "samba started"

# --- Step 9: Apply iptables captive portal rules ---
bash /etc/cyberdeck/iptables-captive.sh
log "iptables captive portal rules applied"

# --- Step 10: Write initial status ---
/usr/local/bin/collect-status.sh 2>/dev/null || true

log "=== CyberDeck boot sequence complete ==="
log "Network stack: $NET_STACK"
log "SSID: $(grep '^ssid=' /etc/hostapd/hostapd.conf | cut -d= -f2)"
log "IP: 192.168.4.1"
log "Dashboard: http://192.168.4.1/"
