# Latest QA Bug Report — 2026-04-07

## BUG: Units zigzag even without trees [A1 - CRITICAL]
- **Observed**: User placed barracks in the middle, units zigzag with NO trees nearby
- **Root cause**: The combat flow field (`combat_flow_fields`) is being used for ALL melee movement in the combat zone (line ~1524 in simulation.gd). Even when no trees exist in the unit's path, the flow field may have diagonal directions from distant tree obstacles, causing unnecessary detours.
- **Fix needed**: Only use combat flow field when unit is within 2-3 cells of a tree obstacle. Otherwise use direct chase (straight line to target). Or rebuild the flow field to only affect cells adjacent to actual obstacles.
- **File**: `core/simulation.gd` — `_move_unit()` combat zone flow field section

## BUG: Units attack castle from side instead of front [A1 - HIGH]
- **Observed**: Melee units reach enemy castle but attack from the sides, not the front face
- **Root cause**: Castle spread code distributes units based on X position relative to castle center. Units approaching from center-left get pushed LEFT, center-right get pushed RIGHT. Only the narrow center third attacks from the front.
- **Fix needed**: Wider center band — most units should attack from front (the march direction), with only extreme flankers going to sides.
- **File**: `core/simulation.gd` — castle perimeter spread code

## BUG: Missing assembled UI assets cause errors [A2 - HIGH]
- **Files missing**: `wood_table_720x240.png`, `wood_table_720x50.png`, `special_paper_720x400.png`
- **Fixed**: Added `ResourceLoader.exists()` guards so errors no longer throw. But the textures are still missing — UI falls back to non-textured.
- **A2 needs to**: Create these assembled assets or remove references.

## BUG: Redundant "CASTLE FIGHT" title on main menu [FIXED]
- Title text hidden since logo already shows game name.
