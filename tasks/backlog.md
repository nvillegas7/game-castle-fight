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
| ~~1B-2~~ | ✅ DONE Surface lobby aborts in main_menu (NetworkManager.match_error → message + retry, version_mismatch → "refresh browser") | A2 | 1B | — |
| ~~1B-4~~ | ✅ DONE Freeze match on desync (GameManager._on_desync_detected → MATCH_OVER + set_process(false)) | A1 | 1B | — |
| ~~1B-5~~ | ✅ DONE (453725a) order-sensitive checksum covering all mutable state + subchecksums + state dump. TODO(minor): dense checksum send in first 200 ticks | A1/A5 | 1B | — |
| 1B-6 | ⏳ DEFERRED (dedicated task): extract LockstepPeer (RefCounted, injected transport+clock) → two-peer headless harness with FakeRelay + BUG-DESYNC1 stall-boundary scenario. Note: test_multiplayer `_test_two_sim_json_wire_lockstep` already covers 520-tick determinism + dup/out-of-order delivery; this adds staging/stall-timing coverage. Risky refactor of live net code — do carefully. | A1 | 1B | BUG-DESYNC1 scenario red on +1 staging, green on +2 |
| ~~1C-1~~ | ✅ DONE (a7efa38) Foot-skate fixed — CombatTuning.walk_ratio_for_speed (px/tick baseline 4.48, was px/sec 44.8). test_combat_feel 5/0 | A2 | 1C | — |
| ~~1C-2~~ | ✅ DONE (d84d354) Hit-stop real — freeze sprite frame + hold position on impact (is_in_hitstop guard) | A2 | 1C | — |
| ~~1C-5~~ | ✅ DONE Removed ~171 lines dead code (_separate_units, LOS helpers, combat_flow_fields, _cell_team_count, hysteresis). Kept aggro_range (in checksum) + flow_fields (tool reads it). Golden byte-identical → zero behavior change. | A5 | 1C | — |
| ~~1C-6~~ | ✅ DONE (a7efa38) set_walk_speed_ratio added to procedural fallback — no more per-frame error | A2 | 1C | — |
| ~~1D-1~~ | ✅ DONE (060f5b9) EventBus.ability_activated signal + game_manager dispatch arm (event was dropped) + game_arena ring/SFX for BOTH teams from sim-confirmed event. test_combat_feel 8/0 | A5→A2 | 1D | — |
| 1D-6 | Rally/Rage buff readability: brief tint or speed-lines on buffed units | A2 | 1D | buffed units visually distinct |

## New (2026-07-10)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|

## Phase 2 — Architecture enablers (sequential, shared files, no rewrite)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| 2.3 | ⏳ PARTIAL: project Theme via gui/theme/custom ✓; default font = Pixel Operator Bold (e0e35b4, replaced NinjaNormal for readability — user-flagged; CC0, crisp import flags). TODO: MorkDungeon title-font variation for headings; shared `ui_style.gd` for StyleBoxes | A2 | 2 | readable global font ✓ |
| 2.4 | ~~Shared scenic_background.gd~~ DOWNGRADED 2026-07-18: the "250-line verbatim copy" premise is stale — the two builders diverged; difflib measures only ~62 verbatim lines in 5 scattered blocks. Unifying two approved screens for that is a bad trade; revisit only if a third scenic consumer appears | A2 | 2 | (annotated, not planned) |
| 2.5 | ✅ CORE DONE — retriaged 2026-07-21: the "80+ private reads / O(n²)" premise was stale (measured 48 `GameManager.simulation.*` sites, most through legit API). The real hot-path cost was `_find_entity_by_id` = a LINEAR scan called per unit per tick from targeting/combat. Fixed: self-healing O(1) `_entity_index` + public `get_entity()` (core/simulation.gd); 10 internal + 9 external callers migrated. test_sim_facade 10/10, replay golden byte-identical. | A5 | 2 | — |
| 2.5b | Low-value cleanup (optional): migrate the ~30 raw `.entities`/`.players`/`.castles` reads in UI/visual files to `get_entity`/existing API + add `z_layers.gd` z-index constants. No perf impact (these are cold paths); do only if a screen touches them anyway. | A2 | 2 | fewer private sim pokes from the view layer |

## Phase 3 — UI/UX parity polish (parallel per-screen on the new theme)

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| 3.2 | Battle tab: single CTA hierarchy (merge BATTLE ribbon + PLAY ONLINE), legible inactive tab labels, progression display restored | A2 | 3 | per-screen golden + layout assertions |
| 3.3 | Battle-zone READABILITY (HUD): gold elixir-bar fill + cheapest-card marker, locked cards→grayscale+padlock, wave preview strip | A2 | 3 | golden diff; no permanent red-card noise |
| 3.4 | Mobile hardening: ability/wrath buttons ≥88px, safe-area insets on header/tab bar, tap-and-hold replaces hover | A2 | 3 | layout assertion: touch targets ≥88px |
| 3.8 | Theme rollout: migrate remaining screens to Theme/ui_style; delete per-label overrides | A2 | 3 | per-screen golden after migration |

## Open bugs (qa-bug-tracker.md) — fold into the phase above they belong to

| ID | Item | Domain | Phase | Detector / Acceptance |
|----|------|--------|-------|-----------------------|
| BUG-40 | Walk animation cadence vs move speed (PENDING LIVE PLAYTEST) | A2 | 1C | HIGH; overlaps 1C-1; needs human eyes on windowed game |
| BUG-35 | MP command delivery unverified — no ACK/retransmit (P2 hardening, superseded by DESYNC1) | A1 | 1B | P2; overlaps 1B-6; explicit ACK + bounded retransmit |
