# FH6 Controller — Server

## Prerequisites

1. Install [ViGEmBus driver](https://github.com/nefarius/ViGEmBus/releases) — run the installer as Administrator and reboot.
2. Python 3.9+

## Setup

```bash
pip install -r requirements.txt
python main.py
```

The server will:
- Create a virtual Xbox 360 controller (visible in `joy.cpl`)
- Print the WebSocket URL and save `qr.png` to the current directory
- Listen on port `8765` for the Flutter app

## USB Tethering (recommended — lowest latency)

1. Connect phone to PC via USB cable
2. On phone: Settings → Hotspot & Tethering → USB Tethering → ON
3. The server auto-detects the `192.168.42.x` address and uses it for the QR code

## WiFi Fallback

If USB tethering is not active, the server falls back to your LAN IP. Both PC and phone must be on the same WiFi network.
