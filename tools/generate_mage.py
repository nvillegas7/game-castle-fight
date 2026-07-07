#!/usr/bin/env python3
"""Generate Mage sprites from the real Tiny RPG Wizard character.

T-083 (P1-CRITICAL): Replaces the Champion unit with a Mage. Per user
feedback "Check the downloaded game assets for a mage/wizard hat" + "We
can reuse the tiny rpg but can we make the color match tiny swords?", we
use the artist-authored Tiny RPG Wizard from Tiny RPG Character Asset
Pack and PALETTE-SWAP its robe colors to match Tiny Swords (replacing
the saturated SNES blues with the gentler Tiny Swords blue family).

Source: Tiny RPG Character Asset Pack v1.03 / Characters(100x100)/Wizard/
  - Wizard-Idle.png    (600×100, 6 frames)
  - Wizard-Walk.png    (800×100, 8 frames)
  - Wizard-Attack01.png (600×100, 6 frames)
  - Wizard-DEATH.png   (400×100, 4 frames)
  - Wizard-Attack01_Effect.png (1000×100, 10 frames — fireball animation)

Native content height ≈ 19px in a 100×100 frame. We NEAREST-upscale 4×
so the content becomes ~76px tall, matching Tiny Swords Monk/Priest body
height and rendering at the same in-game scale (~30px target_content).

Color matching (Tiny Swords palette):
  - Wizard outline (31,26,26)            → TS outline (22,28,46)
  - Wizard robe dark (71,60,154)         → TS blue dark   (40,50,80)
  - Wizard robe mid  (65,78,161)         → TS blue mid    (72,88,132)
  - Wizard robe light (85,98,183)        → TS blue light  (95,130,175)
  - Wizard robe lighter (94,121,190)     → TS blue lighter (130,170,210)
  - Wizard skin (242,218,210) etc        → leave alone (skin tones close)
  - Wizard wood/gold/beard               → leave alone (universal)

Red team uses the same approach with the Tiny Swords RED family
(146,65,89 / 231,97,97 / etc).
"""
from PIL import Image
import numpy as np
import os

# ============================================================
# Constants
# ============================================================
WIZARD_DIR = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Characters(100x100)/Wizard/Wizard"
)
WIZARD_FIREBALL = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Magic(Projectile)/Wizard-Attack01_Effect.png"
)

UPSCALE = 4   # 100×100 source → 400×400 output
F_SRC = 100
F_OUT = F_SRC * UPSCALE  # 400


# ============================================================
# Tiny Swords palette swap maps
# ============================================================
# Each tuple: (wizard_source_rgb, tiny_swords_target_rgb)
# Order matters less because we match by exact-or-nearest.
PALETTE_BLUE = [
    # Outline → Tiny Swords dark navy outline
    ((31, 26, 26),    (22, 28, 46)),
    # Wizard's 4 robe shades → Tiny Swords blue family
    ((71, 60, 154),   (40, 50, 80)),     # darkest robe → TS blue dark
    ((65, 78, 161),   (72, 88, 132)),    # mid robe → TS blue mid (main armor)
    ((85, 98, 183),   (95, 130, 175)),   # light robe → TS blue light
    ((94, 121, 190),  (130, 170, 210)),  # lightest robe → cyan-ish highlight
    ((73, 103, 141),  (70, 100, 145)),   # rim/shadow → keep similar
]

PALETTE_RED = [
    ((31, 26, 26),    (22, 28, 46)),     # same outline (universal)
    ((71, 60, 154),   (90, 30, 50)),     # darkest → TS red dark
    ((65, 78, 161),   (146, 65, 89)),    # mid → TS red main
    ((85, 98, 183),   (200, 90, 100)),   # light → TS red light
    ((94, 121, 190),  (231, 97, 97)),    # lightest → TS red accent
    ((73, 103, 141),  (130, 60, 70)),    # rim/shadow
]


def _build_lut(palette_pairs):
    """Build a dict mapping source RGB tuple → target RGB tuple."""
    return {src: tgt for src, tgt in palette_pairs}


def palette_swap(img, palette_pairs):
    """Replace each pixel matching a source color with its target.

    Pixels not in the LUT are left unchanged. This preserves the wizard's
    skin tone, gray beard, gold orb, and wooden staff while only swapping
    the saturated blue robe pixels for the gentler Tiny Swords blues.
    """
    lut = _build_lut(palette_pairs)
    arr = np.array(img, dtype=np.uint8)
    alpha = arr[:, :, 3]
    h, w = alpha.shape
    out = arr.copy()
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            rgb = (int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2]))
            if rgb in lut:
                tgt = lut[rgb]
                out[y, x, 0] = tgt[0]
                out[y, x, 1] = tgt[1]
                out[y, x, 2] = tgt[2]
    return Image.fromarray(out)


# ============================================================
# HSV recolor for red team
# ============================================================
def hsv_recolor(img, target_hue, sat_boost=0.0):
    """Replace each pixel's hue with target_hue, preserve value+sat.

    target_hue is in [0, 1]. Use 0.0 for red, ~0.08 for warm orange.
    sat_boost adds to saturation (clamped to 1.0).
    """
    from colorsys import rgb_to_hsv, hsv_to_rgb
    arr = np.array(img, dtype=np.uint8)
    alpha = arr[:, :, 3]
    if alpha.sum() == 0:
        return img
    h, w = alpha.shape
    out = arr.copy()
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            r, g, b = (arr[y, x, 0] / 255.0, arr[y, x, 1] / 255.0,
                       arr[y, x, 2] / 255.0)
            _, s, v = rgb_to_hsv(r, g, b)
            new_s = min(1.0, s + sat_boost)
            nr, ng, nb = hsv_to_rgb(target_hue, new_s, v)
            out[y, x, 0] = int(nr * 255)
            out[y, x, 1] = int(ng * 255)
            out[y, x, 2] = int(nb * 255)
    return Image.fromarray(out)


