"""
gui.py — TouchPlay server desktop window (tkinter, stdlib only).

Minimal, friendly window in the spirit of a small Mac utility: a couple of
soft rounded cards, plain-language copy, and no wall of logs — just a quiet
"last activity" line with an optional Details drawer for the curious.

Exposes the exact same API as ui.ServerUI (log / player_* / set_firewall /
refresh_loop / context manager), so main.py can drive either interchangeably.
All public methods are thread-safe: the asyncio server runs on a worker
thread and every UI mutation is marshalled onto the Tk main loop via a queue.

Note: Tk 8.6 only renders Basic-Multilingual-Plane characters, so decorations
stick to safe glyphs (● ↻ ✓ ✦) — no astral-plane emoji.
"""
from __future__ import annotations

import os
import queue
import re
import threading
import tkinter as tk
from tkinter import font as tkfont
from datetime import datetime
from pathlib import Path
from typing import Optional

# ── Palette — soft dark, one cyan accent, Apple-ish status colors ────────────
_BG     = "#0f0f13"
_CARD   = "#17171d"
_TEXT   = "#f4f4f6"
_DIM    = "#a0a0ab"
_FAINT  = "#5d5d68"
_ACCENT = "#00d4ff"
_GREEN  = "#32d74b"
_YELLOW = "#ffd60a"
_RED    = "#ff6961"

_MAX_LOG = 200

_MARKUP_RE = re.compile(r"\[/?[a-zA-Z_ #0-9]*\]")


def _strip_markup(s: str) -> str:
    return _MARKUP_RE.sub("", s)


def _severity(raw: str) -> str:
    if "[red" in raw or "[bright_red" in raw:
        return "err"
    if "[yellow" in raw:
        return "warn"
    if "[green" in raw or "[bright_green" in raw:
        return "ok"
    if "[cyan" in raw or "[bright_cyan" in raw:
        return "accent"
    return "info"


class _Slot:
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


class _Card(tk.Canvas):
    """Soft rounded-corner card. Content goes into `.inner` (a Frame); the
    canvas paints the rounded background behind it and auto-sizes to fit."""

    def __init__(self, parent, radius: int = 18, pad: int = 18,
                 card_bg: str = _CARD, **kw):
        super().__init__(parent, bg=_BG, highlightthickness=0, bd=0, **kw)
        self._card_bg = card_bg
        self._radius = radius
        self._pad = pad
        self.inner = tk.Frame(self, bg=card_bg)
        self._win = self.create_window(pad, pad, anchor="nw", window=self.inner)
        self.bind("<Configure>", self._redraw)
        self.inner.bind("<Configure>", self._fit)

    def _round_rect(self, x1, y1, x2, y2, r, **kw):
        pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r,
               x2, y2, x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r,
               x1, y1 + r, x1, y1]
        return self.create_polygon(pts, smooth=True, **kw)

    def _redraw(self, _e=None) -> None:
        self.delete("bg")
        w = max(self.winfo_width(), 10)
        h = max(self.winfo_height(), 10)
        self._round_rect(1, 1, w - 1, h - 1, self._radius,
                         fill=self._card_bg, outline="", tags="bg")
        self.tag_lower("bg")
        self.itemconfigure(self._win, width=max(10, w - 2 * self._pad))

    def _fit(self, _e=None) -> None:
        self.configure(height=self.inner.winfo_reqheight() + 2 * self._pad)


