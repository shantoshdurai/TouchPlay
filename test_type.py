import ctypes

class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk",         ctypes.c_ushort),
        ("wScan",       ctypes.c_ushort),
        ("dwFlags",     ctypes.c_ulong),
        ("time",        ctypes.c_ulong),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]

class _INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", _KEYBDINPUT), ("pad", ctypes.c_ulong * 6)]

class _INPUT(ctypes.Structure):
    _anonymous_ = ("_input",)
    _fields_    = [("type", ctypes.c_ulong), ("_input", _INPUT_UNION)]

def type_string(text: str):
    for c in text:
        inp = _INPUT(type=1)
        inp.ki.wVk = 0
        inp.ki.wScan = ord(c)
        inp.ki.dwFlags = 0x0004 # KEYEVENTF_UNICODE
        ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))
        
        inp.ki.dwFlags = 0x0004 | 0x0002 # KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
        ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))

import time
time.sleep(2) # time to focus
type_string("Hello World!")
