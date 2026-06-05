"""
TouchPlay — live terminal dashboard (rich-based).

A clean full-screen TUI (screen=True, like htop) that redraws in place:
compact logo, server status, a per-player table and a short event log.
No scrolling, no duplicate output. ~12 MB RAM.
"""
from __future__ import annotations

import asyncio
from collections import deque
from datetime import datetime
from typing import Optional

from rich import box
from rich.align import Align
from rich.console import Console, Group
from rich.padding import Padding
from rich.panel import Panel
from rich.rule import Rule
from rich.table import Table
from rich.text import Text

# ── Palette (monochrome — cyan accent only) ──────────────────────────────────
_C = "bright_cyan"
_D = "grey50"
_G = "bright_green"
_Y = "yellow"
_R = "bright_red"

_PORT = 8765
_MAX_LOG = 6


# ── Compact wordmark logo (figlet 'small' of "TouchPlay", baked in) ───────────
# Hardcoded so we don't ship pyfiglet + its font files inside the exe.
_LOGO_LINES = [
    r' _____            _    ___ _           ',
    r'|_   _|__ _  _ __| |_ | _ \ |__ _ _  _ ',
    r"  | |/ _ \ || / _| ' \|  _/ / _` | || |",
    r'  |_|\___/\_,_\__|_||_|_| |_\__,_|\_, |',
    r'                                  |__/ ',
]


class PlayerInfo:
    __slots__ = ("ip", "phone", "connected", "grace", "since")

    def __init__(self) -> None:
        self.ip: Optional[str] = None
        self.phone: Optional[str] = None
        self.connected = False
        self.grace = False
        self.since: Optional[datetime] = None

    def reset(self) -> None:
        self.ip = None
        self.phone = None
        self.connected = False
        self.grace = False
        self.since = None


