#!/usr/bin/env python3
"""Stitch all PNGs from a scenario/test run into one labeled grid PNG.

Instant-eyeball view of a capture directory — no clicking through files.

Usage:
    python3 tools/contact_sheet.py /tmp/castle_clash_scenarios/place_building
    python3 tools/contact_sheet.py /tmp/castle_clash_test -o /tmp/autotest_sheet.png --cols 5
"""
import argparse
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

LABEL_H = 24
GAP = 6
BG = (24, 24, 30)
LABEL_COLOR = (230, 225, 205)


def main() -> int:
    ap = argparse.ArgumentParser(description="Build a labeled contact sheet from a directory of PNGs")
    ap.add_argument("input_dir", help="directory containing capture PNGs")
    ap.add_argument("-o", "--output", default=None,
                    help="output path (default: <input_dir>/contact_sheet.png)")
    ap.add_argument("--cols", type=int, default=4, help="grid columns (default 4)")
    ap.add_argument("--thumb-width", type=int, default=252,
                    help="thumbnail width in px (default 252 = 0.35x of 720)")
    args = ap.parse_args()

    out_path = args.output or os.path.join(args.input_dir, "contact_sheet.png")
    pngs = sorted(glob.glob(os.path.join(args.input_dir, "*.png")))
    pngs = [p for p in pngs if os.path.abspath(p) != os.path.abspath(out_path)
            and not p.endswith("contact_sheet.png")]
    if not pngs:
        print(f"contact_sheet: no PNGs in {args.input_dir}")
        return 1

    thumbs = []
    for p in pngs:
        img = Image.open(p).convert("RGB")
        scale = args.thumb_width / img.width
        img = img.resize((args.thumb_width, max(1, int(img.height * scale))), Image.LANCZOS)
        thumbs.append((os.path.splitext(os.path.basename(p))[0], img))

    cols = max(1, min(args.cols, len(thumbs)))
    rows = (len(thumbs) + cols - 1) // cols
    cell_w = args.thumb_width
    cell_h = max(t[1].height for t in thumbs) + LABEL_H
    sheet = Image.new("RGB", (cols * (cell_w + GAP) + GAP, rows * (cell_h + GAP) + GAP), BG)
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
    except (OSError, IOError):
        font = ImageFont.load_default()

    for i, (label, img) in enumerate(thumbs):
        cx = GAP + (i % cols) * (cell_w + GAP)
        cy = GAP + (i // cols) * (cell_h + GAP)
        sheet.paste(img, (cx, cy))
        draw.rectangle([cx, cy, cx + cell_w - 1, cy + img.height - 1], outline=(70, 70, 80))
        draw.text((cx + 2, cy + img.height + 4), label, fill=LABEL_COLOR, font=font)

    sheet.save(out_path)
    print(f"contact_sheet: {len(thumbs)} captures -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
