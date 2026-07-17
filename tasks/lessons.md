# Lessons Learned

## 2026-04-05: Don't claim "fixed" without tracing through actual execution

**Pattern**: I changed attack_range from 1→2 cells and claimed melee was fixed, but the actual root cause was that ±2 cell spawn jitter made the 2D aggro distance too large for melee to detect enemies at different X positions. I also missed that the visual sync ran at 60fps while simulation ticks at 10/sec, causing walk animation to flicker.

**Rule**: Before claiming a fix, trace through the FULL execution path:
1. What are the actual pixel values after FP conversion?
2. How does the visual layer read simulation state? At what frequency?
3. Does the fix work at the extremes (max jitter + max X offset)?

**Rule**: When simulation and visual layers run at different rates, never infer state (like "is_moving") from frame-to-frame deltas. Use an authoritative flag from the simulation.

## 2026-04-05: Fixed-point math — always verify with actual numbers

**Pattern**: I assumed attack_range and aggro_range values were reasonable without computing the actual pixel distances after FP.from_int(cells * CELL_SIZE_PX). The Q16.16 format means FP.from_int(140) = 9,175,040, and distance checks involve squaring these values.

**Rule**: When setting game balance values that involve distance, compute the actual pixel values: `range_px = cells * CELL_SIZE_PX`. Then verify: can two units at maximum X offset still detect each other?

## 2026-04-05: Always compute ranges relative to the arena size

**Pattern**: Set archer attack_range to 6 cells (168px) in a 350px combat zone. Archers could shoot from nearly their spawn point without advancing. The "melee gap" the user saw was actually ranged units forming two stationary lines near spawn while melee fought invisibly in a thin strip in the middle.

**Rule**: Attack and aggro ranges must be evaluated RELATIVE to the combat zone dimensions. If attack_range > 40% of combat zone height, ranged units barely need to move. For a 350px zone: max ranged attack_range should be ~4 cells (112px = 32% of zone). Always compute: "how far from spawn does this unit stop?"

**Rule**: Add debug prints FIRST, read the output, THEN fix. Don't guess at root causes across multiple iterations.

## 2026-04-05: FP.sqrt_fp was broken for all real-world distances

**Pattern**: `sqrt_fp` used 6 Newton iterations starting from `val >> 1`. For distance-squared values like 2.3 billion (typical for 190px distances), the initial guess was 77 TRILLION but the answer was 12 MILLION. After 6 halvings: 77T→1.2T — still 100,000x too large. This made `move_delta = speed / dist ≈ 0`, so ALL units were effectively frozen.

**Root cause**: The initial guess `val >> 1` is catastrophically bad for large inputs. For a 48-bit `val`, the guess is ~2^47 but the answer is ~2^23. Need ~24 halvings just to reach the right magnitude, leaving zero iterations for refinement.

**Fix**: Use bit-length to compute initial guess: `1 << (bit_length(val) / 2)`. This starts within 2x of the answer. Newton converges quadratically from there — 4-5 iterations suffice.

**Rule**: ALWAYS test math library functions with actual game-scale values, not just small test cases. A sqrt that works for `sqrt(4) = 2` can catastrophically fail for `sqrt(2,000,000,000)`.

## 2026-04-08: Never claim UI fixes work without pixel-level verification

**Pattern**: Changed TextureRect's `expand_mode` from `EXPAND_FIT_WIDTH` to `EXPAND_IGNORE_SIZE` and claimed "SpecialPaper now properly wraps the logo." Looked at small screenshot thumbnail and declared it fixed. The paper was actually still stretching to x=597 (438px) instead of x=565 (410px). Wasted 3+ iterations on the same bug.

**Root cause**: Godot's TextureRect `size` property gets overridden by the layout system regardless of `expand_mode` or `custom_minimum_size` settings. TextureRect is unreliable for precise sizing inside Control trees.

**Fix**: Use `Sprite2D` with explicit `scale = target_px / texture_size` instead of TextureRect when exact pixel dimensions matter. Sprite2D doesn't participate in Control layout, so its scale/position are always respected.

