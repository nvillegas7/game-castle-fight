# Castle Fight (WC3) - Comprehensive Game Mechanics Research

## 1. Core Gameplay Loop

### Overview
Castle Fight is a **tug-of-war** auto-battler custom map for Warcraft 3. Two teams (up to 3v3) each have a **Castle** they must defend while trying to destroy the enemy's Castle.

### Flow
1. **Race Selection** - Each player picks/gets assigned a race (14 available)
2. **Building Phase** - Players control a single **Builder** unit that constructs buildings in their half of the map
3. **Auto-Spawning** - Buildings periodically spawn units that **automatically march** toward the enemy castle (uncontrollable)
4. **Combat** - Units from both sides meet in lanes and fight automatically
5. **Escalation** - Players earn income, build more/better buildings, counter enemy compositions
6. **Victory** - Destroy the enemy Castle to win the round
7. **Best of X** - Match is best-of-3 (configurable 1-6 rounds)

### Key Principle
Players have **zero micro control** over spawned units. All gameplay is **macro-level**: choosing which buildings to place, when to place them, and how to counter the enemy's composition.

---

## 2. Economy System

### Starting Resources
- **Default Mode**: 4,000 Gold, 3,000 Lumber (configurable)
- **Fixed Income Mode**: 100 Gold, 30 Gold income

### Three Resources
| Resource | Purpose | How Earned |
|----------|---------|------------|
| **Gold** | Primary resource for all buildings, upgrades, items | Passive income (every 10 sec) + kill bounty |
| **Lumber** | Secondary resource for special/legendary buildings | Earned by building unit-producing barracks (lumber earned = building cost) |
| **Cheese** | Tertiary resource for legendary units | Earned by building/upgrading unit buildings |

### Income Mechanics
- **Income tick**: Every **10 seconds**
- **Base income per player**: 5 gold
- **Building income**: Unit-producing buildings give ~2% of their cost as income per tick
- **Income tax**: At 25 income, a tax kicks in (10% increase per 12.5 income above threshold)
- **Destroyed buildings**: You **lose** the income from destroyed buildings
- **Kill bounty**: Killing enemy units/buildings gives gold to the killer
- **Domination bonus**: Team controlling both lanes gets **50% bonus income**

### Treasure Boxes
- Special building that increases income by a percentage
- Optimal placement thresholds: income 40-49 (first), 70-99 (second)
- One player can go all-in on treasure boxes for team income boost

### Income Progression Strategy
- Early: Build cheap barracks (100-125 gold) for fast income ramp
- Mid: Transition to expensive barracks (up to 230+ gold)
- Late: Income snowballs - "new income gives even faster increase in income"

### Building Refunds
- Selling a building refunds **50% of cost**
- Towers do not refund lumber

---

## 3. Unit Stats - Typical Ranges

### Stat Ranges by Role (from Castle Fight + WC3 engine)

#### Cheap Melee (Frontline/Tanks) - Cost: 100-200g
| Stat | Typical Range | Example: Footman (100g) |
|------|--------------|------------------------|
| HP | 170-575 | 250 |
| Damage (DPS) | 12-38 | 18 |
| Armor | 2-7 | 4 |
| Armor Type | Heavy/Medium | Heavy |
| Damage Type | Normal | Normal |
| Attack Range | Melee (100) | Melee |
| Movement Speed | 270-300 | 270 |
| Attack Cooldown | 1.2-1.5s | 1.35s |

#### Ranged Units (Backline DPS) - Cost: 140-320g
| Stat | Typical Range | Example: Sniper (140g) |
|------|--------------|----------------------|
| HP | 270-525 | 270 |
| Damage (DPS) | 22-61 | 22 |
| Armor | 0-5 | 0 |
| Armor Type | Medium/Light | Medium |
| Damage Type | Pierce | Pierce |
| Attack Range | 450-550 (up to 1000 for siege) | 500 |
| Movement Speed | 270 | 270 |
| Attack Cooldown | 1.5-2.5s | ~1.5s |

