# QA Screen Coherence Report — 2026-04-07

## Loading Screen
- Logo loads (gray background fixed, but user may still see edge artifacts)
- Loading bar animates for 3.2 seconds (extended from 1.8)
- **FIX APPLIED**: Missing `special_paper_720x400.png` no longer throws error (guarded with ResourceLoader.exists)
- **ISSUE**: Loading screen scenic background builds fine but paper texture is missing from assembled assets

## Main Menu
- **FIX APPLIED**: Redundant "CASTLE FIGHT" title text hidden — logo already shows the name
- Faction buttons visible (Kingdom blue, Horde red)
- Mode selector at y=500 (no longer overlaps faction buttons)
- Card hand area dark/styled
- Tab bar at bottom

## Battle Arena
- Trees in combat zone + margins
- Both castles visible at 1.0x zoom
- HUD readable (Gold, Time, HP)
- Card hand shows all buildings
- **ISSUE**: Zigzagging footmen (13 detected) — combat flow field Y-reversals around trees

## Victory Screen
- "VICTORY!" text styled with gold color and outline
- Ribbon texture behind title (ribbon_yellow_500.png)
- Stat cards with warm brown bg (lightened from black)
- Buttons styled ("PLAY AGAIN" / "MAIN MENU")
- Trophy count-up animation
- **REMAINING ISSUE**: Still plain compared to Kingdom Rush — needs particle effects, MVP showcase, more visual celebration

## Cross-Screen Coherence
- **Color palette**: Consistent warm brown/gold/green across all screens
- **Font styling**: Gold with dark outline used throughout (consistent)
- **Art style**: Tiny Swords pixel art on arena, but menu/end screens are mostly programmatic (StyleBoxFlat) — mixed visual language
- **Transitions**: Loading → Menu is abrupt scene change. Menu → Battle has no transition. Battle → Victory overlay fades in.

## Filed Issues
1. `special_paper_720x400.png` missing from assets (error guarded but texture doesn't render)
2. 13 zigzagging footmen per match from flow field pathing
3. End screen needs more visual polish (particles, MVP unit sprite, animated stats)
