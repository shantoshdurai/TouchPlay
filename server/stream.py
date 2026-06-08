"""
stream.py — Screen capture + WebSocket stream server (port 8767).

Captures the primary monitor, compresses each frame as JPEG, and pushes
binary frames to every connected phone client at ~24 fps.  Only runs the
capture loop while at least one client is connected so it uses no CPU when
the feature is turned off on the phone.
"""

import asyncio
import io
import socket
import time

STREAM_PORT = 8767
_clients: set = set()


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
    target_w = 854
    target_h = 480
    quality  = 60
    fps      = 60   # always 60 — encode speed is the natural cap, not an artificial limit

def set_quality(level: str):
    if level == 'screen':
        # "2nd Screen" mode — high resolution for crisp text, low framerate so
        # bandwidth stays tiny over WiFi. A work desktop is near-static, so 15fps
        # is plenty and resolution (readability) matters far more than motion.
        StreamSettings.target_w = 1600
        StreamSettings.target_h = 900
        StreamSettings.quality  = 88
        StreamSettings.fps      = 15
    elif level == '720p':
        StreamSettings.target_w = 1280
        StreamSettings.target_h = 720
        StreamSettings.quality  = 78
        StreamSettings.fps      = 60
    elif level == '360p':
        StreamSettings.target_w = 640
        StreamSettings.target_h = 360
        StreamSettings.quality  = 50
        StreamSettings.fps      = 60
    else:  # '480p' default
        StreamSettings.target_w = 854
        StreamSettings.target_h = 480
        StreamSettings.quality  = 60
        StreamSettings.fps      = 60

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
        resized = cv2.resize(
            frame, (StreamSettings.target_w, StreamSettings.target_h),
            interpolation=cv2.INTER_LINEAR)
        ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))

        mx = int((pt.x / w) * StreamSettings.target_w)
        my = int((pt.y / h) * StreamSettings.target_h)
        if 0 <= mx < StreamSettings.target_w and 0 <= my < StreamSettings.target_h:
            cv2.circle(resized, (mx, my), 5, (255, 255, 255), 2)
            cv2.circle(resized, (mx, my), 6, (0, 0, 0), 1)

        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), StreamSettings.quality]
        _, encoded = cv2.imencode('.jpg', resized, encode_param)
        return encoded.tobytes()

    try:
        camera = dxcam.create(output_idx=0, output_color="BGR")
        camera.start(target_fps=60, video_mode=True)

        while True:
            if not _clients:
                await asyncio.sleep(0.05)
                continue

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
        if 'camera' in locals():
            camera.stop()