#### Casters/Support - Cost: 250-350g
| Stat | Typical Range | Example: Warlock (300g) |
|------|--------------|------------------------|
| HP | 290-400 | 350 |
| Damage (DPS) | 8-17 | 17 |
| Armor | 0-1 | 1 |
| Armor Type | Unarmored/Light | Unarmored |
| Damage Type | Magic/Chaos | Chaos |
| Attack Range | 60-650 | 160 |
| Movement Speed | 270 | 270 |
| Attack Cooldown | 1.75-2.5s | ~2.0s |

#### Elite/Legendary Units - Cost: 525-850g
| Stat | Typical Range | Example: Paladin (525g) |
|------|--------------|------------------------|
| HP | 850-1250 | 850 |
| Damage (DPS) | 50-70 | 67 |
| Armor | 6-9 | 9 |
| Armor Type | Heavy | Heavy |
| Damage Type | Hero/Chaos | Hero |
| Attack Range | Melee-60 | Melee |
| Movement Speed | 270-350 | 270 |
| Attack Cooldown | 1.2-1.5s | ~1.4s |

#### Flying Units - Cost: 200-350g
| Stat | Typical Range | Example: Gryphon (250g) |
|------|--------------|------------------------|
| HP | 500-725 | 500 |
| Damage (DPS) | 19-50 | 23 |
| Armor | 0-2 | 2 |
| Armor Type | Light/Medium/Heavy | Medium |
| Damage Type | Magic/Pierce | Magic |
| Attack Range | 30-450 | 450 |
| Movement Speed | 320-400 | 320 |
| Attack Cooldown | 1.75-2.4s | 2.2s |

#### Siege Units - Cost: 210-380g
| Stat | Typical Range | Example: Mortar (210g) |
|------|--------------|----------------------|
| HP | 280-700 | 280 |
| Damage (DPS) | 21-58 | 21 |
| Armor | 0-2 | 0 |
| Armor Type | Light/Heavy/Fortified | Light |
| Damage Type | Siege | Siege |
| Attack Range | 700-1000+ | 1000 |
| Movement Speed | 220-270 | 270 |
| Attack Cooldown | 2.5-3.5s | 3.5s |

### WC3 Movement Speed Tiers
| Category | Speed Value | Example Units |
|----------|-----------|---------------|
| Slow | 190-220 | Peasants, Siege Engines |
| Average | 270 | Footmen, Riflemen, most infantry |
| Fast | 300-320 | Spell Breakers, Heroes, Gryphons |
| Very Fast | 350 | Knights, Dragonhawks |
| Flying Max | 400 | Flying Machines |

### WC3 Attack Speed Categories
| Category | Cooldown Range |
|----------|---------------|
| Very Fast | < 1.0s |
| Fast | 1.0 - 1.49s |
| Normal | 1.5 - 1.99s |
| Slow | 2.0 - 2.99s |
| Very Slow | > 3.0s |

---

## 4. Unit AI / Behavior

### Movement Pattern
- Units spawn from their building and **automatically march toward the enemy castle**
- They follow **lanes** (standard map has 2 lanes, top and bottom)
- Units do NOT roam - they march in a **straight line** toward the enemy base
- When they encounter enemies, they stop and fight

### Targeting / Aggro
- Units attack the **closest enemy** (acquisition range / aggro range)
- Standard WC3 acquisition range: ~500-600 units for most ground units
- Once engaged, units fight until the target dies, then re-acquire
- No smart targeting - purely proximity-based

### Pathfinding
- Units use WC3's built-in A* pathfinding
- They path around buildings and terrain obstacles
- In Castle Fight, buildings placed by players create pathfinding obstacles
- This enables the **"caging"** strategy: building walls to trap/redirect units

