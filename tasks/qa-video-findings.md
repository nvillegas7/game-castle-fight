# QA Video Test Findings — Full Match Analysis
> **Test**: Full match captured (1258 ticks, 126 seconds, 273 frames)
> **Result**: VICTORY — Enemy castle 10000→0, Player castle 10000→10000
> **Behavior**: 0 zigzaggers, 0 bouncers, 8 stuck (false positive — in own build zone)

---

## BUGS TO FIX (Mechanics Agent — A1)

### VF-1: Units walk through trees instead of around them [GAMEPLAY]
- **Observed**: Blue units visually pass through trees in combat zone
- **Expected**: Units should path AROUND trees like Kingdom Rush environmental obstacles
- **Root cause**: Trees placed by QA in combat zone (x=200-520, y=380-660) are decorative Sprite2D nodes — NOT registered as obstacles in the combat flow field
- **Fix needed**: When trees are placed, mark their grid cells as blocked in `combat_flow_fields`. Or add tree positions to a collidable obstacles array checked by `_move_unit()`
- **File**: `core/simulation.gd` — `_build_combat_flow_fields()`, needs tree positions as input

### VF-2: Units don't play attack animation when attacking castle [VISUAL]
- **Observed**: Melee units reach enemy castle, stand still, deal damage — but no attack swing animation plays
- **Root cause**: `_check_castle_damage()` sets `is_moving = false` and deals damage, but never triggers `play_attack()` on the unit visual. The attack animation is only triggered by `_on_unit_attacked` event, which fires for unit-vs-unit combat, not castle damage.
- **Fix needed**: Emit a visual event when a unit attacks the castle so game_arena can call `play_attack()` on the attacker visual
- **File**: `core/simulation.gd` (emit event), `scripts/game/game_arena.gd` (handle event)

### VF-3: Melee units clump behind castle instead of surrounding it [GAMEPLAY]
- **Observed**: When many melee units attack the castle, they all cluster at the same Y position (behind/below the castle) instead of spreading around it
- **Expected**: Units should spread to different sides of the castle like a siege
- **Root cause**: All units march straight to CASTLE_1_Y (y=70) and stop. The castle entity is at a single point, so all units converge to the same location.
- **Fix suggestion**: Castle should have a large bounding area. Units approaching from different X positions should stop at different points around the castle perimeter. Or add position spreading at the castle (similar to unit separation but anchored to castle)
- **File**: `core/simulation.gd` — castle attack positioning

### VF-4: 8 footmen stuck in own build zone for ~3 seconds each [MINOR]
- **Observed**: Footmen at y=751 targeting castle entity, stuck for 29 ticks before unstick kicks in
- **Root cause**: Units spawning from buildings in the player zone path toward the distant enemy castle. If the path goes through their own buildings, they get temporarily stuck until the unstick nudge fires.
- **Severity**: Low — the 3-second delay is barely noticeable and self-resolves

---

## BUGS TO FIX (Visual Agent — A2)

### VF-5: Logo has gray/white checkerboard instead of transparency [ART]
- **Observed**: Logo on loading screen and main menu shows gray+white grid pattern where transparent pixels should be
- **Root cause**: logo.png was likely exported from a design tool (Photoshop/Figma) with transparency shown as checkerboard, then saved as a flat image. Or the PNG lacks proper alpha channel.
- **Fix**: Re-export logo.png with proper alpha transparency. Verify in an image viewer that the background is actually transparent (alpha=0), not gray+white pixels.
- **File**: `assets/sprites/ui/logo.png`, `logo_128.png`, `logo_32.png`, `logo_512.png`

### VF-6: End screen has plain unstyled floating boxes [UI POLISH]
- **Observed**: VICTORY screen shows "PLAY AGAIN" and "Main Menu" as plain unstyled rectangles. Stats are listed but not in styled cards.
- **Expected**: Kingdom Rush / Clash Royale style celebration screen with:
  - Animated "VICTORY!" with particle effects
  - Stats in styled cards (gold borders, parchment bg)
  - Styled buttons matching the game's medieval theme (use BigBlueButton/BigRedButton textures)
  - Trophy change animation
  - MVP unit showcase
- **File**: `scripts/ui/end_screen.gd`

---

## MATCH STATISTICS
- **Duration**: 2:06 (1258 ticks)
- **Units spawned**: 74 total tracked
- **Player buildings placed**: ~10 (automated)
- **Player castle**: 10000 HP (untouched — player dominated)
- **Enemy castle**: 10000 → 0 (destroyed)
- **Balance observation**: Player (Kingdom) won easily with castle untouched. May need to buff Horde AI or reduce Kingdom healing advantage.
