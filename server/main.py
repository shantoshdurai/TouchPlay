import asyncio
import json
import os
import platform
import socket
import subprocess
import websockets
from datetime import datetime
from gamepad import (
    GamepadController, mouse_move, mouse_click, mouse_scroll, mouse_zoom,
    mouse_down, mouse_up, key_down, key_up, type_string, release_all_inputs,
)
from ui import ServerUI
from stream import stream_handler, capture_loop, STREAM_PORT, set_quality, set_high_quality
import stream as stream_mod
import files as file_transfer
import cast as casting
import usb_link

def get_best_ip() -> str:
    """Return USB tethering IP (192.168.42.x) if available, else best LAN IP."""
    candidates = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            addr = info[4][0]
            if addr.startswith("192.168.42."):
                return addr
            if not addr.startswith("127.") and ":" not in addr:
                candidates.append(addr)
    except Exception:
        pass

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            if not ip.startswith("127."):
                return ip
    except Exception:
        pass

    return candidates[0] if candidates else "127.0.0.1"

VERSION      = "1.3.0"
PORT         = 8765
UDP_PORT     = 8766
BATCH_MS     = 0.008   # 8 ms gamepad flush
MAX_PLAYERS  = 4
GRACE_SECONDS = 20

# ── Per-phone session ─────────────────────────────────────────────────────────

class Session:
    __slots__ = ("player", "gamepad", "dirty", "connected", "ip", "device_id", "connected_at", "websocket")

    def __init__(self, player: int, ip: str, websocket) -> None:
        self.player       = player
        self.ip           = ip
        self.device_id    = None
        self.websocket    = websocket
        
        loop = asyncio.get_running_loop()
        def on_rumble(large, small):
            if self.connected and self.websocket:
                msg = json.dumps({"type": "rumble", "large": large, "small": small})
                try:
                    loop.call_soon_threadsafe(lambda: asyncio.create_task(self.websocket.send(msg)))
                except Exception:
                    pass

        self.gamepad      = GamepadController(on_rumble=on_rumble)
        self.dirty        = False
        self.connected    = True
        self.connected_at = datetime.now()

_sessions:      dict[str, Session] = {}   # client_ip → Session
_cleanup_tasks: dict[str, asyncio.Task]  = {}

# Global UI reference — set in main() before the server starts.
_ui: ServerUI | None = None


# ── Windows Firewall ──────────────────────────────────────────────────────────

def ensure_firewall_rule() -> bool:
    if platform.system() != "Windows":
        return True
    flags = 0x08000000
    ok = True
    for name, proto, port in [
        ("TouchPlay Server TCP",    "TCP", PORT),
        ("TouchPlay Server UDP",    "UDP", UDP_PORT),
        ("TouchPlay Stream TCP",    "TCP", STREAM_PORT),
        ("TouchPlay Files TCP",     "TCP", file_transfer.FILES_PORT),
        ("TouchPlay Cast TCP",      "TCP", casting.CAST_PORT),
    ]:
        try:
            chk = subprocess.run(
                ["netsh", "advfirewall", "firewall", "show", "rule", f"name={name}"],
                capture_output=True, text=True, creationflags=flags)
            if chk.returncode == 0 and "No rules match" not in chk.stdout:
                continue
            res = subprocess.run(
                ["netsh", "advfirewall", "firewall", "add", "rule",
                 f"name={name}", "dir=in", "action=allow",
                 f"protocol={proto}", f"localport={port}"],
                capture_output=True, text=True, creationflags=flags)
            if res.returncode != 0:
                ok = False
        except Exception:
            ok = False
    return ok


# ── UDP auto-discovery broadcast ──────────────────────────────────────────────

async def udp_broadcast(ip: str):
    msg = json.dumps({
        "type": "server_hello", "ip": ip,
        "port": PORT, "version": VERSION,
    }).encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setblocking(False)
    parts = ip.split(".")
    targets = ["<broadcast>", "255.255.255.255"]
    if len(parts) == 4:
        targets.append(".".join(parts[:3] + ["255"]))
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
    try:
        while True:
            await asyncio.sleep(BATCH_MS)
            for s in list(_sessions.values()):
                if s.dirty:
                    s.gamepad.update()
                    s.dirty = False
    except asyncio.CancelledError:
        pass


