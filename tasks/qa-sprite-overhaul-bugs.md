# QA Sprite Overhaul Bug Report — Visual Showcase Test
> **Date**: 2026-04-11 | **Agent**: A4 | **Tool**: `tests/test_unit_showcase.gd`
> **Verified via**: Frame-by-frame capture at 3x scale, 10fps
> **All 5 issues CONFIRMED with screenshots**

---

## BUG-SPRITE1: Gryphon Rider walk animation — wings static (no flap)
- **Severity**: HIGH
- **Owner**: A6 (sprite art) + A2 (sprite_registry.gd wiring)
- **Unit**: gryphon_rider (blue_gryphon), wyvern_rider (red_gryphon)
- **Evidence**: Showcase frames — idle vs walk animation, wings in identical position across all walk frames. Previously wings flapped, now static.
- **Root cause**: The walk animation sprite sheet (`Gryphon_Run.png`) may have identical wing positions across all 6 frames, or only the body/legs animate while wings stay spread.
- **Expected**: Wings should flap up/down during walk cycle (like the old version).
- **Also noted**: User reports seeing 3 wings in-game — the original bird wings baked into the sprite + potential overlay artifact. At showcase 3x scale I see 2 large spread wings + the blue feathered crest, but at game scale the crest may read as a 3rd wing.
- **Verify fix**: Run `--showcase --unit gryphon_rider` — walk frames should show wing position changing between frames.

---

## BUG-SPRITE2: Knight/Lancer idle→attack size pop
- **Severity**: HIGH
- **Owner**: A2 (sprite_unit_visual.gd auto_scale logic)
- **Unit**: knight (blue_lancer), berserker (red_lancer)
- **Evidence**: 
  - **Idle**: Tall sprite — spear points UP, frame dominated by vertical spear shaft. Content height ~160px.
  - **Attack**: Short/wide sprite — spear thrusts HORIZONTAL. Content height ~80px.
  - auto_scale normalizes both to `target_content = 30px`, so idle gets scale ~0.19 and attack gets scale ~0.38 — **the body DOUBLES in size** when attacking.
- **Root cause**: `sprite_unit_visual.gd` computes `auto_scale = target_content / content_height` per-animation. When idle content_height >> attack content_height, the body pops to a different scale.
- **Fix needed**: Lock scale to the BODY portion of the sprite, not the full content including weapon. Or: use a single reference animation (idle) to compute scale and apply it to ALL animations for that unit.
- **Verify fix**: Run `--showcase --unit knight` — body should stay same size across idle/walk/attack/death.

---

## BUG-SPRITE3: Catapult peon too large + no rock projectile
- **Severity**: MEDIUM
- **Owner**: A6 (sprite art — peon/machine proportions, Rock.png projectile) + A2 (effects.gd projectile spawning)
- **Unit**: catapult (blue_catapult), demolisher (red_catapult)
- **Evidence**:
  - **Peon size**: The operator figure baked into the catapult sprite is nearly as tall as the catapult machine itself. At game scale, the peon dominates the visual — should be ~60% of machine height.
  - **Rock projectile**: `Rock.png` exists in `assets/sprites/units/blue_catapult/` but is NEVER spawned as a separate projectile. During attack animation, the rock stays attached to the catapult arm cup — no launched projectile visible.
- **Fix needed**: 
  1. The peon is baked into the sprite sheet — can't resize independently. May need to use the ballista approach (render clean machine + separate pawn overlay at correct scale).
  2. Load `Rock.png` and spawn it as a projectile sprite from the catapult position toward the target when attack fires. Similar to how archer arrows should work.
- **Verify fix**: Run `--showcase --unit catapult` — peon should be small relative to machine. In-game: rock projectile should fly from catapult to target.

---

## BUG-SPRITE4: Ballista has 2 visible peons (baked + overlay)
- **Severity**: HIGH
- **Owner**: A6 (sprite art — clean machine-only sprite needed) + A2 (sprite_unit_visual.gd overlay logic)
- **Unit**: ballista_unit (blue_ballista), scorpion (red_ballista)
- **Evidence**: Showcase frames clearly show TWO operators:
  1. **Baked-in peon**: The badly-erased brownish figure behind/inside the ballista machine (from the original sprite sheet where the artist tried to erase the operator but left artifacts)
  2. **Pawn overlay**: The clean blue pawn sprite rendered at 45% scale on top (z_index=1) — this is the fix from `sprite_unit_visual.gd:101-120`
- **Result**: Two peons visible simultaneously — one messy, one clean.
- **Root cause**: The overlay was added to HIDE the baked-in peon, but the baked-in peon is still visible behind/around the overlay. The overlay is too small (45% scale) to fully cover the original.
- **Fix options**:
  1. Increase overlay scale to fully cover the baked-in peon
  2. Edit the `Ballista_*.png` sprite sheets to properly erase the original operator (clean erasure, not partial)
  3. Create a machine-only sprite sheet + separate pawn overlay at proper scale