**Rule — UI verification protocol**:
1. **Never eyeball small screenshots** — always pixel-scan at expected boundary coordinates
2. **Compare inside vs outside** — scan the same x at y-above-element and y-inside-element. If colors match, the element isn't there
3. **Watch for scenic elements** (buildings, clouds, trees) that create false positives at the same coordinates
4. **Verify BEFORE reporting to user** — run the pixel scan first, report the measured width vs expected width
5. **For any Control node sizing issue**: try Sprite2D first. TextureRect expand modes have multiple footguns:
   - `EXPAND_IGNORE_SIZE` still gets overridden by parent layout
   - `EXPAND_FIT_WIDTH` uses native aspect ratio to compute height
   - `EXPAND_KEEP_SIZE` forces minimum size to texture size
   - Sprite2D with `scale = target / texture.get_size()` is the only reliable method

## 2026-04-18: Static analyzers ≠ visual verification — pixel-scan or it didn't ship

**Pattern**: Marked BUG-43 (loading bar 3-segment) and BUG-41 (mobile readability) FIXED + VERIFIED based on (a) re-running `test_screen_layout.gd` static analyzer that PASSED, and (b) eyeballing a wrong-coordinate crop (`y=580` hit tree area, not the actual bar at `y=900`). User playtest immediately re-flagged both bugs. My PASS verdicts were wrong on both counts.

**Root cause**: Two compounding mistakes:
1. **Wrong-coordinate crop** — used a guessed Y position instead of programmatically scanning the screenshot for the bar's actual location. Result: cropped a green field of trees and concluded the bar "looked fine."
2. **Heuristic test misread for ground truth** — `test_screen_layout.gd` checks proxy signals (child count ≤ 6, font_size ≥ 12) but cannot detect the actual visual artifact (3 detached planks rendered by a single NinePatchRect with bad region_rect). When the proxy passes the actual bug can still be present.

**Rule — verification protocol for visual bugs**:
1. **Never trust a static analyzer alone for visual bugs.** Heuristics catch CONSTRUCTION patterns; pixel scans catch RENDERING outcomes.
2. **Programmatically locate the element before cropping.** Use a numpy/PIL scan: `for y in range(...): count_pixels_matching(palette)` to find the actual Y position of the bar / panel / text. Don't guess Y from memory of a previous capture.
3. **For any visual bug regression test, write a PIXEL-LEVEL check, not just a code-pattern check.** Example: BUG-43 is now caught by sampling y=920 of `loading_000.png` and counting horizontal "wood-color" runs — exactly 1 = continuous, 2+ = broken. If the heuristic check passes but the pixel check fails, the pixel check wins.
4. **Low-contrast text needs alpha + size + outline triangulation.** `font_size >= 12` alone isn't readable on busy backgrounds. Real readability rule: `(size >= 14) OR (alpha >= 0.95) OR (outline_size > 0)`. Anything else gets flagged.
5. **Re-run user playtest before claiming victory.** If the user previously reported a bug, ASSUME my fix is wrong until I have user confirmation OR a new pixel-level test that explicitly fails on the old build and passes on the new one.

## 2026-04-18 (round 2): The QA gate must be a hard gate, not a rubber stamp

**Pattern**: User reported the same 4 main-menu visual bugs (dust line, tree-clip, fence row, partial ribbons) across multiple QA iterations. I had filed BUG-46/47/48/49 but they sat OPEN with no automated test guarding them. When A2 worked on adjacent UI, my "QA pass" was based on heuristic checks that didn't open the rendered PNG. User: "you're the last checkpoint in verifying fixes — I expect it to be really fixed when it passes through you as QA."

**Root cause**: I had no enforcement mechanism. Bugs lived as markdown comments in `qa-bug-tracker.md`. There was no contract that a bug COULD NOT be marked DONE without a passing test. Heuristic detectors (font size ≥ 12, child count ≤ 6) caught CONSTRUCTION patterns but missed RENDERING outcomes.

**The new gate** (now in CLAUDE.md A4 role section):

1. **Detector-first bug filing**: When user reports a visual bug, write the pixel detector BEFORE filing the bug. Run it on the current build — it must fail. Reference the detector function name in the bug entry under `**Detector**:`.
2. **No DONE without detector PASS**: A visual bug cannot move QA_REVIEW → DONE unless `godot --headless -s tests/test_screen_layout.gd` reports PASS for the named detector. Cite the test output line in the dispatch coordination log.
3. **Loop fire smoke test**: Every /loop fire runs the full screen-layout suite. Any newly-failing detector means a previously-DONE bug regressed → re-open immediately, don't wait for user.
4. **Calibration is mandatory**: Programmatically scan the capture to find the bug's ACTUAL coordinates (don't guess from memory). Document calibration date and image resolution in the detector docstring.

