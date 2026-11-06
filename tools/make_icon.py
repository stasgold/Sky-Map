# Generates the Star Nav app icon (original artwork, GPL-3.0-or-later).
# Usage: python3 tools/make_icon.py StellarNavigator/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow. Renders at 4x and downsamples for clean edges.
#
# A flat compass over the night sky: a bold azimuth ring with cross-ticks, a segmented inner
# ring, an eight-point compass-rose star with faceted crystal points and gold rays, and a scatter of stars (gold sparkles, ringed bright
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

# --- Azimuth ring with cross-ticks every 30° ------------------------------------------------------
R = S * 0.407
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
rd.ellipse([C - R, C - R, C + R, C + R], outline=RING + (255,), width=int(8 * SS))
for deg in range(0, 360, 30):
    if deg % 90 == 0:      # cardinal: long bar across the ring
        a, b, w = R - S * 0.035, R + S * 0.045, 10
    else:                  # every 30°: bar across the ring
        a, b, w = R - S * 0.03, R + S * 0.03, 10
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


# --- Compass rose star -----------------------------------------------------------------
# Each of the eight points is a kite: centre -> shoulder -> tip -> shoulder. Neighbouring
# points share their shoulders (radius 0.132, at 22.5° + 45°k), where slim gold rays sit.
# Every point is split along its axis into a light half (counter-clockwise) and a cool half
# (clockwise); the diagonals also have an inner facet whose shading flips, which gives the
# crystal look. Facets shade with distance from the centre: warm gold at the core, then
# white or blue toward the tips. Colours were sampled from the reference artwork.
import numpy as np

SHOULDER_R = 0.132
CARDINAL_TIP = 0.356
DIAGONAL_TIP = 0.313
DIAG_SPLIT_R = 0.09

GRADIENTS = {  # radius (fraction of icon width) -> RGB
    "card_light": [(0.0, (240, 202, 150)), (0.06, (237, 222, 200)), (0.10, (230, 236, 240)),
                   (0.15, (234, 243, 252)), (0.22, (243, 247, 252)), (0.34, (251, 253, 252))],
    "card_dark": [(0.0, (241, 209, 168)), (0.05, (196, 186, 172)), (0.08, (140, 168, 210)),
                  (0.15, (140, 194, 238)), (0.22, (168, 222, 244)), (0.34, (190, 233, 245))],
    "diag_light": [(0.0, (236, 214, 176)), (0.10, (200, 233, 252)), (0.15, (214, 237, 251)),
                   (0.22, (240, 250, 255)), (0.30, (246, 252, 255))],
    "diag_dark": [(0.0, (200, 190, 190)), (0.10, (121, 159, 234)), (0.15, (128, 172, 235)),
                  (0.22, (165, 210, 241)), (0.30, (182, 221, 245))],
    "diag_inner_teal": [(0.0, (232, 202, 160)), (0.05, (170, 204, 216)), (0.09, (166, 210, 232))],
    "diag_inner_white": [(0.0, (242, 228, 196)), (0.05, (240, 244, 240)), (0.09, (236, 245, 250))],
    "ray_light": [(0.0, (200, 172, 128)), (0.25, (200, 172, 128))],
    "ray_dark": [(0.0, (150, 130, 122)), (0.25, (150, 130, 122))],
}

yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
radius = np.hypot(xx - C, yy - C) / S
del xx, yy


def shade(img, polys, stops):
    """Fill the polygons with a colour that varies with distance from the centre."""
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    for poly in polys:
        md.polygon(poly, fill=255)
    rs = [r for r, _ in stops]
    rgb = np.stack([np.interp(radius, rs, [c[i] for _, c in stops]) for i in range(3)], axis=-1)
    layer = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")
    layer.putalpha(mask)
    return Image.alpha_composite(img, layer)


img = Image.alpha_composite(img, soft_disc((C, C), S * 0.17, (90, 160, 240), 110, S * 0.08))

facets = {k: [] for k in GRADIENTS}
centre = (C, C)
for k in range(8):  # gold rays between the points, starting at the shared shoulders
    b = 22.5 + 45 * k
    base_l, base_r = polar(S * SHOULDER_R, b - 4.2), polar(S * SHOULDER_R, b + 4.2)
    mid = polar(S * SHOULDER_R, b)
    tip = polar(S * 0.215, b)
    facets["ray_dark"].append([centre, base_l, tip, mid])
    facets["ray_light"].append([centre, mid, tip, base_r])
for k in range(8):
    b = 45 * k
    cardinal = k % 2 == 0
    tip = polar(S * (CARDINAL_TIP if cardinal else DIAGONAL_TIP), b)
    left = polar(S * SHOULDER_R, b - 22.5)   # counter-clockwise shoulder
    right = polar(S * SHOULDER_R, b + 22.5)  # clockwise shoulder
    if cardinal:
        facets["card_light"].append([centre, left, tip])
        facets["card_dark"].append([centre, tip, right])
    else:
        split = polar(S * DIAG_SPLIT_R, b)
        facets["diag_light"].append([split, left, tip])
        facets["diag_dark"].append([split, tip, right])
        facets["diag_inner_teal"].append([centre, left, split])
        facets["diag_inner_white"].append([centre, split, right])

star_only = Image.new("RGBA", (S, S), (0, 0, 0, 0))
for name in ("ray_dark", "ray_light", "diag_light", "diag_dark", "diag_inner_teal",
             "diag_inner_white", "card_light", "card_dark"):
    star_only = shade(star_only, facets[name], GRADIENTS[name])
del radius
img = Image.alpha_composite(img, glow_of(star_only, (150, 200, 255), SS * 8, 0.12))
img = Image.alpha_composite(img, star_only)


# --- Stars -----------------------------------------------------------------------------
def sparkle(img, x, y, length, color):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(8):
        a = math.radians(45 * k)
        ray = length if k % 2 == 0 else length * 0.55
        ux, uy = math.cos(a), -math.sin(a)
        px, py = -uy, ux
        pts = []
        for i in range(41):
            t = i / 40
            w = ray * 0.2 * (1 - t) ** 1.8
            pts.append((x + ux * ray * t + px * w, y + uy * ray * t + py * w))
        for i in range(40, -1, -1):
            t = i / 40
            w = ray * 0.2 * (1 - t) ** 1.8
            pts.append((x + ux * ray * t - px * w, y + uy * ray * t - py * w))
        d.polygon(pts, fill=color + (255,))
    img = Image.alpha_composite(img, soft_disc((x, y), length * 0.45, color, 110, length * 0.3))
    return Image.alpha_composite(img, layer)


dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dots)
# Ringed bright stars: (x, y, colour) as fractions of the icon.
for fx, fy, col in ((0.219, 0.381, (255, 236, 204)), (0.257, 0.676, (255, 236, 204)), (0.698, 0.247, CYAN)):
    x, y, r = S * fx, S * fy, S * 0.011
    dd.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
    halo = CYAN if col == CYAN else GOLD
    dd.ellipse([x - r * 2.1, y - r * 2.1, x + r * 2.1, y + r * 2.1], outline=halo + (150,), width=int(3 * SS))
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
