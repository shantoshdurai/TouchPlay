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

                h, w, _ = frame.shape

                # ── Downscale & Cursor ─────────────────────────────────────────
                resized = cv2.resize(frame, (StreamSettings.target_w, StreamSettings.target_h), interpolation=cv2.INTER_LINEAR)
                ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
                
                mx = int((pt.x / w) * StreamSettings.target_w)
                my = int((pt.y / h) * StreamSettings.target_h)
                
                if 0 <= mx < StreamSettings.target_w and 0 <= my < StreamSettings.target_h:
                    cv2.circle(resized, (mx, my), 5, (255, 255, 255), 2)
                    cv2.circle(resized, (mx, my), 6, (0, 0, 0), 1)

                # ── JPEG compress ─────────────────────────────────────────────
                encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), StreamSettings.quality]
                _, encoded = cv2.imencode('.jpg', resized, encode_param)
                frame_bytes = encoded.tobytes()

                # ── Push to all connected clients ──────────────────────────────
                dead = set()
                max_send_time = 0
                import time
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