**Detector pattern** (in `tests/test_screen_layout.gd`):
```gdscript
func _check_xxx() -> void:
    print("[BUG-NN description (pixel)]")
    var img := _load_capture(MENU_CAPTURE)  # /tmp/castle_clash_test/menu_battle_000.png
    if img == null: return
    # ... pixel sampling logic ...
    if hits.is_empty():
        _assert_pass("description of clean state")
    else:
        _assert_fail("BUG-NN — concrete violation summary", "hint for fixer")
        _record("HIGH/MED/LOW", img_path, y, "diagnostic detail")
```

**Resolution awareness**: Captures may be at 504×896 (desktop window override) or 720×1280 (native mobile). Detectors should compute coords from `img.get_width()`/`get_height()` ratios when possible, OR document the calibration resolution in the docstring.

**Outcome**: 6 detectors now in `test_screen_layout.gd` covering BUG-41/43/46/47/48/49. All 4 new ones FAIL on the current build (as required to prove they exercise the actual bug). Bugs cannot be closed until detectors flip PASS.

## 2026-04-19 (A2 — Loading Screen Overhaul, 10 iterations): Study the reference, inspect the asset, pixel-verify BEFORE shipping

**Context**: User gave a 9-point spec for a loading screen overhaul (logo anchor, shrunk bar, clouds, castle + trees, multi-elevation plateau with water pond, all matching a Tiny Swords reference image). Took **10 rounds** (R1-R10) over one session to converge, with the user having to correct the same class of issue repeatedly. This is the highest iteration count A2 has ever taken for a single directive. The debrief:

**Round-by-round failure pattern (what went wrong at each stage):**

- **R1**: Eyeballed the spec, built everything without measuring; bar fill overflowed its trough because I used `STRETCH_TILE` on a 64-row source in a 27-tall element (clipped the opaque fill band to invisible rows). User had to flag it.
- **R2**: Changed sky color and resized bar but the castle still felt "nowhere near the logo" — I didn't investigate why. Told myself the castle was centered based on a pixel scan but the user was measuring against the LOGO position.
- **R3**: User: "find root cause for why you think it is already centered." Found it: the logo's bob tween was setting `position:y` to ABSOLUTE `-4` / `+4` instead of applying a delta. The logo was drifting 280 px above its anchor every cycle. The castle was technically 20 px below the logo's *intended* position but the logo itself was flying. Root cause found only because user demanded it.
- **R4-R5**: Trees still looked cropped. I blamed the viewport buffer and kept nudging positions. Real cause: `TextureRect.EXPAND_IGNORE_SIZE` only respects `size` *inside a Container*. In a bare Control parent, TextureRect falls back to the texture's NATURAL size (256×256 for Tree1/2, 192×192 for Tree3/4). The rightmost tree's 90-wide box was actually 256 wide and spilled past the viewport. Fix required wrapping every sprite in a fixed-size Control container. Only caught this after running Python to measure the actual rendered extents.
- **R6-R7**: Foam "strips" along the cliff didn't look right. I kept adjusting positions and adding strips. Real cause: **Water_Foam.png is a LOCALIZED wave-blob sprite, not a tileable shoreline texture.** Frame 0 has opaque content only at y=58..141 inside the 192×192 tile (rest transparent). My `STRETCH_TILE` strip into a 28-tall destination rendered rows 0..27 of the source = all transparent = no foam visible. Plus my animation callback was overwriting the region's Y offset every tick. Took 4 rounds of "just tune the position" before I loaded the asset in Python and counted its opaque pixels.
- **R8-R9**: Fixed z-order (foam was rendering OVER the cliff instead of under). Still looked wrong because my 6 discrete blobs read as floating pools, not a shoreline. User: "adjust left then up to be aligned to cliff edges." I still hadn't internalized that the *reference image shows CONTINUOUS foam trim* — I kept trying to make 6 blobs look right.
- **R10**: Finally did the math: `content_w × (display / source) ≥ cliff_tile_w`. At source content 86 px in a 192-px frame, display must be ≥107 px for adjacent blobs at 48-px spacing to touch. Used 120-px display + 11 blobs (one per cliff tile) + 27 px LEFT shift. Pixel-verified: 0 gaps >8px, left edge within 2 px of cliff left, minor 10-14 px right overshoot.

**The pattern underneath all 10 rounds:**

