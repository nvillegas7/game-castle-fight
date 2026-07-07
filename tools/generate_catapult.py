#!/usr/bin/env python3
"""Generate catapult sprites: animated GIF machine + small pawn operator.

Uses Catapulta_animacion.gif (11 frames, 1024x1024) as the machine source.
The GIF has a full attack sequence baked in: arm loaded → swing → rock
launched with flame → recoil. This lets the attack animation use real
artist-authored frames instead of procedural arm rotation.

Idle/walk/death reuse frame 0 (arm up, loaded). The pawn is a Tiny Swords
pawn at ~45% of machine height, positioned to the left of the machine.
All 11 GIF frames are cropped with a SHARED bounding box so the machine's
base stays registered across frames (no wobble).
"""
from PIL import Image, ImageDraw, ImageFilter, ImageSequence
import numpy as np
import math
import os

F = 192  # Output frame size
# Composite sizing is calibrated against sprite_unit_visual.gd target_content=49
# for catapult. Standalone pawn idle content_h = 71px (measured from
# blue_pawn/Pawn_Idle.png). For pawn to display at the same in-game size as
# standalone (~30px), pawn % of idle composite bbox must = 30/49 = 61.2%.
# So idle composite content_h target ≈ 71 / 0.612 = 116px.
#
# Note: the GIF's frame 0 (idle-pose, arm loaded) only fills ~84% of the
# shared bbox height because later frames (arm swing + flame trail) push
# the bbox upward. We scale frames based on FRAME 0's content height so the
# idle composite hits the target — the attack frames will naturally extend
# a bit taller when the flame erupts.
IDLE_COMPOSITE_TARGET_H = 119  # Target content bbox height of idle frame 0

BLUE = {
    'outline': (22, 28, 46),
    'tint': None,  # No tint — use source colors
}
RED = {
    'outline': (22, 28, 46),
    'tint': (200, 60, 60),  # Red wash for Horde demolisher
}

SOURCE_GIF = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Catapulta_animacion.gif"
)
SOURCE_ROCK = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Catapulta_piedra.png"
)


# ============================================================
# GIF frame loading with shared bbox
# ============================================================
def load_gif_frames():
    """Load all 11 catapult GIF frames and crop with a SHARED bounding box.

    The shared bbox ensures the machine's base stays registered across
    frames — if we cropped each frame individually, the arm rising off
    frame 7 would shift the bbox and cause the base to wobble.

    Returns a list of RGBA Images, all the same size.
    """
    gif = Image.open(SOURCE_GIF)
    raw_frames = [f.convert("RGBA") for f in ImageSequence.Iterator(gif)]

    # Compute union bbox across all frames
    min_r, min_c, max_r, max_c = None, None, None, None
    for f in raw_frames:
        arr = np.array(f)
        alpha = arr[:, :, 3]
        rows = np.any(alpha > 32, axis=1)
        cols = np.any(alpha > 32, axis=0)
        if not rows.any() or not cols.any():
            continue
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        min_r = rmin if min_r is None else min(min_r, rmin)
        min_c = cmin if min_c is None else min(min_c, cmin)
        max_r = rmax if max_r is None else max(max_r, rmax)
        max_c = cmax if max_c is None else max(max_c, cmax)

    # Crop all frames with the shared bbox
    cropped = [f.crop((min_c, min_r, max_c + 1, max_r + 1)) for f in raw_frames]
    return cropped


def scale_machine_frames(frames, idle_target_h):
    """Uniformly scale all frames so FRAME 0's content bbox matches idle_target_h.

    This ensures the idle/walk/death composites (which reuse frame 0) have
    predictable total content height. Attack frames will naturally extend
    upward when the arm swings and the flame erupts — that's fine because
    sprite_unit_visual.gd locks auto-scale to the idle frame only.
    """
    # Measure frame 0's content height within the shared-bbox crop
    arr = np.array(frames[0])
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 32, axis=1)
    if not rows.any():
        return frames
    r0, r1 = np.where(rows)[0][[0, -1]]
    f0_content_h = r1 - r0 + 1
    ratio = idle_target_h / f0_content_h
    new_h = int(frames[0].height * ratio)
    new_w = int(frames[0].width * ratio)
    return [f.resize((new_w, new_h), Image.NEAREST) for f in frames]


