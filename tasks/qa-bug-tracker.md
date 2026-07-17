# Castle Clash QA Bug Tracker
> **Last updated**: 2026-04-05 (3rd pass) | **QA Lead**: QA Agent
> 
> Other agents: check this file for bugs in YOUR owned files. Update status when you fix something.

---

## ALL PREVIOUS BUGS (1-12): FIXED
BUG-1 through BUG-12 all resolved. See git history.

---

## LATEST FIXES (This Pass)

### BUG-19: ratio_0 compile error in game_arena.gd
- **Status**: FIXED by QA
- **Root cause**: Dead code left after `_hp_color()` refactor referenced variables from wrong scope.
- **Fix**: Moved castle visual sync back to `_update_castle_hp_bars()`, removed dead code.

### BUG-20: Tower damage inconsistent with unit damage
- **Status**: FIXED by QA
- **File**: `core/simulation.gd:441-451`
- **Root cause**: Towers used flat subtraction (`raw_dmg - armor`) while units use WC3 percentage reduction (`damage / (1 + armor * 0.06)`).
- **Fix**: Tower damage now uses same WC3 formula as unit attacks.

### BUG-21: Dead _distance_squared_y function
- **Status**: FIXED by QA — removed unused function.

### BUG-22: Siege units (catapult/demolisher) had no attack animation
- **Status**: FIXED by QA
- **File**: `autoload/sprite_registry.gd`
- **Fix**: Mapped `Pawn_Interact Hammer` for catapult, `Pawn_Interact Pickaxe` for demolisher.

---

## MELEE RANGE BUG — VERIFIED FIXED

Root cause was in commit 9505d07: attack range used Y-only distance instead of full 2D. Fixed by changing `_distance_squared_y()` to `_distance_squared_2d()` in 3 locations. FP Q16.16 math verified correct — melee (1 cell = 28px) can only attack within 28 pixels in full 2D.

---

## UNUSED TINY SWORDS ASSETS (Visual Agent Should Utilize)

| Asset | Location | Suggested Use |
|-------|----------|---------------|
| `Arrow.png` | `units/blue_archer/`, `units/red_archer/` | Projectile sprite for archer attacks |
| `Heal_Effect.png` | `units/blue_monk/`, `units/red_monk/` | Particle effect on healed targets |
| 8 Lancer directional attacks | `units/blue_lancer/`, `units/red_lancer/` | Direction-aware attack anims (Up when target above, Down when below) |
| 18 Pawn carrying variants | `units/blue_pawn/`, `units/red_pawn/` | Randomize tool carried (Gold, Hammer, Axe, etc.) |
| `Heal_Effect.png` | Both monk folders | Visual heal burst on target |

---

## LATEST FIXES (QA Automated Cycle)

### BUG-23: Wall/palisade buildings had no sprite mapping
- **Status**: FIXED by QA
- **Root cause**: Mechanics agent added wall.tres and palisade.tres but no entry in BUILDING_MAP
- **Fix**: Added `wall` and `palisade` → `House1` mapping in sprite_registry.gd

### BUG-24: Card hand overflows with 8 buildings
- **Status**: FIXED by QA
- **Root cause**: 8 cards × (92px + 5px) = 771px > 720px screen width
- **Fix**: Reduced CARD_W from 92 to 84, CARD_GAP from 5 to 4 → 707px total (fits)

### BUG-25: Units too small to see in combat
- **Status**: FIXED by QA
- **Fix**: Unit sprite scale 0.25→0.30, default camera zoom 1.0→1.2. UI unaffected (CanvasLayer).

### BUG-26: Tower damage formula inconsistent with unit damage
- **Status**: FIXED by QA (earlier this session)
- **Fix**: Tower attacks now use WC3-style armor reduction like unit attacks.

---

## NEW BUGS (2026-04-11 — A4 Session)

### BUG-27: Siege units always prioritize buildings over units
- **Status**: FIXED by A5 (2026-04-17), VERIFIED by A4 (2026-04-18) — `_acquire_target()` now treats siege units like all others (nearest enemy wins). Test output: `3 bldg, 2 unit, 0 castle, 0 none` (was `4 bldg, 0 unit` pre-fix). `[Siege Targeting — Building Preference]` test in test_simulation.gd passes.
- **Severity**: HIGH (gameplay feel)
- **File**: `core/simulation.gd:1798-1826`
- **Root cause**: `_acquire_target()` has siege-specific building preference. When `unit.role == 4` (catapult, ballista, demolisher, scorpion) and any enemy building exists at any distance, siege picks building over closer units/castles. Lines 1819-1821 track `best_bldg_id`, lines 1823-1824 always prefer it.
- **Expected**: Siege units should target like other units — nearest enemy wins.
- **Fix**: Remove `is_siege`/`best_bldg_id` special-casing.

### BUG-28: No anti-air system — all units can target flying units
- **Status**: FIXED by A5 (2026-04-17), VERIFIED by A4 (2026-04-18) — `can_hit_air: bool` added to unit_data.gd; set true only on archer, axe_thrower, gryphon_rider, wyvern_rider. `_acquire_target()` skips flying targets (role==3) when attacker lacks the flag. Test output: `0 melee→flying` (was `1 melee→flying` pre-fix).
- **Severity**: HIGH (gameplay balance)
- **File**: `core/simulation.gd:1798-1826`, `data_scripts/unit_data.gd`
- **Root cause**: Zero filtering for flying targets in `_acquire_target()`. Every unit can acquire and attack flying units (role==3). No `can_hit_air` property exists.
- **Expected**: Only archers and gryphon riders (and their Horde equivalents) should target flying units.
- **Fix**: Add `can_hit_air: bool` to unit_data.gd, set true on archer/gryphon/axe_thrower/wyvern. Filter in `_acquire_target()`.

