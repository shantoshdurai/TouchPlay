import socket
import qrcode


def get_best_ip() -> str:
    """Return USB tethering IP (192.168.42.x) if available, else best LAN IP."""
    candidates = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            addr = info[4][0]
            if addr.startswith("192.168.42."):
                return addr  # USB tethering — highest priority
            if not addr.startswith("127.") and ":" not in addr:
                candidates.append(addr)
    except Exception:
        pass

    # Fallback: connect to external address and read local side
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
    """Generate qr.png for ws://<ip>:<port>, return the IP string."""
    ip = get_best_ip()
    url = f"ws://{ip}:{port}"

    # The QR code is printed directly to the terminal

    # Print the QR code directly to the terminal
    import sys
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    
    qr = qrcode.QRCode()
    qr.add_data(url)
    qr.make()
    
    print(f"\n[ SCAN THIS QR CODE OR TYPE THE IP: {ip} ]\n")
    qr.print_ascii()
    print("\n")

    return ip
