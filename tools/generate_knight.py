#!/usr/bin/env python3
"""Generate mounted knight sprites: Tiny Swords lancer on a real artist horse.

Composites the Tiny Swords lancer (standalone character, same size as the
base "knight" unit in-game) with animated horse sprites from the
Knight_and_Horse asset pack. The lancer is preserved at its native 150px
content height so the rider displays at the same in-game size as the
standalone lancer, per the team-wide rider-size-parity rule.

Animation mapping:
  idle   → Tiny Swords Lancer_Idle + Horse_idle1..5 (cycled)
  run    → Tiny Swords Lancer_Run + Horse_walk1..8
  attack → Tiny Swords Lancer_Right_Attack + Horse_gallop1..5 (charging)
  guard  → Tiny Swords Lancer_Right_Defence + Horse_idle

Layer order (per memory feedback_rider_top_layer.md):
  1. shadow          (back)
  2. horse body      (mid)
  3. lancer (rider)  (TOP — most visible)
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math
import os

# ============================================================
# PALETTE
# ============================================================
# Only used for the HSV recolor of the horse body so the team-color
# reads clearly. The lancer keeps its native Tiny Swords colors.
BLUE = {
    'tint':  (70, 120, 170),    # cool blue team tint
    'tint_strength': 0.28,
}
RED = {
    'tint':  (200, 70, 70),     # warm red team tint
    'tint_strength': 0.32,
}

F = 320  # Output frame size (matches Tiny Swords lancer native)
SHADOW = (22, 28, 46, 50)

# Calibration note: a strict "full bbox" size-parity rule is misleading
# for the lancer because its spear pushes the bbox ~53px above the body,
# so a 150px "lancer" on screen is actually ~19px of body + ~11px of
# spear. Cascading that into the royal_knight composite makes the rider
# body look tiny on the horse.
#
# Instead we size the horse so its content height is ~1.2× the lancer
# BODY (body = content_h minus the spear extension). This keeps the
# composite bbox shorter than the strict 225px target, which RAISES the
# effective scale factor (scale = target_content/composite_h), making the
# lancer BODY bigger in-game — while keeping the rider clearly dominant
# over the horse visually.
#
# HORSE_SCALE=3.33: 22px native body → ~73px, which is ~1/1.5 of the
# previous 110px size per user request ("reduce the size of the horse by
# 1.5x, no change on the lancer riding it"). Fractional upscale still
# works with NEAREST resampling — pixels just double-up slightly unevenly.
HORSE_SCALE = 5.0 / 1.5  # ≈ 3.333

# Visible horse outline thickness (pixels of the output frame). The
# Knight_and_Horse horse has only a subtle internal outline; on a green
# battle terrain the gray-blue horse blends in. A 2px pure-black dilation
# ring around the horse's alpha mask gives it strong silhouette readability.
HORSE_OUTLINE_THICKNESS = 2
HORSE_OUTLINE_COLOR = (18, 18, 22)  # near-black

# How far left of the lancer head_cx to put the horse body center.
# Negative = horse shifts right relative to lancer (lancer ends up at
# horse back, away from horse head). Per user feedback "lancer too near
# horse head when facing left" — this offset puts the lancer over the
# horse's saddle/back instead of the horse's neck/shoulders.
HORSE_X_OFFSET = -8

# Rows in the 320×320 lancer frame that contain the lancer's HELMET.
# Used as the stable anchor point for compositing — the helmet is
# the most pose-stable part of the character (the spear and arms move
# wildly between idle/run/attack frames, but the helmet barely shifts).
LANCER_HEAD_ROWS = (125, 138)

# Source asset paths
KNIGHT_HORSE_DIR = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Knight_and_Horse")


# ============================================================
# Source loading
# ============================================================
def load_lancer_strip(path):
    """Load Tiny Swords Lancer sprite strip as a list of 320×320 RGBA frames."""
    strip = Image.open(path).convert("RGBA")
    h = strip.height
    assert h == F, f"Expected lancer frames at {F}px, got {h}"
    n = strip.width // h
    return [strip.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]


def load_horse_frames(subdir, prefix, count):
    """Load horse animation frames from Knight_and_Horse pack and upscale.

    Knight_and_Horse sprites are 48×48. We NEAREST-upscale by HORSE_SCALE
    so the horse's content_h is ~60-80px (depends on pose), and return
    them in a uniform 320×320 canvas for easy compositing.
    """
    frames = []
    for i in range(1, count + 1):
        path = os.path.join(KNIGHT_HORSE_DIR, subdir, f"{prefix}{i}.png")
        src = Image.open(path).convert("RGBA")
        up = src.resize(
            (int(src.width * HORSE_SCALE), int(src.height * HORSE_SCALE)),
            Image.NEAREST,
        )
        # Center on a 320×320 canvas for uniform compositing
        canvas = Image.new('RGBA', (F, F), (0, 0, 0, 0))
        ox = (F - up.width) // 2
        oy = (F - up.height) // 2
        canvas.paste(up, (ox, oy))
        frames.append(canvas)
    return frames


# ============================================================
# HSV team recolor (for horse trim / blanket / gear)
# ============================================================
def _add_outline(img, color, thickness=2):
    """Add a solid-color outline ring around non-transparent pixels.

    Dilates the alpha channel by `thickness` in all directions and paints
    the dilated-minus-original region with `color`. The result is an image
    with the original content untouched plus a pure-color silhouette ring
    around it. Used to make the gray-blue horse readable on green terrain.
    """
    arr = np.array(img)
    alpha = arr[:, :, 3]
    dilated = np.array(
        Image.fromarray(alpha).filter(ImageFilter.MaxFilter(thickness * 2 + 1))
    )
    mask = (dilated > 128) & (alpha <= 128)
    out = arr.copy()
    out[mask] = [*color, 255]
    return Image.fromarray(out)


def _hsv_recolor(img, target_rgb, strength=0.3):
    """Blend the image's pixels toward target_rgb in HSV space.

    Preserves per-pixel value (brightness) while shifting hue+saturation
    toward the team color. Used only on the horse — leaves the lancer
    untouched because the lancer already has faction-correct colors from
    the Tiny Swords pack.
    """
    from colorsys import rgb_to_hsv, hsv_to_rgb
    arr = np.array(img, dtype=np.uint8)
    alpha = arr[:, :, 3]
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
            # Blend hue fully toward target, keep some native saturation
            new_s = src_s * (1 - strength) + ts * strength
            new_h = th
            nr, ng, nb = hsv_to_rgb(new_h, new_s, src_v)
            out[y, x, 0] = int(nr * 255)
            out[y, x, 1] = int(ng * 255)
            out[y, x, 2] = int(nb * 255)
    return Image.fromarray(out)


# ============================================================
# Horse positioning: find the horse's content bbox and anchor it below
# the lancer's feet so the rider appears to sit on the horse.
# ============================================================
def _content_bbox(img):
    arr = np.array(img)
    a = arr[:, :, 3]
    rows = np.any(a > 32, axis=1)
    cols = np.any(a > 32, axis=0)
    if not rows.any():
        return None
    r0, r1 = np.where(rows)[0][[0, -1]]
    c0, c1 = np.where(cols)[0][[0, -1]]
    return (int(r0), int(c0), int(r1), int(c1))


def _lancer_head_cx(img):
    """Return the column index of the lancer's helmet center.

    Uses a narrow row range (LANCER_HEAD_ROWS) that contains only the
    helmet — not the spear or extended arms. This gives a stable anchor
    point that barely moves between attack/idle/run frames, unlike the
    full bbox cx which jumps ~80 pixels when the spear extends right.
    """
    arr = np.array(img)
    a = arr[:, :, 3]
    sub = a[LANCER_HEAD_ROWS[0]:LANCER_HEAD_ROWS[1], :]
    cols = np.any(sub > 32, axis=0)
    if not cols.any():
        return None
    c0, c1 = np.where(cols)[0][[0, -1]]
    return (int(c0) + int(c1)) // 2


def stabilize_lancer_animation(frames):
    """Counter-shift each frame so its head cx aligns to the median.

    Eliminates the small per-frame drift within an animation (e.g. attack
    frames have head_cx 162-170 = 8px range). After stabilization the
    helmet stays at the same x across all frames in the animation, so
    the lancer body holds steady on the horse and only the spear/arm
    visibly extends. Returns (stabilized_frames, median_cx).
    """
    head_cxs = [_lancer_head_cx(f) for f in frames]
    valid = [c for c in head_cxs if c is not None]
    if not valid:
        return frames, None
    median = sorted(valid)[len(valid) // 2]
    out = []
    for i, f in enumerate(frames):
        if head_cxs[i] is None:
            out.append(f)
            continue
        dx = median - head_cxs[i]
        if dx == 0:
            out.append(f)
        else:
            shifted = Image.new('RGBA', f.size, (0, 0, 0, 0))
            shifted.paste(f, (dx, 0))
            out.append(shifted)
    return out, median


def position_horse_under_lancer(horse_frame, lancer_frame, tint,
                                 reference_lancer=None,
                                 motion_damping=1.0):
    """Shift the horse so its saddle aligns with the lancer's seat.

    Args:
        horse_frame: raw 320×320 RGBA horse image (centered in canvas)
        lancer_frame: current lancer animation frame
        tint: team palette dict
        reference_lancer: optional "rest pose" lancer frame used as a
            stable anchor when the current lancer's bbox moves between
            animation frames (e.g. attack frames where the spear
            thrusts/retracts shift the bbox cx). The horse is positioned
            toward the reference and then the actual current-vs-reference
            horizontal delta is multiplied by `motion_damping`.
        motion_damping: 1.0 = horse follows lancer 1:1 (default),
            0.667 = horse follows 1/1.5 as much (reduces the visible
            "lurch forward" in attack animations per user feedback).

    Returns the repositioned horse as a full-frame (F×F) RGBA image.
    """
    # Measure bboxes
    lbox = _content_bbox(lancer_frame)
    hbox = _content_bbox(horse_frame)
    if lbox is None or hbox is None:
        return horse_frame

    l_top, l_cx_min, l_bot, l_cx_max = lbox
    h_top, h_cx_min, h_bot, h_cx_max = hbox
    horse_h = h_bot - h_top + 1

    # Compute the lancer's RIDING SEAT position. Critical detail: the
    # lancer bbox's `l_top` is the SPEAR TIP, not the body top — so
    # `(l_bot - l_top)` doubles the body height and produces a saddle
    # line that floats above the actual hip area, dragging the horse up
    # into the lancer torso. Instead, use a fixed pixel offset from the
    # lancer's feet (`l_bot`) which is stable across all attack/idle
    # frames and matches the Tiny Swords lancer's actual body geometry.
    LANCER_SEAT_FROM_FEET = 15  # ~20% of the 75px body height (hip line)
    lancer_seat_y = l_bot - LANCER_SEAT_FROM_FEET

    # Horse "back" (where rider sits) is just below the horse bbox top.
    # Use a small offset (not the previous 33%) so the horse top sits
    # AT the lancer seat — that way the lancer body extends UP from the
    # horse back like a real rider, with only the lower hip/legs
    # overlapping the horse silhouette.
    horse_back_offset = int(horse_h * 0.08)  # was 0.33 → caused full overlap

    # We want horse_back at lancer_seat_y
    target_horse_top = lancer_seat_y - horse_back_offset
    dy = target_horse_top - h_top

    # Horizontal: anchor on the lancer's HEAD position (helmet cx), not
    # the bbox cx. The bbox cx is dominated by the spear: in an attack
    # frame the spear extends ~80 pixels right, dragging bbox cx to ~225
    # while the actual lancer body stays at ~167. Anchoring on the head
    # keeps the horse glued to where the character actually is, not
    # where the spear tip points. Falls back to bbox cx if head detect
    # fails (shouldn't happen with the standard Tiny Swords lancer).
    head_cx = _lancer_head_cx(lancer_frame)
    if head_cx is None:
        head_cx = (l_cx_min + l_cx_max) // 2
    # HORSE_X_OFFSET shifts the horse RIGHT in the source so the lancer
    # ends up at the horse's BACK (toward the tail) instead of the head.
    # User feedback: "lancer too near horse head when facing left" — the
    # offset works for both blue and red because flip_h mirrors the
    # whole sprite, so a lancer-back-of-horse pose stays back-of-horse
    # on screen regardless of facing direction.
    horse_cx = (h_cx_min + h_cx_max) // 2
    dx = head_cx - horse_cx - HORSE_X_OFFSET

    shifted = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    shifted.paste(horse_frame, (dx, dy))

    # Apply team tint to the body
    if tint.get('tint'):
        shifted = _hsv_recolor(
            shifted, tint['tint'], strength=tint.get('tint_strength', 0.3)
        )

    # Add black outline AFTER tinting so the outline stays pure black
    # (tinting would otherwise drag the outline toward the team color and
    # defeat the silhouette purpose).
    shifted = _add_outline(
        shifted, HORSE_OUTLINE_COLOR, HORSE_OUTLINE_THICKNESS
    )
    return shifted


# ============================================================
# Frame composition
# ============================================================
def make_mounted_frame(lancer_frame, horse_frame, tint, bob=0,
                       reference_lancer=None, motion_damping=1.0):
    """Compose one mounted knight frame: shadow → horse → lancer (TOP).

    reference_lancer + motion_damping are passed through to
    position_horse_under_lancer. Defaults preserve the pre-existing
    "horse follows lancer 1:1" behaviour for idle/walk/guard. The attack
    animation uses a reference + 1/1.5 damping so the horse lunges
    forward only 2/3 as much as the lancer's spear thrust (user request).
    """
    horse_positioned = position_horse_under_lancer(
        horse_frame, lancer_frame, tint,
        reference_lancer=reference_lancer,
        motion_damping=motion_damping,
    )

    # Optional bob for the horse+lancer
    if bob != 0:
        bobbed = Image.new('RGBA', (F, F), (0, 0, 0, 0))
        bobbed.paste(horse_positioned, (0, bob))
        horse_positioned = bobbed
        lancer_bobbed = Image.new('RGBA', (F, F), (0, 0, 0, 0))
        lancer_bobbed.paste(lancer_frame, (0, bob))
        lancer_frame = lancer_bobbed

    # Shadow: elongated ellipse below the horse feet
    shadow = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    from PIL import ImageDraw
    sd = ImageDraw.Draw(shadow)
    hbox = _content_bbox(horse_positioned)
    if hbox is not None:
        h_bot = hbox[2]
        h_cx = (hbox[1] + hbox[3]) // 2
        sd.ellipse(
            [h_cx - 44, h_bot - 6, h_cx + 44, h_bot + 6],
            fill=SHADOW,
        )

    # CRITICAL per feedback_rider_top_layer.md:
    # lancer (rider) is ALWAYS the topmost layer.
    result = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    result = Image.alpha_composite(result, shadow)
    result = Image.alpha_composite(result, horse_positioned)  # mount
    result = Image.alpha_composite(result, lancer_frame)       # TOP
    return result


# ============================================================
# Animations
# ============================================================
def make_idle(lancer_frames, horse_idle, tint):
    """Idle: horse_idle cycle + lancer idle frames, gentle bob.

    Stabilizes the lancer head cx within the animation so the lancer
    body stays glued to the horse across all 12 idle frames.
    """
    stable, _ = stabilize_lancer_animation(lancer_frames)
    frames = []
    for i, lf in enumerate(stable):
        hf = horse_idle[i % len(horse_idle)]
        bob = round(math.sin(i / max(len(stable), 1) * 2 * math.pi) * 1.5)
        frames.append(make_mounted_frame(lf, hf, tint, bob=bob))
    return frames


def make_run(lancer_frames, horse_walk, tint):
    """Walk: horse_walk cycle + lancer run frames (stabilized)."""
    stable, _ = stabilize_lancer_animation(lancer_frames)
    frames = []
    n_h = len(horse_walk)
    bob_cycle = [0, -1, -2, -1, 0, 1]
    for i, lf in enumerate(stable):
        hf = horse_walk[i % n_h]
        bob = bob_cycle[i % len(bob_cycle)]
        frames.append(make_mounted_frame(lf, hf, tint, bob=bob))
    return frames


def make_attack(lancer_frames, horse_gallop, tint):
    """Attack: horse charging (gallop) + lancer attack frames.

    The lancer's bbox cx jumps wildly between attack frames (162-170 px
    range for the head, BUT 144-306 cols for the bbox because the spear
    thrusts forward then retracts). Previous attempts to dampen the
    horse motion (T-080) didn't work because position_horse_under_lancer
    was anchoring on the bbox cx instead of the body. T-083 fix: anchor
    on head_cx (which jumps only 8px max) AND stabilize within the
    animation so the head is at the same cx for all 3 attack frames.
    Result: lancer body and horse stay locked, only the spear extends.
    """
    stable, _ = stabilize_lancer_animation(lancer_frames)
    frames = []
    n_h = len(horse_gallop)
    for i, lf in enumerate(stable):
        hf = horse_gallop[i % n_h]
        bob = round(math.sin(i / max(len(stable), 1) * math.pi) * -2)
        frames.append(make_mounted_frame(lf, hf, tint, bob=bob))
    return frames


def make_guard(lancer_frames, horse_idle, tint):
    """Guard/death: horse_idle + lancer defence frames, progressive sink."""
    stable, _ = stabilize_lancer_animation(lancer_frames)
    frames = []
    for i, lf in enumerate(stable):
        hf = horse_idle[i % len(horse_idle)]
        sink = i // 2
        frames.append(make_mounted_frame(lf, hf, tint, bob=sink))
    return frames


# ============================================================
# Output
# ============================================================
def assemble_strip(frames):
    strip = Image.new('RGBA', (F * len(frames), F), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (F * i, 0))
    return strip


def generate_team(tint, team_name, lancer_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    print(f"Generating {team_name} mounted knight...")

    # Load Tiny Swords lancer animations
    lancer_idle = load_lancer_strip(os.path.join(lancer_dir, "Lancer_Idle.png"))
    lancer_run = load_lancer_strip(os.path.join(lancer_dir, "Lancer_Run.png"))
    lancer_attack = load_lancer_strip(
        os.path.join(lancer_dir, "Lancer_Right_Attack.png")
    )
    lancer_guard = load_lancer_strip(
        os.path.join(lancer_dir, "Lancer_Right_Defence.png")
    )

    # Load real artist horse animations from Knight_and_Horse pack
    horse_idle = load_horse_frames("Idle", "Horse_idle", 5)
    horse_walk = load_horse_frames("Walk", "Horse_walk", 8)
    horse_gallop = load_horse_frames("Gallop", "Horse_gallop", 5)

    anims = {
        'Knight_Idle': make_idle(lancer_idle, horse_idle, tint),
        'Knight_Run': make_run(lancer_run, horse_walk, tint),
        'Knight_Attack1': make_attack(lancer_attack, horse_gallop, tint),
        'Knight_Guard': make_guard(lancer_guard, horse_idle, tint),
    }

    for name, frames in anims.items():
        strip = assemble_strip(frames)
        path = os.path.join(out_dir, f"{name}.png")
        strip.save(path)
        print(f"  {name}.png  ({strip.width}x{strip.height}, "
              f"{len(frames)} frames)")
    print()


def main():
    base = "castle_clash/assets/sprites/units"
    print("=== Mounted Knight Sprite Generation "
          "(Tiny Swords lancer + real horse) ===\n")

    generate_team(BLUE, "Blue (Kingdom)",
                  os.path.join(base, "blue_lancer"),
                  os.path.join(base, "blue_knight"))
    generate_team(RED, "Red (Horde)",
                  os.path.join(base, "red_lancer"),
                  os.path.join(base, "red_knight"))

    print("Done!")


if __name__ == "__main__":
    main()
