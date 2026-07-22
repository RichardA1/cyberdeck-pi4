# CyberDeck — Raspberry Pi 4 MQTT Hub

A self-contained WiFi Access Point + MQTT Broker + Web Dashboard + Samba
file share on a Raspberry Pi 4 Model B. **Isolated mode only** — no
internet uplink required or expected. Connected clients get DHCP, DNS
(hijacked to the Pi), a captive portal, and a cyberdeck-themed dashboard.

```
┌────────────────────────────────────────────────┐
│  CyberDeck Pi4                                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │ hostapd  │ │mosquitto │ │  nginx   │       │
│  │ WiFi AP  │ │MQTT 1883 │ │ HTTP :80 │       │
│  │CyberDeck │ │ WS  9001 │ │ WS proxy │       │
│  └──────────┘ └──────────┘ └──────────┘       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │ dnsmasq  │ │  samba   │ │iptables  │       │
│  │ DHCP+DNS │ │webfiles  │ │ captive  │       │
│  └──────────┘ └──────────┘ └──────────┘       │
│         192.168.4.1 — SSID: CyberDeck         │
└────────────────────────────────────────────────┘
```

## Hardware

- Raspberry Pi 4 Model B (any RAM variant)
- microSD 16 GB+ (USB SSD/HDD planned for future expansion)
- USB-C 5V/3A power supply (official RPi PSU recommended)
- Heatsink recommended (sustained AP + broker load can throttle at 80°C)

## Quick Start

> **Prerequisite:** A freshly flashed Raspberry Pi OS Trixie Lite (64-bit).
> Use Raspberry Pi Imager to set hostname `cyberdeck-pi4`, enable SSH,
> create user `pi`, and **set WiFi country code** before first boot.

```bash
# 1. SSH into the Pi (on your home WiFi initially, or via Ethernet)
ssh pi@cyberdeck-pi4.local

# 2. Install git (not included in Trixie Lite by default)
sudo apt-get update && sudo apt-get install -y git

# 3. Clone the repo
git clone https://github.com/RichardA1/cyberdeck-pi4.git
cd cyberdeck-pi4

# 4. Run the installer
sudo bash setup.sh

# 5. Reboot
sudo reboot

# 6. Connect to the CyberDeck WiFi, open http://192.168.4.1
```

After reboot, the Pi broadcasts the **CyberDeck** SSID. Connect from any
device, and the captive portal should redirect you to the dashboard. If the
popup doesn't appear (common on HTTPS-probing devices), browse to
`http://192.168.4.1` manually.

## Default Credentials (change after install!)

| What             | Default            |
|------------------|--------------------|
| SSH user         | `pi`               |
| SSH password     | `raspberry`        |
| WiFi SSID        | `CyberDeck`        |
| WiFi password    | `ChangeMe123!`     |
| Samba user       | `pi`               |
| Samba password   | (set during setup) |

