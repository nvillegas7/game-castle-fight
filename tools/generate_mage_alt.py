#!/usr/bin/env python3
"""Variant B: Tiny Swords Monk + REAL wizard hat extracted from Tiny RPG.

T-083 alt: same gameplay role as variant A (full Tiny RPG Wizard) but
preserves Tiny Swords art style for the body. The wizard hat is
extracted from the Tiny RPG Wizard sprite (rows 39-43 of frame 0,
the cone + brim region) and NEAREST-upscaled 3× before being composited
onto each Monk frame at the head position.

Source layers:
  - Body: Tiny Swords Monk (Idle/Run/Heal) — same as Priest
  - Hat:  Tiny RPG Wizard hat (rows 39-43 of Wizard-Idle frame 0)

Output:
  blue_mage_alt/Mage_Idle.png  etc
  red_mage_alt/Mage_Idle.png   etc

The user requested both variants (A and B) so they can compare and
choose which to keep before A2 wires UNIT_MAP.
"""
from PIL import Image, ImageFilter
import numpy as np
import os

# ============================================================
# Constants
# ============================================================
F = 192  # Tiny Swords frame size

MONK_DIR_BLUE = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/"
    "Units/Blue Units/Monk"
)
MONK_DIR_RED = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/"
    "Units/Red Units/Monk"
)
WIZARD_PATH = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Characters(100x100)/Wizard/Wizard/Wizard-Idle.png"
)
WIZARD_FIREBALL = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Magic(Projectile)/Wizard-Attack01_Effect.png"
)

# Tiny RPG Wizard hat region in source coords (measured 2026-04-11)
HAT_SRC_ROW0 = 39
HAT_SRC_ROW1 = 44   # inclusive: rows 39-44 = the pointed tip + the wide brim
HAT_SRC_COL0 = 43
HAT_SRC_COL1 = 59   # inclusive

HAT_UPSCALE = 3     # 17×6 source → 51×18 hat (fits Monk head ~30 wide)

# Per-team body tint to differentiate Mage from Priest
BLUE_BODY_TINT = (140, 100, 180)   # violet
RED_BODY_TINT = (180, 80, 140)     # magenta
TINT_STRENGTH = 0.18


# ============================================================
# Hat extraction (one-time per script run)
# ============================================================
def extract_wizard_hat():
    """Extract the wizard hat from the Tiny RPG Wizard idle frame 0.

    Returns the hat as a tightly-bbox'd, NEAREST-upscaled RGBA image.
    """
    src = Image.open(WIZARD_PATH).convert("RGBA")
    f0 = src.crop((0, 0, 100, 100))
    hat_box = f0.crop((HAT_SRC_COL0, HAT_SRC_ROW0,
                       HAT_SRC_COL1 + 1, HAT_SRC_ROW1 + 1))
    # Trim transparent edges (in case of noise)
    arr = np.array(hat_box)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if rows.any() and cols.any():
        r0, r1 = np.where(rows)[0][[0, -1]]
        c0, c1 = np.where(cols)[0][[0, -1]]
        hat_box = hat_box.crop((c0, r0, c1 + 1, r1 + 1))
    upscaled = hat_box.resize(
        (hat_box.width * HAT_UPSCALE, hat_box.height * HAT_UPSCALE),
        Image.NEAREST,
    )
    return upscaled


def recolor_hat(hat, target_hue):
    """HSV recolor the hat to a new hue (for red team)."""
    from colorsys import rgb_to_hsv, hsv_to_rgb
    arr = np.array(hat, dtype=np.uint8)
    alpha = arr[:, :, 3]
    h, w = alpha.shape
    out = arr.copy()
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            r, g, b = (arr[y, x, 0] / 255.0, arr[y, x, 1] / 255.0,
                       arr[y, x, 2] / 255.0)
            _, s, v = rgb_to_hsv(r, g, b)
            nr, ng, nb = hsv_to_rgb(target_hue, s, v)
            out[y, x, 0] = int(nr * 255)
            out[y, x, 1] = int(ng * 255)
            out[y, x, 2] = int(nb * 255)
    return Image.fromarray(out)


