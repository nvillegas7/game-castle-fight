# Visual Agent Notes & Workflow

## My Monitoring Checklist (check each session)
1. `tasks/qa-bug-tracker.md` — UI/UX bugs filed by QA
2. `tasks/agent-status.md` — coordination log for cross-agent messages
3. `tasks/design-*.md` — feature specs from Game Designer (look for UI/UX/aesthetic tags)
4. `tasks/visual-status.md` — my own status (keep updated)

## What I Implement
- Any new screens/pages/tabs (shop, army, settings, etc.)
- Visual effects (projectiles, heal particles, combat effects)
- New building/unit sprite integration
- UI layout changes (card hand, HUD, menus)
- Aesthetic polish (animations, transitions, visual feedback)
- Any task tagged with `[VISUAL]` or related to UI/UX

## What I DON'T Touch (other agents own)
- `core/simulation.gd` — Game Dev owns
- `data/units/*.tres`, `data/buildings/*.tres` — Game Dev owns
- Unit stats, balance, economy — Game Dev/Designer scope

## Sprite Sheet Frame Extraction
ALL Tiny Swords horizontal sprite sheets need `_extract_sprite_frame()`:
- Trees: 1536x256 (8 frames of 192x256) or 1536x192 (8 frames of 192x192)
- Bushes: 1024x128 (8 frames of 128x128)
- Water Rocks: 1024x64 (16 frames of 64x64)
- Unit sprites: handled by SpriteRegistry
- The function auto-detects frame width for both square and non-square frames

## 9-Patch Atlas Textures (DO NOT use as NinePatchRect)
BigBlueButton, BigRedButton, SpecialPaper, RegularPaper, WoodTable, Banner, Slots, Ribbons — these are 3x3 atlas sheets with transparent gaps. Use StyleBoxFlat or single-panel _Slots variants instead.
