#!/usr/bin/env python3
"""Generate gryphon rider sprites: real Tiny Swords archer mounted on a gryphon.

Loads the actual archer sprite frames and composites gryphon mount elements
(wings, head, talons, tail) around them. Wings are the star visual feature.
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math
import os

# ============================================================
# PALETTE — extracted from actual Tiny Swords sprites
# ============================================================
BLUE = {
    'outline':     (22, 28, 46),
    'outline_mid': (65, 66, 91),
    'armor':       (72, 88, 132),
    'accent':      (70, 151, 172),
    'wing_dark':   (104, 140, 138),
    'wing_mid':    (156, 190, 170),
    'wing_light':  (212, 237, 194),
    'cream':       (239, 225, 171),
    'tan':         (200, 168, 118),
    'white':       (255, 255, 255),
    'beak':        (230, 190, 60),      # golden yellow beak
    'beak_light':  (245, 215, 100),     # beak highlight
    'beak_tip':    (180, 140, 40),      # beak tip darker
}

RED = {
    'outline':     (22, 28, 46),
    'outline_mid': (65, 66, 91),
    'armor':       (146, 65, 89),
    'accent':      (231, 97, 97),
    'wing_dark':   (148, 116, 103),
    'wing_mid':    (207, 156, 113),
    'wing_light':  (232, 206, 145),
    'cream':       (239, 225, 171),
    'tan':         (200, 168, 118),
    'white':       (255, 255, 255),
    'beak':        (230, 190, 60),
    'beak_light':  (245, 215, 100),
    'beak_tip':    (180, 140, 40),
}

F = 192  # frame size
SHADOW = (22, 28, 46, 50)

# Source asset: Angel Statue wings (cropped + body masked)
ANGEL_STATUE_PATH = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/"
    "GandalfHardcore FREE Platformer Assets/Angel Statue.png"
)

# Source asset: Birds.png — 4x4 grid of 48x48 bird sprites.
# Cell (2, 1) is a blue/white dove in full flight pose — perfect as a
# gryphon body base. We overlay angel wings on top as the prominent
# magical wing feature.
BIRDS_PATH = os.path.expanduser(
    "~/Downloads/Dowloaded_Game_Assets/Birds.png"
)
BIRD_CELL_SIZE = 48
BIRD_CELL_ROW = 2
BIRD_CELL_COL = 1
BIRD_SCALE = 3  # upscale from 48px cell → ~144px bird body

# Cached sprites (lazy-loaded)
_wing_cache = {}
_bird_cache = {}


def _load_angel_wings():
    """Extract clean wing sprites from Angel Statue.png.

    Returns (left_wing, right_wing) as RGBA Images, already scaled to
    gryphon size (~48px each) with body pixels masked out.
    """
    if 'left' in _wing_cache:
        return _wing_cache['left'], _wing_cache['right']

    img = Image.open(ANGEL_STATUE_PATH).convert("RGBA")
    arr = np.array(img).copy()
    # Mask out body center (columns 29-35), below wings (rows 30+),
    # and outside content area (cols 0-8 and 57+)
    arr[0:30, 29:36] = [0, 0, 0, 0]
    arr[0:30, 0:9] = [0, 0, 0, 0]
    arr[0:30, 57:] = [0, 0, 0, 0]
    arr[30:, :] = [0, 0, 0, 0]
    wings_only = Image.fromarray(arr)

    # Trim to content bbox
    a = np.array(wings_only)[:, :, 3]
    rows = np.any(a > 0, axis=1)
    cols = np.any(a > 0, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    wings_trimmed = wings_only.crop((cmin, rmin, cmax + 1, rmax + 1))

    # Split in half
    w = wings_trimmed.width // 2
    left = wings_trimmed.crop((0, 0, w, wings_trimmed.height))
    right = wings_trimmed.crop((w, 0, wings_trimmed.width, wings_trimmed.height))

    # Scale up ~2.5x for prominent-but-not-overwhelming wings
    scale = 2.5
    left = left.resize((int(left.width * scale), int(left.height * scale)), Image.NEAREST)
    right = right.resize((int(right.width * scale), int(right.height * scale)), Image.NEAREST)

    _wing_cache['left'] = left
    _wing_cache['right'] = right
    return left, right


def _load_bird_sprite():
    """Extract the gryphon body bird from Birds.png (cell 2,1 = flying dove).

    Crops the 48x48 cell, masks the ground-shadow line at the bottom, trims
    to content bbox, and upscales NEAREST. Returns an RGBA Image.
    """
    if 'sprite' in _bird_cache:
        return _bird_cache['sprite']

    img = Image.open(BIRDS_PATH).convert("RGBA")
    gs = BIRD_CELL_SIZE
    cell = img.crop((
        BIRD_CELL_COL * gs, BIRD_CELL_ROW * gs,
        (BIRD_CELL_COL + 1) * gs, (BIRD_CELL_ROW + 1) * gs,
    ))

    # Mask out ground-shadow horizontal line (pure black pixels at bottom
    # rows that aren't attached to the bird body).
    arr = np.array(cell).copy()
    # Everything below row 40 is shadow/ground line
    arr[40:, :] = [0, 0, 0, 0]
    cleaned = Image.fromarray(arr)

    # Trim to content bbox
    a = np.array(cleaned)[:, :, 3]
    rows = np.any(a > 0, axis=1)
    cols = np.any(a > 0, axis=0)
    if not rows.any() or not cols.any():
        raise RuntimeError("Bird cell had no visible pixels")
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    trimmed = cleaned.crop((cmin, rmin, cmax + 1, rmax + 1))

    # Upscale NEAREST so pixel art stays crisp
    new_w = trimmed.width * BIRD_SCALE
    new_h = trimmed.height * BIRD_SCALE
    scaled = trimmed.resize((new_w, new_h), Image.NEAREST)

    _bird_cache['sprite'] = scaled
    return scaled


def _hsv_recolor(img, target_rgb):
    """Strong team recolor: replace hue+saturation of every opaque pixel
    with the target color's hue/saturation while preserving per-pixel
    value (brightness). This guarantees the bird reads as one solid
    team color (no pink/salmon bleed-through) while keeping pixel-art
    shading/outlines intact.
    """
    from colorsys import rgb_to_hsv, hsv_to_rgb
    arr = np.array(img, dtype=np.uint8)
    alpha = arr[:, :, 3]
    th, ts, _ = rgb_to_hsv(
        target_rgb[0] / 255.0,
        target_rgb[1] / 255.0,
        target_rgb[2] / 255.0,
    )
    out = arr.copy()
    h, w, _ = arr.shape
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            r, g, b = arr[y, x, 0] / 255.0, arr[y, x, 1] / 255.0, arr[y, x, 2] / 255.0
            _, _, v = rgb_to_hsv(r, g, b)
            # Boost value a touch so team color pops even on dim source
            v = min(1.0, v * 1.05)
            nr, ng, nb = hsv_to_rgb(th, ts, v)
            out[y, x, 0] = int(nr * 255)
            out[y, x, 1] = int(ng * 255)
            out[y, x, 2] = int(nb * 255)
    return Image.fromarray(out)


def paste_bird_body(canvas, cx, cy, pal, is_red=False):
    """Paste the Birds.png dove as the gryphon body base.

    (cx, cy) is where the center-of-body should land in the 192x192 frame.
    Both Kingdom and Horde variants are HSV-recolored so the bird reads
    unambiguously as the correct faction color — the native dove has
    pink/salmon highlights that would otherwise pollute both teams.
    """
    bird = _load_bird_sprite().copy()
    # Pure HSV recolor — replaces hue/saturation with team color while
    # preserving per-pixel value (brightness) so shading/outlines stay.
    # Using `accent` gives a vivid, saturated team tone that reads
    # clearly at game scale; `armor` desaturated to muddy purple.
    target = pal['accent']
    bird = _hsv_recolor(bird, target)
    px = cx - bird.width // 2
    py = cy - bird.height // 2
    canvas.alpha_composite(bird, (px, py))


def _tint_image(img, color, strength=0.5):
    """Recolor an image toward a target color while preserving luminance."""
    arr = np.array(img, dtype=np.float32)
    alpha = arr[:, :, 3]
    mask = alpha > 0
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    for c in range(3):
        tint_scaled = color[c] * (lum / 140.0)
        blended = arr[:, :, c] * (1 - strength) + tint_scaled * strength
        arr[:, :, c] = np.where(mask, np.clip(blended, 0, 255), arr[:, :, c])
    return Image.fromarray(arr.astype(np.uint8))


# ============================================================
# Drawing helpers
# ============================================================
def fp(draw, pts, color):
    """Filled polygon."""
    draw.polygon(pts, fill=color + (255,) if len(color) == 3 else color)


def fe(draw, bbox, color):
    """Filled ellipse."""
    draw.ellipse(bbox, fill=color + (255,) if len(color) == 3 else color)


def epts(cx, cy, rx, ry, n=24, a0=0, a1=360):
    """Ellipse arc points."""
    return [(round(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / max(n - 1, 1)))),
             round(cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / max(n - 1, 1)))))
            for i in range(n)]


def make_outline(img, color, thickness=2):
    """Create outline layer by dilating alpha mask."""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    dilated = np.array(Image.fromarray(alpha).filter(
        ImageFilter.MaxFilter(thickness * 2 + 1)))
    mask = (dilated > 128) & (alpha <= 128)
    out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    out[mask] = [*color, 255]
    return Image.fromarray(out)


# ============================================================
# Load archer frames from the actual Tiny Swords PNGs
# ============================================================
def load_frames(path):
    """Load a sprite strip and return list of RGBA frame Images."""
    strip = Image.open(path).convert("RGBA")
    h = strip.height
    n = strip.width // h
    return [strip.crop((i * h, 0, (i + 1) * h, h)) for i in range(n)]


def shift_frame(frame, dx, dy):
    """Shift frame content by (dx, dy) pixels.

    Uses alpha_composite (not paste+mask) so semi-transparent pixels
    (shadows, soft AA edges) are preserved. Paste-with-mask squares the
    alpha channel, fading out the archer's shadow row below threshold.
    """
    layer = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    layer.paste(frame, (dx, dy))
    return layer


# ============================================================
# Gryphon mount drawing (wings, head, talons, tail)
# ============================================================
def paste_angel_wing(canvas, ox, oy, pal, spread, flip=False):
    """Paste an angel-statue wing at a given flap state.

    Replaces the old procedural draw_wing. The angel wings are prominent
    stone-carved feathered wings that read clearly at game scale.

    spread: 0..4 — 0=deep downstroke, 2=level, 4=full upstroke
    flip: True = back wing (slightly smaller, behind gryphon body)
    """
    left_wing, right_wing = _load_angel_wings()
    # Use right wing (viewer's right from gryphon POV = forward wing)
    wing = right_wing.copy()

    # Rotation angle by flap state — negative tilts the wing down, positive up
    angles = {
        0: -25,   # deep downstroke (wing below body)
        1: -10,   # mid down
        2: 0,     # level (gliding)
        3: 20,    # mid up
        4: 40,    # full upstroke (top of flap)
    }
    angle = angles.get(spread, 0)
    wing = wing.rotate(angle, resample=Image.NEAREST, expand=True)

    # Back wing is smaller and dimmer
    if flip:
        new_w = max(1, int(wing.width * 0.75))
        new_h = max(1, int(wing.height * 0.75))
        wing = wing.resize((new_w, new_h), Image.NEAREST)

    # Team-color tint on the wings — use wing_mid as target color
    wing = _tint_image(wing, pal['wing_mid'], strength=0.7)

    # Position: wing anchors at the gryphon's shoulder, extending out-and-up
    # Shift the wing so its pivot (root) is near (ox, oy)
    px = ox - 6
    py = oy - wing.height + 18

    canvas.alpha_composite(wing, (px, py))
    return


def draw_wing(draw, ox, oy, pal, spread, flip=False):
    """DEPRECATED — legacy procedural wing, kept so existing callers don't error.
    The new compositor uses paste_angel_wing() directly on a canvas.
    """
    states = {
        0: (-18, 36, -9, 18),       # folded tight (wings tucked down)
        1: (-42, 48, -24, 30),      # deep downstroke
        2: (-72, 6, -39, 0),        # level (gliding)
        3: (-66, -42, -36, -24),    # angled up
        4: (-54, -72, -30, -42),    # full up (top of flap — very high)
    }
    tdx, tdy, mdx, mdy = states.get(spread, states[2])

    if flip:
        tdx = int(tdx * 0.6)
        tdy = int(tdy * 0.7)
        mdx = int(mdx * 0.6)
        mdy = int(mdy * 0.7)

    tip_x, tip_y = ox + tdx, oy + tdy

    # Wing direction vectors
    wing_angle = math.atan2(tdy, tdx)
    perp_angle = wing_angle + math.pi / 2  # points toward trailing edge
    pw = 15 if not flip else 10  # perpendicular half-width (1.5x)

    n_seg = 12
    lead = []   # leading edge: smooth, straight (top of wing)
    trail = []  # trailing edge: scalloped feathers (bottom of wing)

    for i in range(n_seg + 1):
        t = i / n_seg
        # Position along wing spine
        sx = ox + tdx * t
        sy = oy + tdy * t

        # Width envelope: widens to ~40%, then tapers to tip
        width = pw * (0.5 + 0.8 * math.sin(t * math.pi)) * (1 - t * 0.25)

        # --- LEADING EDGE (top): clean smooth line ---
        lead_w = width * 0.3
        ldx = math.cos(perp_angle) * (-lead_w)
        ldy = math.sin(perp_angle) * (-lead_w)
        lead.append((round(sx + ldx), round(sy + ldy)))

        # --- TRAILING EDGE (bottom): scalloped feather tips ---
        trail_w = width * 0.7
        # Scallop bumps: amplitude grows toward tip (longer flight feathers)
        n_bumps = 5
        scallop_amp = 4.0 * (0.1 + t * 0.9) * (1 if not flip else 0.7)
        scallop = abs(math.sin(t * n_bumps * math.pi)) * scallop_amp
        total_trail = trail_w + scallop
        tdx2 = math.cos(perp_angle) * total_trail
        tdy2 = math.sin(perp_angle) * total_trail
        trail.insert(0, (round(sx + tdx2), round(sy + tdy2)))

    wing_pts = lead + trail

    # --- Fill: base color ---
    base_color = pal['wing_dark'] if flip else pal['wing_mid']
    fp(draw, wing_pts, base_color)

    # --- Feather layer rows (overlapping bands from root to tip) ---
    n_rows = 5 if abs(tdx) > 30 else 3
    for j in range(n_rows):
        t_start = j / n_rows
        t_end = (j + 0.7) / n_rows
        # Build a feather-row polygon along the trailing edge
        row_pts = []
        for k in range(6):
            t = t_start + (t_end - t_start) * k / 5
            if t > 1:
                break
            sx = ox + tdx * t
            sy = oy + tdy * t
            width = pw * (0.5 + 0.8 * math.sin(t * math.pi)) * (1 - t * 0.25)
            # Inner edge of feather row (toward spine)
            inner = width * 0.15
            idx = math.cos(perp_angle) * inner
            idy = math.sin(perp_angle) * inner
            row_pts.append((round(sx + idx), round(sy + idy)))
        # Reverse pass for outer edge
        for k in range(5, -1, -1):
            t = t_start + (t_end - t_start) * k / 5
            if t > 1:
                continue
            sx = ox + tdx * t
            sy = oy + tdy * t
            width = pw * (0.5 + 0.8 * math.sin(t * math.pi)) * (1 - t * 0.25)
            outer = width * 0.55
            scallop = abs(math.sin(t * n_bumps * math.pi)) * 3
            odx = math.cos(perp_angle) * (outer + scallop)
            ody = math.sin(perp_angle) * (outer + scallop)
            row_pts.append((round(sx + odx), round(sy + ody)))
        if len(row_pts) >= 3:
            color = pal['wing_light'] if j % 2 == 0 else pal['wing_mid']
            if flip:
                color = pal['wing_mid'] if j % 2 == 0 else pal['wing_dark']
            fp(draw, row_pts, color)

    # --- Leading edge highlight (clean line) ---
    for i in range(1, min(6, len(lead))):
        lx, ly = lead[i]
        fe(draw, [lx - 1, ly - 1, lx + 2, ly + 1], pal['wing_light'])


def draw_gryphon_head(draw, hx, hy, pal, beak_open=0):
    """Draw small gryphon head with beak, eye, tiny crest."""
    # Head (small round eagle head)
    head_pts = epts(hx, hy, 11, 10, 28)
    fp(draw, head_pts, pal['cream'])

    # Head shadow (lower)
    fe(draw, [hx - 9, hy + 1, hx + 8, hy + 10], pal['tan'])

    # Forehead highlight
    fe(draw, [hx - 4, hy - 9, hx + 6, hy - 3], pal['cream'])

    # Beak (yellow/golden)
    if beak_open == 0:
        bk = [(hx + 9, hy - 2), (hx + 16, hy + 1), (hx + 17, hy + 4),
              (hx + 14, hy + 5), (hx + 9, hy + 4)]
        fp(draw, bk, pal['beak'])
        # Beak upper highlight
        fp(draw, [(hx+9,hy-2),(hx+14,hy),(hx+12,hy+2),(hx+9,hy+1)], pal['beak_light'])
        # Beak tip
        fp(draw, [(hx+14,hy+1),(hx+17,hy+4),(hx+14,hy+5),(hx+12,hy+3)],
           pal['beak_tip'])
        # Nostril
        fe(draw, [hx + 12, hy + 1, hx + 14, hy + 3], pal['outline_mid'])
    else:
        # Open beak (yellow)
        fp(draw, [(hx+9,hy-4),(hx+17,hy-1),(hx+15,hy+1),(hx+9,hy)], pal['beak'])
        fp(draw, [(hx+9,hy-4),(hx+14,hy-2),(hx+12,hy),(hx+9,hy-1)], pal['beak_light'])
        fp(draw, [(hx+14,hy-1),(hx+17,hy-1),(hx+15,hy+1),(hx+13,hy)],
           pal['beak_tip'])
        fp(draw, [(hx+9,hy+3),(hx+15,hy+4),(hx+13,hy+7),(hx+9,hy+6)], pal['beak'])
        fp(draw, [(hx+9,hy),(hx+15,hy+1),(hx+15,hy+4),(hx+9,hy+3)], pal['outline'])

    # Eye
    ex, ey = hx + 5, hy - 3
    fe(draw, [ex - 4, ey - 3, ex + 4, ey + 3], pal['white'])
    fe(draw, [ex, ey - 3, ex + 4, ey + 3], pal['outline'])
    fe(draw, [ex + 1, ey - 2, ex + 3, ey], pal['white'])

    # Tiny crest (2 small feathers)
    fp(draw, [(hx - 4, hy - 8), (hx - 3, hy - 16), (hx, hy - 14),
              (hx + 1, hy - 8)], pal['accent'])
    fp(draw, [(hx - 8, hy - 6), (hx - 7, hy - 12), (hx - 4, hy - 11),
              (hx - 4, hy - 6)], pal['armor'])


def draw_talons(draw, tx, ty, pal, phase=0):
    """Draw two small gryphon talons/feet."""
    offsets = [(0, 0), (0, -1), (1, -1), (1, 0), (0, 1), (0, 0)]
    dx, dy = offsets[phase % 6]

    for i, xoff in enumerate([0, 10]):
        x = tx + xoff + dx * (1 if i == 0 else -1)
        y = ty + dy
        # Leg stub
        fp(draw, [(x, y - 6), (x + 3, y - 6), (x + 4, y), (x - 1, y)], pal['tan'])
        # Three toes
        fp(draw, [(x - 2, y), (x - 3, y + 3), (x, y + 2)], pal['outline_mid'])
        fp(draw, [(x + 1, y), (x + 1, y + 4), (x + 3, y + 2)], pal['outline_mid'])
        fp(draw, [(x + 3, y), (x + 5, y + 3), (x + 5, y + 1)], pal['outline_mid'])


def draw_tail(draw, tx, ty, pal, wag=0):
    """Draw gryphon tail with tuft."""
    tip_x = tx - 16 + wag
    tip_y = ty + 8
    tail = [
        (tx, ty), (tx - 6, ty + 2), (tx - 10 + wag, ty + 5),
        (tip_x, tip_y), (tip_x + 4, tip_y + 2),
        (tx - 8 + wag, ty + 7), (tx - 4, ty + 4), (tx, ty + 2),
    ]
    fp(draw, tail, pal['tan'])
    # Tuft
    fe(draw, [tip_x - 4, tip_y - 3, tip_x + 4, tip_y + 5], pal['accent'])
    fe(draw, [tip_x - 2, tip_y - 1, tip_x + 2, tip_y + 2], pal['wing_light'])


def draw_mount_body(draw, bx, by, pal):
    """Draw the visible portion of the gryphon body (mostly hidden under rider)."""
    # Small visible body area (rounded, below/around rider)
    body = epts(bx, by, 16, 10, 24)
    fp(draw, body, pal['cream'])
    # Body shadow
    fe(draw, [bx - 14, by + 2, bx + 14, by + 10], pal['tan'])
    # Armor strap (horizontal band)
    fp(draw, [(bx - 12, by - 3), (bx + 14, by - 3),
              (bx + 14, by + 1), (bx - 12, by + 1)], pal['armor'])
    fp(draw, [(bx - 10, by - 1), (bx + 12, by - 1),
              (bx + 12, by + 1), (bx - 10, by + 1)], pal['accent'])


# ============================================================
# Composite one mounted gryphon frame
# ============================================================
def make_mounted_frame(archer_frame, pal, wing_state=2,
                       bob=0, head_bob=0, beak=0, leg=0, twag=0):
    """
    Composite archer on gryphon mount.

    archer_frame: RGBA Image of one archer animation frame
    wing_state: 0-4 wing spread
    bob: vertical bob for mount
    """
    # Shift archer up to make room for mount. Calibrated so idle composite
    # content_h ≈ 158px (sprite_unit_visual.gd expects this for
    # target_content=54, giving archer in-game size == standalone archer).
    # Standalone archer content_h=88, so archer_h / composite_h = 88/158
    # = 55.7%, matching 30/54 ratio for rider-size parity.
    RIDER_SHIFT_Y = -27
    rider = shift_frame(archer_frame, 0, RIDER_SHIFT_Y)

    # Mount element positions (relative to frame center)
    # Archer content now at rows 21-108 (native size 88)
    mount_cx = 92
    mount_cy = 128 + bob  # bird body center (lowered to extend composite down)
    is_red = (pal is RED)

    # Wings anchor on the BIRD's shoulders/back, NOT on the rider.
    # Bird center is at (mount_cx+4, mount_cy+4); its upper back is
    # about 14px above the center. Anchoring the wings there makes them
    # visibly emerge from the bird's body, which is what's doing the
    # flying — the rider is just a passenger.
    bird_cx = mount_cx + 4
    bird_back_y = mount_cy - 10  # bird shoulder/upper-back level

    # --- MOUNT LAYER (bird + wings, all below rider) ---
    mount = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    md = ImageDraw.Draw(mount)

    # Shadow on the ground
    fe(md, [mount_cx - 34, mount_cy + 26, mount_cx + 34, mount_cy + 34], SHADOW)

    # Back wing — angel wing, behind bird body for depth
    _paste_back_wing(mount, bird_cx - 16, bird_back_y + 16, pal, wing_state)

    # Real bird sprite as the gryphon body (replaces procedural
    # body/head/talons/tail). The bird faces right with wings up.
    paste_bird_body(mount, bird_cx, mount_cy + 4, pal, is_red=is_red)

    # Front wing — angel wing on the right/forward side, attached to
    # the bird's upper back (not the rider's shoulders).
    paste_angel_wing(mount, bird_cx, bird_back_y + 16, pal, wing_state, flip=False)

    # Kept for API compatibility with the outline-compositing path;
    # bird sprite has baked-in outlines so no dilated pass needed.
    back_outline = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    front_outline = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    back = mount
    front = Image.new('RGBA', (F, F), (0, 0, 0, 0))

    # --- COMPOSITE ---
    # CRITICAL: the Tiny Swords base character (rider) is the TOP layer.
    # Mount (bird + angel wings) goes behind, so the rider is always
    # the most visually prominent element. This matches the team-wide
    # rule: "Tiny Swords base characters must always sit on top."
    result = Image.new('RGBA', (F, F), (0, 0, 0, 0))
    result = Image.alpha_composite(result, back_outline)
    result = Image.alpha_composite(result, back)     # mount (bird + wings)
    result = Image.alpha_composite(result, front_outline)
    result = Image.alpha_composite(result, front)    # (currently empty)
    result = Image.alpha_composite(result, rider)    # TOP — always visible

    return result


def _paste_back_wing(canvas, ox, oy, pal, spread):
    """Paste the back (mirrored) angel wing — slightly smaller, behind body."""
    left_wing, _ = _load_angel_wings()
    wing = left_wing.copy()
    angles = {0: -25, 1: -10, 2: 0, 3: 20, 4: 40}
    angle = -angles.get(spread, 0)  # mirror angle for back wing
    wing = wing.rotate(angle, resample=Image.NEAREST, expand=True)
    # Back wing slightly smaller
    new_w = max(1, int(wing.width * 0.75))
    new_h = max(1, int(wing.height * 0.75))
    wing = wing.resize((new_w, new_h), Image.NEAREST)
    # Darker tint for the back wing (depth)
    wing = _tint_image(wing, pal['wing_dark'], strength=0.7)
    px = ox - wing.width + 10
    py = oy - wing.height + 18
    canvas.alpha_composite(wing, (px, py))


# ============================================================
# Animation sequences
# ============================================================
def make_gryphon_idle(archer_frames, pal):
    """Idle: gentle wing movement, bob. 6 frames matching archer idle."""
    results = []
    wing_cycle = [2, 2, 3, 3, 2, 2]  # gentle up-down
    bob_cycle = [0, -1, -1, 0, 1, 1]
    for i, af in enumerate(archer_frames):
        results.append(make_mounted_frame(
            af, pal,
            wing_state=wing_cycle[i % 6],
            bob=bob_cycle[i % 6],
            head_bob=bob_cycle[i % 6] // 2,
            twag=(i % 3) - 1,
        ))
    return results


def make_gryphon_run(archer_frames, pal):
    """Run/fly: full wing flap cycle. Pad archer 4 frames to 6."""
    # Extend 4 archer run frames to 6: [0,1,2,3,2,1]
    if len(archer_frames) == 4:
        af = [archer_frames[i] for i in [0, 1, 2, 3, 2, 1]]
    else:
        af = archer_frames

    wing_cycle = [4, 3, 2, 1, 0, 1]   # full flap: up→down→up
    bob_cycle = [0, -2, -3, -2, 0, 1]
    results = []
    for i in range(6):
        results.append(make_mounted_frame(
            af[i], pal,
            wing_state=wing_cycle[i],
            bob=bob_cycle[i],
            head_bob=bob_cycle[i] // 2,
            leg=i,
            twag=bob_cycle[i],
        ))
    return results


def make_gryphon_attack(archer_frames, pal):
    """Attack: archer shoots while wings spread. Uses Archer_Shoot frames."""
    n = len(archer_frames)
    results = []
    for i, af in enumerate(archer_frames):
        t = i / max(n - 1, 1)
        # Wings spread during attack, peak at mid-point
        if t < 0.3:
            ws = 3  # rising
        elif t < 0.6:
            ws = 4  # full spread (dramatic moment)
        else:
            ws = 3  # settling

        beak = 1 if 0.2 < t < 0.7 else 0
        bob = round(math.sin(t * math.pi) * -2)
        results.append(make_mounted_frame(
            af, pal,
            wing_state=ws,
            bob=bob,
            head_bob=bob,
            beak=beak,
        ))
    return results


def make_gryphon_guard(archer_frames, pal):
    """Guard/death: wings fold in protectively. Uses Archer_Idle frames."""
    n = len(archer_frames)
    results = []
    wing_cycle = [2, 1, 0, 0, 0, 0]
    bob_cycle = [0, 1, 2, 3, 3, 3]
    for i, af in enumerate(archer_frames):
        results.append(make_mounted_frame(
            af, pal,
            wing_state=wing_cycle[i % 6],
            bob=bob_cycle[i % 6],
            head_bob=bob_cycle[i % 6],
        ))
    return results


# ============================================================
# Strip assembly & output
# ============================================================
def assemble_strip(frames):
    strip = Image.new('RGBA', (F * len(frames), F), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (F * i, 0))
    return strip


def generate_team(team_pal, team_name, archer_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # Load archer animations
    idle_frames = load_frames(os.path.join(archer_dir, "Archer_Idle.png"))
    run_frames = load_frames(os.path.join(archer_dir, "Archer_Run.png"))
    shoot_frames = load_frames(os.path.join(archer_dir, "Archer_Shoot.png"))

    anims = {
        'Gryphon_Idle': make_gryphon_idle(idle_frames, team_pal),
        'Gryphon_Run': make_gryphon_run(run_frames, team_pal),
        'Gryphon_Attack1': make_gryphon_attack(shoot_frames, team_pal),
        'Gryphon_Guard': make_gryphon_guard(idle_frames, team_pal),
    }

    for name, frames in anims.items():
        strip = assemble_strip(frames)
        path = os.path.join(out_dir, f"{name}.png")
        strip.save(path)
        print(f"  {team_name}: {name}.png  "
              f"({strip.width}x{strip.height}, {len(frames)} frames)")


def main():
    base = "castle_clash/assets/sprites/units"
    print("Generating gryphon rider sprites (archer + mount)...\n")

    generate_team(
        BLUE, "Blue (Kingdom)",
        os.path.join(base, "blue_archer"),
        os.path.join(base, "blue_gryphon"),
    )
    generate_team(
        RED, "Red (Horde)",
        os.path.join(base, "red_archer"),
        os.path.join(base, "red_gryphon"),
    )

    print(f"\nDone! → {base}/blue_gryphon/  &  {base}/red_gryphon/")


if __name__ == "__main__":
    main()