class ServerGUI:
    """Tk window with the ServerUI API. Construct + mainloop() on the MAIN
    thread; every other method may be called from any thread."""

    def __init__(self, ip: str, version: str, max_players: int = 4,
                 drop_dir: Optional[Path] = None) -> None:
        self._ip = ip
        self._version = version
        self._max = max_players
        self._start = datetime.now()
        self._slots = [_Slot() for _ in range(max_players)]
        self._fw_ok = True
        self._drop_dir = drop_dir
        self._queue: "queue.Queue" = queue.Queue()
        self._on_close = None
        self._events: list[tuple[str, str, str]] = []   # (ts, text, sev)
        self._details_open = False

        self._root = tk.Tk()
        self._root.title("TouchPlay Server")
        self._root.configure(bg=_BG)
        self._root.geometry("440x520")
        self._root.minsize(400, 460)

        self._tray = None
        self._tray_hint_shown = False
        self._quitting = False

        self._build()
        self._setup_tray()
        self._root.protocol("WM_DELETE_WINDOW", self._close_clicked)
        self._root.after(80, self._pump)
        self._root.after(1000, self._tick)

    # ── public API (thread-safe) ──────────────────────────────────────────────

    def set_on_close(self, fn) -> None:
        self._on_close = fn

    def mainloop(self) -> None:
        self._root.mainloop()

    def log(self, msg: str) -> None:
        ts = datetime.now().strftime("%H:%M")
        sev = _severity(msg)
        text = _strip_markup(msg)
        self._post(lambda: self._add_event(ts, text, sev))

    def player_connect(self, slot: int, ip: str) -> None:
        def apply():
            p = self._slots[slot - 1]
            p.ip, p.connected, p.grace, p.since = ip, True, False, datetime.now()
            self._redraw_players()
        self._post(apply)
        self.log(f"[green]Phone {slot} connected ({ip})[/]")

    def player_reconnect(self, slot: int, ip: str) -> None:
        def apply():
            p = self._slots[slot - 1]
            p.ip, p.connected, p.grace, p.since = ip, True, False, datetime.now()
            self._redraw_players()
        self._post(apply)
        self.log(f"[cyan]Phone {slot} reconnected[/]")

    def player_drop(self, slot: int, grace: int) -> None:
        def apply():
            p = self._slots[slot - 1]
            p.connected, p.grace = False, True
            self._redraw_players()
        self._post(apply)
        if grace:
            self.log(f"[yellow]Phone {slot} lost — keeping its spot "
                     f"for {grace}s[/]")

    def player_release(self, slot: int) -> None:
        def apply():
            self._slots[slot - 1].reset()
            self._redraw_players()
        self._post(apply)

    def player_set_name(self, slot: int, name: str) -> None:
        def apply():
            self._slots[slot - 1].phone = name
            self._redraw_players()
        self._post(apply)

    def player_rejected(self, ip: str, max_p: int) -> None:
        self.log(f"[red]A phone tried to join but all {max_p} spots "
                 f"are taken ({ip})[/]")

    def set_firewall(self, ok: bool) -> None:
        self._fw_ok = ok
        self._post(self._redraw_status)

    async def refresh_loop(self) -> None:
        import asyncio
        try:
            while True:
                await asyncio.sleep(3600)
        except asyncio.CancelledError:
            pass

    def __enter__(self) -> "ServerGUI":
        return self

    def __exit__(self, *a) -> None:
        pass

    # ── Tk thread plumbing ────────────────────────────────────────────────────

    def _post(self, fn) -> None:
        self._queue.put(fn)

    def _pump(self) -> None:
        try:
            while True:
                fn = self._queue.get_nowait()
                try:
                    fn()
                except Exception:
                    pass
        except queue.Empty:
            pass
        self._root.after(80, self._pump)

    def _tick(self) -> None:
        self._redraw_status()
        self._redraw_players()
        self._root.after(1000, self._tick)

    def _close_clicked(self) -> None:
        # With a tray icon, X behaves like Steam/Discord: the window hides but
        # the server keeps serving from the tray. Without one (pystray not
        # installed), X is a real quit.
        if self._tray is not None:
            self._root.withdraw()
            if not self._tray_hint_shown:
                self._tray_hint_shown = True
                try:
                    self._tray.notify(
                        "Still running — your phones stay connected. "
                        "Right-click the tray icon to quit.", "TouchPlay")
                except Exception:
                    pass
            return
        self._quit()

    def _quit(self) -> None:
        if self._quitting:
            return
        self._quitting = True
        # 1. Stop the server first: disconnects every phone and resets the
        #    virtual gamepads (stuck-input safety) before the process dies.
        if self._on_close:
            try:
                self._on_close()
            except Exception:
                pass
        if self._tray is not None:
            try:
                self._tray.stop()
            except Exception:
                pass
            self._tray = None
        # 2. Normal path: unwind Tk so main_gui() reaches its own os._exit(0).
        try:
            self._root.after(150, self._root.destroy)
        except Exception:
            pass
        # 3. Failsafe: Quit must mean QUIT. If Tk never unwinds (withdrawn
        #    window, dead after-loop, cross-thread call), hard-exit anyway —
        #    cleanup above has already run.
        import os as _os
        import threading as _threading
        _threading.Timer(2.0, lambda: _os._exit(0)).start()

    # ── System tray ───────────────────────────────────────────────────────────

    def _setup_tray(self) -> None:
        try:
            import pystray
        except Exception:
            return                      # no tray lib — X simply quits
        img = self._tray_image()
        if img is None:
            return
        try:
            menu = pystray.Menu(
                pystray.MenuItem("Open TouchPlay",
                                 lambda *_: self._post(self._show_window),
                                 default=True),
                # Quit runs DIRECTLY on the tray thread — never queued through
                # the Tk pump. A queued quit silently does nothing if Tk is
                # wedged, leaving the server running with phones connected.
                pystray.MenuItem("Quit",
                                 lambda *_: self._quit()),
            )
            self._tray = pystray.Icon("TouchPlay", img,
                                      "TouchPlay Server — running", menu)
            self._tray.run_detached()
        except Exception:
            self._tray = None

    def _show_window(self) -> None:
        self._root.deiconify()
        self._root.lift()
        try:
            self._root.focus_force()
        except Exception:
            pass

    @staticmethod
    def _tray_image():
        """App icon for the tray; falls back to a drawn cyan dot."""
        try:
            from PIL import Image, ImageDraw
        except Exception:
            return None
        import sys
        candidates = []
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            candidates.append(Path(meipass) / "app_icon.png")
        here = Path(__file__).resolve().parent
        candidates.append(here.parent / "app_icon.png")
        for c in candidates:
            try:
                if c.is_file():
                    return Image.open(c).convert("RGBA")
            except Exception:
                pass
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.ellipse([8, 8, 56, 56], fill=(0, 212, 255, 255))
        return img

    # ── Layout ────────────────────────────────────────────────────────────────

    def _build(self) -> None:
        # Typography: a warm serif for the wordmark + headings (Claude-style),
        # Windows 11's Segoe UI Variable for body text (closest to SF Pro),
        # graceful fallbacks for older Windows.
        fams = set(tkfont.families())

        def pick(*prefs: str, fallback: str = "Segoe UI") -> str:
            for p in prefs:
                if p in fams:
                    return p
            return fallback

        serif = pick("Georgia")
        body  = pick("Segoe UI Variable Text", "Segoe UI Variable")
        disp  = pick("Segoe UI Variable Display", "Segoe UI Variable")

        base = tkfont.nametofont("TkDefaultFont")
        base.configure(family=body, size=10)
        self._f_title = tkfont.Font(family=serif, size=17, weight="bold")
        self._f_big   = tkfont.Font(family=serif, size=13, weight="bold")
        self._f_body  = tkfont.Font(family=body, size=10)
        self._f_small = tkfont.Font(family=body, size=9)
        self._f_mono  = tkfont.Font(family=disp, size=13, weight="bold")

        # Header ───────────────────────────────────────────────────────────────
        head = tk.Frame(self._root, bg=_BG)
        head.pack(fill="x", padx=24, pady=(20, 12))
        tk.Label(head, text="TouchPlay", font=self._f_title,
                 fg=_TEXT, bg=_BG).pack(side="left")
        self._live_lbl = tk.Label(head, text="●  live", font=self._f_small,
                                  fg=_GREEN, bg=_BG)
        self._live_lbl.pack(side="right")

        # Hero card — what to do + where ───────────────────────────────────────
        hero = _Card(self._root)
        hero.pack(fill="x", padx=20, pady=(0, 12))
        tk.Label(hero.inner, text="Ready to play  ✦", font=self._f_big,
                 fg=_TEXT, bg=_CARD, anchor="w").pack(fill="x")
        tk.Label(hero.inner,
                 text="Open TouchPlay on your phone — it finds this\n"
                      "computer on its own.",
                 font=self._f_body, fg=_DIM, bg=_CARD,
                 justify="left", anchor="w").pack(fill="x", pady=(4, 10))
        addr = tk.Frame(hero.inner, bg=_CARD)
        addr.pack(fill="x")
        tk.Label(addr, text="address", font=self._f_small,
                 fg=_FAINT, bg=_CARD).pack(side="left")
        tk.Label(addr, text=self._ip, font=self._f_mono,
                 fg=_ACCENT, bg=_CARD).pack(side="left", padx=(8, 0))
        self._fw_lbl = tk.Label(hero.inner, text="", font=self._f_small,
                                fg=_YELLOW, bg=_CARD, anchor="w",
                                justify="left")

        # Phones card ──────────────────────────────────────────────────────────
        pcard = _Card(self._root)
        pcard.pack(fill="x", padx=20, pady=(0, 12))
        prow = tk.Frame(pcard.inner, bg=_CARD)
        prow.pack(fill="x")
        tk.Label(prow, text="Phones", font=self._f_big,
                 fg=_TEXT, bg=_CARD).pack(side="left")
        self._count_lbl = tk.Label(prow, text="", font=self._f_small,
                                   fg=_FAINT, bg=_CARD)
        self._count_lbl.pack(side="right")
        self._players_box = tk.Frame(pcard.inner, bg=_CARD)
        self._players_box.pack(fill="x", pady=(8, 0))

        # Footer (packed FIRST from the bottom so it never gets pushed out) ────
        foot = tk.Frame(self._root, bg=_BG)
        foot.pack(side="bottom", fill="x", padx=24, pady=(6, 14))
        if self._drop_dir is not None:
            files_btn = tk.Label(foot, text="Open files folder",
                                 font=self._f_small, fg=_ACCENT, bg=_BG,
                                 cursor="hand2")
            files_btn.pack(side="left")
            files_btn.bind("<Button-1>", lambda e: self._open_drop())
        self._uptime_lbl = tk.Label(foot, text="", font=self._f_small,
                                    fg=_FAINT, bg=_BG)
        self._uptime_lbl.pack(side="right")

        # Last-activity line + Details drawer ─────────────────────────────────
        act = tk.Frame(self._root, bg=_BG)
        act.pack(side="bottom", fill="x", padx=24, pady=(0, 2))
        self._last_lbl = tk.Label(act, text="Waiting for the first phone…",
                                  font=self._f_small, fg=_DIM, bg=_BG,
                                  anchor="w")
        self._last_lbl.pack(side="left", fill="x", expand=True)
        self._details_btn = tk.Label(act, text="Details ▸", font=self._f_small,
                                     fg=_FAINT, bg=_BG, cursor="hand2")
        self._details_btn.pack(side="right")
        self._details_btn.bind("<Button-1>", lambda e: self._toggle_details())

        self._details_card = _Card(self._root, pad=12)
        self._log_txt = tk.Text(self._details_card.inner, bg=_CARD, fg=_DIM,
                                bd=0, font=self._f_small, wrap="word",
                                state="disabled", cursor="arrow", height=8,
                                selectbackground="#2a2a33",
                                highlightthickness=0)
        self._log_txt.pack(fill="both", expand=True)
        for tag, color in [("ts", _FAINT), ("info", _DIM), ("ok", _GREEN),
                           ("warn", _YELLOW), ("err", _RED),
                           ("accent", _ACCENT)]:
            self._log_txt.tag_configure(tag, foreground=color)

        self._redraw_players()

    # ── Behaviour (Tk thread only) ────────────────────────────────────────────

    def _toggle_details(self) -> None:
        self._details_open = not self._details_open
        if self._details_open:
            self._details_btn.config(text="Details ▾", fg=_DIM)
            self._details_card.pack(side="bottom", fill="x",
                                    padx=20, pady=(0, 4))
        else:
            self._details_btn.config(text="Details ▸", fg=_FAINT)
            self._details_card.pack_forget()

    def _open_drop(self) -> None:
        try:
            self._drop_dir.mkdir(parents=True, exist_ok=True)
            os.startfile(str(self._drop_dir))   # noqa: S606 — local folder open
        except Exception:
            pass

    def _add_event(self, ts: str, text: str, sev: str) -> None:
        self._events.append((ts, text, sev))
        del self._events[:-_MAX_LOG]

        mark = {"ok": "✓ ", "warn": "↻ ", "err": "✕ "}.get(sev, "")
        line = mark + text
        if len(line) > 64:
            line = line[:63] + "…"
        self._last_lbl.config(
            text=line,
            fg={"ok": _GREEN, "warn": _YELLOW, "err": _RED}.get(sev, _DIM))

        t = self._log_txt
        t.config(state="normal")
        t.insert("end", f"{ts}  ", ("ts",))
        t.insert("end", text + "\n", (sev,))
        lines = int(t.index("end-1c").split(".")[0])
        if lines > _MAX_LOG:
            t.delete("1.0", f"{lines - _MAX_LOG}.0")
        t.see("end")
        t.config(state="disabled")

    def _redraw_status(self) -> None:
        up = int((datetime.now() - self._start).total_seconds())
        h, m = divmod(up // 60, 60)
        self._uptime_lbl.config(
            text=f"running {h} h {m:02d} min" if h else f"running {m} min")
        if self._fw_ok:
            self._fw_lbl.pack_forget()
        else:
            self._fw_lbl.config(
                text="One-time step: run once as Administrator so\n"
                     "Windows lets phones connect.")
            self._fw_lbl.pack(fill="x", pady=(8, 0))

    def _redraw_players(self) -> None:
        active = [p for p in self._slots if p.connected or p.grace]
        self._count_lbl.config(
            text=f"{sum(1 for p in self._slots if p.connected)} of {self._max}")

        for child in self._players_box.winfo_children():
            child.destroy()

        if not active:
            tk.Label(self._players_box,
                     text="None yet — they appear here the moment "
                          "they connect.",
                     font=self._f_small, fg=_FAINT, bg=_CARD,
                     anchor="w").pack(fill="x")
            return

        for i, p in enumerate(self._slots):
            if not (p.connected or p.grace):
                continue
            row = tk.Frame(self._players_box, bg=_CARD)
            row.pack(fill="x", pady=2)
            if p.connected:
                tk.Label(row, text="●", font=self._f_small, fg=_GREEN,
                         bg=_CARD).pack(side="left")
                name = p.phone or p.ip or "Phone"
                tk.Label(row, text=f"  {name}", font=self._f_body, fg=_TEXT,
                         bg=_CARD).pack(side="left")
                tk.Label(row, text=self._ago(p.since), font=self._f_small,
                         fg=_FAINT, bg=_CARD).pack(side="right")
            else:
                tk.Label(row, text="↻", font=self._f_small, fg=_YELLOW,
                         bg=_CARD).pack(side="left")
                tk.Label(row, text=f"  {p.phone or 'Phone'} — coming back…",
                         font=self._f_body, fg=_DIM, bg=_CARD).pack(side="left")

    @staticmethod
    def _ago(since: Optional[datetime]) -> str:
        if since is None:
            return ""
        secs = int((datetime.now() - since).total_seconds())
        if secs < 60:
            return "just now"
        m = secs // 60
        if m < 60:
            return f"{m} min"
        return f"{m // 60} h {m % 60:02d} min"
