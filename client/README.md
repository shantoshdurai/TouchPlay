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

## Game Layouts (the "Games" tab)

Tap the **Games** chip in the top bar to switch the on-screen layout. Every
layout speaks the same Xbox-gamepad protocol, so the server never changes.

- **Standard Gamepad** — the full dual-stick Xbox controller.
- **Forza Horizon** — a mobile racing HUD: steering (wheel **or** L/R pads,
  switchable in Settings), hold-to-floor pedals, and a drift handbrake.

The selected layout and your steering choice are remembered between launches.
More games are stubbed as "coming soon" cards and slot into
`lib/games/game_profiles.dart` + a layout builder.

## Custom Layouts (build your own)

In the Games tab, **New Layout** opens the editor. Start from **Blank**, a
**Gamepad** starter, or a **Keyboard + Mouse** starter, then:

- **Add** buttons, sticks, triggers, a D-pad, or a **mouse pad**.
- **Drag** to move, **resize** with the slider, **delete**, and **rename**.
- **Bind** any button to a **gamepad button**, a **keyboard key** (WASD, Space,
  Shift, …), or a **mouse click** — so you can build a touch layout for
  keyboard+mouse games, not just gamepad ones.

Layouts are saved on the phone and appear as cards in the Games tab (edit/delete
from the card). Data model: `lib/games/custom_layout.dart`; live controls:
`lib/widgets/custom_controls.dart`; editor: `lib/screens/layout_editor.dart`.
The server gained keyboard + hold-able-mouse injection (`server/gamepad.py`).

## Forza layout → FH5 default controller mapping

| Touch control | Sends | Forza action     |
|---------------|-------|------------------|
| Steering wheel / pads | Left stick | Steer    |
| GAS (hold)    | RT    | Accelerate       |
| BRAKE (hold)  | LT    | Brake / reverse  |
| HBRAKE        | A     | E-brake (drift)  |
| CAM           | RB    | Switch camera    |
| REWIND        | Y     | Rewind           |
| HORN          | RS    | Horn             |
| CLUTCH        | LB    | Clutch (manual)  |
| SHIFT ↑       | B     | Upshift (manual) |
| MAP           | BACK  | Open map         |
| ANNA          | D-Pad ↓ | Assistant      |
| PHOTO         | D-Pad ↑ | Photo mode     |
| PAUSE         | START | Pause menu       |
