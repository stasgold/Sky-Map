# Generates the Star Nav app icon (original artwork, GPL-3.0-or-later).
# Usage: python3 tools/make_icon.py StellarNavigator/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow. Renders at 4x and downsamples for clean edges.
#
# A schematic star chart: an azimuthal grid with a bold degree ring, a scatter of
# unconnected stars sized by brightness, and a large compass star at the centre.
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 4
S = 1024 * SS
C = S / 2

GOLD = (255, 204, 120)
CYAN = (110, 220, 255)
GRID = (130, 190, 255)
WHITE = (245, 248, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def soft_disc(center, radius, color, alpha, blur):
    """A blurred disc of solid colour: only the alpha mask is blurred, so edges never darken."""
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([center[0] - radius, center[1] - radius,
                                  center[0] + radius, center[1] + radius], fill=alpha)
    layer = Image.new("RGBA", (S, S), color + (0,))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return layer


def glow_of(layer, color, blur, strength=1.0):
    g = Image.new("RGBA", (S, S), color + (0,))
    g.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(min(255, v * strength))))
    return g


# --- Background: indigo night with two soft nebula washes ---------------------------------
grad = Image.new("RGBA", (1, 256))
for y in range(256):
    grad.putpixel((0, y), lerp((22, 20, 78, 255), (6, 10, 38, 255), y / 255))
img = grad.resize((S, S), Image.BICUBIC)
img = Image.alpha_composite(img, soft_disc((S * 0.26, S * 0.30), S * 0.36, (120, 70, 210), 110, S * 0.14))
img = Image.alpha_composite(img, soft_disc((S * 0.80, S * 0.74), S * 0.34, (30, 130, 200), 90, S * 0.14))
img = Image.alpha_composite(img, soft_disc((C, C), S * 0.30, (70, 90, 200), 60, S * 0.12))

random.seed(4)
dust = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dust)
for _ in range(90):
    x, y = random.random() * S, random.random() * S
    r = random.choice([1.5, 2, 2, 3]) * SS
    dd.ellipse([x - r, y - r, x + r, y + r], fill=WHITE + (random.randint(70, 170),))
img = Image.alpha_composite(img, dust.filter(ImageFilter.GaussianBlur(SS * 0.5)))

# --- Chart grid ------------------------------------------------------------------------
R = S * 0.415
grid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(grid)
lw = int(3.2 * SS)
for frac, a, w in ((1.0, 235, int(8 * SS)), (0.68, 95, lw), (0.36, 80, lw)):
    r = R * frac
    g.ellipse([C - r, C - r, C + r, C + r], outline=GRID + (a,), width=w)
for deg in range(0, 360, 30):
    t = math.radians(deg)
    g.line([(C, C), (C + R * math.cos(t), C + R * math.sin(t))], fill=GRID + (55,), width=int(2.4 * SS))
# Crosshair through the chart, reaching past the rim.
ext = R * 1.12
g.line([(C - ext, C), (C + ext, C)], fill=GRID + (120,), width=lw)
g.line([(C, C - ext), (C, C + ext)], fill=GRID + (120,), width=lw)
# Degree ring (the azimuth scale): ticks every 5°, longer every 30°, drawn bold.
for deg in range(0, 360, 5):
    t = math.radians(deg)
    major = deg % 30 == 0
    r0 = R
    r1 = R * (1.075 if major else 1.04)
    g.line([(C + r0 * math.cos(t), C + r0 * math.sin(t)), (C + r1 * math.cos(t), C + r1 * math.sin(t))],
           fill=GRID + (240 if major else 170,), width=int((8 if major else 4.5) * SS))
img = Image.alpha_composite(img, glow_of(grid, GRID, SS * 6, 0.6))
img = Image.alpha_composite(img, grid)


