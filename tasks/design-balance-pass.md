# Balance Pass: Buildings HP/Armor + Unit Stats + Rock-Paper-Scissors
> **Author**: A0 (Lead Game Designer) | **Date**: 2026-04-11
> **Reference**: WC3 Castle Fight damage types, Kingdom Rush unit roles

---

## Current Damage Matrix (keep as-is — it's correct)

```
              Light(0)  Medium(1)  Heavy(2)  Fortified(3)
Physical(0):   100%      100%       75%        50%
Pierce(1):     150%       75%      100%        50%
Magic(2):      125%       75%      100%       100%
Siege(3):       50%       50%       50%       150%
```

This matrix is WC3-faithful. The key interactions:
- **Pierce shreds Light** (150%) — archers destroy other archers, priests, light units
- **Physical is bad vs Fortified** (50%) — footmen/knights barely scratch buildings
- **Siege is THE building killer** (150% vs Fortified) — catapult/ballista are essential
- **Magic ignores Fortified** (100%) — priests damage buildings at full rate

---

## Problem 1: Building HP + Armor

### Current State
- ALL buildings: **500 HP, Fortified armor** (hardcoded in simulation.gd:542)
- Wall/Palisade: **500 HP, Fortified armor, 1x1, 15g**
- No per-building HP variation

### Issues
- 500 HP is the same for a 15g Wall and a 180g Champion's Hall — that's wrong
- Walls at 500 HP / 15g are actually very efficient HP-per-gold (33.3 HP/g vs Barracks at 10 HP/g)
- But in practice walls feel fragile because enemy units with Normal attack deal 50% to Fortified = 250 effective HP. A footman (10 dmg, 10 tick speed) kills a wall in 25 attacks = 25 seconds. That's... actually not bad?

### Proposed Building HP (scale with cost, add armor)

| Building | Cost | Current HP | Proposed HP | Armor | Effective HP vs Physical | Effective HP vs Siege |
|----------|------|-----------|-------------|-------|-------------------------|----------------------|
| **Wall** | 15g | 500 | **300** | **5** | 300/(1+5×0.06)=231 × 2(50%)=**462** | 300/1.3 × 0.67=**154** |
| **Barracks** | 50g | 500 | **600** | **3** | 600/1.18 × 2=**1017** | 600/1.18 × 0.67=**340** |
| **Archer Range** | 60g | 500 | **550** | **2** | 550/1.12 × 2=**982** | 550/1.12 × 0.67=**329** |
| **Priest Temple** | 80g | 500 | **500** | **2** | 500/1.12 × 2=**893** | 500/1.12 × 0.67=**299** |
| **Gold Mine** | 80g | 500 | **700** | **4** | 700/1.24 × 2=**1129** | 700/1.24 × 0.67=**378** |
| **Guard Tower** | 70g | 500 | **800** | **5** | 800/1.30 × 2=**1231** | 800/1.30 × 0.67=**412** |
| **Knight Hall** | 120g | 500 | **800** | **4** | 800/1.24 × 2=**1290** | 800/1.24 × 0.67=**432** |
| **Siege Workshop** | 100g | 500 | **700** | **3** | 700/1.18 × 2=**1186** | 700/1.18 × 0.67=**397** |
| **Champion's Hall** | 180g | 500 | **1000** | **5** | 1000/1.30 × 2=**1538** | 1000/1.30 × 0.67=**515** |

**Key design points:**
- **Wall (300 HP, 5 armor)**: Cheap but not free to destroy. A footman (Physical, 50% vs Fortified) needs ~46 hits = 46 seconds. That's worth 15g. A Catapult (Siege, 150% vs Fortified, 28 dmg) kills it in ~8 hits = 200 seconds (25 tick attack speed). Walls are VERY resistant to Normal/Pierce but Siege shreds them — exactly right.
- **Gold Mine/Tower get extra HP+armor**: They're strategic targets worth protecting.
- **Buildings scale with cost**: Expensive buildings are tankier.
- **Armor on buildings matters**: The WC3 formula `dmg/(1+armor×0.06)` means 5 armor = 23% damage reduction ON TOP of the Fortified type resistance.

