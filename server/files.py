"""
files.py — File Transfer HTTP server (port 8768).

Phone ⇄ PC file drop. Everything lands in / is served from a single shared
folder: ~/Downloads/TouchPlay. Stdlib only (http.server) so it adds zero
pip dependencies and runs in a daemon thread next to the asyncio servers.

Endpoints (both ends are ours, so the protocol stays dead simple):
  GET  /info               → {"app": "touchplay", "files_port": 8768}
  GET  /files              → [{"name", "size", "mtime"}, …] newest first
  GET  /download?name=X    → raw file bytes (attachment)
  GET  /thumb?name=X&s=128 → JPEG thumbnail for images/videos (404 otherwise)
  POST /upload?name=X      → raw body saved into the drop folder
"""

import io
import json
import threading
import time
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs, quote

FILES_PORT = 8768
DROP_DIR = Path.home() / "Downloads" / "TouchPlay"

# Optional UI log hook — set by main.py.
_log = lambda msg: None

def set_logger(fn) -> None:
    global _log
    _log = fn


def _safe_name(raw: str) -> str:
    """Strip any path component — uploads can only create files IN the drop dir."""
    name = Path(raw.replace("\\", "/")).name.strip()
    return name or f"file-{int(time.time())}"


_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
_VIDEO_EXTS = {".mp4", ".mkv", ".avi", ".webm", ".mov"}

# (name, mtime, size) → JPEG bytes; tiny LRU so list scrolling stays instant.
_thumb_cache: "OrderedDict[tuple, bytes]" = OrderedDict()
_thumb_lock = threading.Lock()
_THUMB_CACHE_MAX = 256


def _make_thumb(path: Path, edge: int) -> bytes | None:
    """Downscaled JPEG for an image/video file, or None if not thumbnail-able."""
    ext = path.suffix.lower()
    try:
        if ext in _IMAGE_EXTS:
            from PIL import Image, ImageOps
            with Image.open(path) as im:
                im = ImageOps.exif_transpose(im)
                im.thumbnail((edge, edge))
                if im.mode not in ("RGB", "L"):
                    im = im.convert("RGB")
                buf = io.BytesIO()
                im.save(buf, "JPEG", quality=72)
                return buf.getvalue()
        if ext in _VIDEO_EXTS:
            import cv2
            cap = cv2.VideoCapture(str(path))
            ok, frame = cap.read()
            cap.release()
            if not ok or frame is None:
                return None
            h, w = frame.shape[:2]
            scale = edge / max(h, w)
            if scale < 1:
                frame = cv2.resize(frame, (max(2, int(w * scale)),
                                           max(2, int(h * scale))))
            ok, enc = cv2.imencode(".jpg", frame,
                                   [int(cv2.IMWRITE_JPEG_QUALITY), 72])
            return enc.tobytes() if ok else None
    except Exception:
        return None
    return None


def _unique_path(name: str) -> Path:
    """photo.jpg → photo (2).jpg if it already exists."""
    p = DROP_DIR / name
    if not p.exists():
        return p
    stem, suffix = p.stem, p.suffix
    for i in range(2, 1000):
        q = DROP_DIR / f"{stem} ({i}){suffix}"
        if not q.exists():
            return q
    return DROP_DIR / f"{stem}-{int(time.time())}{suffix}"


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # Silence the default stderr access log — the rich dashboard owns the console.
    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)

        if url.path == "/info":
            self._json({"app": "touchplay", "files_port": FILES_PORT})
            return

        if url.path == "/files":
            DROP_DIR.mkdir(parents=True, exist_ok=True)
            entries = []
            for p in DROP_DIR.iterdir():
                if p.is_file() and not p.name.startswith((".", "~")):
                    st = p.stat()
                    entries.append({
                        "name": p.name,
                        "size": st.st_size,
                        "mtime": int(st.st_mtime),
                    })
            entries.sort(key=lambda e: e["mtime"], reverse=True)
            self._json(entries)
            return

        if url.path == "/thumb":
            qs = parse_qs(url.query)
            name = _safe_name(qs.get("name", [""])[0])
            try:
                edge = max(32, min(512, int(qs.get("s", ["128"])[0])))
            except ValueError:
                edge = 128
            path = DROP_DIR / name
            if not path.is_file():
                self._json({"error": "not found"}, 404)
                return
            st = path.stat()
            key = (name, int(st.st_mtime), st.st_size, edge)
            with _thumb_lock:
                data = _thumb_cache.get(key)
                if data is not None:
                    _thumb_cache.move_to_end(key)
            if data is None:
                data = _make_thumb(path, edge)
                if data is None:
                    self._json({"error": "no thumbnail"}, 404)
                    return
                with _thumb_lock:
                    _thumb_cache[key] = data
                    while len(_thumb_cache) > _THUMB_CACHE_MAX:
                        _thumb_cache.popitem(last=False)
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "max-age=3600")
            self.end_headers()
            try:
                self.wfile.write(data)
            except (ConnectionError, BrokenPipeError):
                pass
            return

        if url.path == "/download":
            name = _safe_name(parse_qs(url.query).get("name", [""])[0])
            path = DROP_DIR / name
            if not path.is_file():
                self._json({"error": "not found"}, 404)
                return
            size = path.stat().st_size
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition",
                             f"attachment; filename*=UTF-8''{quote(name)}")
            self.end_headers()
            try:
                with path.open("rb") as f:
                    while chunk := f.read(64 * 1024):
                        self.wfile.write(chunk)
                _log(f"[cyan]⇱[/] sent [bold]{name}[/] to phone")
            except (ConnectionError, BrokenPipeError):
                pass
            return

        self._json({"error": "unknown endpoint"}, 404)

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/upload":
            self._json({"error": "unknown endpoint"}, 404)
            return

        name = _safe_name(parse_qs(url.query).get("name", [""])[0])
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self._json({"error": "empty body"}, 400)
            return

        DROP_DIR.mkdir(parents=True, exist_ok=True)
        dest = _unique_path(name)
        remaining = length
        try:
            with dest.open("wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(64 * 1024, remaining))
                    if not chunk:
                        break
                    f.write(chunk)
                    remaining -= len(chunk)
        except (ConnectionError, BrokenPipeError):
            dest.unlink(missing_ok=True)
            return
        if remaining > 0:                       # truncated upload — discard
            dest.unlink(missing_ok=True)
            self._json({"error": "incomplete upload"}, 400)
            return

        _log(f"[cyan]⇲[/] received [bold]{dest.name}[/] from phone "
             f"({length // 1024} KB) → Downloads\\TouchPlay")
        self._json({"ok": True, "name": dest.name})


def start_file_server() -> None:
    """Start the file server in a daemon thread. Never raises."""
    def run():
        try:
            DROP_DIR.mkdir(parents=True, exist_ok=True)
            srv = ThreadingHTTPServer(("0.0.0.0", FILES_PORT), _Handler)
            srv.daemon_threads = True
            srv.serve_forever()
        except Exception as e:
            _log(f"[red]File server failed: {e}[/]")

    threading.Thread(target=run, name="touchplay-files", daemon=True).start()
