# QA Bug Tracker — Consolidated (2026-04-07 Session)
> **QA Lead**: A4 | **Last Updated**: 2026-04-07
> Other agents: check this file for bugs in YOUR owned files. Update status when fixed.

---

## CRITICAL BUGS

### BUG-IMPORT: 5 assembled UI textures fail to load — stale import cache [A2/ALL - NEW]
- **Severity**: HIGH
- **Status**: OPEN
- **Owner**: A2 or anyone who can run Godot editor
- **Description**: 5 PNG files in `assets/sprites/ui/assembled/` exist on disk with `.import` sidecar files, but their compiled `.ctex` versions in `.godot/imported/` are missing. This causes `Failed loading resource` errors on every game launch.
- **Affected files**:
  1. `special_paper_720x400.png` — used by loading_screen.gd:59
  2. `ribbon_yellow_500.png` — used by main_menu.gd:526
  3. `wood_table_720x240.png` — used by game_arena.gd:953
  4. `wood_table_720x50.png` — used by game_arena.gd:966
  5. `regular_paper_500x200.png` — used by end_screen.gd:63
- **Root cause**: The source PNGs were added to the repo but Godot's import pipeline never ran (or `.godot/imported/` was cleaned). The `.import` files reference `.ctex` paths that don't exist.
- **Fix**: Open the project in Godot editor → it will auto-reimport. Or delete `.godot/imported/` and reopen — Godot rebuilds all imports. Commit the regenerated `.import` files if hashes changed.
- **Impact**: UI falls back to unstyled panels. Loading screen has no paper background, main menu has no ribbon, game arena has no wood table HUD frame, end screen has no paper background.
- **Test**: `_test_assembled_ui_assets()` in test_simulation.gd now catches this (5 FAIL).

### BUG-ENGAGE: Units march past each other without fighting [A5 - NEW]
- **Severity**: CRITICAL
- **Status**: OPEN
- **Owner**: A5 (owns movement/targeting in simulation.gd)
- **Evidence**: 3v3 test (`tests/test_unit_behavior.gd`) — 4/6 units spent >90% of life "chasing" with FULL HP, never attacking. Footman #5: 527 ticks alive, 180/180 HP, 94% chasing. Grunt #6: 462 ticks alive, 150/150 HP, 100% chasing. Units march to opposite castle without engaging mid-field enemies.
- **Root cause**: `_acquire_target()` doesn't find passing enemies. Units moving in opposite directions have closing speeds of ~10px/tick. With aggro check running once per tick, a unit can pass through another unit's aggro range in 1-2 ticks and never be detected.
- **Fix suggestion**: Check all enemies along the unit's MOVEMENT PATH each tick, not just current position. Or: widen aggro Y-range for units moving toward each other. Or: add a mid-field engagement zone where all units within X pixels of an enemy MUST stop and fight.
- **Test**: `godot --headless --path castle_clash -s tests/test_unit_behavior.gd`
- **Log**: `/tmp/castle_clash_behavior/behavior_log.json`

### BUG-ZIGZAG-BOUNDARY: Units oscillate at combat zone boundary [A5 - NEW]
- **Severity**: HIGH
- **Status**: OPEN
- **Owner**: A5 (owns movement/targeting in simulation.gd)
- **Evidence**: 3v3 test — grunt #8 oscillates y=343↔348 for 8 ticks (tick 238-247), footman #5 oscillates y=703↔709 for 5 ticks (tick 175-179). Both positions are exactly at the build/combat zone boundary.
- **Root cause**: Movement logic switches between flow-field mode (build zone) and direct-chase mode (combat zone) at the zone boundary. Unit crosses boundary → switches mode → new mode sends it back → crosses again → infinite oscillation.
- **Fix suggestion**: Add hysteresis — once a unit enters a zone, don't switch movement mode until it's 2+ cells deep. Or: use same movement mode within 1 cell of the boundary.

### BUG-PATH1: Unit zigzag/stuck pathing [A5 - IN PROGRESS]
- **Severity**: CRITICAL (downgraded — stuck was false positive, zigzag is real)
- **Status**: QA_REVIEW — stuck metric fixed, now: 56 zigzag, 0 stuck / 516 units in melee
- **Owner**: A5 (owns movement/targeting/collision in simulation.gd per CLAUDE.md)
- **Root Cause Analysis** (from tick log deep dive — see `tasks/qa-crowd-behavior-report.md`):
  1. **PRIMARY BUG (75% of stuck)**: 319/513 units (62%) spend >50% of their life IDLE with `target_id = -1` in enemy territory. They march to enemy side, kill their target, and then never reacquire. `_acquire_target()` fails because no enemies are nearby — they all marched past in the other direction. **Fix: force-target enemy castle when in enemy half with no target for >10 ticks.**
  2. **CASTLE ZONE IDLE**: 123 units stuck near enemy castle (y<120 or y>920) with no target. They REACHED the castle but don't attack it. Castle targeting only activates within 3 cells — may need wider radius.
  3. **ASYMMETRY**: Kingdom puts 147 units at enemy castle vs Horde's 8. Horde zigzags 2x more (146 vs 79 units). Check flow field symmetry for team 0 vs team 1.
  4. **ZIGZAG**: Avg 24.7 Y-reversals per zigzag unit, max 137. Horde grunts are worst affected.
