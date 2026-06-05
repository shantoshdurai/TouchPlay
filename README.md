<div align="center">

# TouchPlay

**Turn your Android phone into a wireless Xbox controller for any PC game.**

[![Release](https://img.shields.io/github/v/release/shantoshdurai/TouchPlay?color=00D4FF&label=latest)](https://github.com/shantoshdurai/TouchPlay/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows-blue)](https://github.com/shantoshdurai/TouchPlay/releases/latest)
[![Android](https://img.shields.io/badge/android-8.0%2B-brightgreen)](https://github.com/shantoshdurai/TouchPlay/releases/latest)
[![License](https://img.shields.io/github/license/shantoshdurai/TouchPlay)](LICENSE)

</div>

---

## What is TouchPlay?

TouchPlay is a **local wireless gamepad** — your Android phone becomes a real Xbox 360 controller on your PC through a lightweight Python server. No Bluetooth, no cloud, no subscription. Works with **any game** that supports a gamepad.

- **Ultra-low latency** — LAN Wi-Fi or USB tethering (~2 ms)
- **Up to 4 phones at once** — local co-op out of the box
- **Game-specific layouts** — Forza Horizon racing HUD, Spider-Man 2 controls, full standard gamepad
- **Fully customizable** — drag, resize, and rebind every button in the built-in editor
- **Real haptic feedback** — direct motor control, not the quiet system tap

---

## Quick Start

### PC Setup (one time only)

1. **[Download the latest release](https://github.com/shantoshdurai/TouchPlay/releases/latest)**
2. Extract the zip anywhere
3. Double-click **`TouchPlay-Setup.bat`**
   - Automatically installs Python if needed
   - Automatically installs the ViGEm gamepad driver
   - Adds firewall rules and creates a Desktop shortcut
4. Done — launch **TouchPlay Server** from your Desktop

### Phone Setup

Download the app:

> **[⬇ Download TouchPlay.apk](https://github.com/shantoshdurai/TouchPlay/releases/latest)**

Or build from source — see [Building](#building-the-app).

### Connect

1. Make sure PC and phone are on the **same Wi-Fi network**
2. Start the server on PC (Desktop shortcut)
3. Open TouchPlay on your phone — it auto-connects

---

## Features

### Game Layouts

Switch layouts from the **Games tab** in the app. Every layout sends standard Xbox gamepad events — the server never changes.

| Layout | Description |
|--------|-------------|
| **Standard Gamepad** | Full dual-stick Xbox controller with floating joysticks |
| **Forza Horizon** | Racing HUD — wheel, pedals, drift brake, 4 steering modes |
| **Spider-Man 2** | Swing (RT), zip (L2+R2), web wings (Y), full combat buttons |
| **Custom** | Build your own from scratch — any game, any layout |

### Custom Layout Editor

Build your own touch layout for any game:
- Drop **buttons, sticks, triggers, D-pads, mouse pads**
- Bind to gamepad buttons, keyboard keys, or mouse clicks
- Drag to reposition, resize with a slider, adjust opacity
- Supports keyboard+mouse games (WASD, Space, Shift…)

### Co-op

Connect up to **4 phones simultaneously** — each gets its own virtual Xbox pad (Player 1–4). The server holds each pad slot for 20 seconds across drops so a Wi-Fi blip never interrupts your game.

---

## Screenshots

| Server Terminal | Standard Controller | Forza Racing HUD |
|:-:|:-:|:-:|
| *live player dashboard* | *full gamepad* | *wheel + pedals* |

---

## Building the App

Requirements: [Flutter SDK](https://flutter.dev/docs/get-started/install), Android SDK

```bash
cd client
flutter pub get
flutter build apk --release
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

---

## How It Works

```
Phone (Flutter app)
      │  WebSocket  (Wi-Fi / USB)
      ▼
PC Server (Python)
      │  ViGEm Bus Driver
      ▼
Virtual Xbox 360 Controller
      │  XInput API
      ▼
Your game
```

The server creates one virtual Xbox 360 pad per connected phone via [ViGEmBus](https://github.com/nefarius/ViGEmBus). The phone streams control events over a WebSocket. The server also handles keyboard and mouse injection for keyboard+mouse game layouts.

---

## Requirements

**PC:**
- Windows 10 / 11
- The setup script handles everything else (Python, ViGEm, firewall)

**Phone:**
- Android 8.0 (Oreo) or newer
- Same Wi-Fi network as the PC (or USB tethered)

---

## Comparison

| Feature | TouchPlay | 62Bytes Touch |
|---------|:---------:|:-------------:|
| Auto-installs ViGEm driver | ✅ | ❌ manual |
| Co-op (multiple phones) | ✅ up to 4 | ✅ |
| Custom layout editor | ✅ | ❌ |
| Real vibration feedback | ✅ | ✅ |
| Game-specific layouts | ✅ | ✅ |
| Open source | ✅ | ❌ |

---

## License

MIT — see [LICENSE](LICENSE)

---

<div align="center">
Made with ♥ · <a href="https://github.com/shantoshdurai/TouchPlay/issues">Report a bug</a> · <a href="https://github.com/shantoshdurai/TouchPlay/releases">Download</a>
</div>
