"""
cast.py — Phone → PC casting receiver (WebSocket port 8769).

Handles two phone features over one port:
  • Virtual Cam — the phone camera becomes a PC webcam. Frames are fed into
    a pyvirtualcam output (requires the OBS Virtual Camera driver). If the
    driver / package is missing we fall back to a preview window so the
    feature still visibly works, with a log hint on how to enable webcam mode.
  • Projector — the phone screen is mirrored into a resizable PC window.

Protocol: the phone connects and first sends one JSON text message
  {"type": "hello", "mode": "camera" | "projector", "name": "<phone name>"}
then pushes binary JPEG frames. Server decodes and displays/forwards.

All OpenCV windows are driven by ONE dedicated display thread (HighGUI is
not thread-safe across threads), fed via a latest-frame-wins mailbox.
"""

import asyncio
import json
import socket
import threading

CAST_PORT = 8769

# Optional UI log hook — set by main.py.
_log = lambda msg: None

def set_logger(fn) -> None:
    global _log
    _log = fn


# ── Display pump (single thread owns all cv2 windows) ─────────────────────────

class _Mailbox:
    """Latest-frame-wins slot. Decoding can't backlog the network reader."""
    def __init__(self, title: str):
        self.title = title
        self.frame = None          # np.ndarray BGR, ready to imshow
        self.lock = threading.Lock()
        self.open = True


_windows: dict[str, _Mailbox] = {}
_windows_lock = threading.Lock()
_pump_started = False


def _ensure_pump():
    global _pump_started
    if _pump_started:
        return
    _pump_started = True

    def pump():
        import cv2
        shown: set[str] = set()
        while True:
            with _windows_lock:
                boxes = dict(_windows)
            for key, box in boxes.items():
                if not box.open:
                    if key in shown:
                        try:
                            cv2.destroyWindow(box.title)
                        except Exception:
                            pass
                        shown.discard(key)
                    with _windows_lock:
                        _windows.pop(key, None)
                    continue
                with box.lock:
                    frame = box.frame
                    box.frame = None
                if frame is not None:
                    if key not in shown:
                        cv2.namedWindow(box.title, cv2.WINDOW_NORMAL)
                        h, w = frame.shape[:2]
                        cv2.resizeWindow(box.title, w, h)
                        shown.add(key)
                    cv2.imshow(box.title, frame)
            cv2.waitKey(30)          # pumps the HighGUI event loop too

    threading.Thread(target=pump, name="touchplay-display", daemon=True).start()


# ── Virtual camera sink ───────────────────────────────────────────────────────

class _VirtualCamSink:
    """Feeds frames into the OBS virtual camera; resolution follows the stream."""

    def __init__(self):
        self.cam = None
        self.size = None

    def push(self, frame_bgr) -> bool:
        import pyvirtualcam
        import cv2
        h, w = frame_bgr.shape[:2]
        if self.cam is None or self.size != (w, h):
            self.close()
            self.cam = pyvirtualcam.Camera(width=w, height=h, fps=20,
                                           print_fps=False)
            self.size = (w, h)
            _log(f"[green]●[/] Virtual camera live: [bold]{self.cam.device}[/] "
                 f"{w}×{h} — pick it in Discord/Zoom/OBS")
        self.cam.send(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))
        self.cam.sleep_until_next_frame()
        return True

    def close(self):
        if self.cam is not None:
            try:
                self.cam.close()
            except Exception:
                pass
            self.cam = None
            self.size = None


# ── WebSocket handler ─────────────────────────────────────────────────────────

def _set_nodelay(websocket) -> None:
    try:
        sock = websocket.transport.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception:
        pass


async def cast_handler(websocket):
    try:
        import cv2
        import numpy as np
    except ImportError:
        await websocket.close()
        return

    _set_nodelay(websocket)

    # First message must be the JSON hello declaring the mode.
    try:
        raw = await asyncio.wait_for(websocket.recv(), timeout=5)
        hello = json.loads(raw)
        mode = hello.get("mode")
        phone = hello.get("name") or "Phone"
        assert mode in ("camera", "projector")
    except Exception:
        await websocket.close()
        return

    key = f"{mode}-{websocket.remote_address[0]}"
    title = ("TouchPlay — Phone Camera" if mode == "camera"
             else "TouchPlay — Projector")

    vcam = None
    use_window = True
    if mode == "camera":
        try:
            import pyvirtualcam  # noqa: F401 — probe only
            vcam = _VirtualCamSink()
            use_window = False
        except ImportError:
            _log("[yellow]Virtual camera driver not found — showing preview "
                 "window instead. Install OBS Studio (it ships the driver) "
                 "and `pip install pyvirtualcam` for true webcam mode.[/]")

    box = None
    if use_window:
        _ensure_pump()
        box = _Mailbox(title)
        with _windows_lock:
            _windows[key] = box

    _log(f"[cyan]▣[/] {phone} started "
         f"{'Virtual Cam' if mode == 'camera' else 'Projector'}")

    loop = asyncio.get_running_loop()

    def decode(buf: bytes):
        return cv2.imdecode(np.frombuffer(buf, np.uint8), cv2.IMREAD_COLOR)

    try:
        async for msg in websocket:
            if not isinstance(msg, (bytes, bytearray)):
                continue
            frame = await loop.run_in_executor(None, decode, bytes(msg))
            if frame is None:
                continue
            if vcam is not None:
                try:
                    await loop.run_in_executor(None, vcam.push, frame)
                except Exception as e:
                    # Driver missing/locked at runtime — fall back to a window.
                    _log(f"[yellow]Virtual cam unavailable ({e}) — "
                         "showing preview window instead.[/]")
                    vcam.close()
                    vcam = None
                    _ensure_pump()
                    box = _Mailbox(title)
                    with _windows_lock:
                        _windows[key] = box
            if box is not None:
                with box.lock:
                    box.frame = frame
    except Exception:
        pass
    finally:
        if vcam is not None:
            vcam.close()
        if box is not None:
            box.open = False
        _log(f"[dim]{phone} stopped "
             f"{'Virtual Cam' if mode == 'camera' else 'Projector'}[/]")