### BUG-29: Gold coin icon far from gold text in battle HUD
- **Status**: OPEN — Owner: A2
- **Severity**: LOW (cosmetic)
- **File**: `game_arena.gd:987-994`
- **Root cause**: Coin at x=131, label starts at x=145 but spans to x=605 (460px wide). If center-aligned, gold number renders ~244px from coin.
- **Fix**: Left-align gold label text, or narrow label width.

### BUG-31: Opponent units render as BLUE instead of RED (T-066 regression)
- **Status**: FIXED by A4
- **Severity**: CRITICAL (gameplay)
- **Files**: `autoload/sprite_registry.gd`, `scripts/game/game_arena.gd`
- **Root cause**: T-066 faction simplification made both teams use Kingdom units (e.g., both spawn "footman"). `get_unit_sprites(unit_type)` only took unit_type, mapping to blue folders. Team 1 got blue sprites.
- **Fix**: Added `RED_EQUIVALENT` map (9 entries), team param to `get_unit_sprites()`, passed `entity.team` from game_arena.gd. 19 new tests verify.

### BUG-30: Card bottom text overlap in 2-row layout
- **Status**: OPEN — Owner: A2
- **Severity**: MEDIUM (readability)
- **File**: `card_hand.gd:346-374`
- **Root cause**: In 2-row layout card_h shrinks to ~96px. Building name y=68, type y=81, stats y=h-6=90. Only 9px gap → text overlap.
- **Fix**: Hide stats when h<110, or compute info_y with minimum spacing from type text.

### BUG-32: Roof icon decorations barely visible on upgraded buildings
- **Status**: FIXED + VERIFIED 2026-07-17 — icon targets doubled (wing 22→44,
  bolt 26→52, horse 18→36) + near-black backing silhouette (1.12x) behind each
  icon for contrast (`sprite_building_visual.gd`). **Detector**:
  `_check_roof_icon_visibility` (autotest now places a gryphon_roost via gold
  boost; locates it from game_state.json grid coords, unflipped player-0
  mapping). Controlled git-stash baseline: pre-fix 16 pale px → post-fix 60
  (bar 30). 4x crop shows readable wings. Feel sign-off on the deployed build
  is Neil's; escalation path if still weak = banner/flag overlay (below).
- **Severity**: HIGH (gameplay clarity)
- **File**: `scripts/game/sprite_building_visual.gd:70-87`
- **Root cause**: ROOF_ICONS use tiny pixel sizes: wing_icon=22px, bolt_icon=26px, horse_icon=18px. Buildings render at ~60x60px in battle. At that scale, icons are 3-5 pixels on screen — invisible to players. User confirmed: "the wings and the arrow on the roof and others are barely visible."
- **Affected buildings**: gryphon_roost, wyvern_nest (wing), ballista_workshop, scorpion_foundry (bolt), royal_stable, beast_pen (horse)
- **Fix**: Double icon sizes minimum — wing 22→44px, bolt 26→52px, horse 18→36px. Consider adding a contrasting outline/glow behind icons for visibility. Alternative: use colored banner/flag overlay or tinted roof instead of small icons.

### BUG-36: No audio on web export (multiplayer and offline) — AudioWorklet mock silences everything
- **Status**: FIXED by A1 (2026-04-18), VERIFIED by A4 (2026-04-18) — headers confirmed live on production via `curl -sI https://play.castlefight.net/` and `/index.wasm`: `cross-origin-opener-policy: same-origin` + `cross-origin-embedder-policy: credentialless`. Brotli compression + 1-year immutable cache preserved. `credentialless` choice keeps Nakama cross-origin auth working without requiring CORP headers on nakama.castlefight.net. User confirmed sound works in multiplayer. SharedArrayBuffer + AudioWorklet now available. Owner: A3/A1
- **Severity**: CRITICAL (no sound at all on web) — user-confirmed working post-fix
- **Files**: `castle_clash/export/web/_headers` (new COOP/COEP block), `castle_clash/build.sh` (template), Cloudflare Pages deploy 2026-04-18
- **A1 resolution (2026-04-18)**: Root cause was missing Cross-Origin-Isolation headers on the Cloudflare Pages deployment. Without `Cross-Origin-Opener-Policy` + `Cross-Origin-Embedder-Policy`, browsers refuse to expose `SharedArrayBuffer`, which Godot 4.6.2's AudioWorklet path needs. Added `/* COOP: same-origin + COEP: credentialless` to `castle_clash/export/web/_headers` and the matching block in the `build.sh` template so future builds don't regress. Deployed via `wrangler pages deploy` — header scan shows both headers on `/`, `/index.wasm`, `/index.pck` for https://play.castlefight.net/. Chose `credentialless` over `require-corp` to avoid breaking Nakama HTTP auth (cross-origin to `nakama.castlefight.net` — `require-corp` would need CORP headers on Nakama responses). `credentialless` still cross-origin-isolates the page while letting the existing CORS-with-credentials auth flow continue. User confirms multiplayer audio works end-to-end on `play.castlefight.net` post-deploy. Offline audio should also benefit since cross-origin-isolation unlocks AudioWorklet regardless of MP mode. Keeping `sfx.gd:553,599,786` procedural-audio web guards in place — file-based .ogg is the intended path on web and it's working. **A4 to verify**: open fresh Chrome tab on `play.castlefight.net`, confirm `crossOriginIsolated === true` in DevTools, play a full match with sound.

---

