# Phase 4 Design — Building Upgrade Paths + Unit Consolidation

> **Status**: DRAFT (2026-04-18) — design spec, not yet dispatched as tasks
> **Author**: A0
> **Benchmark**: WC3 Castle Fight custom map
> **Prerequisites**: Phase 3 must close (T-093 polish, BUG-DESYNC1, BUG-36) before starting implementation

---

## Motivation

### Why add an upgrade path
The WC3 Castle Fight DNA is "level up your spawners, not just tech new ones." In our current model we did the opposite — every tier unlocks a new building producing a distinct unit. That gave us a wide roster (19 units) but created a coverage problem:

- Several unit pairs are **mechanically redundant**, differentiated only by stat inflation
- Match depth plateaus once all tiers are unlocked — mid-to-late game has no incremental decisions
- Rank/skill expression has nowhere to go beyond "who tech'd faster"

Adding Lv1→Lv2→Lv3 upgrades on each spawner turns every income tick into a strategic choice: **"tech to new unit"** vs **"buff what I already have."** This is the strategic glue that makes a ranked mode worth playing.

### Why now is the right time
- Phase 3 closes the first playable prod release
- Phase 4 already plans (a) real Horde faction sprites and (b) ranked mode — upgrade paths are the connective system
- Consolidating redundant units reduces A6's Horde sprite workload (fewer distinct units = fewer sprite sheets to composite)

---

## Current unit redundancies (2026-04-18 audit)

| Pair | Redundancy | Evidence |
|---|---|---|
| **Knight / Royal Knight** | Both Heavy-armor melee bruisers. Royal Knight = Knight +14% stats +25% speed. No mechanical identity | HP 350/400, DMG 22/25, Speed 4/5, same attack_type/armor_type/role |
| **Catapult / Ballista** | Both Siege role=4 with move_speed=1. Compete for building-killer niche | Both Siege attack, both role=4, both speed=1 |

Not redundant (keep as distinct):
- Priest (healer + magic — unique support identity)
- Gryphon Rider (flying role=3, only AA target alongside wyvern)
- Mage (ranged magic caster with AoE — distinct from priest)
- Footman / Archer (distinct attack types + roles)

---

## Proposed unit consolidation

Collapse the two redundant pairs into upgrade ladders:

