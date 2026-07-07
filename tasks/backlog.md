# Backlog — OPEN work only

Live task list for the Polish-to-Parity campaign. Replaces `dispatch.md`.
Delete a row when it lands (git history is the log). Detail for BUG-* rows lives in
`qa-bug-tracker.md`; process rules in `PROCESS.md`; full plan in `plan-polish-parity.md`.

Domain = subagent scope (see PROCESS §6). Detector/Acceptance = the RED artifact required
before the fix, or the passing criterion.

---

## Phase 1 — Correctness: the six reported areas (parallel worktrees, detector-first)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| ~~1A-1~~ | ✅ DONE (2701d96) Canvas-transform-inverse for screen→grid — place under zoom fixed; place_building_zoomed 5/0 | A2 | 1A | — |
| ~~1A-2~~ | ✅ DONE (fa508cb) Dedup emulated-mouse vs touch — mobile tap-to-place fixed; place_building_touch RED→GREEN + touch harness added | A2 | 1A | — |
| 1A-3 | Hand-rolled two-finger pinch-zoom + pan from ScreenTouch/ScreenDrag; enable Android pan-and-scale | A2 | 1A | `pinch_zoom_pan` scenario asserts camera transform |
| 1A-4 | Radial menu at true cell center; scale hit radius by zoom; kill double-fire path | A2 | 1A | `radial_menu_under_zoom` scenario (see BUG-34) |
| 1A-5 | ⏳ PARTIAL (6ea781f: wheel event.pressed guard + ZOOM_MIN 1.0 done). TODO: reparent Blocked!/info popup to UILayer; zoom-to-cursor; fix middle-drag pan (consumed by STOP ColorRect) | A2 | 1A | popup renders in screen space regardless of pan/zoom |
| 1B-1 | ⚠️ NEEDS USER: sync fix is committed (bdb34e6); deploy it — `cd castle_clash && ./build.sh` (needs brotli+wrangler+Cloudflare auth). Live build predates the fix. | A1 | 1B | served index.<hash>.pck newer than Apr 19 |
| ~~1B-2~~ | ✅ DONE Surface lobby aborts in main_menu (NetworkManager.match_error → message + retry, version_mismatch → "refresh browser") | A2 | 1B | — |
| 1B-3 | Total command ordering: per-player seq number; sort (player_id, seq) | A1 | 1B | test_multiplayer.gd asserts deterministic apply order |
| ~~1B-4~~ | ✅ DONE Freeze match on desync (GameManager._on_desync_detected → MATCH_OVER + set_process(false)) | A1 | 1B | — |
| ~~1B-5~~ | ✅ DONE (453725a) order-sensitive checksum covering all mutable state + subchecksums + state dump. TODO(minor): dense checksum send in first 200 ticks | A1/A5 | 1B | — |
| 1B-6 | ⏳ DEFERRED (dedicated task): extract LockstepPeer (RefCounted, injected transport+clock) → two-peer headless harness with FakeRelay + BUG-DESYNC1 stall-boundary scenario. Note: test_multiplayer `_test_two_sim_json_wire_lockstep` already covers 520-tick determinism + dup/out-of-order delivery; this adds staging/stall-timing coverage. Risky refactor of live net code — do carefully. | A1 | 1B | BUG-DESYNC1 scenario red on +1 staging, green on +2 |
| ~~1C-1~~ | ✅ DONE (a7efa38) Foot-skate fixed — CombatTuning.walk_ratio_for_speed (px/tick baseline 4.48, was px/sec 44.8). test_combat_feel 5/0 | A2 | 1C | — |
| ~~1C-2~~ | ✅ DONE (d84d354) Hit-stop real — freeze sprite frame + hold position on impact (is_in_hitstop guard) | A2 | 1C | — |
| 1C-3 | Impact timing: delay damage number/flash to strike frame (melee) / projectile arrival (ranged); arrow impact puff | A2 | 1C | damage number fires on impact frame |
| 1C-4 | Dedupe attacker swing VFX on AoE multi-victim events | A2 | 1C | one swing VFX per attack, N hit VFX |
| ~~1C-5~~ | ✅ DONE Removed ~171 lines dead code (_separate_units, LOS helpers, combat_flow_fields, _cell_team_count, hysteresis). Kept aggro_range (in checksum) + flow_fields (tool reads it). Golden byte-identical → zero behavior change. | A5 | 1C | — |
| ~~1C-6~~ | ✅ DONE (a7efa38) set_walk_speed_ratio added to procedural fallback — no more per-frame error | A2 | 1C | — |
| ~~1D-1~~ | ✅ DONE (060f5b9) EventBus.ability_activated signal + game_manager dispatch arm (event was dropped) + game_arena ring/SFX for BOTH teams from sim-confirmed event. test_combat_feel 8/0 | A5→A2 | 1D | — |
| 1D-2 | Fireball splash uses event payload coords (kill live sim re-lookup) | A5/A2 | 1D | splash VFX at event-reported center |
| 1D-3 | castle_wrath_refused → button shake/toast; ready-chime only for LOCAL player's castle | A2 | 1D | refusal feedback shown; chime not cross-fired |
| 1D-4 | Emit skill_proc for the six silent skills or delete their dead VFX/SFX branches | A5 | 1D | each skill either fires or has no dead branch |
| 1D-5 | Offline AI uses Castle Wrath; fix test_multiplayer.gd to use a real ability id | A5 | 1D | test_multiplayer.gd references valid ability |
| 1D-6 | Rally/Rage buff readability: brief tint or speed-lines on buffed units | A2 | 1D | buffed units visually distinct |

