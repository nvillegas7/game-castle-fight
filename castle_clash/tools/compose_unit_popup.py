#!/usr/bin/env python3
"""compose_unit_popup.py — design-space compositor for the Army-tab unit
detail view (backlog 3.6).

THE FLOW (tasks/design-flow.md): iterate HERE (~0.1s/render) → user approves →
design/army_popup_target.png is the pixel spec → main_menu.gd PORTS the LAYOUT
verbatim (same assets, same geometry; UIStyle semantics: fonts 16/32 only).

Three CONCEPT VARIANTS (user asked for a rethink of the centered modal,
2026-07-18 — all four axes: layout, content, style, interaction):
  sheet — CR-style bottom sheet on the card-hand wood-table language
  card  — expand-in-place: the tapped card grows inside the list, no scrim
  page  — KR-style full-page hero takeover with back button

Shared content language (de-spreadsheeted, matching P4): STAT TILES (wood
slots, big values) instead of label:value rows; role chips; skill strips WITH
short descriptions (drafted here — the port needs a reviewed SKILL_DESC table).
Mock = real footman.tres / barracks.tres values.

Usage:
  python3 tools/compose_unit_popup.py                # all 3 → design/concepts/
  python3 tools/compose_unit_popup.py --variant sheet  # one → design/army_popup_target.png
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "assets" / "sprites" / "ui"
OUT = ROOT / "design" / "army_popup_target.png"
W, H = 720, 1280

FONT = str(ROOT / "assets" / "fonts" / "PixelOperatorBold.ttf")
F16 = ImageFont.truetype(FONT, 16)
F32 = ImageFont.truetype(FONT, 32)

TEXT_CREAM = (237, 222, 184)
TEXT_GOLD = (255, 224, 89)
TEXT_DIM = (200, 186, 152)
OUTLINE = (26, 18, 8)
PANEL_WOOD = (56, 41, 26)
PANEL_BORDER = (140, 107, 56)

MOCK = {
    "name": "FOOTMAN",
    "chips": [("Melee", (86, 125, 70)), ("Physical", (140, 128, 128)),
              ("Light armor", (128, 133, 140))],
    # (label, value) — core 6 as tiles; extras line below
    "tiles": [("HP", "180"), ("DMG", "10"), ("SPD", "2"),
              ("RNG", "1"), ("ARM", "3"), ("ATK/S", "1.0")],
    "extras": "Aggro 7 · Magic def 0 · Bounty 5g",
    "skills": [("Shield Wall", "Raises shields to block incoming damage."),
               ("Devotion Aura", "Nearby allies take reduced damage.")],
    "trained": "Trained at Barracks · 50g · Tier 1",
}


def ninepatch(src, w, h, m, my=-1):
    sw, sh = src.size
    if my < 0:
        my = m
    out = Image.new("RGBA", (w, h))
    xs = [(0, m, 0, m), (m, sw - m, m, w - m), (sw - m, sw, w - m, w)]
    ys = [(0, sh, 0, h)] if my == 0 else \
        [(0, my, 0, my), (my, sh - my, my, h - my), (sh - my, sh, h - my, h)]
    for sy0, sy1, dy0, dy1 in ys:
        for sx0, sx1, dx0, dx1 in xs:
            piece = src.crop((sx0, sy0, sx1, sy1))
            if piece.size[0] and piece.size[1] and dx1 > dx0 and dy1 > dy0:
                out.alpha_composite(piece.resize((dx1 - dx0, dy1 - dy0), Image.NEAREST), (dx0, dy0))
    return out


def txt(d, xy, s, font, fill, px=2, anchor="la"):
    for dx in range(-px, px + 1):
        for dy in range(-px, px + 1):
            if dx or dy:
                d.text((xy[0] + dx, xy[1] + dy), s, font=font, fill=OUTLINE, anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def unit_sprite(height_px: int) -> Image.Image:
    sheet = Image.open(ROOT / "assets" / "sprites" / "units" / "blue_warrior" / "Warrior_Idle.png").convert("RGBA")
    fh = sheet.size[1]
    fw = fh if sheet.size[0] % fh == 0 else sheet.size[0] // 8
    content = sheet.crop((0, 0, fw, fh))
    content = content.crop(content.getbbox())
    s = height_px / content.size[1]
    return content.resize((round(content.size[0] * s), height_px), Image.NEAREST)


def chips_row(d, x, y, gap=8):
    for label, col in MOCK["chips"]:
        tw = d.textlength(label, font=F16)
        d.rounded_rectangle([x, y, x + tw + 24, y + 30], radius=8,
                            fill=col + (110,), outline=col + (200,), width=2)
        txt(d, (x + 12 + tw / 2, y + 15), label, F16, TEXT_CREAM, px=1, anchor="mm")
        x += tw + 24 + gap
    return x


def stat_tiles(img, d, x0, y0, tile_w, tile_h, cols, gap=10):
    for i, (label, val) in enumerate(MOCK["tiles"]):
        cx = x0 + (i % cols) * (tile_w + gap)
        cy = y0 + (i // cols) * (tile_h + gap)
        d.rounded_rectangle([cx, cy, cx + tile_w, cy + tile_h], radius=10,
                            fill=PANEL_WOOD + (235,), outline=PANEL_BORDER + (255,), width=2)
        txt(d, (cx + tile_w / 2, cy + 16), label, F16, TEXT_DIM, px=1, anchor="mm")
        txt(d, (cx + tile_w / 2, cy + tile_h - 20), val, F32, TEXT_CREAM, px=1, anchor="mm")
    return y0 + ((len(MOCK["tiles"]) + cols - 1) // cols) * (tile_h + gap)


def skill_strips(img, d, x0, y0, w, strip_h=58, gap=8):
    for i, (name, desc) in enumerate(MOCK["skills"]):
        yy = y0 + i * (strip_h + gap)
        d.rounded_rectangle([x0, yy, x0 + w, yy + strip_h], radius=10,
                            fill=(66, 50, 30, 200), outline=(160, 128, 66, 255), width=2)
        txt(d, (x0 + 14, yy + 8), name, F16, TEXT_GOLD, px=1)
        txt(d, (x0 + 14, yy + 32), desc, F16, TEXT_DIM, px=1)
    return y0 + len(MOCK["skills"]) * (strip_h + gap)


def army_backdrop(dim: int) -> Image.Image:
    cap = Image.open(ROOT / "test_output" / "autotest" / "menu_army_000.png").convert("RGBA")
    img = cap.resize((W, H), Image.NEAREST)
    if dim:
        img.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, dim)))
    return img


# ---------------------------------------------------------------- variants --

def render_sheet() -> Image.Image:
    """CR-style bottom sheet: wood-table panel sliding up over a light scrim,
    anchored above the tab bar. Tap outside (or the notch) to dismiss."""
    img = army_backdrop(110)
    d = ImageDraw.Draw(img)
    wood = Image.open(UI / "ninepatch" / "woodtable.png").convert("RGBA")
    P = (16, 640, 704, 1150)  # sheet rect (above tab bar at 1160)
    img.alpha_composite(ninepatch(wood, P[2] - P[0], P[3] - P[1], 84), (P[0], P[1]))
    d = ImageDraw.Draw(img)
    # Drag notch
    d.rounded_rectangle([320, 654, 400, 664], radius=5, fill=(30, 22, 14, 255))
    # Header: name + cost/tier right
    txt(d, (44, 682), MOCK["name"], F32, TEXT_GOLD)
    txt(d, (676, 690), "50g · T1", F16, TEXT_CREAM, px=1, anchor="ra")
    chips_row(d, 44, 726)
    # Sprite left, tiles right
    spr = unit_sprite(150)
    img.alpha_composite(spr, (100 - spr.size[0] // 2, 790))
    d = ImageDraw.Draw(img)
    stat_tiles(img, d, 190, 782, 152, 74, 3)
    txt(d, (190, 950), MOCK["extras"], F16, TEXT_DIM, px=1)
    skill_strips(img, d, 44, 986, 632)
    return img


def render_card() -> Image.Image:
    """Expand-in-place: the tapped card grows inside the list (no scrim, list
    stays live behind); tap again to collapse."""
    img = army_backdrop(0)
    d = ImageDraw.Draw(img)
    # Expanded card replaces the tapped one at its list slot (footman ≈ y=306)
    C = (20, 300, 700, 810)
    d.rounded_rectangle(C, radius=12, fill=(66, 48, 30, 250), outline=(150, 115, 60, 255), width=3)
    d = ImageDraw.Draw(img)
    spr = unit_sprite(160)
    img.alpha_composite(spr, (110 - spr.size[0] // 2, 340))
    d = ImageDraw.Draw(img)
    txt(d, (210, 330), MOCK["name"], F32, TEXT_GOLD)
    txt(d, (676, 338), "50g · T1", F16, TEXT_CREAM, px=1, anchor="ra")
    chips_row(d, 210, 376)
    stat_tiles(img, d, 210, 420, 148, 72, 3)
    txt(d, (210, 582), MOCK["extras"], F16, TEXT_DIM, px=1)
    skill_strips(img, d, 40, 616, 640)
    # collapse hint chevron
    txt(d, (360, 786), "^ tap to close ^", F16, TEXT_DIM, px=1, anchor="mm")
    return img


def render_page() -> Image.Image:
    """KR-style full-page hero takeover: the content area becomes the unit
    page (header + tab bar stay); back chevron returns to the roster."""
    img = army_backdrop(0)
    d = ImageDraw.Draw(img)
    paper = Image.open(UI / "ninepatch" / "regularpaper.png").convert("RGBA")
    P = (8, 96, 712, 1150)
    img.alpha_composite(ninepatch(paper, P[2] - P[0], P[3] - P[1], 28), (P[0], P[1]))
    d = ImageDraw.Draw(img)
    # Back button
    btn = Image.open(UI / "TinyRoundRedButton.png").convert("RGBA")
    img.alpha_composite(btn, (28, 112))
    d = ImageDraw.Draw(img)
    txt(d, (60, 144), "<", F32, TEXT_CREAM, px=1, anchor="mm")
    # Hero: big sprite on a grass pedestal strip
    d.rounded_rectangle([120, 150, 600, 390], radius=14, fill=(104, 152, 78, 255),
                        outline=(70, 105, 52, 255), width=3)
    spr = unit_sprite(220)
    img.alpha_composite(spr, (360 - spr.size[0] // 2, 158))
    d = ImageDraw.Draw(img)
    # Name ribbon under the hero strip
    ribbon = Image.open(UI / "ninepatch" / "ribbon_blue.png").convert("RGBA")
    img.alpha_composite(ninepatch(ribbon, 380, 103, 70, 0), (170, 356))
    d = ImageDraw.Draw(img)
    txt(d, (360, 398), MOCK["name"], F32, TEXT_CREAM, anchor="mm")
    cx_end = chips_row(d, 360 - 170, 478)
    stat_tiles(img, d, 120, 530, 152, 80, 3)
    txt(d, (360, 720), MOCK["extras"], F16, TEXT_DIM, px=1, anchor="mm")
    skill_strips(img, d, 100, 754, 520)
    txt(d, (360, 908), MOCK["trained"], F16, TEXT_DIM, px=1, anchor="mm")
    return img


VARIANTS = {"sheet": render_sheet, "card": render_card, "page": render_page}

if __name__ == "__main__":
    if "--variant" in sys.argv:
        v = sys.argv[sys.argv.index("--variant") + 1]
        im = VARIANTS[v]()
        OUT.parent.mkdir(exist_ok=True)
        im.save(OUT)
        print(f"wrote {OUT} ({v})")
    else:
        outdir = ROOT / "design" / "concepts"
        outdir.mkdir(parents=True, exist_ok=True)
        for v, fn in VARIANTS.items():
            p = outdir / f"army_popup_{v}.png"
            fn().save(p)
            print(f"wrote {p}")
