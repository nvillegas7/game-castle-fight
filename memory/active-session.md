# Active Session — UI/UX Polish + Gameplay Verification Pass (2026-07-02)

## Mission (from Neil)
Before any new features: polish all screens to Kingdom Rush / Clash Royale bar, verify+fix current gameplay
(blast skill = Castle Wrath, building placement, unit fighting, camera zoom/scroll, placement-under-zoom,
multiplayer sync error). Also: build more efficient test tooling to replace manual screen recording.

## In flight
- Audit workflow `wf_e43d8130-1aa` (6 areas: ui-ux, blast-skill, placement-zoom, camera, combat, multiplayer) — running
- Scenario harness builder agent — building `--scenario` mode + input injection + contact sheet — running
- Fresh autotest captures at /tmp/castle_clash_test/ (done)

## Baseline (all green before changes)
- test_simulation.gd 373/373, test_multiplayer.gd 76/76, test_behavior_audit.gd 24/24
- test_screen_layout.gd 11 pass / 2 FAIL: BUG-47 (tree z-clip over spire), BUG-49 (edge-clipped ribbons)

## My design-lead review of fresh captures (A0 eyes, 504x896)

### Loading screen
- Flat single-tone green background everywhere — clouds are darker-green blobs on green "sky". No sky
  gradient. Reads unfinished vs Tiny Swords reference (blue sky expected).
- Tip panel style clashes: gray/blue default-theme panel + thin gold corners vs wooden/pixel theme.
- Progress bar small, red-on-brown, floats disconnected below island. (BUG-43 detector now PASSES though.)

### Main menu Battle tab
- Tagline text floats bare on green — no panel, placeholder feel.
- BATTLE ribbon: low-contrast beige-on-tan text, doesn't read as dominant CTA (CR bar: huge, gold, glowing).
- "PLAY ONLINE (1v1)" flat dark-green rectangle — style inconsistent with wooden theme.
- Stray single coin icon floating top-center under header.
- Tab bar labels ~10px, "Social" icon is an info-circle (wrong metaphor).
- Symmetric copy-paste tree rows flank castle. BUG-47 + BUG-49 confirmed by detectors.
- Top bar "Commander / New Commander" plain text, no trophy/level badge visuals.

### Battle screen (game_004)
- Middle combat zone: large flat green expanse, washed-out dirt strips, sparse decor — far from KR density.
- Side rails (dark teal) have noisy random pixel dots/flags — look unfinished.
- Gold ribbon spans full width but "40g (+20/5s)" text tiny/left; not CR elixir-bar quality.
- HUD top: plain text "Time 0:20 / HP 5000 | Foe 5000" — no castle HP bar visuals.
- Card hand: pervasive text truncation ("ArcherRang", "Lancer Barrack", "Siege Worksho", "Need:PriestTe",
  "Need:Siege Wo", "Need: Knight H"). Cards mostly dark empty space, art tiny.

### End screen (victory) — WORST screen
- Translucent gray panel floats over still-visible battlefield; 3 stars render at TOP OF SCREEN overlapping
  the enemy castle, disconnected from the panel.
- "Trophies: +30 (750 — Commander)" green text overlaps flag/building sprites; another text line under it
  collides with sprites (unreadable).
- CARD HAND + GOLD RIBBON STILL VISIBLE during end screen — screen doesn't take over.
- Stat rows plain brown bars. No visible confetti/MVP in capture.

### Army tab — closest to shippable
- Clean readable cards BUT portraits show BUILDING sprites, not units (Footman row = barracks house).

### Shop tab
- Sparse: unlabeled avatar grid on flat brown, no frames/prices, "Daily Pick" 10px.

### Social tab — BROKEN/EMPTY
- Completely empty dark brown screen with faint empty rectangles. Ship-blocker: populate or remove tab.

