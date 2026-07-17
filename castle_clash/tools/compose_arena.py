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

3.3b terrain overhaul (density parity vs design/references/v2+v3): the field
was measured 2.3x sparser than the mockups (object-content 12.9% vs 29.4%,
central-field decoration 7% vs 23% — forensics wf_772ab315). The enrichment:
SIDE PLATEAUS (elevation ledges framing the combat zone, the mockups' lane
definition), denser multi-species tree lines, shrubs/stumps/props, a big
central gold cluster, clouds + rocks on the water. Run --stats to measure.

Usage:
  python3 tools/compose_arena.py            # → design/arena_target.png
  python3 tools/compose_arena.py --grid     # + sim geometry overlay
  python3 tools/compose_arena.py --stats [png ...] # density metrics (no render)
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


def frame_of(sheet: Path, idx: int = 0, fw: int = 0) -> Image.Image:
    """Extract frame idx. fw = true frame width — NOT always the sheet height:
    Tree1/Tree2 are 8 frames of 192x256 (non-square); the old square crop bled
    a 26px sliver of the next frame in ("floating fir fragments" bug,
    user-reported 2026-07-10). Default fw=height only when it divides evenly."""
    im = load(sheet)
    fh = im.size[1]
    if fw <= 0:
        fw = fh if im.size[0] % fh == 0 else im.size[0] // 8
    return im.crop((idx * fw, 0, idx * fw + fw, fh))


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
GRASS_WORN = TER / "Tilemap_color4.png"   # desaturated olive — worn-path variant only
WATER_RGB = (71, 171, 169)          # native water texel — NEVER tint
FOAM = TER / "Water Foam.png"

# Island platform: symmetric about PIVOT (72+968 = 2*520 ✓), 9x14 tiles.
PLAT_X0, PLAT_X1 = 72, 648
PLAT_Y0, PLAT_Y1 = 72, 968

CASTLE_SCALE = 0.538                 # content fits the 7x4-cell sim footprint (112px tall)
# Castle visuals snap to their 7x4 grid-block CENTERS (enemy y[55,167]->111,
# player y[863,975]->919), NOT mirror_y — the build grids sit symmetric about
# 515 (legacy 10px zone quirk), while decorations mirror about the 520 pivot.
CASTLE_CENTERS = {"red": (360, 111), "blue": (360, 919)}

# Castle cliff base (integrated mound) — replaces the old waist-height wall row.
# The castle's stone foot merges into a stone cliff FACE on its SOUTH front, grass
# rim curling over the top (row-3 grass-edge tile), stone face below (rows 4/5).
# PERSPECTIVE-LOCKED: face always points SOUTH on both halves; NEVER flipped.
# Reference v3: cliff ≈ 128px tall (2 tiles), castle-body-width. cx=360 both.
CLIFF_W_TILES = 3                    # band width in 64px tiles (~192px; body=168 + turret overhang)
CLIFF_EDGE_Y = {"red": 163, "blue": 967}   # stone top; meets this tool's castle foot (167/975)
CLIFF_FACE_PX = {"red": 64, "blue": 64}     # one-tile stone band (matches ref v3 proportion)
# PORT NOTE: game_arena.gd/arena_terrain.gd uses edge = red 132 / blue 958, NOT
# these. castle_visual.gd renders the in-game castle ~20px HIGHER than CASTLE_CENTERS
# here (measured game red content-foot = design ~147 vs 167), so the cliff must rise to
# stay merged with the castle foot. Same LOOK, different absolute Y — keep both in sync
# by the RELATION "cliff stone body just under the castle's rendered content-foot".
TOWER_SCALE, TOWER_GY = 0.72, 268    # flanking towers at x=140 / 720-140
HOUSE = ("House1.png", 122, 148, 0.62)   # corner house; mirrored 4x

# --- 3.3b SIDE PLATEAUS (the structural centerpiece; v2's flanking ledges) ---
# One elevated shelf per side band, framing the combat zone (y=[350,690]).
# The GRASS REGION self-mirrors about the pivot (328+712=1040 ✓ asserted), so
# the y-flip maps each plateau onto itself; the stone face is ORIENTATION and
# stays on the SOUTH end on both halves (perspective lock, like the castle
# cliffs' re-authored red-132/blue-958 pattern). x=[72,200]: flush with the
# west coast (elevation-over-water left edge, exactly the loading screen's
# island), 6px clear of the gameplay column (206). 2 cols wide → tile cols
# use L-edge(5)/R-edge(7); rows: 0 top-rim, 1 fill, 2 bottom-transition,
# 4 stone face (row 5's foam rim is water-only — not used on grass).
PLATEAU_L = {"x0": 72, "cols": 2, "grass_y0": 328, "grass_rows": 5, "stone_px": 64}