### Knight Hall ladder
- **Lv1 Knight**: HP 250, DMG 18, **Speed 2** (matches footman/archer — base cavalry is not faster than infantry yet, it's just tougher), Heavy armor
- **Lv2 Armored Knight**: HP 350, DMG 22, Speed 2, Heavy armor (current Knight stats, static)
- **Lv3 Royal Knight (mounted)**: HP 400, DMG 25, **Speed 5**, Heavy armor, +20% charge damage vs first target — the mount is the Lv3 identity, not just "bigger numbers"

**Design intent**: Before Lv3, Knight Hall is a "tanky grunt" (durable but ground-speed). Upgrading to Lv3 is the moment you "mount up" — a visible, mechanical leap. This is exactly the WC3 moment.

### Siege Workshop ladder
- **Lv1 Scout Ballista**: HP 100, DMG 18, Range 5, Speed 1, Siege (light harasser)
- **Lv2 Siege Ballista**: HP 120, DMG 24, Range 6, Speed 1, Siege (current Ballista stats)
- **Lv3 Heavy Catapult**: HP 150, DMG 35, Range 5, Speed 1, Siege, **splash damage 1.5 cell radius** (current Catapult + splash upgrade)

**Design intent**: Range → range → splash. Each upgrade meaningfully changes how the unit is used. Lv1 is a cheap harasser, Lv3 is the game-ender.

### Other spawners (single-unit ladders, stat scaling only)
- Barracks → Footman Lv1/Lv2/Lv3
- Archer Range → Archer Lv1/Lv2/Lv3
- Priest Temple → Priest Lv1/Lv2/Lv3
- Mage Tower → Mage Lv1/Lv2/Lv3
- Gryphon Roost → Gryphon Rider Lv1/Lv2/Lv3

Kept without upgrade: Walls, Gold Mines, Towers, War Horn/Blood Totem (economy/defense/specials don't need a tier ladder).

---

## Upgrade mechanics

### Cost scaling
Upgrade cost = **1.5× base building cost** per tier.
- Example: Barracks 50g. Lv1→Lv2 = 75g. Lv2→Lv3 = 110g.
- Example: Knight Hall 150g. Lv1→Lv2 = 225g. Lv2→Lv3 = 340g.

### Stat scaling rules
For single-unit ladders (Footman, Archer, Priest, Mage, Gryphon):
- **HP**: +20% per level
- **DMG**: +15% per level
- **Speed**: unchanged (speed changes feel better as unique mechanics, not multipliers)

For consolidated ladders (Knight, Siege):
- Stats defined per-tier explicitly (see proposals above)
- Each level has a **qualitative** change, not just multiplied numbers

### Skill evolution
- Lv2 unlocks the second skill proc chance (30% → 50% trigger rate)
- Lv3 upgrades skill params (e.g., Priest heal amount 15 → 20 → 30; Mage fireball splash 40% → 55% → 70%)

### Anti-death-spiral
- Lv3 spawn interval is **10% slower** (better units, fewer of them)
- Lv3 unit costs more to replace if killed (kill bounty = tier * base bounty)
- Prevents "Lv3 spam is always optimal" failure mode

---

## Visual distinguishing

**Three-layer approach** (all cheap per-frame, leverages A6's PIL/Pillow pipeline):

| Layer | Lv1 | Lv2 | Lv3 |
|---|---|---|---|
| **Size scale** | 1.0× | 1.1× | 1.2× |
| **Helmet overlay** | bare head | iron helmet | gold crown / feathered helm |
| **Outline tint** | neutral (black) | silver | gold |

**Why this combo**:
- Size reads at-a-glance in peripheral vision (most important for fast-paced combat)
- Helmet is iconic RPG progression — readable when player looks directly
- Gold outline at Lv3 screams "elite" without particle noise

**Building visual progression**:
- Lv1: base building sprite
- Lv2: banner/flag overlay on roof
- Lv3: larger sprite + gold trim + small aura glow

### Sprite work scope (A6)
- 8 upgradable spawner buildings × 2 upgrade variants = 16 new building sprite states
- 8 unit types × 2 helmet variants = 16 new unit composite layers
- Gold outline: shader or palette swap, one-time pipeline

Estimate: ~2 weeks of A6 compositing work.

---

## Data model changes

### `data_scripts/building_data.gd`
Add per-level stats struct:
```gdscript
@export var upgrade_cost_l2: int = 0   # 0 = not upgradable
@export var upgrade_cost_l3: int = 0

# Per-level spawn stats (optional — if 0, compute from base via multipliers)
@export var spawns_unit_l2: UnitData = null
@export var spawns_unit_l3: UnitData = null
```

### `data_scripts/unit_data.gd`
Add tier field + per-tier skill overrides:
```gdscript
@export var tier: int = 1   # 1/2/3 for upgrade visual + skill lookup
```

For consolidated ladders, create new .tres files:
- `knight_l1.tres`, `armored_knight_l2.tres`, `royal_knight_l3.tres`
- `scout_ballista_l1.tres`, `siege_ballista_l2.tres`, `heavy_catapult_l3.tres`

### `core/simulation.gd`
- `_place_building()`: accept `level: int = 1` param
- New command type: `Command.Type.UPGRADE_BUILDING`
- `_handle_upgrade()`: deducts gold, increments level, swaps spawns_unit reference
- `_spawn_unit()`: reads `spawns_unit` from current building level
- Stat scaling: inline formulas for single-unit ladders, explicit lookup for consolidated ladders
- Checksum: include building level so multiplayer doesn't desync

### `autoload/sprite_registry.gd`
- Extend BUILDING_MAP to support per-level sprites: `"barracks" → {l1: "Barracks_L1", l2: "Barracks_L2", l3: "Barracks_L3"}`
- UNIT_MAP additions for consolidated ladder variants

---

## UI changes (A2)

### Building radial menu
Current: Sell / Info / Cancel
Extended: **Upgrade** button appears if `building.level < 3 && player.gold >= upgrade_cost`

### Tier indicator
Building sprite shows tier stars in the corner (1/2/3 gold stars) for at-a-glance level reading.

### Unit cards (card hand)
Cards show current tier of the spawner building. Upgrading the building updates the card visual in real-time.

### Tooltips
Upgrade button tooltip shows:
- Cost
- Unit preview (Lv2 silhouette)
- Stat delta (+20% HP, +15% DMG, skill upgrade)

---

## Balance risks + mitigations

| Risk | Mitigation |
|---|---|
| "Upgrade always optimal" — game reduces to upgrade race | Lv3 spawn interval 10% slower; kill bounty scales with tier (Lv3 kill = 2× gold for enemy) |
| "Upgrade never worth it" — new tech always better | Per-level cost below 1× equivalent new spawner; upgrade retains existing income momentum |
| Balance matrix explosion (tier × level × unit) | Use formulas (not per-cell tuning) for single-unit ladders; explicit stats only for consolidated ladders |
| Match length creep | Speed buffs don't scale with level; kill bounty scaling keeps economy punchy |
| Desync risk from new Command type + level state | Add to `tests/test_multiplayer.gd` + determinism checksum |

### Balance validation plan
1. Mirror-match balance test (100 runs) after every data change — target 45-55% win rate within faction
2. Tier-diversity test — count how often each upgrade level is built in AI-vs-AI matches; all three should fire
3. Match-length test — average should stay 3-5 minutes per T-089 goal

---

## Cross-agent scope

| Agent | Work | Estimate |
|---|---|---|
| A0 | Design spec (this doc) + dispatch task decomposition + balance tuning | 1 week |
| A5 | Data model + sim changes + upgrade command + stat scaling + tests | 2 weeks |
| A6 | 16 building sprite variants + 16 unit helmet composites + outline shader | 2 weeks |
| A2 | Radial menu upgrade button + tier stars + card updates + tooltips | 1 week |
| A4 | Test matrix + balance validation + regression suite | 1 week |

**Total**: ~5-7 weeks elapsed, assuming parallel A5/A6 work and A2 follows A6 by a week.

---

## Implementation phases

### 4A: Foundation (A5 + A0)
- Add `level` field to building entity
- Implement UPGRADE_BUILDING command + handler
- Single test case: upgrade Barracks Lv1→Lv2 changes spawned Footman HP

### 4B: Consolidation (A5 + A6)
- Migrate Royal Knight → Knight Hall Lv3 data
- Migrate Ballista → Siege Workshop Lv2/Lv3 data
- Deprecate `royal_knight.tres`, `ballista_unit.tres` (keep on disk as orphans)
- Horde parity: migrate `war_rider` → Beast Pen Lv3, `scorpion` → Demolisher Works Lv2/Lv3

### 4C: Sprite tier system (A6 + A2)
- Helmet overlay pipeline in generate_*.py scripts
- Size scale integration into sprite_unit_visual.gd
- Gold outline shader
- Building Lv2/Lv3 sprite variants

### 4D: UI (A2)
- Radial menu upgrade button
- Tier stars on buildings
- Card hand tier indicator
- Upgrade tooltips

### 4E: Balance + polish (A0 + A4)
- 100-match balance test with all tiers
- Tier-diversity test
- Match-length regression
- Final stat tuning

---

## Open questions (for A0 to resolve before dispatch)

1. **Upgrade timing**: can you upgrade during combat, or only in prep phase? (WC3: anytime. Ours: anytime seems fine, keeps pressure on.)
2. **Partial refund on sell**: does selling an upgraded building refund a percentage of upgrade cost or just base? (Recommend: 50% of total invested.)
3. **AI upgrade behavior**: smart AI should upgrade based on match phase. Strategy logic in game_arena.gd. Start simple — upgrade whichever spawner has spawned the most kills this match.
4. **Horde upgrade parity**: when we build the real Horde roster, do Horde upgrades mirror Kingdom stat curves, or differ (e.g., Horde upgrades boost DMG more, Kingdom boosts HP more)? Recommend: mirror for Phase 4 launch, asymmetric balance for Phase 5.
5. **Perk interaction**: do existing perks (Iron Discipline, Swift March, etc.) stack with tier scaling additively or multiplicatively? Recommend: additive (tier gives +20% HP, perk gives +10% HP, total +30%), simpler to reason about.

---

## Appendix — consolidation data migration table

| Current unit | New location | Action |
|---|---|---|
| footman.tres | Barracks Lv1 | unchanged |
| archer.tres | Archer Range Lv1 | unchanged |
| priest.tres | Priest Temple Lv1 | unchanged |
| mage.tres | Mage Tower Lv1 | unchanged |
| gryphon_rider.tres | Gryphon Roost Lv1 | unchanged |
| **knight.tres** | Knight Hall Lv1 | **speed 4→2** (base cavalry is tough, not fast) |
| **NEW: armored_knight.tres** | Knight Hall Lv2 | HP 350, DMG 22, Speed 2, Heavy |
| **royal_knight.tres** | Knight Hall Lv3 | **speed 5→6 + charge bonus**; sprite becomes the mount |
| **NEW: scout_ballista.tres** | Siege Workshop Lv1 | HP 100, DMG 18, Range 5, Siege |
| **ballista_unit.tres** | Siege Workshop Lv2 | unchanged |
| **catapult.tres** | Siege Workshop Lv3 | **add 1.5-cell splash** |

Orphaned after migration: `royal_knight.tres` and `ballista_unit.tres` keep their file paths (they're referenced by Knight Hall Lv3 and Siege Workshop Lv2 respectively), just swap the building association.
