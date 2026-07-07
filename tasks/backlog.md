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
| 1A-1 | Canvas-transform-inverse for screen→grid in building_grid.gd (place :272, sell :352, radial :374) — pattern exists at :173 | A2 | 1A | RED zoom-input scenario: ghost+placement land on tapped cell at zoom≠1 |
| 1A-2 | Dedup emulated-mouse vs touch (ignore DEVICE_ID_EMULATION mouse) — fixes tap-to-place on mobile | A2 | 1A | `emulated_mouse_dedup` scenario asserts single commit |
| 1A-3 | Hand-rolled two-finger pinch-zoom + pan from ScreenTouch/ScreenDrag; enable Android pan-and-scale | A2 | 1A | `pinch_zoom_pan` scenario asserts camera transform |
| 1A-4 | Radial menu at true cell center; scale hit radius by zoom; kill double-fire path | A2 | 1A | `radial_menu_under_zoom` scenario (see BUG-34) |
| 1A-5 | Reparent Blocked!/no-gold popup + info panel to UILayer; wheel-zoom event.pressed guard; zoom-to-cursor; ZOOM_MIN 1.0 | A2 | 1A | popup renders in screen space regardless of pan/zoom |
| 1B-1 | Commit lockstep rework; build.sh → hashed deploy; verify served artifacts | A1 | 1B | live build no longer runs pre-fix current_tick+1 race |
| 1B-2 | Surface lobby aborts (version_mismatch/config_timeout) in main_menu instead of hanging on "Starting…" | A2 | 1B | abort reason shown, no infinite spinner |
| 1B-3 | Total command ordering: per-player seq number; sort (player_id, seq) | A1 | 1B | test_multiplayer.gd asserts deterministic apply order |
| 1B-4 | Freeze match on desync (stop simulating divergent games behind overlay) | A1 | 1B | on checksum mismatch sim halts |
| 1B-5 | Stronger checksum (gold + next_entity_id, order-sensitive rolling hash; dense first 200 ticks) | A1/A5 | 1B | replaces order-insensitive XOR at simulation.gd:431-446 |
| 1B-6 | Integration test send→flush→stall→commit across frame boundaries; two-client Nakama + 2-tab | A1 | 1B | BUG-DESYNC1 stall-boundary scenario red on pre-fix, green on fixed |
| 1C-1 | Walk-cadence divisor bug (game_arena.gd:729 px/sec vs px/tick) — units foot-skate at ~10% cadence | A2 | 1C | see BUG-40; per-cycle displacement ≈ 1 body width |
| 1C-2 | Make hit-stop real (pause sprite + skip position sync during stop) or delete the claim | A2 | 1C | no position drift during hit-stop |
| 1C-3 | Impact timing: delay damage number/flash to strike frame (melee) / projectile arrival (ranged); arrow impact puff | A2 | 1C | damage number fires on impact frame |
| 1C-4 | Dedupe attacker swing VFX on AoE multi-victim events | A2 | 1C | one swing VFX per attack, N hit VFX |
| 1C-5 | Delete dead flow-field/LOS/aggro code paths; fix docs to match straight-line reality (Decision 3) | A5 | 1C | behavior audit still green; docs updated |
| 1C-6 | Guard/stub set_walk_speed_ratio on procedural fallback (per-frame error spam) | A2 | 1C | no runtime errors on fallback unit |
| 1D-1 | Route ability_activated sim event → EventBus → VFX/SFX (enemy War Horn/Blood Totem invisible+inaudible today) | A5→A2 | 1D | enemy ability produces VFX+SFX on both clients |
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
