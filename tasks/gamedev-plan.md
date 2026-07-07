# Castle Fight Mechanics Alignment — Detailed Game Dev Plan

**Owner**: Senior Game Dev (Agent)
**Status**: PLANNING — awaiting approval
**Date**: 2026-04-05

---

## Executive Summary

After deep research into WC3 Castle Fight and full audit of our simulation (`core/simulation.gd`, all 10 unit `.tres` files, building data), here are the **critical mechanical gaps** between our game and Castle Fight, prioritized by gameplay impact. The user identified 5 key issues; I found 4 additional ones.

---

## GAP ANALYSIS: Our Game vs Castle Fight

### What We Already Have Right
- Two-faction auto-battler with building placement ✅
- Damage type vs armor type matrix (4x4) ✅
- Kill bounty system (awards gold to enemy team) ✅
- Income from buildings + periodic income ticks ✅
- Deterministic simulation with FP math ✅
- 10 unique skills across 10 unit types ✅
- Siege units with castle-targeting ✅
- Building sell at 50% refund ✅
- Tower defense buildings ✅
- Building income loss on destruction ✅

---

## PHASE 1: Movement & Combat Feel (HIGHEST PRIORITY)

### 1.1 — Fix Ranged/Caster Column-Lock Movement
**Files**: `core/simulation.gd:738-752`

**Problem**: Ranged (role 1) and Caster (role 2) units ONLY move on Y-axis. They march in their spawn column and never chase laterally. This makes combat look like parallel train tracks — the "linear marching" the user sees.

**Castle Fight behavior**: ALL units march toward enemy castle and engage nearest enemy with full pathfinding. Ranged units naturally stack behind melee because they stop at their longer attack range.

**Fix**: Change ranged/caster movement to full 2D chase (like melee role 0). The correct frontline/backline formation emerges automatically:
- Melee stops at 1 cell from target → frontline
- Ranged stops at 5-6 cells from target → backline
- Siege keeps march-only (no chasing) → way back

```gdscript
# CURRENT (simulation.gd:747-750):
1, 2:  # Ranged, Caster: Y-only march (stay in column)
    var sign_y: int = 1 if dy > 0 else -1
    unit.y = FP.add(unit.y, FP.mul(FP.from_int(sign_y), unit.move_speed))
    return

# CHANGE TO: full 2D chase (same as melee at lines 740-746)
1, 2:  # Ranged, Caster: full 2D chase (stop at attack range)
    var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
    var dist: int = FP.sqrt_fp(dist_sq)
    if dist > 0:
        unit.x = FP.add(unit.x, FP.div(FP.mul(dx, unit.move_speed), dist))
        unit.y = FP.add(unit.y, FP.div(FP.mul(dy, unit.move_speed), dist))
        unit.x = FP.clamp_fp(unit.x, FP.from_int(ARENA_LEFT), FP.from_int(ARENA_RIGHT))
    return
```

**Tasks**:
- [ ] Remove Y-only movement for ranged/caster roles (make them use melee chase code)
- [ ] Siege units (role 4) keep march-only behavior (no chasing) — this is correct
- [ ] Verify ranged units naturally form backline (they stop when within 5-6 cell attack_range)
- [ ] Playtest: units should spread across board width, not march single-file

### 1.2 — Fix Melee "Phantom Range" Attack
**Files**: `core/simulation.gd:614-616, 636-665`, unit `.tres` files

**Problem**: User reports melee units stopping midway and appearing to attack from range. Attack range = 1 cell = 28px should be very close. 

**Root causes** (after code audit):
1. **Unit separation** (line 636-665) pushes overlapping same-team units apart with 14px force every tick. Two melee units attacking the same target get pushed sideways, creating a visual gap between attacker and target.
2. **No sticky targeting**: Once in attack range and attacking, the separation push can move the unit OUT of attack range, causing it to chase again, creating a stutter-step that looks like ranged attacking.

