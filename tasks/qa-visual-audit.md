# QA Visual Audit — Latest Build (2026-04-05 Evening)
> AI-vs-AI autotest, 30 frames, 60 seconds of gameplay

## PREVIOUS BUGS — STATUS

| Bug | Status | Evidence |
|-----|--------|----------|
| Tree clipping at arena edges | **FIXED** | Trees properly bounded Y=140-920, no chopping visible |
| Tree overlapping | **FIXED** | 80px spacing prevents overlaps |
| HUD text unreadable | **FIXED** | "Gold: 40 Time 0:10" clearly visible at 18px |
| Card hand overflow | **FIXED** | 8 cards fit at 84px width |
| Castle HP bar overlap | **FIXED** | Bars positioned above/below castle areas |
| Building on castle | **FIXED** | Autotest places wall at (4,1) not last rows |
| Unit visibility | **IMPROVED** | 0.30 scale + 1.2x zoom, units distinguishable |
| Terrain decorations | **WORKING** | Trees, bushes, rocks, stumps all rendering |
| Combat engagement | **WORKING** | Melee units walk close, ranged stay back |
| Explosion/dust/fire effects | **ADDED by visual agent** | castle_visual.gd now uses sprite fire |

## CURRENT VISUAL ISSUES (For Visual Agent)

### 1. Castle Areas Asymmetric [OPEN]
- Enemy castle area: y=55-120 (65px tall)
- Player castle area: y=940-1005 (65px tall)
- But distance to combat zone differs: enemy=225px gap, player=245px gap
- **Fix**: Either center the combat zone or adjust castle positions for equal spacing

### 2. Wall Sprite Not Ideal [MINOR]
- Walls use "House1" sprite mapping (a full house) for a 1x1 defensive block
- At 28px, the house sprite is compressed and doesn't look like a wall
- **Recommend**: Use a simpler sprite or tiled fence texture for walls

### 3. Loading/Transition Screen Missing [OPEN]
- Frame 0 captures a blank dark screen during scene transition
- Should show a loading indicator or splash screen

### 4. Gold Bar Text Partially Occluded at 1.2x Zoom [MINOR]
- "Gold: 40 (+20/5s)" text is at the edge of the visible area
- At 1.2x zoom the viewport clips earlier, though CanvasLayer compensates

### 5. No Visual Feedback for Building Placement Success [MINOR]
- When a building is placed, no dust puff or construction animation plays
- The new dust effect exists (`Effects.create_dust()`) but isn't hooked into building placement

## COMBAT OBSERVATIONS (For Mechanics Agent)

### 6. Units Behind Own Buildings Get Temporarily Stuck [KNOWN]
- 2 enemy grunts at y=195 and y=265 with no target for several ticks
- The `_unstick_unit()` system should resolve this after 30 ticks (3 seconds)
- Not a critical issue — they eventually march forward

### 7. Enemy Grunts Reaching Player Build Zone [BY DESIGN]
- 3 grunts at y=708-733 attacking player buildings
- This is correct behavior — units march to enemy castle, engage buildings en route
- The unit-targeting priority (units > buildings) would make this less frequent

### 8. Both Castles at 10000 HP After 60 Seconds [ACCEPTABLE]
- User confirmed pacing is OK — combat builds gradually
- First engagement around t=30s, sustained combat by t=45s

## OVERALL GAME EXPERIENCE ASSESSMENT

**What looks good:**
- Arena has life with trees, bushes, rocks, stumps decorating the zones
- Combat is visible and engaging at 1.2x zoom
- HUD and card hand are clean and readable
- Color palette is warm and consistent
- Building sprites are identifiable
- The Tiny Swords art style is working

**What needs improvement:**
- Ground textures still flat (green/brown ColorRects, no tile variation)
- Castle visuals too small/subtle — could be more prominent
- No dust/explosion effects visible during combat (may need game_arena hookup)
- Main menu still dark/plain background
- No loading screen during scene transition

**Quality level:** 6/10 — Good foundation, polished basics, but Kingdom Rush level (9/10) requires: textured ground, prominent castles, rich particle effects, and polished UI transitions.
