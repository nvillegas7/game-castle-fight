# QA Menu Layout Bugs — 2026-04-07 (From Screenshot)

## BUG-M1: "Soldier" rank bar floating with no container [A2]
- Top-right area shows "Soldier" text + dark progress bar overlapping scenic background
- This is from T-046 (arena banner/trophy progression)
- Needs proper positioning within a styled panel, not floating over terrain
- File: `scripts/ui/main_menu.gd` — arena banner positioning

## BUG-M2: Player stats text floating below BATTLE button [A2]
- "Soldier | 4W / 1L" text has no background, barely readable against terrain
- Needs a dark semi-transparent panel behind it or integrate into the header
- File: `scripts/ui/main_menu.gd` — status label styling

## BUG-M3: Mode selector overlaps faction description [A2]
- Standard/Blitz/Mirror buttons at y=500 overlap with faction description text
- The faction description text sits below faction buttons and the mode buttons land on top
- Fix: move mode selector further down OR move faction description above faction buttons
- File: `scripts/ui/main_menu.gd` — `_build_mode_selector()` position

## BUG-M4: Multiple text layers overlap in battle panel center [A2]
- "Choose your faction" text, faction description, and mode buttons all fighting for space
- The vertical layout needs proper spacing with no overlaps
- Fix: use VBoxContainer or explicit Y positioning with proper gaps

## Overall: Menu layout needs a spacing pass to prevent overlaps at 720x1280.
