from PIL import Image, ImageDraw

size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Polished modern cyan background
d.rounded_rectangle((40, 120, 984, 904), radius=200, fill=(0, 190, 240))

# D-pad perfectly centered on the left
center_y = 512
left_cx = 300
d_w = 160
d.rounded_rectangle((left_cx - d_w/2, center_y - d_w*1.5/2, left_cx + d_w/2, center_y + d_w*1.5/2), radius=20, fill=(255, 255, 255))
d.rounded_rectangle((left_cx - d_w*1.5/2, center_y - d_w/2, left_cx + d_w*1.5/2, center_y + d_w/2), radius=20, fill=(255, 255, 255))

# Buttons on the right
right_cx = 724
btn_r = 65
spacing = 130
d.ellipse((right_cx - btn_r, center_y + spacing - btn_r, right_cx + btn_r, center_y + spacing + btn_r), fill=(255, 255, 255)) # A
d.ellipse((right_cx - spacing - btn_r, center_y - btn_r, right_cx - spacing + btn_r, center_y + btn_r), fill=(255, 255, 255)) # X
d.ellipse((right_cx + spacing - btn_r, center_y - btn_r, right_cx + spacing + btn_r, center_y + btn_r), fill=(255, 255, 255)) # B
d.ellipse((right_cx - btn_r, center_y - spacing - btn_r, right_cx + btn_r, center_y - spacing + btn_r), fill=(255, 255, 255)) # Y

# Analog sticks (dark blue/grey)
stick_r = 90
d.ellipse((left_cx - stick_r, 260 - stick_r, left_cx + stick_r, 260 + stick_r), fill=(20, 25, 40))
d.ellipse((right_cx - stick_r - 200, 764 - stick_r, right_cx + stick_r - 200, 764 + stick_r), fill=(20, 25, 40))

img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
img.save('c:/New folder/controller/app_icon.png')

# Create proper ICO with explicitly scaled images
icon_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
img.save('c:/New folder/controller/app_icon.ico', format='ICO', sizes=icon_sizes)