async def focus_monitor_loop():
    try:
        import uiautomation as auto
    except ImportError:
        return

    def check_focus():
        try:
            elem = auto.GetFocusedControl()
            if elem and elem.ControlType in [50004, 50030]:
                return True
        except Exception:
            pass
        return False

    last_state = False
    try:
        while True:
            await asyncio.sleep(0.5)
            if not any(s.connected for s in _sessions.values()):
                continue
            
            current_state = await asyncio.to_thread(check_focus)
            if current_state != last_state:
                last_state = current_state
                msg = json.dumps({"type": "keyboard_requested", "show": current_state})
                for s in list(_sessions.values()):
                    if s.connected and getattr(s, "websocket", None):
                        try:
                            await s.websocket.send(msg)
                        except Exception:
                            pass
    except asyncio.CancelledError:
        pass


# ── Message handler ───────────────────────────────────────────────────────────

def handle_message(data: dict, sess: Session) -> str | None:
    t = data.get("type")
    g = sess.gamepad

    if t == "button_press":
        g.press_button(data["button"]); sess.dirty = True
    elif t == "button_release":
        g.release_button(data["button"]); sess.dirty = True
    elif t == "left_stick":
        g.set_left_stick(data["x"], data["y"]); sess.dirty = True
    elif t == "right_stick":
        g.set_right_stick(data["x"], data["y"]); sess.dirty = True
    elif t == "left_trigger":
        g.set_left_trigger(data["value"]); sess.dirty = True
    elif t == "right_trigger":
        g.set_right_trigger(data["value"]); sess.dirty = True
    elif t == "mouse_move":
        mouse_move(int(data.get("dx", 0)), int(data.get("dy", 0)))
    elif t == "mouse_scroll":
        mouse_scroll(int(data.get("dx", 0)), int(data.get("dy", 0)))
    elif t == "mouse_zoom":
        mouse_zoom(int(data.get("delta", 0)))
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
    elif t == "keyboard_string":
        type_string(data.get("text", ""))
    elif t == "reset":
        g.reset()
        if len(_sessions) <= 1:
            release_all_inputs()
    elif t == "ping":
        return json.dumps({"type": "pong"})
    elif t == "client_info":
        phone_name = data.get("phone_name")
        if phone_name and _ui:
            _ui.player_set_name(sess.player, phone_name)
    elif t == "set_stream_quality":
        level = data.get("quality")
        if level in ('360p', '480p', '720p', '1080p', 'screen'):
            set_quality(level)
        else:
            set_high_quality(data.get("high_quality", False))
    return None


async def broadcast_player_count():
    count = sum(1 for s in _sessions.values() if s.connected)
    msg = json.dumps({"type": "player_count", "count": count})
    for s in list(_sessions.values()):
        if s.connected and getattr(s, "websocket", None):
            try:
                await s.websocket.send(msg)
            except Exception:
                pass

def _assign_player() -> int | None:
    used = {s.player for s in _sessions.values()}
    for i in range(1, MAX_PLAYERS + 1):
        if i not in used:
            return i
    return None


async def _grace_cleanup(ip: str, sess: Session):
    try:
        await asyncio.sleep(GRACE_SECONDS)
    except asyncio.CancelledError:
        return
    if _sessions.get(ip) is sess and not sess.connected:
        sess.gamepad.reset()
        _sessions.pop(ip, None)
        if _ui:
            _ui.player_release(sess.player)
    _cleanup_tasks.pop(ip, None)


# ── WebSocket handler ─────────────────────────────────────────────────────────

