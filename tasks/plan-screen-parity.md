# Plan — Screen Parity Sweep (KR quality, Tiny Swords assets)

**Requested 2026-07-10.** Every screen readable, cohesive, Apple-HIG-compliant, no
cropped/floating assets, palette cohesive with our art — including the in-game HUD.
Evidence: 5 parallel audit agents (wf_878bcc29), each grading a screen domain against
KR production quality with pixel-measured findings. **PLAN ONLY — approved scope TBD.**

## Audit grades (today)

| Screen | Grade | Verdict in one line |
|--------|-------|---------------------|
| Loading + Battle tab | C+ | Best screens; killed by invisible tab labels, dual CTAs, flat-green menu "sky" |
| Game HUD | C+ | Strong ribbon/tray art; illegible HP pills, mushy font sizes, tiny ability buttons, no gold fill bar |
| End screen | C+ | Right structure; HUD bleeds through behind it, low-contrast VICTORY, sub-44pt buttons |
| Shop + Army | C− | Buildings where units should be, navy programmer panels, zero shop affordances |
| Social + Settings | D+ | Godot-default gray sliders, 64–75% dead void, destructive action is the visual primary |

## Cross-cutting root causes (fix once, benefit everywhere)

1. **No shared panel kit.** Every tab hand-rolls `StyleBoxFlat` → cold-navy/flat-gray
   programmer boxes off the Tiny Swords palette (Army/Social cards RGB(29,42,69)!).
   `assets/sprites/ui/assembled/` is partly missing; audits reference 9-patch paths that
   must be verified/created from the pack (Papers/RegularPaper, woodtable, ribbons, BigBar).
2. **Pixel-font size chaos.** Pixel Operator Bold is 16px-native; overrides at
   12/13/14/15/18px render mushy glyphs ("LOCKED"→"LOCKCD"). Rule: quantize to 16/32.
3. **Void backgrounds.** All menu tabs sit on near-black brown (39,29,20) with content
   hugging the top — 60–75% empty. KR fills with textured parchment + expanded content.
4. **Touch targets below HIG floor** (80px design ≈ 44pt): ability buttons 64×38,
   cards 84w, end-screen buttons ~43, sliders ~40 rows.
5. **Tab-bar labels 2.1:1 contrast** — the most-used navigation is nearly invisible.
6. **Two rendering languages mixed**: vector capsules/AA polygons/flat rects amid pixel
   art (HP pills, end-screen stars, confetti rects, banners).

## Work packages (sequenced by player impact)

### P0 — Foundation: `ui_style.gd` + asset kit *(prereq for all; = backlog 2.3 TODO)*
- Inventory + assemble the 9-patch kit from the Tiny Swords UI pack (A6-style, PIL):
  paper panel, wood table panel, dark ribbon header, slider track/grabber, pixel star.
  Verify which `assets/sprites/ui/ninepatch|assembled/*` paths actually exist first
  (lessons: inspect assets before coding against them).
- Shared `ui_style.gd`: `paper_panel()`, `wood_panel()`, `tab_title()`, `stat_chip()`,
  themed slider, font-size constants (16/32 only). All later packages consume it.

### P1 — Game HUD *(the screen players stare at longest)*
- Castle HP pills: font 12→16, pills enlarged, StyleBoxTexture from BigBar assets
  (kills the vector-capsule clash). `hud.gd:13-14,72-104`
- Quantize every HUD font size to 16/32 (`hud.gd:33`, `card_hand.gd` ×8 sites).
- Ability + Castle Wrath buttons 64×38 → **88×88** square with icon (KR hero-power
  style). `game_arena.gd:982,1097`
- Gold bar: restore elixir-style fill (BigBar base+fill) + cheapest-card affordability
  marker (backlog 3.3). `game_arena.gd:810,1312`
- Cards: CARD_W 84→88 gap 6; wood StyleBoxTexture (match tray); locked = grayscale icon
  + padlock, drop red "LOCKED" text; tier dots → rimmed 5px or mini banners; tower/spawner
  type-label contrast ≥4.5:1. `card_hand.gd:12-14,233,362-434`
- HUDBg near-black slab → transparent (ribbon carries the strip). `game_arena.tscn:172`

