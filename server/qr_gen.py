import socket
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', line_buffering=True)


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


def generate_qr(port: int = 8765) -> str:
    """Legacy wrapper — still usable but main.py now calls get_best_ip() directly."""
    return get_best_ip()
