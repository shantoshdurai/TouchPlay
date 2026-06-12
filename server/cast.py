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

    def window_size(w: int, h: int) -> tuple[int, int]:
        """Window matching the frame's aspect ratio, capped so a portrait
        phone frame never opens taller than the desktop."""
        scale = min(1500 / w, 850 / h, 1.0)
        return max(2, int(w * scale)), max(2, int(h * scale))

    def pump():
        import cv2
        shown: dict[str, tuple[int, int]] = {}   # key → last frame (w, h)
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
                        shown.pop(key, None)
                    with _windows_lock:
                        _windows.pop(key, None)
                    continue
                with box.lock:
                    frame = box.frame
                    box.frame = None
                if frame is not None:
                    h, w = frame.shape[:2]
                    if key not in shown:
                        cv2.namedWindow(box.title, cv2.WINDOW_NORMAL)
                        cv2.resizeWindow(box.title, *window_size(w, h))
                        shown[key] = (w, h)
                    elif shown[key] != (w, h):
                        # Phone rotated mid-cast — re-shape the window so the
                        # picture keeps the phone's real aspect ratio.
                        cv2.resizeWindow(box.title, *window_size(w, h))
                        shown[key] = (w, h)
                    cv2.imshow(box.title, frame)
            cv2.waitKey(30)          # pumps the HighGUI event loop too

    threading.Thread(target=pump, name="touchplay-display", daemon=True).start()


# ── Virtual camera sink ───────────────────────────────────────────────────────

class _VirtualCamSink:
    """Feeds frames into the OBS virtual camera; resolution follows the stream."""

    def __init__(self):
        self.cam = None
        self.size = None
        self.device = None   # set once the camera is actually open

    def push(self, frame_bgr) -> bool:
        import pyvirtualcam
        import cv2
        h, w = frame_bgr.shape[:2]
        if self.cam is None or self.size != (w, h):
            self.close()
            self.cam = pyvirtualcam.Camera(width=w, height=h, fps=30,
                                           print_fps=False)
            self.size = (w, h)
            self.device = self.cam.device
            _log(f"[green]●[/] Virtual camera live: [bold]{self.cam.device}[/] "
                 f"{w}×{h} — pick it in Discord/Zoom/OBS")
        # No sleep_until_next_frame() here: the phone paces the stream, and
        # sleeping in the executor just throttled the pipeline to <20 fps.
        self.cam.send(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))
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
    # ASCII only: HighGUI window titles go through the ANSI API on Windows,
    # so an em-dash renders as mojibake ("â€~").
    title = ("TouchPlay - Phone Camera" if mode == "camera"
             else "TouchPlay - Projector")

    async def send_status(sink: str, device: str | None = None):
        """Tell the phone what the frames actually land in (webcam vs window),
        so its UI can stop claiming webcam mode when the driver is missing."""
        try:
            await websocket.send(json.dumps(
                {"type": "cast_status", "sink": sink, "device": device}))
        except Exception:
            pass

    # Handshake: lets the phone distinguish "new server, ready" from a dead
    # port (old servers simply never send this — the phone tolerates that).
    try:
        await websocket.send(json.dumps({"type": "cast_ready", "mode": mode}))
    except Exception:
        pass

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
        await send_status("window")

    _log(f"[cyan]▣[/] {phone} started "
         f"{'Virtual Cam' if mode == 'camera' else 'Projector'}")

    loop = asyncio.get_running_loop()

    def decode(buf: bytes):
        return cv2.imdecode(np.frombuffer(buf, np.uint8), cv2.IMREAD_COLOR)

    vcam_announced = False
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
                    if not vcam_announced and vcam.device:
                        vcam_announced = True
                        await send_status("webcam", vcam.device)
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
                    await send_status("window")
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
