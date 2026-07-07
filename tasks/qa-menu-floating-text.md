# QA Bug: Main Menu Floating Text / Layout Issues — 2026-04-11
> **Agent**: A4 | **Method**: 3x zoom crop of menu screen from video capture
> **Owner**: A2 (main_menu.gd, main_menu.tscn)

---

## Issues Found (6 floating/misplaced elements)

### 1. "Commander" header text — floating, no panel
- Top-left: avatar icon + "Commander" text rendered directly over scenic background
- No dark panel or container behind it
- Hard to read against green terrain

### 2. "New Commander" text — floating, no panel  
- Top-right: coin icon + "New Commander" text, same issue
- These are from `_build_progression_display()` or `_build_header()` in main_menu.gd

### 3. "Commander" rank progress bar — overlaps logo area
- Right side: dark progress bar with "Commando..." text bleeding into the Castle Fight logo area
- This was previously fixed (BUG-M1/M2) but has reappeared

### 4. "Classic match standard rules" text — overlaps faction description
- Behind/under the "Build towers, spawn units, destroy the enemy castle!" text
- Two text layers at similar Y position, different content
- The mode description (from T-056 fix) and the old "classic match" text are both rendering

### 5. Building preview cards — floating in logo area
- 4 miniature building cards (Barracks 50g, Archer Range 60g, etc.) rendered inside the paper/logo area
- These are from T-046 (home screen progression building cards)
- They have no clear visual separation from the logo

### 6. Overall layout feels like multiple features piled on without spatial planning
- Header, logo, building previews, mode selector, description text, BATTLE button, PLAY ONLINE — all competing for vertical space

## Why Tests Missed This

**No test inspects main menu layout.** Our test suite covers:
- Battle screen (video_test.gd)
- Unit sprites (showcase)
- Audio state (audio tests)
- Simulation logic (269 headless tests)

But ZERO tests capture and analyze the main menu for:
- Text overlap detection
- Element positioning validation
- Panel/container presence behind text
- Vertical spacing between elements

## Fix Needed (A2)

1. Remove or containerize floating "Commander" / "New Commander" header elements
2. Remove duplicate "Classic match standard rules" text (T-056 already added mode description)
3. Move building preview cards to a proper panel or remove from Battle tab
4. Ensure all text has a readable background (dark panel, paper texture, or outline)

---

## BUG-INCOME-DISPLAY: Gold income label doesn't update when gold mines placed
- **Severity**: HIGH
- **Owner**: A2 (game_arena.gd:591-601 — `_update_gold_bar()`)
- **Root cause**: Line 599 reads `players[pi].income` which is the BASE income (20g). Gold mines add a +15% compound bonus computed dynamically at income tick time (simulation.gd:318). The display never reflects this bonus — it always shows "+20/5s" even with 3 gold mines.
- **Fix**: Compute actual income in the display, matching simulation.gd:307-319:
  ```gdscript
  # Count income buildings for this player
  var pct_bonus: int = 0
  for e in GameManager.simulation.entities:
      if e.type == "building" and e.player_index == pi:
          var bd = GameManager.simulation.building_registry.get(e.building_type)
          if bd and bd.income_bonus > 0:
              pct_bonus += bd.income_bonus
  income = income * (100 + pct_bonus) / 100
  ```
- **Expected**: 0 mines → "+20/5s", 1 mine → "+23/5s", 2 mines → "+26/5s", 3 mines → "+30/5s"

---

---

## BUG-CASTLE-VFX: Attack effects render at WRONG castle position
- **Severity**: HIGH
- **Owner**: A2 (game_arena.gd:452)
- **Symptom**: When enemy units attack the player's castle (bottom, y=920), the attack projectiles and dust effects render at the ENEMY castle (top, y=70) instead.
- **Root cause**: `game_arena.gd:452` — castle Y values are **swapped**:
  ```gdscript
  # CURRENT (WRONG):
  var castle_y: float = 70.0 if hit_team == 0 else 920.0
  
  # CORRECT:
  var castle_y: float = 920.0 if hit_team == 0 else 70.0
  ```
  `hit_team` is the team being HIT. Team 0 castle is at y=920 (bottom), team 1 castle at y=70 (top). The ternary has them backwards.
- **Fix**: Swap the values on line 452. One character change.
- **Verify**: Run a battle, watch when enemy reaches player castle — attack effects should appear at the bottom castle, not the top.

---

## Test Gap to Fill (A4)

Create a menu layout test that:
1. Captures main menu at each tab
2. Checks for text overlap by sampling pixel regions where text should NOT appear
3. Verifies key elements are at expected Y positions
4. Detects orphaned labels (text with no panel behind it)
