# Feature Spec: Second Skill Per Unit (T-019, T-020, T-021)
> **Author**: A0 (Game Designer) | **Date**: 2026-04-05
> **References**: WC3 Castle Fight unit abilities, DotA/HoN passive system

---

## Goal

Add a second unique ability to each of the 10 units, doubling the game's strategic depth. Each skill should create interesting interactions and counter-play between unit types.

## Data Model Change

### UnitData (`data_scripts/unit_data.gd`)
Add 3 new exported fields:
```gdscript
@export var skill_id_2: StringName = &""
@export var skill_param_3: int = 0
@export var skill_param_4: int = 0
```

### Simulation Entity
Add to unit entity dictionary:
```gdscript
"skill_2_cooldown": 0,
"skill_2_stacks": 0,
"skill_2_active": false,
"mana_shield_hp": 0,  # Priest-specific
```

---

## Kingdom Second Skills

### Footman: Devotion Aura
- **Type**: Passive Aura (always active)
- **Effect**: +2 armor to all allied units within 3 cells (84px)
- **Params**: skill_param_3 = 2 (bonus armor), skill_param_4 = 84 (range in px)
- **Implementation**: In `_check_passive_skills()`, scan nearby allies and apply temporary armor buff. Buff resets each tick (recalculated).
- **Counter-play**: Kill footmen first to remove the aura, making squishy units vulnerable.
- **Stacking**: Multiple footmen DO stack (2 footmen = +4 armor). Intentionally strong for footman-heavy builds.

### Archer: Piercing Shot
- **Type**: Passive On-Hit Proc
- **Effect**: 15% chance for attack to completely ignore target's armor
- **Params**: skill_param_3 = 15 (chance %), skill_param_4 = 0 (unused)
- **Implementation**: In `_perform_attack()`, if attacker has piercing_shot skill, roll RNG. On proc, set armor to 0 for this attack's damage calculation.
- **Counter-play**: Evasion (Berserker) can dodge piercing shots. Knights take occasional massive hits.
- **Uses deterministic RNG**: `sim_rng.randi_range(1, 100) <= 15`

### Knight: Cleave
- **Type**: Passive On-Hit AoE
- **Effect**: Each attack deals 30% splash damage to enemies within 1 cell (28px) of the primary target
- **Params**: skill_param_3 = 30 (splash % of damage), skill_param_4 = 28 (splash radius px)
- **Implementation**: After `_perform_attack()` deals primary damage, scan for enemies near target. Apply `damage * 0.30` to each (uses same armor/type calculation).
- **Counter-play**: Spread out units (anti-clump). Ranged units naturally avoid cleave since they're far from melee targets.
- **Synergy**: Charge (first skill) + Cleave = devastating first hit with AoE.

### Priest: Mana Shield
- **Type**: Passive One-Time Shield
- **Effect**: Absorbs the first 20 damage taken (then breaks permanently)
- **Params**: skill_param_3 = 20 (shield HP), skill_param_4 = 0 (unused)
- **Implementation**: On spawn, set `entity.mana_shield_hp = 20`. In damage calculation, subtract from shield first. When shield reaches 0, it's gone for that unit's life.
- **Counter-play**: Fast attackers (Grunts, Axe Throwers) burn through 20 HP shields quickly. One Grunt swing (12 dmg) almost breaks it.
- **Design intent**: Keeps priests alive longer against initial aggro, giving them time to heal.

### Catapult: Siege Momentum
- **Type**: Passive Damage Scaling
- **Effect**: +5% damage for each 2 cells of distance to target (max +25% at 10 cells)
- **Params**: skill_param_3 = 5 (% per 2 cells), skill_param_4 = 25 (max bonus %)
- **Implementation**: In `_perform_attack()`, calculate distance to target in cells. Bonus = min(distance / 2 * 5, 25). Apply as damage multiplier.
- **Counter-play**: Close the gap fast (Knight Charge) to minimize catapult bonus. Catapults at max range do 25% more, but they fire very slowly.
- **Synergy**: Boulder Splash (first skill) + Siege Momentum = devastating long-range AoE.

---

## Horde Second Skills

