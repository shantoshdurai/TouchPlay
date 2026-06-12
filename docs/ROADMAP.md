# TouchPlay — Competitor Gaps & Release Roadmap

> Goal: learn from the most popular "phone → PC controller" app, **fix what its
> users have been asking for (some for 2+ years)**, and out-innovate it on
> experience. We copy table-stakes where it makes sense, but we win on
> reliability, correctness, customization, and feel. Not an attack — just doing
> right by users who deserve better.

## The app we benchmark against

**"Touch - A Pc Controller"** by **62Bytes** (Play Store id `com.S2bytes.touch`).
- Windows-only `.exe` server + Android app. Simulates an Xbox 360 pad via ViGEm.
- Has game-specific layouts (GTA 5, RDR2, Watch Dogs 2), mouse/media layouts,
  multi-device, and four pairing modes (Wi-Fi, USB, Bluetooth, QR).
- Public issue trackers (our research source):
  - Server: https://github.com/62Bytes/Touch-Server/issues
  - Client: https://github.com/62Bytes/Touch-Client/issues
- Sentiment: loved when it works ("best app from Play Store"), but recurring
  complaints about **connection drops, driver pain, antivirus flags, no custom
  layouts, no rumble, mapping bugs, input lag**.

Issue refs below use `S#n` = Touch-Server, `C#n` = Touch-Client.

---

## Where we ALREADY beat them (our edge today — protect & market it)

