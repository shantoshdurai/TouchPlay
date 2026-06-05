"""
TouchPlay — live terminal dashboard (rich-based).

Provides ServerUI: a Live-rendered panel with logo, server status,
per-player table and a scrolling event log. Zero Chromium, ~12 MB RAM.

Usage:
    ui = ServerUI(ip="192.168.1.5", version="1.2.0", max_players=4)
    with ui:
        # asyncio event loop running — call ui.log() / ui.player_*() freely
        await asyncio.sleep(99999)
"""
from __future__ import annotations

import asyncio
import socket
from collections import deque
from datetime import datetime
from typing import Optional

from rich import box
from rich.align import Align
from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

# ── Accent palette (monochrome design — cyan only, no Xbox colours) ───────────
_C  = "bright_cyan"       # accent
_W  = "white"
_D  = "dim white"
_G  = "bright_green"
_Y  = "yellow"
_R  = "bright_red"
_BG = "on #09090f"        # near-black background used in panels

# ── ASCII logo (hand-crafted block-char "TOUCHPLAY") ─────────────────────────
# Fits comfortably in an 80-column window. Two rows: TOUCH / PLAY stacked.
_LOGO_LINES = [
    r" ████████╗ ██████╗ ██╗   ██╗ ██████╗██╗  ██╗",
    r"    ██╔══╝██╔═══██╗██║   ██║██╔════╝██║  ██║",
    r"    ██║   ██║   ██║██║   ██║██║     ███████║",
    r"    ╚═╝   ╚██████╔╝╚██████╔╝╚██████╗██║  ██║",
    r"           ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝",
    r"",
    r"    ██████╗ ██╗      █████╗ ██╗   ██╗",
    r"    ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝",
    r"    ██████╔╝██║     ███████║ ╚████╔╝",
    r"    ██╔═══╝ ██║     ██╔══██║  ╚██╔╝",
    r"    ╚═╝     ███████╗██║  ██║   ██║",
    r"            ╚══════╝╚═╝  ╚═╝   ╚═╝",
]

# Player-slot indicator glyphs
_ONLINE  = f"[{_G}]●[/]"
_WAITING = f"[{_D}]○[/]"
_GRACE   = f"[{_Y}]◔[/]"   # held during grace window

_MAX_LOG = 8  # event log lines to keep


class PlayerInfo:
    """Snapshot of one player slot's display state."""
    __slots__ = ("ip", "connected", "grace", "connected_at")

    def __init__(self) -> None:
        self.ip: Optional[str]      = None
        self.connected: bool        = False
        self.grace: bool            = False
        self.connected_at: Optional[datetime] = None

    def reset(self) -> None:
        self.ip = None
        self.connected = False
        self.grace = False
        self.connected_at = None