## Phase 2 — Architecture enablers (sequential, shared files, no rewrite)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| 2.1 | Extract opponent AI → `arena_ai.gd` (ends game_arena.gd SHARED contention; balance suite then tests the REAL AI) | A5 | 2 | balance suite green against extracted AI |
| 2.2 | Extract terrain/decoration builder → `arena_terrain.gd` (~670 one-shot lines) | A2 | 2 | pixel-identical autotest captures (golden diff) |
| 2.3 | Shared style module `ui_style.gd` + project Theme resource with MorkDungeon.ttf defaults | A2 | 2 | highest-leverage visual change; theme applied |
| 2.4 | Shared `scenic_background.gd` (delete the 250-line verbatim copy) | A2 | 2 | one source, both callers use it |
| 2.5 | Sim read facade (O(1) get_entity, castle_ratio, player_gold) + `z_layers.gd` constants | A5/A1 | 2 | removes 80+ private reads / per-frame O(n²) scans |

## Phase 3 — UI/UX parity polish (parallel per-screen on the new theme)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| 3.1 | Re-enable buried features: tutorial (gate games_played==0), game-mode selector (Blitz/Mirror). Faction selection DEFERRED (Decision 2) | A2 | 3 | tutorial + mode selector reachable |
| 3.2 | Battle tab: single CTA hierarchy (merge BATTLE ribbon + PLAY ONLINE), legible inactive tab labels, progression display restored | A2 | 3 | per-screen golden + layout assertions |
| 3.3 | Battle-zone readability: lane markings through dead mid-band, gold elixir-bar fill + cheapest-card marker, locked cards→grayscale+padlock, wave preview strip | A2 | 3 | golden diff; no permanent red-card noise |
| 3.4 | Mobile hardening: ability/wrath buttons ≥88px, safe-area insets on header/tab bar, tap-and-hold replaces hover | A2 | 3 | layout assertion: touch targets ≥88px |
| 3.5 | End screen takeover: hide HUD/gold bar/card hand behind results; restore on replay | A2 | 3 | golden: results screen has no bleed-through |
| 3.6 | Army tab: real unit sprites (not spawner buildings), tappable detail popup, de-spreadsheet rows | A2/A6 | 3 | golden + tap scenario |
| 3.7 | Shop→Avatars rename + Social "Coming Soon!" empty state (Decision 1) | A2 | 3 | polished empty state, no economy work |
| 3.8 | Theme rollout: migrate remaining screens to Theme/ui_style; delete per-label overrides | A2 | 3 | per-screen golden after migration |

## Open bugs (qa-bug-tracker.md) — fold into the phase above they belong to

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| BUG-32 | Roof icon decorations barely visible on upgraded buildings (3-5px on screen) | A2 | 3 | HIGH; double icon sizes / add outline; detector TBD |
| BUG-50 | Red-castle placement: building visual and gray "occupied" tiles at different coords | A5+A2 | 1A | HIGH; needs place-in-red-zone capture detector + sim assert |
| BUG-40 | Walk animation cadence vs move speed (PENDING LIVE PLAYTEST) | A2 | 1C | HIGH; overlaps 1C-1; needs human eyes on windowed game |
| BUG-43 | Loading bar renders as 3 detached wood planks at 720×1280 (RE-OPENED) | A2 | 3 | HIGH; `_check_progress_bar_pixel_continuity` needs resolution-aware calibration |
| BUG-47 | Main-menu tree foliage z-clips church/cottage spire | A2 | 3 | MEDIUM; `_check_tree_spire_zindex` currently FAILS |
| BUG-49 | Main-menu ribbon/flag decorations clipped at screen edges | A2 | 3 | LOW; `_check_ribbon_edge_clipping` currently FAILS |
| BUG-34 | Radial menu dismiss races with button click (can't sell/inspect in MP) | A2 | 1A | MEDIUM; overlaps 1A-4; kill deferred double-dismiss |
| BUG-30 | Card bottom-text overlap in 2-row layout | A2 | 3 | MEDIUM; hide stats when card h<110 |
| BUG-29 | Gold coin icon far from gold text in battle HUD | A2 | 3 | LOW; left-align gold label |
| BUG-35 | MP command delivery unverified — no ACK/retransmit (P2 hardening, superseded by DESYNC1) | A1 | 1B | P2; overlaps 1B-6; explicit ACK + bounded retransmit |
