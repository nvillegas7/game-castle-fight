# Castle Fight -- Master Task List

## Phase 0: Foundation
- [x] Deep research on Castle Fight mechanics
- [x] Research multiplayer architecture & server costs
- [x] Analyze mobile vs web platform decision
- [x] Research monetization & profitability strategies
- [x] Design the expert agent team
- [x] Write Game Design Document (GDD)
- [x] Set up Godot 4 project skeleton
- [x] Set up git repository

## Phase 1: Web MVP (Months 1-4)
- [x] **Core Simulation**
  - [x] Deterministic game loop (fixed-point math, fixed timestep)
  - [x] Grid-based building placement + sell buildings
  - [x] Wave spawn system (synchronized timer)
  - [x] Unit AI (targeting, auto-combat, healing, castle damage)
  - [x] Damage type / armor type matrix (4x4)
  - [x] Resource/income system
  - [x] Castle HP and win condition
- [x] **Factions (2 at MVP)**
  - [x] The Kingdom (5 buildings: Barracks, Archer Range, Priest Temple, Knight Hall, Siege Workshop)
  - [x] The Horde (5 buildings: War Camp, Axe Range, War Drums, Berserker Pit, Demolisher Works)
- [x] **Multiplayer**
  - [x] Nakama server setup (Docker Compose)
  - [x] Nakama Godot addon integration
  - [x] NetworkManager with auth, matchmaking, relay, lockstep
  - [x] GameManager lockstep tick waiting + checksum desync detection
  - [x] Offline mode preserved for local dev
  - [ ] Test with 2 browser tabs against local Nakama
  - [ ] Deploy Nakama to VPS for public play
- [x] **UI/UX**
  - [x] Main menu with faction selection
  - [x] Building placement UI (grid overlay, ghost preview)
  - [x] HUD (gold, wave timer, castle HP)
  - [x] End-of-match results screen (victory/defeat + restart)
  - [x] Unit health bars (green/yellow/red)
  - [x] Sell buildings (right-click)
  - [x] Simple AI opponent
  - [x] Castle HP bars on castle areas
  - [x] Wave announcement text
  - [x] Building tier indicators + unit name labels
  - [x] Play Online button with connection status
  - [ ] Basic tutorial / onboarding
- [ ] **Art (Placeholder -> Polish)**
  - [ ] Define chibi art style guide
  - [ ] Source/create placeholder sprites
  - [ ] Create map/arena tileset
- [x] **Audio**
  - [x] SFX throttling system (per-type cooldowns, global frame cap, intensity volume scaling)
  - [x] Audio bus architecture (Music/SFX/UI buses with independent volume)
  - [x] Music system overhaul (file-based with crossfade, procedural fallback)
  - [x] File-based SFX system (auto-scan variants, pitch randomization, no-repeat)
  - [x] UI sound integration (buttons, tabs, cards, hover, denied)
  - [x] Income tick and sell sounds
  - [ ] Download and integrate CC0 music tracks (menu, battle, victory, defeat)
  - [ ] Download and integrate CC0 SFX packs (combat, building, UI)
- [x] **Web Export**
  - [x] Godot HTML5 export (37MB total, ~12MB gzipped)
  - [ ] Deploy to itch.io
  - [ ] Set up domain with Cloudflare Pages

## Phase 1.5: Castle Fight Mechanics Alignment (COMPLETE)
> See `tasks/gamedev-plan.md` for full details

- [x] **Economy Rebalance**
  - [x] Starting gold 0, income 20g/5s, immediate first tick
  - [x] Kill bounty proportional to building cost
- [x] **Movement & Combat**
  - [x] Fix ranged/caster column-lock (full 2D chase)
  - [x] Fix melee phantom range attack
  - [x] Differentiate aggro/attack range per unit
  - [x] Improve unit spread (anti-clump + spawn jitter)
- [x] **Armor Formula**
  - [x] Switch to WC3 percentage-based: `dmg / (1 + armor * 0.06)`
- [x] **Stat Rebalance**
  - [x] Full 10-unit stat pass with Castle Fight ratios
- [x] **Flow Field Pathfinding + Maze Building**
  - [x] BFS flow field from castle goal
  - [x] Anti-block validation (rejects path-sealing placements)
  - [x] Wall (Kingdom) + Palisade (Horde) maze buildings
  - [x] Stuck unit recovery (teleport after 30 ticks)