# ============================================================
# Pawn loading
# ============================================================
def load_strip(path):
    strip = Image.open(path).convert("RGBA")
    h = strip.height
    n = max(1, strip.width // h)
    return [strip.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]


def scale_frame(frame, target_h):
    """Scale a full 192x192 pawn frame so the content height matches target_h."""
    arr = np.array(frame)
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 32, axis=1)
    if not np.any(rows):
        return frame
    rmin, rmax = np.where(rows)[0][[0, -1]]
    content_h = rmax - rmin + 1
    ratio = target_h / content_h
    new_size = (int(frame.width * ratio), int(frame.height * ratio))
    scaled = frame.resize(new_size, Image.NEAREST)
    result = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    ox = (F - scaled.width) // 2
    oy = (F - scaled.height) // 2
    result.paste(scaled, (ox, oy), scaled)
    return result


# ============================================================
# Team tint
# ============================================================
def apply_team_tint(img, tint_color, strength=0.25):
    """Apply soft team-color wash while preserving luminance."""
    if tint_color is None:
        return img
    arr = np.array(img, dtype=np.float32)
    alpha = arr[:, :, 3]
    mask = alpha > 0
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    for c in range(3):
        tint_scaled = tint_color[c] * (lum / 128.0)
        blended = arr[:, :, c] * (1 - strength) + tint_scaled * strength
        arr[:, :, c] = np.where(mask, np.clip(blended, 0, 255), arr[:, :, c])
    return Image.fromarray(arr.astype(np.uint8))


def add_outline(img, color, thickness=2):
    arr = np.array(img)
    alpha = arr[:, :, 3]
    dilated = np.array(Image.fromarray(alpha).filter(
        ImageFilter.MaxFilter(thickness * 2 + 1)))
    mask = (dilated > 128) & (alpha <= 128)
    out = arr.copy()
    out[mask] = [*color, 255]
    return Image.fromarray(out)


# ============================================================
# Frame composition
# ============================================================
def _content_bbox(img):
    """Return (rmin, cmin, rmax, cmax) of non-transparent pixels, or None."""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 32, axis=1)
    cols = np.any(alpha > 32, axis=0)
    if not rows.any() or not cols.any():
        return None
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    return (int(rmin), int(cmin), int(rmax), int(cmax))


def compose_frame(machine_img, pawn_frame, machine_dy=0, pal=None):
    """Compose one catapult frame: machine + NATIVE-size pawn operator.

    The pawn is pasted at its native Tiny Swords pixel size (no rescaling),
    so the operator looks identical in size to a standalone pawn unit.
    Machine and pawn are bottom-aligned on a shared ground line.

    machine_img: the full catapult machine for this animation frame
    machine_dy: vertical offset (bob for idle/walk)
    pawn_frame: raw 192x192 Tiny Swords pawn frame (used at native scale)
    """
    canvas = Image.new('RGBA', (F, F), (0, 0, 0, 0))

    # Ground line (bottom of both machine and pawn content)
    ground_y = F - 20

    # Machine position: centered horizontally, base on ground line
    machine_x = (F - machine_img.width) // 2 + 6
    machine_y = ground_y - machine_img.height + machine_dy

    # Pawn: use raw frame. Find content bbox and shift so bottom = ground_y.
    pbox = _content_bbox(pawn_frame)
    if pbox is None:
        pawn_x, pawn_y = 0, 0
    else:
        pr0, pc0, pr1, pc1 = pbox
        pawn_content_w = pc1 - pc0 + 1
        # Horizontal: place pawn to the LEFT of the machine, content tight
        target_pawn_content_cx = machine_x + 10 - (pawn_content_w // 2) - 2
        pawn_x = target_pawn_content_cx - pc0
        # Vertical: align pawn bottom with ground line
        pawn_y = ground_y - pr1

    # Layer order: machine FIRST, then pawn ON TOP per team-wide rule
    # "Tiny Swords base characters must always be the topmost layer".
    # The pawn is positioned to the LEFT of the machine so there's minimal
    # overlap with the arm/flame — when they do overlap, the pawn wins.
    # Use alpha_composite (not paste+mask) to preserve semi-transparent
    # shadow pixels — paste with RGBA as mask squares the alpha channel.
    machine_layer = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    machine_layer.paste(machine_img, (machine_x, machine_y))
    canvas = Image.alpha_composite(canvas, machine_layer)

    pawn_layer = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    pawn_layer.paste(pawn_frame, (pawn_x, pawn_y))
    canvas = Image.alpha_composite(canvas, pawn_layer)

    # Apply team tint if specified
    if pal and pal.get('tint'):
        canvas = apply_team_tint(canvas, pal['tint'], strength=0.3)

    return canvas


# ============================================================
# Animations
# ============================================================
def make_idle(machine_frames, pawn_idle, pal):
    """Idle: static machine (frame 0 = loaded), pawn bobbing. 6 frames."""
    frames = []
    base = machine_frames[0]  # frame 0 = arm up, loaded with rock
    for i in range(6):
        bob = int(math.sin(i / 6 * 2 * math.pi) * 1)
        pf = pawn_idle[i % len(pawn_idle)]
        frame = compose_frame(base, pf, machine_dy=bob, pal=pal)
        frames.append(frame)
    return frames


def make_run(machine_frames, pawn_run, pal):
    """Walk: loaded machine rolling with pawn walking alongside. 6 frames."""
    frames = []
    base = machine_frames[0]
    for i in range(6):
        bob = int(math.sin(i / 6 * 2 * math.pi) * 2)
        pf = pawn_run[i % len(pawn_run)]
        frame = compose_frame(base, pf, machine_dy=bob, pal=pal)
        frames.append(frame)
    return frames


def make_attack(machine_frames, pawn_interact, pal):
    """Attack: use the 11 GIF frames for the full fire sequence.

    The GIF already bakes in arm rotation, rock launch, flame trail, and
    recoil. We just pair each machine frame with a pawn frame cycling
    through the interact/hammer animation so the pawn looks active.
    """
    frames = []
    for i, mf in enumerate(machine_frames):
        pf = pawn_interact[i % len(pawn_interact)]
        frame = compose_frame(mf, pf, pal=pal)
        frames.append(frame)
    return frames


def make_guard(machine_frames, pawn_idle, pal):
    """Death/guard: machine and pawn sink down. 6 frames."""
    frames = []
    base = machine_frames[0]
    for i in range(6):
        sink = i // 2  # Progressive downward sink
        pf = pawn_idle[i % len(pawn_idle)]
        frame = compose_frame(base, pf, machine_dy=sink, pal=pal)
        frames.append(frame)
    return frames


# ============================================================
# Rock projectile
# ============================================================
def generate_rock(out_dir):
    """Copy/scale Catapulta_piedra.png as a clean projectile sprite."""
    src = Image.open(SOURCE_ROCK).convert("RGBA")
    # Trim any padding
    arr = np.array(src)
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 32, axis=1)
    cols = np.any(alpha > 32, axis=0)
    if rows.any() and cols.any():
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        src = src.crop((cmin, rmin, cmax + 1, rmax + 1))
    # Scale to 48x48 (small projectile)
    side = 48
    scale = min(side / src.width, side / src.height)
    new_w = int(src.width * scale)
    new_h = int(src.height * scale)
    scaled = src.resize((new_w, new_h), Image.NEAREST)
    # Center in 64x64 canvas with small padding
    canvas = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    ox = (64 - new_w) // 2
    oy = (64 - new_h) // 2
    canvas.paste(scaled, (ox, oy), scaled)
    out_path = os.path.join(out_dir, "Rock.png")
    canvas.save(out_path)
    print(f"  Rock.png (64x64)")