**Fix**:
```gdscript
# In _separate_units(): skip units currently attacking (cooldown > 0 means just attacked)
if a.attack_cooldown > 0 and a.target_id != -1:
    continue  # Don't push units that are mid-combat
```
Also:
- [ ] Reduce melee attack_range: Footman/Grunt from 1→1 cell (keep), but ensure separation doesn't push them out
- [ ] Add "combat lock": if unit is in attack range AND has a living target, separation force = 0 for that unit
- [ ] Alternative: only apply separation between units that DON'T share the same target

### 1.3 — Differentiate Aggro Range and Attack Range Per Unit
**Files**: All 10 `data/units/*.tres`

**Problem**: Most units have similar aggro ranges (6-9 cells). This means all units detect and engage at roughly the same distance. In Castle Fight, engagement distances vary significantly.

**Proposed differentiated values** (attack_range / aggro_range in grid cells):

| Unit | Current Atk/Aggro | New Atk/Aggro | Why |
|------|-------------------|---------------|-----|
| Footman | 1 / 6 | 1 / 5 | Standard melee, moderate awareness |
| Archer | 5 / 8 | 6 / 9 | Sniper — sees and shoots far |
| Knight | 1 / 7 | 1 / 4 | Charges blind into close range |
| Priest | 4 / 7 | 5 / 6 | Heals at range, modest detection |
| Catapult | 6 / 9 | 8 / 11 | Artillery — longest range in game |
| Grunt | 1 / 6 | 1 / 5 | Mirrors Footman |
| Axe Thrower | 4 / 7 | 5 / 8 | Mid-range harasser |
| Berserker | 1 / 8 | 1 / 7 | Aggressive, wide detection |
| Wardrummer | 4 / 7 | 3 / 5 | Support, stays close to pack |
| Demolisher | 5 / 8 | 7 / 10 | Siege artillery |

- [ ] Update all 10 `.tres` files with new ranges
- [ ] This creates organic engagement: Catapults fire from 8 cells away while Knights don't notice enemies until 4 cells away, creating staggered engagement timing

### 1.4 — Improve Unit Spread (Anti-Clump + Spawn Jitter)
**Files**: `core/simulation.gd` (spawn logic ~line 488, separation ~line 636)

**Problem**: Units spawn at the building's grid center and march in lockstep. With full 2D movement, they'll converge on the same targets and clump.

**Fix**:
- [ ] Add random X offset to spawn position: `±(1-2 cells)` using deterministic RNG
- [ ] Add ±5% random variation to `move_speed` per unit instance (not the data, the entity)
- [ ] Increase separation distance from 14px to 20px for all units

---

## PHASE 2: Economy Rebalance (HIGH PRIORITY)

### 2.1 — Starting Gold = 0
**File**: `core/simulation.gd:80`

**Current**: `"gold": FP.from_int(100)`, `"income": FP.from_int(10)`
**User request**: Gold should start from 0.

**Proposed**:
```gdscript
"gold": FP.from_int(0),
"income": FP.from_int(20),  # Bumped from 10 to compensate
```
Plus: **Immediate first income tick** — at tick 1, grant the first income so players get 20g immediately and can place a cheap building right away (instead of staring at empty board for 5 seconds).

```gdscript
# In step(), change income check:
if tick % INCOME_INTERVAL_TICKS == 0 or tick == 1:  # Include tick 1
```

**Alternatively**, reduce cheapest building costs:
- Barracks: 50g → 40g
- War Camp: 45g → 35g

This means: Start at 0g → get 20g at tick 1 → get 20g at tick 50 (5s) = 40g → can afford first building at 5s. **This pacing matches Castle Fight's deliberate early game.**

- [ ] Set starting gold to 0
- [ ] Set starting income to 20g/5s
- [ ] Add immediate first income tick (tick 1)
- [ ] Consider reducing cheapest building cost to 35-40g