### BUG-33: USE_ABILITY command silently dropped by simulation
- **Status**: FIXED by A5 (2026-04-17), VERIFIED by A4 (2026-04-18) — `Command.Type.USE_ABILITY` now routes to `_handle_use_ability(cmd)` in `_process_command()`. Dispatch by `cmd.ability_id`: `&"castle_wrath"` handled, unknown ids emit `push_warning("Unknown USE_ABILITY id: %s")` instead of being silently dropped. Nyquist test `_test_use_ability_unknown_warns` verifies unknown ids produce zero castle_wrath events and castle_wrath is refused while HP > 30%.
- **Severity**: HIGH (multiplayer sync risk)
- **File**: `core/simulation.gd:459-468`
- **Root cause**: `_process_command()` handles PLACE_BUILDING, SELL_BUILDING, ACTIVATE_BUILDING but has NO match arm for `Command.Type.USE_ABILITY`. Command is serialized/deserialized correctly by NetworkManager (lines 386-389, 407-410) but simulation ignores it. Currently both clients drop it so no desync occurs, but any future ability implementation will be dead code until this is added.
- **Fix**: Add `Command.Type.USE_ABILITY: events.append_array(_handle_use_ability(cmd))` to the match statement in `_process_command()`. Implement `_handle_use_ability()` or at minimum add an empty handler that logs a warning.

