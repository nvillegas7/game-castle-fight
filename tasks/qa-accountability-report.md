# QA Accountability Report - 2026-04-05 (Updated)
> **Verdict: IMPROVING but still below Kingdom Rush quality bar.**

---

## FIXED THIS SESSION BY QA (18 issues total)

### Code Audit Bugs (12)
1-12: Sell income exploit, Siege Fire formula, sprite scaling, priest behavior, card/grid deselection (x2), gold bar cap, z-ordering, castle tint, camera zoom, online button

### Visual Bugs from Screenshots (6+)
13. Terrain decorations invisible (z_index fix)
14. Audio completely silent (race condition fix)
15. Cyan water borders (WaterBase + modulate)
16. Castle HP bars overlapping
17. HUD text too small
18. Card name truncation

### Sound Overhaul
- Rewrote all 10 SFX to use metallic impacts, whooshes, multi-layer harmonics
- Added war horn for wave announcements
- Fixed music to D minor atmospheric pad
- Added saw/triangle wave oscillators

### Latest Fixes (this pass)
- Water color override in script (resistant to scene file reverts)
- Grass texture variation (60 random patches break up flat green)
- Dirt specks on combat lane (30 random specks)
- Grid line opacity reduced (0.2 → 0.1)
- Grid border thinned and faded

---

## CURRENT STATE (from latest screenshot 1:32 PM)

### What's Working
- Trees rendering on both sides
- Castle visuals at proper scale (0.7)
- Castle areas have transparent backgrounds
- HP bars positioned correctly
- Card hand well-styled with all buildings
- Gold bar clean with dark background
- Clouds drifting
- Unit sprites animating (though tiny)
- Building sprites rendering

### What Still Needs Work (Visual Agent)

1. **Ground Textures**: Grass zones are still flat ColorRects. The terrain Tileset folder has grass, dirt, and path tile PNGs — use them as TextureRects with tiling, not solid colors.

2. **Combat Lane Detail**: The brown lane needs paths, footprints, or battle scars. Kingdom Rush lanes have stone paths with wear marks.

3. **Main Menu Background**: SpecialPaper.png is covered by opaque styled panels from `_style_all_ui()`. Reduce panel opacity to let the parchment show through.

4. **Loading Screen**: Doesn't exist. Create one with SpecialPaper + Swords + loading bar.

5. **Unit Scale**: Units at ~48px are too small for mobile at 720x1280. Consider increasing CELL_SIZE or default camera zoom.

### What Still Needs Work (Mechanics Agent)
1. Unused skill parameters (Shield Wall param_2, Charge param_1) — wire them in or document why they're unused.
2. Verify starting gold=0 + income=20 + immediate tick=1 feels right for gameplay pacing.

---

## PROCESS IMPROVEMENT

Going forward, every feature merge must include:
- [ ] Screenshot proving the feature renders in-game
- [ ] Audio test confirming sounds play
- [ ] No silent error swallowing (log warnings for null checks)
- [ ] QA sign-off before marking as "done"