### 2.2 — Kill Bounty Proportional to Unit Cost
**Files**: All 10 `data/units/*.tres`

**Current**: Flat bounty (5g for cheap, 7-8g for expensive)
**Castle Fight**: Bounty scales with unit power. Killing expensive units should be significantly more rewarding.

**Formula**: `bounty = max(3, round(building_cost / 10))`

| Building | Cost | Unit | Current Bounty | New Bounty |
|----------|------|------|----------------|------------|
| Barracks | 50g | Footman | 5g | 5g |
| Archer Range | 60g | Archer | 5g | 6g |
| Priest Temple | 80g | Priest | 5g | 8g |
| Knight Hall | 120g | Knight | 8g | 12g |
| Siege Workshop | 100g | Catapult | 7g | 10g |
| War Camp | 45g | Grunt | 5g | 5g |
| Axe Range | 55g | Axe Thrower | 5g | 6g |
| War Drums | 70g | Wardrummer | 5g | 7g |
| Berserker Pit | 110g | Berserker | 8g | 11g |
| Demolisher Works | 90g | Demolisher | 7g | 9g |

- [ ] Update all bounty values in `.tres` files
- [ ] Show "+Xg" floating gold text on kill in effects system

---

## PHASE 3: Armor Formula Upgrade (MEDIUM PRIORITY)

### 3.1 — Switch to Percentage-Based Armor Reduction
**File**: `core/simulation.gd:765-778`

**Current** (flat subtraction):
```gdscript
var final_damage: int = FP.sub(raw_damage, defense)
```

**Castle Fight / WC3** (percentage reduction):
```
actual_damage = base_damage / (1 + armor * 0.06)
```

**Why this matters**: Flat subtraction makes armor disproportionately strong vs fast, weak attackers. A Grunt with 8-tick attack speed and 14 damage vs 5 armor loses 36% DPS to armor. A Catapult with 20-tick speed and 25 damage vs 5 armor loses only 20%. The WC3 formula makes armor equally effective against all attack speeds.

**Implementation in FP math**:
```gdscript
# Replace: var final_damage = FP.sub(raw_damage, defense)
# With:
var armor_factor: int = FP.add(FP.ONE, FP.div(FP.mul(defense, FP.from_int(6)), FP.from_int(100)))
var final_damage: int = FP.div(raw_damage, armor_factor)
final_damage = FP.max_fp(final_damage, FP.ONE)
```

**Rebalanced armor values** (to feel right under new formula):

| Unit | Current Armor | New Armor | Effective DR |
|------|--------------|-----------|-------------|
| Footman | 2 | 3 | 15.3% |
| Knight | 5 | 6 | 26.5% |
| Grunt | 1 | 2 | 10.7% |
| Berserker | 1 | 1 | 5.7% |
| All others | 0 | 0 | 0% |

- [ ] Implement WC3 armor formula in `_perform_attack()`
- [ ] Apply same formula to `magic_defense` vs magic damage
- [ ] Update armor values in `.tres` files
- [ ] Add rule: splash/AoE damage ignores armor value (only apply type multiplier)

---

## PHASE 4: Skill System Expansion (MEDIUM PRIORITY)

### 4.1 — Current Skills (Already Working)
| Skill | Unit | Type | Status |
|-------|------|------|--------|
| Shield Wall | Footman | Passive (pierce DR) | ✅ |
| Volley | Archer | Active (multi-shot) | ✅ |
| Charge | Knight | Passive (speed burst) | ✅ |
| Holy Light | Priest | Active (AoE heal) | ✅ |
| Boulder Splash | Catapult | On-hit (AoE) | ✅ |
| Toughness | Grunt | Passive (emergency armor) | ✅ |
| Rending Throw | Axe Thrower | On-hit (debuff) | ✅ |
| Blood Frenzy | Berserker | On-kill (stacking dmg) | ✅ |
| Siege Fire | Demolisher | On-hit (castle burn) | ✅ |
| War Drums | Wardrummer | Aura (attack speed) | ✅ |