### BUG-34: Radial menu dismiss races with button click
- **Status**: OPEN — Owner: A2
- **Severity**: MEDIUM (building interaction — user reports can't click buildings)
- **File**: `scripts/game/building_grid.gd:99-108`
- **Root cause**: When radial menu is open and user taps, line 107 calls `_dismiss_radial.call_deferred()` BEFORE Area2D buttons process the input event. On slow frames or multiplayer lag, the deferred dismiss can fire in the same frame as the button's `_on_input_event()`, causing the menu to vanish before the action executes. The `_RadialButton._on_input_event()` calls `get_viewport().set_input_as_handled()` (line 517) as mitigation, but this only prevents further propagation — it doesn't cancel the already-queued deferred dismiss.
- **Symptoms**: User reports "can't click buildings for information or to sell" in multiplayer sessions.
- **Fix**: Remove the unconditional `_dismiss_radial.call_deferred()` at line 107. Instead, set a flag `_dismiss_pending = true`, and in `_process()` dismiss only if the flag is still true (button clicks would clear it). Or: use a short timer (0.1s) before dismissing, giving buttons time to process input first.

### BUG-35: Multiplayer command delivery not verified
- **Status**: OPEN (downgraded to P2 hardening — superseded by BUG-DESYNC1 fix 2026-04-18) — Owner: A1
- **Severity**: HIGH (multiplayer sync) → **MEDIUM** post-DESYNC1
- **File**: `autoload/network_manager.gd:69-86`
- **Root cause**: `flush_commands_for_tick()` sends commands via `_socket.send_match_state_async()` (fire-and-forget) and immediately marks `_local_commands_sent[tick] = true`. No ACK mechanism exists. If the Nakama relay drops a packet, the remote client never receives commands for that tick but the local client believes they were sent. The remote client then stalls (waiting for local commands) until the 5s timeout aborts the match. User reports "sync error" — this is the likely cause.
- **Symptoms**: Sync errors, match aborts, desync detected at checksum comparison.
- **Fix**: Add command acknowledgment: remote client sends OpCode.ACK after receiving commands for a tick. If no ACK within 500ms, resend. Or: send commands redundantly (include previous tick's commands as backup in each message).
- **A1 update (2026-04-18)**: Largely superseded by the BUG-DESYNC1 fix. The "+2 tick buffer" in `send_command()` plus the post-commit definitive re-flush in `commit_tick_commands()` already guarantee that a command has two tick boundaries to arrive at the remote before stalling, and every committed tick's payload is re-sent redundantly. User confirms the user-visible "sync error" symptom is gone. Remaining value in BUG-35: explicit ACK + bounded retransmit would add observability (we'd know a packet was lost rather than silently retrying) and tighten the worst-case for multi-packet loss. Leaving OPEN at P2 as a hardening followup; not a production blocker.

### BUG-37: Kingdom faction description still references Champions
- **Status**: FIXED by A2 (2026-04-18), VERIFIED by A4 (2026-04-18) — main_menu.gd:30 FACTION_DESCRIPTIONS["kingdom"] now reads "Mages burn packed enemies with fireball splash" (was "Champions bring aura buffs"). Matches T-084 mage replacement. Owner: A2
- **Severity**: LOW (cosmetic copy — not gameplay-blocking)
- **File**: `scripts/ui/main_menu.gd:30`
- **Root cause**: After T-084 replaced Champion with Mage, the kingdom description `"The Kingdom — Balanced faction with healing priests and heavy lancers. Champions bring aura buffs. Sustain-oriented, wins long fights."` still references Champions, which no longer exist in the roster.
- **Fix**: Update to reference Mage/fireball or drop the Champions line entirely. Suggested: `"The Kingdom — Balanced faction with healing priests and heavy lancers. Mages rain fireballs across the field. Sustain-oriented, wins long fights."`

### BUG-38: Perspective flip — sell/radial input not Y-inverted for player 1
- **Status**: FIXED by A2 (2026-04-18), VERIFIED by A4 (2026-04-18) — building_grid.gd `_try_sell_building:260` and `_try_show_radial:283` now call `_visual_row(int(local_pos.y)/CELL_SIZE)`. Reflection is self-inverse so the same helper serves both directions. Ghost placement inversion at :211-215 unchanged.
- **Severity**: MEDIUM (multiplayer UX — player 1 can't reliably sell/inspect buildings)
- **File**: `scripts/game/building_grid.gd:261-298`
- **Root cause**: `_update_ghost_position` correctly inverts `gy → sim_gy = (GRID_ROWS - size_y) - gy` for player 1 (view_flipped view). But `_try_sell_building` and `_try_show_radial` both use `gy = local_pos.y / CELL_SIZE` and index `grid[gy][gx]` without the same inversion. Result: a tap on a building in player 1's flipped view queries the wrong sim row — can sell/inspect the wrong building or nothing.
- **Fix**: Mirror the `_update_ghost_position` inversion logic into both `_try_sell_building` and `_try_show_radial`. Factor the inversion into a helper `_visual_row_to_sim_row(gy, size_y=1)` to keep all three call sites consistent.
- **Also**: `scripts/game/building_grid.gd` still has debug `print(...)` statements at lines 73, 78, 114, 216 — remove before release.

### BUG-39: Perspective flip — terrain zone tints not swapped for player 1
- **Status**: WONTFIX-BY-CONSTRUCTION (2026-04-18 A2/A4) — terrain tints are screen-positional (green y=695–1010, darker y=0–345); Y-reflection in `sim_to_screen` around FLIP_PIVOT_Y=520 keeps the flipped player's entities over the green bottom half naturally. No code change needed. Added doc-comment to `_apply_perspective_flip()` explaining the passes-by-construction reasoning.
- **Severity**: LOW (cosmetic — player 1 sees their zone in enemy tint)
- **File**: `scripts/game/game_arena.gd:_apply_perspective_flip`
- **Root cause**: T-085 perspective flip swaps castle scene positions and grid overlay player_index assignments, but the terrain zone tints (combat lane brown, grass green, enemy zone darker) stay painted in world coordinates. For player 1 in a flipped view, the terrain visually communicates the wrong zone ownership — "your" zone looks like enemy territory.
- **Fix**: Either (a) swap the zone color fills in `_apply_perspective_flip`, or (b) parameterize `_build_terrain_textures` to key its color choices off `view_flipped`. Option (b) is cleaner since terrain is built in `_ready` after `view_flipped` is set.

### BUG-40: Walk animation FPS out of sync with movement speed (T-088 regression)
- **Status**: CODE-VERIFIED (round 2 fix), **PENDING LIVE PLAYTEST** — A2 round 2 (2026-04-18) replaced the static fps revert with two synergistic techniques: **(1) per-unit dynamic walk speed_scale** — `set_walk_speed_ratio(ratio)` on sprite_unit_visual.gd:250-255 + 290 + 297; game_arena.gd:697-703 feeds `ratio = entity.move_speed / 44.8` (44.8 = footman 2 cells/sec × 28px × 0.80 T-077 penalty). Result: knight at 3 cells/sec → ratio 1.5 → 15fps walk, priest at 1 cells/sec → ratio 0.5 → 5fps walk, footman → 1.0 → 10fps. Stride stays ~1.1 body widths for every unit. **(2) Distance-driven walk bounce** — `_walk_phase += moved / 35.0` (ground) or `/60.0` (flying) at sprite_unit_visual.gd:335/341, replacing the time-driven `delta * 10.0`. Body bob now pulses at footfall rhythm (no bouncing in place during hit-stop, no mismatched phase under accel/decel). `moved` clamped to 3.0px max per frame to guard teleport spikes. **Also**: pawn overlay (ballista/scorpion) gets matching speed_scale. **Tests**: 365/365 sim PASS. **Pending**: live playtest verification of the 5 perception checks A2 listed (knight smoother than footman, priest deliberate, no bounce in hit-stop, no skating, ratio stable). A4 cannot evaluate sprite cadence from headless captures — needs human eyes on the windowed game.
- **A2 fix**: `autoload/sprite_registry.gd:21` reverted to `"walk": {"fps": 10, "loop": true}`. T-088's idle (8fps) and attack/cast (12fps) bumps kept. Math: 10fps × 6-frame cycle = 0.6s/cycle → 33.6px displacement at 56px/sec ≈ 1.1 body widths per cycle (target).
- **What A4 verified**: source change applied; headless `_test_animation_smoothness_*` tests pass with smooth interpolation metrics (these test sim position math, not sprite rendering).
- **What A4 did NOT verify**: actual visual walk-cycle cadence vs movement rate in a real game frame sequence. The autotest video capture at 504×896 was too small to step through a single foot-plant phase per frame; native 720×1280 capture exists but multi-frame analysis still needs live human eyes per CLAUDE.md "Game mechanics changes" rule.
- **Owner**: A2. **Verification ask**: please run `godot --path castle_clash` (windowed, full size), watch a footman march from spawn to combat lane, confirm walk feels grounded (not skating). If still off, file follow-up with which unit type and at what speed.
- **Severity**: HIGH (UX — user-reported: "walking is kind of lagging, units are teleporting a small distance")
- **File**: `autoload/sprite_registry.gd:18` (ANIM_PROPS["walk"]["fps"] = 14), `scripts/game/sprite_unit_visual.gd:214` (walk speed_scale = 1.0 constant)
- **Root cause**: T-088 bumped walk animation from 8fps → 14fps (75% faster) without adjusting unit movement speed or introducing a speed-scale ratio. The sprite's legs now cycle too fast for the actual march rate, producing a "treadmill" / "skating feet" perception. Users describe it as "teleporting a small distance" because each animation cycle displaces the unit less than one body width — the feet planting rhythm no longer matches forward progress.
- **Evidence**: new headless test `_test_animation_smoothness_real_spawn` (tests/test_simulation.gd) confirms the SIMULATION position interpolation is perfectly smooth (mean Δy=0.747px/frame, CV=0, no teleports). The issue is purely visual: animation cadence vs movement cadence mismatch.
- **Math**: Footman moves at 2 cells/sec = 56px/sec. Walk cycle is 6 frames × (1/14s) = 0.43s per cycle → 24px displacement per cycle (< 1 body width of 30px). Fort Guardian's feel is based on >= 1 body-width per cycle.
- **Fix options** (A2 to choose):
  1. **Quick**: revert walk fps from 14 → 10 (compromise between old 8 and current 14). Moves per-cycle displacement to 56×(6/10) = 33.6px ≈ 1.1 body widths.
  2. **Better**: set `_sprite.speed_scale` proportional to actual sim move_speed when is_moving=true, calibrated so the default footman renders at 10fps equivalent. Formula: `speed_scale = (current_move_speed / FOOTMAN_BASE_SPEED) * (10.0 / 14.0)`.
  3. **Best**: move ANIM_PROPS["walk"]["fps"] back to 10, keep T-088's idle (8fps) and attack/cast (12fps) bumps — they don't interact with movement pacing.
- **Ownership**: `autoload/sprite_registry.gd` is A2's. Coordinating fix ownership with A0 before change — this is a user-perception issue identified in live play.

### BUG-46: Main menu — chimney smoke renders as 6-puff horizontal LINE above BATTLE button instead of vertical column
- **Status**: **FIXED** by A2 (observed by A4 17:50) — VERIFIED via detector PASS. Owner: A2
- **Detector**: `_check_chimney_smoke_vertical` in `tests/test_screen_layout.gd` — flipped FAIL→PASS. Output: "PASS: no horizontal puff-line pattern in y=510-565".
- **Severity**: HIGH (visual — user-flagged: "line of dust animation")
- **File**: `scripts/ui/main_menu.gd::_add_chimney_smoke` lines 802-836 (T-099 work)
- **Root cause**: line 835 `tw.parallel().tween_property(puff, "position:x", base_pos.x + 8.0, 2.0)` — all 4 puffs (2 chimneys × 2 puffs) animate X identically while Y also animates, producing a horizontal-line drift pattern instead of independent vertical columns.
- **Fix direction**: remove the X tween (or randomize X per-puff with stddev > 12px); each chimney's puff should rise straight up from its base position. Each chimney should be one TextureRect that animates its Y from chimney_y → chimney_y - 40 over a long period, not a row of puffs sharing X drift.

### BUG-47: Main menu — tree foliage z-clips through church/cottage spire (left side)
- **Status**: OPEN — Owner: A2
- **Detector**: `_check_tree_spire_zindex` in `tests/test_screen_layout.gd` — currently FAILS with 19 mixed Y-rows in left scenic strip
- **Severity**: MEDIUM (visual — user-flagged: "overlapping trees to buildings")
- **File**: `scripts/ui/main_menu.gd` background scene composition: trees lines 682-705, buildings lines 665-680 (no `z_index` set on either)
- **Root cause**: NEITHER tree NOR building sprites set `z_index`. They render in node-tree-add-order, which produces inconsistent layering (tree foliage cuts through cottage spire silhouette).
- **Fix direction**: Set `z_index` on tree sprites — either definitively in front (z=10) or definitively behind (z=-10). Recommend behind so the architectural silhouettes are clean.

### BUG-48: Main menu — duplicate fence sprites lined up horizontally at top-right
- **Status**: **FIXED** by A2 (observed by A4 17:50) — VERIFIED via detector PASS. Owner: A2
- **Detector**: `_check_fence_row_repetition` in `tests/test_screen_layout.gd` — flipped FAIL→PASS. Output: "PASS: no evenly-spaced wood/fence row in top-right scenic strip".
- **Severity**: MEDIUM (visual — programmatic-creation artifact, identifiable as 3 identical sprites placed in a row)
- **File**: `scripts/ui/main_menu.gd` (background scene decorations) — Explore agent could not find the loop; may be in `scenes/ui/main_menu.tscn` static placement OR another decoration file. Detector locates it pixel-wise so the source file should be greppable for `add_child` near "fence" at top-right coords.
- **Fix direction**: Either remove the row entirely (it doesn't add value), reduce to 1-2 fences with variation in rotation/scale, or use a single wider "fence row" art asset rather than instancing 3 small ones.

### BUG-49: Main menu — partial ribbon/flag decorations clipped at screen edges
- **Status**: OPEN — Owner: A2
- **Detector**: `_check_ribbon_edge_clipping` in `tests/test_screen_layout.gd` — currently FAILS with 3 right-edge ribbon zones (y=400-560, 100-215 ribbon-px each)
- **Severity**: LOW (visual polish — user-flagged: "partial ribbons animated")
- **File**: `scripts/ui/main_menu.gd::_add_castle_flags` lines 751-799 (T-099 flag wave work)
- **Root cause**: flag anchors at Vector2(68, 220), Vector2(617, 190), Vector2(590, 620) place the rightmost flag's banner texture beyond the safe area; banner extends past viewport edge.
- **Fix direction**: Reposition flag anchors inward by ~80px so the entire banner fits within the visible frame, OR remove the edge flags entirely.

### BUG-51: Battle tab permanently styled as active (gold + lifted) regardless of selection
- **Status**: **FIXED** by A2 (observed by A4 16:30) — VERIFIED via detector PASS. Owner: A2
- **Detector**: `_check_battle_tab_always_lifted` in `tests/test_screen_layout.gd` — flipped FAIL→PASS. Output: "PASS: Battle tab not permanently styled (gold 0 ~ comparable to others)". Battle gold dropped from 395 → 0 px on menu_army_000.png.
- **Severity**: MEDIUM (UX — user flag 2026-04-21 "The battle tab is always lifted where it should only be the active tab in main menu")
- **File**: `scripts/ui/main_menu.gd::_apply_center_tab_emphasis` (lines 982-1012). Called once from `_ready` at line 951, shifts Battle tab's inner children `-12px` and adds a gold `CenterRing` Node2D. Neither gets reset/re-applied when a different tab is selected in `_select_tab` (line 1079-1101).
- **Fix direction**: Either (a) make the lift+ring conditional on `_current_tab == 2` and re-apply in `_select_tab` — raise the active tab, lower others; or (b) remove the permanent emphasis entirely and rely on `_select_tab`'s gold-stylebox override at line 1087-1088 plus `_bounce_tab_icon`. Option (b) is simpler and matches other tabs' styling story.
- **Acceptance**: After fix, `godot --headless -s tests/test_screen_layout.gd` reports PASS on `_check_battle_tab_always_lifted`. User-visible: switching to Army/Shop/Settings/Social makes THAT tab gold + lifted, Battle returns to neutral brown styling.

### BUG-52: Non-Battle tabs show scenic background + Battle panel content bleeding through
- **Status**: **FIXED** by A2 (observed by A4 16:46) — VERIFIED via detector PASS. Owner: A2
- **Detector**: `_check_non_battle_tab_scenic_bleed` in `tests/test_screen_layout.gd` — flipped FAIL→PASS. Output: "PASS: non-Battle tab edges have clean UI background (L=0 R=0)". Left edge grass+stone dropped 350 → 0, right edge 2733 → 0.
- **Severity**: HIGH (UX — user flag 2026-04-21: "It is hard to read the details in army tab and other tabs because of the background screen. For Other tabs aside from Battle tab, it is okay to not have backgrounds e.g. buildings from Battle tab.")
- **File**: `scripts/ui/main_menu.gd::_build_scenic_background` (lines 636-...). `SceneLayer` is added to root at `move_child(scene, 0)` (line 644) — always behind all panels, always visible. Non-Battle tab panels only have 88% alpha backgrounds (line 959 `Color(0.15, 0.1, 0.06, 0.88)`) which is not enough to hide grass + buildings. Zoom of `/tmp/castle_clash_test/army_bg_zoom.png` also shows the Battle panel's "BATTLE" button text and "PLAY ONLINE (1v1)" leaking through — Battle panel might still be rendering under the army panel during/after tab switch.
- **Fix direction**: Either (a) hide SceneLayer (`scene.visible = false`) when `_current_tab != 2`, show when Battle tab is active; or (b) add opaque (alpha=1.0) panel background to Shop/Army/Social/Settings panels so scenic can't leak. Option (a) is cheaper — single toggle in `_select_tab` after the panel visibility loop. Also verify Battle panel's `play_btn` and child nodes get hidden properly when `battle_panel.visible = false`; the tween at line 1058-1059 fades old panel modulate and hides on callback — if a button child has its own modulate tween running (from `_start_battle_pulse`) it might not honor parent visibility until one full frame later.
- **Acceptance**: After fix, `_check_non_battle_tab_scenic_bleed` PASSES (both edge bands < 150 scenic px). User-visible: tapping Army/Shop/Settings/Social produces a clean dark-brown content panel with NO trees, grass, buildings, or Battle-tab UI visible.

### BUG-50: Red castle building placement — building visual sits at one cell, gray "occupied" tiles render at a different coordinate
- **Status**: OPEN — Owner: A5 (sim authoritative grid) + A2 (overlay rendering)
- **Detector**: NOT YET WRITTEN — requires `auto_screenshot.gd` extension that places a building in the red zone before capturing, then a detector that checks gray-tile bounding box vs building visual bounding box. Tracked separately.
- **Severity**: HIGH (gameplay correctness — placing a building in red zone marks the WRONG cells as occupied, blocking subsequent placements at correct spots and freeing up cells under the visible building)
- **User-reported (2026-04-18)**: "I do see a bug in red player castle, the building placed generates a gray, occupied tiles in another coordinates instead of under it"
- **Likely root cause**: `building_grid.gd` overlay coordinates assume player-0 mirroring (top-down) but use the same row/col → screen translation for player-1 (red) zone. After T-085 perspective flip + T-096 5×2 footprint, the per-team `(row, col) → (screen_x, screen_y)` map probably wasn't updated for team 1, so the visual sprite renders at the FLIP_PIVOT_Y-mirrored position while the gray-tile occupancy mask still draws at the un-mirrored coordinate.
- **Files to inspect**: `scripts/game/building_grid.gd` (overlay/ghost preview position), `scripts/game/building_visual.gd` (sprite anchor), `core/simulation.gd` `place_building` + grid->world conversions for team 1
- **Fix direction**: For red-team placements, mirror the gray-tile overlay through FLIP_PIVOT_Y the same way the building visual is mirrored. Add an integration test in `test_simulation.gd` that places a building in team-1 zone and asserts `sim.grid[row][col]` matches the screen-space position the player tapped.
- **Acceptance**: Place a building in red zone via autotest, then capture the screen — gray occupied tiles must overlap the building footprint exactly (not appear at a different (row,col) offset).

### BUG-43: Loading screen progress bar — 3 detached wood plank elements lined up at same Y
- **Status**: CLOSED 2026-07-17 — two separate defects unwound: (1) the ART was
  already fixed by the round-4 cap+tiled-rivet rebuild
  (`_build_wooden_progress_bar`, bar_y=990), which POSTDATES the 2026-04-18
  re-open evidence; verified at BOTH resolutions (godot --resolution 720x1280
  -- --autotest-loading → 4x crop shows one continuous bar; detector runs=1
  main=259px native / 181px @504x896). (2) the DETECTOR was a vacuous green —
  it sampled y=648, 43px above the rebuilt bar, found 0 wood runs and passed
  that as "continuous". Recalibrated resolution-aware (rows from design
  y 1024-1034 × h/1280), 0 runs = FAIL, three trough rows must each be one
  ≥75%-width run; wood|fill|shine all classed as bar content (the shine sweep
  carved false gaps).
- **Detector**: `_check_progress_bar_pixel_continuity` — recalibrated 2026-07-17, trusted at 504×896 and 720×1280.
- **Severity**: HIGH (visual — broken polish, makes T-098 work look unfinished)
- **File**: `scripts/ui/loading_screen.gd` (progress bar construction lines 113-185)
- **Evidence**: `/tmp/castle_clash_test/loading_000.png` (autotest 2026-04-18) and `/tmp/loading_progress_zoom.png` (cropped 504×140 → upscaled). Three separate wood-plank rectangles visible at y≈630, NOT a single continuous progress bar:
  - Left plank: red bar over wood — looks like an old/legacy bar element
  - Middle plank: wood with "Loading..." text floating ABOVE it (text not centered on the plank)
  - Right plank: thin wood-end stub
- **Likely root cause**: BigBar_Base + BigBar_Fill NinePatch construction is producing separate sprite instances or the NinePatch is being clipped/cropped wrong. Multiple sprites being placed where one stretched 9-patch should be.
- **Fix direction**: Use a single NinePatchRect with proper region_rect + patch_margin so the wood texture stretches as one unit. Verify `_create_progress_bar()` doesn't accidentally instance the texture multiple times in a row.

### BUG-44: Loading screen tip strip — NinePatch edge artifacts (visible thin lines top + bottom)
- **Status**: FIXED by A2 (2026-04-18), VERIFIED by A4 (2026-04-18) — same StyleBoxFlat sweep that fixed BUG-43 also cleaned up tip strip. Fresh autotest shows clean parchment panel under "Wall buildings redirect enemy paths…" tip text — no doubled edge lines. Owner: A2
- **Severity**: MEDIUM (visual — distracts from tip readability)
- **File**: `scripts/ui/loading_screen.gd` (tip strip RegularPaper construction near line 185)
- **Evidence**: same `/tmp/loading_progress_zoom.png` — 2 thin horizontal lines visible at top of tip area + 2 at bottom, suggesting the NinePatch edge regions are rendering doubled or the Container is showing through gaps in the patch. Tip text "Wall buildings redirect enemy paths — use them to create chokepoints" wraps to 2 lines but the background edges appear as 4 thin parallel stripes instead of a clean parchment border.
- **Fix direction**: Inspect `RegularPaper.png` patch_margin values + verify the tip strip uses `NinePatchRect` not multiple stacked `TextureRect` instances. Consider replacing with `StyleBoxFlat` wrapped Panel for cleaner edge.

### BUG-45: Card hand text truncation — "Gold Mine" → "Gold M ne", LOCKED labels overlap building names
- **Status**: FIXED by A2 (2026-04-18), VERIFIED by A4 (2026-04-18) — fresh `/tmp/cardhand_v2.png` shows: (a) "Gold Mine" renders correctly (no more "Gold M ne" truncation — font_size sweep from BUG-41 fix is the cause), (b) LOCKED cards now stack labels vertically with no overlap: cost badge → LOCKED → "Need: PriestTe" requirement; building name + role labels hidden when locked. Minor cosmetic followup: long card names ("Lancer Barrack", "Siege Worksho") still get right-edge truncation — file as BUG-46 if user wants ellipsis treatment. Owner: A2
- **Severity**: HIGH (UX — affects every game card; user-visible "broken text")
- **File**: `scripts/ui/card_hand.gd` (text rendering around lines 358-370)
- **Evidence**: `/tmp/cardhand_zoom.png` (cropped 504×200 → upscaled in-game card hand). Visible text-rendering bugs:
  - `Gold Mine` rendered as `Gold M ne` (lowercase i missing — font glyph may be too narrow at the rendered size + insufficient label.size.x)
  - `Lancer Barracks` wrapping awkward with broken letter spacing
  - **LOCKED cards** show 3 overlapping labels: requires-building hint ("Need pries_ temp" with truncation) + building name ("Mage Tower") + role ("Spawner") + the big red "LOCKED" overlay — all at the same y position, all overlapping
- **Root cause**: Labels are positioned at same Y inside the card with no z-index management or visibility toggle when LOCKED. Programmatic loop in `_build_card` likely adds all sub-labels regardless of LOCKED state.
- **Fix direction**: When card is LOCKED, hide the building name + cost + role labels (only show LOCKED + the requirements hint). When unlocked, hide the requirements hint. Also bump font sizes per BUG-41 fix sweep so "Gold Mine" doesn't truncate.

### BUG-42: Castle attack VFX uses stale enemy castle Y after T-096
- **Status**: FIXED by A2 (2026-04-18), VERIFIED by A4 (2026-04-18) — game_arena.gd:622 now `var castle_y: float = 920.0 if hit_team == 0 else 120.0`. Matches T-096's CASTLE_1_Y move. Sim 365/365 unchanged. Visual alignment best-confirmed by playtest but the source change is one-line and matches the simulation constant directly. Owner: A2
- **Severity**: MEDIUM (visual — enemy castle hit VFX renders 50px above the actual castle position)
- **File**: `scripts/game/game_arena.gd:620-621`
- **Root cause**: Hardcoded `var castle_y: float = 920.0 if hit_team == 0 else 70.0` predates T-096's symmetric Y move. Team 1 castle is now at y=120 (was 70). Attack VFX (hit flash + damage numbers) for hits to enemy castle render at the old y=70 position, 50px above where the castle visual actually sits.
- **Fix**: Update line 621 to `var castle_y: float = 920.0 if hit_team == 0 else 120.0`. Better: read the value from the simulation's `CASTLE_0_Y`/`CASTLE_1_Y` constants exposed via GameManager rather than hardcoding.
- **Acceptance**: VFX visibly aligns with castle sprite center on hits to both castles. Verify with `godot --path castle_clash -- --autotest` and inspect game_*.png frames during enemy castle hits.

### BUG-41: Sub-12px text on multiple screens fails mobile readability
- **Status**: **FIXED** by A2 (2026-04-18, observed by A4 18:54) — VERIFIED via detector. Owner: A2
- **Detector**: `_check_low_contrast_text` in `tests/test_screen_layout.gd` — flipped FAIL→PASS. Output: "PASS: no low-contrast (small + faded + un-outlined) labels found". A2 fix confirmed at main_menu.gd:80-88 (tagline now font 15 + alpha 1.0 + outline 3), :180-182 (trophy text alpha 1.0 + outline 2), :253-256 (mode_desc alpha 1.0 + outline), :1681 (army tab type_lbl bumped). All three previously-flagged Color(...alpha < 0.95) labels now have alpha 1.0 + outline_size 2-3.
  - **(a) Main menu tagline** (`main_menu.gd:80-82`): "Build towers, spawn units, destroy the enemy castle!" rendered at **font_size=13** + color `(0.75, 0.7, 0.55, 0.9)` — light tan with 90% alpha — directly on the GREEN scenic background (no card / parchment behind it). Evidence: `/tmp/castle_clash_test/menu_tagline_zoom.png` (4× zoom). Tan-on-green = ~2:1 contrast ratio (WCAG AA needs 4.5:1).
  - **(b) Army tab unit type label** (`main_menu.gd:1559-1562`): "Physical atk | Light armor" / "Magic atk | Heavy armor" rendered at **font_size=12** + color `(0.6, 0.58, 0.5, 0.7)` — gray-tan with 70% alpha — on dark blue card background. Evidence: `/tmp/castle_clash_test/army_zoom.png` (3× zoom). Stat-label (HP/DMG/SPD) at 12px+0.9 alpha is borderline; type-label at 12px+0.7 alpha is the worst offender.
- **Severity**: HIGH (UX — user-reported: "make sure all text are readable from mobile perspective. This includes every screen")
- **Files**: `scripts/ui/main_menu.gd`, `scripts/ui/card_hand.gd`, `scripts/game/game_arena.gd`
- **Severity**: HIGH (UX — user-reported: "make sure all text are readable from mobile perspective. This includes every screen")
- **Files**: `scripts/ui/main_menu.gd`, `scripts/ui/card_hand.gd`, `scripts/game/game_arena.gd`
- **Root cause**: Industry mobile-readability minimum is ~14px body text. Current codebase uses 8-11px in many spots, especially on the main menu Army/Shop/Battle tabs and in-game card hand.
- **Inventory of sub-12px text** (most critical first):
  - **8px** — `main_menu.gd:371` `unit_lbl` in card preview (basically illegible at 720×1280 scaled to 5–6" phone)
  - **9px** — `card_hand.gd:359` building name when length > 12 chars (e.g., "Champion's Hall", "Priest Temple", "Royal Stable" all trigger 9px), `main_menu.gd:341` deck-card name preview, `main_menu.gd:1380` Army-tab `type_lbl` (attack type / armor type line)
  - **10px** — `main_menu.gd:350` deck-card cost, `:362` tier stars, `:1374` Army-tab `stat_lbl` (HP/DMG/SPD/RNG/ARM line), `:1387` Army-tab `skill_lbl`
  - **11px** — `main_menu.gd:170` arena banner trophy text, `:243` mode description (Blitz/Mirror), `card_hand.gd:359` default building name (≤12 chars), `game_arena.gd:758` perk indicator on battle screen
  - **13px** — `main_menu.gd:78` faction description tagline (borderline — readable but tight)
- **Visible-evidence frames**: `/tmp/castle_clash_test/game_001.png` thru `game_010.png` (720×1280 native capture, 2026-04-18). Card hand text labels (building names + costs + stats) and HUD top bar (`Time 0:25 | HP 5000 | Foe 5000`) are the most affected at this resolution.
- **Recommended fix sweep** (A2 to apply consistently):
  - All body labels: minimum 14px
  - Stats / sub-labels: minimum 12px
  - Drop the 8px and 9px sizes entirely — replace with 12px (and shorten label text instead of shrinking font)
  - Card-name labels: use 13px with text truncation/ellipsis when name > 10 chars instead of falling back to 9px
  - Re-verify with `godot --path castle_clash --resolution 720x1280 -- --autotest` and visual review of /tmp/castle_clash_test/game_*.png
- **Out of scope here**: in-game floating damage numbers (different UX category — they're meant to be quick reads, current 13/17px is fine).

---

## REMAINING VISUAL ISSUES (Visual Agent)

1. **Ground textures**: Use terrain Tileset PNGs, not flat ColorRects
2. **Main menu**: SpecialPaper background hidden by opaque panels
3. **Loading screen**: Doesn't exist
4. **Unit scale**: Too small for mobile at 720x1280

## File Ownership Reference
| Agent | Owned Files |
|-------|-------------|
| **Mechanics** | `core/simulation.gd`, `data/`, `core/command*.gd` |
| **Visual** | `scripts/game/sprite_*.gd`, `scripts/ui/*.gd`, `autoload/sprite_registry.gd`, `scenes/*.tscn` |
| **QA** | This file, test verification, `tasks/` |
| **Shared** | `scripts/game/game_arena.gd` — coordinate via `memory/` notes |