- [x] **Buildings Attack Before Castle**
  - [x] Units target enemy buildings in their zone before castle
- [ ] ~~**Skill Expansion**~~ → Deferred to Phase 2C
- [x] **Spawn Timer**
  - [x] Cost-proportional spawn intervals (7-11s range)

## Phase 2: Production Polish (COMPLETE)
> 7-agent team (A0-A6). See `tasks/dispatch.md` for task detail (T-001 through T-088). See `tasks/design-gap-analysis.md` for benchmark analysis.
> **Benchmarks**: Kingdom Rush (battle), Clash Royale (menus), Castle Fight (strategy), Fort Guardian (animation smoothness)

### 2A: Core Visual Polish (QA_REVIEW)
- [x] Explosion/Fire/Dust effect sprites integrated (T-001, T-002, T-003) — QA_REVIEW
- [x] Building construction & destruction animations (T-004, T-005) — QA_REVIEW
- [x] Gold bounty floating text (T-006) — QA_REVIEW

### 2B: Onboarding & Menu Content
- [x] Tutorial design spec written (T-011) — QA_REVIEW
- [ ] Tutorial overlay system (T-012) — UNBLOCKED
- [ ] Tutorial simulation hooks (T-013) — UNBLOCKED
- [x] Settings tab — volume sliders, credits, replay tutorial (T-014) — QA_REVIEW
- [ ] Army tab — unit roster with stats and skills (T-015)
- [ ] Enhanced match results screen (T-017)

### 2C: Strategic Depth (PARTIALLY COMPLETE)
- [x] Second skill per unit — 10 new skills (T-019, T-020, T-021) — QA_REVIEW
- [x] Upgrade buildings — Armory, Blood Altar (T-023) — QA_REVIEW
- [ ] Smarter AI opponent (T-024)
- [ ] Balance pass — 45-55% faction win rate (T-025)

### 2D: Audio Polish
- [ ] Verify all 42 SFX play correctly (T-027)
- [ ] Verify 8 music tracks crossfade (T-028)
- [ ] Ambient battlefield sounds (T-030)

### 2E: Deploy & Multiplayer
- [ ] Test local multiplayer vs Nakama (T-032)
- [ ] Web export polish (T-034)
- [ ] Deploy to itch.io (T-035)

### 2F: Gap Analysis Iterations (HIGHEST PRIORITY — NEW)
> See `tasks/design-gap-analysis.md` for full analysis with benchmarks.

**Wave 0: Animation Smoothness (Fort Guardian reference — P0)**
- [ ] **Position interpolation** — store prev pos, lerp at 60fps (T-057 A1, T-058 A2)
- [ ] Hit-stop + attack timing contrast + smooth turns (T-059 A2)

**Wave 1: Foundation Polish (biggest visual impact)**
- [x] **Rename to "Castle Fight"** — done (T-051)
- [ ] KR 3-layer terrain — tiled textures, feathered transitions, decoration hierarchy (T-060 A2, P0)
- [ ] Faction-themed environmental decorations (T-061 A2)
- [ ] Battle button yellow/gold dominant redesign (T-037 A2, P0)
- [ ] Menu color hierarchy — Yellow CTA, Green positive, Red alert (T-038)
- [ ] Visual hierarchy — mute backgrounds, brighten interactables (T-039)

**Wave 2: Feel & Juice**
- [ ] Idle world animations — tree sway, water foam (T-049)
- [ ] Smooth tab transitions (T-047)
- [ ] Gold bar redesign — elixir-style, segmented (T-050)
- [ ] End screen overhaul — celebration, MVP, stats cards (T-048)

**Wave 3: Castle Fight Strategic Depth**
- [ ] Special buildings with active abilities — War Horn, Blood Totem (T-042, T-043)
- [ ] Compound income — Gold Mine gives % bonus (T-044)
- [ ] ~~Wave preview~~ — cancelled per user decision
- [ ] Building radial menu — tap to sell/info (T-045)
- [ ] Home screen progression — arena banner, trophy bar (T-046)

**Wave 4: Replayability**
- [ ] Pre-game perk selection — 3 per faction with upside+downside (T-053, T-054)
- [ ] Game mode variants — Blitz, Mirror Match (T-055, T-056)
- [ ] Logo creation (T-052)

