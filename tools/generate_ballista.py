#!/usr/bin/env python3
"""Generate Tiny Swords style ballista sprite sheets for Castle Clash.

Composites the real Tiny Swords pawn (hammer) with a procedural ballista
weapon at 1.5x scale. Uses exact wood/metal palette from Tiny Swords buildings.
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math
import os

# ============================================================
# PALETTE
# ============================================================
WOOD = {
    'outline':     (22, 28, 46),
    'outline_mid': (64, 65, 86),
    'wood_dark':   (155, 114, 96),
    'wood_med':    (208, 152, 98),
    'wood_light':  (233, 188, 127),
    'wood_cream':  (225, 220, 163),
    'stone':       (187, 174, 147),
    'stone_dark':  (152, 142, 132),
    'gray':        (84, 114, 111),
    'dark_gray':   (63, 74, 80),
    'metal':       (128, 158, 148),
    'metal_light': (164, 185, 170),
    'rope':        (200, 168, 118),
    'white':       (255, 255, 255),
    'bolt_tip':    (140, 145, 155),
}

BLUE_TEAM = {'armor': (76, 92, 139), 'accent': (71, 149, 167), 'light': (99, 183, 186)}
RED_TEAM = {'armor': (146, 65, 89), 'accent': (231, 97, 97), 'light': (207, 156, 113)}

F = 192
SHADOW = (22, 28, 46, 50)
S = 1.5  # ballista scale factor


# ============================================================
# Drawing helpers
# ============================================================
def fp(draw, pts, color):
    draw.polygon(pts, fill=color + (255,) if len(color) == 3 else color)

def fe(draw, bbox, color):
    draw.ellipse(bbox, fill=color + (255,) if len(color) == 3 else color)

def fl(draw, pts, color, width=2):
    draw.line(pts, fill=color + (255,) if len(color) == 3 else color, width=width)

def frect(draw, bbox, color):
    draw.rectangle(bbox, fill=color + (255,) if len(color) == 3 else color)

def o(val):
    """Scale an offset by the ballista scale factor."""
    return round(val * S)

def make_outline(img, color, thickness=2):
    arr = np.array(img)
    alpha = arr[:, :, 3]
    dilated = np.array(Image.fromarray(alpha).filter(
        ImageFilter.MaxFilter(thickness * 2 + 1)))
    mask = (dilated > 128) & (alpha <= 128)
    out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    out[mask] = [*color, 255]
    return Image.fromarray(out)


def load_frames(path):
    strip = Image.open(path).convert("RGBA")
    h = strip.height
    n = strip.width // h
    return [strip.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]

def shift_frame(frame, dx, dy):
    result = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    result.paste(frame, (dx, dy), frame)
    return result


# ============================================================
# Ballista weapon drawing (1.5x scale)
# ============================================================
def draw_wheel(draw, cx, cy, radius):
    W = WOOD
    r = radius
    fe(draw, [cx - r, cy - r, cx + r, cy + r], W['wood_dark'])
    fe(draw, [cx - r + 3, cy - r + 3, cx + r - 3, cy + r - 3], W['wood_med'])
    fe(draw, [cx - 4, cy - 4, cx + 4, cy + 4], W['wood_dark'])
    fe(draw, [cx - 2, cy - 2, cx + 2, cy], W['wood_light'])
    for i in range(4):
        angle = i * math.pi / 4
        sx = round(cx + math.cos(angle) * (r - 4))
        sy = round(cy + math.sin(angle) * (r - 4))
        fl(draw, [(cx, cy), (sx, sy)], W['wood_dark'], width=2)


def draw_ballista_weapon(draw, bx, by, team, arm_angle=0, has_bolt=True,
                         string_pull=0, recoil=0):
    W = WOOD
    rx = o(recoil)

    # ---- WHEELS ----
    wheel_y = by + o(16)
    draw_wheel(draw, bx - o(14) + rx, wheel_y, o(9))
    draw_wheel(draw, bx + o(14) + rx, wheel_y, o(9))
    # Axle
    frect(draw, [bx - o(16) + rx, wheel_y - 2, bx + o(16) + rx, wheel_y + 2], W['wood_dark'])

    # ---- BASE PLATFORM ----
    fp(draw, [
        (bx - o(18) + rx, by + o(4)), (bx + o(22) + rx, by + o(4)),
        (bx + o(24) + rx, by + o(10)), (bx - o(16) + rx, by + o(10)),
    ], W['wood_med'])
    frect(draw, [bx - o(17) + rx, by + o(4), bx + o(22) + rx, by + o(6)], W['wood_light'])
    frect(draw, [bx - o(16) + rx, by + o(8), bx + o(23) + rx, by + o(10)], W['wood_dark'])

    # ---- MAIN STOCK ----
    fp(draw, [
        (bx - o(12) + rx, by - o(4)), (bx + o(28) + rx, by - o(6)),
        (bx + o(30) + rx, by + o(2)), (bx - o(12) + rx, by + o(2)),
    ], W['wood_med'])
    frect(draw, [bx - o(10) + rx, by - o(4), bx + o(28) + rx, by - o(2)], W['wood_light'])
    frect(draw, [bx - o(8) + rx, by - o(2), bx + o(26) + rx, by], W['wood_dark'])

    # ---- SUPPORT STRUTS ----
    fp(draw, [
        (bx - o(10) + rx, by + o(4)), (bx - o(6) + rx, by + o(4)),
        (bx - o(8) + rx, by - o(2)), (bx - o(12) + rx, by - o(2)),
    ], W['wood_dark'])
    fp(draw, [
        (bx + o(10) + rx, by + o(4)), (bx + o(14) + rx, by + o(4)),
        (bx + o(16) + rx, by - o(2)), (bx + o(12) + rx, by - o(2)),
    ], W['wood_dark'])

    # ---- BOW ARMS ----
    arm_spread = {0: 35, 1: 20, 2: 5}
    spread = arm_spread.get(arm_angle, 35)
    mount_x = bx + o(28) + rx
    mount_y = by - o(2)
    arm_len = o(28)
    arm_base_w = o(3)

    for sign in [-1, 1]:  # upper arm (-1) and lower arm (+1)
        a = math.radians(180 - spread * sign)
        tip_x = round(mount_x + math.cos(a) * arm_len)
        tip_y = round(mount_y + math.sin(a) * arm_len)
        perp = a + math.pi / 2
        pts = [
            (mount_x + round(math.cos(perp) * arm_base_w),
             mount_y + round(math.sin(perp) * arm_base_w)),
            (tip_x + round(math.cos(perp) * 1),
             tip_y + round(math.sin(perp) * 1)),
            (tip_x - round(math.cos(perp) * 1),
             tip_y - round(math.sin(perp) * 1)),
            (mount_x - round(math.cos(perp) * arm_base_w),
             mount_y - round(math.sin(perp) * arm_base_w)),
        ]
        fp(draw, pts, W['wood_med'])
        fl(draw, [(mount_x, mount_y), (tip_x, tip_y)], W['wood_light'], width=1)
        fe(draw, [tip_x - o(3), tip_y - o(3), tip_x + o(3), tip_y + o(3)], W['metal'])

        # Store tip for string
        if sign == -1:
            ua_tip = (tip_x, tip_y)
        else:
            la_tip = (tip_x, tip_y)

    # ---- BOWSTRING ----
    # string_pull 0..3: 0=relaxed, 1=taut, 2=half-cocked, 3=fully cocked
    sdx = [0, o(5), o(10), o(16)][min(string_pull, 3)]
    smx = (ua_tip[0] + la_tip[0]) // 2 - sdx
    smy = (ua_tip[1] + la_tip[1]) // 2
    fl(draw, [ua_tip, (smx, smy)], W['rope'], width=2)
    fl(draw, [la_tip, (smx, smy)], W['rope'], width=2)

    # ---- BOLT ----
    if has_bolt:
        bolt_x = bx - o(6) + rx
        bolt_y = by - o(2)
        bolt_tip_x = bx + o(38) + rx
        fl(draw, [(bolt_x, bolt_y), (bolt_tip_x, bolt_y)], W['wood_dark'], width=o(2))
        # Arrowhead
        fp(draw, [
            (bolt_tip_x, bolt_y - o(4)),
            (bolt_tip_x + o(10), bolt_y),
            (bolt_tip_x, bolt_y + o(4)),
        ], W['bolt_tip'])
        fp(draw, [
            (bolt_tip_x + o(2), bolt_y - o(2)),
            (bolt_tip_x + o(8), bolt_y),
            (bolt_tip_x + o(2), bolt_y),
        ], W['metal_light'])
        # Fletching
        fp(draw, [(bolt_x, bolt_y - o(4)), (bolt_x + o(6), bolt_y), (bolt_x, bolt_y)],
           W['wood_light'])
        fp(draw, [(bolt_x, bolt_y), (bolt_x + o(6), bolt_y), (bolt_x, bolt_y + o(4))],
           W['wood_dark'])

    # ---- FRONT BRACKET ----
    bw = o(3)
    bh = o(6)
    fp(draw, [
        (mount_x - bw, mount_y - bh), (mount_x + bw, mount_y - bh),
        (mount_x + bw, mount_y + bh), (mount_x - bw, mount_y + bh),
    ], W['metal'])
    fe(draw, [mount_x - 2, mount_y - o(4), mount_x + 2, mount_y - o(2)], W['metal_light'])
    fe(draw, [mount_x - 2, mount_y + o(2), mount_x + 2, mount_y + o(4)], W['metal_light'])

    # ---- TEAM FLAG ----
    fp(draw, [
        (bx - o(14) + rx, by - o(8)), (bx - o(14) + rx, by + o(2)),
        (bx - o(8) + rx, by), (bx - o(8) + rx, by - o(6)),
    ], team['armor'])
    frect(draw, [bx - o(13) + rx, by - o(5), bx - o(9) + rx, by - o(3)], team['accent'])

    # ---- WINCH ----
    wx = bx - o(12) + rx
    wy = by - o(6)
    fe(draw, [wx - o(4), wy - o(4), wx + o(4), wy + o(4)], W['metal'])
    fe(draw, [wx - o(2), wy - o(2), wx + o(2), wy + o(2)], W['wood_dark'])
    fl(draw, [(wx, wy), (wx - o(5), wy - o(6))], W['metal'], width=2)
    fe(draw, [wx - o(7), wy - o(8), wx - o(3), wy - o(4)], W['wood_med'])


# ============================================================
# Composite
# ============================================================
def make_ballista_frame(pawn_frame, team, arm_angle=0, has_bolt=True,
                        string_pull=0, recoil=0, pawn_dx=0, pawn_dy=0):
    """Machine-only ballista frame — pawn is rendered by sprite_unit_visual.gd
    overlay at runtime. pawn_frame arg kept for API compatibility but ignored."""
    bx, by = 108, 108

    weapon = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    wd = ImageDraw.Draw(weapon)
    fe(wd, [bx - o(30) + o(recoil), by + o(22),
            bx + o(30) + o(recoil), by + o(30)], SHADOW)
    draw_ballista_weapon(wd, bx, by, team, arm_angle, has_bolt, string_pull, recoil)

    weapon_outline = make_outline(weapon, WOOD['outline'], 2)

    result = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    result = Image.alpha_composite(result, weapon_outline)
    result = Image.alpha_composite(result, weapon)
    return result


# ============================================================
# Animations — all use Pawn_Interact Hammer
# ============================================================
def make_idle(pawn_frames, team):
    """Idle: loaded ballista, pawn with hammer. Cycle 3 hammer frames over 8."""
    results = []
    n = len(pawn_frames)
    for i in range(8):
        pf = pawn_frames[i % n]
        results.append(make_ballista_frame(pf, team, arm_angle=0, has_bolt=True))
    return results


def make_run(pawn_frames, team):
    """Run: pawn pushes ballista with hammer. 6 frames."""
    results = []
    n = len(pawn_frames)
    bob = [0, -1, -1, 0, 1, 1]
    for i in range(6):
        pf = pawn_frames[i % n]
        results.append(make_ballista_frame(
            pf, team, arm_angle=0, has_bolt=True,
            pawn_dx=bob[i], pawn_dy=bob[i]))
    return results


def make_attack(pawn_frames, team):
    """Attack: full coiling fire sequence. 8 frames.

    Shows the arms progressively flexing and the bowstring pulling back
    (winding / coiling) before the snap release — this was missing in the
    previous 6-frame sequence which jumped from relaxed to fired in one
    step. The user explicitly asked to see the coiling action.

    Sequence:
        0: REST     — arms spread, string relaxed, bolt loaded
        1: WIND_1   — arms begin to flex, string starts pulling back
        2: WIND_2   — arms mid-flex, string halfway
        3: COCKED   — arms maximally flexed, string fully drawn back
        4: AIM      — held cocked, pawn sighting the shot
        5: FIRE     — arms snap back to spread, string snaps forward,
                       bolt GONE (flying toward target), machine recoils
        6: RECOIL   — arms settling, machine still recoiled
        7: RELOAD   — arms at rest, bolt back in slot
    """
    n = len(pawn_frames)
    params = [
        # 0 REST
        dict(arm_angle=0, has_bolt=True,  string_pull=0, recoil=0,  pawn_dx=0,  pawn_dy=0),
        # 1 WIND_1 — pawn cranks, arms flex slightly, string taut
        dict(arm_angle=1, has_bolt=True,  string_pull=1, recoil=0,  pawn_dx=-1, pawn_dy=0),
        # 2 WIND_2 — arms flex more, string halfway back
        dict(arm_angle=1, has_bolt=True,  string_pull=2, recoil=0,  pawn_dx=-2, pawn_dy=0),
        # 3 COCKED — arms fully flexed inward, string fully drawn
        dict(arm_angle=2, has_bolt=True,  string_pull=3, recoil=0,  pawn_dx=-2, pawn_dy=-1),
        # 4 AIM — held cocked briefly
        dict(arm_angle=2, has_bolt=True,  string_pull=3, recoil=0,  pawn_dx=-1, pawn_dy=-1),
        # 5 FIRE — SNAP! arms released, string snaps forward, bolt flies
        dict(arm_angle=0, has_bolt=False, string_pull=0, recoil=-4, pawn_dx=1,  pawn_dy=1),
        # 6 RECOIL — machine still pushed back, arms vibrating
        dict(arm_angle=0, has_bolt=False, string_pull=0, recoil=-2, pawn_dx=2,  pawn_dy=1),
        # 7 RELOAD — bolt slotted back, machine settles
        dict(arm_angle=0, has_bolt=True,  string_pull=0, recoil=0,  pawn_dx=0,  pawn_dy=0),
    ]
    return [make_ballista_frame(pawn_frames[i % n], team, **p)
            for i, p in enumerate(params)]


def make_guard(pawn_frames, team):
    """Guard: pawn hunkers behind. 6 frames."""
    n = len(pawn_frames)
    results = []
    for i in range(6):
        pf = pawn_frames[i % n]
        results.append(make_ballista_frame(
            pf, team, arm_angle=0, has_bolt=True,
            pawn_dx=-4, pawn_dy=3 + i // 2))
    return results


# ============================================================
# Output
# ============================================================
def assemble_strip(frames):
    strip = Image.new('RGBA', (F * len(frames), F), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (F * i, 0))
    return strip


def draw_clean_bolt(out_path):
    """Generate the ballista bolt projectile by upscaling the archer's arrow.

    User feedback: previous procedural bolt rendered as a HOLLOW outline
    because the final make_outline() call replaced the filled image with
    only its dilated edge ring. The bolt should look like the archer/
    gryphon arrow but 2× bigger (it's a siege bolt — same shape, larger
    scale). Reusing the Tiny Swords arrow guarantees visual consistency
    with other ranged units.

    Source: castle_clash/assets/sprites/units/{team}_archer/Arrow.png
    Output: 128×128 (2× the 64×64 source) per ballista folder.
    """
    # The output path tells us which team folder we're writing to
    team_dir = os.path.dirname(out_path)
    folder_name = os.path.basename(team_dir)  # blue_ballista or red_ballista
    team = "blue" if folder_name.startswith("blue") else "red"
    arrow_path = os.path.join(
        os.path.dirname(team_dir), f"{team}_archer", "Arrow.png"
    )
    if not os.path.exists(arrow_path):
        print(f"  WARN: archer arrow not found at {arrow_path}")
        return
    arrow = Image.open(arrow_path).convert("RGBA")
    upscaled = arrow.resize(
        (arrow.width * 4, arrow.height * 4), Image.NEAREST
    )
    upscaled.save(out_path)
    print(f"  Bolt.png ({upscaled.width}x{upscaled.height}, "
          f"4× scaled from {team}_archer/Arrow.png)")


def generate_team(team_colors, team_name, pawn_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # Use Pawn_Interact Hammer for ALL animations (ignored in machine-only mode)
    hammer_frames = load_frames(os.path.join(pawn_dir, "Pawn_Interact Hammer.png"))

    anims = {
        'Ballista_Idle': make_idle(hammer_frames, team_colors),
        'Ballista_Run': make_run(hammer_frames, team_colors),
        'Ballista_Attack1': make_attack(hammer_frames, team_colors),
        'Ballista_Guard': make_guard(hammer_frames, team_colors),
    }

    for name, frames in anims.items():
        strip = assemble_strip(frames)
        path = os.path.join(out_dir, f"{name}.png")
        strip.save(path)
        print(f"  {team_name}: {name}.png  "
              f"({strip.width}x{strip.height}, {len(frames)} frames)")

    # Clean standalone Bolt projectile sprite
    draw_clean_bolt(os.path.join(out_dir, "Bolt.png"))


def main():
    base = "castle_clash/assets/sprites/units"
    print("Generating Tiny Swords style ballista sprites (1.5x)...\n")
    generate_team(BLUE_TEAM, "Blue (Kingdom)",
                  os.path.join(base, "blue_pawn"), os.path.join(base, "blue_ballista"))
    generate_team(RED_TEAM, "Red (Horde)",
                  os.path.join(base, "red_pawn"), os.path.join(base, "red_ballista"))
    print(f"\nDone! → {base}/blue_ballista/  &  {base}/red_ballista/")


if __name__ == "__main__":
    main()