- **Zone breakdown of stuck units**:
  - Castle zone: 123 (38%) — should be attacking castle
  - Build zone: 121 (37%) — lost target, no fallback
  - Combat zone: 80 (25%) — may be normal melee engagement
- **QA Action**: Full tick-log analysis in `tasks/qa-crowd-behavior-report.md` with per-unit lifecycle data.

### BUG-27: Enemy units spawning in player's base [A1 - OPEN]
- **Severity**: CRITICAL
- **Status**: OPEN
- **Owner**: A1 (simulation.gd:707-725 — `_spawn_from_building()`)
- **Description**: Enemy troops appear inside the player's build zone instead of spawning in the enemy zone
- **Likely cause**: Spawn Y calculation places units at building Y offset, but for team 1 buildings the Y may be inverted

### BUG-BALANCE: Kingdom 100% win rate vs Horde [A1 - NEW]
- **Severity**: HIGH
- **Status**: OPEN
- **Owner**: A1
- **Description**: Balance test (100 AI-vs-AI matches) shows Kingdom wins 100% with fixed build orders. See `tasks/qa-balance-report.md` for full analysis.
- **Likely causes**: Priest healing advantage, Knight charge burst, Guard Tower outperforming Flame Tower
- **Fix needed**: Buff Horde sustain or nerf Kingdom healing

---

## HIGH PRIORITY

### BUG-30: Footman stuck at edge with no target [A1 - OPEN]
- **Severity**: MEDIUM
- **Status**: OPEN
- **Owner**: A1 (simulation.gd — `_move_unit()` and `_unstick_unit()`)
- **Description**: Units at arena edge with target_id=-1 get stuck

### BUG-31: Walls at row 0 block unit spawn path [A1 - OPEN]
- **Severity**: MEDIUM
- **Status**: OPEN
- **Owner**: A1 (simulation.gd — spawn_y near walls)
- **Description**: Units spawn at same Y as walls at row 0, get stuck behind them

### BUG-M3: Mode selector overlaps faction description [A2 - OPEN]
- **Severity**: LOW
- **Status**: OPEN
- **Owner**: A2 (main_menu.gd — `_build_mode_selector()`)

### BUG-M4: Multiple text layers overlap in battle panel [A2 - OPEN]
- **Severity**: LOW
- **Status**: OPEN
- **Owner**: A2 (main_menu.gd — vertical layout spacing)

---

## QA REVIEW FAILURES (returned to agents)

### T-016: Shop tab missing "Daily Pick" section [A2]
- Grid and selection work, but "Daily Pick" with 3 featured avatars not implemented

### T-022: Skill VFX missing 3 of 10 skills [A2 + A1]
- Missing: Devotion Aura (gold ring), Cleave (arc slash), Siege Momentum (projectile growth)
- A1 also needs to emit skill_proc events for these 3 skills from simulation.gd

### T-046: Home screen missing building cards + mastery badge [A2]
- Arena banner and trophy bar work. Missing: 3-4 faction building cards, mastery badge, flame icon on streak

### T-049: Idle animations missing building smoke [A2]
- Trees sway, foam, bush pulse all work. Missing: spawner building smoke/steam particles

### T-054: Perk UI missing confirm step + battle display [A2]
- Perk cards render correctly but single-tap selects AND starts. No confirm step. Perk not shown on battle screen.

### T-056: Game mode description text not rendered [A2]
- Mode buttons and gold border work. Description strings defined but never displayed.

### T-065: Asset packs not downloaded [USER ACTION]
- Research document (asset-research.md) is complete. Only MoRk DuNgEoN font downloaded. User needs to manually download from itch.io/kenney.nl.

---

## FIXED BUGS (This Session)

- BUG-CASTLE1: Castle HP not reaching 0 — PASS (A1 fixed)
- BUG-BUILD1: AI builds on castle — PASS (A1 fixed)
- BUG-CLUMP1: Units clump at tree wall — PASS (A1 fixed)
- BUG-TERRAIN1: Grass tiles missing — PASS (A2 fixed)
- BUG-M1: Floating rank bar — PASS (A2 fixed)
- BUG-M2: Redundant rank stats — PASS (A2 fixed)
- BUG-AE1: Square grass patches — PASS (A2 fixed)
- VF-1: Units walk through trees — PASS (A1 fixed)
- VF-2: No attack animation at castle — PASS (A1 fixed)
- VF-3: Units clump behind castle — PASS (A1 fixed)