I made three compounding mistakes on EVERY round until the last one:
1. **Didn't treat the reference image as the SPEC.** User showed me a Tiny Swords terrain reference on Round 1. I glanced at it, started coding from the text spec, and never opened it again to cross-check my output. Every foam iteration could have been skipped if I'd asked "does my output match THIS picture" instead of "does my output look like what I thought I was making."
2. **Didn't inspect the asset before using it.** Water_Foam.png's alpha structure was knowable via 10 lines of Python. I assumed it was a tileable shoreline because "that's what I wanted to use it for." Cost me 4 rounds.
3. **Reported QA_REVIEW based on code-level changes, not visual verification.** User had to explicitly call this out ("you're back to not testing your fixes") to break the pattern. I was pushing work to A4 without checking the rendered PNG myself.

**Rules that would have saved 8 rounds:**

**Rule — asset-semantics audit before use.** For any texture I haven't used before, open it in Python FIRST and report: dimensions, alpha bbox, tile structure, animation frame layout. The 5 minutes of inspection beats 3 rounds of "tune the position." This is the `tasks/asset-usage.md` discipline I already wrote for UI atlases — I should be applying it to ALL assets (terrain, effects, sprites), not just UI 9-patches.

**Rule — reference-image spec.** When the user provides a reference image as part of a spec, the reference IS the spec. Before shipping each round, pull up the reference side-by-side with the rendered output and list the visible differences. If I can't name 3+ matches and 0 clear misses, it's not ready.

**Rule — measure, don't guess.** For every claim I make about the rendered output ("foam is continuous", "trees are uncropped", "castle is centered"), have a Python script that demonstrates the claim quantitatively on the current PNG. "309 foam px at y=654 + 0 gaps >8 px at peak row" is a claim. "Foam looks continuous" is a guess.

**Rule — understand TextureRect's sizing contract.** TextureRect respects explicit `size` ONLY when inside a Container (HBox/VBox/GridContainer) OR when wrapped in a fixed-size Control parent with `set_anchors_and_offsets_preset(FULL_RECT)`. In a bare Control, EXPAND_IGNORE_SIZE falls back to the texture's NATURAL size. This isn't a bug, it's Godot's documented behavior. For precise pixel-sizing in scenic composition, either use Sprite2D (immune to Control layout) or use the wrap-in-Control-container pattern.

**Rule — z-index sandwich ordering.** When layering an effect SPRITE over a TERRAIN COMPOSITE (like foam over a cliff), decide BEFORE coding which direction the sprite renders: in front of the terrain ("wave splash on rocks") or behind it ("thin trim hugging the base"). The z-index choice is the art-direction call, not a tuning parameter. If uncertain, ask — don't ship both in alternating rounds.

**Rule — keep the reference texture's natural structure visible in code.** When cropping a source texture to content (e.g., foam_region_y=56, foam_region_h=94), write a comment explaining the native content bbox (y=58..141 for frame 0, drifts to y=148 at frame 11) so the next editor doesn't have to rediscover it by inspection.

**One-line summary**: When the output looks wrong, inspect the asset + measure the render + re-read the reference. Don't tune positions hoping to converge.


---

## Lesson (2026-07-07) — Per-tile hue variation betrays the tile grid

**Context**: 3.3b meadow overhaul. To make grass "not flat" I filled the field with a
per-tile random pick from 3 lush green hues (color1/2/3). Captured → the arena showed an
obvious checkerboard of rectangular green patches. The mockups have NONE of this.

**Root cause**: A 64px tile filled with a uniformly-different hue makes its rectangular
boundary visible. Random per-tile hue = a grid of visible rectangles. This is inherent to
per-tile colour variation, not a tuning problem — closer hues or brightness jitter only
reduce it, never remove it.

**Rule — terrain variation comes from decoration, not base-tile hue.** Keep the ground a
single uniform tile (mockups do exactly this). Get organic variation from NON-grid-aligned
sprites on top: trees, bushes, sheep, wildflowers, gold, rocks — placed at free x/y, not
snapped to the 64px grid. Uniform base + scattered decoration reads lush; per-tile hue reads
tiled. Verified by capture: uniform color1 + decoration matched mockup, hue-mix did not.

**Corollary — "flat" was never about uniform grass.** The original arena looked muddy
because of the reddish enemy TINT + brown combat-lane tint, not because grass was uniform.
Fixing the tint (→ one lush green) solved "flat"; adding hue-blocks made it worse.

---

## Lesson (2026-07-08) — Why visual iterations never converge: compose in image space, not in code