- **Also**: Bolt projectile (`Bolt.png` in assets) is baked into the machine sprite tip, not spawned as separate projectile. Should be a flying projectile like the rock for catapult.
- **Verify fix**: Run `--showcase --unit ballista_unit` — should see ONE clean operator, not two overlapping figures.

---

## BUG-SPRITE5: All Lancer-type units (Knight + Berserker) same size-pop issue
- **Severity**: HIGH (same as BUG-SPRITE2 but confirming both factions affected)
- **Owner**: A2 (sprite_unit_visual.gd auto_scale fix resolves both)
- **Units affected**: knight, berserker (both use Lancer sprite set)
- **Evidence**: Berserker showcase: idle (tall, vertical spear) → attack (short, horizontal thrust) — same body-size-doubling behavior as Knight. Red lancer has identical sprite structure to blue lancer.
- **This is a duplicate of BUG-SPRITE2** — listed separately to confirm both teams are affected. Single fix in auto_scale logic resolves both.

---

## BUG-SPRITE6: Composite unit sizing — rider/operator must match base unit size
- **Severity**: HIGH
- **Owner**: A6 (sprite generation) + A2 (auto_scale target_content values in sprite_unit_visual.gd)
- **Units**: ALL composites — gryphon_rider, knight, catapult, ballista_unit (+ red equivalents)
- **Rule**: The human character (rider/operator/pawn) on a composite unit must be the SAME pixel size as the standalone base unit. The mount/machine is ADDITIONAL — it makes the total sprite bigger, but the person stays consistent.
- **Evidence** (side-by-side at 3x showcase zoom):
  - **Archer vs Gryphon Rider**: Rider's archer portion is ~2x bigger than standalone archer
  - **Footman vs Knight (Lancer)**: Lancer body is ~60% of footman — too small
  - **Footman vs Catapult peon**: Peon is ~70% of footman — undersized
  - **Footman vs Ballista pawn**: Pawn overlay is ~40% of footman — way too small
- **Root cause**: `sprite_unit_visual.gd` uses `target_content` constants per unit type to normalize size. The composite target values don't account for the base character needing to match standalone size.
  - Standalone baseline: `target_content = 30px`
  - Gryphon: `target_content = 54px` → makes whole composite 54px, but rider portion ends up bigger than standalone archer
  - Ballista: `target_content = 36px` → pawn overlay at 45% of this = ~16px, way smaller than standalone 30px
- **Fix approach for A6**: When compositing, ensure the RIDER/OPERATOR portion of the sprite occupies the same pixel height as a standalone unit (~30px at game scale). The mount/machine adds to the TOTAL height but doesn't shrink the person.
- **Fix approach for A2**: Adjust `target_content` values so the character body matches standalone size. May need per-composite scaling where the body is locked and only the mount scales.
- **Verify**: Run `godot --path castle_clash -- --showcase`, compare base vs composite side-by-side. Rider/operator should be visually same size as standalone.

---

## Summary

| Bug | Unit(s) | Issue | Severity |
|-----|---------|-------|----------|
| SPRITE1 | gryphon_rider, wyvern_rider | Walk wings don't flap | HIGH |
| SPRITE2 | knight, berserker | Body doubles in size on attack | HIGH |
| SPRITE3 | catapult, demolisher | Peon too large, no rock projectile | MEDIUM |
| SPRITE4 | ballista_unit, scorpion | 2 peons visible (baked + overlay) | HIGH |
| SPRITE5 | knight, berserker | Same as SPRITE2 (both factions) | HIGH |

## Overhaul Verification Checklist

After fixes, run these commands and verify:

```bash
# Full unit showcase — all 18 units
godot --path castle_clash -- --showcase

# Composite group only (the 5 problem units)
godot --path castle_clash -- --showcase --group composite

# Individual unit with video capture for frame review
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/paulinecolobong/game/castle_clash \
  --write-movie "/tmp/showcase_verify/frame.png" \
  --fixed-fps 10 --disable-vsync \
  -- --showcase --unit knight
```

**Per-unit verification criteria:**
- [ ] SPRITE1: gryphon_rider walk frames show wing position CHANGING between frames
- [ ] SPRITE2: knight body stays SAME SIZE across idle/walk/attack/death
- [ ] SPRITE3: catapult peon visibly smaller than machine; rock projectile visible during attack
- [ ] SPRITE4: ballista shows ONE clean operator (no ghost/artifact peon behind it)
- [ ] SPRITE5: berserker body stays SAME SIZE across idle/walk/attack/death