### Formation Behavior
- Frontline melee units naturally end up in front (they stop when they hit enemies)
- Backline ranged units stack behind melee (they can shoot over friendlies)
- Flying units path over everything - immune to ground-based obstacles
- Different movement speeds cause formation breakup (slower units arrive later)
- **Sync strategy**: Players time unit releases so fast and slow units arrive together

### Key Behavioral Properties
- Units are **completely uncontrollable** after spawning
- They will always march toward the enemy castle
- They engage any enemy unit in their aggro range
- They do NOT retreat - they fight to the death
- Spawned units appear at the building that created them

---

## 5. Skills / Abilities

### Unit Abilities (Passive)
| Ability | Description | Example Unit |
|---------|-------------|-------------|
| **Evasion** | % chance to dodge attacks | Defender |
| **Defend** | Reduces pierce damage taken | Defender |
| **Critical Strike** | % chance for bonus damage | Sniper, Marksman |
| **Cleave/Splash** | Hit multiple units with melee | Crusader, Paladin |
| **Devotion Aura** | +Armor to nearby allies | Crusader, Paladin |
| **Bash** | % chance to stun on hit | Gryphon, Paladin |
| **Spell Reduction** | Units get 10% spell damage reduction | Global buff |
| **Mana Regen Aura** | +Mana regen to nearby allies | Power Plant building |

### Unit Abilities (Active/Auto-cast)
| Ability | Description | Example Unit |
|---------|-------------|-------------|
| **Inner Fire** | Buffs damage + armor of allies | Crusader, Paladin |
| **Chain Lightning** | Bouncing damage on attack | Gryphon |
| **Resurrection** | Revives dead allied units | Paladin |
| **Healing** | Heals allied units | Sorceress, Coral Statue |
| **Banish** | Makes unit ethereal (immune to physical) | Nature special |
| **Tornado** | AoE disruption | Nature special |

### Special Building Abilities
| Category | Description | Examples |
|----------|-------------|---------|
| **Artillery** | Deals direct siege damage to random enemy buildings | Human Artillery (400-500 siege damage) |
| **AoE Damage** | Area damage to enemy units | Volcanoes, Decay, Earthquake, Well of Pain |
| **Buffs** | Team-wide or area buffs | Gjallarhorn (66% attack speed), Heroic Shrine (22% double spawn) |
| **Armor Reduction** | Reduces enemy armor | Eye of Corruption (map-wide), Void Keeper (650 range), Wandigoo (850 AoE) |
| **Healing** | Heals friendly units/buildings | Coral Statue (Naga), NE Heal special |
| **Stasis** | Global stun | Legendary Totem (stasis type) |
| **Endurance** | Global attack/move speed buff | Legendary Totem (endurance type) |
| **Direct Damage** | Single-target spells | Obelisk of Light, Oracle |

### Legendary Totem Types (Build Once Each)
1. **Stasis Totem** - Global stun on all enemies
2. **Healing Totem** - Global heal on all allies
3. **Endurance Totem** - Global attack speed + movement speed buff

### Castle Shop Items
| Item | Effect |
|------|--------|
| **Damage Aura** | +200% or +400% damage to nearby allies |
| **Healing Aura** | Heals nearby buildings |
| **Lightning** | Damages enemy units (persists until round end) |
| **Healing Scroll** | Single-use healing (must repurchase) |
| **Staff** | Counters siege units |

### Rescue Strike (RS)
- **One-time use per round** ability
- Kills every enemy unit in a large area
- Critical strategic resource - timing is everything

---

## 6. Building Mechanics

### Building Categories
| Category | Cost | Function |
|----------|------|----------|
| **Barracks (Unit Buildings)** | 100-525 Gold | Spawn units automatically on a timer |
| **Special Buildings** | Gold + Lumber | Cast active/passive spells, provide buffs/debuffs |
| **Towers (Defense)** | 150-250 Gold + 300 Lumber | Shoot at enemies in range, no spells |
| **Treasure Boxes** | Gold | Increase passive income by % |
| **Legendary Buildings** | Gold + Lumber + Cheese | Spawn powerful legendary units |