# Worn-grass lane path (user-picked variant B, 2026-07-17): a contiguous 2-col
# color4 patch down the combat zone center, rounded 3x3 edge tiles (this is
# patch-on-patch, the pack's intended use — NOT per-tile hue mixing, which the
# 2026-07-07 lesson bans). Region y-symmetric about pivot (360+680=1040 ✓).
PATH = {"x0": 296, "cols": 2, "y0": 360, "rows": 5}  # x=[296,424] c=360; y=[360,680] ✓

# Decorations — LEFT side of ENEMY half only. (cx, ground_y, extra)
# TREES: (cx, gy, sheet_idx 1-4, scale). 1/2=fir, 3/4=autumn birch.
# Plateau-top cluster (ground on the shelf) + flat corner grove by the house.
# PLATEAU-TOP rule: the plateau REGION self-mirrors, but its GRASS zone maps
# [328,648]→[392,712] (south 64px = stone). Shelf decorations must sit in the
# SELF-MIRRORING grass zone y∈[392,648] so their y-mirrors stay on grass —
# and each authored item doubles onto its own shelf (author 2.5, get 5).
TREES_L = [
    (98, 442, 1, 0.60), (150, 488, 2, 0.52),           # plateau firs (+ their shelf mirrors)
    (146, 432, 1, 0.50),                               # rim-line fir (+ mirror at 608)
    (112, 520, 2, 0.62),                               # pivot fir — mirrors onto itself
    (102, 234, 3, 0.50),                               # flat corner autumn by the house
]
SHEEP_L = [(176, 414), (238, 538)]           # shelf sheep + field grazing pair
# Big central gold (v2's midfield treasure) — POINT-mirrored (cx, gy, kind):
# authored spots + their 180° twins read as one centered cluster.
GOLD_BIG = [(340, 500, "big"), (384, 478, "big"),
            (310, 532, "small"), (368, 540, "small")]
BUSH_L = [(170, 250, 1)]                     # (cx, gy, sprite idx) round bush, corner
SHRUB_L = [(226, 408, 3), (232, 588, 4)]     # twiggy shrubs at the column margin
STUMP_L = [(182, 306, 1)]                    # stump between corner and plateau
WOOD_L = [(188, 334)]                        # wood pile beside the stump (logging camp)
WROCK_L = [(40, 300, 1), (34, 470, 3), (38, 168, 2), (36, 640, 4)]  # in-water rocks
ROCKS_MID = [(340, 508, 1), (288, 438, 2)]   # midfield accents; point-mirrored

TREE_SCALE, SHEEP_SCALE, GOLD_SCALE = 0.52, 0.55, 0.55
GOLD_BIG_SCALE = 0.85
BUSH_SCALE, ROCK_SCALE, WROCK_SCALE = 0.5, 0.4, 0.5
SHRUB_SCALE, STUMP_SCALE, WOOD_SCALE = 0.5, 0.5, 0.55


def mirror_x(x: float) -> float:
    return 720.0 - x


def mirror_y(y: float) -> float:
    return 2.0 * PIVOT - y


def cliff_base(img: Image.Image, cx: float, edge_y: float, face_px: int) -> None:
    """Integrated stone cliff band under a castle (design/references v3 red): a
    continuous castle-width stone rampart FACE whose top (edge_y) meets the castle's
    own stone foot, so the two read as one raised mound. Grass-edge rim tile (col,3)
    caps the top (the grass lip, mostly behind the castle); stone face (col,4) drops
    SOUTH one tile; a lower course (col,5) is added, overlap-hiding the seam, only for
    face_px>64. Middle stone cols 6/7 (subtle variation, NOT the grass-cornered 5/8).
    NEVER flipped — south-lock. Painted before the castle."""
    n = CLIFF_W_TILES
    x0 = round(cx - n * TS / 2)
    edge = round(edge_y)
    col = 6  # full-width (0..63) middle stone tile; tiles seamlessly (col7 has a
             # 3px transparent right edge that leaves grass slivers between tiles)
    for i in range(n):
        x = x0 + i * TS
        img.alpha_composite(tile_of(GRASS, col, 3), (x, edge - TS))   # grass rim lip
        img.alpha_composite(tile_of(GRASS, col, 4), (x, edge))         # stone face
        if face_px > TS:                                              # taller: lower course
            img.alpha_composite(tile_of(GRASS, col, 5), (x, edge + face_px - TS))