- [x] **Cross-platform-ready server** — ours is Python, not a Windows-only `.exe`
      (their Mac/Linux requests: C#3, S#43, S#28 sit unanswered for years).
- [x] **Auto-discovery + auto-reconnect + USB tethering (~2 ms)** — UDP broadcast
      finds the PC instantly; we silently retry. Directly targets their #1 pain
      (S#1/6/7/8/21/24).
- [x] **Live transparency** — latency (ms), phone temp, and battery in the status
      chip. They show none of this; users guess whether lag is "app or hotspot".
- [x] **Stick ≠ stick-click** — our LS/RS are separate controls, so we don't have
      their "moving the stick also presses L3/R3" bug (S#29).
- [x] **Per-game layouts already shipping** — Standard + Forza Horizon, with a
      **steering wheel** — which is *literally* an open request there (S#25).
- [x] **Themed, considered UI** — monochrome, quiet-at-rest/cyan-on-press, a
      first-run steering chooser, profile-aware settings.

---

## Signal from real users — grouped, with evidence

### 1. Custom / editable layout editor  ⭐ most-requested, still unbuilt by them
- Drag/resize/add/remove buttons; save your own layout. C#2, S#13 ("like Remote
  Gamepad's editor", +"couldn't agree more"), S#5, S#3.
- **Our move:** a real layout editor — long-press to enter edit mode, move/scale
  any control, add buttons from a palette, bind to any gamepad/key/mouse action,
  save **per game profile**, export/import/share as a file.

### 2. Connection reliability & dead-simple pairing  ⭐ biggest frustration
- Drops every ~2 s (S#8), intermittent (S#6, S#7), can't connect at home vs
  office = **firewall private-vs-public** (S#24), server not visible in scan
  (S#1, S#21), version-mismatch blocks connect (S#2, S#31, S#14), Wi-Fi vs LAN
  host address (C#1). Play review: input lag even on hotspot.
- **Our move:** (a) server **adds its own firewall rule** on first run (covers
  the #1 root cause); (b) hardened keepalive + instant resume (kill the 2 s
  drop); (c) a **"Can't connect?" diagnostic** screen that checks network match,
  firewall, and server reachability and tells the user exactly what's wrong;
  (d) version handshake that warns *and links the matching build* instead of
  dead-ending; (e) keep USB as the zero-config low-latency path.

### 3. Virtual-gamepad correctness  ⭐ trust-breaking bugs
- ABXY duplicated/swapped (S#39), buttons get **stuck on** (S#34), stick also
  fires its click (S#29), unresponsive on GeForce Now until server restart
  (S#44), phone registers as **controller 2/3 not P1** (S#41), left stick dead in
  Roblox (S#18), camera/move dead (S#16), GTA5 enter-vehicle flips to the wrong
  layout (S#23).
- **Our move:** verify every control against `hardwaretester.com/gamepad`;
  **release-all-buttons on disconnect/app-background** (no stuck keys); force
  single player-index P1; document GFN/streaming setup; correct per-action
  layout switching.

### 4. Rumble → phone vibration  ⭐ clean differentiator
- Wanted repeatedly; they call it impossible (S#19, S#35 closed).
- **Our move:** read the game's rumble from the virtual pad (vgamepad supports a
  rumble/notification callback) and **vibrate the phone** with matching
  intensity. A feature they explicitly gave up on.

### 5. Driver experience (ViGEm / "VIGME")
- "Driver not found" (S#17, S#20, S#36, S#40), naming confusion ("VIGME"?
  S#20), Linux driver (S#28), install says done but app says not (S#36).
- **Our move:** detect driver status, **one-click guided install / bundle it**,
  plain-language naming, and a clear "Xbox features need this driver" banner with
  a fix button.

### 6. Trust & antivirus false positives  ⭐ reputation killer
- Flagged as Trojan/malware by several engines (S#12, S#22), scares users off.
- **Our move:** ship an **unobfuscated, signed** build; publish a SHA + VirusTotal
  link; document why it needs input/network permissions. Transparency as a
  feature.

### 7. Mouse / trackpad quality
- Plain cursor won't move / selects a range instead (S#33), want full
  physical-mouse replacement with gestures (S#10).
- **Our move:** precise trackpad — single-finger move, tap = click, two-finger
  scroll, drag-lock, right/middle click, adjustable accel; make it good enough to
  replace a real mouse.

### 8. Keyboard input
- No built-in keyboard (Play Store review).
- **Our move:** an on-screen keyboard / text-send layout + bindable key buttons,
  using SendInput on the server (we already use it for the mouse).

### 9. Cross-platform server
- Mac (C#3), Linux (S#43, S#28).
- **Our move:** package the Python server for **Linux & macOS** (mouse/keyboard
  there; gamepad where the OS allows). A multi-year unmet ask we can answer.

### 10. Game-streaming use-cases
- Parsec (S#27), GeForce Now (S#44), Moonlight + use phone as the controller over
  the network (S#46).
- **Our move:** verify the virtual pad passes cleanly through Moonlight / Parsec /
  GFN; add a short "streaming setup" guide; treat streamers as a target user.

### 11. More prebuilt game profiles (validates our direction)
- Steering wheel for cars (S#25 — we built it!), GTA/FiveM (S#23, S#30, S#33, S#38),
  RDR (S#29).
- **Our move:** keep expanding the **Games tab** — GTA V, NFS, RDR2, flight, etc.,
  each tuned; analog pedals + tilt steering options for racers.

### 12. Stability
- Phone freezes/restarts if server stopped before disconnect (S#9).
- **Our move:** graceful server-gone handling on the phone (we already auto-detect
  disconnect and reconnect — verify no freeze path).

### 13. Community
- People want to contribute (S#11). **Our move:** keep it tidy + documented so
  contribution is easy; consider open layouts/profiles.

> Triaged as noise (spam/no-content): S#45, S#42, S#15, S#26, S#32, S#40-images.

---

## Release roadmap — solve one by one

Tick items as we ship + test. Each release should be installable on the phone
and verified on a real game before moving on.

### R1 — "It just connects, and it's safe to install"  (reliability + trust)
- [x] Server auto-creates its Windows firewall rule (TCP 8765 + UDP 8766) on
      launch; prints plain-language guidance if it can't (not admin). `main.py`
- [x] Release-all-buttons on disconnect / app background — `gamepad.reset()` on
      connect + disconnect (server) and a `reset` msg when the app is
      backgrounded (client). No more stuck throttle/keys. `gamepad.py`,`main.py`,`websocket_service.dart`
- [x] "Can't connect?" diagnostic — dialog shows the discovered PC IP, the IPs
      it's trying, the server version, firewall/Wi-Fi tips, and a **Rescan**
      button. `controller_screen.dart`,`websocket_service.dart`
- [~] Version handshake — server now broadcasts + sends its version and the app
      displays it. TODO: actively warn / link the matching build on mismatch.
- [x] Clean shutdown — Ctrl+C no longer prints "Task was destroyed but it is
      pending"; background tasks are cancelled + awaited. `main.py`
- [x] Faster launch — `run_server.bat` only pip-installs when deps are missing.
- [x] Wider discovery — UDP announce now also hits the subnet-directed broadcast
      (e.g. `10.107.204.255`) for networks that drop `255.255.255.255`. `main.py`
- [ ] Hardened keepalive + instant resume (we have ping/pong + auto-reconnect;
      revisit only if real-world drops persist — many are Windows hotspot churn).
- [ ] Signed build + published SHA / VirusTotal + permissions explainer.

### R2 — "The controller is correct and feels alive"  (correctness + rumble)
- [ ] Audit all buttons/sticks/triggers vs hardwaretester; fix any mapping drift.
- [ ] Force player-index P1; document multi-device order.
- [ ] **Rumble → phone vibration** with intensity.
- [ ] Verify GeForce Now / Moonlight / Parsec passthrough.

### R3 — "Make it yours"  (custom layout editor — their most-wanted)  ✅ shipped
- [x] In-app WYSIWYG editor: add / move (drag) / resize (slider) / delete /
      rename controls. `layout_editor.dart`
- [x] Bind any button to **gamepad / keyboard key / mouse** — server now injects
      key down/up + hold-able mouse. `gamepad.py`,`main.py`,`custom_controls.dart`
- [x] Control kinds: button, stick, trigger, D-pad, **mouse pad** (drag-to-move).
- [x] Custom layouts saved + listed in the Games tab; create from **Blank /
      Gamepad / Keyboard+Mouse** templates. `custom_layout.dart`,`controller_screen.dart`
- [x] Stuck-input safety extended to keyboard/mouse (release-all on
      reset/disconnect). `gamepad.py`
- [x] Per-control **transparency/opacity** in the editor (Free-Fire style).
- [x] **Customize** the built-in **Standard** preset → opens an editable copy.
- [x] Slider steering: **center-vibrate** for muscle memory + mode-aware size
      label ('Slider width'). `forza_controls.dart`,`controller_screen.dart`
- [x] Settings sliders: bigger thumb/track + spacing so scrolling no longer
      nudges sensitivity by mistake. `controller_screen.dart`
- [x] Customize **Forza** preset — added **wheel + pedal** as editor control
      types; both Standard & Forza cards now have a Customize button.
- [x] Editor visual polish — removed bounding-box clutter, selected control gets
      a cyan glow, gradient top-bar header, scrollable Add sheet.
- [x] Slider steering center = stronger `mediumImpact` buzz (muscle memory).
- [ ] Multiple presets per game (Free-Fire style Preset 1 / Preset 2).
- [ ] Export / import / share a layout (clipboard or file).

### R4 — "Replace your mouse & keyboard"  (desktop input)
- [x] Precision trackpad — v1.3.0 dedicated Mouse & Keys screen (portrait +
      landscape): tap, double-tap-hold drag, two-finger scroll/zoom/right-tap,
      scroll strip, hold-able L/M/R buttons.
- [x] On-screen keyboard — v1.3.0: system-keyboard piping (backspace/Enter
      included) + scalable floating mini-keyboard. Bindable key buttons still open.

### R5 — "A layout for every game"  (content + streaming)
- [ ] More game profiles (GTA V, NFS, RDR2, flight, …).
- [x] Forza steering: **4 modes** — Wheel, **Slider** (center knob), **Tilt**
      (accelerometer, with Recenter), and L/R Pads; switch in Settings + a
      first-run chooser. `forza_controls.dart`
- [ ] Racing extras: analog pedals (slide for partial throttle), wheel polish,
      tilt axis auto-calibration.
- [ ] Streaming setup guide + tested presets.

### R6 — "Runs anywhere"  (platform + onboarding)
- [ ] Package server for Linux & macOS.
- [ ] Guided driver install / bundle ViGEm; clear status UI.
- [ ] First-run onboarding that gets a new user playing in <60 s.

---

## Moonshots / ideas to revisit
- Cloud-less code pairing (short code or QR) as an alternative to IP/scan.
- Gyro aiming (phone IMU → right stick) for shooters.
- Adaptive latency HUD + auto-tuning of batch interval.
- Community profile gallery (download layouts for your game).
- Per-control haptics already done; extend to layout-wide haptic themes.

## Sources
- Touch-Server issues — https://github.com/62Bytes/Touch-Server/issues
- Touch-Client issues — https://github.com/62Bytes/Touch-Client/issues
- Play Store listing — https://play.google.com/store/apps/details?id=com.S2bytes.touch
