"""
usb_link.py — USB auto-link (ADB) background task. (Named usb_link, not
usb, to avoid shadowing the PyPI `usb` package, which breaks PyInstaller.)

If a phone is plugged in over USB with debugging enabled, forward the
TouchPlay ports through the cable (adb reverse) and launch the app on the
phone. Replaces the one-shot check the old TouchPlay-Server.bat did — this
loop keeps watching, so plugging the phone in AFTER the server starts works
too. Skips silently when adb isn't installed or no device is attached.
"""

import asyncio
import os
import shutil
import subprocess
import sys
from pathlib import Path

PORTS = [8765, 8767, 8768, 8769]
_FLAGS = 0x08000000  # CREATE_NO_WINDOW — never flash a console

# Optional UI log hook — set by main.py.
_log = lambda msg: None

def set_logger(fn) -> None:
    global _log
    _log = fn


def _find_adb() -> str | None:
    p = shutil.which("adb")
    if p:
        return p
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) /
        "Android" / "Sdk" / "platform-tools" / "adb.exe",
        # next to the exe / the controller folder (a bundled platform-tools)
        Path(sys.argv[0]).resolve().parent / "platform-tools" / "adb.exe",
        Path(__file__).resolve().parent.parent / "platform-tools" / "adb.exe",
    ]
    for c in candidates:
        try:
            if c.is_file():
                return str(c)
        except OSError:
            pass
    return None


def _run(adb: str, *args: str, timeout: int = 8):
    return subprocess.run([adb, *args], capture_output=True, text=True,
                          timeout=timeout, creationflags=_FLAGS)


def _devices(adb: str) -> list[str]:
    try:
        lines = _run(adb, "devices").stdout.strip().splitlines()[1:]
        return [ln.split()[0] for ln in lines
                if ln.strip() and ln.split()[-1] == "device"]
    except Exception:
        return []


def _link(adb: str, serial: str) -> bool:
    ok = True
    for port in PORTS:
        r = _run(adb, "-s", serial, "reverse", f"tcp:{port}", f"tcp:{port}")
        ok = ok and r.returncode == 0
    # Best-effort: bring the app up on the phone.
    _run(adb, "-s", serial, "shell", "monkey", "-p", "com.touchplay.app",
         "-c", "android.intent.category.LAUNCHER", "1")
    return ok


async def usb_autolink_loop() -> None:
    adb = _find_adb()
    if adb is None:
        return                      # no adb on this PC — feature just absent
    linked: set[str] = set()
    try:
        while True:
            try:
                devs = set(await asyncio.to_thread(_devices, adb))
                linked &= devs      # forget unplugged phones → relink on return
                for d in devs - linked:
                    if await asyncio.to_thread(_link, adb, d):
                        linked.add(d)
                        _log("[cyan]▮ USB phone linked — ports forwarded "
                             "through the cable (no Wi-Fi needed)[/]")
            except Exception:
                pass
            await asyncio.sleep(3)
    except asyncio.CancelledError:
        pass
