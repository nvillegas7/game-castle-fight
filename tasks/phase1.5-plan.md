# Phase 1.5: Game Improvement Plan

## Three Parallel Workstreams

### STREAM 1: UI Overhaul (Clash Royale Style)
**Goal**: Portrait mobile-first layout with card-based building placement

1. **Portrait viewport** (720x1280)
   - Change project.godot viewport to 720x1280
   - Add sim-to-screen coordinate transform (sim X -> screen Y, sim Y -> screen X)
   - Player territory at bottom, enemy at top, combat lane in middle

2. **Card hand** (replaces right-side building menu)
   - 6 building cards at bottom of screen (103x110px each)
   - Card shows: mini building visual, name, gold cost badge, tier stars
   - Drag-and-drop to place (not click-then-click)
   - Cards gray out when can't afford, lock icon when prereq missing
   - Long-press shows unit stat tooltip

3. **Gold bar** (elixir bar style)
   - Horizontal bar above card hand
   - Fills as income ticks, segment markers every 50g
   - Coin icon + current gold + income rate display

4. **Main menu redesign**
   - Trophy/rank display with progress bar
   - Large faction showcase area with animated castle + units
   - Faction selector cards
   - Big green BATTLE button with pulse animation
   - Bottom nav tabs (Battle/Army/Shop/Profile)

5. **Arena layout** (portrait)
   - Enemy build zone: top (y=140-440), grid 11x10 at 28px cells
   - Combat lane: middle (y=440-660), 220px tall
   - Player build zone: bottom (y=660-1000), grid 11x10 at 28px
   - Castles centered above/below their zones
   - Horizontal castle HP bars

---

### STREAM 2: Combat Mechanics Overhaul
**Goal**: Deep, strategic combat matching Castle Fight quality

1. **Per-building spawn timers** (replaces global waves)
   - Each building has own `spawn_interval_ticks` (18-30s)
   - Timer starts when building is placed
   - Creates staggered reinforcement streams, not bursty waves
   - Removes the 25s global wave -- units flow continuously

2. **Expanded unit stats**
   - Add `magic_defense` (reduces magic damage separately from armor)
   - Add `aggro_range` (how far unit detects enemies, 4-7 cells)
   - Add `skill_id` + params (unique ability per unit)
   - New damage formula: Physical/Pierce/Siege reduced by armor, Magic reduced by magic_defense

3. **Lane-crossing** (2D targeting)
   - Melee units chase enemies within aggro_range in 2D (cross Y-lanes)
   - Ranged/Caster: stay in lane, X-only movement
   - Flying: aggressive 2D chase with extended aggro_range
   - Siege: march straight to castle, no chasing
   - March toward castle when no target; chase when target in aggro_range

4. **Unit skills** (10 unique abilities)

   Kingdom:
   - **Footman "Shield Wall"**: Passive, -15% Pierce damage when HP>50%
   - **Archer "Volley"**: Active (5s cd), fires 3 arrows at 60% damage each
   - **Priest "Holy Light"**: Active (3s cd), AoE heal allies within 2 cells for 50%
   - **Knight "Charge"**: One-time, 2x speed for 1.5s + first hit deals 200% damage
   - **Catapult "Boulder Splash"**: Passive, 40% splash damage within 1.5 cells

   Horde:
   - **Grunt "Toughness"**: Passive, +3 armor when HP drops below 30%
   - **Axe Thrower "Rending Throw"**: 25% chance to debuff target (+20% damage taken, 2s)
   - **Wardrummer "War Drums"**: Aura, allies within 3 cells get +15% attack speed
   - **Berserker "Blood Frenzy"**: +10% damage per kill, stacks 5x
   - **Demolisher "Siege Fire"**: Castle attacks deal +25% and apply burn (50 total damage)

5. **Upgrade buildings** (Critical missing mechanic from Castle Fight)
   - Non-spawning buildings that buff all your units globally
   - Kingdom "Armory": +1 armor to all units (stackable)
   - Horde "Blood Altar": +10% attack damage to all units

---

### STREAM 3: Animation System
**Goal**: Every unit has attack, walk, and skill animations

1. **State machine** in unit_visual.gd
   - States: IDLE, WALKING, ATTACKING, CASTING, DYING
   - Triggered by: movement detection, attack events, heal events

2. **Attack animations** (per role)
   - Melee (0.35s): sword lunge + swing with body squash/stretch
   - Ranged (0.40s): bow draw + release snap
   - Caster (0.50s): staff raise + orb channel + lower
   - Flying (0.40s): rise + dive + pull-up
   - Siege (0.55s): arm load + launch + settle with spring

3. **Walk animation**
   - Leg alternation via sin() phase offset
   - Body lean in movement direction (1.5px)
   - Siege: wheel rotation

4. **Skill VFX** (6 reusable effect types)
   - AoE circle (expanding ring + fill)
   - Buff glow (pulsing gold outline)
   - Shield dome (translucent hemisphere)
   - Slash arc (sweeping line)
   - Orb beam (wavy line between healer and target)
   - Impact shockwave (concentric rings + ground cracks)

---

## Implementation Priority Order

| Step | Stream | What | Est. Effort | Dependencies |
|------|--------|------|------------|-------------|
| 1 | Mechanics | Expanded unit stats (magic_def, aggro_range, skill_id) | Small | None |
| 2 | Mechanics | Per-building spawn timers | Medium | None |
| 3 | Mechanics | Lane-crossing (2D movement + aggro targeting) | Medium | Step 1 |
| 4 | Animation | State machine + walk animation | Medium | None |
| 5 | Animation | Attack animations (all 5 roles) | Large | Step 4 |
| 6 | Mechanics | Unit skills (10 abilities) | Large | Steps 1-3 |
| 7 | Animation | Skill VFX effects | Medium | Steps 5-6 |
| 8 | UI | Portrait viewport + coordinate transform | Large | None |
| 9 | UI | Card hand system | Large | Step 8 |
| 10 | UI | Gold bar + HUD redesign | Medium | Step 8 |
| 11 | UI | Main menu redesign | Medium | Step 8 |
| 12 | UI | Visual adjustments for portrait scale | Medium | Steps 8-11 |

**Recommended execution**: Steps 1-3 first (mechanics foundation), then 4-7 (animation), then 8-12 (UI). Mechanics and animation can run in parallel since they touch different files.

---

## Key Files Modified Per Stream

**Mechanics**: simulation.gd, unit_data.gd, building_data.gd, all .tres files, event_bus.gd
**Animation**: unit_visual.gd, effects.gd, game_arena.gd
**UI**: project.godot, game_arena.tscn, game_arena.gd, building_grid.gd, new card_hand.gd, new gold_bar.gd, main_menu.tscn, main_menu.gd
