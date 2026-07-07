#!/usr/bin/env python3
"""Generate T3 unit sprites: Champion (Knight Templar) and Warlord (Elite Orc).

Upscales Tiny RPG 100x100 sprites to 192x192 with team-color tinting.
Champion = Kingdom blue, Warlord = Horde red.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import numpy as np
import os

# ============================================================
# CONFIG
# ============================================================
FRAME_SIZE = 192  # Output frame size (matches Tiny Swords)
SRC_SIZE = 100    # Tiny RPG frame size
SCALE = 2         # 100 * 2 = 200, then center-crop to 192

RPG_BASE = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/"
    "Characters(100x100)"
)
OUT_BASE = "castle_clash/assets/sprites/units"

# Team color tint overlays (applied as soft light blend)
BLUE_TINT = (60, 100, 200)   # Kingdom blue
RED_TINT = (200, 60, 60)     # Horde red


# ============================================================
# HELPERS
# ============================================================
def load_strip(path):
    """Load a horizontal sprite strip and return individual frames."""
    strip = Image.open(path).convert("RGBA")
    h = strip.height
    n = max(1, strip.width // h)
    return [strip.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]


def upscale_frame(frame, target=FRAME_SIZE):
    """Upscale a small frame to target size using nearest-neighbor, centered."""
    # Scale up with nearest neighbor (preserves pixel art crispness)
    scaled = frame.resize((SRC_SIZE * SCALE, SRC_SIZE * SCALE), Image.NEAREST)
    sw, sh = scaled.size

    # Center in target canvas
    result = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    ox = (target - sw) // 2
    oy = (target - sh) // 2
    result.paste(scaled, (ox, oy), scaled)
    return result


def add_outline(img, color, thickness=2):
    """Add a colored outline around non-transparent pixels."""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    dilated = np.array(Image.fromarray(alpha).filter(
        ImageFilter.MaxFilter(thickness * 2 + 1)))
    mask = (dilated > 128) & (alpha <= 128)
    out = arr.copy()
    out[mask] = [*color, 255]
    return Image.fromarray(out)


def apply_team_tint(img, tint_color, strength=0.25):
    """Apply a subtle team-color tint to non-transparent pixels.

    Uses a multiply-like blend: shifts hue toward tint while preserving
    luminance and detail. Only affects pixels with alpha > 0.
    """
    arr = np.array(img, dtype=np.float32)
    alpha = arr[:, :, 3]
    mask = alpha > 0

    # Compute luminance of each pixel
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]

    for c in range(3):
        # Blend: original * (1 - strength) + tint_scaled * strength
        # tint_scaled preserves luminance: tint_channel * (lum / 128)
        tint_val = tint_color[c]
        tint_scaled = tint_val * (lum / 128.0)
        blended = arr[:, :, c] * (1 - strength) + tint_scaled * strength
        arr[:, :, c] = np.where(mask, np.clip(blended, 0, 255), arr[:, :, c])

    return Image.fromarray(arr.astype(np.uint8))


def add_shadow(img):
    """Add a small drop shadow ellipse beneath the character."""
    arr = np.array(img)
    alpha = arr[:, :, 3]

    # Find bounding box of non-transparent pixels
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not np.any(rows) or not np.any(cols):
        return img

    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]

    # Shadow positioned at character's feet
    cx = (cmin + cmax) // 2
    cy = rmax + 2
    rx = (cmax - cmin) // 3
    ry = max(3, rx // 3)

    result = img.copy()
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(22, 28, 46, 50))

    # Paste shadow behind character
    out = Image.alpha_composite(shadow, result)
    return out


def assemble_strip(frames):
    """Combine frames into a horizontal sprite strip."""
    if not frames:
        return Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    strip = Image.new("RGBA", (FRAME_SIZE * len(frames), FRAME_SIZE), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (FRAME_SIZE * i, 0))
    return strip


def process_animation(src_path, tint_color, outline_color):
    """Load strip → upscale → tint → outline → shadow each frame."""
    frames = load_strip(src_path)
    result = []
    for frame in frames:
        f = upscale_frame(frame)
        f = apply_team_tint(f, tint_color, strength=0.3)
        f = add_shadow(f)
        f = add_outline(f, outline_color, thickness=2)
        result.append(f)
    return result


# ============================================================
# CHAMPION (Knight Templar → Kingdom Blue)
# ============================================================
def generate_champion():
    """Generate blue_champion sprites from Knight Templar."""
    src_dir = os.path.join(RPG_BASE, "Knight Templar", "Knight Templar")
    out_dir = os.path.join(OUT_BASE, "blue_champion")
    os.makedirs(out_dir, exist_ok=True)

    outline = (22, 28, 46)  # Dark outline matching Tiny Swords style

    # Animation mapping: output_name → source_file
    anims = {
        "Champion_Idle":    "Knight Templar-Idle.png",
        "Champion_Walk":    "Knight Templar-Walk01.png",
        "Champion_Attack1": "Knight Templar-Attack01.png",
        "Champion_Death":   "Knight Templar-Death.png",
        "Champion_Guard":   "Knight Templar-Block.png",
    }

    print("Generating Champion (Kingdom Blue)...")
    for anim_name, src_file in anims.items():
        src_path = os.path.join(src_dir, src_file)
        if not os.path.exists(src_path):
            print(f"  SKIP {anim_name}: {src_file} not found")
            continue

        frames = process_animation(src_path, BLUE_TINT, outline)
        strip = assemble_strip(frames)
        out_path = os.path.join(out_dir, f"{anim_name}.png")
        strip.save(out_path)
        print(f"  {anim_name}.png ({strip.width}x{strip.height}, {len(frames)} frames)")

    print(f"  → {out_dir}/\n")


# ============================================================
# WARLORD (Elite Orc → Horde Red)
# ============================================================
def generate_warlord():
    """Generate red_warlord sprites from Elite Orc."""
    src_dir = os.path.join(RPG_BASE, "Elite Orc", "Elite Orc")
    out_dir = os.path.join(OUT_BASE, "red_warlord")
    os.makedirs(out_dir, exist_ok=True)

    outline = (22, 28, 46)

    anims = {
        "Warlord_Idle":    "Elite Orc-Idle.png",
        "Warlord_Walk":    "Elite Orc-Walk.png",
        "Warlord_Attack1": "Elite Orc-Attack01.png",
        "Warlord_Death":   "Elite Orc-Death.png",
        "Warlord_Hurt":    "Elite Orc-Hurt.png",
    }

    print("Generating Warlord (Horde Red)...")
    for anim_name, src_file in anims.items():
        src_path = os.path.join(src_dir, src_file)
        if not os.path.exists(src_path):
            print(f"  SKIP {anim_name}: {src_file} not found")
            continue

        frames = process_animation(src_path, RED_TINT, outline)
        strip = assemble_strip(frames)
        out_path = os.path.join(out_dir, f"{anim_name}.png")
        strip.save(out_path)
        print(f"  {anim_name}.png ({strip.width}x{strip.height}, {len(frames)} frames)")

    print(f"  → {out_dir}/\n")


# ============================================================
# MAIN
# ============================================================
def main():
    print("=== T3 Unit Sprite Generation ===\n")
    generate_champion()
    generate_warlord()
    print("Done!")


if __name__ == "__main__":
    main()
