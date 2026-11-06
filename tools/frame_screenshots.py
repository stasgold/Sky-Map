#!/usr/bin/env python3
# Adds a caption header to App Store screenshots (GPL-3.0-or-later).
#
# Usage: frame_screenshots.py RAW_DIR OUT_DIR
#   RAW_DIR holds iphone-6.9/ and ipad-13/ folders of real app screenshots; OUT_DIR gets the
#   same folders with each screenshot placed under a caption, at the same pixel size Apple
#   requires. The app's own pixels are not altered, only scaled. Requires Pillow.
import pathlib
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = pathlib.Path(__file__).resolve().parent / "fonts"
TITLE_FONT = FONTS / "InterDisplay-Bold.otf"
BODY_FONT = FONTS / "Inter-Medium.otf"

# Caption per screenshot (file stem): a headline and a supporting line. Every claim is true
# of the app (see the README for the numbers).
CAPTIONS = {
    "01-sky": ("See the sky above you", "Stars, planets and constellations in real time"),
    "02-info-card": ("Tap anything to learn more", "Photos, facts and rise & set times"),
    "03-search": ("Find any star or planet", "Search by name or catalog number"),
    "04-search-results": ("Explore the deep sky", "Nebulae, galaxies and star clusters"),
    "05-find-orion": ("Glide to your target", "Search, and the map takes you there"),
    "06-layers": ("Show what you want", "Grids, horizon, ecliptic, meteor showers"),
    "07-time-travel": ("Travel through time", "The sky on any date from 1800 to 2049"),
    "08-night-mode": ("Night mode", "All red, to keep your eyes dark-adapted"),
}

# Layout per device folder: canvas size, header height, title/body sizes, corner radius.
LAYOUTS = {
    "iphone-6.9": dict(size=(1320, 2868), header=500, title=104, body=52, radius=72, margin=70),
    "ipad-13": dict(size=(2064, 2752), header=400, title=100, body=50, radius=48, margin=70),
}

TOP = (44, 30, 112)      # violet, as in the app icon
BOTTOM = (12, 30, 78)    # deep blue
TITLE_COLOUR = (255, 255, 255)
BODY_COLOUR = (190, 214, 255)


def background(size):
    w, h = size
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel((0, y), tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    img = grad.resize((w, h), Image.BICUBIC)
    # A few faint stars, so the frame belongs to the app's night sky.
    random.seed(w * 31 + h)
    stars = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(stars)
    for _ in range(90):
        x, y = random.random() * w, random.random() * h
        r = random.choice([1.5, 2, 2.5, 3.5])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(235, 240, 255, random.randint(60, 150)))
    return Image.alpha_composite(img.convert("RGBA"), stars)


def fit_font(path, size, text, max_width):
    while size > 20:
        font = ImageFont.truetype(str(path), size)
        if font.getlength(text) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(path), size)


def frame(src, layout, caption):
    W, H = layout["size"]
    canvas = background((W, H))
    d = ImageDraw.Draw(canvas)
    title, body = caption
    max_text = W - 2 * layout["margin"]
    tf = fit_font(TITLE_FONT, layout["title"], title, max_text)
    bf = fit_font(BODY_FONT, layout["body"], body, max_text)
    header = layout["header"]
    tb = d.textbbox((0, 0), title, font=tf)
    bb = d.textbbox((0, 0), body, font=bf)
    gap = int(layout["body"] * 0.55)
    block = (tb[3] - tb[1]) + gap + (bb[3] - bb[1])
    y0 = (header - block) // 2 + int(header * 0.04)
    d.text(((W - (tb[2] - tb[0])) / 2 - tb[0], y0 - tb[1]), title, font=tf, fill=TITLE_COLOUR)
    d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], y0 + (tb[3] - tb[1]) + gap - bb[1]), body, font=bf,
           fill=BODY_COLOUR)

    # The real screenshot, scaled to fit under the header, with rounded corners and a soft shadow.
    shot = Image.open(src).convert("RGB")
    avail_h = H - header - layout["margin"]
    scale = min(avail_h / shot.height, (W - 2 * layout["margin"]) / shot.width)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, header
    r = int(layout["radius"])
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=r, fill=255)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 16, x + sw, y + sh + 16], radius=r, fill=(0, 0, 0, 150))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.paste(shot, (x, y), mask)
    ImageDraw.Draw(canvas).rounded_rectangle([x, y, x + sw - 1, y + sh - 1], radius=r,
                                             outline=(150, 180, 255, 90), width=3)
    return canvas.convert("RGB")


def main(raw_dir, out_dir):
    raw, out = pathlib.Path(raw_dir), pathlib.Path(out_dir)
    for device, layout in LAYOUTS.items():
        src_dir = raw / device
        if not src_dir.is_dir():
            continue
        (out / device).mkdir(parents=True, exist_ok=True)
        for src in sorted(src_dir.glob("*.png")):
            caption = CAPTIONS.get(src.stem)
            if caption is None:
                print(f"skip {device}/{src.name}: no caption defined")
                continue
            img = frame(src, layout, caption)
            assert img.size == layout["size"], img.size
            img.save(out / device / src.name, optimize=True)
            print(f"framed {device}/{src.name} {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