# --- Chart stars: unconnected dots sized by brightness (star-chart convention) ---------
# (x, y) as fractions of the icon, magnitude-like size class 1 (brightest) .. 4, colour.
CHART_STARS = [
    (0.30, 0.27, 1, GOLD), (0.42, 0.21, 3, WHITE), (0.22, 0.38, 2, WHITE), (0.36, 0.38, 4, WHITE),
    (0.70, 0.25, 2, CYAN), (0.79, 0.36, 3, WHITE), (0.62, 0.17, 4, WHITE),
    (0.26, 0.68, 2, WHITE), (0.37, 0.79, 3, GOLD), (0.19, 0.58, 4, WHITE),
    (0.72, 0.73, 1, CYAN), (0.63, 0.83, 3, WHITE), (0.82, 0.63, 4, WHITE), (0.58, 0.66, 4, WHITE),
]
RADIUS_BY_CLASS = {1: 0.0145, 2: 0.0110, 3: 0.0080, 4: 0.0058}

dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dots)
for fx, fy, cls, colour in CHART_STARS:
    x, y, r = S * fx, S * fy, S * RADIUS_BY_CLASS[cls]
    dd.ellipse([x - r, y - r, x + r, y + r], fill=colour + (255,))
    if cls <= 2:
        dd.ellipse([x - r * 1.8, y - r * 1.8, x + r * 1.8, y + r * 1.8], outline=colour + (140,), width=int(1.8 * SS))
img = Image.alpha_composite(img, glow_of(dots, WHITE, SS * 10, 0.9))
img = Image.alpha_composite(img, dots)

# --- Compass star at the chart centre -------------------------------------------------
def point(cx, cy, ang, length, hw):
    a = math.radians(ang)
    tip = (cx + length * math.cos(a), cy - length * math.sin(a))
    l = (cx + hw * math.cos(a + math.pi / 2), cy - hw * math.sin(a + math.pi / 2))
    r = (cx + hw * math.cos(a - math.pi / 2), cy - hw * math.sin(a - math.pi / 2))
    return [(cx, cy), l, tip], [(cx, cy), tip, r]


cr = S * 0.21
img = Image.alpha_composite(img, soft_disc((C, C), cr * 0.75, CYAN, 120, cr * 0.45))
comp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(comp)
for k in range(4):
    a, b = point(C, C, 45 + 90 * k, cr * 0.55, cr * 0.10)
    cd.polygon(a, fill=(150, 200, 255, 255)); cd.polygon(b, fill=(80, 130, 220, 255))
for k in range(4):
    length = cr * (1.0 if k == 1 else 0.82)
    a, b = point(C, C, 90 * k, length, cr * 0.15)
    cd.polygon(a, fill=WHITE + (255,)); cd.polygon(b, fill=CYAN + (255,))
img = Image.alpha_composite(img, glow_of(comp, CYAN, SS * 12, 0.5))
img = Image.alpha_composite(img, comp)
img = Image.alpha_composite(img, soft_disc((C, C), cr * 0.07, WHITE, 255, cr * 0.03))

# --- Bright star at the chart centre ------------------------------------------------------
def sparkle(img, x, y, length, color):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(4):
        a = math.radians(90 * k)
        ux, uy = math.cos(a), -math.sin(a)
        px, py = -uy, ux
        pts = []
        for i in range(41):
            t = i / 40
            w = length * 0.16 * (1 - t) ** 2.2
            pts.append((x + ux * length * t + px * w, y + uy * length * t + py * w))
        for i in range(40, -1, -1):
            t = i / 40
            w = length * 0.16 * (1 - t) ** 2.2
            pts.append((x + ux * length * t - px * w, y + uy * length * t - py * w))
        d.polygon(pts, fill=color + (255,))
    img = Image.alpha_composite(img, soft_disc((x, y), length * 0.5, CYAN, 170, length * 0.35))
    img = Image.alpha_composite(img, layer)
    return Image.alpha_composite(img, soft_disc((x, y), length * 0.12, WHITE, 255, length * 0.05))


for fx, fy, cls, colour in CHART_STARS:
    if cls == 1:
        img = sparkle(img, S * fx, S * fy, S * 0.045, WHITE)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
