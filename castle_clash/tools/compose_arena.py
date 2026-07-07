#!/usr/bin/env python3
"""compose_arena.py — design-space compositor for the battle arena screen.

THE FLOW (tasks/design-flow.md): iterate the look HERE (~0.1s/render, real
assets, real 720x1280 geometry) → user approves → design/arena_target.png is
the pixel spec → the game PORTS the LAYOUT tables below verbatim → parity
detectors in tests/test_screen_layout.gd pin it.

INVARIANTS (user feedback 2026-07-08):
  * SYMMETRY BY CONSTRUCTION, PERSPECTIVE-LOCKED — decorations are authored
    for the LEFT side of the ENEMY (top) half only. Right side = x-mirror
    (720-x, same y). Player half = y-mirror about FLIP_PIVOT (1040-y).
    POSITIONS mirror; ORIENTATIONS never do: the 2.5D camera does not flip
    with the layout, so elevation/cliff tiles keep their stone "bar" face
    pointing SOUTH (screen-down) on BOTH halves, with only the thin rim line
    on top denoting height (user feedback 2026-07-08, Tiny Swords reference).
    Never flip_v a terrain or building tile.
  * Y-SORTED RENDERING — decorations paint back-to-front by ground-y exactly
    like the game's y-sorted DecorationLayer, so layering bugs (sheep floating
    on trees) are visible HERE before approval, not after the port.
  * CALIBRATED SCALE — landmark sizes come from MEASURED reference fractions
    (forensics wf_772ab315): castle = 0.296 of playfield width → 0.68 native.
    Never eyeball a scale when a measured number exists.
  * Castles sit ON their sim anchors (360,120)/(360,920); at 0.68 the castle
    overhangs the island rim by ~23px — "seated at the cliff" like mockup v2.

Sim geometry (game_arena.gd): gameplay column x=[206,514]; build grids
y=[55,335]/[695,975]; FLIP_PIVOT_Y=520. Outside the column = decoration space.

Usage:
  python3 tools/compose_arena.py            # → design/arena_target.png
  python3 tools/compose_arena.py --grid     # + sim geometry overlay
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent  # castle_clash/
A = ROOT / "assets" / "sprites"
TER = A / "terrain"
OUT = ROOT / "design" / "arena_target.png"

W, H = 720, 1280
TS = 64
PIVOT = 520.0  # FLIP_PIVOT_Y

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
    im = load(sheet)
    fh = im.size[1]
    return im.crop((idx * fh, 0, (idx + 1) * fh, fh))


def blit(dst, src, cx, cy, scale=1.0, flip_h=False, flip_v=False, anchor="bottom"):
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
    y = round(cy - bbox[3]) if anchor == "bottom" else round(cy - bbox[1] - chh / 2)
    dst.alpha_composite(src, (x, y))


# ------------------------------------------------------------------ layout --
# PORT THESE VERBATIM. Author left-side/enemy-half only — mirrors generated.

GRASS = TER / "Tilemap_color1.png"
WATER_RGB = (71, 171, 169)          # native water texel — NEVER tint
FOAM = TER / "Water Foam.png"

# Island platform: symmetric about PIVOT (72+968 = 2*520 ✓), 9x14 tiles.
PLAT_X0, PLAT_X1 = 72, 648
PLAT_Y0, PLAT_Y1 = 72, 968

CASTLE_SCALE = 0.544                 # 0.68 measured mockup fraction x0.8 (user: placed buildings overlapped the castle)
CASTLE_ANCHOR = (360, 120)           # sim anchor (enemy); player = y-mirror

# Fortress dressing (enemy half; x already centered/paired where needed)
WALL_Y_ENEMY = 112                   # stone bottom (176) = red castle base at 0.544
WALL_Y_PLAYER = 912                  # stone bottom (976) = blue castle base — face STILL south
WALL_X = (140, 580)
TOWER_SCALE, TOWER_GY = 0.72, 268    # flanking towers at x=140 / 720-140
HOUSE = ("House1.png", 122, 148, 0.62)   # corner house; mirrored 4x

# Decorations — LEFT side of ENEMY half only. (cx, ground_y, extra)
TREES_L = [(110, 428, 3), (110, 580, 2)]     # (cx, gy, count)
SHEEP_L = [(190, 350), (190, 620)]           # graze spots, inboard of trees
GOLD_L = [(188, 505)]                        # nugget cluster
BUSH_L = [(170, 250, 1)]                     # (cx, gy, sprite idx)
WROCK_L = [(40, 300, 1), (34, 470, 3)]       # in-water rocks
ROCK_MID = (340, 508, 1)                     # midfield accent; point-mirrored

TREE_SCALE, SHEEP_SCALE, GOLD_SCALE = 0.52, 0.55, 0.55
BUSH_SCALE, ROCK_SCALE, WROCK_SCALE = 0.5, 0.4, 0.5


def mirror_x(x: float) -> float:
    return 720.0 - x


def mirror_y(y: float) -> float:
    return 2.0 * PIVOT - y


# ------------------------------------------------------------------ render --

def render(show_grid: bool = False) -> Image.Image:
    img = Image.new("RGBA", (W, H), WATER_RGB + (255,))

    # Foam dashes hugging all four coasts (before land, peeking out)
    foam = frame_of(FOAM, 0)
    for i, x in enumerate(range(PLAT_X0, PLAT_X1 - 24, 60)):
        jig = 8 if i % 2 == 0 else -5
        blit(img, foam, x + 30 + jig, PLAT_Y0 + 14, 0.32, anchor="center")
        blit(img, foam, x + 30 - jig, PLAT_Y1 + 4, 0.32, anchor="center", flip_v=True)
    for i, y in enumerate(range(PLAT_Y0, PLAT_Y1 - 24, 60)):
        jig = 9 if i % 2 == 0 else -6
        blit(img, foam, PLAT_X0 - 2, y + 30 + jig, 0.32, anchor="center")
        blit(img, foam, PLAT_X1 + 2, y + 30 - jig, 0.32, anchor="center", flip_h=True)

    # Island platform, 3x3 edge tiles + rounded corners (mirror of the game's
    # _build_tiled_zone call)
    cols = (PLAT_X1 - PLAT_X0) // TS
    rows = (PLAT_Y1 - PLAT_Y0) // TS
    for r in range(rows):
        for c in range(cols):
            gx = 0 if c == 0 else (2 if c == cols - 1 else 1)
            gy = 0 if r == 0 else (2 if r == rows - 1 else 1)
            img.alpha_composite(tile_of(GRASS, gx, gy),
                                (PLAT_X0 + c * TS, PLAT_Y0 + r * TS))

    # Per-half fortress: stone wall row, then castle/towers/houses.
    stone = tile_of(GRASS, 6, 4)  # stone face w/ rim line on top — NEVER flipped
    for team, flip in (("red", False), ("blue", True)):
        bdir = A / "buildings" / team
        wy = WALL_Y_ENEMY if not flip else WALL_Y_PLAYER
        x = WALL_X[0]
        while x < WALL_X[1]:
            img.alpha_composite(stone, (x, round(wy)))
            x += TS
        cy = CASTLE_ANCHOR[1] if not flip else mirror_y(CASTLE_ANCHOR[1])
        blit(img, load(bdir / "Castle.png"), CASTLE_ANCHOR[0], cy,
             CASTLE_SCALE, anchor="center")
        for tx in (140, mirror_x(140)):
            gy2 = TOWER_GY if not flip else mirror_y(TOWER_GY)
            blit(img, load(bdir / "Tower.png"), tx, gy2, TOWER_SCALE)
        hname, hx, hy, hs = HOUSE
        for hx2 in (hx, mirror_x(hx)):
            gy3 = hy if not flip else mirror_y(hy)
            blit(img, load(bdir / hname), hx2, gy3, hs)

    # Decorations — expand mirrors, then paint back-to-front by ground-y
    # (exactly like the game's y-sorted DecorationLayer).
    jobs = []  # (ground_y, callable)

    def all4(cx, gy):
        """4-way symmetric expansion: L/R x-mirror x top/bottom y-mirror."""
        return [(cx, gy), (mirror_x(cx), gy), (cx, mirror_y(gy)),
                (mirror_x(cx), mirror_y(gy))]

    for cx, gy, n in TREES_L:
        for k in range(n):
            t = frame_of(TER / "Resources" / f"Tree{(k % 4) + 1}.png", 0)
            dx = (k - n / 2) * 32 + 16
            dy = (k % 2) * 26
            for px, py in all4(cx + dx, gy + dy):
                jobs.append((py, lambda p=(px, py), s=t: blit(img, s, p[0], p[1], TREE_SCALE)))

    sheep = frame_of(TER / "Resources" / "Sheep_Idle.png", 0)
    for cx, gy in SHEEP_L:
        for i, (px, py) in enumerate(all4(cx, gy)):
            flip_h = px > 360  # face inward
            jobs.append((py, lambda p=(px, py), f=flip_h: blit(img, sheep, p[0], p[1], SHEEP_SCALE, flip_h=f)))

    for cx, gy in GOLD_L:
        for k in range(3):
            g = load(TER / "Resources" / f"Gold Stone {(k % 6) + 1}.png")
            dx, dy = (k - 1) * 30, (k % 2) * 14
            for px, py in all4(cx + dx, gy + dy):
                jobs.append((py, lambda p=(px, py), s=g: blit(img, s, p[0], p[1], GOLD_SCALE)))

    for cx, gy, idx in BUSH_L:
        b = frame_of(TER / "Decorations" / f"Bushe{idx}.png", 0)
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=b: blit(img, s, p[0], p[1], BUSH_SCALE)))

    for cx, gy, idx in WROCK_L:
        wr = frame_of(TER / "Decorations" / f"Water Rocks_{idx:02d}.png", 0)
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=wr: blit(img, s, p[0], p[1], WROCK_SCALE)))

    rx, ry, ridx = ROCK_MID
    r_img = load(TER / "Decorations" / f"Rock{ridx}.png")
    for px, py in [(rx, ry), (mirror_x(rx), mirror_y(ry))]:  # point symmetry
        jobs.append((py, lambda p=(px, py): blit(img, r_img, p[0], p[1], ROCK_SCALE)))

    for _, job in sorted(jobs, key=lambda j: j[0]):
        job()

    # HUD occlusion (honest view)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.rectangle([0, 0, W, 40], fill=(20, 10, 8, 210))
    d.rectangle([0, 985, W, H], fill=(20, 10, 8, 210))
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
    assert (PLAT_Y0 + PLAT_Y1) == 2 * PIVOT, "platform must mirror about the pivot"
    OUT.parent.mkdir(exist_ok=True)
    im = render(show_grid="--grid" in sys.argv)
    im.save(OUT)
    print(f"wrote {OUT} ({im.size[0]}x{im.size[1]})")
