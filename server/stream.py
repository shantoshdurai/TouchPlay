"""
stream.py — Screen capture + WebSocket stream server (port 8767).

Captures the primary monitor, compresses each frame as JPEG, and pushes
binary frames to every connected phone client at ~24 fps.  Only runs the
capture loop while at least one client is connected so it uses no CPU when
the feature is turned off on the phone.
"""

import asyncio
import io
import os
import socket
import subprocess
import sys
import time
import urllib.request
import zipfile

STREAM_PORT = 8767
_clients: set = set()

# Optional UI log hook — set by main.py.
_log = lambda msg: None

def set_logger(fn) -> None:
    global _log
    _log = fn


def _set_nodelay(websocket) -> None:
    """Disable Nagle algorithm on an accepted WebSocket connection.

    Without this, TCP can batch small frames together and add up to 40 ms of
    artificial delay before flushing — catastrophic for real-time video.
    """
    try:
        sock = websocket.transport.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception:
        pass


async def stream_handler(websocket):
    """Accept a new streaming client, keep the connection open until it closes."""
    _set_nodelay(websocket)
    _clients.add(websocket)
    try:
        # Just hold the connection — frames are pushed by capture_loop().
        await websocket.wait_closed()
    finally:
        _clients.discard(websocket)


class StreamSettings:
    # Only the HEIGHT is fixed per preset — width follows the real monitor
    # aspect ratio so the picture is never stretched/squashed on the phone.
    target_h = 480
    quality  = 65
    fps      = 60
    # "2nd Screen" preset: capture the EXTENDED display (monitor 2) when the
    # PC has one, so the phone shows the desk's second screen, not a mirror.
    # (A true driver-level virtual display is a separate future project.)
    second_screen = False

# preset → (height, jpeg quality, fps cap)
_PRESETS = {
    # "2nd Screen" mode — high resolution for crisp text at 30fps so the
    # extended desktop still feels fluid (like spacedesk & co).
    'screen': (900,  85, 30),
    '1080p':  (1080, 80, 30),
    '720p':   (720,  78, 60),
    '480p':   (480,  65, 60),
    '360p':   (360,  52, 60),
}

def set_quality(level: str):
    global _vd_attempted
    h, q, fps = _PRESETS.get(level, _PRESETS['480p'])
    StreamSettings.target_h = h
    StreamSettings.quality  = q
    StreamSettings.fps      = fps
    StreamSettings.second_screen = (level == 'screen')
    if level == 'screen':
        _vd_attempted = False   # fresh selection → one fresh enable attempt


# ── Virtual display ("2nd Screen" extend mode) ────────────────────────────────
# Windows can't grow the desktop without an Indirect Display Driver, so we use
# Amyuni's freeware usbmmidd_v2 (the same driver family second-screen apps
# ship). Downloaded once next to the server, installed, then plugged/unplugged
# as the phone enters/leaves the 2nd-Screen preset. If anything here fails we
# quietly fall back to mirroring the primary screen.

_VD_URL = "https://www.amyuni.com/downloads/usbmmidd_v2.zip"
_vd_on = False
_vd_attempted = False


def _vd_base() -> str:
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def _vd_tool():
    for sub in ("usbmmidd_v2", os.path.join("usbmmidd_v2", "usbmmidd_v2")):
        exe = os.path.join(_vd_base(), sub, "deviceinstaller64.exe")
        if os.path.exists(exe):
            return exe
    return None


def _vd_download():
    try:
        zpath = os.path.join(_vd_base(), "usbmmidd_v2.zip")
        _log("[cyan]Downloading virtual display driver (one-time, ~1 MB)…[/]")
        urllib.request.urlretrieve(_VD_URL, zpath)
        with zipfile.ZipFile(zpath) as z:
            z.extractall(_vd_base())
        os.remove(zpath)
        return _vd_tool()
    except Exception as e:
        _log(f"[yellow]Virtual display driver download failed ({e}) — "
             "2nd Screen will mirror instead.[/]")
        return None