**Context**: User escalated: "Claude Design made v1/v2/v3 from the SAME assets and they look
great; our game doesn't after several iterations — something is fundamentally wrong with the
flow." Forensic audit (wf_772ab315) confirmed it.

**Root cause chain** (full numbers in tasks/design-flow.md):
1. Art composed blind in GDScript coordinates; feedback = 3-5 min per placement decision
   (boot + capture + inspect) vs ~0.1s in image space. 50-100x latency gap.
2. The reference mockups were never IN the repo/loop — no resolution-matched target, no diff.
3. Acceptance = element checklists ("sheep ✓ trees ✓"), shipped at 2.3x sparser composition.
4. Scale never art-directed: castle 1.7x too small vs mockup; sim cell size dictated visuals.
5. Global alpha/tint nerfs (T-039 et al) made reference parity mathematically unreachable.

**Rules now enforced (tasks/design-flow.md + PROCESS.md §2):**
- **Rule — visual tasks start in the compositor.** `tools/compose_<screen>.py` renders the
  screen from real assets at real resolution (~0.1s). All art decisions happen there. The
  approved PNG is committed to `design/` as the pixel spec; code PORTS it mechanically.
- **Rule — the reference lives in the repo**, resolution-matched (design/references/), or it
  is not a spec.
- **Rule — full opacity, native palette.** Never modulate-tint or alpha-fade pack art for
  "readability" — solve readability with PLACEMENT. Never rotate pixel art by random radians.
- **Rule — composition parity is numeric.** Density/scale/coverage stats vs the target, not
  "looks close". (Perceptual-diff gate: pending implementation.)
- **Meta-rule — lessons must compile into tooling/gates.** "Reference image is the spec" was
  already written 2026-04-19 and violated again in 3.3b because it stayed prose. A lesson
  that matters becomes a tool, a gate, or a checked-in artifact — not a paragraph.

---

## Lesson (2026-07-08b) — Three compositor-flow refinements from the first feedback round

1. **Calibrate from measured fractions, never eyeball.** Ported the castle at 0.9x native
   from a rough eyeball while the forensics report had the measured answer (0.296 of
   playfield width → 0.68x). User immediately flagged "too big". When a measurement exists,
   the LAYOUT must cite it. Detector now pins a TWO-SIDED band (130..172px) so scale can't
   silently drift in either direction.
2. **The design tool must share the game's rendering semantics.** The compositor drew in
   table order while the game y-sorts — so "sheep floating on tree canopies" was invisible
   in the approved target and appeared only in-game. The compositor now paints back-to-front
   by ground-y. Generalization: any semantic the runtime applies (y-sort, z-layers,
   modulate) must exist in the design tool, or the spec lies.
3. **Symmetry by construction.** Hand-placed "roughly mirrored" decorations drifted ±4-10px.
   Author one quadrant; generate mirrors; assert the invariant (platform spans mirror about
   FLIP_PIVOT_Y). Matters doubly here: the multiplayer perspective flip means asymmetry =
   different-looking arenas for the two players.

---

## Lesson (2026-07-08c) — 2.5D perspective orientation is not mirrorable

**Context**: To mirror the player-half fortress wall I vertically flipped the stone cliff
tile. User caught it: in Tiny Swords' fake-3D top-down perspective, the stone "bar" face of
any elevation ALWAYS points SOUTH (screen-down) — you see cliff faces below plateaus, never
above them; a plateau's top boundary is only a thin rim line. A flipped cliff tile is
perspective-illegal and reads instantly wrong.

**Rule — mirror positions, never orientations.** Layout symmetry = mirrored coordinates.
Tile/sprite orientation is owned by the camera perspective, which does not flip with the
layout. Never flip_v elevation, cliff, or building art. "The bar-like edge of the cliff at
the bottom of the castle, wherever the player is."

---

## Lesson (2026-07-10) — One frame-extraction path; never bypass the smart helper

**Context**: "Cropped trees" = disembodied fir fragments floating in the water. Tree1/Tree2
sheets are 8 frames of 192x256 (NON-square). The codebase already HAD a correct extractor
(`_extract_sprite_frame` tries frame counts 8/6/16/4/12) — but the tree code bypassed it
with a hand-rolled square `Rect2(0,0,fh,fh)` crop, which bled a 26px sliver of the NEXT
animation frame into every tree sprite. The compositor's `frame_of` had the same square
assumption, so the approved target contained the bug too.