### Spawn Timer Formula
```
Spawn Time = 15 + (building_cost / 20) seconds
```
**Examples:**
| Building Cost | Spawn Timer |
|--------------|-------------|
| 100g (cheap) | 20 seconds |
| 200g | 25 seconds |
| 280g | 29 seconds |
| 310g | 30.5 seconds |
| 400g | 35 seconds |

### Tower Costs by Race
| Race | Tower Cost (Gold) | Notes |
|------|------------------|-------|
| Human | 150 | Cheapest tower |
| Orc | 175 | |
| Undead | 200 | |
| Corrupted | 200 | Chaos damage |
| Nature | 210 | |
| Night Elf | 210 | |
| Elemental | 240 | |
| High Elf | 250 | Most expensive |
| North | 250 | |

All towers additionally cost **300 Lumber**.

### Building Upgrades
- Many barracks can be upgraded to spawn stronger units
- Upgrading costs additional gold (and sometimes lumber)
- Upgraded buildings replace the spawned unit type
- You can upgrade mid-game to adapt to enemy composition

### Building Placement Rules
- Buildings can only be placed in your half of the map
- Builder unit constructs buildings (takes build time)
- Buildings can be repaired by the builder
- Buildings form physical obstacles (used for caging strategy)
- Strategic placement: build barracks **behind** your castle so enemies attack castle first (your buildings survive longer)

---

## 7. Combat Mechanics

### Damage Type vs Armor Type Matrix (Frozen Throne)

| Attack Type | Unarmored | Light | Medium | Heavy | Fortified | Hero |
|-------------|-----------|-------|--------|-------|-----------|------|
| **Normal** | 100% | 100% | **150%** | 100% | 70% | 100% |
| **Piercing** | **150%** | **200%** | 75% | 100% | 35% | 50% |
| **Siege** | **150%** | 100% | 50% | 100% | **150%** | 50% |
| **Magic** | 100% | **125%** | 75% | **200%** | 35% | 50% |
| **Chaos** | 100% | 100% | 100% | 100% | 100% | 100% |
| **Spells** | 100% | 100% | 100% | 100% | 100% | 70% |
| **Hero** | 100% | 100% | 100% | 100% | 50% | 100% |

### Armor Damage Reduction Formula
```
Actual Damage = Base Damage / (1 + Armor * 0.06)
```
**Examples:**
| Armor | Damage Reduction |
|-------|-----------------|
| 0 | 0% |
| 3 | 15.3% |
| 5 | 23.1% |
| 7 | 29.6% |
| 10 | 37.5% |

### Key Combat Interactions
- **Spell, Splash, and Cleave damage IGNORE armor** (only affected by damage type multiplier)
- **Normal** damage excels vs Medium armor (frontline infantry killers)
- **Piercing** excels vs Light armor and Unarmored (anti-caster, anti-air)
- **Siege** excels vs Fortified (building destroyers) and Unarmored
- **Magic** excels vs Heavy armor (anti-tank)
- **Chaos** deals full damage to everything (rare, expensive units)
- **Castles have Fortified armor** - only Siege and Chaos damage effectively hurt them

### Melee vs Ranged
- **Melee units** form the frontline, absorb damage (tanks)
- **Ranged units** stand behind and deal damage (DPS)
- **Balance**: Melee units generally have more HP and armor, less DPS; ranged units are glass cannons
- **Late game**: "Melees are generally just meat" - ranged/caster units dominate

### Splash/AoE Damage
- Some units have **splash** on their attacks (e.g., Heavy Gunner)
- Splash damage **ignores armor value** (but not armor type)
- AoE special buildings can devastate grouped units
- Flying units are **immune** to many ground-based AoE (volcanoes, earthquakes)

