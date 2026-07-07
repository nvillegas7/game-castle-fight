#!/usr/bin/env python3
"""compose_arena.py — design-space compositor for the battle arena screen.

WHY THIS EXISTS (tasks/design-flow.md):
  The mockups the user commissioned (Desktop v1/v2/v3) were composed in IMAGE
  SPACE from the real game assets — seconds per iteration, full visual feedback
  on every placement. Our old flow composed art blind in GDScript coordinates
  with a ~90s boot-and-capture feedback loop, and it never converged.

  New flow:
    1. Iterate the look HERE   (python3 tools/compose_arena.py → ~1s render)
    2. User approves the output → design/arena_target.png IS the pixel spec
    3. The LAYOUT table below is the single source of truth; the game-side
       implementation mirrors it mechanically (same asset, same xy, same scale)
    4. Gate: capture vs target perceptual diff (tests), not vibes

Renders at native 720x1280. Sim geometry mirrored from game_arena.gd —
gameplay occupies x=[206,514] (11 cols x 28px); castles at (360,120)/(360,920);
build grids y=[55,335] (enemy) and y=[695,975] (player). Everything outside
x=[206,514] is decoration-only space.

Usage:
  python3 tools/compose_arena.py            # render design/arena_target.png
  python3 tools/compose_arena.py --grid     # + overlay sim geometry (debug)
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent  # castle_clash/
A = ROOT / "assets" / "sprites"
TER = A / "terrain"
OUT = ROOT / "design" / "arena_target.png"

W, H = 720, 1280
TS = 64  # terrain tile size

# ---------------------------------------------------------------- asset io --

_cache = {}


def load(path: Path) -> Image.Image:
    key = str(path)
    if key not in _cache:
        _cache[key] = Image.open(path).convert("RGBA")
    return _cache[key]


def tile_of(sheet: Path, col: int, row: int) -> Image.Image:
    return load(sheet).crop((col * TS, row * TS, (col + 1) * TS, (row + 1) * TS))


def frame_of(sheet: Path, idx: int = 0) -> Image.Image:
    """Square frame idx from a horizontal strip (frame size = sheet height)."""
    im = load(sheet)
    fh = im.size[1]
    return im.crop((idx * fh, 0, (idx + 1) * fh, fh))


def blit(dst: Image.Image, src: Image.Image, cx: float, cy: float,
         scale: float = 1.0, flip_h: bool = False, flip_v: bool = False,
         anchor: str = "bottom") -> None:
    """Paste src centered-x at cx; anchor='bottom' puts the sprite's content
    bottom at cy (how things 'stand' on the ground), 'center' centers it."""
    if flip_h:
        src = src.transpose(Image.FLIP_LEFT_RIGHT)
    if flip_v:
        src = src.transpose(Image.FLIP_TOP_BOTTOM)
    if scale != 1.0:
        src = src.resize((max(1, round(src.size[0] * scale)),
                          max(1, round(src.size[1] * scale))), Image.NEAREST)
    bbox = src.getbbox()
    if bbox is None:
        return
    cw, chh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = round(cx - bbox[0] - cw / 2)
    if anchor == "bottom":
        y = round(cy - bbox[3])
    else:
        y = round(cy - bbox[1] - chh / 2)
    dst.alpha_composite(src, (x, y))


# ------------------------------------------------------------------ layout --
# The single source of truth. The game-side port reads THESE values.
# All placements are (cx, ground_y) unless noted. Symmetry: the player half is
# the enemy half mirrored about y=PIVOT (blue variants instead of red).

PIVOT = 520.0  # play-area midline, = FLIP_PIVOT_Y in game_arena.gd

GRASS = TER / "Tilemap_color1.png"   # sunny green flat tiles (3x3 at cols 0-2)
ELEV = TER / "Tilemap_color1.png"    # elevated/stone tiles (cols 5-8)
WATER = TER / "Water Background color.png"
FOAM = TER / "Water Foam.png"

# Grass platform (the island). Water fills everything else.
# 64px-grid-aligned: x tiles 1..10 → x=[64,704]... chosen: x=[72,648] can't
# grid-align; use tile grid offset 8 so platform = 9 tiles [72..648].
PLAT_X0, PLAT_X1 = 72, 648     # land span (9 tiles wide, offset 8)
PLAT_Y0, PLAT_Y1 = 56, 984     # land span vertically
CORNER_CUT = 1                  # corner tiles rounded

BUILDINGS = {
    "castle": {"asset": "Castle.png", "scale": 0.90},   # 312px content → ~281px
    "tower": {"asset": "Tower.png", "scale": 0.72},     # 120px content → ~86px
    "house1": {"asset": "House1.png", "scale": 0.62},
    "house2": {"asset": "House2.png", "scale": 0.62},
}

# Enemy (red, top) half placements; player half auto-mirrored.
ENEMY_HALF = {
    "castle": (360, 210),          # big centered fortress, base y=210
    "towers": [(140, 268), (580, 268)],
    "houses": [("house1", 122, 150), ("house2", 598, 146)],
    # stone wall (solid stone face row) castle base → towers, like mockup v2
    "wall_y": 150,                  # top-left y of wall tile row
    "wall_x": (140, 580),
}

TREE_CLUSTERS = [                   # (cx, ground_y, n) — outer bands, ON LAND
    (136, 428, 3), (584, 438, 3),
    (128, 580, 2), (592, 590, 2),
]
SHEEP = [(178, 392, False), (542, 392, True), (160, 668, False), (560, 660, True)]
GOLD = [(178, 508, 3), (542, 508, 3)]      # (cx, cy, n nuggets)
BUSHES = [(168, 322, 0), (552, 318, 1), (168, 740, 2), (552, 734, 3)]
ROCKS = [(340, 508, 0), (388, 540, 1)]     # tiny midfield accents
WATER_ROCKS = [(40, 300, 0), (684, 360, 1), (34, 700, 2), (688, 760, 3)]


# ------------------------------------------------------------------ render --

def render(show_grid: bool = False) -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))

    # 1. Water base — everywhere, organic life comes from foam + rocks
    wtile = load(WATER)
    for y in range(0, H, TS):
        for x in range(0, W, TS):
            img.alpha_composite(wtile, (x, y))

    # 2. Foam dashes hugging the coastline (drawn before land so it peeks out
    #    from under the edge tiles — small, staggered, like the mockup's dashes)
    foam = frame_of(FOAM, 0)
    fs = 0.32
    for i, x in enumerate(range(PLAT_X0, PLAT_X1 - 24, 60)):
        jig = 8 if i % 2 else -5
        blit(img, foam, x + 30 + jig, PLAT_Y0 + 14, fs, anchor="center")
        blit(img, foam, x + 30 - jig, PLAT_Y1 + 4, fs, anchor="center", flip_v=True)
    for i, y in enumerate(range(PLAT_Y0, PLAT_Y1 - 24, 60)):
        jig = 9 if i % 2 else -6
        blit(img, foam, PLAT_X0 - 2, y + 30 + jig, fs, anchor="center")
        blit(img, foam, PLAT_X1 + 2, y + 30 - jig, fs, anchor="center", flip_h=True)

    # 3. Grass platform with proper 3x3 edge tiles + rounded corners
    cols = (PLAT_X1 - PLAT_X0) // TS
    rows = (PLAT_Y1 - PLAT_Y0) // TS
    for r in range(rows):
        for c in range(cols):
            is_t, is_b = r == 0, r == rows - 1
            is_l, is_r = c == 0, c == cols - 1
            # rounded corners: skip the extreme corner tile, use corner art next to it
            if (is_t or is_b) and (is_l or is_r):
                gx, gy = (0 if is_l else 2), (0 if is_t else 2)
            elif is_t:
                gx, gy = 1, 0
            elif is_b:
                gx, gy = 1, 2
            elif is_l:
                gx, gy = 0, 1
            elif is_r:
                gx, gy = 2, 1
            else:
                gx, gy = 1, 1
            img.alpha_composite(tile_of(GRASS, gx, gy),
                                (PLAT_X0 + c * TS, PLAT_Y0 + r * TS))

    # 4+5. Per-half fortress composition (enemy red top, player blue mirrored)
    for team, faction in (("red", False), ("blue", True)):
        bdir = A / "buildings" / team

        def my(y: float) -> float:  # mirror ground-y for the player half
            return y if not faction else 2 * PIVOT - y

        # stone wall row first (behind buildings) — solid stone face like v2
        wy = ENEMY_HALF["wall_y"]
        wy = wy if not faction else 2 * PIVOT - wy - TS
        wall_tile = tile_of(ELEV, 6, 4)
        if faction:
            wall_tile = wall_tile.transpose(Image.FLIP_TOP_BOTTOM)
        x0, x1 = ENEMY_HALF["wall_x"]
        x = x0
        while x < x1:
            img.alpha_composite(wall_tile, (x, round(wy)))
            x += TS

        cx, cy = ENEMY_HALF["castle"]
        blit(img, load(bdir / "Castle.png"), cx, my(cy), BUILDINGS["castle"]["scale"])
        for tx, ty in ENEMY_HALF["towers"]:
            blit(img, load(bdir / "Tower.png"), tx, my(ty), BUILDINGS["tower"]["scale"])
        for hname, hx, hy in ENEMY_HALF["houses"]:
            blit(img, load(bdir / BUILDINGS[hname]["asset"]), hx, my(hy),
                 BUILDINGS[hname]["scale"])

    # 6. Decorations — FULL OPACITY, native palette, clustered like the mockups
    for cx, gy, n in TREE_CLUSTERS:
        for k in range(n):
            t = frame_of(TER / "Resources" / f"Tree{(k % 4) + 1}.png", 0)
            dx = (k - n / 2) * 40 + 20
            blit(img, t, cx + dx, gy + (k % 2) * 26, 0.52)
            blit(img, t, cx + dx, 2 * PIVOT - gy + (k % 2) * 26, 0.52)  # mirror half

    for bx, by, i in BUSHES:
        b = frame_of(TER / "Decorations" / f"Bushe{i + 1}.png", 0)
        blit(img, b, bx, by, 0.5)
    for rx, ry, i in ROCKS:
        blit(img, load(TER / "Decorations" / f"Rock{i + 1}.png"), rx, ry, 0.4)
    for wx, wy2, i in WATER_ROCKS:
        blit(img, frame_of(TER / "Decorations" / f"Water Rocks_{i + 1:02d}.png", 0),
             wx, wy2, 0.5)

    sheep_img = frame_of(TER / "Resources" / "Sheep_Idle.png", 0)
    for sx, sy, flip in SHEEP:
        blit(img, sheep_img, sx, sy, 0.55, flip_h=flip)
        blit(img, sheep_img, sx, 2 * PIVOT - sy, 0.55, flip_h=not flip)

    for gx2, gy2, n in GOLD:
        for k in range(n):
            g = load(TER / "Resources" / f"Gold Stone {(k % 6) + 1}.png")
            blit(img, g, gx2 + (k - n / 2) * 34 + 17, gy2 + (k % 2) * 16, 0.55)

    # 7. HUD occlusion zones (honest preview of what the player actually sees)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.rectangle([0, 0, W, 40], fill=(20, 10, 8, 210))          # top HUD ribbon
    d.rectangle([0, 985, W, H], fill=(20, 10, 8, 210))         # gold bar + cards
    d.text((W // 2 - 30, 14), "HUD", fill=(200, 180, 160, 255))
    d.text((W // 2 - 60, 1100), "CARD HAND", fill=(200, 180, 160, 255))
    img = Image.alpha_composite(img, ov)

    if show_grid:
        d = ImageDraw.Draw(img)
        for rect, label in [((206, 55, 514, 335), "ENEMY GRID"),
                            ((206, 695, 514, 975), "PLAYER GRID"),
                            ((206, 350, 514, 690), "COMBAT")]:
            d.rectangle(rect, outline=(255, 0, 0, 255), width=2)
            d.text((rect[0] + 4, rect[1] + 4), label, fill=(255, 0, 0, 255))
        d.line([(0, PIVOT), (W, PIVOT)], fill=(255, 255, 0, 180), width=1)

    return img


if __name__ == "__main__":
    OUT.parent.mkdir(exist_ok=True)
    im = render(show_grid="--grid" in sys.argv)
    im.save(OUT)
    print(f"wrote {OUT} ({im.size[0]}x{im.size[1]})")
