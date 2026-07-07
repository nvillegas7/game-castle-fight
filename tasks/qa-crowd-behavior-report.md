# QA Crowd Behavior Analysis — Video Test Deep Dive
> **Date**: 2026-04-07 | **Agent**: A4 | **Scenarios**: melee, full_army
> **Verdict**: FAIL — 3 critical crowd behavior bugs found

---

## Executive Summary

| Metric | Melee | Full Army |
|--------|-------|-----------|
| Total units | 513 | 356 |
| Zigzag | 67 (13%) | 7 (2%) |
| Stuck (20+ ticks) | 345 (67%) | 247 (69%) |
| Bounce | 0 | 0 |
| Match result | Kingdom wins | Kingdom wins |
| Match length | 148s | 137s |

**62-69% of ALL units get stuck for 20+ ticks.** This is the core problem.

---

## Root Cause Analysis (from tick log data)

### BUG-CROWD1: 319/513 units (62%) spend >50% of their life trapped with NO TARGET

This is the #1 issue. Units march to enemy territory, reach the enemy build zone or castle area, and then **lose their target and never reacquire one.** They sit idle (`target_id = -1`, `is_moving = false`) for hundreds of ticks.

**Evidence from melee tick log:**

| Unit | Spawn Y | Final Y | % Life Stuck | Ticks Alive |
|------|---------|---------|-------------|-------------|
| #15 footman | 687 | 98 | 94% | 1273 |
| #20 grunt | 176 | 892 | 95% | 1232 |
| #38 grunt | 167 | 892 | 94% | 1162 |

**Pattern**: Units spawn → march to enemy side → arrive near enemy castle (y≈98 for Kingdom, y≈892 for Horde) → target dies or expires → `target_id = -1` → stuck forever.

**Root cause in simulation.gd**: `_acquire_target()` runs each tick but fails to find a new target for these units. They're in the enemy build zone (y<345 or y>695) but there are no enemies nearby because:
1. Enemy units already passed through heading the other direction
2. Enemy buildings were destroyed
3. The castle is nearby but not being targeted (castle targeting only kicks in within 3 cells)

**Fix needed**: When a unit is in the enemy build zone with `target_id = -1` for more than 10 ticks, it should force-target the enemy castle regardless of distance.

### BUG-CROWD2: Kingdom reaches enemy castle 18x more than Horde

| Team | Units near enemy castle (>30% life) |
|------|-------------------------------------|
| Kingdom (footman) | 147 |
| Horde (grunt) | 8 |

Kingdom dominates the castle attack zone while Horde barely gets there. This explains the 100% Kingdom win rate in balance tests.

**Root cause**: Kingdom footmen survive longer (likely priest healing) and maintain a consistent push. Horde grunts die before reaching the enemy castle zone. The asymmetry is massive — 147 vs 8.

### BUG-CROWD3: Zigzag heavily biased toward Horde (65% of zigzags)

| Team | Zigzag units | Avg reversals |
|------|-------------|---------------|
| Kingdom | 79 | — |
| Horde | 146 | — |
| Avg across all | — | 24.7 |
| Max | — | 137 |

Horde grunts zigzag nearly 2x more than Kingdom footmen. This suggests the flow field or targeting logic creates more instability for units moving "upward" (Horde → Kingdom) than "downward" (Kingdom → Horde).

**Root cause**: Likely asymmetry in flow field direction computation or castle Y-position calculations for team 1 vs team 0.

---

## Zone Distribution of Stuck Units (40+ ticks)

| Zone | Count | % | Interpretation |
|------|-------|---|---------------|
| CASTLE (y<120 or y>920) | 123 | 38% | At enemy castle — SHOULD be attacking but sitting idle |
| BUILD (y<345 or y>695) | 121 | 37% | In enemy build zone — lost target, no fallback |
| COMBAT (y 345-695) | 80 | 25% | In combat zone — likely engaged in melee (somewhat normal) |

**Key insight**: 75% of stuck units are in enemy territory (castle + build zones) with no target. The problem is NOT pathfinding to the enemy — units get there fine. The problem is **what happens after they arrive and their initial target dies.**

---

## Specific Recommendations for A1

### Priority 1: Fix idle units in enemy territory
In `_acquire_target()`:
- If unit is in enemy half (Kingdom: y < ARENA_CENTER_Y, Horde: y > ARENA_CENTER_Y) AND `target_id == -1` for > 10 ticks → force target enemy castle
- This alone would fix 75% of the "stuck" problem

### Priority 2: Fix Horde vs Kingdom asymmetry
- Audit flow field generation for team 0 vs team 1 — ensure symmetric treatment
- Check if castle Y positions and spawn Y positions are truly mirrored
- Run a "Horde vs Kingdom" test (swap which faction is team 0) to isolate if the bias is faction-based or position-based

### Priority 3: Reduce zigzag severity
- The 20-tick stuck threshold in `_unstick_unit()` fires correctly but the nudge direction may cause oscillation
- Consider: when nudging, always nudge TOWARD the enemy castle (deterministic direction) rather than random jitter

---

## Test Files and Output

| File | Location |
|------|----------|
| Melee frames (74) | `/tmp/castle_clash_video/melee/` |
| Melee tick log | `/tmp/castle_clash_video/melee/tick_log.json` |
| Full army frames (70) | `/tmp/castle_clash_video/full_army/` |
| Full army tick log | `/tmp/castle_clash_video/full_army/tick_log.json` |
| Video test report | `/tmp/castle_clash_video/report.json` |
| This analysis | `tasks/qa-crowd-behavior-report.md` |