def plateau(img: Image.Image, spec: dict) -> None:
    """Side plateau: an elevated grass shelf whose SOUTH end drops via a stone
    face (perspective-locked, never flipped). Tile semantics from the loading
    screen's proven _build_plateau mapping: col 5=L-edge, 6=fill, 7=R-edge;
    row 0=dark top rim, 1=clean fill, 2=bottom transition (curls overlap the
    stone), 4=stone face. Drawn L→R, top→bottom; grass region must self-mirror
    about the pivot (asserted in main)."""
    x0, cols = spec["x0"], spec["cols"]
    gy0, rows = spec["grass_y0"], spec["grass_rows"]
    for r in range(rows):
        row_k = 0 if r == 0 else (2 if r == rows - 1 else 1)
        for c in range(cols):
            col_k = 5 if c == 0 else (7 if c == cols - 1 else 6)
            img.alpha_composite(tile_of(GRASS, col_k, row_k), (x0 + c * TS, gy0 + r * TS))
    y_stone = gy0 + rows * TS
    for c in range(cols):
        col_k = 5 if c == 0 else (7 if c == cols - 1 else 6)
        img.alpha_composite(tile_of(GRASS, col_k, 4), (x0 + c * TS, y_stone))


def worn_path(img: Image.Image, spec: dict) -> None:
    """Worn-grass lane strip — a contiguous color4 patch with the
    3x3 rounded edge tiles (patch-on-patch per the pack's design; a deliberate
    single-hue region, NOT the banned random per-tile hue mixing)."""
    x0, cols = spec["x0"], spec["cols"]
    y0, rows = spec["y0"], spec["rows"]
    for r in range(rows):
        gy = 0 if r == 0 else (2 if r == rows - 1 else 1)
        for c in range(cols):
            gx = 0 if c == 0 else (2 if c == cols - 1 else 1)
            img.alpha_composite(tile_of(GRASS_WORN, gx, gy), (x0 + c * TS, y0 + r * TS))


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

    # 3.3b: worn lane path down the combat zone — over the island, under all else
    worn_path(img, PATH)

    # 3.3b: side plateaus framing the combat zone (x-mirrored pair; each
    # self-mirrors about the pivot in y — see PLATEAU_L note)
    plateau(img, PLATEAU_L)
    plateau(img, {**PLATEAU_L, "x0": round(mirror_x(PLATEAU_L["x0"] + PLATEAU_L["cols"] * TS))})

    # Per-half fortress: integrated cliff base UNDER the castle, then castle/towers.
    # cliff_base paints the mound FIRST (behind), castle sits ON it (drawn after) so
    # the castle's stone foot merges into the cliff top. Face never flips (south-lock).
    for team, flip in (("red", False), ("blue", True)):
        bdir = A / "buildings" / team
        cliff_base(img, CASTLE_CENTERS[team][0], CLIFF_EDGE_Y[team], CLIFF_FACE_PX[team])
        ccx, ccy = CASTLE_CENTERS[team]
        blit(img, load(bdir / "Castle.png"), ccx, ccy, CASTLE_SCALE, anchor="center")
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

    for cx, gy, sheet_idx, sc in TREES_L:
        sheet = TER / "Resources" / f"Tree{sheet_idx}.png"
        t = frame_of(sheet, 0, fw=load(sheet).size[0] // 8)  # 8-frame strips
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=t, k=sc: blit(img, s, p[0], p[1], k)))

    sheep = frame_of(TER / "Resources" / "Sheep_Idle.png", 0)
    for cx, gy in SHEEP_L:
        for i, (px, py) in enumerate(all4(cx, gy)):
            flip_h = px > 360  # face inward
            jobs.append((py, lambda p=(px, py), f=flip_h: blit(img, sheep, p[0], p[1], SHEEP_SCALE, flip_h=f)))

    # Big central gold: authored + point-mirrored twins (one centered cluster)
    gold_big = load(TER / "Resources" / "Gold_Resource.png")
    gold_small = load(TER / "Resources" / "Gold Stone 2.png")
    for cx, gy, kind in GOLD_BIG:
        s_img, sc = (gold_big, GOLD_BIG_SCALE) if kind == "big" else (gold_small, GOLD_SCALE)
        for px, py in [(cx, gy), (mirror_x(cx), mirror_y(gy))]:
            jobs.append((py, lambda p=(px, py), s=s_img, k=sc: blit(img, s, p[0], p[1], k)))

    for cx, gy, idx in BUSH_L + SHRUB_L:
        b = frame_of(TER / "Decorations" / f"Bushe{idx}.png", 0)
        sc = BUSH_SCALE if idx <= 2 else SHRUB_SCALE
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=b, k=sc: blit(img, s, p[0], p[1], k)))

    for cx, gy, idx in STUMP_L:
        s_img = load(TER / "Resources" / f"Stump {idx}.png")
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=s_img: blit(img, s, p[0], p[1], STUMP_SCALE)))

    for cx, gy in WOOD_L:
        w_img = load(TER / "Resources" / "Wood Resource.png")
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=w_img: blit(img, s, p[0], p[1], WOOD_SCALE)))

    for cx, gy, idx in WROCK_L:
        wr = frame_of(TER / "Decorations" / f"Water Rocks_{idx:02d}.png", 0)
        for px, py in all4(cx, gy):
            jobs.append((py, lambda p=(px, py), s=wr: blit(img, s, p[0], p[1], WROCK_SCALE)))

    r_sheets = {i: load(TER / "Decorations" / f"Rock{i}.png") for i in (1, 2, 3, 4)}
    for rx, ry, ridx in ROCKS_MID:
        for px, py in [(rx, ry), (mirror_x(rx), mirror_y(ry))]:  # point symmetry
            jobs.append((py, lambda p=(px, py), s=r_sheets[ridx]: blit(img, s, p[0], p[1], ROCK_SCALE)))

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