## Phase 3: Production Ready — Aesthetics + Balance + Endgame Pacing (CURRENT, NEAR-COMPLETE)
> See `tasks/design-prod-ready.md`. Phase 3 wraps up production polish + unblocks prod deploy.

- [x] T-084 Mage replaces Champion (A5, QA_REVIEW)
- [x] T-089 Castle HP 10K → 5K for faster match resolution (A5, QA_REVIEW)
- [x] T-090 Castle Wrath panic button — sim side (A5, QA_REVIEW)
- [x] T-085 CR-standard perspective flip — Player 2 builds at bottom (A2, QA_REVIEW)
- [x] T-068 Army tab — single-faction roster with tier headers (A2, QA_REVIEW)
- [x] T-092 Logo finalization — rich scene with castles, units, ribbon (A6, QA_REVIEW)
- [x] T-086 Mage Tower sprite + BUILDING_MAP wire (A6+A2, QA_REVIEW)
- [x] BUG-27 Siege targeting — pick nearest instead of building-first (A5, QA_REVIEW)
- [x] BUG-28 Anti-air system — only archer/axe_thrower/gryphon/wyvern hit flying (A5, QA_REVIEW)
- [x] BUG-33 USE_ABILITY command handler (A5, QA_REVIEW)
- [x] BUG-34 Radial menu dismiss race fix (A2, QA_REVIEW)
- [ ] T-094 EventBus wiring — castle_wrath_ready + castle_wrath_activated signals (A1)
- [ ] T-090 Castle Wrath HUD button + shockwave VFX (A2, followup, pending ID T-095/96)
- [ ] Mage fireball VFX + main_menu Champion→Mage copy fix (A2, pending ID)
- [ ] T-093 Screen polish audit — every screen production-ready (A4)
- [x] BUG-DESYNC1 Multiplayer init mismatch (A1, P0) — user-reported FIXED 2026-04-17, awaiting A1 confirmation + commit
- [ ] BUG-36 Web audio — COOP/COEP + threading enablement (A1)
- [ ] T-091 Build zone behind castle — CANCELLED (covered by T-089+T-090)

## Phase 3.5: Polish & Correctness Blitz (2026-07-02, direct orchestration — no dispatch.md ceremony)
> Source: 6-area adversarially-verified audit (49 findings) + A0 capture review. Goal: KR/CR-bar screens,
> all current gameplay verifiably working, MP sync fixed, screen-recording replaced by scenario harness.

### Wave 0: Test infrastructure (in flight)
- [ ] Scenario harness: `--scenario` mode, input injection, state forcing, contact sheet (agent running)
- [ ] Two-sim JSON-wire lockstep test (500+ ticks checksum equality) — part of Wave 1C

### Wave 1A: Main menu (main_menu.gd/.tscn)
- [x] Trophy header wired (call _update_player_stats from _ready + after match), distinct trophy icon
- [x] Reset All Progress: stop stacking duplicate Settings UI (_build_settings_tab frees old container)
- [x] Replay Tutorial: hide/disable while tutorial globally disabled (no silent normal match)
- [x] Non-Battle tab background: replace raw SpecialPaper atlas (transparent gap bands) with seamless tile
- [x] Press feedback on all CTAs/tabs (0.96 scale down/up); shared wood button style on all raw Buttons
- [x] Tab switch: kill+reset slide tween (position drift on rapid switching)
- [x] Social tab: minimum viable content (match record W/L + themed "friends coming soon") or drop tab
- [x] BATTLE ribbon text contrast; PLAY ONLINE themed styling; remove stray floating coin icon

### Wave 1B: Sim + event pipeline (simulation.gd, game_manager.gd, event_bus.gd + minimal game_arena compat)
- [x] Castle Wrath radius: edge-distance (match _in_attack_range hw/hh) so max-range besiegers are hit; test
- [x] Wrath consume-after-null-check; emit castle_wrath_refused event (UI can skip SFX on no-op)
- [x] unit_attacked/entity_died events carry target x/y + bounty in payload; dispatch from payload not
      entity re-lookup (fixes dropped killing-blow visuals + dead bounty popup)
- [x] building_destroyed carries reason: "sold"|"killed" (fixes SOLD label on combat destroy + wrong SFX)
- [x] Keep 373 sim tests green; add tests for wrath edge-radius + killing-blow event delivery