# ============================================================
# Frame loading + upscale
# ============================================================
def load_wizard_strip(filename):
    """Load a Tiny RPG Wizard sprite strip and split into 100×100 frames."""
    path = os.path.join(WIZARD_DIR, filename)
    img = Image.open(path).convert("RGBA")
    n = img.width // F_SRC
    return [img.crop((i * F_SRC, 0, (i + 1) * F_SRC, F_SRC)) for i in range(n)]


def upscale_frame(frame):
    """NEAREST-upscale a 100×100 wizard frame to 400×400."""
    return frame.resize((F_OUT, F_OUT), Image.NEAREST)


def assemble_strip(frames):
    """Concatenate frames horizontally into a single PNG strip."""
    strip = Image.new('RGBA', (F_OUT * len(frames), F_OUT), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (F_OUT * i, 0))
    return strip


# ============================================================
# Animation makers
# ============================================================
def make_anim(filename, palette=None):
    """Load a wizard animation, palette-swap to Tiny Swords colors, upscale.

    Order matters: palette-swap BEFORE upscaling so the LUT match works on
    the original 1-pixel color regions (NEAREST upscale just duplicates
    pixels, so swapping after would still work, but doing it first keeps
    the inner loops smaller).
    """
    src = load_wizard_strip(filename)
    if palette is not None:
        src = [palette_swap(f, palette) for f in src]
    return [upscale_frame(f) for f in src]


# ============================================================
# Fireball projectile
# ============================================================
def generate_fireball(out_dir, recolor_hue=None):
    """Render the fireball from Wizard-Attack01_Effect peak frame."""
    src = Image.open(WIZARD_FIREBALL).convert("RGBA")
    n = src.width // src.height
    frame_idx = min(5, n - 1)  # peak fireball
    h = src.height
    f = src.crop((frame_idx * h, 0, (frame_idx + 1) * h, h))

    # Trim to content
    arr = np.array(f)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if rows.any() and cols.any():
        r0, r1 = np.where(rows)[0][[0, -1]]
        c0, c1 = np.where(cols)[0][[0, -1]]
        f = f.crop((c0, r0, c1 + 1, r1 + 1))

    # NEAREST upscale 2× for visibility (was 1.5× in v1, bumped up)
    f = f.resize((f.width * 2, f.height * 2), Image.NEAREST)

    # Optional team recolor
    if recolor_hue is not None:
        f = hsv_recolor(f, recolor_hue)

    # Center on a 96×96 canvas (matches arrow projectile size scale)
    side = 96
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    ox = (side - f.width) // 2
    oy = (side - f.height) // 2
    canvas.paste(f, (ox, oy))
    out_path = os.path.join(out_dir, "Fireball.png")
    canvas.save(out_path)
    print(f"  Fireball.png ({side}×{side})")


# ============================================================
# Team generation
# ============================================================
def generate_team(team_name, out_dir, palette, fireball_hue=None):
    """Generate all 4 mage animations + fireball for a team.

    palette: PALETTE_BLUE or PALETTE_RED for the LUT swap.
    fireball_hue: optional HSV hue for the fireball projectile recolor
        (the fireball is a magical effect, not the wizard's robe, so it
        uses an HSV shift to red instead of the LUT swap).
    """
    os.makedirs(out_dir, exist_ok=True)
    print(f"Generating {team_name} mage from Tiny RPG Wizard...")

    anims = {
        'Mage_Idle': make_anim('Wizard-Idle.png', palette),
        'Mage_Walk': make_anim('Wizard-Walk.png', palette),
        'Mage_Attack': make_anim('Wizard-Attack01.png', palette),
        'Mage_Death': make_anim('Wizard-DEATH.png', palette),
    }

    for name, frames in anims.items():
        strip = assemble_strip(frames)
        out_path = os.path.join(out_dir, f"{name}.png")
        strip.save(out_path)
        print(f"  {name}.png ({strip.width}×{strip.height}, "
              f"{len(frames)} frames @ {F_OUT}×{F_OUT})")

    generate_fireball(out_dir, fireball_hue)
    print()


def main():
    base = "castle_clash/assets/sprites/units"
    print("=== Mage Sprite Generation "
          "(Tiny RPG Wizard, palette-swapped to Tiny Swords) ===\n")

    # Blue team: palette-swap wizard's SNES blues to Tiny Swords blues
    generate_team("Blue (Kingdom)",
                  os.path.join(base, "blue_mage"),
                  palette=PALETTE_BLUE,
                  fireball_hue=None)  # fireball stays blue/cyan native

    # Red team: palette-swap wizard's blues to Tiny Swords reds
    generate_team("Red (Horde)",
                  os.path.join(base, "red_mage"),
                  palette=PALETTE_RED,
                  fireball_hue=0.0)  # fireball recolored red

    print("Done!")


if __name__ == "__main__":
    main()
