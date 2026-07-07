# Feature Spec: Fort Guardian-Level Animation Smoothness + Kingdom Rush Battle Zone
> **Author**: A0 (Game Designer) | **Date**: 2026-04-05
> **References**: Fort Guardian (Xiaomo/Voodoo), Kingdom Rush (Ironhide)

---

## ROOT CAUSE: Why Our Units Feel Choppy

**The pipeline today:**
```
Simulation (10 TPS) → _sync_unit_positions() (60 FPS) → visual.position = new_pos
```

Problem: Position only changes every 100ms (simulation tick), but rendering runs at 60fps. Units hold position for ~6 frames, then snap to the new position. Walk animations play smoothly but the unit's world position **jumps**.

```
Frame 1-6:  position = (100, 500)  ← held for 100ms
Frame 7:    position = (115, 485)  ← 15px jump in one frame
Frame 8-12: position = (115, 485)  ← held for 100ms
```

**This is the #1 fix.** Everything else (bounce, hit-stop, decorations) is polish on top.

---

## FIX 1: Position Interpolation Between Ticks (A1 + A2, CRITICAL)

### The Solution
Store the **previous tick position** and **current tick position** for each entity. In `_sync_unit_positions()`, lerp between them based on how far we are between ticks.

### A1 (Game Dev) — Simulation Side
In `game_manager.gd`, expose an interpolation factor:
```gdscript
var tick_interpolation: float = 0.0  # 0.0 = at last tick, 1.0 = at next tick

func _process(delta: float) -> void:
    _tick_accumulator_msec += int(delta * 1000.0)
    while _tick_accumulator_msec >= TICK_DURATION_MSEC:
        _advance_simulation_tick()
        _tick_accumulator_msec -= TICK_DURATION_MSEC
    # Expose how far between ticks we are
    tick_interpolation = clampf(float(_tick_accumulator_msec) / float(TICK_DURATION_MSEC), 0.0, 1.0)
```

In `simulation.gd`, store previous position before moving:
```gdscript
# In _move_unit(), before changing position:
unit["prev_x"] = unit.x
unit["prev_y"] = unit.y
# Then move as normal...
```

### A2 (UI/UX) — Visual Side
In `_sync_unit_positions()`, interpolate:
```gdscript
func _sync_unit_positions() -> void:
    var t: float = GameManager.tick_interpolation
    for entity in GameManager.simulation.entities:
        var visual = _unit_visuals[entity.id]
        var prev_pos := Vector2(FP.to_float(entity.get("prev_x", entity.x)), FP.to_float(entity.get("prev_y", entity.y)))
        var curr_pos := Vector2(FP.to_float(entity.x), FP.to_float(entity.y))
        visual.position = prev_pos.lerp(curr_pos, t)  # SMOOTH!
        # ... rest of sync unchanged
```

**Result**: Units glide smoothly between tick positions. No more 100ms jumps. Position updates 60 times per second visually even though simulation only ticks 10 times.

**Critical**: This does NOT affect determinism. Simulation is unchanged. Only the visual representation interpolates.

---

## FIX 2: Walk Bounce (A2, QUICK WIN)

Add a subtle 2px vertical sinusoidal bounce synced to the walk cycle. This sells weight and momentum.

### sprite_unit_visual.gd
```gdscript
var _walk_phase: float = 0.0
var _walk_bounce_amplitude: float = 2.0  # pixels

func _process(delta: float) -> void:
    if _anim_state == 1:  # WALKING
        _walk_phase += delta * 10.0  # ~1.3 steps per second
        _sprite.offset.y = sin(_walk_phase * TAU) * _walk_bounce_amplitude
    else:
        _sprite.offset.y = 0.0
```

### unit_visual.gd (procedural)
Already has walk phase via `_walk_phase`. Just add body Y offset:
```gdscript
# In _draw(), during WALKING state, add to body_y:
var bounce_y: float = sin(_walk_phase) * 2.0
# Apply to body draw position
```

---

## FIX 3: Stagger Animation Phases (A2, QUICK WIN)

Units spawned from the same building shouldn't march in lockstep.

### At spawn time (game_arena.gd):
```gdscript
# When creating unit visual:
visual._walk_phase = randf() * TAU  # Random starting phase
# For sprite-based: offset the AnimatedSprite2D frame
visual._sprite.frame = randi() % visual._sprite.sprite_frames.get_frame_count("walk")
```

---

## FIX 4: Hit-Stop on Attack Impact (A2, MEDIUM)

When an attack lands, freeze both attacker and target for 2 frames (~33ms). Subtle but massively impactful for "crunch."

### Implementation:
```gdscript
var _hitstop_timer: float = 0.0
const HITSTOP_DURATION: float = 0.033  # 2 frames at 60fps

func trigger_hitstop() -> void:
    _hitstop_timer = HITSTOP_DURATION

func _process(delta: float) -> void:
    if _hitstop_timer > 0:
        _hitstop_timer -= delta
        return  # Skip ALL animation updates — freeze in place
    # ... normal animation processing
```

Trigger hitstop on both attacker and target when `unit_attacked` event fires.

---

## FIX 5: Attack Timing Contrast (A2, MEDIUM)

Current attack animations have uniform timing. Fort Guardian uses:
- **Wind-up**: 40% of duration (slow, builds tension)
- **Strike**: 20% of duration (fast, impactful)
- **Recovery**: 40% of duration (medium, returns to idle)

