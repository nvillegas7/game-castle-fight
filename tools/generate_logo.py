#!/usr/bin/env python3
"""Generate Castle Fight logo — heraldic crest on transparent background.

The logo sits on top of scenic menu/loading screens that already have their
own grass + buildings + clouds. Adding another scene inside the logo creates
rectangular "poster" edges and fights the surrounding background. So the logo
is a proper heraldic CREST — shaped emblem on transparency, menu scene shows
through the gaps:

  1. Soft radial gold glow (circular, fades to transparent at edges)
  2. Large heraldic shield backdrop (Icon_06, NEAREST-upscaled)
  3. Crossed swords (blue × red) in front of shield
  4. Blue ribbon banner across the crest
  5. "CASTLE FIGHT" title text — Mork Dungeon font with gold gradient +
     navy outline + drop shadow
  6. Gold coin ornaments (Icon_03) at each ribbon end

Outputs:
  - castle_clash/assets/sprites/ui/logo.png       (1024×640 crest on transparency)
  - castle_clash/assets/sprites/ui/logo_512.png   (512×320 LANCZOS)
  - castle_clash/assets/sprites/ui/logo_128.png   (128×auto LANCZOS, tight-cropped)
  - castle_clash/assets/sprites/ui/logo_32.png    (32×32 favicon — shield+swords)
"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import os

# ============================================================
# Asset paths
# ============================================================
TS = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)"
)
TS_UI = os.path.join(TS, "UI Elements/UI Elements")
SWORDS_PATH = os.path.join(TS_UI, "Swords/Swords.png")
RIBBONS_PATH = os.path.join(TS_UI, "Ribbons/BigRibbons.png")
SHIELD_PATH = os.path.join(TS_UI, "Icons/Icon_06.png")
SWORD_ICON_PATH = os.path.join(TS_UI, "Icons/Icon_05.png")
# Chunky pixel-block font bundled with the project; ships with the build.
FONT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "castle_clash/assets/fonts/NinjaNormal.ttf"
)

# Buildings + units (used as decorative emblem flanks, radial-fade-masked
# so the outer canvas stays transparent and they don't create a rectangle)
CASTLE_BLUE = os.path.join(TS, "Buildings/Blue Buildings/Castle.png")
CASTLE_RED = os.path.join(TS, "Buildings/Red Buildings/Castle.png")
TOWER_BLUE = os.path.join(TS, "Buildings/Blue Buildings/Tower.png")
TOWER_RED = os.path.join(TS, "Buildings/Red Buildings/Tower.png")
WARRIOR_BLUE_ATK = os.path.join(TS, "Units/Blue Units/Warrior/Warrior_Attack1.png")
WARRIOR_RED_ATK = os.path.join(TS, "Units/Red Units/Warrior/Warrior_Attack1.png")
WARRIOR_BLUE_IDLE = os.path.join(TS, "Units/Blue Units/Warrior/Warrior_Idle.png")
WARRIOR_RED_IDLE = os.path.join(TS, "Units/Red Units/Warrior/Warrior_Idle.png")
ARCHER_BLUE = os.path.join(TS, "Units/Blue Units/Archer/Archer_Idle.png")
ARCHER_RED = os.path.join(TS, "Units/Red Units/Archer/Archer_Idle.png")
LANCER_BLUE = os.path.join(TS, "Units/Blue Units/Lancer/Lancer_Right_Defence.png")
LANCER_RED = os.path.join(TS, "Units/Red Units/Lancer/Lancer_Right_Defence.png")

# ============================================================
# Helpers
# ============================================================
def _trim_alpha(img):
    bbox = img.getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def _rotate(img, deg):
    return img.rotate(deg, resample=Image.BICUBIC, expand=True)


def _extract_frame(strip_path, frame_idx, frame_w, frame_h):
    src = Image.open(strip_path).convert("RGBA")
    x0 = frame_idx * frame_w
    return src.crop((x0, 0, x0 + frame_w, frame_h))


def _radial_fade_alpha(img, center, inner_radius, outer_radius):
    """Multiply img's alpha channel by a circular falloff. Pixels within
    inner_radius keep full alpha; pixels beyond outer_radius become
    transparent; linear falloff in between. This is the same circular-mask
    idea as the gold glow, so the outer canvas stays transparent and the
    logo has no rectangular edge."""
    arr = np.array(img).astype(np.float32)
    h, w = arr.shape[:2]
    cx, cy = center
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    span = max(outer_radius - inner_radius, 1.0)
    fade = np.clip(1.0 - (dist - inner_radius) / span, 0.0, 1.0)
    arr[..., 3] = arr[..., 3] * fade
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode='RGBA')


# ============================================================
# Sword extraction (from Swords.png atlas)
# ============================================================
SWORD_ROW_H = 128
SWORD_ROWS = {'blue': 0, 'red': 1}
PMM_COLS = (23, 127)
MID_COLS = (192, 255)
TIP_COLS = (320, 411)


def extract_sword(color):
    src = Image.open(SWORDS_PATH).convert("RGBA")
    row = SWORD_ROWS[color]
    y0 = row * SWORD_ROW_H
    y1 = y0 + SWORD_ROW_H
    pommel = src.crop((PMM_COLS[0], y0, PMM_COLS[1] + 1, y1))
    middle = src.crop((MID_COLS[0], y0, MID_COLS[1] + 1, y1))
    tip = src.crop((TIP_COLS[0], y0, TIP_COLS[1] + 1, y1))
    middle = middle.resize((middle.width * 2, middle.height), Image.NEAREST)
    total_w = pommel.width + middle.width + tip.width
    sword = Image.new('RGBA', (total_w, SWORD_ROW_H), (0, 0, 0, 0))
    sword.paste(pommel, (0, 0))
    sword.paste(middle, (pommel.width, 0))
    sword.paste(tip, (pommel.width + middle.width, 0))
    return _trim_alpha(sword)


# ============================================================
# Ribbon extraction (from BigRibbons.png atlas)
# ============================================================
RIBBON_ROWS = [(20, 122), (148, 250), (276, 378), (404, 506), (532, 634)]
RIBBON_COLOR_INDEX = {'blue': 0, 'red': 1, 'yellow': 2}


def extract_ribbon(color, target_width):
    src = Image.open(RIBBONS_PATH).convert("RGBA")
    row_idx = RIBBON_COLOR_INDEX[color]
    y0, y1 = RIBBON_ROWS[row_idx]
    cell_w = src.width // 3
    left = _trim_alpha(src.crop((0, y0, cell_w, y1 + 1)))
    middle = _trim_alpha(src.crop((cell_w, y0, cell_w * 2, y1 + 1)))
    right = _trim_alpha(src.crop((cell_w * 2, y0, src.width, y1 + 1)))
    middle_target_w = max(1, target_width - left.width - right.width)
    middle = middle.resize((middle_target_w, middle.height), Image.NEAREST)
    total_h = max(left.height, middle.height, right.height)
    canvas = Image.new('RGBA', (target_width, total_h), (0, 0, 0, 0))
    canvas.paste(left, (0, (total_h - left.height) // 2))
    canvas.paste(middle, (left.width, (total_h - middle.height) // 2))
    canvas.paste(right, (left.width + middle.width,
                         (total_h - right.height) // 2))
    return canvas


# ============================================================
# Logo composition — heraldic crest on transparent background
# ============================================================
def _draw_radial_glow(canvas, cx, cy, radius, color, max_alpha=120,
                      inner_ratio=0.35):
    """Draw a soft circular gold glow with alpha falloff. Center is brightest,
    edge fully transparent. Shape is a circle — no rectangular edge."""
    w, h = canvas.size
    # Use numpy for speed — build an alpha falloff mask sized to the glow.
    box = radius * 2
    yy, xx = np.mgrid[0:box, 0:box]
    dx = xx - radius
    dy = yy - radius
    dist = np.sqrt(dx * dx + dy * dy)
    # Alpha: max at center, linear falloff to 0 at radius, plateau inside
    # inner_ratio * radius so the core stays bright.
    inner_r = radius * inner_ratio
    alpha = np.where(
        dist <= inner_r,
        max_alpha,
        np.clip(max_alpha * (1.0 - (dist - inner_r) / (radius - inner_r)),
                0, max_alpha)
    )
    alpha = alpha.astype(np.uint8)
    r, g, b = color
    rgba = np.zeros((box, box, 4), dtype=np.uint8)
    rgba[..., 0] = r
    rgba[..., 1] = g
    rgba[..., 2] = b
    rgba[..., 3] = alpha
    glow = Image.fromarray(rgba, mode='RGBA')
    canvas.alpha_composite(glow, (cx - radius, cy - radius))


def _apply_gold_gradient(text_img, text_mask_rgb=(239, 225, 171)):
    """Replace a flat-color text mask with a top-bright / bottom-warmer gold
    gradient. text_img is an RGBA where fill pixels are text_mask_rgb."""
    arr = np.array(text_img)
    h, w = arr.shape[:2]
    # Find fill pixels (approximate match to cream fill)
    r_match = np.abs(arr[..., 0].astype(int) - text_mask_rgb[0]) < 4
    g_match = np.abs(arr[..., 1].astype(int) - text_mask_rgb[1]) < 4
    b_match = np.abs(arr[..., 2].astype(int) - text_mask_rgb[2]) < 4
    a_match = arr[..., 3] > 128
    mask = r_match & g_match & b_match & a_match
    if not mask.any():
        return text_img
    ys = np.where(mask)[0]
    top = ys.min()
    bot = ys.max()
    span = max(bot - top, 1)
    # Top color: bright cream (almost white highlight)
    # Bottom color: warm cream (NOT dark gold — keeps letters legible at
    # small sizes against the blue ribbon).
    top_c = np.array([255, 245, 205], dtype=np.float32)
    bot_c = np.array([240, 200, 130], dtype=np.float32)
    for y in range(top, bot + 1):
        t = (y - top) / span
        c = top_c * (1 - t) + bot_c * t
        row_mask = mask[y]
        arr[y, row_mask, 0] = int(c[0])
        arr[y, row_mask, 1] = int(c[1])
        arr[y, row_mask, 2] = int(c[2])
    return Image.fromarray(arr, mode='RGBA')


def _tight_crop(img):
    """Crop to tight alpha bbox — used to pack units visually without a
    big padding halo around each sprite."""
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def _build_scene_layer(width, height, cx, cy):
    """Render a TWO-ARMIES-CLASHING battle scene behind the emblem:
    blue castle + tower + a front line of 3 blue units on the left,
    red castle + tower + a front line of 3 red units on the right.
    Then apply a circular radial alpha fade so the rectangle dissolves
    at the edges and nothing fights the menu background. Elements are
    sized large enough to be recognizable at 512px output (the main
    display size in-game)."""
    scene = Image.new('RGBA', (width, height), (0, 0, 0, 0))

    def _scale_h(img, h_target):
        ratio = h_target / img.height
        return img.resize((int(img.width * ratio), h_target), Image.NEAREST)

    # ---- Castles (stay BELOW the ribbon — merlons shouldn't poke into text) ----
    blue_castle = Image.open(CASTLE_BLUE).convert("RGBA")
    red_castle = Image.open(CASTLE_RED).convert("RGBA")
    castle_h = int(height * 0.34)
    blue_castle = _scale_h(blue_castle, castle_h)
    red_castle = _scale_h(red_castle, castle_h)
    red_castle = red_castle.transpose(Image.FLIP_LEFT_RIGHT)

    # Ground baseline — all battle-scene sprites share this y so they read
    # as standing on the same terrain. Pushed down to keep castle tops below
    # the ribbon bottom and leave room for a clear front-line.
    ground_y = cy + int(height * 0.46)

    scene.alpha_composite(
        blue_castle,
        (int(width * 0.02), ground_y - blue_castle.height)
    )
    scene.alpha_composite(
        red_castle,
        (int(width * 0.98) - red_castle.width,
         ground_y - red_castle.height)
    )

    # ---- Towers (in front of castles, adds silhouette variety) ----
    blue_tower = Image.open(TOWER_BLUE).convert("RGBA")
    red_tower = Image.open(TOWER_RED).convert("RGBA")
    tower_h = int(height * 0.28)
    blue_tower = _scale_h(blue_tower, tower_h)
    red_tower = _scale_h(red_tower, tower_h)
    scene.alpha_composite(
        blue_tower,
        (int(width * 0.18) - blue_tower.width // 2, ground_y - blue_tower.height)
    )
    scene.alpha_composite(
        red_tower,
        (int(width * 0.82) - red_tower.width // 2, ground_y - red_tower.height)
    )

    # ---- Front-line units (3 per team, charging inward like a clash) ----
    # Warriors attacking (their Attack1 frame 2 = mid-swing, sword raised),
    # archer drawing bow (Idle frame 0), lancer holding spear forward.
    # All flipped horizontally for red so weapons point toward center.
    # Sized large enough that the warrior silhouette is unmistakable even
    # at the 512px display scale.
    unit_h = int(height * 0.30)

    blue_warrior_A = _tight_crop(
        _extract_frame(WARRIOR_BLUE_ATK, 2, 192, 192))
    red_warrior_A = _tight_crop(
        _extract_frame(WARRIOR_RED_ATK, 2, 192, 192)).transpose(
            Image.FLIP_LEFT_RIGHT)
    blue_warrior_B = _tight_crop(
        _extract_frame(WARRIOR_BLUE_IDLE, 0, 192, 192))
    red_warrior_B = _tight_crop(
        _extract_frame(WARRIOR_RED_IDLE, 0, 192, 192)).transpose(
            Image.FLIP_LEFT_RIGHT)
    blue_archer = _tight_crop(
        _extract_frame(ARCHER_BLUE, 0, 192, 192))
    red_archer = _tight_crop(
        _extract_frame(ARCHER_RED, 0, 192, 192)).transpose(
            Image.FLIP_LEFT_RIGHT)
    # Lancer strip is 320×320 per frame
    blue_lancer = _tight_crop(
        _extract_frame(LANCER_BLUE, 2, 320, 320))
    red_lancer = _tight_crop(
        _extract_frame(LANCER_RED, 2, 320, 320)).transpose(
            Image.FLIP_LEFT_RIGHT)

    blue_warrior_A = _scale_h(blue_warrior_A, unit_h)
    red_warrior_A = _scale_h(red_warrior_A, unit_h)
    blue_warrior_B = _scale_h(blue_warrior_B, unit_h)
    red_warrior_B = _scale_h(red_warrior_B, unit_h)
    blue_archer = _scale_h(blue_archer, unit_h)
    red_archer = _scale_h(red_archer, unit_h)
    # Lancer's tight-crop bbox includes the vertical spear (~40% of bbox
    # height). At unit_h * 1.0 its BODY would be smaller than the warrior's
    # but its OVERALL silhouette taller — reads as "bigger" and covers the
    # castle behind. Scale to 0.82 so the body visually matches the warrior
    # and the spear stops short of the castle silhouette.
    lancer_h = int(unit_h * 0.82)
    blue_lancer = _scale_h(blue_lancer, lancer_h)
    red_lancer = _scale_h(red_lancer, lancer_h)

    # Blue line (left → center): archer back, lancer mid, warrior front
    # Red line (right → center): mirror
    def _paste(img, xc_pct, y_base):
        scene.alpha_composite(
            img,
            (int(width * xc_pct) - img.width // 2, y_base - img.height)
        )

    # Formation: front-line warriors clash at center; lancers behind with
    # spears pointing over; archers in the back drawing bows. Archers
    # bumped up a touch so their bows peek above the warrior line.
    _paste(blue_archer, 0.20, ground_y - 8)
    _paste(blue_lancer, 0.32, ground_y + 6)
    _paste(blue_warrior_A, 0.44, ground_y + 14)

    _paste(red_archer, 0.80, ground_y - 8)
    _paste(red_lancer, 0.68, ground_y + 6)
    _paste(red_warrior_A, 0.56, ground_y + 14)

    # ---- Radial alpha fade — dissolves the rectangular scene boundary ----
    # Wider radii than v5 (the scene is now taller/wider so the fade has
    # to reach further) but still fully transparent at canvas corners.
    fade_cx = cx
    fade_cy = cy + int(height * 0.15)
    inner_r = int(height * 0.48)
    outer_r = int(height * 0.72)
    scene = _radial_fade_alpha(scene, (fade_cx, fade_cy), inner_r, outer_r)

    return scene


def make_logo(width=1024, height=640):
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    cx = width // 2
    cy = height // 2

    # ---- 1. Soft radial gold glow (circular, fades to transparent) ----
    _draw_radial_glow(canvas, cx, cy, radius=int(height * 0.55),
                      color=(255, 205, 95), max_alpha=175, inner_ratio=0.30)

    # ---- 2. Scene flanks (castles + units, radial-fade-masked) ----
    scene = _build_scene_layer(width, height, cx, cy)
    canvas.alpha_composite(scene)

    # ---- 3. Crossed swords (in front of scene + glow) ----
    blue_sword = extract_sword('blue')
    red_sword = extract_sword('red')

    target_sword_w = int(width * 0.55)
    s_ratio = target_sword_w / blue_sword.width
    new_h = int(blue_sword.height * s_ratio)
    blue_sword = blue_sword.resize((target_sword_w, new_h), Image.NEAREST)
    red_sword = red_sword.resize((target_sword_w, new_h), Image.NEAREST)

    blue_rot = _rotate(blue_sword, -25)
    red_rot = _rotate(red_sword, 25 + 180)

    swords_cy = cy - int(height * 0.05)
    canvas.alpha_composite(
        blue_rot,
        (cx - blue_rot.width // 2, swords_cy - blue_rot.height // 2)
    )
    canvas.alpha_composite(
        red_rot,
        (cx - red_rot.width // 2, swords_cy - red_rot.height // 2)
    )

    # ---- 4. Ribbon banner (in front of swords, across text zone) ----
    # Target final (width, height) directly — do NOT preserve aspect from
    # extract_ribbon's output, or the height scale would multiply the
    # width past the canvas.
    ribbon_final_w = int(width * 0.80)
    ribbon_h = int(height * 0.28)
    ribbon = extract_ribbon('blue', target_width=ribbon_final_w)
    ribbon = ribbon.resize((ribbon_final_w, ribbon_h), Image.NEAREST)
    rib_x = cx - ribbon.width // 2
    rib_y = cy - ribbon.height // 2 + 10
    canvas.alpha_composite(ribbon, (rib_x, rib_y))

    # ---- 5. Title text — Ninja pixel-block font, triple-spaced because
    # NinjaNormal's single-space glyph is zero-width.
    font_size = int(ribbon_h * 0.56)
    try:
        font = ImageFont.truetype(FONT_PATH, font_size)
    except Exception:
        font = ImageFont.load_default()

    text = "CASTLE   FIGHT"
    bbox = font.getbbox(text) if hasattr(font, 'getbbox') else (
        0, 0, font_size * len(text), font_size
    )
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    text_x = cx - text_w // 2 - bbox[0]
    text_y = rib_y + ribbon.height // 2 - text_h // 2 - bbox[1]

    text_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(text_layer)

    outline_color = (22, 28, 46, 255)
    fill_color = (239, 225, 171, 255)
    shadow_color = (0, 0, 0, 220)

    # Drop shadow.
    td.text((text_x + 6, text_y + 8), text, font=font, fill=shadow_color)

    # 6px circular outline.
    outline_r = 6
    for dx in range(-outline_r, outline_r + 1):
        for dy in range(-outline_r, outline_r + 1):
            if dx == 0 and dy == 0:
                continue
            if dx * dx + dy * dy > (outline_r + 0.5) ** 2:
                continue
            td.text((text_x + dx, text_y + dy), text, font=font,
                    fill=outline_color)

    td.text((text_x, text_y), text, font=font, fill=fill_color)

    # Gold gradient — top bright cream, bottom slightly warmer.
    text_layer = _apply_gold_gradient(text_layer, text_mask_rgb=fill_color[:3])

    canvas = Image.alpha_composite(canvas, text_layer)

    return canvas


def crop_to_emblem(img, pad_ratio=0.04):
    """Crop to emblem alpha bbox with small symmetric padding. Used for small
    size variants so the ribbon + text fill the frame rather than being
    swallowed by transparent padding."""
    bbox = img.getbbox()
    if bbox is None:
        return img
    x0, y0, x1, y1 = bbox
    w = x1 - x0
    h = y1 - y0
    px = int(w * pad_ratio)
    py = int(h * pad_ratio)
    x0 = max(0, x0 - px)
    y0 = max(0, y0 - py)
    x1 = min(img.width, x1 + px)
    y1 = min(img.height, y1 + py)
    return img.crop((x0, y0, x1, y1))


def crop_to_ribbon_zone(img):
    """Crop tightly to the ribbon + swords + glow region only, excluding the
    scene flanks. Gives the small 128px variant more text-focused pixels —
    the castles/units at full scale are unreadable at that size anyway."""
    w, h = img.size
    # Keep the middle vertical band where the ribbon sits; trim ~25% top
    # and ~40% bottom so the (now larger) battle scene is excluded.
    y0 = int(h * 0.20)
    y1 = int(h * 0.58)
    # Horizontally, trim to the emblem bbox so we don't carry dead padding.
    mid = img.crop((0, y0, w, y1))
    bbox = mid.getbbox()
    if bbox is None:
        return mid
    x0, _, x1, _ = bbox
    pad = int((x1 - x0) * 0.04)
    x0 = max(0, x0 - pad)
    x1 = min(w, x1 + pad)
    return mid.crop((x0, 0, x1, y1 - y0))


# ============================================================
# Favicon — shield + crossed swords icon (no text at 32px)
# ============================================================
def make_favicon(size=32):
    shield = _trim_alpha(Image.open(SHIELD_PATH).convert("RGBA"))
    sword_icon = _trim_alpha(Image.open(SWORD_ICON_PATH).convert("RGBA"))

    shield_sz = int(size * 0.85)
    shield = shield.resize((shield_sz, shield_sz), Image.LANCZOS)

    sword_sz = int(size * 0.65)
    sword_icon = sword_icon.resize((sword_sz, sword_sz), Image.LANCZOS)

    sword_left = _rotate(sword_icon, 30)
    sword_right = _rotate(sword_icon.transpose(Image.FLIP_LEFT_RIGHT), -30)

    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ccx = size // 2
    ccy = size // 2

    canvas.alpha_composite(
        sword_left,
        (ccx - sword_left.width // 2 - 1, ccy - sword_left.height // 2 - 2)
    )
    canvas.alpha_composite(
        sword_right,
        (ccx - sword_right.width // 2 + 1, ccy - sword_right.height // 2 - 2)
    )
    canvas.alpha_composite(
        shield,
        (ccx - shield.width // 2, ccy - shield.height // 2 + 1)
    )

    return canvas


def main():
    out_dir = "castle_clash/assets/sprites/ui"
    os.makedirs(out_dir, exist_ok=True)

    print("=== Castle Fight Logo Generation (Emblem Only) ===\n")

    full = make_logo(1024, 640)
    full.save(os.path.join(out_dir, "logo.png"))
    print(f"  logo.png: {full.size}")

    full.resize((512, 320), Image.LANCZOS).save(
        os.path.join(out_dir, "logo_512.png"))
    print(f"  logo_512.png: 512×320 (LANCZOS)")

    # Small sizes: crop to the ribbon + swords region only so the text
    # survives the downscale. The scene flanks would be unreadable mush
    # at 128px so we exclude them.
    cropped = crop_to_ribbon_zone(full)
    cropped.resize((128, int(128 * cropped.height / cropped.width)),
                   Image.LANCZOS).save(os.path.join(out_dir, "logo_128.png"))
    print(f"  logo_128.png: 128×auto (LANCZOS, ribbon-zone crop)")

    favicon = make_favicon(32)
    favicon.save(os.path.join(out_dir, "logo_32.png"))
    print(f"  logo_32.png: 32×32 (shield+swords favicon)")

    print("\nDone!")


if __name__ == "__main__":
    main()
