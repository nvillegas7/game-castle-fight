# Feature Spec: Combat Zone Tree Lane System
> **Author**: A0 (Game Designer) | **Date**: 2026-04-07
> **Reference**: WC3 Castle Fight center tree line, TTW lane system

---

## Concept

Add a **horizontal tree wall** across the middle of the combat zone, splitting it into **upper half** (enemy side) and **lower half** (player side). The tree wall has **2-3 gaps** creating lanes that units must path through.

This is the Castle Fight signature terrain feature — it transforms the game from "units march straight" to "units funnel through chokepoints."

---

## Current State

The combat zone (Y=345-709, 364px tall, 11 cols × 13 rows at 28px) already has **9 tree obstacles** in a symmetric pattern:

```
Combat Grid (11 cols × 13 rows):
Row 3:   . . T T . . . T T . .    (2 clusters)
Row 6:   . . . . . T . . . . .    (1 center tree)
Row 9:   . . T T . . . T T . .    (2 clusters)
```

These create soft obstacles but NOT a true lane system. Units can easily walk between them.

---

## Proposed Layout: Horizontal Tree Band at Row 6-7

```
Combat Grid (11 cols × 13 rows):

Row 0:    . . . . . . . . . . .     ← Enemy units enter
Row 1:    . . . . . . . . . . .
Row 2:    . . . . . . . . . . .     ← Open combat (enemy side)
Row 3:    . . T T . . . T T . .     ← Existing clusters (keep)
Row 4:    . . . . . . . . . . .
Row 5:    . . . . . . . . . . .
Row 6:    . T T T . . . T T T .     ← NEW: Tree wall (2 gaps)
Row 7:    . T T T . . . T T T .     ← NEW: Tree wall (2 gaps)
Row 8:    . . . . . . . . . . .
Row 9:    . . T T . . . T T . .     ← Existing clusters (keep)
Row 10:   . . . . . . . . . . .     ← Open combat (player side)
Row 11:   . . . . . . . . . . .
Row 12:   . . . . . . . . . . .     ← Player units enter

Gaps at: cols 0, 4-5, 10 (left edge, center, right edge)
```

### Why This Layout

- **2 cells thick** (rows 6-7): Ranged units with 3-4 cell attack range (84-112px) CANNOT shoot through. Forces them to position at the gap.
- **3 gaps**: Left edge (col 0), center (cols 4-5, 2 cells wide), right edge (col 10). Center gap is the main highway.
- **Edge gaps**: Cols 0 and 10 are at the arena edges — flanking routes that are narrow (1 cell). Creates risk/reward: flank is uncontested but slow.
- **Center gap (2 cells wide)**: Main chokepoint. Most units funnel here. Splash damage and AoE are devastating at this point.
- **Preserves existing clusters**: Rows 3 and 9 clusters create additional minor obstacles for variety.

---

## Strategic Impact Analysis

### Melee Units (Footman, Grunt, Knight, Berserker)
- **Disadvantaged**: Must path through gaps. Arrive at enemy in a stream, not a wave.
- **Chokepoint vulnerability**: Bunch up at gaps → vulnerable to AoE (Boulder Splash, Cleave).
- **Compensation**: Already cheaper and tankier. The extra pathing time means they arrive slightly staggered, reducing instant focus-fire.
- **Player strategy**: Place melee-spawning buildings near the gap you want to push through. Buildings on the left → units path through left gap.

### Ranged Units (Archer, Axe Thrower)
- **Advantaged early game**: Position behind tree wall on their side, shoot enemies as they funnel through gaps.
- **Gap control**: Archers at a gap entrance can pick off melee units filing through.
- **Attack range vs tree thickness**: With attack range 3-4 cells (84-112px) and tree wall 2 cells thick (56px), archers CANNOT shoot through the wall. They must be near a gap to engage.
- **Player strategy**: Place archer buildings so archers spawn near gaps. Archers positioned at gaps create kill zones.

### Siege Units (Catapult, Demolisher)
- **March-only behavior**: Siege units don't chase targets, they march straight. Tree wall forces them through gaps too.
- **Future potential**: Siege units could gain "tree destruction" ability — spending time clearing trees to open new paths. This is a late-game strategic tool.
- **AoE at chokepoints**: Catapult Boulder Splash at a gap = devastating.

### Flying Units (Future)
- **Bypass entirely**: Flying units ignore tree obstacles, taking the shortest path.
- **Counter to tree-heavy defense**: If opponent relies on tree chokepoints for defense, flying units fly over.
- **Balances the system**: Without flying units, ranged-heavy + tree defense would be too strong.
- **Design note**: This makes flying units a premium counter-strategy worth saving gold for.

