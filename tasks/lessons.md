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