async def handler(websocket):
    # Kill Nagle batching so button-press JSON arrives without TCP delay.
    try:
        _sock = websocket.transport.get_extra_info('socket')
        if _sock:
            import socket as _socket
            _sock.setsockopt(_socket.IPPROTO_TCP, _socket.TCP_NODELAY, 1)
    except Exception:
        pass
    client_ip = websocket.remote_address[0]

    task = _cleanup_tasks.pop(client_ip, None)
    if task:
        task.cancel()

    sess = _sessions.get(client_ip)
    if sess is None:
        player = _assign_player()
        if player is None:
            await websocket.send(json.dumps({"type": "server_full", "max": MAX_PLAYERS}))
            if _ui:
                _ui.player_rejected(client_ip, MAX_PLAYERS)
            return
        sess = Session(player, client_ip, websocket)
        _sessions[client_ip] = sess
        if _ui:
            _ui.player_connect(player, client_ip)
    else:
        sess.connected = True
        sess.websocket = websocket
        sess.connected_at = datetime.now()
        if _ui:
            _ui.player_reconnect(sess.player, client_ip)

    sess.gamepad.reset()
    await broadcast_player_count()
    try:
        await websocket.send(json.dumps({
            "type": "server_info", "version": VERSION,
            "player": sess.player, "maxPlayers": MAX_PLAYERS,
        }))
        async for raw in websocket:
            try:
                data = json.loads(raw)
                
                if data.get("type") == "client_info":
                    device_id = data.get("device_id")
                    if device_id:
                        existing = None
                        existing_ip = None
                        for ip, s in _sessions.items():
                            if s.device_id == device_id and s is not sess:
                                existing = s
                                existing_ip = ip
                                break
                        if existing and not existing.connected:
                            if _ui:
                                _ui.player_drop(sess.player, 0)
                            _sessions.pop(client_ip, None)
                            
                            sess = existing
                            sess.connected = True
                            sess.websocket = websocket
                            sess.ip = client_ip
                            sess.connected_at = datetime.now()
                            _sessions[client_ip] = sess
                            if existing_ip and existing_ip != client_ip:
                                _sessions.pop(existing_ip, None)
                                
                            if _ui:
                                _ui.player_reconnect(sess.player, client_ip)
                                
                            await websocket.send(json.dumps({
                                "type": "server_info", "version": VERSION,
                                "player": sess.player, "maxPlayers": MAX_PLAYERS,
                            }))
                            await broadcast_player_count()
                        else:
                            sess.device_id = device_id

                response = handle_message(data, sess)
                if response:
                    await websocket.send(response)
            except (json.JSONDecodeError, KeyError):
                pass
    except (websockets.exceptions.ConnectionClosedError, asyncio.CancelledError):
        pass
    except Exception:
        pass
    finally:
        sess.connected = False
        sess.gamepad.reset()
        if _ui:
            _ui.player_drop(sess.player, GRACE_SECONDS)
        
        asyncio.create_task(broadcast_player_count())
        
        _cleanup_tasks[client_ip] = asyncio.create_task(
            _grace_cleanup(client_ip, sess)
        )


# ── Entry point ───────────────────────────────────────────────────────────────

async def run_server(ui, ip: str):
    """Run every server component against the given UI (terminal or window)."""
    global _ui
    _ui = ui

    ui.log(f"Server live · co-op ready · up to [bold]{MAX_PLAYERS}[/] players")

    file_transfer.set_logger(ui.log)
    casting.set_logger(ui.log)
    usb_link.set_logger(ui.log)
    stream_mod.set_logger(ui.log)
    file_transfer.start_file_server()
    ui.log(f"File drop ready · phone files land in [bold]Downloads\\TouchPlay[/]")

    bg: list[asyncio.Task] = []
    with ui:
        bg = [
            asyncio.create_task(flush_loop()),
            asyncio.create_task(udp_broadcast(ip)),
            asyncio.create_task(ui.refresh_loop()),
            asyncio.create_task(capture_loop()),
            asyncio.create_task(focus_monitor_loop()),
            asyncio.create_task(usb_link.usb_autolink_loop()),
        ]
        try:
            async with websockets.serve(handler, "0.0.0.0", PORT):
                async with websockets.serve(stream_handler, "0.0.0.0", STREAM_PORT):
                    async with websockets.serve(
                            casting.cast_handler, "0.0.0.0", casting.CAST_PORT,
                            max_size=8 * 1024 * 1024):
                        await asyncio.Future()
        except (asyncio.CancelledError, KeyboardInterrupt):
            pass
        finally:
            for t in bg:
                t.cancel()
            await asyncio.gather(*bg, return_exceptions=True)
            try:
                for s in list(_sessions.values()):
                    s.gamepad.reset()
                release_all_inputs()
            except Exception:
                pass