class ServerUI:
    """
    Live terminal dashboard.  Use as a context manager:

        with ServerUI(...) as ui:
            ui.log("started")
            ...
    """

    def __init__(self, ip: str, version: str, max_players: int = 4) -> None:
        self._ip          = ip
        self._version     = version
        self._max_players = max_players
        self._started_at  = datetime.now()
        self._players     = [PlayerInfo() for _ in range(max_players)]
        self._log: deque[str] = deque(maxlen=_MAX_LOG)
        self._fw_ok       = True
        self._console     = Console(highlight=False)
        self._live: Optional[Live] = None

    # ── Public API called from main.py ────────────────────────────────────────

    def log(self, msg: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S")
        self._log.appendleft(f"[{_D}]{ts}[/]  {msg}")
        if self._live:
            self._live.update(self._build())

    def player_connect(self, slot: int, ip: str) -> None:
        if 1 <= slot <= self._max_players:
            p = self._players[slot - 1]
            p.ip = ip
            p.connected = True
            p.grace = False
            p.connected_at = datetime.now()
        self.log(f"[{_G}][P{slot}][/] Connected  [{_D}]{ip}[/]")

    def player_reconnect(self, slot: int, ip: str) -> None:
        if 1 <= slot <= self._max_players:
            p = self._players[slot - 1]
            p.connected = True
            p.grace = False
            p.connected_at = datetime.now()
        self.log(f"[{_C}][P{slot}][/] Reconnected  [{_D}]{ip}[/]")

    def player_drop(self, slot: int, grace_sec: int) -> None:
        if 1 <= slot <= self._max_players:
            self._players[slot - 1].connected = False
            self._players[slot - 1].grace = True
        self.log(f"[{_Y}][P{slot}][/] Dropped — holding [{_D}]{grace_sec}s[/]")

    def player_release(self, slot: int) -> None:
        if 1 <= slot <= self._max_players:
            self._players[slot - 1].reset()
        self.log(f"[{_D}][P{slot}] Released[/]")

    def player_rejected(self, ip: str, max_p: int) -> None:
        self.log(f"[{_R}]Rejected {ip} — server full ({max_p} players)[/]")

    def set_firewall(self, ok: bool) -> None:
        self._fw_ok = ok

    # ── Context manager ───────────────────────────────────────────────────────

    def __enter__(self) -> "ServerUI":
        self._live = Live(
            self._build(),
            console=self._console,
            refresh_per_second=2,
            screen=False,
            vertical_overflow="visible",
        )
        self._live.__enter__()
        return self

    def __exit__(self, *args) -> None:
        if self._live:
            self._live.__exit__(*args)
            self._live = None
        self._console.print(
            f"\n[{_C}]  TouchPlay server stopped cleanly.[/]\n"
        )

    # ── Async refresh loop (run as background task) ───────────────────────────

    async def refresh_loop(self) -> None:
        """Redraw every 0.5 s so uptime counter ticks live."""
        try:
            while True:
                if self._live:
                    self._live.update(self._build())
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            pass

    # ── Layout builders ───────────────────────────────────────────────────────

    def _build(self) -> Panel:
        rows = []

        # ── Logo ──────────────────────────────────────────────────────────────
        logo_text = Text(justify="left")
        for line in _LOGO_LINES:
            logo_text.append(line + "\n", style=f"bold {_C}")
        rows.append(Align.center(logo_text))
        rows.append(Text(
            f"  v{self._version}  ·  Turn your phone into a controller",
            style=f"bold {_D}", justify="center"
        ))
        rows.append(Text(""))

        # ── Status bar ────────────────────────────────────────────────────────
        up_secs = int((datetime.now() - self._started_at).total_seconds())
        h, rem  = divmod(up_secs, 3600)
        m, s    = divmod(rem, 60)
        uptime  = f"{h:02d}:{m:02d}:{s:02d}"

        active  = sum(1 for p in self._players if p.connected)
        fw_note = "" if self._fw_ok else f"  [{_Y}]⚠ Firewall[/]"

        status  = Text(justify="center")
        status.append(f"  ● SERVER LIVE", style=f"bold {_G}")
        status.append(f"   {self._ip}:{8765}", style=_W)
        status.append(f"   ⏱ {uptime}", style=_D)
        status.append(f"   Players: {active}/{self._max_players}", style=_C)
        status.append(fw_note)
        rows.append(status)
        rows.append(Text(""))

        # ── Player table ──────────────────────────────────────────────────────
        tbl = Table(
            box=box.SIMPLE_HEAD,
            show_header=True,
            header_style=f"bold {_C}",
            padding=(0, 1),
            expand=False,
        )
        tbl.add_column("SLOT",    style="bold white",  width=6)
        tbl.add_column("STATUS",  style="white",       width=14)
        tbl.add_column("IP",      style=_D,            width=18)
        tbl.add_column("SINCE",   style=_D,            width=10)

        for i, p in enumerate(self._players):
            slot_label = f"P{i+1}"
            if p.connected:
                icon   = _ONLINE
                status_txt = f"[{_G}]● CONNECTED[/]"
                ip_txt     = f"[white]{p.ip or '—'}[/]"
                since      = self._elapsed(p.connected_at)
            elif p.grace:
                icon   = _GRACE
                status_txt = f"[{_Y}]◔ GRACE[/]"
                ip_txt     = f"[{_D}]{p.ip or '—'}[/]"
                since      = self._elapsed(p.connected_at)
            else:
                icon   = _WAITING
                status_txt = f"[{_D}]○ WAITING[/]"
                ip_txt     = f"[{_D}]—[/]"
                since      = f"[{_D}]—[/]"

            tbl.add_row(
                f"{icon} {slot_label}",
                status_txt,
                ip_txt,
                since,
            )

        rows.append(Align.center(tbl))
        rows.append(Text(""))

        # ── Event log ─────────────────────────────────────────────────────────
        if self._log:
            for entry in self._log:
                rows.append(Text.from_markup(f"  {entry}"))
        else:
            rows.append(Text(
                "  Waiting for phones to connect…",
                style=_D
            ))
        rows.append(Text(""))

        # ── Footer ────────────────────────────────────────────────────────────
        rows.append(Text(
            "  [Ctrl+C] Stop server",
            style=f"dim {_D}",
        ))

        # Combine into one renderable
        from rich.console import Group
        content = Group(*rows)

        return Panel(
            content,
            border_style=_C,
            padding=(0, 1),
        )

    @staticmethod
    def _elapsed(since: Optional[datetime]) -> str:
        if since is None:
            return f"[dim]—[/]"
        secs = int((datetime.now() - since).total_seconds())
        h, rem = divmod(secs, 3600)
        m, s   = divmod(rem, 60)
        if h:
            return f"[dim]{h}h {m:02d}m[/]"
        return f"[dim]{m}:{s:02d}[/]"


# ── Startup splash (shown once before entering Live mode) ─────────────────────

def print_startup_splash(ip: str, port: int, version: str) -> None:
    """Print a static connection info card before the live UI starts."""
    console = Console(highlight=False)
    console.print()
    for line in _LOGO_LINES:
        console.print(f"  [bold {_C}]{line}[/]")
    console.print(f"\n  [bold {_C}]v{version}[/]  ·  Turn your phone into a controller\n")

    w = 44
    console.print(f"  ┌{'─' * w}┐")
    console.print(f"  │{'SERVER STARTING':^{w}}│")
    console.print(f"  ├{'─' * w}┤")
    console.print(f"  │ [white]{'IP   :  ' + ip:<{w-1}}[/]│")
    console.print(f"  │ [white]{'Port :  ' + str(port):<{w-1}}[/]│")
    console.print(f"  ├{'─' * w}┤")
    console.print(f"  │ [{_D}]{'Open the app — it auto-connects.':<{w-1}}[/]│")
    console.print(f"  └{'─' * w}┘\n")
