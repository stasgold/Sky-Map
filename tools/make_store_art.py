#!/usr/bin/env python3
# Generates the App Store product-page creative assets for Star Nav (GPL-3.0-or-later).
#
# Usage: make_store_art.py OUT_DIR [SKY_SCREENSHOT]
#   header-3840x1646.png   Header, 21:9
#   header-5244x2950.png   Header, 16:9 (Apple accepts PNG only at this size)
#   search-3840x2560.png   Search Results, 3:2 (shows SKY_SCREENSHOT, a real app capture,
#                          on a phone; defaults to the screenshot branch's raw 01-sky.png)
# Flat RGB, no transparency, key content inside a centred safe area. Requires Pillow + numpy.
import math
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = pathlib.Path(__file__).resolve().parent / "fonts"
TITLE_FONT = str(FONTS / "InterDisplay-Bold.otf")
BODY_FONT = str(FONTS / "Inter-Medium.otf")

TOP = np.array([18, 14, 58], np.float32)       # deep violet sky
MID = np.array([30, 34, 104], np.float32)
HORIZON = np.array([34, 70, 128], np.float32)  # blue glow at the horizon
GOLD = (246, 184, 92)
ICE = (150, 216, 246)
WHITE = (242, 246, 255)


def sky(w, h, seed):
    """Night-sky gradient, Milky Way band and a star field."""
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    t1 = np.clip(y / 0.6, 0, 1)
    t2 = np.clip((y - 0.6) / 0.4, 0, 1)
    rgb = TOP * (1 - t1)[..., None] + MID * t1[..., None]
    rgb = rgb * (1 - t2)[..., None] + HORIZON * t2[..., None]
    img = np.broadcast_to(rgb, (h, w, 3)).copy()

    # Milky Way: a soft, slightly lumpy diagonal band.
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = (xx / w * 0.55 - yy / h + 0.62)  # distance to a diagonal line
    noise = Image.fromarray((rng.random((h // 24 + 1, w // 24 + 1)) * 255).astype(np.uint8)).resize(
        (w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(w / 160))
    n = np.asarray(noise, np.float32) / 255
    band = np.exp(-(d / 0.16) ** 2) * (0.55 + 0.6 * n)
    img += band[..., None] * np.array([60, 58, 96], np.float32)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")

    # Stars: many faint, few bright; denser along the band.
    random.seed(seed)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    count = int(w * h / 2600)
    for _ in range(count):
        x, yv = random.random() * w, random.random() * h
        on_band = math.exp(-((x / w * 0.55 - yv / h + 0.62) / 0.16) ** 2)
        if random.random() > 0.35 + 0.65 * on_band:
            continue
        r = 1.0 + 3.2 * random.random() ** 6 * (w / 3840)
        a = int(90 + 165 * random.random() ** 2)
        tint = random.choice([(255, 255, 255), (255, 236, 210), (210, 226, 255)])
        dr.ellipse([x - r, yv - r, x + r, yv + r], fill=tint + (a,))
    out = Image.alpha_composite(out.convert("RGBA"), layer.filter(ImageFilter.GaussianBlur(0.6)))
    # A handful of bright stars with soft glows.
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for _ in range(int(14 * w / 3840)):
        x, yv = random.random() * w, random.random() * h * 0.7
        r = (6 + 6 * random.random()) * w / 3840
        gd.ellipse([x - r * 4, yv - r * 4, x + r * 4, yv + r * 4], fill=(200, 215, 255, 60))
        gd.ellipse([x - r, yv - r, x + r, yv + r], fill=(255, 255, 255, 255))
    out = Image.alpha_composite(out, glow.filter(ImageFilter.GaussianBlur(4 * w / 3840)))
    return out


def mountains(img, seed, base, height):
    """Two layered mountain silhouettes along the bottom, with a faint horizon glow."""
    w, h = img.size
    random.seed(seed)
    for layer_i, (frac, colour) in enumerate(((1.0, (22, 26, 70)), (0.62, (10, 12, 34)))):
        pts = [(0, h)]
        x = 0.0
        y = base + height * (1 - frac) * 0.6
        while True:
            y += random.uniform(-1, 1) * height * 0.35 * frac
            y = min(max(y, base - height * frac), base + height * 0.4)
            pts.append((min(x, w), y))
            if x >= w:
                break
            x += w / random.uniform(18, 30)
        pts.append((w, h))
        sil = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(sil).polygon(pts, fill=colour + (255,))
        img = Image.alpha_composite(img, sil.filter(ImageFilter.GaussianBlur(1.2)))
    return img


def constellation(img, stars, lines, centre, scale, colour, rot=0.0):
    """A real constellation figure (J2000 ra/dec), drawn as a faint chart overlay."""
    ra0 = sum(s[0] for s in stars) / len(stars)
    de0 = sum(s[1] for s in stars) / len(stars)
    c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    pts = []
    for ra, de in stars:
        x = -(ra - ra0) * math.cos(math.radians(de0))
        y = -(de - de0)
        pts.append((centre[0] + (x * c - y * s_) * scale, centre[1] + (x * s_ + y * c) * scale))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lw = max(2, int(scale * 0.12))
    for a, b in lines:
        d.line([pts[a], pts[b]], fill=colour + (150,), width=lw)
    for x, y in pts:
        r = lw * 2.2
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE + (255,))
    return Image.alpha_composite(img, layer)


def rose(size):
    """The app icon's compass-rose star on a transparent tile of `size` pixels."""
    S = size
    C = S / 2
    R = S * 0.48

    def polar(r, b):
        t = math.radians(b)
        return (C + r * math.sin(t), C - r * math.cos(t))

    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rad = np.hypot(xx - C, yy - C) / (R / 0.356)

    def shade(img, polys, stops):
        mask = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(mask)
        for p in polys:
            md.polygon(p, fill=255)
        rs = [r for r, _ in stops]
        rgb = np.stack([np.interp(rad, rs, [c[i] for _, c in stops]) for i in range(3)], -1)
        lay = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")
        lay.putalpha(mask)
        return Image.alpha_composite(img, lay)

    g = {
        "cl": [(0, (240, 202, 150)), (0.06, (237, 222, 200)), (0.10, (230, 236, 240)), (0.15, (234, 243, 252)),
               (0.22, (243, 247, 252)), (0.34, (251, 253, 252))],
        "cd": [(0, (241, 209, 168)), (0.05, (196, 186, 172)), (0.08, (140, 168, 210)), (0.15, (140, 194, 238)),
               (0.22, (168, 222, 244)), (0.34, (190, 233, 245))],
        "dl": [(0, (236, 214, 176)), (0.10, (200, 233, 252)), (0.15, (214, 237, 251)), (0.22, (240, 250, 255)),
               (0.30, (246, 252, 255))],
        "dd": [(0, (200, 190, 190)), (0.10, (121, 159, 234)), (0.15, (128, 172, 235)), (0.22, (165, 210, 241)),
               (0.30, (182, 221, 245))],
        "it": [(0, (232, 202, 160)), (0.05, (170, 204, 216)), (0.09, (166, 210, 232))],
        "iw": [(0, (242, 228, 196)), (0.05, (240, 244, 240)), (0.09, (236, 245, 250))],
        "rl": [(0, (200, 172, 128)), (0.4, (200, 172, 128))],
        "rd": [(0, (150, 130, 122)), (0.4, (150, 130, 122))],
    }
    k_ = R / 0.356  # pixels per unit of the icon's geometry
    f = {k: [] for k in g}
    c0 = (C, C)
    for k in range(8):
        b = 22.5 + 45 * k
        f["rd"].append([c0, polar(0.132 * k_, b - 4.2), polar(0.215 * k_, b), polar(0.132 * k_, b)])
        f["rl"].append([c0, polar(0.132 * k_, b), polar(0.215 * k_, b), polar(0.132 * k_, b + 4.2)])
    for k in range(8):
        b = 45 * k
        tip = polar((0.356 if k % 2 == 0 else 0.313) * k_, b)
        l, r = polar(0.132 * k_, b - 22.5), polar(0.132 * k_, b + 22.5)
        if k % 2 == 0:
            f["cl"].append([c0, l, tip]); f["cd"].append([c0, tip, r])
        else:
            sp = polar(0.09 * k_, b)
            f["dl"].append([sp, l, tip]); f["dd"].append([sp, tip, r])
            f["it"].append([c0, l, sp]); f["iw"].append([c0, sp, r])
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for name in ("rd", "rl", "dl", "dd", "it", "iw", "cl", "cd"):
        tile = shade(tile, f[name], g[name])
    halo = Image.new("RGBA", (S, S), (150, 200, 255, 0))
    halo.putalpha(tile.getchannel("A").filter(ImageFilter.GaussianBlur(S * 0.03)).point(lambda v: int(v * 0.45)))
    return Image.alpha_composite(halo, tile)


def azimuth_ring(img, cx, cy, r, alpha=110):
    """A faint azimuth ring with cross-ticks, echoing the icon."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lw = max(3, int(r * 0.012))
    col = (122, 162, 232, alpha)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=lw)
    for deg in range(0, 360, 30):
        t = math.radians(deg)
        a, b = (r - r * 0.06, r + r * 0.08) if deg % 90 == 0 else (r - r * 0.05, r + r * 0.05)
        d.line([(cx + a * math.sin(t), cy - a * math.cos(t)), (cx + b * math.sin(t), cy - b * math.cos(t))],
               fill=col, width=lw)
    return Image.alpha_composite(img, layer)


def text_block(img, x, y, title, subtitle, title_px, align="left"):
    d = ImageDraw.Draw(img)
    tf = ImageFont.truetype(TITLE_FONT, title_px)
    bf = ImageFont.truetype(BODY_FONT, int(title_px * 0.36))
    tb = d.textbbox((0, 0), title, font=tf)
    bb = d.textbbox((0, 0), subtitle, font=bf)
    tw, bw = tb[2] - tb[0], bb[2] - bb[0]
    ox = (lambda w_: x - w_ / 2) if align == "center" else (lambda w_: x)
    d.text((ox(tw) - tb[0], y - tb[1]), title, font=tf, fill=(255, 255, 255))
    d.text((ox(bw) - bb[0], y + (tb[3] - tb[1]) + title_px * 0.28 - bb[1]), subtitle, font=bf, fill=(198, 218, 255))


ORION = dict(
    stars=[(88.79, 7.41), (81.28, 6.35), (83.00, -0.30), (84.05, -1.20), (85.19, -1.94),
           (78.63, -8.20), (86.94, -9.67), (83.78, 9.93)],
    lines=[(0, 1), (0, 4), (1, 2), (2, 3), (3, 4), (2, 5), (4, 6), (0, 7), (1, 7)],
)
CASSIOPEIA = dict(stars=[(2.29, 59.15), (10.13, 56.54), (14.18, 60.72), (21.45, 60.24), (28.60, 63.67)],
                  lines=[(0, 1), (1, 2), (2, 3), (3, 4)])


def header(w, h, title_px, rose_frac=0.62):
    img = sky(w, h, seed=w)
    img = mountains(img, seed=7, base=h * 0.86, height=h * 0.1)
    # Key content in the centre: the rose inside its ring, then the name and phrase.
    rose_px = int(h * rose_frac)
    cx, cy = int(w * 0.5 - h * 0.42), int(h * 0.46)
    img = azimuth_ring(img, cx, cy, rose_px * 0.56)
    img = constellation(img, CASSIOPEIA["stars"], CASSIOPEIA["lines"], (w * 0.5 + h * 1.05, h * 0.24), h * 0.012, ICE, rot=10)
    img = constellation(img, ORION["stars"], ORION["lines"], (w * 0.5 - h * 1.25, h * 0.36), h * 0.014, GOLD, rot=-8)
    tile = rose(rose_px)
    img.alpha_composite(tile, (cx - rose_px // 2, cy - rose_px // 2))
    text_block(img, int(cx + rose_px * 0.62), int(cy - title_px * 0.78), "Star Nav", "Your guide to the night sky", title_px)
    return img.convert("RGB")


def search(w, h, screenshot):
    img = sky(w, h, seed=w + 1)
    img = mountains(img, seed=11, base=h * 0.9, height=h * 0.07)
    img = constellation(img, ORION["stars"], ORION["lines"], (w * 0.14, h * 0.2), h * 0.011, GOLD, rot=-8)
    # Left: rose, name and what the app does. Right: the real app on a phone.
    rose_px = int(h * 0.3)
    img.alpha_composite(rose(rose_px), (int(w * 0.16), int(h * 0.2)))
    text_block(img, int(w * 0.16), int(h * 0.55), "Star Nav", "Point your phone at the sky", int(h * 0.11))
    shot = Image.open(screenshot).convert("RGB")
    ph = int(h * 0.82)
    pw = int(ph * shot.width / shot.height)
    bezel = int(pw * 0.035)
    px, py = int(w * 0.66) - pw // 2, (h - ph) // 2
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([px - bezel, py - bezel, px + pw + bezel, py + ph + bezel], radius=int(pw * 0.16),
                         fill=(8, 8, 14, 255), outline=(90, 100, 140, 255), width=max(3, bezel // 5))
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px - bezel, py - bezel + 30, px + pw + bezel, py + ph + bezel + 30],
                                             radius=int(pw * 0.16), fill=(0, 0, 0, 170))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(40)))
    img = Image.alpha_composite(img, frame)
    screen = shot.resize((pw, ph), Image.LANCZOS)
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=int(pw * 0.13), fill=255)
    img.paste(screen, (px, py), mask)
    return img.convert("RGB")


def main(out_dir, screenshot=None):
    out = pathlib.Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for (w, h), px, frac in (((3840, 1646), 250, 0.62), ((5244, 2950), 330, 0.48)):
        im = header(w, h, px, frac)
        im.save(out / f"header-{w}x{h}.png", optimize=True)
        print("wrote", f"header-{w}x{h}.png", im.size, im.mode)
    if screenshot:
        im = search(3840, 2560, screenshot)
        im.save(out / "search-3840x2560.png", optimize=True)
        print("wrote search-3840x2560.png", im.size, im.mode)


if __name__ == "__main__":
    main(*sys.argv[1:3])