async def main():
    """Terminal-dashboard mode (fallback / --console)."""
    ip = get_best_ip()
    fw = ensure_firewall_rule()
    ui = ServerUI(ip=ip, version=VERSION, max_players=MAX_PLAYERS)
    ui.set_firewall(fw)
    if not fw:
        ui.log("[yellow]⚠ Firewall rule missing — run as Administrator once[/]")
    await run_server(ui, ip)


def main_gui() -> bool:
    """Desktop-window mode (default). Tk owns the main thread; the asyncio
    server runs on a worker thread. Returns False if Tk isn't available so
    the caller can fall back to the terminal dashboard."""
    import threading
    try:
        from gui import ServerGUI
    except Exception:
        return False

    ip = get_best_ip()
    fw = ensure_firewall_rule()
    try:
        gui = ServerGUI(ip=ip, version=VERSION, max_players=MAX_PLAYERS,
                        drop_dir=file_transfer.DROP_DIR)
    except Exception:
        return False   # e.g. headless session — use the terminal instead
    gui.set_firewall(fw)
    if not fw:
        gui.log("[yellow]⚠ Firewall rule missing — run once as Administrator[/]")

    holder: dict = {}

    def runner():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        task = loop.create_task(run_server(gui, ip))
        holder["loop"], holder["task"] = loop, task
        try:
            loop.run_until_complete(task)
        except Exception:
            pass
        finally:
            try:
                release_all_inputs()
            except Exception:
                pass
            loop.close()

    t = threading.Thread(target=runner, name="touchplay-server", daemon=True)
    t.start()

    def stop_server():
        loop, task = holder.get("loop"), holder.get("task")
        if loop and task:
            loop.call_soon_threadsafe(task.cancel)
        t.join(timeout=3)   # give the loop a moment to reset gamepads

    gui.set_on_close(stop_server)
    gui.mainloop()
    stop_server()
    # Hard exit: stray non-daemon threads (COM/uiautomation/capture helpers)
    # kept the process alive after the window closed — the cause of "I hit X
    # but Task Manager still shows it". Gamepads are already reset above.
    os._exit(0)


def _force_utf8_console() -> None:
    """Make the console UTF-8 + VT-capable so the dashboard's box/▣ glyphs render
    on any Windows console (not just Windows Terminal). Without this, a default
    cp1252 console crashes on characters like ● ◔ ·."""
    try:
        import ctypes
        k32 = ctypes.windll.kernel32
        k32.SetConsoleOutputCP(65001)
        k32.SetConsoleCP(65001)
        # Enable virtual-terminal processing (ANSI colours) on the output handle.
        h = k32.GetStdHandle(-11)
        mode = ctypes.c_uint()
        if k32.GetConsoleMode(h, ctypes.byref(mode)):
            k32.SetConsoleMode(h, mode.value | 0x0004)
    except Exception:
        pass
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


if __name__ == "__main__":
    import sys
    sys.tracebacklimit = 0
    # Default: desktop window. `--console` (or a missing/broken tkinter)
    # falls back to the rich terminal dashboard.
    if "--console" not in sys.argv:
        try:
            if main_gui():
                sys.exit(0)
        except (KeyboardInterrupt, SystemExit):
            sys.exit(0)
        except Exception:
            pass   # fall through to the terminal dashboard
    _force_utf8_console()
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
    except Exception as e:
        print(f"\n[ERROR] {e}")
