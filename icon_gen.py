from PIL import Image, ImageDraw

img = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# A sleek rounded rectangle background (cyan)
d.rounded_rectangle((10, 30, 246, 226), radius=50, fill=(0, 212, 255))

# DPAD (left)
d.rectangle((50, 110, 90, 150), fill=(255, 255, 255))
d.rectangle((30, 130, 110, 170), fill=(255, 255, 255))

# Buttons (right)
d.ellipse((180, 140, 210, 170), fill=(255, 255, 255)) # A
d.ellipse((150, 110, 180, 140), fill=(255, 255, 255)) # X
d.ellipse((210, 110, 240, 140), fill=(255, 255, 255)) # B
d.ellipse((180, 80, 210, 110), fill=(255, 255, 255))  # Y

# Sticks
d.ellipse((50, 60, 90, 100), fill=(30, 30, 40))
d.ellipse((120, 140, 160, 180), fill=(30, 30, 40))

img.save('c:/New folder/controller/app_icon.ico', format='ICO', sizes=[(256, 256), (128, 128), (64, 64), (32, 32)])
