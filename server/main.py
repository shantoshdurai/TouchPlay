import asyncio
import json
import logging
import socket
import websockets
from gamepad import GamepadController, mouse_move, mouse_click
from qr_gen import generate_qr, get_best_ip

PORT      = 8765
UDP_PORT  = 8766          # discovery broadcast port
BATCH_MS  = 0.008         # 8 ms gamepad flush

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

gamepad = GamepadController()
_dirty  = False


# ── UDP auto-discovery broadcast ─────────────────────────────────────────────

async def udp_broadcast(ip: str):
    """Send UDP broadcast every 2 s so the phone app finds the server instantly."""
    msg = json.dumps({"type": "server_hello", "ip": ip, "port": PORT}).encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setblocking(False)
    while True:
        try:
            sock.sendto(msg, ("<broadcast>", UDP_PORT))
        except Exception:
            pass
        await asyncio.sleep(2)


# ── Gamepad flush loop ────────────────────────────────────────────────────────

async def flush_loop():
    global _dirty
    while True:
        await asyncio.sleep(BATCH_MS)
        if _dirty:
            gamepad.update()
            _dirty = False


# ── Message handler ───────────────────────────────────────────────────────────

def handle_message(data: dict) -> str | None:
    global _dirty
    t = data.get("type")

    if t == "button_press":
        gamepad.press_button(data["button"]); _dirty = True
    elif t == "button_release":
        gamepad.release_button(data["button"]); _dirty = True
    elif t == "left_stick":
        gamepad.set_left_stick(data["x"], data["y"]); _dirty = True
    elif t == "right_stick":
        gamepad.set_right_stick(data["x"], data["y"]); _dirty = True
    elif t == "left_trigger":
        gamepad.set_left_trigger(data["value"]); _dirty = True
    elif t == "right_trigger":
        gamepad.set_right_trigger(data["value"]); _dirty = True
    elif t == "mouse_move":
        mouse_move(int(data.get("dx", 0)), int(data.get("dy", 0)))
    elif t == "mouse_click":
        mouse_click(data.get("button", "left"))
    elif t == "ping":
        return json.dumps({"type": "pong"})
    return None


# ── WebSocket handler ─────────────────────────────────────────────────────────

async def handler(websocket):
    client_ip = websocket.remote_address[0]
    log.info(f"Phone connected: {client_ip}")
    try:
        async for raw in websocket:
            try:
                data     = json.loads(raw)
                response = handle_message(data)
                if response:
                    await websocket.send(response)
            except (json.JSONDecodeError, KeyError) as e:
                log.warning(f"Bad message: {e}")
    except (websockets.exceptions.ConnectionClosedError, asyncio.CancelledError):
        pass
    except Exception as e:
        log.error(f"Error: {e}")
    finally:
        log.info(f"Phone disconnected: {client_ip}")


# ── Entry point ───────────────────────────────────────────────────────────────

async def main():
    ip = generate_qr(PORT)
    log.info(f"Server listening on {ip}:{PORT}")
    log.info("Broadcasting presence via UDP — phone will auto-connect!")

    async with websockets.serve(handler, "0.0.0.0", PORT):
        await asyncio.gather(
            asyncio.Future(),
            flush_loop(),
            udp_broadcast(ip),
        )


if __name__ == "__main__":
    import sys
    sys.tracebacklimit = 0   # no ugly tracebacks on Ctrl+C
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        print("\n[OK] Server stopped cleanly.")
    except Exception as e:
        print(f"\n[ERROR] {e}")