### P2 — Menu shell + Battle tab *(shared chrome: header, tab bar, background)*
- Tab labels: 2.1:1 → ~8:1 (cream + 2px outline, size 13→16, icon alpha 0.85). `main_menu.tscn:692+`
- Header/TabBar ColorRects → wood 9-patch; trophy icon = actual trophy (not shield). 
- ONE primary CTA: keep BATTLE ribbon; demote PLAY ONLINE to a ≥80px secondary chip
  clustered 24px under the ribbon (recommend; alt: fold online into mode selector). `main_menu.gd:104-117`
- Menu "sky": flat green wall → port the loading screen's blue→haze→meadow gradient
  (fixes clouds + loading→menu palette flash). `main_menu.gd:689`
- Island slab: side-edge cliff tiles on end columns + foam wrapping corners; water band
  runs behind lower UI instead of hard seam. `loading_screen.gd:564`, `main_menu.gd:871`
- BATTLE label → dark-on-tan (ribbon convention). Resolves quarantined BUG-47/49
  detectors (rewrite two-phase per backlog).

### P3 — End screen
- **Takeover**: hide HUD/gold bar/card hand on show; restore on replay (backlog 3.5). `end_screen.gd:37`
- VICTORY! contrast: ribbon modulate 1.0 + dark outline (2.46:1 → ≥3:1). `end_screen.gd:116`
- Buttons ≥80px (PLAY AGAIN 96): `game_arena.tscn:397+`
- Backdrop flat panel → wood 9-patch; stat text 13→16, taller stat cards.
- Celebration: confetti 8–16px warm-palette (from 4–8px dust), pixel-art stars
  (replace AA vector polygons).

### P4 — Army + Shop tabs
- Army rows show **unit idle sprites** (exist in assets/sprites/units/), not spawner
  buildings (backlog 3.6). `main_menu.gd:1777`
- De-spreadsheet: one 16px middot stat line (HP 100 · DMG 10 · …), skill on line 2;
  warm wood cards (kill navy); tier headers on dark ribbons; trailing spacer (last card
  clips into tab bar). `main_menu.gd:1742-1817`
- Shop: gold-balance chip; cost/Owned/Equipped badges + selected ring (state currently
  invisible at Δ6 RGB); confirm-before-buy; center the grid (22px vs 66px margins). `main_menu.gd:491-543`

### P5 — Social + Settings tabs
- Themed sliders (track/grabber from bar assets, ≥80px rows). `main_menu.gd:2042-2076`
- Navy cards → paper panels; Settings grouped into titled AUDIO/GAME/ABOUT panels.
- **Demote "Reset All Progress"** to low-emphasis outline style at the bottom (it is
  currently the brightest element — destructive action as visual primary). `main_menu.gd:2013`
- Social: MATCH RECORD as 3 stat chips w/ icons; FRIENDS empty state with illustration.
- Kill the void: expand content, unify tab title style (shared helper).

## Verification (per screen, detector-first where feasible)
- New pixel detectors added WITH each package: tab-label contrast; end-screen
  bleed-through (card tray pixels while results shown); no-cold-navy on menu tabs;
  HUD font-size static scan (already exists — tighten to quantization rule);
  touch-target static asserts (≥80px on named controls).
- Full capture + eyeball vs the audit findings each package; L0 gate stays green
  (all UI-layer — sim untouched; golden unaffected).
- Each package = one branch → gate → merge → deploy (screens improve incrementally live).

## What we will NOT touch
- Sim/gameplay, network, arena terrain (all just stabilized).
- The strengths the audits flagged: loading gradient/parallax, wooden progress bar,
  ribbon CTAs, tray wood texture, end-screen structure, active-tab treatment.

## Decisions — RESOLVED by user 2026-07-10
1. **P2 CTA shape**: ✅ demote PLAY ONLINE to a ≥80px secondary chip clustered 24px under
   the BATTLE ribbon (the "recommended" option). Do NOT fold into the mode selector.
2. **Sequencing**: ✅ P0→P1→P2→P3→P4→P5 in order, by player impact.
3. **Scope**: ✅ ALL packages P0–P5. Nothing cut.

Execution model: fresh session per `/handoff`; one package = one branch → detector-first
where feasible → `bash tests/run_all.sh` gate green → merge → `./build.sh` deploy → next
package. Verify each screen's captures against the audit findings (wf_878bcc29) before merge.
