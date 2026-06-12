# TouchPlay v1.3.0

Big quality pass over every feature outside the gamepad, driven by real-use feedback.

## PC server — now a real app window
- **New dashboard window** (dark, matching the app) instead of the terminal: live status,
  the 4 player slots, a calm activity feed, and an "open file-drop folder" shortcut.
  Close the window to stop the server. `--console` still gives the old terminal dashboard.
- `TouchPlay-Server.exe` is now built windowed — no console flash.

## Screen Mirror
- **Dedicated viewer screen** (the tile no longer opens the gamepad).
- **Aspect-ratio-correct scaling** — the picture is never stretched/squashed anymore.
- Sharper downscaling (INTER_AREA) + new **1080p** quality preset.
- Quality chips, stretch toggle and fps right in the viewer's auto-hiding top bar.
- **Touch Control** mode: use the mirrored picture as a giant trackpad — slide to move
  the PC cursor, tap to click, two fingers to scroll / right-click, pinch to zoom.

## Mouse & Keys
- **Completely new screen** (no more gamepad copy): proper trackpad surface, dedicated
  scroll strip, hold-able Left / Mid / Right buttons, double-tap-and-hold drag.
- **Rotates freely** — use it in portrait like a TV remote.
- **System keyboard piping**: tap Keyboard and everything you type (incl. backspace and
  Enter) goes to the PC. Tip: Gboard's floating mode works great with it.
- The floating mini-keyboard is now **scalable** (pinch or −/＋) and remembers its
  size & position; added Shift and Tab.

## Virtual Cam
- **Up to 30 fps at 720p** (was ~12–15 fps at 640×480): faster phone capture and the PC
  sink no longer throttles to 20 fps.
- The phone UI now shows the **true PC-side status**: live as a real webcam (with the
  device name) vs. preview-window fallback when the OBS driver is missing — with what
  to do about it. (Note: OBS hides its own virtual camera from its device list.)

## Projector
- ~22 fps capture (was ~12) and higher JPEG quality.
- Fixed the misleading "server is running an old version" error: the cast connection
  now retries once and reports the real cause (firewall / server not running / old build).

## File Transfer
- **Rotates to portrait**, where browsing files one-handed actually works.
- **Real image & video thumbnails** in the list (new `/thumb` endpoint on the PC).
- Clear "Not connected" state with instructions, and the list now **loads itself the
  moment the PC link comes up** — no more mysterious empty blocks.

## Under the hood
- Server and app now handshake on version **1.3.0**; the connection diagnostic flags
  old servers correctly.
- Cast channel handshake (`cast_ready` / `cast_status`) for accurate status on the phone.
