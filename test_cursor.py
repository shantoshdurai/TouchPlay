import mss
from PIL import Image, ImageDraw
import ctypes
import time

class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

def test():
    with mss.mss() as sct:
        monitor = sct.monitors[1]
        shot = sct.grab(monitor)
        img = Image.frombytes("RGB", shot.size, shot.rgb)
        
        pt = POINT()
        ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
        
        # Monitor offsets
        mx = pt.x - monitor["left"]
        my = pt.y - monitor["top"]
        
        draw = ImageDraw.Draw(img)
        draw.ellipse([mx-5, my-5, mx+5, my+5], fill="white", outline="black")
        
        print("Mouse at:", mx, my)
        
test()