# ============================================================
# Team generation
# ============================================================
def generate_team(pal, team_name, pawn_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    print(f"Generating {team_name} catapult...")

    # Load all 11 GIF frames with shared bbox, scaled to target height
    raw = load_gif_frames()
    machine_frames = scale_machine_frames(raw, IDLE_COMPOSITE_TARGET_H)
    print(f"  loaded {len(machine_frames)} GIF machine frames "
          f"({machine_frames[0].size})")

    # Load pawn animations
    pawn_idle = load_strip(os.path.join(pawn_dir, "Pawn_Idle.png"))
    pawn_run = load_strip(os.path.join(pawn_dir, "Pawn_Run.png"))
    pawn_interact = load_strip(os.path.join(pawn_dir, "Pawn_Interact Hammer.png"))

    anims = {
        'Catapult_Idle': make_idle(machine_frames, pawn_idle, pal),
        'Catapult_Run': make_run(machine_frames, pawn_run, pal),
        'Catapult_Attack1': make_attack(machine_frames, pawn_interact, pal),
        'Catapult_Guard': make_guard(machine_frames, pawn_idle, pal),
    }

    for name, frames in anims.items():
        strip = Image.new('RGBA', (F * len(frames), F), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            strip.paste(f, (F * i, 0), f)
        out_path = os.path.join(out_dir, f"{name}.png")
        strip.save(out_path)
        print(f"  {name}.png ({strip.width}x{strip.height}, {len(frames)} frames)")

    # Rock projectile
    generate_rock(out_dir)
    print()


def main():
    base = "castle_clash/assets/sprites/units"
    print("=== Catapult Sprite Generation (GIF-based) ===\n")

    generate_team(BLUE, "Blue (Kingdom)",
                  os.path.join(base, "blue_pawn"),
                  os.path.join(base, "blue_catapult"))
    generate_team(RED, "Red (Horde)",
                  os.path.join(base, "red_pawn"),
                  os.path.join(base, "red_catapult"))

    print("Done!")


if __name__ == "__main__":
    main()