See **[Changing Credentials](#changing-credentials)** below.

## Web Pages

| Page               | URL                          | Purpose                              |
|--------------------|------------------------------|--------------------------------------|
| Server Overview    | `http://192.168.4.1/`        | System info, gauges, service health  |
| Connected Devices  | `http://192.168.4.1/devices.html` | WiFi clients, MQTT activity     |
| MQTT Dashboard     | `http://192.168.4.1/mqtt.html`    | Subscribe, publish, live feed   |

All pages share the cyberdeck dark-terminal aesthetic and a vertical tab
rail for navigation.

## Samba File Share

The web root (`/var/www/html`) is shared as `webfiles` over SMB, so you
can edit the dashboard pages from Windows/Mac/Linux:

```
# Windows Explorer address bar:
\\192.168.4.1\webfiles

# macOS Finder → Go → Connect to Server:
smb://192.168.4.1/webfiles

# Linux:
smbclient //192.168.4.1/webfiles -U pi
```

---

# Detailed Setup Instructions

Everything below is the step-by-step walkthrough with verification at each
stage. Run these on a fresh Raspberry Pi OS Trixie Lite (64-bit) install.

## Prerequisites

### Flash the SD Card

1. Download and install [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi OS Lite (64-bit)** — the Trixie release
3. Click the gear/settings icon and configure:
   - Hostname: `cyberdeck-pi4`
   - Enable SSH (password authentication)
   - Username: `pi`
   - Password: `raspberry`
   - WiFi country: `US` (or your country code)
   - Locale/timezone as needed
4. Flash to your microSD card
5. Insert into Pi 4, connect power and Ethernet (for initial setup)

### First SSH Connection

```bash
ssh pi@cyberdeck-pi4.local
# Accept the host key, enter password: raspberry
```

**If `cyberdeck-pi4.local` doesn't resolve:** The underscore is technically
invalid in mDNS hostnames. Find the Pi's IP from your router's DHCP table
and SSH to that IP instead. We'll fix the hostname during setup if needed.

### Verify: Correct OS

```bash
cat /etc/os-release | grep PRETTY
# Expected: PRETTY_NAME="Debian GNU/Linux trixie/sid" (or similar Trixie)

uname -a
# Expected: aarch64, kernel 6.18.x
```

---

## Stage 1: System Update & Base Packages

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

### Verify: System is current

```bash
sudo apt-get -s upgrade | grep "^0 upgraded"
# Expected: "0 upgraded, 0 newly installed, 0 to remove..."
```

### Install all required packages

```bash
sudo apt-get install -y \
  hostapd \
  dnsmasq \
  mosquitto mosquitto-clients \
  nginx-light \
  samba \
  iptables \
  git \
  jq
```

### Verify: All packages installed

```bash
for pkg in hostapd dnsmasq mosquitto mosquitto-clients nginx-light samba iptables git jq; do
  dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed" \
    && echo "PASS: $pkg" \
    || echo "FAIL: $pkg"
done
```

**Expected:** All PASS. If any FAIL, re-run `apt-get install` for that package.

### Stop services during configuration

```bash
sudo systemctl stop hostapd dnsmasq mosquitto nginx smbd nmbd 2>/dev/null
sudo systemctl disable hostapd dnsmasq 2>/dev/null
# We'll manage these via our own systemd unit
```

---

## Stage 2: Install Git & Clone the Repo

Git is not included in Trixie Lite by default — install it first:

```bash
sudo apt-get install -y git
```

```bash
cd ~
git clone https://github.com/RichardA1/cyberdeck-pi4.git
cd cyberdeck-pi4
```

Or if working locally, copy the project files to the Pi via SCP:

```bash
# From your laptop:
scp -r cyberdeck-pi4/ pi@cyberdeck-pi4.local:~/
```

---

## Stage 3: Network Stack Detection & Static IP

### Detect which network manager is present

```bash
if systemctl list-unit-files NetworkManager.service | grep -q enabled; then
  echo "NetworkManager detected (Trixie/Bookworm)"
elif systemctl list-unit-files dhcpcd.service | grep -q enabled; then
  echo "dhcpcd detected (older Pi OS)"
else
  echo "WARNING: Neither detected"
fi
```

**Expected on Trixie:** `NetworkManager detected`

### Unblock WiFi and set country code (required)

The WiFi radio is rf-killed on a fresh headless install until a country
code is set. **Both commands are required** even if you set the country in
Raspberry Pi Imager — the headless boot may not have applied it:

```bash
sudo raspi-config nonint do_wifi_country US
sudo rfkill unblock wifi
rfkill list wifi
# Expected: "Soft blocked: no" and "Hard blocked: no"
```

Replace `US` with your country's ISO 3166-1 alpha-2 code if needed.

### Install NetworkManager unmanaged config

```bash
sudo cp ~/cyberdeck-pi4/config/networkmanager-unmanaged.conf \
  /etc/NetworkManager/conf.d/99-unmanaged.conf
sudo systemctl restart NetworkManager
sleep 2
```

### Verify: wlan0 is unmanaged

```bash
nmcli device status | grep wlan0
# Expected: wlan0  wifi  unmanaged  --
```

### Apply static IP

```bash
sudo ip addr flush dev wlan0
sudo ip addr add 192.168.4.1/24 dev wlan0
sudo ip link set wlan0 up
```

### Verify: Static IP assigned

```bash
ip addr show wlan0 | grep "192.168.4.1"
# Expected: inet 192.168.4.1/24 ...
```

---

## Stage 4: hostapd (WiFi Access Point)

### Install config

```bash
sudo cp ~/cyberdeck-pi4/config/hostapd.conf /etc/hostapd/hostapd.conf
```

### Verify: Config file contents

```bash
grep -E "^ssid=|^wpa_passphrase=" /etc/hostapd/hostapd.conf
# Expected:
#   ssid=CyberDeck
#   wpa_passphrase=ChangeMe123!
```

### Unmask and start hostapd

```bash
sudo systemctl unmask hostapd
sudo systemctl start hostapd
```

### Verify: hostapd is running and SSID is visible

```bash
systemctl is-active hostapd
# Expected: active

# From another device, scan for WiFi networks — you should see "CyberDeck"
```

---

## Stage 5: dnsmasq (DHCP + DNS Hijacking)

### Install config

```bash
# Disable the default dnsmasq config
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null
sudo cp ~/cyberdeck-pi4/config/dnsmasq.conf /etc/dnsmasq.conf
```

### Verify: dnsmasq config is correct

```bash
grep -E "^interface=|^dhcp-range=|^address=" /etc/dnsmasq.conf
# Expected:
#   interface=wlan0
#   dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
#   address=/#/192.168.4.1
```

### Start dnsmasq (AFTER static IP is set — critical ordering)

```bash
sudo systemctl start dnsmasq
```

### Verify: dnsmasq is running and DNS resolves to Pi

```bash
systemctl is-active dnsmasq
# Expected: active

dig @192.168.4.1 anything.test +short
# Expected: 192.168.4.1
```

---

## Stage 6: Mosquitto MQTT Broker

### Install config

```bash
sudo cp ~/cyberdeck-pi4/config/mosquitto.conf \
  /etc/mosquitto/conf.d/cyberdeck.conf
```

### Verify: No duplicate persistence_location

```bash
grep -r "persistence_location" /etc/mosquitto/
# Expected: Only ONE line, in the main mosquitto.conf (NOT in cyberdeck.conf)
```

### Start Mosquitto

```bash
sudo systemctl restart mosquitto
```

### Verify: Mosquitto starts AND stays up (catches crash-loop)

```bash
systemctl is-active mosquitto
# Expected: active

sleep 5
systemctl is-active mosquitto
# Expected: still active (if it says "activating" or "failed", the config is bad)
```

### Verify: MQTT pub/sub round-trip

```bash
# In one terminal:
timeout 5 mosquitto_sub -h 192.168.4.1 -t "test/verify" -C 1 &
SUB_PID=$!
sleep 1

# In the same terminal:
mosquitto_pub -h 192.168.4.1 -t "test/verify" -m "hello-cyberdeck"
wait $SUB_PID
# Expected: prints "hello-cyberdeck"
```

### Verify: WebSocket port 9001 is listening

```bash
ss -ltn | grep 9001
# Expected: LISTEN ... *:9001 ...
```

---

## Stage 7: Nginx (Web Server + Captive Portal + WS Proxy)

### Install web files

```bash
sudo mkdir -p /var/www/html
sudo cp -r ~/cyberdeck-pi4/web/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html
```

### Install nginx config

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo cp ~/cyberdeck-pi4/config/nginx-cyberdeck /etc/nginx/sites-available/cyberdeck
sudo ln -sf /etc/nginx/sites-available/cyberdeck /etc/nginx/sites-enabled/cyberdeck
```

### Verify: Nginx config syntax

```bash
sudo nginx -t
# Expected: syntax is ok / test is successful
```

### Start Nginx

```bash
sudo systemctl restart nginx
```

### Verify: Pages serve correctly

```bash
curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/devices.html
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/mqtt.html
# Expected: 200
```

### Verify: Captive portal redirects

```bash
curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/generate_204
# Expected: 302

curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/hotspot-detect.html
# Expected: 302
```

---

## Stage 8: iptables (Captive Portal Interception)

### Apply captive portal rules

```bash
sudo bash ~/cyberdeck-pi4/config/iptables-captive.sh
```

### Verify: Rules are active

```bash
sudo iptables -t nat -L PREROUTING -n | grep -E "REDIRECT|DNAT"
# Expected: Rules redirecting ports 80, 443, 53 to the Pi
```

---

## Stage 9: Samba File Share

### Set up the webedit group

```bash
sudo groupadd -f webedit
sudo usermod -aG webedit pi
sudo usermod -aG webedit www-data

# Set ownership and permissions on web root
sudo chown -R www-data:webedit /var/www/html
sudo chmod -R 2775 /var/www/html
sudo find /var/www/html -type f -exec chmod 0664 {} \;
```

### Install Samba config

```bash
sudo cp ~/cyberdeck-pi4/config/smb-cyberdeck.conf /etc/samba/smb-cyberdeck.conf

# Include our config from the main smb.conf (if not already)
if ! grep -q "include = /etc/samba/smb-cyberdeck.conf" /etc/samba/smb.conf; then
  echo "include = /etc/samba/smb-cyberdeck.conf" | sudo tee -a /etc/samba/smb.conf
fi
```

### Set Samba password for pi user

```bash
sudo smbpasswd -a pi
# Enter a password when prompted (this is separate from the SSH password)
```

### Restart Samba

```bash
sudo systemctl restart smbd nmbd
```

### Verify: Samba is running

```bash
systemctl is-active smbd
# Expected: active

systemctl is-active nmbd
# Expected: active
```

### Verify: Share is configured

```bash
testparm -s 2>/dev/null | grep -A2 "\[webfiles\]"
# Expected:
#   [webfiles]
#       comment = CyberDeck web files
#       path = /var/www/html
```

**From another device on the same network** (Windows, Mac, or Linux):

```
Windows Explorer:  \\cyberdeck-pi4.local\webfiles
macOS Finder:      smb://cyberdeck-pi4.local/webfiles
```

Enter username `pi` and the Samba password you set.

### Verify: Write-through works (SMB write → Nginx serves)

```bash
echo "samba-test-ok" | sudo tee /var/www/html/samba-test.txt
curl -s http://192.168.4.1/samba-test.txt
# Expected: samba-test-ok
sudo rm /var/www/html/samba-test.txt
```

---

## Stage 10: Status Collector (systemd timer)

### Install the collector script

```bash
sudo cp ~/cyberdeck-pi4/scripts/collect-status.sh /usr/local/bin/collect-status.sh
sudo chmod +x /usr/local/bin/collect-status.sh
```

### Install systemd units

```bash
sudo cp ~/cyberdeck-pi4/config/cyberdeck-status.service /etc/systemd/system/
sudo cp ~/cyberdeck-pi4/config/cyberdeck-status.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cyberdeck-status.timer
```

### Verify: Timer is running and JSON is generated

```bash
systemctl is-active cyberdeck-status.timer
# Expected: active

# Force a run and check
sudo /usr/local/bin/collect-status.sh
cat /var/www/html/status.json | jq .hostname
# Expected: "cyberdeck_pi4"

cat /var/www/html/clients.json | jq length
# Expected: 0 (or more if clients are connected)
```

---

## Stage 11: Shutdown API (for the web shutdown button)

### Install the shutdown handler

```bash
sudo cp ~/cyberdeck-pi4/scripts/shutdown-handler.sh /usr/local/bin/shutdown-handler.sh
sudo chmod +x /usr/local/bin/shutdown-handler.sh
sudo cp ~/cyberdeck-pi4/config/cyberdeck-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cyberdeck-shutdown.service
```

### Verify: Shutdown listener is running

```bash
systemctl is-active cyberdeck-shutdown.service
# Expected: active

# Test the endpoint (should return OK but NOT actually shut down
# unless you confirm via the web UI — the handler requires a POST)
curl -s http://192.168.4.1:8080/ping
# Expected: pong
```

---

## Stage 12: Boot Persistence (systemd service)

### Install the boot service

```bash
sudo cp ~/cyberdeck-pi4/config/cyberdeck.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cyberdeck.service
```

### Verify: Service is enabled

```bash
systemctl is-enabled cyberdeck.service
# Expected: enabled

systemctl is-enabled cyberdeck-status.timer
# Expected: enabled
```

---

## Stage 13: Full System Test

### Reboot and verify everything comes up

```bash
sudo reboot
```

Wait 30-60 seconds, then from another device:

1. **Connect to CyberDeck WiFi** (password: `ChangeMe123!`)
2. **Browse to `http://192.168.4.1/`** — you should see the Server Overview

### SSH back in and run the full verification

```bash
ssh pi@192.168.4.1
cd ~/cyberdeck-pi4
sudo bash scripts/verify.sh
```

This runs every check from stages 1-12 and prints a summary.

### Manual post-reboot checks

```bash
# All services up
for svc in hostapd dnsmasq mosquitto nginx smbd cyberdeck-status.timer cyberdeck-shutdown.service; do
  echo "$svc: $(systemctl is-active $svc)"
done
# Expected: all "active"

# Static IP persisted
ip addr show wlan0 | grep 192.168.4.1
# Expected: inet 192.168.4.1/24

# DNS hijacking works
dig @192.168.4.1 google.com +short
# Expected: 192.168.4.1

# iptables rules persisted
sudo iptables -t nat -L PREROUTING -n | grep REDIRECT
# Expected: redirect rules present

# MQTT round-trip
timeout 5 mosquitto_sub -h 192.168.4.1 -t "test/reboot" -C 1 &
sleep 1
mosquitto_pub -h 192.168.4.1 -t "test/reboot" -m "survived-reboot"
wait
# Expected: prints "survived-reboot"

# Web pages
for page in / /devices.html /mqtt.html; do
  echo "$page: $(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1$page)"
done
# Expected: all 200

# Captive portal
curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1/generate_204
# Expected: 302

# Status JSON is fresh
AGE=$(( $(date +%s) - $(jq -r .timestamp /var/www/html/status.json) ))
echo "status.json age: ${AGE}s"
# Expected: under 30 seconds
```

---

## Automated Setup (Alternative)

Instead of running each stage manually, you can use the automated installer:

```bash
cd ~/cyberdeck-pi4
sudo bash setup.sh
sudo reboot
```

`setup.sh` runs all stages above and prints PASS/FAIL for each verification
step. Review the output before rebooting.

---

# Changing Credentials

After confirming everything works, change these defaults.

## SSH Password

```bash
passwd
# Enter current password (raspberry), then new password twice
```

## WiFi SSID and Password

```bash
sudo nano /etc/hostapd/hostapd.conf
# Change: ssid=CyberDeck → your preferred SSID
# Change: wpa_passphrase=ChangeMe123! → your new password (8+ chars)

sudo systemctl restart hostapd
```

**Verify:** Scan for WiFi from another device — old SSID gone, new one visible.

## Samba Password

```bash
sudo smbpasswd pi
# Enter new SMB password twice
```

**Verify:** From another device, connect to `\\cyberdeck-pi4.local\webfiles` with the new password.

## Hostname

```bash
sudo hostnamectl set-hostname your-new-hostname

# Also update /etc/hosts
sudo sed -i "s/cyberdeck-pi4/your-new-hostname/g" /etc/hosts

# Update the status collector so the dashboard reflects it
sudo systemctl restart cyberdeck-status.timer

sudo reboot
```

**Verify:** `hostname` shows the new name; the dashboard Home page shows it.

## MQTT Broker (add authentication)

By default, Mosquitto allows anonymous connections (appropriate for an
isolated AP). To require credentials:

```bash
# Create a password file
sudo mosquitto_passwd -c /etc/mosquitto/passwd mqtt_user
# Enter password when prompted

# Edit the config
sudo nano /etc/mosquitto/conf.d/cyberdeck.conf
# Add:
#   allow_anonymous false
#   password_file /etc/mosquitto/passwd

sudo systemctl restart mosquitto
```

**Verify:** `mosquitto_pub -h 192.168.4.1 -t test -m hello` should fail;
`mosquitto_pub -h 192.168.4.1 -u mqtt_user -P your_pass -t test -m hello` should work.

**Note:** If you add MQTT auth, you'll also need to update `mqtt.html` to
prompt for credentials or hardcode them (not recommended on a shared AP).

## Nginx (add basic auth to the dashboard)

If you want to password-protect the web dashboard:

```bash
sudo apt-get install -y apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd admin
# Enter password

# Edit the nginx config to add auth
sudo nano /etc/nginx/sites-available/cyberdeck
# Inside the "location / {" block, add:
#   auth_basic "CyberDeck";
#   auth_basic_user_file /etc/nginx/.htpasswd;

sudo nginx -t && sudo systemctl restart nginx
```

---

# Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues
including WiFi not broadcasting, captive portal not appearing, under-voltage
warnings, thermal throttling, and Samba permission errors.

---

## License

MIT — see [LICENSE](LICENSE).
