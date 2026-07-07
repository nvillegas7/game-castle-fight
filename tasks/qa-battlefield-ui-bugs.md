# QA Battlefield UI Visual Audit — 2026-04-11
> **Agent**: A4 | **Method**: Video capture at 10fps + 3x zoom crop of card hand area
> **Command**: `--write-movie + --videotest --scenario full_army`

---

## BUG-CARD1: Gold cost badge overlaps building name text [A2]
- **Severity**: HIGH
- **Status**: CONFIRMED
- **Owner**: A2 (card_hand.gd)
- **Evidence**: 3x zoom crops of card hand area. Every card shows name text partially hidden behind the gold cost badge.
- **Root cause** (`card_hand.gd:333-378`):
  - Card layout is 84×130px
  - Icon: y=8 to ~60
  - Name: y=68 (font 9-11px)
  - Type text: y=81 (name_y + 13)
  - Stats: y=96 (name_y + 28)
  - **Cost badge: y=104** (h - badge_h - 4 = 130 - 22 - 4)
  - Stats at y=96 and cost badge at y=104 have only **8px gap** — they overlap
  - On compressed cards (14 cards in 2 rows), card height shrinks further, making overlap worse
- **Visible on**: "Archer Range" shows "A r...", "Priest Temple" shows "P r i...", all names partially hidden
- **Fix suggestions**:
  1. Move cost badge to TOP of card (overlay on icon corner) instead of bottom — frees vertical space for name/stats
  2. Or: reduce icon size to make more room below for text
  3. Or: put name ABOVE icon, cost below
  4. Or: increase card height from 130 to 150px (may require reducing card rows)
- **Verify**: Run `--videotest --scenario full_army`, crop card hand at 3x zoom, all building names should be fully readable without any overlap from cost badge

---

## SELL BUTTON — Code Review (needs manual verification)
- **Status**: CODE LOOKS CORRECT — needs manual play-test
- **Sell flow** (`building_grid.gd`):
  1. **Left tap** on owned building (no card selected) → `_try_show_radial()` (line 118) → shows 3-button radial menu (sell/info/cancel) with pop-out animation
  2. **Sell button** in radial → `_on_radial_action("sell")` → `Command.sell_building()` sent via NetworkManager
  3. **Right-click** shortcut → `_try_sell_building()` (line 93) → direct sell command
  4. **Refund**: `bd.gold_cost * bd.sell_refund_percent / 100` shown on sell button tooltip
- **Potential issues to test manually**:
  - Does the radial menu appear when tapping an owned building? (visual test can't trigger taps)
  - Does the sell command actually remove the building and add gold?
  - Does the grid cell free up for new placement after selling?
  - Does the sell SFX play?
- **How to verify**: Play the game manually (`godot --path castle_clash`), place a building, tap it, verify radial appears, tap sell, verify building removed and gold increases
