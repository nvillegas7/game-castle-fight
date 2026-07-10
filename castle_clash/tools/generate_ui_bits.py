#!/usr/bin/env python3
"""Generate the two UI bits the ninepatch kit is missing (P0 foundation).

Outputs (pixel-art, NEAREST-filtered in engine):
  assets/sprites/ui/star_gold.png   32x32  filled gold 5-point star + dark rim  (P3 end-screen tier stars)
  assets/sprites/ui/star_empty.png  32x32  same silhouette, dim/desaturated     (empty tier slot)
  assets/sprites/ui/padlock.png     24x24  brass padlock (shackle + body)        (P1 locked cards)

Drawn at target resolution with hard (aliased) edges so the pixel look survives NEAREST
scaling. No anti-aliasing, no procedural rotation (lessons: never rotate pixel art).
Run:  python3 tools/generate_ui_bits.py   (from castle_clash/)
"""
import math
import os

from PIL import Image, ImageDraw

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "ui")


def star_points(cx, cy, r_out, r_in, n=5):
    """Return the 2n vertices of an n-point star, first outer point straight up."""
    pts = []
    for i in range(n * 2):
        ang = -math.pi / 2 + i * math.pi / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def make_star(fill, outline, size=32):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2 - 0.5
    pts = star_points(c, c, r_out=size * 0.47, r_in=size * 0.20)
    d.polygon(pts, fill=fill, outline=outline)
    # thicken rim by re-stroking the outline (width param on polygon is unreliable pre-Pillow 9.2)
    d.line(pts + [pts[0]], fill=outline, width=2, joint="curve")
    return img


def make_padlock(size=24):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    metal = (150, 140, 120, 255)
    metal_rim = (70, 62, 48, 255)
    brass = (206, 162, 66, 255)
    brass_rim = (96, 66, 18, 255)
    keyhole = (74, 50, 10, 255)
    # Shackle: an open-bottom arc above the body.
    d.arc((7, 3, 17, 15), start=180, end=360, fill=metal, width=3)
    d.arc((7, 3, 17, 15), start=180, end=360, fill=metal_rim, width=1)
    # Body: rounded brass block.
    d.rounded_rectangle((4, 11, 20, 22), radius=3, fill=brass, outline=brass_rim, width=1)
    # Keyhole: pin + slot.
    d.ellipse((10, 14, 14, 18), fill=keyhole)
    d.rectangle((11, 17, 13, 20), fill=keyhole)
    return img


def make_trophy(size=28):
    """Gold trophy cup (P2 header) — the Tiny Swords pack has no trophy icon."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    gold = (232, 184, 66, 255)
    rim = (150, 102, 28, 255)
    dark = (70, 48, 10, 255)
    hi = (255, 226, 120, 255)
    # Handles (behind the bowl).
    d.arc((2, 5, 11, 16), start=90, end=270, fill=rim, width=2)    # left
    d.arc((17, 5, 26, 16), start=270, end=90, fill=rim, width=2)   # right
    # Bowl: trapezoid narrowing downward.
    d.polygon([(6, 7), (22, 7), (18, 16), (10, 16)], fill=gold, outline=dark)
    d.line([(7, 8), (21, 8)], fill=hi, width=1)                    # rim highlight
    # Stem + tiered base.
    d.rectangle((12, 16, 15, 20), fill=gold, outline=dark)
    d.rectangle((9, 20, 18, 22), fill=rim, outline=dark)
    d.rectangle((7, 22, 20, 25), fill=gold, outline=dark)
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    outputs = {
        "star_gold.png": make_star(fill=(255, 205, 60, 255), outline=(92, 56, 14, 255)),
        "star_empty.png": make_star(fill=(74, 64, 48, 255), outline=(44, 36, 24, 255)),
        "padlock.png": make_padlock(),
        "trophy.png": make_trophy(),
    }
    for name, img in outputs.items():
        p = os.path.abspath(os.path.join(OUT_DIR, name))
        img.save(p)
        bbox = img.getbbox()
        print(f"wrote {p}  {img.size}  alpha_bbox={bbox}")


if __name__ == "__main__":
    main()