### 4.2 — New Skills (Castle Fight Inspired)
Add a **second skill** to each unit. This requires extending UnitData.

**Data model change** (`data_scripts/unit_data.gd`):
```gdscript
@export var skill_id_2: StringName = &""
@export var skill_param_3: int = 0
@export var skill_param_4: int = 0
```

**New skills**:

| Skill | Unit | Type | Description | Params |
|-------|------|------|-------------|--------|
| **Devotion Aura** | Footman | Passive aura | +2 armor to allies within 3 cells | range=84px, bonus=2 |
| **Piercing Shot** | Archer | Passive | 15% chance to ignore armor entirely | chance=15% |
| **Cleave** | Knight | On-hit | 30% splash damage to enemies within 1 cell of target | splash%=30, range=28px |
| **Mana Shield** | Priest | Passive | Absorbs first 20 damage taken (one-time) | shield=20 |
| **Siege Momentum** | Catapult | Passive | +5% damage for each 2 cells of distance to target | per_2cells=5% |
| **Enrage** | Grunt | Passive | +20% attack speed when below 50% HP | threshold=50%, bonus=20% |
| **Critical Strike** | Axe Thrower | On-hit | 20% chance for 2x damage | chance=20%, multi=2x |
| **Evasion** | Berserker | Passive | 15% chance to dodge attacks | chance=15% |
| **Battle Cry** | Wardrummer | Active | Every 40 ticks, +15% damage to allies in aura range for 15 ticks | cd=40, bonus=15%, dur=15 |
| **Burning Ground** | Demolisher | On-hit | Leaves fire on ground for 10 ticks dealing 3 DPS to units standing in it | dur=10, dps=3 |

- [ ] Add `skill_id_2`, `skill_param_3`, `skill_param_4` to `unit_data.gd`
- [ ] Implement each skill in `simulation.gd` (new functions per skill type)
- [ ] Update all 10 `.tres` files with second skills
- [ ] Add skill visual effects in `effects.gd`

---

## PHASE 5: Full Stat Rebalance (MEDIUM PRIORITY)

### 5.1 — Stat Pass with Castle Fight Ratios

Castle Fight stats are much higher (250-1250 HP). Our scale is smaller (60-300 HP) — fine for mobile. But **ratios between units** should match Castle Fight's design intent:
- Tanks: high HP, moderate damage, slow attack
- DPS: low HP, high damage, fast attack, long range
- Siege: moderate HP, very high damage, very slow attack, very long range
- Support: low HP, special abilities compensate

**Proposed stats** (all values are data values, converted to FP in simulation):

| Unit | HP | DMG | AtkSpd(ticks) | AtkRange | Aggro | MoveSpd | Armor | MagDef |
|------|-----|-----|------|------|-------|---------|-------|--------|
| Footman | 180 | 10 | 10 | 1 | 5 | 2 | 3 | 0 |
| Archer | 70 | 14 | 14 | 6 | 9 | 2 | 0 | 0 |
| Knight | 350 | 22 | 12 | 1 | 4 | 3 | 6 | 2 |
| Priest | 50 | 10 | 18 | 5 | 6 | 2 | 0 | 3 |
| Catapult | 100 | 28 | 25 | 8 | 11 | 1 | 0 | 0 |
| Grunt | 150 | 12 | 9 | 1 | 5 | 2 | 2 | 0 |
| Axe Thrower | 65 | 16 | 14 | 5 | 8 | 2 | 0 | 0 |
| Berserker | 250 | 28 | 10 | 1 | 7 | 3 | 1 | 0 |
| Wardrummer | 60 | 10 | 14 | 3 | 5 | 2 | 0 | 1 |
| Demolisher | 80 | 32 | 22 | 7 | 10 | 1 | 0 | 0 |

