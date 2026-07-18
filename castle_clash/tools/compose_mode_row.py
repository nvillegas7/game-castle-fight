#!/usr/bin/env python3
"""compose_mode_row.py — design-space compositor for the battle-tab game-mode
selector (backlog 3.1; the old T-056 selector predates the P2 redesign).

Two placement OPTIONS on the current battle capture:
  a — compact row in the grass gap ABOVE the BATTLE plateau (y≈746)
  b — row on the green band BELOW the PLAY ONLINE chip (y≈1102)
Kit language: stat-chip buttons (16px labels), selected = gold ring (Avatars
picker pattern) + one 16px description line under the row.

Usage:
  python3 tools/compose_mode_row.py            # both → design/concepts/
  python3 tools/compose_mode_row.py --variant a  # one → design/battle_mode_row_target.png
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "design" / "battle_mode_row_target.png"
W, H = 720, 1280
FONT = str(ROOT / "assets" / "fonts" / "PixelOperatorBold.ttf")
F16 = ImageFont.truetype(FONT, 16)

TEXT_CREAM = (237, 222, 184)
OUTLINE = (26, 18, 8)
GOLD = (255, 210, 60)
CHIP_BG = (40, 30, 20)
CHIP_BORDER = (120, 92, 48)

# ---------------------------------------------------------------- layout --
# PORT VERBATIM into main_menu._build_mode_row.
CHIP_W, CHIP_H, CHIP_GAP = 150, 44, 16
MODES = ["Standard", "Blitz", "Mirror"]
DESCS = {
    "a": "Classic match — standard rules",
}
ROW_Y = {"a": 712.0, "b": 1076.0}   # chip row top
DESC_DY = 52                        # description line offset under the row


def txt(d, xy, s, font, fill, px=2, anchor="la"):
    for dx in range(-px, px + 1):
        for dy in range(-px, px + 1):
            if dx or dy:
                d.text((xy[0] + dx, xy[1] + dy), s, font=font, fill=OUTLINE, anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def render(variant: str) -> Image.Image:
    cap = Image.open(ROOT / "test_output" / "autotest" / "menu_battle_000.png").convert("RGBA")
    img = cap.resize((W, H), Image.NEAREST)
    d = ImageDraw.Draw(img)
    row_y = ROW_Y[variant]
    total = 3 * CHIP_W + 2 * CHIP_GAP
    x = (W - total) / 2
    for i, m in enumerate(MODES):
        cx = x + i * (CHIP_W + CHIP_GAP)
        sel = (i == 0)
        d.rounded_rectangle([cx, row_y, cx + CHIP_W, row_y + CHIP_H], radius=10,
                            fill=CHIP_BG + (225,),
                            outline=(GOLD if sel else CHIP_BORDER) + (255,),
                            width=3 if sel else 2)
        txt(d, (cx + CHIP_W / 2, row_y + CHIP_H / 2), m, F16,
            (GOLD if sel else TEXT_CREAM), px=1, anchor="mm")
    txt(d, (W / 2, row_y + DESC_DY), "Classic match — standard rules", F16,
        (210, 196, 162), px=1, anchor="mm")
    return img


if __name__ == "__main__":
    if "--variant" in sys.argv:
        v = sys.argv[sys.argv.index("--variant") + 1]
        render(v).save(OUT)
        print(f"wrote {OUT} (variant {v})")
    else:
        outdir = ROOT / "design" / "concepts"
        outdir.mkdir(parents=True, exist_ok=True)
        for v in ["a", "b"]:
            p = outdir / f"mode_row_{v}.png"
            render(v).save(p)
            print(f"wrote {p}")