**Rules:**
- **One extraction path.** If a smart helper exists (`_extract_sprite_frame`), route ALL
  strip crops through it. A bypass is where the next asset bug lives.
- **Non-square frames are normal** in Tiny Swords (192x256 trees). "frame = height x height"
  is an assumption, not a fact — measure content-column runs (10 lines of PIL) per sheet.
- **Gate what the eye keeps catching.** The user had to report cropped art AGAIN — now
  `_check_arena_no_floating_foliage` fails the gate on any foliage beyond the island rim
  band. When a class of visual bug recurs, it gets a detector, not another one-off fix.

**Also learned (wf_d5ce1bda):** sim placement tests tolerate silent no-ops — place_building
returns empty events on invalid coords, and several team-1 test placements were ALREADY
silently failing under the old 5x2 footprint without any assertion noticing. Backlogged:
placement tests must assert the building EXISTS after placing.

---

## Lesson (2026-07-14) — The compositor's castle Y is NOT where the game renders it

**Context**: CASTLE-CLIFF. Composed an integrated stone cliff base under each castle,
approved the target, ported the LAYOUT verbatim (cliff edge = compositor castle foot − 4).
In-game the cliff floated with a grass gap below the castle — the exact "detached floating
strip" failure we'd sworn off. Root cause: `compose_arena.py` blits `Castle.png` at
`CASTLE_CENTERS` (red foot design 167), but the GAME places the castle via
`castle_visual.gd` (sprite parented to a `CastleArea` ColorRect + a `CastleVisual` node at
scale 0.7 with a sim-anchor offset). The two DISAGREE: measured game red content-foot ≈
design **147**, ~20px higher than the compositor assumes. So "port the compositor LAYOUT
verbatim" put the cliff 20px too low.

**Rules:**
- **The compositor mirrors the game for TERRAIN it fully owns, not for elements another
  system positions.** Castles/units are placed by their own visual scripts, so the
  compositor's `CASTLE_CENTERS` is a design approximation, not ground truth. Anything that
  must ATTACH to such an element (a cliff under a castle, a shadow, a banner) must be
  aligned to the element's ACTUAL rendered position — measured from a capture — not to the
  compositor's assumed coordinate.
- **Measure the attach point in the real capture before porting.** cap = 0.7 × design
  (720×1280 → 504×896; verify via the platform edge: design x72 → cap x50). Find the
  element's rendered foot by the first grass row below its blob (or by its unique color —
  cream wall vs cool cliff stone), NOT by transform arithmetic (I got the transform wrong
  twice).
- **Hide the tile's coastal-foam fringe.** Tiny Swords elevation face tiles (col6 row4)
  carry a grass fringe on top + a bright foam rim on the bottom. Put the cliff top ABOVE
  the castle foot so the castle body hides the fringe and the stone emerges merged with the
  castle's own stone foundation — otherwise a thin grass line shows between them.
- **Calibrate the detector window on a clean baseline, not near the element.** First window
  (just under the foot) caught the castle's own foundation stone → 433 px on the no-cliff
  build, a thin RED margin. Moving it a few px lower (clear of the foundation) gave a pure-
  grass 0-px baseline vs 760-px cliff — a real RED→GREEN. Get the no-cliff baseline by
  `git stash push -- <the one render file>` → capture, then pop → capture.

---

## Lesson (2026-07-17) — Two rules from 3.3b (side plateaus + worn path)

1. **Pivot-straddling structures: mirrored decorations only in the SELF-MIRRORING
   sub-zone.** A side plateau spanning y=[328,712] self-mirrors about the pivot as a
   REGION, but its grass zone [328,648] maps to [392,712] — the south 64px of the image
   is the stone face. A sheep authored at gy=352 put its y-mirror ON the cliff. Rule:
   decorations on such a structure must sit in the intersection zone (here y∈[392,648]);
   an item authored AT the pivot mirrors onto itself (dedupe it in the GAME port, or two
   out-of-phase sway tweens ghost-double the sprite).
2. **Never rng-position a visual that a pixel detector can see.** The rubber duck's
   `rng.randf_range(430,560)` y meant ANY upstream decoration edit reshuffled the rng
   sequence and could park the duck's yellow-green shading inside the floating-foliage
   scan band (it did). Pin easter-egg/ambient positions to constants and exempt their
   full drift ENVELOPE (tween min..max, not the spawn point) in the detector.