---

## 8. Factions / Races

Castle Fight features **14 races**, each with unique buildings, units, and special abilities:

### Race Summaries

| Race | Tier | Strengths | Weaknesses |
|------|------|-----------|------------|
| **Human** | Mid | Strong early, cheap towers (150g), artillery, defenders, resurrection (Paladin) | No chaos damage, loses power midgame |
| **Naga** | High | Best farming (murlocs), coral statue healing, oracle (strong early special), turtles for siege | Requires good macro |
| **Night Elf** | Mid | Chaos damage (druid), strong magic damage, starfall AoE, heal+buff specials | Expensive units |
| **Undead** | Mid | Best AoE (Decay), lots of magic damage, cheap zombies for income | Less lumber, weak to mech (no decay on mechs) |
| **Nature** | Mid | Balanced units, banish/tornado specials, dragon | No cheap units (cheapest ~200g) |
| **Orc** | Low | Support auras, katapult siege, cheap grunt for income | Weakest race overall, limited options |
| **High Elf (Elf)** | High | Strong single-target specials, powerful units, blademaster tank | Most expensive tower (250g), expensive units |
| **North (Northrend)** | Mid | Frost launcher artillery, mushroom anti-air, strong late-game | Requires 2000 lumber for dual frost launchers |
| **Chaos** | Low | Chaos damage (ignores armor type), strong shrine ultimate (850g), cheap tower with chaos damage | No towers in traditional sense, weak early |
| **The Corrupted** | Mid-High | Strong late-game tree, cheap units for caging/income, chaos damage tower, strong attacking specials | Tentacle units can feed enemy gold |
| **Mech** | Mid-High | All mech units (repairable, immune to poison/decay), shield mechanics, chaos damage access | Weak to single-target spells (shield only blocks AoE) |
| **Elemental** | Mid | Most powerful unit in game (fire elemental lvl2 chaos), diverse options | Depends heavily on fire elemental |
| **Pandaren** | Mid | Custom unique addition | Newer, less established |
| **Desert** | Mid | First new race added in DE | Newest race |

### Race Design Patterns
Each race typically has:
- **2-4 cheap barracks** (100-200g) - income builders, basic units
- **2-3 mid-tier barracks** (200-350g) - core army units
- **1-2 expensive barracks** (350-525g) - elite units
- **1-3 special buildings** (gold + lumber) - race-defining abilities
- **1 tower** (gold + lumber) - defensive structure
- **1 legendary building** (gold + lumber + cheese) - ultimate unit/ability
- **Treasure box** - income booster (shared across races)

---

## 9. Balance Philosophy

### Core Balance Mechanisms

1. **Rock-Paper-Scissors Damage System**
   - Every armor type is strong against some damage types and weak against others
   - No single unit composition is universally dominant
   - Players must **scout and counter** enemy compositions

2. **Economic Tension**
   - Spending on units = immediate power but lower income growth
   - Spending on income buildings = weaker now but stronger later
   - Treasure boxes = pure economy investment with delayed payoff
   - Destroyed buildings = lost income (punishes overextension)

3. **Unit Role Balance**
   - Tanks (heavy armor, high HP) are countered by magic damage
   - Ranged DPS (pierce) is countered by medium armor + fortified
   - Siege (building destroyers) is weak vs units
   - Casters (magic) are fragile to pierce damage
   - Chaos damage (ignores armor types) is gated by high cost

4. **Frontline/Backline Dynamic**
   - "There are always units that go in front and take hits (frontline), and those who stand behind and shoot (backline)"
   - You can rarely find a unit that has high HP AND high armor AND good range AND splash (Hydra is cited as the exception, and its cost reflects it)

5. **Timing Windows**
   - Different races peak at different game phases
   - Human peaks early, Corrupted peaks late
   - "The team who strikes first will usually lose" - defense is favored
   - Rush strategies exist (6-8 minute wins possible) but are risky