### Grunt: Enrage
- **Type**: Passive Threshold Trigger
- **Effect**: +20% attack speed when HP drops below 50%
- **Params**: skill_param_3 = 50 (HP threshold %), skill_param_4 = 20 (attack speed bonus %)
- **Implementation**: In `_check_passive_skills()`, if HP < 50% max HP and not already enraged, reduce attack_speed_ticks by 20% (round up, min 1). Set `skill_2_active = true`.
- **Counter-play**: Burst damage (Knight Charge) kills grunts before enrage matters. Heal denial is key.
- **Stacking with Toughness**: Below 30% HP, grunt has +3 armor AND +20% attack speed. Very dangerous to leave alive at low HP.

### Axe Thrower: Critical Strike
- **Type**: Passive On-Hit Proc
- **Effect**: 20% chance for 2x damage
- **Params**: skill_param_3 = 20 (chance %), skill_param_4 = 200 (damage multiplier %, 200 = 2x)
- **Implementation**: In `_perform_attack()`, roll RNG. On proc, multiply raw damage by 2 before armor reduction.
- **Counter-play**: High armor units (Knight, Footman with Devotion Aura) still reduce crit damage. Mana Shield absorbs the first crit.
- **Synergy with Rending Throw**: 25% chance to debuff + 20% chance to crit = occasional devastating combos.

### Berserker: Evasion
- **Type**: Passive On-Hit Defense
- **Effect**: 15% chance to completely dodge an incoming attack
- **Params**: skill_param_3 = 15 (evasion chance %), skill_param_4 = 0 (unused)
- **Implementation**: In `_perform_attack()`, before applying damage, check if defender has evasion. Roll RNG. On proc, skip damage entirely. Emit `skill_proc` event with "evade" type.
- **Counter-play**: AoE/splash damage (Catapult Boulder Splash, Knight Cleave) cannot be evaded. Only single-target attacks can miss.
- **Design intent**: Makes Berserker a terrifying 1v1 duelist (Blood Frenzy + Evasion).

### Wardrummer: Battle Cry
- **Type**: Active Periodic Buff
- **Effect**: Every 40 ticks (4s), allies within aura range get +15% damage for 15 ticks (1.5s)
- **Params**: skill_param_3 = 40 (cooldown ticks), skill_param_4 = 15 (buff duration ticks)
- **Implementation**: Track `skill_2_cooldown`. When it hits 0, scan allies in war_drums aura range. Apply `battle_cry_buff` (15 tick duration, +15% damage). Reset cooldown. Buff stacks with War Drums aura.
- **Counter-play**: Kill wardrummers to remove both War Drums aura AND Battle Cry. They're squishy (60 HP).
- **Synergy**: War Drums (+85% attack speed) + Battle Cry (+15% damage) = massive DPS window every 4s.

### Demolisher: Burning Ground
- **Type**: On-Hit Area Denial
- **Effect**: Attacks leave a fire zone at impact point for 10 ticks (1s) dealing 3 DPS to all enemies standing in it
- **Params**: skill_param_3 = 10 (duration ticks), skill_param_4 = 3 (damage per tick)
- **Implementation**: On demolisher attack impact, create a "fire_zone" entry in a new `state.fire_zones` array: `{x, y, radius: 28, damage: 3, ticks_remaining: 10, team: attacker_team}`. Each tick, damage enemies in fire zones. Decrement ticks. Remove when 0.
- **Counter-play**: Move units out of fire (they do this naturally via movement AI). Ranged units rarely stand in fire. Mostly punishes melee clumps.
- **Visual**: Fire_01/02/03.png sprites at ground level (A2 handles in T-022).

---

## Balance Notes

- **Proc chances use deterministic RNG** — critical for multiplayer sync
- **No skill interrupts another skill** — both skills are always active
- **Buff stacking is intentional** — multiple footmen/wardrummers create powerful deathballs, but they're expensive and vulnerable to AoE
- **Counter-play matrix**:
  - Armor buffs (Devotion Aura) → countered by Piercing Shot, Siege damage type
  - Evasion → countered by AoE (Cleave, Boulder Splash)
  - Mana Shield → countered by fast attackers (Grunt, Axe Thrower)
  - Burning Ground → countered by ranged compositions
  - Battle Cry timing → countered by killing wardrummer before it activates

## Implementation Order
1. T-019: Add data fields (no gameplay change, pure schema)
2. T-020: Kingdom skills (Footman/Archer first, they're simplest)
3. T-021: Horde skills (Grunt/Axe Thrower first, simplest)
4. T-026: Emit events for all skills (enables A2/A3 work)
5. T-022: Visual effects (A2)
6. T-029: Audio SFX (A3)
7. T-025: Balance test (A4)