### For sprite_unit_visual.gd:
Adjust the AnimatedSprite2D speed_scale during attack phases:
```gdscript
func play_attack() -> void:
    _sprite.speed_scale = 0.6   # Slow wind-up
    _sprite.play("attack")
    await get_tree().create_timer(attack_duration * 0.4).timeout
    _sprite.speed_scale = 2.0   # Fast strike
    await get_tree().create_timer(attack_duration * 0.2).timeout
    _sprite.speed_scale = 0.8   # Medium recovery
```

### For unit_visual.gd (procedural):
Already has good easing. Just emphasize the contrast:
- Wind-up: Use ease-in-out (slow start)
- Strike: Use linear or ease-in (snap forward)
- Recovery: Use ease-out (decelerate)

---

## FIX 6: Smooth Direction Changes (A2, SMALL)

Instead of instant sprite flip when changing direction, add a brief squash transition:

```gdscript
# Instead of instant flip_h toggle:
if new_facing != _current_facing:
    # Squash to 0 width over 0.05s, then flip, then expand back
    var tween = create_tween()
    tween.tween_property(_sprite, "scale:x", 0.0, 0.05)
    tween.tween_callback(func(): _sprite.flip_h = (new_facing < 0))
    tween.tween_property(_sprite, "scale:x", 1.0, 0.05)
    _current_facing = new_facing
```

This creates a fluid "turn" effect instead of a jarring mirror-flip.

---

## KINGDOM RUSH BATTLE ZONE — Terrain Design

### Current State
- GrassMain: flat ColorRect RGB(0.38, 0.58, 0.25)
- CombatLane: flat ColorRect RGB(0.72, 0.6, 0.38)
- Hard color boundary between zones
- Random scatter of decorations (bushes, rocks, trees)

### Target: Kingdom Rush 3-Layer Approach

**Layer 1: Base Terrain Textures**
- Replace GrassMain with **tiled grass texture** from `assets/sprites/terrain/Tileset/`
- Replace CombatLane with **tiled dirt/stone texture**
- Use 2-3 tileset color variants (color1-5 in our assets) blended for variety
- Each tile: 64x64px from our Tileset folder

**Layer 2: Transition Zones (NO HARD BOUNDARIES)**
- Every terrain boundary gets a **3-zone feathered transition** (24-48px wide):
  - Zone A (8-16px): Full grass with scattered dirt particles
  - Zone AB (8-16px): Mixed grass/dirt sprites overlapping
  - Zone B (8-16px): Full dirt with scattered grass tufts
- Implementation: Place transition sprites (semi-transparent, 50-70% alpha) along zone boundaries
- Use our existing bush/rock sprites scaled small as boundary markers

**Layer 3: Decoration Hierarchy**
Kingdom Rush uses a clear density system:

| Type | Spacing | Examples from our assets | Placement |
|------|---------|------------------------|-----------|
| **Primary landmarks** | Every 200-300px | Large trees, rock formations | Zone boundaries, path edges |
| **Secondary decor** | Every 80-120px | Medium bushes, stumps, rocks | Along combat lane edges |
| **Tertiary scatter** | Every 30-50px | Small grass clumps, pebbles, flowers | Fill gaps in all zones |
| **Atmospheric** | 4-6 per screen | Drifting clouds, dust motes | Above everything, low alpha |

### Faction-Themed Decoration (Environmental Storytelling)
- **Player side (Kingdom)**: Neat fences, blue banners, intact structures, flowers
- **Enemy side (Horde)**: Rough palisades, red war banners, skull totems, scorched earth
- **Combat lane center**: Battle debris, weapon fragments, craters — intensifies as match progresses

### Terrain Transitions Specifically Needed

**Grass → Combat Lane (×2, top and bottom edges):**
- 3 rows of transition: grass gets trampled → mixed → dirt
- Small stones scatter from lane edge outward
- Grass sprites at edge are 15% darker (trampled feel)

**Grass → Water (×2, left and right edges):**
- Shore strip: wet sand/mud 12px wide, darker texture
- Water foam animation (Water Foam.png, 4-frame sheet at 4fps)
- Reeds, lily pads, small rocks at edge

**Build Zone → Combat Lane:**
- Subtle elevation hint: combat lane drawn 2px lower (shadow at top edge)
- Worn path marks where units march

---

## IMPLEMENTATION PRIORITY

| # | Fix | Agent | Impact on Feel | Effort |
|---|-----|-------|---------------|--------|
| 1 | **Position interpolation** | A1+A2 | MASSIVE — eliminates choppiness entirely | Small (20 lines total) |
| 2 | **Walk bounce** | A2 | High — sells weight and momentum | Tiny (5 lines) |
| 3 | **Stagger animation phases** | A2 | Medium — prevents lockstep marching | Tiny (3 lines) |
| 4 | **Smooth direction changes** | A2 | Medium — fluid turns | Small (10 lines) |
| 5 | **Hit-stop** | A2 | High — combat crunch | Small (15 lines) |
| 6 | **Attack timing contrast** | A2 | Medium — impactful attacks | Small (15 lines) |
| 7 | **3-layer terrain** | A2 | MASSIVE — KR quality terrain | Medium |
| 8 | **Transition zones** | A2 | High — no hard boundaries | Medium |
| 9 | **Decoration hierarchy** | A2 | High — alive world | Medium |
| 10 | **Faction-themed decor** | A2 | Medium — storytelling | Small |

**Fixes 1-6 should take 1 session.** They're all small code changes with huge feel improvement.
**Fixes 7-10 are the terrain overhaul** — can run in parallel.
