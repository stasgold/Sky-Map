# Generates the Stellar Navigator app icon (original artwork, GPL-3.0-or-later).
# Usage: python3 tools/make_icon.py StellarNavigator/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow. Renders at 4x and downsamples for clean edges.
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SS = 4            # supersampling factor
S = 1024 * SS
C = S / 2

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def radial(size, center, radius, inner, outer, power=1.0):
    """RGBA radial gradient image."""
    w, h = size
    g = Image.new("L", (512, 512))
    px = g.load()
    for y in range(512):
        for x in range(512):
            d = math.hypot(x - 255.5, y - 255.5) / 255.5
            px[x, y] = int(255 * min(1, d) ** power)
    g = g.resize((int(radius * 2), int(radius * 2)), Image.BICUBIC)
    out = Image.new("RGBA", size, outer)
    col_in = Image.new("RGBA", g.size, inner)
    col_out = Image.new("RGBA", g.size, outer)
    blob = Image.composite(col_out, col_in, g)
    out.paste(blob, (int(center[0] - radius), int(center[1] - radius)))
    return out

def glow(size, center, radius, color, alpha, blur):
    """A soft disc of solid color: only the alpha mask is blurred, so edges never darken."""
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).ellipse([center[0] - radius, center[1] - radius,
                                  center[0] + radius, center[1] + radius], fill=alpha)
    layer = Image.new("RGBA", size, color + (0,))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return layer

# --- Background: deep night with a cool nebula wash -------------------------------------
img = Image.new("RGBA", (S, S))
grad = Image.new("RGBA", (1, 256))
for y in range(256):
    t = y / 255
    grad.putpixel((0, y), lerp((10, 14, 46, 255), (4, 6, 22, 255), t))
img = grad.resize((S, S), Image.BICUBIC)

img = Image.alpha_composite(img, glow((S, S), (S * 0.30, S * 0.28), S * 0.42, (86, 60, 190), 120, S * 0.16))
img = Image.alpha_composite(img, glow((S, S), (S * 0.78, S * 0.80), S * 0.40, (20, 120, 170), 95, S * 0.16))
img = Image.alpha_composite(img, glow((S, S), (C, C), S * 0.30, (255, 190, 110), 70, S * 0.14))

# --- Star field ---------------------------------------------------------------------
random.seed(11)
stars = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(stars)
for _ in range(140):
    x, y = random.random() * S, random.random() * S
    if math.hypot(x - C, y - C) < S * 0.30:
        continue
    r = random.choice([1.2, 1.5, 2, 2, 3, 4]) * SS
    a = random.randint(110, 230)
    d.ellipse([x - r, y - r, x + r, y + r], fill=(235, 238, 255, a))
img = Image.alpha_composite(img, stars.filter(ImageFilter.GaussianBlur(SS * 0.6)))

# --- Compass bezel: concentric rings with tick marks --------------------------------
bez = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(bez)
R1, R2 = S * 0.345, S * 0.372
gold = (255, 196, 110)
bd.ellipse([C - R2, C - R2, C + R2, C + R2], outline=gold + (150,), width=int(5 * SS))
bd.ellipse([C - R1, C - R1, C + R1, C + R1], outline=gold + (90,), width=int(3 * SS))
for deg in range(0, 360, 10):
    a = math.radians(deg)
    major = deg % 30 == 0
    r_in = R1 + (S * 0.004 if major else S * 0.011)
    r_out = R2 - S * 0.004
    w = int((5 if major else 3) * SS)
    alpha = 200 if major else 120
    bd.line([(C + r_in * math.cos(a), C + r_in * math.sin(a)),
             (C + r_out * math.cos(a), C + r_out * math.sin(a))], fill=gold + (alpha,), width=w)
img = Image.alpha_composite(img, bez.filter(ImageFilter.GaussianBlur(SS * 0.5)))

# --- The navigation star: four faceted main points + four slim diagonals ---------------
def point_polys(angle_deg, length, half_width):
    """A kite-shaped point split along its axis into a lit and a shaded facet."""
    a = math.radians(angle_deg)
    tip = (C + length * math.cos(a), C - length * math.sin(a))
    left = (C + half_width * math.cos(a + math.pi / 2), C - half_width * math.sin(a + math.pi / 2))
    right = (C + half_width * math.cos(a - math.pi / 2), C - half_width * math.sin(a - math.pi / 2))
    centre = (C, C)
    return [centre, left, tip], [centre, tip, right]

star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(star)

# Diagonal points (behind), slimmer and dimmer.
for ang in (45, 135, 225, 315):
    lit, dark = point_polys(ang, S * 0.235, S * 0.04)
    sd.polygon(lit, fill=(214, 196, 255, 255))
    sd.polygon(dark, fill=(140, 120, 210, 255))

# Main compass points; north is the longest (the "north star").
lengths = {90: S * 0.43, 0: S * 0.315, 180: S * 0.315, 270: S * 0.315}
for ang, length in lengths.items():
    lit, dark = point_polys(ang, length, S * 0.082)
    sd.polygon(lit, fill=(255, 246, 222, 255))
    sd.polygon(dark, fill=(255, 176, 72, 255))

# Soft glow behind the star, then the star itself.
halo = Image.new("RGBA", (S, S), (255, 200, 130, 0))
halo.putalpha(star.getchannel("A").filter(ImageFilter.GaussianBlur(S * 0.03)).point(lambda v: int(v * 0.8)))
img = Image.alpha_composite(img, halo)
img = Image.alpha_composite(img, star)

# Soft luminous core where the facets meet.
img = Image.alpha_composite(img, glow((S, S), (C, C), S * 0.06, (255, 214, 140), 150, S * 0.03))
img = Image.alpha_composite(img, glow((S, S), (C, C), S * 0.022, (255, 255, 248), 255, S * 0.008))

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