## Known open bugs (qa-bug-tracker)
- BUG-47, BUG-49 (detector-confirmed, above)
- BUG-34 radial menu dismiss race (todo.md says QA_REVIEW fix, tracker says OPEN — reconcile)
- BUG-50 red-side building placement: visual cell != occupied overlay cell (mirror-perspective suspect)
- BUG-43 loading bar re-opened by user, but detector passes now — needs re-check on 720x1280
- T-094/T-095: Castle Wrath EventBus wiring + HUD button + shockwave VFX were never-landed follow-ups

## Progress
- Audit workflow DONE: 49 findings, 12 confirmed HIGH (2 refuted). Full summary at
  /private/tmp/claude-501/-Users-paulinecolobong-game/485a59cf-e24a-41b7-91d8-20437a4a7881/scratchpad/audit_summary.txt
- Plan written to tasks/todo.md "Phase 3.5" section.
- WAVE 1 COMPLETE (4 agents, all suites green):
  - 1A main_menu: trophy header live, settings-dup fix, replay-tutorial disabled, 9-patch tab backdrop,
    press feedback + shared button style, tab-drift fix, Social tab (match record), BATTLE contrast.
  - 1B sim pipeline: wrath EDGE-distance radius, consume-after-guard + castle_wrath_refused signal,
    killing-blow events carry target_x/y (10 sites), bounty in entity_died, building_destroyed reason
    sold/killed. Tests 373→395. NEW CONTRACTS: unit_died(unit_id,killer_id,bounty,pos_x,pos_y),
    building_destroyed(building_id,reason), castle_wrath_refused(team,reason).
  - 1C multiplayer: content-hashed web deploy (build.sh rewrites index.html refs; _headers interim
    max-age=300), BUILD_ID handshake in MATCH_CONFIG (version from project.godot stamped by build.sh),
    dual-player-0 abort, CONFIG_ACK retry, perks shared online, leave_match on reset + null guards,
    buffered checksum compare. Tests 76→123 incl 520-tick two-sim JSON-wire lockstep.
    NEW: NetworkManager.match_error(kind,message) signal needs UI wiring (game_arena + menu).
  - 1D match/flow UI: HUD castle HP bars, card text >=12px + wrap/ellipsis, end-screen ribbon/backdrop/
    star anchoring, loading sky gradient + themed tip panel.
- WAVE 2 CANCELLED BY USER before any edits landed (tree verified clean of its changes; building_grid.gd
  untouched, game_arena.gd only has W1B's handler edits). Awaiting user direction before redoing. Scope was:
  placement screen→world under zoom, BUG-50 view_flipped keying,
  ENEMY_ZONE_Y 55→65 (+tscn), touch pinch/pan + zoom-to-cursor + smoothing + ZOOM_MIN 1.0, shake→
  camera.offset, walk ratio /10 (baseline 4.48 px/tick), wrath button team check + refused feedback +
  SFX on activated, match_error wiring, ability ring sim_to_screen, death anims, hitstop sprite pause,
  attack coroutine generation, end-screen takeover (hide card hand/gold bar), test_audio_visual handlers.
- HARNESS AGENT still running (tests/scenarios/, tools/, main.gd --scenario mode).

## Next steps
1. Collect Wave 2 + harness results; run scenarios (place_building_zoomed + castle_wrath should PASS now)
2. Wave 3 QA: recalibrate BUG-47/49 detectors (scenery redesigned — current fails are false positives),
   update qa-bug-tracker (BUG-34 fixed, BUG-43 closed-refuted, BUG-47/49 resolved-by-redesign, BUG-50 fixed),
   full suite + fresh autotest + contact sheet + balance re-run (baseline 48/52), visual review of captures
3. Commit in logical chunks (tree had ~9.5k uncommitted lines BEFORE this session — separate those)
4. Wave 4 (test-first, deferred): aggro gating/MARCH lanes, LOS decision, flow-field wire-or-delete,
   AI uses wrath, army tab unit portraits

## Note: previous content of this file (2026-04-07 QA handoff) superseded; see git history if needed.
