#!/bin/bash
# CyberDeck — Status collector
# Writes /var/www/html/status.json and /var/www/html/clients.json
# Called by cyberdeck-status.timer every ~10 seconds

WEB_ROOT="/var/www/html"

# --- Gather data ---
HOSTNAME=$(hostname)
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
UPTIME_HUMAN=$(uptime -p 2>/dev/null || echo "unknown")

# CPU temperature (millidegrees → degrees)
CPU_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
CPU_TEMP=$(echo "scale=1; $CPU_TEMP_RAW / 1000" | bc 2>/dev/null || echo "0")

# Load average
LOAD=$(awk '{print $1}' /proc/loadavg)

# Memory
MEM_TOTAL=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))

# Disk (root partition)
DISK_TOTAL=$(df / --output=size -BM | tail -1 | tr -d ' M')
DISK_USED=$(df / --output=used -BM | tail -1 | tr -d ' M')
DISK_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')

# Service states
svc_state() {
    systemctl is-active "$1" 2>/dev/null || echo "inactive"
}

SVC_HOSTAPD=$(svc_state hostapd)
SVC_DNSMASQ=$(svc_state dnsmasq)
SVC_MOSQUITTO=$(svc_state mosquitto)
SVC_NGINX=$(svc_state nginx)
SVC_SMBD=$(svc_state smbd)
SVC_TIMER=$(svc_state cyberdeck-status.timer)
SVC_SHUTDOWN=$(svc_state cyberdeck-shutdown.service)

# AP client count (connected WiFi stations)
AP_CLIENTS=0
if command -v iw &>/dev/null; then
    AP_CLIENTS=$(iw dev wlan0 station dump 2>/dev/null | grep -c "^Station" || echo "0")
fi

# Timestamp
TIMESTAMP=$(date +%s)

# --- Write status.json ---
cat > "${WEB_ROOT}/status.json" <<STATUSEOF
{
  "hostname": "${HOSTNAME}",
  "uptime_sec": ${UPTIME_SEC},
  "uptime_human": "${UPTIME_HUMAN}",
  "cpu_temp": ${CPU_TEMP},
  "load": ${LOAD},
  "mem_total_mb": ${MEM_TOTAL},
  "mem_used_mb": ${MEM_USED},
  "disk_total_mb": ${DISK_TOTAL},
  "disk_used_mb": ${DISK_USED},
  "disk_pct": ${DISK_PCT},
  "services": {
    "hostapd": "${SVC_HOSTAPD}",
    "dnsmasq": "${SVC_DNSMASQ}",
    "mosquitto": "${SVC_MOSQUITTO}",
    "nginx": "${SVC_NGINX}",
    "smbd": "${SVC_SMBD}",
    "status_timer": "${SVC_TIMER}",
    "shutdown_handler": "${SVC_SHUTDOWN}"
  },
  "ap_clients": ${AP_CLIENTS},
  "mode": "isolated",
  "timestamp": ${TIMESTAMP}
}
STATUSEOF

# --- Write clients.json (from dnsmasq leases) ---
LEASE_FILE="/var/lib/misc/dnsmasq.leases"
if [ -f "$LEASE_FILE" ]; then
    # Format: epoch mac ip hostname client-id
    echo "[" > "${WEB_ROOT}/clients.json"
    FIRST=true
    while IFS=' ' read -r expires mac ip host _clientid; do
        [ -z "$mac" ] && continue
        REMAINING=$(( expires - $(date +%s) ))
        [ "$REMAINING" -lt 0 ] && REMAINING=0
        HOURS=$(( REMAINING / 3600 ))
        MINS=$(( (REMAINING % 3600) / 60 ))

        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "${WEB_ROOT}/clients.json"
        fi

        cat >> "${WEB_ROOT}/clients.json" <<CLIENTEOF
  {
    "mac": "${mac}",
    "ip": "${ip}",
    "hostname": "${host}",
    "lease_remaining": "${HOURS}h ${MINS}m"
  }
CLIENTEOF
    done < "$LEASE_FILE"
    echo "]" >> "${WEB_ROOT}/clients.json"
else
    echo "[]" > "${WEB_ROOT}/clients.json"
fi

# Fix permissions
chown www-data:webedit "${WEB_ROOT}/status.json" "${WEB_ROOT}/clients.json" 2>/dev/null || true
chmod 664 "${WEB_ROOT}/status.json" "${WEB_ROOT}/clients.json" 2>/dev/null || true
