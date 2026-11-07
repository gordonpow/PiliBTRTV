"""產生 PiliBTR TV 開機動畫 assets/icons/startup.mp4（無文字）。
用法: python tool/gen_splash.py [frames_dir]
多條粉紫光線從邊緣匯聚到中心，logo 淡入放大並帶柔光，停留後淡出到深色背景。
"""
import math, os, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter
import imageio_ffmpeg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, 'assets', 'icons', 'pilibtr_logo_fg.png')
OUT = os.path.join(ROOT, 'assets', 'icons', 'startup.mp4')
FRAMES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), 'splash_frames')

W, H, FPS, DUR = 1920, 1080, 30, 2.4
N = int(round(FPS * DUR))
BG = np.array([18, 18, 18], np.float32)
PINK = np.array([225, 92, 175], np.float32)
PURPLE = np.array([150, 90, 232], np.float32)
LOGO_SIZE = 560

def ease_out(t): return 1 - (1 - t) ** 3
def ease_io(t): return t * t * (3 - 2 * t)
def clamp(t): return min(1.0, max(0.0, t))

# 半解析度畫光線，之後放大（光線本來就是柔邊）
SW, SH = W // 2, H // 2
yy, xx = np.mgrid[0:SH, 0:SW].astype(np.float32)
px, py = (xx - SW / 2) * 2, (yy - SH / 2) * 2

rng = np.random.default_rng(7)
N_STREAK = 16
streaks = []
for i in range(N_STREAK):
    ang = 2 * math.pi * (i + rng.uniform(-0.25, 0.25)) / N_STREAK
    streaks.append(dict(
        ang=ang, delay=rng.uniform(0, 0.25), dur=rng.uniform(0.7, 0.95),
        tail=rng.uniform(220, 420), width=rng.uniform(1.6, 2.6),
        col=PINK + (PURPLE - PINK) * rng.uniform(0, 1)))

def streaks_layer(t):
    img = np.zeros((SH, SW, 3), np.float32)
    for s in streaks:
        k = clamp((t - s['delay']) / s['dur'])
        if k <= 0 or k >= 1: continue
        r0 = 1100.0
        head = r0 * (1 - ease_io(k) ** 0.9) + 40
        ux, uy = math.cos(s['ang']), math.sin(s['ang'])
        along = px * ux + py * uy
        perp = -px * uy + py * ux
        d = along - head
        tail = s['tail'] * (0.4 + 0.6 * (1 - k))
        inten = np.clip(1 - d / tail, 0, 1) ** 1.6 * (d >= 0)
        inten *= np.exp(-(perp / s['width']) ** 2)
        inten *= np.clip(d / 6 + 1, 0, 1)
        fade = clamp(k / 0.15) * clamp((1 - k) / 0.25)
        img += inten[..., None] * s['col'] * fade * 1.1
    return img

logo = Image.open(LOGO).convert('RGBA')
radial_d = np.hypot(*np.mgrid[0:H, 0:W].astype(np.float32) - np.array([H / 2, W / 2], np.float32)[:, None, None])

def paste_logo(canvas, scale, alpha):
    sz = max(2, int(LOGO_SIZE * scale))
    lg = logo.resize((sz, sz), Image.LANCZOS)
    a = np.asarray(lg.split()[3], np.float32) / 255
    rgb = np.asarray(lg.convert('RGB'), np.float32)
    # 柔光：模糊後的 alpha，著粉紫色
    big = Image.new('L', (W, H), 0)
    big.paste(lg.split()[3], ((W - sz) // 2, (H - sz) // 2))
    glow = np.asarray(big.filter(ImageFilter.GaussianBlur(45)), np.float32) / 255
    gcol = (PINK + PURPLE) / 2
    canvas += glow[..., None] * gcol * 0.9 * alpha
    x0, y0 = (W - sz) // 2, (H - sz) // 2
    reg = canvas[y0:y0 + sz, x0:x0 + sz]
    aa = (a * alpha)[..., None]
    canvas[y0:y0 + sz, x0:x0 + sz] = reg * (1 - aa) + rgb * aa

def render(i):
    t = i / FPS
    canvas = np.tile(BG, (H, W, 1))
    # 背景中心微暈
    canvas += (np.exp(-(radial_d / 700) ** 2) * 10)[..., None] * np.array([1, 0.5, 1.2], np.float32)
    sl = streaks_layer(t)
    sl = np.asarray(Image.fromarray(np.clip(sl, 0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32)
    canvas += sl
    # 匯聚閃光
    flash = math.exp(-((t - 0.95) / 0.18) ** 2)
    canvas += (np.exp(-(radial_d / 260) ** 2) * 70 * flash)[..., None] * np.array([1, 0.55, 1], np.float32)
    k = clamp((t - 0.85) / 0.6)
    if k > 0:
        paste_logo(canvas, 0.78 + 0.22 * ease_out(k), ease_out(clamp((t - 0.85) / 0.45)))
    out = clamp((t - 2.0) / 0.4)
    if out > 0:
        canvas = canvas * (1 - ease_io(out)) + BG * ease_io(out)
    # 抖動雜訊，減少暗部漸層的色帶
    canvas += np.random.default_rng(i).uniform(-1.2, 1.2, (H, W, 1)).astype(np.float32)
    return Image.fromarray(np.clip(canvas + 0.5, 0, 255).astype(np.uint8))

if os.path.isdir(FRAMES): shutil.rmtree(FRAMES)
os.makedirs(FRAMES)
for i in range(N):
    render(i).save(os.path.join(FRAMES, f'f{i:04d}.png'))
tmp = OUT + '.tmp.mp4'
subprocess.check_call([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-framerate', str(FPS),
    '-i', os.path.join(FRAMES, 'f%04d.png'), '-an', '-c:v', 'libx264', '-profile:v', 'high',
    '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart', tmp])
os.replace(tmp, OUT)
print('wrote', OUT)
