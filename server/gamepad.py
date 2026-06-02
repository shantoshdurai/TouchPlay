import ctypes
import vgamepad as vg

BUTTON_MAP = {
    "A":          vg.XUSB_BUTTON.XUSB_GAMEPAD_A,
    "B":          vg.XUSB_BUTTON.XUSB_GAMEPAD_B,
    "X":          vg.XUSB_BUTTON.XUSB_GAMEPAD_X,
    "Y":          vg.XUSB_BUTTON.XUSB_GAMEPAD_Y,
    "LB":         vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER,
    "RB":         vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER,
    "START":      vg.XUSB_BUTTON.XUSB_GAMEPAD_START,
    "BACK":       vg.XUSB_BUTTON.XUSB_GAMEPAD_BACK,
    "DPAD_UP":    vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_UP,
    "DPAD_DOWN":  vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_DOWN,
    "DPAD_LEFT":  vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_LEFT,
    "DPAD_RIGHT": vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_RIGHT,
    "LS":         vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_THUMB,
    "RS":         vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_THUMB,
}

try:
    BUTTON_MAP["GUIDE"] = vg.XUSB_BUTTON.XUSB_GAMEPAD_GUIDE
except AttributeError:
    pass


def _axis(v: float) -> int:
    return int(max(-1.0, min(1.0, v)) * 32767)

def _trig(v: float) -> int:
    return int(max(0.0, min(1.0, v)) * 255)


class GamepadController:
    def __init__(self):
        self.gamepad = vg.VX360Gamepad()
        self.gamepad.update()

    def press_button(self, name: str):
        btn = BUTTON_MAP.get(name)
        if btn is not None:
            self.gamepad.press_button(button=btn)

    def release_button(self, name: str):
        btn = BUTTON_MAP.get(name)
        if btn is not None:
            self.gamepad.release_button(button=btn)

    def set_left_stick(self, x: float, y: float):
        self.gamepad.left_joystick(x_value=_axis(x), y_value=_axis(y))

    def set_right_stick(self, x: float, y: float):
        self.gamepad.right_joystick(x_value=_axis(x), y_value=_axis(y))

    def set_left_trigger(self, value: float):
        self.gamepad.left_trigger(value=_trig(value))

    def set_right_trigger(self, value: float):
        self.gamepad.right_trigger(value=_trig(value))

    def update(self):
        self.gamepad.update()

    def reset(self):
        """Release everything — buttons up, sticks centered, triggers at 0 —
        and flush immediately. Called on connect/disconnect so a held input
        (e.g. throttle) can never get 'stuck' when the phone drops."""
        self.gamepad.reset()
        self.gamepad.update()


# ── Mouse injection via SendInput ─────────────────────────────────────────────
# SendInput generates proper Raw Input events (WM_INPUT) that games read
# even in controller mode. The old mouse_event() API skips Raw Input.

class _MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx",          ctypes.c_long),
        ("dy",          ctypes.c_long),
        ("mouseData",   ctypes.c_ulong),
        ("dwFlags",     ctypes.c_ulong),
        ("time",        ctypes.c_ulong),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]

class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk",         ctypes.c_ushort),
        ("wScan",       ctypes.c_ushort),
        ("dwFlags",     ctypes.c_ulong),
        ("time",        ctypes.c_ulong),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]

class _INPUT_UNION(ctypes.Union):
    _fields_ = [("mi", _MOUSEINPUT), ("ki", _KEYBDINPUT)]

class _INPUT(ctypes.Structure):
    _anonymous_ = ("_input",)
    _fields_    = [("type", ctypes.c_ulong), ("_input", _INPUT_UNION)]

_MOVE  = 0x0001
_LDN   = 0x0002
_LUP   = 0x0004
_RDN   = 0x0008
_RUP   = 0x0010

def _send(flags: int, dx: int = 0, dy: int = 0) -> None:
    inp            = _INPUT(type=0)   # INPUT_MOUSE = 0
    inp.mi.dx      = dx
    inp.mi.dy      = dy
    inp.mi.dwFlags = flags
    ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))


def mouse_move(dx: int, dy: int) -> None:
    if dx == 0 and dy == 0:
        return
    _send(_MOVE, dx, dy)


def mouse_click(button: str = "left") -> None:
    if button == "left":
        _send(_LDN); _send(_LUP)
    elif button == "right":
        _send(_RDN); _send(_RUP)


# Track held keys / mouse buttons so we can release them all on reset or
# disconnect — stops a held W or mouse button from sticking if the phone
# backgrounds or drops mid-press.
_keys_down = set()
_mouse_held = set()

def mouse_down(button: str = "left") -> None:
    _mouse_held.add(button)
    _send(_LDN if button == "left" else _RDN)

def mouse_up(button: str = "left") -> None:
    _mouse_held.discard(button)
    _send(_LUP if button == "left" else _RUP)


# ── Keyboard injection via SendInput ──────────────────────────────────────────
# Lets custom layouts bind buttons to real keys (WASD, Space, E, Shift, …) so a
# touch layout can drive keyboard+mouse games, not just gamepad ones.

_KEYUP = 0x0002

_VK = {
    "SPACE": 0x20, "ENTER": 0x0D, "RETURN": 0x0D, "ESC": 0x1B, "ESCAPE": 0x1B,
    "TAB": 0x09, "SHIFT": 0x10, "CTRL": 0x11, "CONTROL": 0x11, "ALT": 0x12,
    "BACKSPACE": 0x08, "DEL": 0x2E, "DELETE": 0x2E, "CAPS": 0x14,
    "UP": 0x26, "DOWN": 0x28, "LEFT": 0x25, "RIGHT": 0x27,
    "F1": 0x70, "F2": 0x71, "F3": 0x72, "F4": 0x73, "F5": 0x74, "F6": 0x75,
    "F7": 0x76, "F8": 0x77, "F9": 0x78, "F10": 0x79, "F11": 0x7A, "F12": 0x7B,
}
_VK_PUNCT = {";": 0xBA, "=": 0xBB, ",": 0xBC, "-": 0xBD, ".": 0xBE, "/": 0xBF,
             "`": 0xC0, "[": 0xDB, "\\": 0xDC, "]": 0xDD, "'": 0xDE}


def _vk(name: str) -> int:
    if not name:
        return 0
    up = name.upper()
    if up in _VK:
        return _VK[up]
    if len(name) == 1:
        c = up
        if "A" <= c <= "Z" or "0" <= c <= "9":
            return ord(c)
        return _VK_PUNCT.get(name, 0)
    return 0


def _send_key(vk: int, key_up: bool) -> None:
    if vk == 0:
        return
    inp            = _INPUT(type=1)   # INPUT_KEYBOARD = 1
    inp.ki.wVk     = vk
    inp.ki.dwFlags = _KEYUP if key_up else 0
    ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))


def key_down(name: str) -> None:
    vk = _vk(name)
    if vk:
        _keys_down.add(name.upper())
        _send_key(vk, False)

def key_up(name: str) -> None:
    vk = _vk(name)
    if vk:
        _keys_down.discard(name.upper())
        _send_key(vk, True)


def release_all_inputs() -> None:
    """Release every held key + mouse button. Called on reset/disconnect."""
    for k in list(_keys_down):
        _send_key(_vk(k), True)
    _keys_down.clear()
    for b in list(_mouse_held):
        _send(_LUP if b == "left" else _RUP)
    _mouse_held.clear()
