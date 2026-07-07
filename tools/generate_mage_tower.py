#!/usr/bin/env python3
"""Merge Tiny Swords Tower + Tiny RPG Wizard hat → MageTower building.

Per user "Feel free to use tiny swords existing building but find an
available sprite/png to merge", this tool combines:

  Base:    Tiny Swords Buildings/Blue Buildings/Tower.png   (128×256)
  Overlay: Tiny RPG Wizard hat (rows 39-44 cols 43-59 of Wizard-Idle f0)

The hat is palette-swapped to the Tiny Swords blue family (same LUT as
the mage unit recolor) so it matches the tower's blue stones, then
NEAREST-upscaled ~6× and pasted onto the tower's roof so the wooden
dome is replaced by a tall pointed wizard hat. Visually unmistakable
as a "mage tower" while keeping the Tiny Swords art style.

Output:
  castle_clash/assets/sprites/buildings/blue/MageTower.png  (128×256 + headroom)
  castle_clash/assets/sprites/buildings/red/MageTower.png   (red tower base)

Note: the output sprite extends ABOVE the tower's original 256px height
so the hat tip pokes above the original frame. Output canvas grows to
128×320 to fit the hat without clipping.
"""
from PIL import Image
import numpy as np
import os

# ============================================================
# Constants
# ============================================================
TOWER_BLUE = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/"
    "Buildings/Blue Buildings/Tower.png"
)
TOWER_RED = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/"
    "Buildings/Red Buildings/Tower.png"
)
WIZARD_PATH = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Characters(100x100)/Wizard/Wizard/Wizard-Idle.png"
)

HAT_ROW0, HAT_ROW1 = 39, 44
HAT_COL0, HAT_COL1 = 43, 59
HAT_UPSCALE = 6  # 17×6 source → 102×36 hat to crown the 128-wide tower

# Tiny Swords blue palette LUT (matches generate_mage.py PALETTE_BLUE)
PALETTE_BLUE = [
    ((31, 26, 26),    (22, 28, 46)),
    ((71, 60, 154),   (40, 50, 80)),
    ((65, 78, 161),   (72, 88, 132)),
    ((85, 98, 183),   (95, 130, 175)),
    ((94, 121, 190),  (130, 170, 210)),
    ((73, 103, 141),  (70, 100, 145)),
]
PALETTE_RED = [
    ((31, 26, 26),    (22, 28, 46)),
    ((71, 60, 154),   (90, 30, 50)),
    ((65, 78, 161),   (146, 65, 89)),
    ((85, 98, 183),   (200, 90, 100)),
    ((94, 121, 190),  (231, 97, 97)),
    ((73, 103, 141),  (130, 60, 70)),
]


# ============================================================
# Helpers
# ============================================================
def palette_swap(img, pairs):
    lut = {s: t for s, t in pairs}
    arr = np.array(img, dtype=np.uint8)
    out = arr.copy()
    h, w = arr.shape[:2]
    for y in range(h):
        for x in range(w):
            if arr[y, x, 3] == 0:
                continue
            rgb = (int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2]))
            if rgb in lut:
                out[y, x, 0:3] = lut[rgb]
    return Image.fromarray(out)


def trim_alpha(img):
    """Crop transparent borders to a tight bbox."""
    arr = np.array(img)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if not rows.any() or not cols.any():
        return img
    r0, r1 = np.where(rows)[0][[0, -1]]
    c0, c1 = np.where(cols)[0][[0, -1]]
    return img.crop((c0, r0, c1 + 1, r1 + 1))


def extract_wizard_hat(palette):
    """Extract, palette-swap, and upscale the wizard hat.

    Returns (upscaled_hat_image, cone_tip_x_in_image). The cone tip x
    is needed because the wizard's hat is drawn slightly tilted — the
    tip is ~4 cols left of the bbox center in the source. Centering
    by bbox would push the tip off-center on the tower. Centering by
    cone_tip_x keeps the hat visually plumb on top of the tower.
    """
    src = Image.open(WIZARD_PATH).convert("RGBA")
    f0 = src.crop((0, 0, 100, 100))
    hat = f0.crop((HAT_COL0, HAT_ROW0, HAT_COL1 + 1, HAT_ROW1 + 1))
    hat = trim_alpha(hat)

    # Find the cone tip x within the trimmed hat (topmost row's center)
    arr = np.array(hat)
    a = arr[:, :, 3]
    top_row_cols = np.where(a[0, :] > 32)[0]
    if len(top_row_cols) > 0:
        tip_x_native = (int(top_row_cols[0]) + int(top_row_cols[-1])) // 2
    else:
        tip_x_native = hat.width // 2

    hat = palette_swap(hat, palette)
    upscaled = hat.resize(
        (hat.width * HAT_UPSCALE, hat.height * HAT_UPSCALE),
        Image.NEAREST,
    )
    tip_x_upscaled = tip_x_native * HAT_UPSCALE + HAT_UPSCALE // 2
    return upscaled, tip_x_upscaled


