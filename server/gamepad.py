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

class _INPUT_UNION(ctypes.Union):
    _fields_ = [("mi", _MOUSEINPUT)]

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