---

## Problem 2: Unit Attack/Armor Type Assignments

### Current State (from data audit)

| Unit | Attack Type | Armor Type | Role |
|------|------------|-----------|------|
| Footman | Physical(0) | Medium(1) | Melee |
| Archer | Pierce(1) | Light(0) | Ranged |
| Priest | Magic(2) | Light(0) | Caster |
| Lancer | Physical(0) | Heavy(2) | Melee |
| Catapult | Siege(3) | Medium(1) | Siege |
| Royal Knight | Physical(0) | Heavy(2) | Melee |
| Gryphon | Pierce(1) | Light(0) | Flying |
| Ballista | Pierce(1) | Medium(1) | Siege |
| Champion | Physical(0) | Heavy(2) | Melee |

### Issues
- **Ballista has Pierce attack, not Siege** — a siege unit should have Siege attack to kill buildings. Currently it's a long-range archer, not a building killer.
- **Catapult is the ONLY Siege attacker** — need at least 2 siege options
- No unit has **Magic armor** (type not used on units at all)

### Proposed Type Assignments

| Unit | Attack | Armor | RPS Strength | RPS Weakness |
|------|--------|-------|-------------|-------------|
| **Footman** | Physical(0) | **Light(0)** | Solid vs Medium units | Weak vs Pierce (archers shred footmen) |
| **Archer** | Pierce(1) | Light(0) | Shreds Light armor (footmen, priests) | Weak vs Pierce mirror, squishy |
| **Priest** | Magic(2) | Light(0) | Damages everything evenly, heals | Squishy, slow attack |
| **Lancer** | **Pierce(1)** | Heavy(2) | Pierce+Heavy = kills Light AND tanky | Weak vs Physical (50% effective vs his pierce on Heavy targets? No — Pierce vs Heavy is 100%. Hmm) |
| **Catapult** | Siege(3) | Medium(1) | Building destroyer | Weak vs all units (50% dmg to Light/Med/Heavy) |
| **Royal Knight** | Physical(0) | Heavy(2) | Tank, decent vs Medium | Weak vs Pierce-heavy comps |
| **Gryphon** | Pierce(1) | Light(0) | Mobile, kills Light, bypasses terrain | Very squishy |
| **Ballista** | **Siege(3)** | Medium(1) | Building destroyer (long range) | Weak vs units |
| **Champion** | Physical(0) | Heavy(2) | Ultra-tank | Physical is mediocre vs Heavy mirrors |

Wait, let me reconsider the Lancer. In Castle Fight, Lancers typically have Normal attack. The lance pierce mechanic (T-076) already gives them a unique identity. Let me keep them Physical but change the Footman to Light armor so archers counter footmen.

### Revised — Clean Rock-Paper-Scissors

**The triangle:**
```
Physical (Footman, Lancer, Knight, Champion)
    ↓ strong vs Medium armor
Pierce (Archer, Gryphon)
    ↓ strong vs Light armor
Light armor units (Footman, Archer, Priest, Gryphon)
    ↑ weak to Pierce
    
Siege (Catapult, Ballista) → strong vs Buildings (Fortified)
Magic (Priest) → good vs everything, heals, squishy
```