6. **Team Coordination**
   - Balanced building across a team (tanks + DPS + support + auras) beats solo strategies
   - One player can specialize in income while others build army
   - Complementary race selections matter

### Anti-Snowball Mechanisms
- Buildings behind castle survive longer (units attack castle first)
- Rescue Strike (one-time nuke) prevents unstoppable pushes
- Income system means even losing teams can rebuild
- Tower spam as emergency defense (3-5-8 towers)

### Pro-Snowball Mechanisms
- Destroyed buildings = lost income (winner gets richer)
- Kill bounty rewards aggressive play
- Domination bonus (50% income for controlling both lanes)
- Unit waves build up if opponent can't clear them

---

## 10. Map Layout

### Standard Map
- **Dimensions**: 95 x 56 (tileset: Ashenvale)
- **Players**: 2, 4, or 6 (2 teams)
- **Orientation**: Left team vs Right team (horizontal)

### Layout Structure
```
[Left Castle] --- [Left Build Zone] --- [Lane Top] --- [Right Build Zone] --- [Right Castle]
                                     --- [Lane Bot] ---
```

### Two Lanes (Standard)
- **Top Lane** and **Bottom Lane**
- Units march from their spawn building toward the enemy castle
- Lanes converge at/near the castles
- Players focus ~85% of attention on the lanes

### Single Lane Variant
- Mode `-sl` restricts to one lane
- `-slt` = single lane top, `-slb` = single lane bottom

### Building Zones
- Each team has a **building area** on their half of the map
- Buildings can ONLY be placed in your team's zone
- Strategic positioning matters:
  - **Behind castle**: Buildings survive longer (enemies hit castle first)
  - **Near lanes**: Units reach combat faster
  - **Caging**: Building walls to trap and accumulate units for synchronized release

### Castle Properties
- Central structure for each team
- Has **Fortified armor** (only Siege and Chaos do full damage)
- Has a **shop** that sells items (damage auras, healing, lightning)
- Destroying enemy castle = win the round
- Castle HP is significant but not published in sources (estimated 2000-5000 HP range based on game length)

### Coins (Optional Mode)
- Coins spawn every 40 seconds randomly in the castle area
- Players who pick them up get bonus gold

---

## Implementation-Critical Numbers Summary

### Economy Quick Reference
| Parameter | Value |
|-----------|-------|
| Starting Gold | ~4,000 (configurable) |
| Starting Lumber | ~3,000 (configurable) |
| Income Tick | Every 10 seconds |
| Base Income | 5 gold/tick |
| Building Income | ~2% of building cost per tick |
| Tax Threshold | 25 income |
| Building Sell Refund | 50% |
| Domination Bonus | +50% income |

### Unit Cost Quick Reference
| Tier | Gold Range | Examples |
|------|-----------|---------|
| T1 (Cheap) | 100-150 | Footman (100), Zombie (120), Murloc, Grunt |
| T2 (Standard) | 150-280 | Sniper (140), Mortar (210), Gryphon (250) |
| T3 (Elite) | 280-400 | Heavy Gunner (320), Warlock (300), Flesh Golem (370) |
| T4 (Legendary) | 400-850 | Paladin (525), Chaos Shrine (850) |

### Spawn Timer Quick Reference
```
Spawn Time = 15 + (cost / 20) seconds
```
| Cost | Spawn Time |
|------|-----------|
| 100g | 20s |
| 200g | 25s |
| 300g | 30s |
| 400g | 35s |
| 500g | 40s |

### Combat Quick Reference
- Armor reduction: `damage / (1 + armor * 0.06)`
- Spell/splash/cleave ignores armor value
- Chaos damage = 100% vs all armor types
- Siege = 150% vs Fortified (buildings/castle)
- Pierce = 200% vs Light, 35% vs Fortified
- Magic = 200% vs Heavy, 35% vs Fortified
