# Troubleshooting

## WiFi Network Not Visible

**Symptom:** The CyberDeck SSID doesn't appear when scanning for WiFi.

**Check hostapd:**
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd --no-pager -n 20
```

**Common causes:**
- WiFi is rf-killed: `sudo rfkill unblock wifi`
- WiFi country not set: `sudo raspi-config nonint do_wifi_country US`
- wlan0 not unmanaged: check `nmcli device status` shows `unmanaged`
- hostapd config error: check `/etc/hostapd/hostapd.conf` syntax

## Captive Portal Doesn't Appear

**This is expected on many modern devices.** Android 10+ and iOS 14+ probe
connectivity over HTTPS, which our plain-HTTP captive portal can't
intercept (no TLS cert for a private IP). The redirect works on older
devices and some browsers.

**Manual fallback:** Browse to `http://192.168.4.1` directly.

**Check DNS hijacking:**
```bash
dig @192.168.4.1 google.com +short
# Should return: 192.168.4.1
```

**Check iptables:**
```bash
sudo iptables -t nat -L PREROUTING -n
# Should show REDIRECT rules for ports 53, 80, 443
```

## Mosquitto Won't Start / Crash-Loops

**Most common cause:** Duplicate `persistence_location` in config.

```bash
grep -r "persistence_location" /etc/mosquitto/
# Should show only ONE line (in mosquitto.conf, NOT in cyberdeck.conf)
```

If cyberdeck.conf has `persistence_location`, remove it:
```bash
sudo nano /etc/mosquitto/conf.d/cyberdeck.conf
# Delete the persistence_location line
sudo systemctl restart mosquitto
```

## Under-Voltage Warnings (Lightning Bolt Icon)

The Pi 4 needs a proper USB-C 5V/3A supply. Cheap cables or weak chargers
cause under-voltage, leading to WiFi dropouts and SD card corruption.

```bash
vcgencmd get_throttled
# 0x0 = all clear
# Any other value = throttling has occurred
```

**Fix:** Use the official Raspberry Pi 4 power supply or a quality USB-C
PD adapter with a good cable.

## Thermal Throttling

The BCM2711 throttles at 80°C. Under sustained AP + broker load in an
enclosed space this can happen.

```bash
cat /sys/class/thermal/thermal_zone0/temp
# Divide by 1000 for °C — anything above 70 is getting warm
```

**Fix:** Add a heatsink. For enclosed deployments, use a passive aluminum
case or add a small fan.

## Samba Permission Errors

If you can connect but can't write files:

```bash
# Check group membership
groups pi
# Should include: webedit

# Check web root permissions
ls -la /var/www/html/
# Should show: drwxrwsr-x ... www-data webedit

# Fix if needed
sudo chown -R www-data:webedit /var/www/html
sudo chmod -R 2775 /var/www/html
```

## Services Don't Survive Reboot

The `cyberdeck.service` systemd unit reapplies the static IP and iptables
rules at boot. If it's not enabled:

```bash
sudo systemctl enable cyberdeck.service
sudo systemctl enable cyberdeck-status.timer
sudo systemctl enable cyberdeck-shutdown.service
```

## dnsmasq Fails to Start

dnsmasq must start **after** wlan0 has its static IP. If it starts too
early, it binds to the wrong address.

```bash
# Check if IP is assigned
ip addr show wlan0 | grep 192.168.4.1

# Restart dnsmasq after confirming IP
sudo systemctl restart dnsmasq
```

If dnsmasq is stuck (port 53 held by old process):
```bash
sudo killall dnsmasq
sleep 1
sudo systemctl start dnsmasq
```

## mDNS / .local Resolution Fails

The hostname `cyberdeck_pi4` contains an underscore, which is technically
invalid for mDNS. If `cyberdeck-pi4.local` doesn't resolve:

- Use the IP directly: `ssh pi@192.168.4.1` (when on CyberDeck WiFi)
- Or find the Pi's IP from your router's DHCP table (when on your home network)
- Consider changing the hostname to use a hyphen: `cyberdeck-pi4`

## MQTT WebSocket Connection Fails in Browser

```bash
# Verify WebSocket port is listening
ss -ltn | grep 9001

# Check nginx proxy config
sudo nginx -t

# Check Mosquitto WebSocket listener
grep -A1 "listener 9001" /etc/mosquitto/conf.d/cyberdeck.conf
```

The browser connects via `ws://192.168.4.1:9001/mqtt` which nginx proxies
to Mosquitto's WebSocket listener.