### Wave 1C: Multiplayer sync (network_manager.gd, export/web/_headers, build.sh)
- [x] BUILD_ID in MATCH_CONFIG; mismatch → "new version available, refresh" abort (not checksum desync)
- [x] Web cache: content-hash pck/wasm/js filenames per deploy OR drop immutable + short max-age/ETag
- [x] Matchmaker fallback: abort if deduped user_ids != 2 (never dual-player-0 with different seeds)
- [x] Share perk in MATCH_CONFIG + pass through _begin_match (or hide perk banner online until then)
- [x] Teardown: leave_match/guard null command_buffer on late COMMANDS
- [x] Buffer unmatched remote checksums, compare when local catches up
- [x] Two-sim JSON-wire lockstep test as above

### Wave 1D: In-match + flow UI (hud.gd, card_hand.gd, end_screen.gd, loading_screen.gd)
- [x] HUD: real castle HP bars (own green / enemy red), drop dead gold no-op wiring
- [x] Card hand: all text >=12px, ellipsis/wrap instead of shrink, no right-truncation
- [x] End screen: ribbon out of container (fixed-size wrap), stars anchored to panel not screen-top,
      trophy text off the battlefield sprites (opaque backdrop)
- [x] Loading: sky gradient (blue above horizon per Tiny Swords ref), themed tip panel

### Wave 2: Arena input/camera/combat visuals (game_arena.gd, building_grid.gd, sprite_unit_visual.gd)
- [ ] Placement input: one screen→world helper via canvas transform for ghost/commit/sell/radial (zoom fix)
- [ ] BUG-50: overlay row-mirror keyed on view_flipped (not player_index); ENEMY_ZONE_Y 55→65 (=sim)
- [ ] Radial hit radius scaled by canvas zoom; Blocked!/No gold!/info panel into UILayer
- [ ] Camera: touch pinch-zoom + pan (ScreenTouch/ScreenDrag), wheel pressed-guard, zoom-to-cursor,
      ZOOM_MIN=1.0 (or expanded limits), smoothing lerp, multiplicative wheel steps
- [ ] Walk anim ratio /10 fix (px/tick baseline 4.48); hit-stop pauses sprite; death anims play;
      attack coroutine generation counter; wrath button only removed for local team's activation
- [ ] End screen takeover: hide card hand + gold ribbon on match end
- [ ] T-043 ability ring through sim_to_screen

### Wave 3: QA + docs
- [ ] Recalibrate/retire BUG-47/49 detectors (scenery redesigned — current fails are false positives)
- [ ] qa-bug-tracker updates: BUG-34 fixed, BUG-43 closed (refuted), BUG-47/49 resolved-by-redesign,
      BUG-50 fixed
- [ ] Full suite run + scenario run + fresh autotest + contact sheet; balance re-run (48/52 baseline)
- [ ] Commit in logical chunks (working tree has ~9.5k uncommitted lines from before this session)

### Wave 4 (follow-up, test-first): combat architecture
- [ ] aggro_range gating in _acquire_target + lane-following MARCH (units drift to center today)
- [ ] LOS decision: wire _is_blocked_by_* helpers or delete + document no-LOS
- [ ] Flow fields: consult in movement or delete rebuild machinery; unstick give-up → re-path
- [ ] Offline AI uses Castle Wrath; army tab unit portraits (needs A6-style sprite work)

## Phase 4: Growth Content (Planning — spec via `tasks/design-phase-4.md` once T-093 lands)
- [ ] Second real Horde faction with distinct sprites (A6 biggest project — currently Horde mirrors Kingdom data)
- [ ] Ranked mode with MMR + matchmaking tiers
- [ ] New maps with terrain obstacles (reactivates T-074 + T-078 test-first suite)
- [ ] Spectator mode + replay system
- [ ] Battle pass / cosmetic shop / daily quests (retention hooks)
- [ ] Submit to CrazyGames and Poki
- [ ] 2v2 and 3v3 team modes

## Phase 5: Mobile (post-Phase-4)
- [ ] Export to Android + iOS
- [ ] Integrate mobile ads + IAP
- [ ] Cross-play (web + mobile same backend)
- [ ] App Store Optimization

## Phase 6: Growth (long-term)
- [ ] Paid user acquisition
- [ ] New seasons with content
- [ ] Tournaments + esports support
