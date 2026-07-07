# Feature Spec: Tutorial System (T-011, T-012, T-013)
> **Author**: A0 (Game Designer) | **Date**: 2026-04-05
> **References**: Clash Royale tutorial flow, Kingdom Rush tutorial

---

## Goal

First-time players must understand the game within 60 seconds without reading any docs. The tutorial should feel like part of the game, not a separate mode.

## Player Journey (3 Steps)

### Step 1: "Place Your First Building" (15s)
**Trigger**: First ever match launch (PlayerData.games_played == 0)

**Screen state**: Match is paused. Player has 50g. AI is paused.

**UI overlay**:
- Dark semi-transparent overlay (alpha 0.6) covers everything EXCEPT the card hand
- Pulsing golden arrow points DOWN at the cheapest building card (Barracks/War Camp)
- Text bubble above cards: **"Tap a card to place a building!"**
- "Skip Tutorial" button in top-right corner (small, subtle)

**On card select**:
- Overlay shifts: now highlights the player's build zone (bottom grid)
- Arrow points to center of build zone
- Text updates: **"Tap the grid to place it!"**

**On building placed**:
- Celebration effect (gold sparkles around building)
- Text: **"Nice! Buildings spawn units that fight for you."**
- "Got it!" button appears
- On tap: advance to Step 2

### Step 2: "Earn Gold, Build More" (20s)
**Screen state**: Match resumes. Income ticks start. AI starts building (slowly).

**UI overlay**:
- Arrow points to gold bar
- Text: **"You earn gold every 5 seconds. Build more to overwhelm your enemy!"**
- Overlay lifts after 10s or when player places second building (whichever first)
- Brief flash on gold bar each income tick during tutorial

### Step 3: "Destroy the Enemy Castle" (ongoing)
**Screen state**: Normal match, no overlay.

**One-time tooltip** (appears after first wave of units reaches combat):
- Small banner at top: **"Your units attack automatically. Destroy the red castle to win!"**
- Auto-dismisses after 5s
- Arrow briefly points to enemy castle

**Tutorial end**: After Step 3 tooltip dismisses, tutorial is complete. `PlayerData.tutorial_complete = true`.

## Technical Requirements

### A2 (UI/UX): Tutorial Overlay System
- New scene: `scenes/ui/tutorial.tscn`
- New script: `scripts/ui/tutorial.gd`
- CanvasLayer (layer 10, above game but below pause menu)
- Dark panel with holes (use `Light2D` masking or manually position clear rectangles)
- Arrow node: animated Sprite2D that bobs up/down (sin wave, 2px amplitude)
- Text bubble: Panel with Label, rounded corners, team-colored border
- "Got it!" button: BigBlueButton texture
- Step state machine: STEP_1_CARD -> STEP_1_PLACE -> STEP_2 -> STEP_3 -> COMPLETE
- Listens to EventBus signals: building_placed, gold_changed, wave_spawned

### A1 (Game Dev): Simulation Hooks
- `GameManager.tutorial_mode: bool` flag
- When tutorial_mode and step == 1:
  - Set starting gold to 50 (override normal 0)
  - Pause AI (don't process AI commands)
  - Pause wave timer
- When tutorial step advances to 2:
  - Resume AI (with slow build rate: 1 building per 15s instead of normal)
  - Resume wave/income timers
- When tutorial completes (step 3 done):
  - AI returns to normal speed
  - No further simulation modifications
- Emit `tutorial_step_changed(step: int)` signal via EventBus

### A2 (UI): PlayerData Integration
- `PlayerData.tutorial_complete: bool` (default false, saved to disk)
- `PlayerData.tutorial_step: int` (0-3, for resume if app closes mid-tutorial)
- Settings tab: "Replay Tutorial" button resets `tutorial_complete = false`

## Design Rationale
- **3 steps, not 5+**: Mobile players abandon long tutorials. Teach minimum viable knowledge.
- **Dark overlay with highlights**: Clash Royale pattern — proven to guide attention.
- **Immediate action**: Step 1 gives gold and asks player to DO something, not read.
- **Progressive reveal**: Don't explain walls, upgrades, skills. Let players discover those.
- **Skippable**: Experienced players (from watching gameplay) should not be forced through it.

## Constraints
- Tutorial must NOT break deterministic simulation (no special RNG paths)
- Tutorial state is purely a visual/gameplay-speed modifier, not a different game mode
- Must work in both offline and online mode (online: tutorial is local-only, opponent plays normally)
