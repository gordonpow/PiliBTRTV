"""Generate TV banner (320x180) for PiliBTRTV: logo on the left, text on the right."""
from PIL import Image, ImageDraw, ImageFont

W, H = 320, 180
SCALE = 4  # supersample for smoother edges
OUTS = [
    "android/app/src/main/res/drawable/banner.png",
    "android/app/src/main/res/drawable-xhdpi/banner.png",
]
LOGO = "assets/icons/pilibtr_logo_fg.png"
FONTS = ["C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]
TEXT = "PiliBTRTV"

w, h = W * SCALE, H * SCALE
img = Image.new("RGBA", (w, h), (255, 255, 255, 255))

pad = 20 * SCALE
logo_size = h - 2 * pad
logo = Image.open(LOGO).convert("RGBA").resize((logo_size, logo_size), Image.LANCZOS)
img.alpha_composite(logo, (pad, pad))

gap = 12 * SCALE
avail = w - pad - (pad + logo_size + gap)
font = None
for path in FONTS:
    try:
        size = 60 * SCALE
        while size > 8:
            f = ImageFont.truetype(path, size)
            if f.getbbox(TEXT)[2] - f.getbbox(TEXT)[0] <= avail:
                font = f
                break
            size -= SCALE
        if font:
            break
    except OSError:
        continue
draw = ImageDraw.Draw(img)
l, t, r, b = draw.textbbox((0, 0), TEXT, font=font)
x = pad + logo_size + gap - l
y = (h - (b - t)) // 2 - t
draw.text((x, y), TEXT, font=font, fill=(0x21, 0x21, 0x21, 255))

out = img.resize((W, H), Image.LANCZOS)
for p in OUTS:
    out.save(p)
    print("wrote", p, out.size)
