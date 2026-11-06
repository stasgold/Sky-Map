# Generates the Star Nav app icon (original artwork, GPL-3.0-or-later).
# Usage: python3 tools/make_icon.py StellarNavigator/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow. Renders at 4x and downsamples for clean edges.
#
# A schematic star chart: an azimuthal grid with a degree ring, three real constellation
# figures (Big Dipper, Cassiopeia, Cygnus, Cepheus) drawn from their J2000 positions, and a compass
# star at the centre.
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


# --- Constellations from real J2000 positions --------------------------------------------
def project(stars, center, scale, rotate_deg):
    """Gnomonic-ish local projection of (ra, dec) around the figure's mean, east to the left."""
    ra0 = sum(s[0] for s in stars) / len(stars)
    de0 = sum(s[1] for s in stars) / len(stars)
    rot = math.radians(rotate_deg)
    out = []
    for ra, de in stars:
        x = -(ra - ra0) * math.cos(math.radians(de0))
        y = -(de - de0)
        xr = x * math.cos(rot) - y * math.sin(rot)
        yr = x * math.sin(rot) + y * math.cos(rot)
        out.append((center[0] + xr * scale, center[1] + yr * scale))
    return out


FIGURES = [
    # Big Dipper: Dubhe, Merak, Phecda, Megrez, Alioth, Mizar, Alkaid (magnitudes for dot size).
    dict(stars=[(165.93, 61.75), (165.46, 56.38), (178.46, 53.69), (183.86, 57.03), (193.51, 55.96),
                (200.98, 54.93), (206.89, 49.31)],
         mags=[1.8, 2.4, 2.4, 3.3, 1.8, 2.2, 1.9],
         lines=[(0, 1), (1, 2), (2, 3), (3, 0), (3, 4), (4, 5), (5, 6)],
         center=(S * 0.33, S * 0.31), scale=S * 0.0105, rot=-18, color=GOLD),
    # Cassiopeia: Caph, Schedar, Navi, Ruchbah, Segin.
    dict(stars=[(2.29, 59.15), (10.13, 56.54), (14.18, 60.72), (21.45, 60.24), (28.60, 63.67)],
         mags=[2.3, 2.2, 2.5, 2.7, 3.4],
         lines=[(0, 1), (1, 2), (2, 3), (3, 4)],
         center=(S * 0.66, S * 0.68), scale=S * 0.0135, rot=8, color=CYAN),
    # Cygnus: Deneb, Sadr, Gienah, Delta Cyg, Albireo.
    dict(stars=[(310.36, 45.28), (305.56, 40.26), (311.55, 33.97), (296.24, 45.13), (292.68, 27.96)],
         mags=[1.3, 2.2, 2.5, 2.9, 3.1],
         lines=[(0, 1), (1, 4), (3, 1), (1, 2)],
         center=(S * 0.32, S * 0.69), scale=S * 0.0105, rot=-30, color=GOLD),
    # Cepheus: Alderamin, Alfirk, Errai, Iota Cep, Zeta Cep (the "house").
    dict(stars=[(319.64, 62.59), (322.16, 70.56), (354.84, 77.63), (342.42, 66.20), (332.71, 58.20)],
         mags=[2.5, 3.2, 3.2, 3.5, 3.4],
         lines=[(0, 1), (1, 2), (2, 3), (3, 4), (4, 0), (1, 3)],
         center=(S * 0.715, S * 0.32), scale=S * 0.0092, rot=40, color=CYAN),
]

lines = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(lines)
dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dots)
for f in FIGURES:
    pts = project(f["stars"], f["center"], f["scale"], f["rot"])
    for a, b in f["lines"]:
        ld.line([pts[a], pts[b]], fill=f["color"] + (235,), width=int(4.5 * SS))
    for (x, y), m in zip(pts, f["mags"]):
        r = S * (0.0115 - 0.0019 * (m - 1.3))
        dd.ellipse([x - r, y - r, x + r, y + r], fill=WHITE + (255,))
        dd.ellipse([x - r * 1.7, y - r * 1.7, x + r * 1.7, y + r * 1.7], outline=f["color"] + (150,), width=int(1.8 * SS))
img = Image.alpha_composite(img, glow_of(lines, GOLD, SS * 8, 0.55))
img = Image.alpha_composite(img, lines)
img = Image.alpha_composite(img, glow_of(dots, WHITE, SS * 10, 0.9))
img = Image.alpha_composite(img, dots)


# --- Compass star at the chart centre -------------------------------------------------
def point(cx, cy, ang, length, hw):
    a = math.radians(ang)
    tip = (cx + length * math.cos(a), cy - length * math.sin(a))
    l = (cx + hw * math.cos(a + math.pi / 2), cy - hw * math.sin(a + math.pi / 2))
    r = (cx + hw * math.cos(a - math.pi / 2), cy - hw * math.sin(a - math.pi / 2))
    return [(cx, cy), l, tip], [(cx, cy), tip, r]


cr = S * 0.15
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


for x, y, l in ((S * 0.86, S * 0.52, S * 0.03), (S * 0.15, S * 0.50, S * 0.024), (S * 0.53, S * 0.88, S * 0.022)):
    img = sparkle(img, x, y, l, WHITE)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
