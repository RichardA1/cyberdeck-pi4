#!/bin/bash
# CyberDeck — iptables rules for captive portal (isolated mode)
# Redirects HTTP (80), HTTPS (443), and DNS (53) to the Pi

set -e

# Flush any existing NAT rules
iptables -t nat -F PREROUTING 2>/dev/null || true

# Redirect DNS queries to dnsmasq on the Pi
iptables -t nat -A PREROUTING -i wlan0 -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 53 -j REDIRECT --to-ports 53

# Redirect HTTP to nginx
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-ports 80

# Redirect HTTPS to nginx (will fail TLS but triggers captive portal detection)
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 443 -j REDIRECT --to-ports 80

echo "iptables: captive portal rules applied"