# ------------------------------------------------------------------- stats --

def density_stats(png: Path) -> dict:
    """Composition-parity metrics (forensics wf_772ab315 methodology): classify
    island pixels as flat base grass vs 'content' (anything else). Mockup
    targets: object-content ≈29%, central-field decoration ≈23%; the pre-3.3b
    arena measured 12.9% / 7%."""
    import numpy as np
    im = np.array(Image.open(png).convert("RGB"), dtype=np.int16)
    scale = im.shape[1] / 720.0  # handle 504x896 captures (0.7x)
    base = np.array(Image.open(GRASS).convert("RGB").crop((64 + 8, 64 + 8, 128 - 8, 128 - 8)))
    palette = np.unique(base.reshape(-1, 3), axis=0).astype(np.int16)

    def region_content(x0, y0, x1, y1):
        r = im[round(y0 * scale):round(y1 * scale), round(x0 * scale):round(x1 * scale)]
        d = np.abs(r[:, :, None, :] - palette[None, None, :, :]).sum(axis=3).min(axis=2)
        return float((d > 30).mean())

    return {
        "island_content": region_content(72, 72, 648, 968),
        "central_field": region_content(206, 350, 514, 690),
        "side_bands": (region_content(72, 350, 206, 690) + region_content(514, 350, 648, 690)) / 2.0,
    }


if __name__ == "__main__":
    if "--stats" in sys.argv:
        args = [a for a in sys.argv[sys.argv.index("--stats") + 1:] if not a.startswith("--")]
        for p in (args or [str(OUT)]):
            s = density_stats(Path(p))
            print(f"{p}: island_content={s['island_content']:.1%} "
                  f"central_field={s['central_field']:.1%} side_bands={s['side_bands']:.1%}")
        sys.exit(0)

    assert (PLAT_Y0 + PLAT_Y1) == 2 * PIVOT, "platform must mirror about the pivot"
    pl_top = PLATEAU_L["grass_y0"]
    pl_bot = pl_top + PLATEAU_L["grass_rows"] * TS + PLATEAU_L["stone_px"]
    assert pl_top + pl_bot == round(2 * PIVOT), "plateau region must self-mirror about the pivot"
    assert PLATEAU_L["x0"] + PLATEAU_L["cols"] * TS <= 206, "plateau must stay out of the gameplay column"
    assert PATH["y0"] + (PATH["y0"] + PATH["rows"] * TS) == round(2 * PIVOT), "path must self-mirror"

    OUT.parent.mkdir(exist_ok=True)
    im = render(show_grid="--grid" in sys.argv)
    im.save(OUT)
    print(f"wrote {OUT} ({im.size[0]}x{im.size[1]})")