# ============================================================
# Per-frame head detection (same as v1)
# ============================================================
def detect_head_position(frame):
    arr = np.array(frame)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    if not rows.any():
        return None
    head_top = int(np.where(rows)[0][0])
    head_band = a[head_top:head_top + 15, :]
    head_cols = np.any(head_band > 32, axis=0)
    if not head_cols.any():
        return None
    c0, c1 = np.where(head_cols)[0][[0, -1]]
    return (int(c0 + c1) // 2, head_top)


# ============================================================
# Body tint
# ============================================================
def tint_body_hsv(img, target_rgb, strength):
    from colorsys import rgb_to_hsv, hsv_to_rgb
    arr = np.array(img, dtype=np.uint8)
    alpha = arr[:, :, 3]
    if alpha.sum() == 0:
        return img
    h, w = alpha.shape
    th, ts, _ = rgb_to_hsv(
        target_rgb[0] / 255.0, target_rgb[1] / 255.0, target_rgb[2] / 255.0
    )
    out = arr.copy()
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            r, g, b = (arr[y, x, 0] / 255.0, arr[y, x, 1] / 255.0,
                       arr[y, x, 2] / 255.0)
            _, src_s, src_v = rgb_to_hsv(r, g, b)
            new_s = src_s * (1 - strength) + ts * strength
            nr, ng, nb = hsv_to_rgb(th, new_s, src_v)
            out[y, x, 0] = int(nr * 255)
            out[y, x, 1] = int(ng * 255)
            out[y, x, 2] = int(nb * 255)
    return Image.fromarray(out)


# ============================================================
# Frame composition: tint Monk → place hat at head
# ============================================================
def compose_alt_frame(monk_frame, hat_img, body_tint, hat_tilt=0,
                       alpha_mul=1.0):
    """Tint Monk body, place pre-cropped wizard hat above head."""
    tinted = tint_body_hsv(monk_frame, body_tint, TINT_STRENGTH)
    head = detect_head_position(tinted)
    canvas = tinted
    if head is not None:
        head_cx, head_top = head
        hat = hat_img
        if hat_tilt != 0:
            hat = hat.rotate(hat_tilt, resample=Image.NEAREST, expand=True)
        hat_w, hat_h = hat.size
        # Anchor: hat brim sits 2px above the Monk's head top
        paste_x = head_cx - hat_w // 2
        paste_y = head_top - hat_h + 5
        layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
        layer.paste(hat, (paste_x, paste_y))
        canvas = Image.alpha_composite(canvas, layer)

    if alpha_mul < 1.0:
        arr = np.array(canvas, dtype=np.float32)
        arr[:, :, 3] *= alpha_mul
        canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return canvas


# ============================================================
# Frame loading + animations
# ============================================================
def load_strip(path):
    img = Image.open(path).convert("RGBA")
    h = img.height
    n = img.width // h
    return [img.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]


def assemble_strip(frames):
    strip = Image.new('RGBA', (F * len(frames), F), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (F * i, 0))
    return strip


def make_idle(monk_dir, hat, tint):
    src = load_strip(os.path.join(monk_dir, "Idle.png"))
    return [compose_alt_frame(f, hat, tint) for f in src]


def make_walk(monk_dir, hat, tint):
    src = load_strip(os.path.join(monk_dir, "Run.png"))
    return [compose_alt_frame(f, hat, tint) for f in src]


def make_attack(monk_dir, hat, tint):
    src = load_strip(os.path.join(monk_dir, "Heal.png"))
    return [compose_alt_frame(f, hat, tint) for f in src]


def make_death(monk_dir, hat, tint):
    src = load_strip(os.path.join(monk_dir, "Idle.png"))
    base = src[0]
    frames = []
    for i in range(6):
        tilt = -i * 8
        alpha = 1.0 - (i / 6.0) * 0.6
        frames.append(compose_alt_frame(base, hat, tint, hat_tilt=tilt,
                                         alpha_mul=alpha))
    return frames


# ============================================================
# Fireball (same as v1, copied here so script is self-contained)
# ============================================================
def generate_fireball(out_dir, recolor_hue=None):
    src = Image.open(WIZARD_FIREBALL).convert("RGBA")
    n = src.width // src.height
    frame_idx = min(5, n - 1)
    h = src.height
    f = src.crop((frame_idx * h, 0, (frame_idx + 1) * h, h))
    arr = np.array(f)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if rows.any() and cols.any():
        r0, r1 = np.where(rows)[0][[0, -1]]
        c0, c1 = np.where(cols)[0][[0, -1]]
        f = f.crop((c0, r0, c1 + 1, r1 + 1))
    f = f.resize((f.width * 2, f.height * 2), Image.NEAREST)
    if recolor_hue is not None:
        from colorsys import rgb_to_hsv, hsv_to_rgb
        arr = np.array(f, dtype=np.uint8)
        alpha = arr[:, :, 3]
        for y in range(arr.shape[0]):
            for x in range(arr.shape[1]):
                if alpha[y, x] == 0:
                    continue
                r, g, b = (arr[y, x, 0] / 255.0, arr[y, x, 1] / 255.0,
                           arr[y, x, 2] / 255.0)
                _, s, v = rgb_to_hsv(r, g, b)
                nr, ng, nb = hsv_to_rgb(recolor_hue, s, v)
                arr[y, x, 0] = int(nr * 255)
                arr[y, x, 1] = int(ng * 255)
                arr[y, x, 2] = int(nb * 255)
        f = Image.fromarray(arr)
    side = 96
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    ox = (side - f.width) // 2
    oy = (side - f.height) // 2
    canvas.paste(f, (ox, oy))
    canvas.save(os.path.join(out_dir, "Fireball.png"))
    print(f"  Fireball.png ({side}×{side})")


# ============================================================
# Team generation
# ============================================================
def generate_team(team_name, monk_dir, out_dir, body_tint,
                   hat_recolor_hue=None, fireball_hue=None):
    os.makedirs(out_dir, exist_ok=True)
    print(f"Generating {team_name} mage_alt (Monk + extracted RPG hat)...")

    hat = extract_wizard_hat()
    if hat_recolor_hue is not None:
        hat = recolor_hat(hat, hat_recolor_hue)

    anims = {
        'Mage_Idle': make_idle(monk_dir, hat, body_tint),
        'Mage_Walk': make_walk(monk_dir, hat, body_tint),
        'Mage_Attack': make_attack(monk_dir, hat, body_tint),
        'Mage_Death': make_death(monk_dir, hat, body_tint),
    }

    for name, frames in anims.items():
        strip = assemble_strip(frames)
        out_path = os.path.join(out_dir, f"{name}.png")
        strip.save(out_path)
        print(f"  {name}.png ({strip.width}×{strip.height}, "
              f"{len(frames)} frames @ {F}×{F})")

    generate_fireball(out_dir, fireball_hue)
    print()


def main():
    base = "castle_clash/assets/sprites/units"
    print("=== Mage Alt Generation (Monk body + extracted Wizard hat) ===\n")

    generate_team("Blue (Kingdom)",
                  MONK_DIR_BLUE,
                  os.path.join(base, "blue_mage_alt"),
                  body_tint=BLUE_BODY_TINT,
                  hat_recolor_hue=None,
                  fireball_hue=None)
    generate_team("Red (Horde)",
                  MONK_DIR_RED,
                  os.path.join(base, "red_mage_alt"),
                  body_tint=RED_BODY_TINT,
                  hat_recolor_hue=0.0,
                  fireball_hue=0.0)

    print("Done! Compare with /tmp/asset_preview/mage_v2_preview.png "
          "(variant A = full Tiny RPG Wizard) to choose.")


if __name__ == "__main__":
    main()
