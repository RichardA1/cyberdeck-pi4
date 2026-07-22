# Manual Setup Notes

## 5 GHz Access Point (Advanced)

The Pi 4's CYW43455 supports dual-band WiFi. By default, CyberDeck uses
2.4 GHz (channel 7) for maximum compatibility — most ESP8266/ESP32 IoT
devices only support 2.4 GHz.

To switch to 5 GHz for faster throughput (at shorter range):

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Change these lines:
```
hw_mode=a
channel=36
ieee80211ac=1
ieee80211n=1
wmm_enabled=1
```

Then restart:
```bash
sudo systemctl restart hostapd
```

**Note:** Not all client devices support 5 GHz. If a device can't see the
network after switching, change back to `hw_mode=g` and `channel=7`.

## USB-C Power Requirements

The Pi 4 needs 5V/3A via USB-C. The official Raspberry Pi 4 power supply
(5.1V/3A) is recommended. Symptoms of under-voltage:

- Lightning bolt icon on HDMI output
- Random WiFi disconnects
- SD card filesystem corruption
- `vcgencmd get_throttled` returns non-zero

## Ethernet Management Access

If you want SSH access to the Pi without joining the CyberDeck WiFi, you
can plug in an Ethernet cable to your home network. The Pi 4's eth0 will
get an IP via DHCP from your router. This does **not** enable internet
bridge mode — it's just for management.

```bash
# Find the eth0 IP
ip addr show eth0

# SSH via Ethernet
ssh pi@<eth0-ip>
```

Both eth0 and wlan0 can be active simultaneously. The AP and all services
continue running on wlan0 (192.168.4.1).

## WiFi Country Code

The WiFi radio won't transmit until a country code is set (regulatory
requirement). If you didn't set it in Raspberry Pi Imager:

```bash
sudo raspi-config nonint do_wifi_country US
sudo rfkill unblock wifi
```

Replace `US` with your country's ISO 3166-1 alpha-2 code.
