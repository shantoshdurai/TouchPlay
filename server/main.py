import asyncio
import json
import platform
import socket
import subprocess
import websockets
from gamepad import (
    GamepadController, mouse_move, mouse_click,
    mouse_down, mouse_up, key_down, key_up, release_all_inputs,
)
from qr_gen import generate_qr

VERSION   = "1.1.0"       # bumped to the version the app handshakes against
PORT      = 8765
UDP_PORT  = 8766          # discovery broadcast port
BATCH_MS  = 0.008         # 8 ms gamepad flush

gamepad = GamepadController()
_dirty  = False


# ── Windows Firewall auto-allow ──────────────────────────────────────────────
# The #1 reason people "can't connect" is that Windows blocks the inbound port
# on the Private/Public profile. We add the rule ourselves (needs admin once);
# if we can't, we print plain-language guidance instead of failing silently.

def ensure_firewall_rule() -> str | None:
    if platform.system() != "Windows":
        return None
    flags = 0x08000000  # CREATE_NO_WINDOW — no console flash
    ok = True
    for name, proto, port in [
        ("TouchPlay Server TCP", "TCP", PORT),
        ("TouchPlay Server UDP", "UDP", UDP_PORT),
    ]:
        try:
            chk = subprocess.run(
                ["netsh", "advfirewall", "firewall", "show", "rule", f"name={name}"],
                capture_output=True, text=True, creationflags=flags)
            if chk.returncode == 0 and "No rules match" not in chk.stdout:
                continue  # already allowed
            res = subprocess.run(
                ["netsh", "advfirewall", "firewall", "add", "rule",
                 f"name={name}", "dir=in", "action=allow",
                 f"protocol={proto}", f"localport={port}"],
                capture_output=True, text=True, creationflags=flags)
            if res.returncode != 0:
                ok = False
        except Exception:
            ok = False
    return "ok" if ok else "failed"


# ── UDP auto-discovery broadcast ─────────────────────────────────────────────

async def udp_broadcast(ip: str):
    """Announce the server every 2 s so the phone finds it automatically.
    We hit the global, limited and subnet-directed broadcast addresses because
    some networks (corporate / hotspot) silently drop 255.255.255.255."""
    msg = json.dumps({"type": "server_hello", "ip": ip, "port": PORT, "version": VERSION}).encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setblocking(False)
    parts = ip.split(".")
    targets = ["<broadcast>", "255.255.255.255"]
    if len(parts) == 4:
        targets.append(".".join(parts[:3] + ["255"]))   # e.g. 10.107.204.255
    try:
        while True:
            for t in targets:
                try:
                    sock.sendto(msg, (t, UDP_PORT))
                except Exception:
                    pass
            await asyncio.sleep(2)
    except asyncio.CancelledError:
        pass
    finally:
        sock.close()


# ── Gamepad flush loop ────────────────────────────────────────────────────────

async def flush_loop():
    global _dirty
    try:
        while True:
            await asyncio.sleep(BATCH_MS)
            if _dirty:
                gamepad.update()
                _dirty = False
    except asyncio.CancelledError:
        pass


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
    elif t == "mouse_down":
        mouse_down(data.get("button", "left"))
    elif t == "mouse_up":
        mouse_up(data.get("button", "left"))
    elif t == "key_down":
        key_down(data.get("key", ""))
    elif t == "key_up":
        key_up(data.get("key", ""))
    elif t == "reset":
        gamepad.reset()           # release everything (e.g. on app background)
        release_all_inputs()
    elif t == "ping":
        return json.dumps({"type": "pong"})
    return None


# ── WebSocket handler ─────────────────────────────────────────────────────────

async def handler(websocket):
    client_ip = websocket.remote_address[0]
    print(f"\n[+] Phone connected! ({client_ip})")
    gamepad.reset()                       # clean slate for the new session
    release_all_inputs()
    try:
        # Tell the app who it's talking to (version handshake on the client).
        await websocket.send(json.dumps({"type": "server_info", "version": VERSION}))
        async for raw in websocket:
            try:
                data     = json.loads(raw)
                response = handle_message(data)
                if response:
                    await websocket.send(response)
            except (json.JSONDecodeError, KeyError):
                pass
    except (websockets.exceptions.ConnectionClosedError, asyncio.CancelledError):
        pass
    except Exception:
        pass
    finally:
        gamepad.reset()                   # release everything — never leave an input stuck
        release_all_inputs()
        print(f"[-] Phone disconnected. ({client_ip})")


# ── Entry point ───────────────────────────────────────────────────────────────

async def main():
    ip = generate_qr(PORT)

    fw = ensure_firewall_rule()
    if fw == "ok":
        print("  [OK] Windows Firewall allows the server.")
    elif fw == "failed":
        print("  [!] Couldn't auto-allow the firewall. Run this once as admin,")
        print("      or allow 'python'/'TouchPlay' for Private + Public networks.")

    print("  Waiting for phone...\n")

    bg = [asyncio.create_task(flush_loop()), asyncio.create_task(udp_broadcast(ip))]
    try:
        async with websockets.serve(handler, "0.0.0.0", PORT):
            await asyncio.Future()          # run until cancelled (Ctrl+C)
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        # Cancel background tasks cleanly so there's no "Task was destroyed" noise.
        for t in bg:
            t.cancel()
        await asyncio.gather(*bg, return_exceptions=True)
        try:
            gamepad.reset()
            release_all_inputs()
        except Exception:
            pass


if __name__ == "__main__":
    import sys
    sys.tracebacklimit = 0   # no ugly tracebacks on Ctrl+C
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        print("\n[OK] Server stopped cleanly.")
    except Exception as e:
        print(f"\n[ERROR] {e}")