**Key changes from current**:
- Knight: HP 300→350, DMG 18→22, Speed 1→3 (cavalry feel!)
- Berserker: HP 220→250, DMG 24→28, Speed 3→3 (already fast)
- Catapult: AtkSpd 20→25 (much slower), DMG 25→28 (hits harder per shot)
- Priest: AtkSpd 15→18 (heals slower), DMG 8→10 (heals more per cast)
- Archer: Range 5→6 (longer sniper range)

- [ ] Update all 10 `.tres` files with new stats
- [ ] Playtest: verify combat feels right (fights should last 15-30s per wave collision)

---

## PHASE 6: Spawn Timer Proportional to Cost (LOW PRIORITY)

### 6.1 — Cost-Based Spawn Intervals
**Files**: `data/buildings/*.tres`

**Castle Fight formula**: `spawn_time = 15 + (cost / 20)` seconds → converted to ticks at 10/s

| Building | Cost | CF Formula (sec) | Current Ticks | Proposed Ticks |
|----------|------|-------------------|---------------|----------------|
| War Camp | 45g | 17.3s | 18 | 173 |
| Barracks | 50g | 17.5s | 20 | 175 |
| Axe Range | 55g | 17.8s | 20 | 178 |
| Archer Range | 60g | 18.0s | 20 | 180 |
| Flame Tower | 65g | — | — | — (tower) |
| Guard Tower | 70g | — | — | — (tower) |
| War Drums | 70g | 18.5s | 22 | 185 |
| Gold Mine | 80g | — | — | — (income) |
| Priest Temple | 80g | 19.0s | 25 | 190 |
| Demolisher Works | 90g | 19.5s | 30 | 195 |
| Siege Workshop | 100g | 20.0s | 30 | 200 |
| Berserker Pit | 110g | 20.5s | 28 | 205 |
| Knight Hall | 120g | 21.0s | 30 | 210 |

**Note**: These are much longer than current timers (20-30 ticks = 2-3s). Castle Fight's 17-21 seconds is for a PC game with longer matches. For mobile, we may want: `spawn_time = 5 + (cost / 40)` seconds → 6.1-8s range. Needs playtesting.

- [ ] Decide on mobile-appropriate spawn formula
- [ ] Update all building `.tres` spawn intervals

---

## Implementation Order (Recommended)

| # | Task | Effort | Impact | Files |
|---|------|--------|--------|-------|
| 1 | 2.1 Starting gold = 0 | Small | High | simulation.gd:80 |
| 2 | 1.1 Fix ranged/caster movement | Small | High | simulation.gd:738-752 |
| 3 | 1.2 Fix melee phantom range | Medium | High | simulation.gd:636-665 |
| 4 | 1.3 Differentiate ranges | Small | Medium | 10× .tres files |
| 5 | 2.2 Kill bounty rebalance | Small | Medium | 10× .tres files |
| 6 | 5.1 Full stat rebalance | Small | High | 10× .tres files |
| 7 | 3.1 Armor formula | Medium | Medium | simulation.gd:765-778 |
| 8 | 1.4 Unit spread/jitter | Small | Medium | simulation.gd spawn + separation |
| 9 | 4.2 New skills (second skill per unit) | Large | High | unit_data.gd, simulation.gd, .tres files |
| 10 | 6.1 Spawn timer formula | Small | Low | building .tres files |

**Estimated total**: ~3-4 focused sessions

---

## Open Questions

1. **Starting gold 0 + immediate first income tick** — approve this approach?
2. **Ranged units: pure 2D chase or add "prefer staying behind melee" bias?** Castle Fight does pure 2D, recommending we match.
3. **Second skill per unit** — do this now or defer to Phase 2?
4. **Spawn timer**: CF uses 17-21s. Our current is 2-3s. Mobile should be faster but probably 6-10s range. Need playtesting.
5. **Should splash/AoE ignore armor** (WC3 behavior)? This is a significant balance lever.
