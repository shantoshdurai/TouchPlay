"""
stream.py — Screen capture + WebSocket stream server (port 8767).

Captures the primary monitor, compresses each frame as JPEG, and pushes
binary frames to every connected phone client at ~24 fps.  Only runs the
capture loop while at least one client is connected so it uses no CPU when
the feature is turned off on the phone.
"""

import asyncio
import io

STREAM_PORT = 8767
_clients: set = set()


async def stream_handler(websocket):
    """Accept a new streaming client, keep the connection open until it closes."""
    _clients.add(websocket)
    try:
        # Just hold the connection — frames are pushed by capture_loop().
        await websocket.wait_closed()
    finally:
        _clients.discard(websocket)


class StreamSettings:
    target_w = 854
    target_h = 480
    quality  = 55
    fps      = 24

def set_high_quality(enabled: bool):
    if enabled:
        StreamSettings.target_w = 1280
        StreamSettings.target_h = 720
        StreamSettings.quality  = 80
        StreamSettings.fps      = 60
    else:
        StreamSettings.target_w = 854
        StreamSettings.target_h = 480
        StreamSettings.quality  = 55
        StreamSettings.fps      = 24

async def capture_loop():
    """Continuously capture the screen and push JPEG frames to all clients."""
    try:
        import mss
        from PIL import Image
    except ImportError:
        return   # mss/Pillow not installed — stream silently unavailable

    with mss.mss() as sct:
        monitor = sct.monitors[1]   # primary monitor
        while True:
            if not _clients:
                await asyncio.sleep(0.05)
                continue

            try:
                # ── Capture ───────────────────────────────────────────────────
                shot = sct.grab(monitor)
                img  = Image.frombytes("RGB", shot.size, shot.rgb)

                # ── Downscale to phone resolution ─────────────────────────────
                img  = img.resize((StreamSettings.target_w, StreamSettings.target_h), Image.BILINEAR)

                # ── JPEG compress to bytes ─────────────────────────────────────
                buf  = io.BytesIO()
                img.save(buf, format="JPEG", quality=StreamSettings.quality, optimize=False)
                frame = buf.getvalue()

                # ── Push to all connected clients ──────────────────────────────
                dead = set()
                for ws in list(_clients):
                    try:
                        await ws.send(frame)
                    except Exception:
                        dead.add(ws)
                _clients -= dead

            except Exception:
                pass

            await asyncio.sleep(1 / StreamSettings.fps)