def _vd_run(tool, *args) -> bool:
    try:
        r = subprocess.run(
            [tool, *args], cwd=os.path.dirname(tool), capture_output=True,
            timeout=90, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return r.returncode == 0
    except Exception:
        return False


def _display_count() -> int:
    try:
        import ctypes
        return ctypes.windll.user32.GetSystemMetrics(80)   # SM_CMONITORS
    except Exception:
        return 1


def enable_virtual_display() -> bool:
    """Plug in the extended display. Blocking — run in an executor."""
    global _vd_on, _vd_attempted
    if _vd_on:
        return True
    _vd_attempted = True
    tool = _vd_tool() or _vd_download()
    if tool is None:
        return False
    # Install creates a NEW device node every time, so only do it on the very
    # first run (marker file) — repeat installs pile up broken duplicates.
    marker = os.path.join(os.path.dirname(tool), ".installed")
    if not os.path.exists(marker):
        if _vd_run(tool, "install", "usbmmIdd.inf", "usbmmidd"):
            open(marker, "w").close()
    before = _display_count()
    if not _vd_run(tool, "enableidd", "1"):
        _log("[yellow]Couldn't plug in the virtual display — "
             "2nd Screen will mirror instead.[/]")
        return False
    time.sleep(3.0)   # let Windows bring the new display up
    if _display_count() <= before:
        # enableidd reported success but no display appeared — this driver is
        # Windows-10-only and recent Windows 11 builds reject it silently.
        _vd_run(tool, "enableidd", "0")
        _log("[yellow]Your Windows build blocks this virtual display driver "
             "(it is Windows-10-only). 2nd Screen will MIRROR for now. For a "
             "true extended display, install 'Virtual Display Driver' from "
             "github.com/VirtualDrivers once — TouchPlay will then use it "
             "automatically.[/]")
        return False
    _vd_on = True
    # Make sure Windows is in EXTEND mode, not duplicate.
    try:
        subprocess.run(["DisplaySwitch.exe", "/extend"], timeout=15,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except Exception:
        pass
    _log("[green]●[/] Virtual display plugged in — the phone now EXTENDS "
         "your desktop (drag windows to the right)")
    return True


def disable_virtual_display() -> None:
    global _vd_on
    if not _vd_on:
        return
    tool = _vd_tool()
    if tool and _vd_run(tool, "enableidd", "0"):
        _vd_on = False
        _log("[dim]Virtual display unplugged[/]")

# Keep old name for any callers still using it.
def set_high_quality(enabled: bool):
    set_quality('720p' if enabled else '480p')

async def capture_loop():
    """Continuously capture the screen and push JPEG frames to all clients."""
    global _clients
    try:
        import dxcam
        import cv2
        import ctypes
        import importlib
        import numpy as np
    except ImportError:
        return   # dependencies not installed — stream silently unavailable

    class POINT(ctypes.Structure):
        _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]
    pt = POINT()

    loop = asyncio.get_running_loop()

    def _process(frame):
        """Resize → draw cursor → JPEG encode. Runs in a worker thread.

        OpenCV releases the GIL during resize/encode, so doing this off the
        event loop lets control input (button/stick JSON on the shared loop)
        be handled WHILE a frame encodes instead of stalling ~8ms behind it.
        """
        h, w, _ = frame.shape
        # Keep the monitor's aspect ratio: fix the preset height, derive the
        # width from the source frame (rounded to even for the JPEG encoder).
        th = min(StreamSettings.target_h, h)
        th -= th % 2
        tw = int(round(th * w / h / 2)) * 2
        # INTER_AREA is visibly sharper than INTER_LINEAR when downscaling.
        resized = cv2.resize(frame, (tw, th), interpolation=cv2.INTER_AREA)
        ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))

        mx = int((pt.x / w) * tw)
        my = int((pt.y / h) * th)
        if 0 <= mx < tw and 0 <= my < th:
            cv2.circle(resized, (mx, my), 5, (255, 255, 255), 2)
            cv2.circle(resized, (mx, my), 6, (0, 0, 0), 1)

        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), StreamSettings.quality]
        _, encoded = cv2.imencode('.jpg', resized, encode_param)
        return encoded.tobytes()

    # One dxcam instance per monitor, started lazily; False = known-missing.
    cameras: dict[int, object] = {}
    started: set[int] = set()

    def acquire(idx: int):
        cam = cameras.get(idx)
        if cam is False:
            return None
        if cam is None:
            try:
                cam = dxcam.create(output_idx=idx, output_color="BGR")
            except Exception:
                cam = None
            if cam is None:
                cameras[idx] = False      # this monitor doesn't exist
                return None
            cameras[idx] = cam
        if idx not in started:
            try:
                cam.start(target_fps=60, video_mode=True)
                started.add(idx)
            except Exception:
                return None
        return cam

    try:
        current_idx = 0
        camera = acquire(0)
        if camera is None:
            return

        while True:
            if not _clients:
                # Mirror screen closed — fall back to the primary monitor and
                # unplug the virtual display so the desktop returns to normal.
                if _vd_on:
                    if current_idx == 1:
                        try:
                            camera.stop()
                            started.discard(1)
                        except Exception:
                            pass
                        nxt = acquire(0)
                        if nxt is not None:
                            camera = nxt
                            current_idx = 0
                    await loop.run_in_executor(None, disable_virtual_display)
                await asyncio.sleep(0.05)
                continue

            # "2nd Screen" wants the extended display. If the PC has only one
            # monitor, plug in a VIRTUAL one (Amyuni IDD) so the phone truly
            # extends the desktop instead of duplicating it.
            want = 1 if StreamSettings.second_screen else 0
            if want == 1 and current_idx != 1 and cameras.get(1) is False \
                    and not _vd_attempted:
                if await loop.run_in_executor(None, enable_virtual_display):
                    # The new monitor appeared after dxcam enumerated outputs —
                    # reload the module so it can see it, then reacquire.
                    for i in list(started):
                        try:
                            cameras[i].stop()
                        except Exception:
                            pass
                    cameras.clear()
                    started.clear()
                    importlib.reload(dxcam)
                    camera = acquire(0)
                    current_idx = 0
            if want != current_idx:
                nxt = acquire(want)
                if nxt is not None:
                    try:
                        camera.stop()
                        started.discard(current_idx)
                    except Exception:
                        pass
                    camera = nxt
                    current_idx = want
                elif want == 0:
                    # primary vanished?! — keep whatever still works
                    pass

            # Left 2nd-Screen mode → unplug the virtual display again.
            if _vd_on and not StreamSettings.second_screen \
                    and current_idx == 0:
                await loop.run_in_executor(None, disable_virtual_display)

            try:
                # ── Capture ───────────────────────────────────────────────────
                frame = camera.get_latest_frame()
                if frame is None:
                    await asyncio.sleep(0.005)
                    continue

                # ── Resize + cursor + JPEG encode (off the event loop) ─────────
                frame_bytes = await loop.run_in_executor(None, _process, frame)

                # ── Push to all connected clients ──────────────────────────────
                dead = set()
                max_send_time = 0
                for ws in list(_clients):
                    try:
                        t0 = time.time()
                        await asyncio.wait_for(ws.send(frame_bytes), timeout=1.0)
                        send_duration = time.time() - t0
                        max_send_time = max(max_send_time, send_duration)
                    except Exception:
                        dead.add(ws)
                _clients -= dead

            except Exception as e:
                print("CAPTURE ERROR:", e)

            # ── Smart Bufferbloat Throttling ──────────────────────────────
            base_sleep = 1 / StreamSettings.fps
            if max_send_time > 0.02:
                drain_sleep = min(max_send_time * 2, 0.25)
                await asyncio.sleep(base_sleep + drain_sleep)
            else:
                await asyncio.sleep(base_sleep)
    except Exception as e:
        print("Fatal stream error:", e)
    finally:
        for idx in list(started):
            try:
                cameras[idx].stop()
            except Exception:
                pass
