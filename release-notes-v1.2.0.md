# TouchPlay v1.2.0 — Everything unlocked

Every "Coming Soon" tile in the menu is now a real, working feature. This is the biggest update yet — update **both** the app and the PC server.

## New features

### 📁 File Transfer
Send files both ways between phone and PC.
- Phone → PC: pick any file, it lands in `Downloads\TouchPlay` on the PC
- PC → phone: drop files in `Downloads\TouchPlay`, pull them from the app into your phone's Downloads

### 📷 Virtual Cam
Your phone camera becomes a PC webcam.
- Pick **OBS Virtual Camera** in Discord / Zoom / Meet / OBS
- No virtual-camera driver? A live preview window opens instead (install OBS Studio once to get the driver)
- Flip between front/back camera while live

### 📽️ Projector
Mirror your phone screen into a window on the PC. Keeps casting while you switch apps on the phone (runs as a proper Android screen-cast service).

### 🖱️ Trackpad upgrades (Mouse & Keys)
- **Two-finger swipe** → scroll (natural scrolling)
- **Pinch** → zoom (Ctrl+wheel)
- **Two-finger tap** → right-click

## Also in this release
- Search in the main menu — jump straight to any feature
- Controller Settings now reachable from the main menu (sticks, mouse, vibration, stream quality)
- Privacy Policy built into the app — TL;DR: everything stays on your own network, zero tracking
- Feedback + Community now open GitHub Issues / Discussions
- "Go to Release" / "Check for Update" buttons actually open the Releases page
- PC server: new file + cast ports (8768/8769) auto-added to the firewall; setup script updated
- New `build-exe.bat` for building a standalone server EXE (no Python needed)

## Update steps
1. Install the new APK below
2. Replace your PC server folder with `TouchPlay-PC-Server-v1.2.0.zip` and run `TouchPlay-Setup.bat` once (adds the two new firewall rules)