class ServerUI:
    def __init__(self, ip: str, version: str, max_players: int = 4) -> None:
        self._ip = ip
        self._version = version
        self._max = max_players
        self._start = datetime.now()
        self._players = [PlayerInfo() for _ in range(max_players)]
        self._log: deque[str] = deque(maxlen=_MAX_LOG)
        self._fw_ok = True
        # legacy_windows=False forces ANSI/VT output (Win10+) so unicode glyphs
        # like ● ◔ · never hit the cp1252 charmap path and crash.
        self._console = Console(highlight=False, legacy_windows=False)
        self._live = None

    # ── public API ────────────────────────────────────────────────────────────
    def log(self, msg: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S")
        self._log.appendleft(f"[{_D}]{ts}[/]  {msg}")
        self._refresh()

    def player_connect(self, slot: int, ip: str) -> None:
        p = self._players[slot - 1]
        p.ip, p.connected, p.grace, p.since = ip, True, False, datetime.now()
        self.log(f"[{_G}]●[/] [bold]P{slot}[/] connected  [{_D}]{ip}[/]")

    def player_reconnect(self, slot: int, ip: str) -> None:
        p = self._players[slot - 1]
        p.connected, p.grace, p.since = True, False, datetime.now()
        self.log(f"[{_C}]●[/] [bold]P{slot}[/] reconnected  [{_D}]{ip}[/]")

    def player_drop(self, slot: int, grace: int) -> None:
        p = self._players[slot - 1]
        p.connected, p.grace = False, True
        self.log(f"[{_Y}]◔[/] [bold]P{slot}[/] dropped — holding [{_D}]{grace}s[/]")

    def player_release(self, slot: int) -> None:
        self._players[slot - 1].reset()
        self.log(f"[{_D}]○ P{slot} released[/]")

    def player_set_name(self, slot: int, name: str) -> None:
        self._players[slot - 1].phone = name
        self._refresh()

    def player_rejected(self, ip: str, max_p: int) -> None:
        self.log(f"[{_R}]server full — rejected {ip}[/]")

    def set_firewall(self, ok: bool) -> None:
        self._fw_ok = ok

    # ── context manager ───────────────────────────────────────────────────────
    def __enter__(self) -> "ServerUI":
        from rich.live import Live
        self._live = Live(
            self._build(),
            console=self._console,
            screen=True,             # full-screen alt buffer — no scroll/dupes
            refresh_per_second=4,
            transient=False,
        )
        self._live.__enter__()
        return self

    def __exit__(self, *a) -> None:
        if self._live:
            self._live.__exit__(*a)
            self._live = None
        self._console.print(f"[{_C}]  TouchPlay server stopped.[/]")

    async def refresh_loop(self) -> None:
        try:
            while True:
                self._refresh()
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            pass

    def _refresh(self) -> None:
        if self._live:
            self._live.update(self._build())

    # ── rendering ─────────────────────────────────────────────────────────────
    def _build(self):
        # Logo
        logo = Text(justify="left")
        for ln in _LOGO_LINES:
            logo.append(ln + "\n", style=f"bold {_C}")
        logo.append(f"v{self._version}  ", style=f"bold {_D}")
        logo.append("· wireless controller server", style=_D)

        # Status line
        up = int((datetime.now() - self._start).total_seconds())
        h, r = divmod(up, 3600)
        m, s = divmod(r, 60)
        active = sum(1 for p in self._players if p.connected)

        status = Text()
        status.append("● ", style=f"bold {_G}")
        status.append("SERVER LIVE", style=f"bold {_G}")
        status.append("     ")
        status.append(f"{self._ip}:{_PORT}", style="white")
        status.append("     ")
        status.append(f"uptime {h:02d}:{m:02d}:{s:02d}", style=_D)
        status.append("     ")
        status.append(f"players ", style=_D)
        status.append(f"{active}/{self._max}", style=f"bold {_C}")
        if not self._fw_ok:
            status.append(f"     ⚠ firewall", style=_Y)

        # Player table
        tbl = Table(box=box.SIMPLE_HEAD, show_edge=False, expand=False,
                    header_style=f"bold {_C}", padding=(0, 2))
        tbl.add_column("SLOT", width=5)
        tbl.add_column("STATUS", width=13)
        tbl.add_column("IP / DEVICE", width=25, style=_D)
        tbl.add_column("SINCE", width=8, style=_D)
        
        has_players = False
        for i, p in enumerate(self._players):
            if not p.connected and not p.grace:
                continue
            has_players = True
            
            if p.connected:
                st = f"[{_G}]● connected[/]"
            else:
                st = f"[{_Y}]◔ grace[/]"
                
            ip_str = p.ip or "—"
            if p.phone:
                ip_str += f"  [{p.phone}]"
            ip = f"[white]{ip_str}[/]" if p.connected else f"[{_D}]{ip_str}[/]"
            since = self._ago(p.since)
            tbl.add_row(f"[bold]P{i+1}[/]", st, ip, since)

        available_slots = self._max - active
        if available_slots > 0:
            slots_text = f"Waiting for connections... ({available_slots} slots available)" if not has_players else f"({available_slots} slots available)"
        else:
            slots_text = ""

        # Event log
        log_lines = list(self._log) or [f"[{_D}]waiting for phones to connect…[/]"]
        log_group = Group(*[Text.from_markup(x) for x in log_lines])

        items = [
            logo,
            Text(""),
            status,
            Rule(style=_D)
        ]
        
        if has_players:
            items.append(tbl)
            
        if slots_text:
            items.append(Padding(Text(slots_text, style=_D), (0, 0, 1, 0) if has_players else (1, 0)))

        items.extend([
            Rule(style=_D),
            Text("RECENT", style=f"bold {_D}"),
            log_group,
            Text(""),
            Text("Ctrl+C to stop", style=_D),
        ])
        
        body = Group(*items)
        return Padding(body, (1, 3))

    @staticmethod
    def _ago(since: Optional[datetime]) -> str:
        if since is None:
            return f"[{_D}]—[/]"
        secs = int((datetime.now() - since).total_seconds())
        m, s = divmod(secs, 60)
        h, m = divmod(m, 60)
        return f"[{_D}]{h}h{m:02d}[/]" if h else f"[{_D}]{m}:{s:02d}[/]"
