# FH6 Controller — Flutter App

## Build & Run

```bash
flutter pub get
flutter run          # connect phone via USB, enable developer mode
# or
flutter build apk --release
```

## USB Tethering Setup (recommended — ~2ms latency)

1. Connect phone to PC via USB data cable
2. Phone → Settings → Hotspot & Tethering → USB Tethering → ON
3. The app will automatically try `192.168.42.129:8765` first

## WiFi Fallback

If USB tethering is unavailable, the app cycles through saved IPs. Tap the
connection bar at the top to enter your PC's LAN IP manually or scan the QR
code printed by `python main.py`.

## Button → FH6 Mapping

| Control    | FH6 Action     |
|------------|----------------|
| Left Stick | Steer          |
| RT         | Accelerate     |
| LT         | Brake          |
| A          | Handbrake      |
| B          | Rewind         |
| X          | Look back      |
| Y          | Change camera  |
| D-Pad ↑↓   | Anna assistant |
| START      | Pause          |
| BACK       | Menu           |
