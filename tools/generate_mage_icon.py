#!/usr/bin/env python3
"""Generate the mage_tower roof icon (wizard hat) for the BUILDING_ICON system.

A2's `sprite_building_visual.gd` has a `BUILDING_ICON` dict that overlays
small symbolic icons on top of upgrade buildings to distinguish them from
their parent (e.g. gryphon_roost gets wing_icon over Archery, royal_stable
gets horse_icon over Barracks). Following the same pattern, mage_tower
needs a `mage_icon.png` so A2 can wire `mage_tower → Tower base + mage_icon`.

Source: same Tiny RPG Wizard hat region used by generate_mage_alt.py
(rows 39-44, cols 43-59 of Wizard-Idle frame 0). Palette-swapped to
Tiny Swords colors so it visually matches the mage unit's recolored hat.

Output: castle_clash/assets/sprites/ui/mage_icon.png (~68×24)
"""
from PIL import Image
import numpy as np
import os

WIZARD_PATH = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Characters(100x100)/Wizard/Wizard/Wizard-Idle.png"
)

HAT_ROW0, HAT_ROW1 = 39, 44
HAT_COL0, HAT_COL1 = 43, 59
UPSCALE = 4

# Same palette swap as generate_mage.py — Tiny Swords blue family
PALETTE_BLUE = [
    ((31, 26, 26),    (22, 28, 46)),
    ((71, 60, 154),   (40, 50, 80)),
    ((65, 78, 161),   (72, 88, 132)),
    ((85, 98, 183),   (95, 130, 175)),
    ((94, 121, 190),  (130, 170, 210)),
    ((73, 103, 141),  (70, 100, 145)),
]


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
                tgt = lut[rgb]
                out[y, x, 0:3] = tgt
    return Image.fromarray(out)


def main():
    src = Image.open(WIZARD_PATH).convert("RGBA")
    f0 = src.crop((0, 0, 100, 100))
    # Crop hat region (cone tip + brim)
    hat = f0.crop((HAT_COL0, HAT_ROW0, HAT_COL1 + 1, HAT_ROW1 + 1))
    # Trim transparent edges
    arr = np.array(hat)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if rows.any() and cols.any():
        r0, r1 = np.where(rows)[0][[0, -1]]
        c0, c1 = np.where(cols)[0][[0, -1]]
        hat = hat.crop((c0, r0, c1 + 1, r1 + 1))
    # Recolor to Tiny Swords palette so it matches the mage unit's hat
    hat = palette_swap(hat, PALETTE_BLUE)
    # Upscale 4× for visibility on building tops
    upscaled = hat.resize(
        (hat.width * UPSCALE, hat.height * UPSCALE),
        Image.NEAREST,
    )
    out_path = "castle_clash/assets/sprites/ui/mage_icon.png"
    upscaled.save(out_path)
    print(f"Saved {out_path} at {upscaled.size}")


if __name__ == "__main__":
    main()
