# Generates the Star Nav app icon (original artwork, GPL-3.0-or-later).
# Usage: python3 tools/make_icon.py StellarNavigator/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow. Renders at 4x and downsamples for clean edges.
#
# A flat compass over the night sky: a bold azimuth ring with cross-ticks, a segmented inner
# ring, an eight-pointed star with equal points, and a scatter of stars (gold sparkles, ringed bright
# stars and small dots).
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 4
S = 1024 * SS
C = S / 2

RING = (122, 162, 232)
WHITE = (242, 246, 255)
ICE = (150, 216, 246)
DIAG_LIT = (176, 204, 246)
DIAG_DARK = (104, 140, 222)
GOLD = (246, 184, 92)
CYAN = (110, 200, 246)


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
    g.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(blur))
               .point(lambda v: int(min(255, v * strength))))
    return g


def polar(r, deg):
    """Screen point at radius r and compass bearing deg (0 = up, clockwise)."""
    t = math.radians(deg)
    return (C + r * math.sin(t), C - r * math.cos(t))


# --- Background: deep navy, violet toward the top left, blue toward the bottom right ----
grad = Image.new("RGBA", (256, 256))
stops = [(0.0, (52, 36, 118)), (0.5, (24, 30, 92)), (1.0, (14, 46, 104))]
for y in range(256):
    for x in range(256):
        t = (x + y) / 510
        (t0, c0), (t1, c1) = (stops[0], stops[1]) if t <= 0.5 else (stops[1], stops[2])
        grad.putpixel((x, y), lerp(c0 + (255,), c1 + (255,), (t - t0) / (t1 - t0)))
img = grad.resize((S, S), Image.BICUBIC)
img = Image.alpha_composite(img, soft_disc((C, C), S * 0.30, (60, 110, 210), 70, S * 0.12))

# --- Azimuth ring with cross-ticks ------------------------------------------------------
R = S * 0.407
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
rd.ellipse([C - R, C - R, C + R, C + R], outline=RING + (255,), width=int(10 * SS))
for deg in range(0, 360, 10):
    if deg % 90 == 0:      # cardinal: long bar across the ring
        a, b, w = R - S * 0.035, R + S * 0.045, 12
    elif deg % 30 == 0:    # every 30°: bar across the ring
        a, b, w = R - S * 0.028, R + S * 0.028, 11
    else:                  # minor: short tick inside the ring
        a, b, w = R - S * 0.03, R, 5
    rd.line([polar(a, deg), polar(b, deg)], fill=RING + (255,), width=int(w * SS))
img = Image.alpha_composite(img, ring)

# --- Segmented inner ring, broken where the eight points pass -----------------------------
r2 = S * 0.277
inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
idr = ImageDraw.Draw(inner)
gap = 9  # degrees either side of each of the eight points
for k in range(8):
    start = 45 * k + gap
    end = 45 * (k + 1) - gap
    # PIL measures arcs from 3 o'clock, clockwise; convert from compass bearings.
    idr.arc([C - r2, C - r2, C + r2, C + r2], start=start - 90, end=end - 90,
            fill=RING + (115,), width=int(10 * SS))
img = Image.alpha_composite(img, inner)


# --- Eight-pointed star, all points equal ------------------------------------------------------------
def point(bearing, length, hw):
    tip = polar(length, bearing)
    left = polar(hw, bearing - 90)
    right = polar(hw, bearing + 90)
    return [(C, C), left, tip], [(C, C), tip, right]


img = Image.alpha_composite(img, soft_disc((C, C), S * 0.16, (90, 160, 240), 110, S * 0.08))
star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(star)
for k in range(4):
    lit, dark = point(45 + 90 * k, S * 0.315, S * 0.058)
    sd.polygon(lit, fill=DIAG_LIT + (255,))
    sd.polygon(dark, fill=DIAG_DARK + (255,))
for bearing, length in ((0, 0.315), (90, 0.315), (180, 0.315), (270, 0.315)):
    lit, dark = point(bearing, S * length, S * 0.058)
    sd.polygon(lit, fill=WHITE + (255,))
    sd.polygon(dark, fill=ICE + (255,))
img = Image.alpha_composite(img, glow_of(star, (120, 180, 255), SS * 10, 0.35))
img = Image.alpha_composite(img, star)


# --- Stars -----------------------------------------------------------------------------
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
            w = length * 0.22 * (1 - t) ** 1.8
            pts.append((x + ux * length * t + px * w, y + uy * length * t + py * w))
        for i in range(40, -1, -1):
            t = i / 40
            w = length * 0.22 * (1 - t) ** 1.8
            pts.append((x + ux * length * t - px * w, y + uy * length * t - py * w))
        d.polygon(pts, fill=color + (255,))
    img = Image.alpha_composite(img, soft_disc((x, y), length * 0.45, color, 110, length * 0.3))
    return Image.alpha_composite(img, layer)


dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dots)
# Ringed bright stars: (x, y, colour) as fractions of the icon.
for fx, fy, col in ((0.219, 0.381, WHITE), (0.257, 0.676, WHITE), (0.698, 0.247, CYAN)):
    x, y, r = S * fx, S * fy, S * 0.011
    dd.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
    dd.ellipse([x - r * 2.1, y - r * 2.1, x + r * 2.1, y + r * 2.1], outline=col + (130,), width=int(3 * SS))
# Small dots.
for fx, fy, col, rr in ((0.619, 0.171, GOLD, 0.0060), (0.790, 0.359, GOLD, 0.0075),
                        (0.188, 0.580, WHITE, 0.0060), (0.580, 0.660, GOLD, 0.0060), (0.819, 0.629, WHITE, 0.0065),
                        (0.371, 0.788, GOLD, 0.0075)):
    x, y, r = S * fx, S * fy, S * rr
    dd.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
img = Image.alpha_composite(img, glow_of(dots, WHITE, SS * 6, 0.6))
img = Image.alpha_composite(img, dots)

# Gold sparkles.
# Placed in the gaps between points (bearings 337.5° and 157.5°) so no point touches them.
for bearing in (337.5, 157.5):
    x, y = polar(S * 0.305, bearing)
    img = sparkle(img, x, y, S * 0.045, GOLD)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