### Healers (Priest, Wardrummer)
- **Position behind the wall**: Healers naturally stay behind melee. Tree wall gives them protected positioning.
- **Heal through gaps**: Priest Holy Light (2-cell AoE) can heal allies at the gap while staying behind the tree wall.
- **Wardrummer aura**: Aura range (3 cells) can buff allies at the gap from behind the wall.

---

## Building Placement Strategy (New Dimension)

The tree wall creates a **lane preference system** based on building position:

```
Player Build Zone (cols 0-10):

Left buildings → units march up → path through LEFT GAP (col 0)
Center buildings → units march up → path through CENTER GAP (cols 4-5)
Right buildings → units march up → path through RIGHT GAP (col 10)
```

**New strategic decisions**:
1. **Concentrate one lane**: All buildings on left side → massive push through left gap. But right gap is undefended.
2. **Split across lanes**: Half left, half right → pressure both gaps. But each push is weaker.
3. **Ranged behind center**: Place archer buildings at cols 4-6, archers spawn near center gap and control it.
4. **Tower at gap**: Place Guard Tower/Flame Tower near a gap → it fires at enemies funneling through.
5. **Wall + gap combo**: Build walls to narrow a gap further, creating an even tighter chokepoint for your towers.

---

## Implementation

### A1 (Game Dev) — Simulation Changes

1. **Add tree wall to combat grid** in `simulation.gd` initialization:
```gdscript
# In _init_combat_grid() or equivalent:
# Tree wall at rows 6-7, cols 1-3 and 7-9
for row in [6, 7]:
    for col in [1, 2, 3, 7, 8, 9]:
        combat_trees[row][col] = 1  # Blocked
# Gaps at: col 0 (left edge), cols 4-5 (center), col 10 (right edge)
```

2. **Flow field respects tree wall**: Already works — flow field BFS skips blocked cells. Units will automatically path through gaps.

3. **Ranged attack LOS check**: Ranged units should NOT be able to attack through tree cells. Add a check: if the straight line between attacker and target crosses a tree cell, the target is not valid. (This may already be handled by the T-062 fix for building LOS — extend to trees.)

4. **Future: Flying role ignores trees**: When flying units are added (role 3), skip tree collision in movement. They fly over the tree wall.

### A2 (UI/UX) — Visual Layer

1. **Render tree wall**: Place Tree1-4.png sprites at tree wall grid positions. Use the existing `_extract_sprite_frame()` for single-frame extraction. Scale ~0.4-0.5 for 28px cells.

2. **Visual density**: 2 trees per cell for a thick forest feel. Slight random offset within cell for organic look.

3. **Gap visibility**: Gaps should be clearly visible — use lighter ground texture (worn path) through the gaps. Maybe a few scattered pebbles/footprints.

4. **Parallax depth**: Trees on the tree wall should have slight shadow beneath them, implying height. Higher z_index than units so trees partially overlap units walking near them (depth illusion).

---

## Balance Considerations

| Factor | Effect | Mitigation |
|--------|--------|-----------|
| Melee weakened | Must path through gaps | Melee is already cheaper; add +10% HP to compensate if needed |
| Ranged strengthened | Controls chokepoints | Ranged is already squishier; melee that GETS through gaps kills them |
| AoE massively buffed | Chokepoints = clumped units | This is intentional — AoE should be premium at chokepoints |
| One-lane rush OP? | All units through one gap = overwhelming force | Enemy can wall/tower the gap + counter-build |
| Turtling too strong? | Sit behind trees, range everything | Flying units (future) + siege counter this; compound income means turtlers get out-economied |

### Should Trees Be Destructible?
**Recommend: NO for MVP.** Keep trees permanent. Reasons:
- Simpler implementation
- Consistent strategic landscape
- Destructible trees adds complexity that's better for a later expansion
- The original Castle Fight trees are effectively permanent (most games end before siege clears them)

**Future expansion**: Siege units could gain a "Demolish" passive — attacks that hit trees destroy one tree after 3 hits. This creates late-game path opening.

---

## Risk Assessment

**Low risk**: The flow field already handles obstacles. Adding more tree cells to the grid is trivial — the BFS pathfinding automatically routes around them. The visual layer just needs more tree sprites placed at specific positions.

**Medium risk**: Balance. Ranged-heavy compositions may become too strong. Monitor with AI-vs-AI testing after implementation. Adjust if Kingdom (heal + ranged) win rate goes above 55%.

**No risk to determinism**: Tree positions are fixed at initialization, not random. Both clients will have identical tree layouts.
