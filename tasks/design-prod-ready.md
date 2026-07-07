# Phase 3: Production Ready — Aesthetics + Balance + Polish
> **Author**: A0 (Lead Game Designer) | **Date**: 2026-04-14
> **Goal**: Ship-ready single-player experience with satisfying match pacing

---

## Current Status: 81/97 tasks DONE

### Remaining open items (11 tasks):
- BUG-DESYNC1: Multiplayer desync (A1, IN_PROGRESS)
- T-085: Mirror perspective (A2, READY)
- T-084: Champion→Mage data (A5, READY — just unblocked)
- T-068: Army tab single faction (A2, READY — just unblocked)
- T-074: Terrain obstacles (A5, QA_FAIL — needs permanent tests)
- T-078: Terrain obstacle test suite (A4, READY)
- T-018/T-032/T-080: Tutorial + multiplayer testing (IN_PROGRESS)
- T-033/T-035: Multiplayer desync test + itch.io deploy (BLOCKED)

### New tasks needed for production readiness:

---

## 1. LOGO FINALIZATION

A6 generated a logo (T-087, DONE) using Tiny Swords crossed swords + blue ribbon + MoRk DuNgEoN font. But is it final? User wants to "finalize" it.

**Action**: User reviews current logo at `assets/sprites/ui/logo.png`. If changes needed, dispatch to A6 with specific feedback.

---

## 2. CASTLE SIEGE PACING — "Boring to watch castle get sieged forever"

**The problem**: When one player is losing badly, the endgame drags. Lots of enemy units hacking at the castle, no way to come back, but the castle takes forever to die because it has 10,000 HP.

### Analysis of the 3 proposed solutions:

**Option 1: One-time castle skill (panic button)**
A powerful AoE that wipes nearby enemies. Used once per game.
- **Pros**: Dramatic comeback moment, creates tension ("did they use it yet?"), skill ceiling (timing matters)
- **Cons**: Delays the inevitable if opponent has sustained army advantage, feels cheap if it negates 2 minutes of play
- **Verdict**: Good as a SUPPLEMENT, not a fix on its own

**Option 2: Lower castle HP**
Current: 10,000 HP. That's a LOT.
- A Footman does 10 dmg × 50% (Physical vs Fortified) / (1 + 0×0.06) = 5 effective damage per hit, every 10 ticks (1s)
- Time for 1 Footman to solo a castle: 10000/5 = 2000 hits = 2000 seconds = **33 minutes**
- Even 10 Footmen: **3.3 minutes** of constant siege
- With Siege units (Catapult, 35 dmg × 150% = 52.5 effective): 10000/52.5 = 190 hits × 25 ticks = 4750 ticks = **475 seconds = 8 minutes**
- **Proposed**: 5000 HP (halve it). Same 10 Footmen = 1.6 min, Catapult = 4 min.
- **Verdict**: YES — 10K is too much. 5000 creates faster resolution once a side is clearly winning.

**Option 3: Build behind/beside castle**
Allow building placement in the castle zone (currently blocked).
- **Pros**: Defensive depth, towers behind castle add last-stand defense, mazing around castle creates strategy
- **Cons**: Complexity — units that prioritize castle might ignore behind-castle buildings, pathfinding near castle needs care
- **Verdict**: YES — but with caveat: units still prioritize castle. Buildings behind/beside castle are purely defensive (towers shoot attackers, spawners produce reinforcements from deep position).

### Recommended implementation:

**All three, but tuned:**

1. **Castle Wrath (one-time skill)**: When castle HP drops below 30%, a "CASTLE WRATH" button appears. One-time use. Deals 200 magic damage to ALL enemy units within 5 cells of the castle. Kills squishy units (archers, mages), heavily damages melee, siege might survive. Creates a dramatic "the castle fights back!" moment.

2. **Castle HP: 10000 → 5000**: Matches are faster to resolve. A dominant army takes the castle in 2-3 minutes instead of 5-8.

3. **Expand build zone by 1-2 rows behind castle**: Currently castle sits at the edge of the build zone. Add 1-2 rows behind it. Players can build Guard Towers or spawner buildings there. Enemy units still prioritize the castle (nearest enemy target), so behind-castle buildings aren't attacked first — they provide support fire.

---

## 3. SCREEN POLISH (Aesthetics prod-ready)

### Loading screen:
- Logo should be prominent and centered (verify current state)
- Progress bar should fill smoothly
- "Castle Fight" title in MoRk DuNgEoN font

### Main menu:
- Battle tab: clean, yellow BATTLE button dominant, single faction shown
- Army tab: show current unit roster with stats (T-068, needs Mage not Champion)
- Settings: volume sliders working
- All tabs have content (no "Coming Soon")

### Battle screen:
- Terrain: tiled textures (verify post T-060 work)
- Effects: explosions, fire, dust all rendering
- HUD: clean gold bar, castle HP bars, wave timer
- Card hand: no text overlap (T-073 fix)

### End screen:
- Victory/defeat celebration (T-048, DONE)
- MVP unit, stats, trophy animation

---

## 4. BALANCE TUNING

### Current issues identified from playtesting:
1. Castle HP too high (addressed above — 10K→5K)
2. Champion's Hall still shows instead of Mage Tower (T-084 blocks this)
3. Need to verify RPS triangle feels right after T-079 balance pass (Footman Light armor, Ballista Siege attack)
4. Wall durability vs cost — did T-079 calibration make walls worth building?

### Balance verification plan:
- Run 100 AI-vs-AI matches after T-084 (Mage) is integrated
- Verify win rate 45-55%
- Manual playtest: does the Archer→Footman→Lancer→Mage counter-play feel real?
- Verify walls survive long enough to be strategic
