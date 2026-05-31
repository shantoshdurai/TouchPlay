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

# Guide button — not all vgamepad builds expose it
try:
    BUTTON_MAP["GUIDE"] = vg.XUSB_BUTTON.XUSB_GAMEPAD_GUIDE
except AttributeError:
    pass

_MOVE  = 0x0001
_LDN   = 0x0002
_LUP   = 0x0004
_RDN   = 0x0008
_RUP   = 0x0010

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


def mouse_move(dx: int, dy: int):
    ctypes.windll.user32.mouse_event(_MOVE, dx, dy, 0, 0)


def mouse_click(button: str = "left"):
    if button == "left":
        ctypes.windll.user32.mouse_event(_LDN, 0, 0, 0, 0)
        ctypes.windll.user32.mouse_event(_LUP, 0, 0, 0, 0)
    elif button == "right":
        ctypes.windll.user32.mouse_event(_RDN, 0, 0, 0, 0)
        ctypes.windll.user32.mouse_event(_RUP, 0, 0, 0, 0)