**Counter-play chains:**
1. Enemy builds Footmen (Light armor) → YOU build Archers (Pierce shreds Light, 150%)
2. Enemy builds Archers (Light armor) → YOU build Lancers (Heavy armor, Pierce only does 100% — but Lancer is tanky enough to close the gap and kill)
3. Enemy builds Lancers (Heavy armor) → YOU build more Footmen (Physical does 75% to Heavy, but they're cheap and can swarm)
4. Enemy builds lots of buildings/walls → YOU build Catapult/Ballista (Siege 150% vs Fortified)
5. Enemy has everything → YOU build Priest (Magic 100-125% vs everything, heals your army)

**Footman to Light armor is the KEY change.** Currently Footman has Medium(1) armor, making them resistant to Pierce (75%). Changing to Light(0) means Archers do 150% to Footmen — creating the core RPS dynamic: Archers → Footmen → Lancers → Archers.

---

## Problem 3: Unit Stat Calibration

Keeping attack/armor types from above, here's the full stat table. Changes marked with **.

| Unit | HP | DMG | AtkSpd | Range | Speed | Armor | MagDef | AtkType | ArmType | Notes |
|------|-----|-----|--------|-------|-------|-------|--------|---------|---------|-------|
| Footman | 180 | 10 | 10 | 1 | 2 | 3 | 0 | Phys | **Light** | **Armor type 1→0**. Core infantry, cheap, vulnerable to Pierce |
| Archer | 70 | 14 | 14 | 4 | 2 | 0 | 0 | Pierce | Light | Unchanged. Glass cannon, destroys Light |
| Priest | 50 | 10 | 18 | 3 | 1 | 0 | 3 | Magic | Light | **Speed 1→2**. Too slow currently, dies before healing |
| Lancer | 350 | 22 | 12 | 1 | 4 | 6 | 2 | Phys | Heavy | Unchanged. Tanky cavalry |
| Catapult | 100 | **35** | 25 | 5 | 1 | 0 | 0 | Siege | Medium | **DMG 28→35**. Needs to meaningfully threaten buildings |
| Royal Knight | 400 | 25 | 12 | 1 | 5 | 7 | 3 | Phys | Heavy | Unchanged. Elite cavalry |
| Gryphon | 180 | 16 | 14 | 3 | 5 | 1 | 1 | Pierce | Light | Unchanged. Fast, fragile, air |
| Ballista | 120 | 24 | 22 | 6 | 1 | 2 | 0 | **Siege** | Medium | **AtkType 1→3**. Now a real building killer |
| Champion | 500 | 30 | 14 | 1 | 3 | 8 | 4 | Phys | Heavy | Unchanged. Ultra-tank |

---

## Problem 4: Wall Worth Analysis

**At proposed stats (300 HP, 5 armor, Fortified, 15g):**

| Attacker | Attack Type | Effective DPS vs Wall | Time to Kill |
|----------|-----------|---------------------|-------------|
| Footman (10 dmg, Phys) | 50% Fortified × armor reduction | ~3.8 effective/hit, 10 tick cd | 79 hits = **79 seconds** |
| Archer (14 dmg, Pierce) | 50% Fortified × armor reduction | ~5.4 effective/hit, 14 tick cd | 56 hits = **78 seconds** |
| Lancer (22 dmg, Phys) | 50% Fortified × armor reduction | ~8.5 effective/hit, 12 tick cd | 36 hits = **43 seconds** |
| Catapult (35 dmg, Siege) | 150% Fortified × armor reduction | ~40.4 effective/hit, 25 tick cd | 8 hits = **20 seconds** |
| Ballista (24 dmg, Siege) | 150% Fortified × armor reduction | ~27.7 effective/hit, 22 tick cd | 11 hits = **24 seconds** |

**Verdict**: A wall survives 79 seconds vs a single Footman. That's VERY worth 15g — the path extension from that wall forces enemies to walk 5-10 extra seconds through your tower range. Meanwhile, Catapult kills it in 20 seconds — you NEED siege to deal with walls efficiently. This is the exact RPS we want.

---

## Summary of Changes

1. **Footman armor: Medium(1) → Light(0)** — Archers now counter Footmen (150% Pierce vs Light)
2. **Ballista attack: Pierce(1) → Siege(3)** — Now a real building killer alongside Catapult
3. **Catapult damage: 28 → 35** — More threatening to buildings
4. **Priest speed: 1 → 2** — Can keep up with army
5. **Building HP: scale with cost** (300-1000 HP instead of flat 500)
6. **Building armor: 2-5 per building** (was 0 — only Fortified type mattered)
7. **Wall: 300 HP, 5 armor** — survives 79s vs Footman, 20s vs Catapult