# ============================================================
# Tower analysis: find the dome roof bbox so we know where to plant the hat
# ============================================================
def find_tower_top(tower_img):
    """Return (top_y, center_x) of the tower's content top.

    The cone-tip of the wizard hat will be planted ABOVE this point so
    the hat appears to crown the tower. Center_x is the horizontal
    midpoint of the tower's content bbox at its widest row.
    """
    arr = np.array(tower_img)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    if not rows.any():
        return None
    top_y = int(np.where(rows)[0][0])
    # Use the row at top_y + 30 (the battlement ring) for cx
    sample_row = min(top_y + 30, a.shape[0] - 1)
    cols_at_sample = np.where(a[sample_row, :] > 32)[0]
    if len(cols_at_sample) == 0:
        cols = np.any(a > 32, axis=0)
        c = np.where(cols)[0]
        cx = (c[0] + c[-1]) // 2
    else:
        cx = (cols_at_sample[0] + cols_at_sample[-1]) // 2
    return (top_y, int(cx))


# ============================================================
# Composite
# ============================================================
def make_mage_tower(tower_path, palette, out_path):
    tower = Image.open(tower_path).convert("RGBA")
    hat, tip_x_in_hat = extract_wizard_hat(palette)

    pos = find_tower_top(tower)
    if pos is None:
        print(f"  WARN: could not detect tower top in {tower_path}")
        return
    top_y, center_x = pos

    # Output canvas: extend ABOVE the tower so the hat tip doesn't clip
    # off the top of the frame. Hat brim overlaps the battlements ring
    # by ~10 px so the hat appears to sit ON the tower, not float above.
    BRIM_OVERLAP = 10
    hat_y_in_canvas_target = -1   # placeholder, computed below
    extra_top = max(0, hat.height - (top_y + BRIM_OVERLAP) + 4)
    out_w = tower.width
    out_h = tower.height + extra_top
    canvas = Image.new('RGBA', (out_w, out_h), (0, 0, 0, 0))

    # Paste the tower into the lower portion of the canvas (shifted down
    # by extra_top so the hat has room above)
    canvas.paste(tower, (0, extra_top))

    # Tower's top in canvas coords
    tower_top_canvas = top_y + extra_top

    # Hat position:
    #   horizontal: cone tip at the tower's center_x
    #   vertical:   hat bottom (brim) sits BRIM_OVERLAP pixels INTO the
    #               battlements (so the brim merges visually with the stones)
    hat_x = center_x - tip_x_in_hat
    hat_y = tower_top_canvas - hat.height + BRIM_OVERLAP

    layer = Image.new('RGBA', (out_w, out_h), (0, 0, 0, 0))
    layer.paste(hat, (hat_x, hat_y))
    canvas = Image.alpha_composite(canvas, layer)

    canvas.save(out_path)
    print(f"  {os.path.basename(out_path)}: {canvas.size} "
          f"(hat at ({hat_x}, {hat_y}), tower_top_canvas={tower_top_canvas}, "
          f"tip_x_in_hat={tip_x_in_hat})")


def main():
    print("=== Mage Tower Generation "
          "(Tiny Swords Tower + Tiny RPG Wizard hat) ===\n")

    out_dir_blue = "castle_clash/assets/sprites/buildings/blue"
    out_dir_red = "castle_clash/assets/sprites/buildings/red"
    os.makedirs(out_dir_blue, exist_ok=True)
    os.makedirs(out_dir_red, exist_ok=True)

    print("Blue (Kingdom):")
    make_mage_tower(TOWER_BLUE, PALETTE_BLUE,
                    os.path.join(out_dir_blue, "MageTower.png"))

    print("Red (Horde):")
    make_mage_tower(TOWER_RED, PALETTE_RED,
                    os.path.join(out_dir_red, "MageTower.png"))

    print("\nDone!")


if __name__ == "__main__":
    main()
