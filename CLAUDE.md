# Trade Project

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Only touch what's necessary. No side effects with new bugs.

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness
- **Game mechanics changes**: Run the relevant video test scenario, read the captured screenshots, verify the visual behavior matches expectations. Headless tests verify logic; video tests verify gameplay feel.
- **Architecture first**: Before patching parameters (ranges, thresholds, buffers), audit whether the underlying system is correct. A wrong architecture cannot be fixed with parameter tuning.

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes -- don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests -- then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Context Management
- After completing each major sub-task, save progress to `memory/active-session.md`
- When a conversation is getting long (many tool calls, large outputs), proactively checkpoint findings to memory
- Before reading large files or running expensive operations, save current state first

## Multi-Agent Team Protocol (7 Agents) — SUPERSEDED 2026-07-07

> **This 7-agent cron-polling model is RETIRED. See `tasks/PROCESS.md` for the
> current operating model: one orchestrator session + ephemeral scoped
> subagents.** Do NOT start a `/loop`, do NOT "onboard as an agent", do NOT read
> `tasks/dispatch.md` as a live task queue (it is archived under
> `tasks/archive/`). The live task list is `tasks/backlog.md`.
>
> The role/ownership tables below are RETAINED, but reinterpreted as **subagent
> scoping** — i.e. which domain owns which files when the orchestrator fans out
> parallel fix agents (A1=infra/net, A2=UI, A3=audio, A4=tests, A5=sim/data,
> A6=sprites). They are reference for the File Ownership Map, not a roster of
> separate Claude instances to spawn or a `/loop` to run.

### (Historical) New Agent Onboarding — DO NOT FOLLOW; see tasks/PROCESS.md

The steps below described the retired model and are kept only for context:

| Role | Command |
|------|---------|
| A0 | `/loop 60m Read tasks/dispatch.md. Check Coordination Log for messages to A0/ALL. Check QA_FAIL tasks needing design revision. Check tasks/qa-bug-tracker.md for bugs needing design decisions. Create design specs and file new tasks if needed. Update tasks/todo.md if roadmap changed. Report findings.` |
| A1 | `/loop 30m Read tasks/dispatch.md. Check for READY/QA_FAIL tasks where Owner-agent=A1. Claim and implement if found (domain: autoload/game_manager.gd, network_manager.gd, event_bus.gd, player_data.gd, project.godot). Run godot --headless -s tests/test_simulation.gd. Set QA_REVIEW. Check tasks/qa-bug-tracker.md for infra bugs. Report findings.` |
| A2 | `/loop 30m Read tasks/dispatch.md. Check for READY/QA_FAIL tasks where Owner-agent=A2. Check Coordination Log for A6 sprite wiring requests. Claim and implement if found (domain: scripts/ui/, scenes/, sprite_registry.gd). If A6 logged new sprites, add UNIT_MAP entries. Report findings.` |
| A3 | `/loop 30m Read tasks/dispatch.md. Check for READY/QA_FAIL tasks where Owner-agent=A3. Claim and implement if found (domain: autoload/sfx.gd, assets/audio/). SFX packs at ~/Downloads/Dowloaded_Game_Assets/. Convert WAV to OGG: ffmpeg -i in.wav -c:a libvorbis -q:a 4 out.ogg. Report findings.` |
| A4 | `/loop 15m Read tasks/dispatch.md. Process all QA_REVIEW tasks: read acceptance criteria, run tests (godot --headless -s tests/test_simulation.gd for sim, godot --path castle_clash -- --autotest for visual), verify criteria. Set DONE or QA_FAIL with notes. File new bugs in tasks/qa-bug-tracker.md. Report verdicts.` |
| A5 | `/loop 30m Read tasks/dispatch.md. Check for READY/QA_FAIL tasks where Owner-agent=A5. Claim and implement if found (domain: core/simulation.gd, data/). Run tests BEFORE and AFTER changes (test_simulation.gd + test_behavior_audit.gd). Set QA_REVIEW with before/after comparison. Check qa-bug-tracker.md for gameplay bugs. Report findings.` |
| A6 | `/loop 30m Read tasks/dispatch.md. Check for READY/QA_FAIL tasks where Owner-agent=A6. Create sprites using PIL/Pillow+NumPy (reference tools/generate_knight.py). Output to assets/sprites/units/blue_{name}/ and red_{name}/. Open PNG to verify. Set QA_REVIEW. Log message asking A2 to wire UNIT_MAP. Source assets at ~/Downloads/Dowloaded_Game_Assets/. Report findings.` |

This makes you fully autonomous — you'll poll for new work every cycle without the user needing to prompt you.

Then find your role below for full context:

---

#### A0 — Lead Game Designer (Onboarding)

**The game**: Castle Fight — a WC3 Castle Fight-inspired auto-battler built in Godot 4.6.2 (GDScript). Portrait mobile 720x1280. Two factions (Kingdom blue, Horde red) with 18 units, 28 buildings. Tiny Swords pixel art. Named after the WC3 custom map for nostalgia.

**Benchmarks**: Kingdom Rush (battle zone visuals), Clash Royale (menu UI/UX), Fort Guardian (animation smoothness), WC3 Castle Fight (strategic depth).

**What's been done**: 65+ tasks complete across Phase 2. Terrain overhaul, visual hierarchy, smooth animations, hit-stop, 10 second skills, upgrade buildings, special buildings with active abilities, compound income, perks, game modes, tutorial, all menu tabs populated, end screen polish, logo.

**Your files to read**: `tasks/todo.md` (master roadmap), `tasks/design-*.md` (your design specs: gap-analysis, tutorial, second-skills, animation-smoothness, tree-lanes), `tasks/competitive-research.md`, `tasks/asset-research.md`.

**How you work**: Create design specs → file tasks in dispatch.md → agents claim and implement → QA verifies. You don't assign tasks directly — you make them READY and provide priority guidance in the Coordination Log.

**Test**: You don't test code. You review QA reports and playtest via web export: `cd castle_clash && godot --headless --export-release "Web" export/web/index.html && cd export/web && python3 -m http.server 8080`

---

#### A1 — Lead Programmer (Onboarding)

**Tech stack**: Godot 4.6.2, GDScript, HTML5 web export (38MB WASM), Nakama server (Docker Compose, ready but untested for multiplayer).

**Architecture**:
- **Deterministic simulation** (`core/simulation.gd`, 2346 lines) — fixed-point math (Q16.16), seeded RNG, 10 ticks/sec. NO Godot nodes in sim. Visual layer reads sim state.
- **Autoloads** (7): EventBus (signal bus), GameManager (match lifecycle, tick scheduling, tick_interpolation), NetworkManager (Nakama relay, lockstep), PlayerData (trophies/ranks/settings, saves to `user://player_data.cfg`), SFX (audio), SpriteRegistry (sprite loading), AutoScreenshot (test automation).
- **Event-driven**: Simulation emits events → EventBus signals → visual/audio layers subscribe.
- **Networking**: Nakama addon in `addons/`. Lockstep tick model with checksum desync detection. `GameManager.offline_mode` flag routes commands locally or via relay.
- **Web export**: `export_presets.cfg` has "Web" preset with custom HTML shell. Export to `export/web/`.
- **Display**: 720x1280 viewport, canvas_items stretch, 504x896 desktop window override.

**Your files**: `autoload/game_manager.gd` (256 lines — tick scheduling, match states, tutorial mode), `autoload/network_manager.gd` (Nakama), `autoload/event_bus.gd` (signals), `autoload/player_data.gd` (148 lines — persistence), `project.godot`, `export_presets.cfg`.

**You do NOT touch**: `core/simulation.gd` (that's A5), `scripts/ui/` (that's A2), `assets/audio/` (that's A3).

**Test**: `cd castle_clash && godot --headless -s tests/test_simulation.gd` (239+ tests). For networking: spin up Nakama via `docker-compose up` then test with 2 browser tabs.

---

#### A2 — UI/UX Designer (Onboarding)

**Current UI screens** (all implemented, files in `scripts/ui/`):
- `loading_screen.gd` — Scenic background, logo, progress bar, transitions to main menu
- `main_menu.gd` — 5-tab bottom bar (Battle/Shop/Army/Social/Settings), scenic background, faction selection, perk selection, game mode selector, progression display (arena banner, trophy bar), avatar header
- `card_hand.gd` — Auto-sizing building cards (handles 10+ buildings), cost badge, lock overlay, tier stars, type indicator, radial menu on tap
- `hud.gd` — Gold label, wave timer, castle HP
- `end_screen.gd` — Victory/defeat with confetti, stat cards, MVP unit, trophy animation, styled buttons
- `tutorial.gd` — Dark overlay with spotlight cutouts, bobbing arrows, text bubbles, 3-step state machine
- `building_menu.gd` — Building info panels

**Visual systems** (in `scripts/game/`):
- `sprite_unit_visual.gd` — AnimatedSprite2D wrapper with hit-stop, attack timing phases, squash-turn, auto-scaling
- `unit_visual.gd` — Procedural chibi fallback with walk cycle, attack anims per role
- `effects.gd` — 12+ skill VFX, damage numbers, death poofs, projectiles, heal sparkles, spawn bursts
- `building_grid.gd` — Grid overlay, ghost preview, Kingdom Rush-style radial menu (sell/info/cancel)
- `castle_visual.gd` — Castle sprite with damage tint + fire at low HP
- `game_arena.gd` (SHARED) — terrain builder, decorations, unit/building visual creation, gold bar, ability HUD buttons

**UI art assets** in `~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/UI Elements/` — buttons, bars, ribbons, papers, icons, avatars. Pre-assembled 9-patch textures in `assets/sprites/ui/assembled/`. Note: Tiny Swords button PNGs are 3x3 atlas grids — use assembled versions or StyleBoxFlat.

**Sprite wiring**: When A6 creates new unit sprites, YOU add the UNIT_MAP entry in `autoload/sprite_registry.gd`. The format: `&"unit_name": {"folder": "blue_unitname", ...}` with animation file mappings.

**Test**: Run game in Godot editor (`godot --path castle_clash`), visually verify. For screenshots: `godot --path castle_clash -- --autotest` captures 30 frames.

---

#### A3 — Sound Designer (Onboarding)

**Audio architecture** (`autoload/sfx.gd`, 803 lines):
- **3-bus system**: Master → Music (-6dB) / SFX / UI — independent volume control via PlayerData
- **Hybrid**: File-based .ogg primary, procedural synthesis fallback (sine/square/saw/triangle/noise oscillators with ADSR envelopes)
- **16-slot combat audio pool** with round-robin, per-type cooldown throttling (hit: 150ms, castle_hit: 300ms, place: 0ms)
- **4-slot UI audio pool** (no throttle)
- **Music crossfade**: 1.5s fade between tracks
- **Auto-scan**: Loads `assets/audio/sfx/{category}/{name}_{01-09}.ogg` variants automatically. No-repeat random selection.

**Current audio inventory** (87 files):
- Combat: hit (5), shoot (4), death (3), heal (2), castle_hit (5) — castle hits recently replaced with Kenney Impact plate sounds
- Building: place (3, recently replaced with hammer sounds), gold (3), sell (1), destroy (3, NEW)
- Announce: wave (1), skill (3)
- UI: button_click, tab_switch, card_select, card_hover, card_denied
- Music: menu_theme, battle_theme, victory_fanfare, defeat_fanfare, loading_ambient + 4 extras (bards_tale, kings_feast, market_day, rejoicing)

**Downloaded SFX packs** in `~/Downloads/Dowloaded_Game_Assets/`:
- `kenney_impact-sounds/` — 130 OGG: stone, metal, wood, glass impacts (CC0)
- `Hammer_Free/` — 20 WAV hammer sounds (CC-BY, need WAV→OGG conversion: `ffmpeg -i input.wav -c:a libvorbis -q:a 4 output.ogg`)
- `kenney_rpg-audio/` — 50 OGG: RPG sounds, coins, doors, cloth (CC0)
- `kenney_ui-audio/` — 17 OGG: clicks, rollovers (CC0)
- `80-CC0-RPG-SFX/` — 80 OGG: blades, spells, creatures, fire (CC0)
- `kenney_music-jingles/` — music jingles (CC0)

**Known issues** (from T-063): ability activation calls `play_ui("card_select")` instead of `play_skill()`, gold popup calls `play_ui("card_hover")` instead of `play_gold()`, need `play_destroy()` function for enemy building destruction.

**Test**: Run game, play a full match, listen. Check Godot console for audio errors. Verify volume sliders work (Settings tab).

---

#### A4 — QA Lead (Onboarding)

**Test suites** (in `tests/`):

**The gate**: `bash tests/run_all.sh` (see `tasks/PROCESS.md`). `SKIP_VISUAL=1` = L0 headless only (<1 min); no env = L0 + L1 visual; `RUN_NIGHTLY=1` adds L3. Facts corrected 2026-07-07 (the table below had drifted):

| Test | Command | What It Does | Runtime |
|------|---------|-------------|---------|
| **Headless simulation** | `godot --headless -s tests/test_simulation.gd` | 395 deterministic asserts: FP math, sprites, combat, income, targeting, buildings | ~2 s |
| **Determinism lint** | `godot --headless -s tests/test_banned_api.gd` | Hard-fails on RNG/clock/node/transcendental leaks in the sim core; float ratchet | ~1 s |
| **Replay determinism** | `godot --headless -s tests/test_replay_determinism.gd` | Re-run identity + golden trace over a fixed-seed match (`-- --rebless` to re-pin) | ~10 s |
| **Behavior audit** | `godot --headless -s tests/test_behavior_audit.gd` | Unit movement: zigzags, stuck units, targeting consistency (24 asserts) | ~2 s |
| **Multiplayer** | `godot --headless -s tests/test_multiplayer.gd` | Checksum divergence/identity + MATCH_CONFIG wire round-trip (123 asserts) | ~2 s |
| **Balance test** | `godot --headless -s tests/test_balance.gd` | 100 AI-vs-AI matches, faction win rates | **~176 s** (was mislabeled ~30 s) |
| **Screen layout (L1)** | `godot --headless -s tests/test_screen_layout.gd` | Pixel detectors — needs a fresh capture (`tests/capture.sh`) or it FAILS, not passes | ~1 s |
| **Capture pipeline** | `bash tests/capture.sh` | Windowed --autotest → 20 PNGs + manifest in `test_output/autotest/`, retries once | ~60–90 s |

Note: `test_audio_visual.gd` / `test_tutorial_visual.gd` are windowed autoload flag tests (`godot --path castle_clash -- --audiotest` / `--tutorialtest`), NOT `--headless -s` scripts. Captures live in `test_output/` (gitignored), not `/tmp`.

**QA workflow**: pick from `tasks/backlog.md` → write the failing test/detector first → fix → run the gate → one evidence-citing commit → update backlog. Bugs in `tasks/qa-bug-tracker.md`.

**Key rule** (from lessons): Don't flag test-scenario artifacts as bugs. Verify in actual game context first. Always run test BEFORE a change for baseline, then after to confirm improvement.

**HARD QA GATE — Visual bugs require pixel-level detectors (added 2026-04-18 after 4-iteration regression on main menu bugs)**:

1. **Detector-first bug filing**. When user reports a visual bug, write a pixel detector in `tests/test_screen_layout.gd` BEFORE filing the bug. Run the detector — it must FAIL on the current build. The bug entry's `**Detector**:` field cites the detector function name.

2. **No DONE without detector PASS**. Cannot transition a visual bug from QA_REVIEW → DONE unless `godot --headless -s tests/test_screen_layout.gd` reports PASS for the named detector. Cite the test output line in the dispatch coordination log entry.

3. **Loop fire smoke test**. Every /loop fire runs the full screen-layout suite. Any newly-failing detector means a previously-DONE bug regressed → re-open immediately, do not wait for user to re-flag.

4. **Static analyzers ≠ visual verification**. Heuristics (font size ≥ 12, child count ≤ 6) catch construction patterns; pixel scans catch rendering outcomes. When the heuristic passes but the bug is visible, the pixel scan wins.

5. **Detector calibration is mandatory**. Before adding a detector, programmatically scan the capture to find the bug's actual coordinates (do not guess from memory). Document calibration date and image resolution in the detector docstring.

**Test results**: `tests/test_results.json`, `tests/balance_results.json`

---

#### A5 — Gameplay Programmer (Onboarding)

**Your domain**: `core/simulation.gd` (2346 lines) — the entire deterministic game simulation. Plus all data files.

**Architecture you built/own**:
1. **Unit Occupancy Grid** — 11×34 cell grid, capacity 2 units/cell, register/unregister on spawn/death/move
2. **Explicit State Machine** — MARCH/CHASE/ATTACK states (SIEGE removed; castle is a normal nearest-target obstacle)
3. **Committed Targeting** — Sticky lock-on (keep target until death), enemy-half castle fallback
4. **Castle Wall** — Castle rows blocked full-width in occupancy grid (3 rows)
5. **Preventive Collision** — Pre-move occupancy check with Y-only/X-only fallbacks, wall-safe unstick
6. **Movement is straight-line-to-nearest-enemy** — the old "weighted flow field" was never wired into movement decisions and its dead code was removed 2026-07-07 (1C-5). A vestigial build-zone `flow_fields` BFS remains only because a terrain test tool reads it.
7. **Combat zone trees** — Horizontal tree wall at rows 6-7 with 3 gaps (lane system)
8. **WC3 armor formula** — `damage / (1 + armor * 0.06)`, 4×4 damage type matrix

**Current units** (18): footman, archer, priest, knight, catapult, royal_knight, gryphon_rider, ballista_unit, champion + grunt, axe_thrower, wardrummer, berserker, demolisher, war_rider, wyvern_rider, scorpion, warlord

**Current buildings** (28): 14 per faction including walls, towers, income, special (War Horn/Blood Totem), T1/T2/T3 tiers

**Data model**: `data_scripts/unit_data.gd` (25 fields: HP, DMG, speed, armor, skills x2, role, types), `data_scripts/building_data.gd` (16 fields: cost, spawn, tower, grid_size)

**Key constants**: TICKS_PER_SECOND=10, CELL_SIZE_PX=28, GRID_COLS=11, GRID_ROWS=10 (per build zone), 13 combat rows

**Test**: `godot --headless -s tests/test_simulation.gd` (headless), `godot --headless -s tests/test_behavior_audit.gd` (movement quality), video test for visual verification. **Always test BEFORE and AFTER changes.**

**Memory to read**: `memory/a5_session_progress.md`, `memory/feedback_test_first.md`

---

#### A6 — Technical Artist (Onboarding)

**(Full details in the A6 role definition section further below in this file)**

**Quick start**: Read `tools/generate_knight.py` as your reference pattern. Source art in `~/Downloads/Dowloaded_Game_Assets/`. Output to `assets/sprites/units/blue_{name}/` and `red_{name}/`. Test by opening the output PNG.

**Current units with sprites** (21 folders in `assets/sprites/units/`): blue/red variants of warrior, archer, lancer, monk, pawn, knight (mounted), gryphon (flying), ballista (siege), catapult + rpg_soldier (Champion), rpg_orc (Warlord)

**Source packs**: Tiny Swords (5 base unit types × 4 colors), Tiny RPG (20 characters at 100×100), Knight_and_Horse (mounted anims), Pixel Crawler (5 types), Birds.png, Catapulta sprites

**Memory to read**: `memory/feedback_sprite_compositing.md` (layer order, sizing, positioning rules)

### Session Boot Sequence — SUPERSEDED, see `tasks/PROCESS.md`
The dispatch.md/QA_REVIEW/Agent-Registry workflow below is retired. Current boot:
1. Read `tasks/PROCESS.md` (operating model + gate) and `tasks/lessons.md`.
2. Live task list is `tasks/backlog.md`; open bugs in `tasks/qa-bug-tracker.md`.
3. Use the File Ownership Map below as **subagent scoping** (which domain owns which files).
4. Per-task: write the failing test/detector first → fix → `bash tests/run_all.sh` → one evidence-citing commit → update `tasks/backlog.md`.
5. `tasks/dispatch.md` is archived under `tasks/archive/` — historical reference only.

### Agent Roles (Industry-Standard Game Dev Team)

| ID | Role | Responsibility | Key Files |
|----|------|---------------|-----------|
| **A0** | Lead Game Designer | Creative direction, feature design, balance design, competitive analysis, task orchestration, roadmap. The "product owner" — decides WHAT to build and WHY. | `tasks/dispatch.md`, `tasks/design-*.md`, `tasks/todo.md` |
| **A1** | Lead Programmer | Core engine infrastructure, networking (Nakama), build pipeline, export, performance, project configuration. The scaffolding everything else runs on. Does NOT do gameplay logic (that's A5). | `autoload/game_manager.gd`, `autoload/network_manager.gd`, `autoload/event_bus.gd`, `autoload/player_data.gd`, `project.godot`, `export_presets.cfg` |
| **A2** | UI/UX Designer | Menus, HUD, card hand, end screen, settings, tutorial overlays, tab navigation, gold bar, progression displays, building grid/radial menu. Pure UI — does NOT create unit sprites or animations (that's A6). | `scripts/ui/`, `scripts/game/building_grid.gd`, `scenes/ui/`, `scenes/game/game_arena.tscn` (UI nodes) |
| **A3** | Sound Designer | Music composition/integration, SFX design, ambient soundscapes, audio bus architecture, sound triggering code. | `autoload/sfx.gd`, `assets/audio/`, `default_bus_layout.tres` |
| **A4** | QA Lead | Test automation (headless + video), bug tracking, regression testing, balance testing (AI-vs-AI), acceptance verification, visual audits. | `tests/`, `tasks/qa-*.md` |
| **A5** | Gameplay Programmer | ALL gameplay logic in simulation: combat math, skills, economy, movement, targeting, pathfinding, AI, unit state machine, occupancy grid, flow fields, building placement, damage table, perks, game modes. The "game feel" engineer. Verifies with video test screenshots, not just headless tests. | `core/simulation.gd`, `core/*.gd`, `data/`, `data_scripts/`, `scripts/game/game_arena.gd` (AI logic) |
| **A6** | Technical Artist | Sprite compositing via PIL/Pillow + NumPy. Creates unit sprites, animations, projectiles, mounts, VFX sprite sheets. Does NOT use Godot or AI generators — builds art programmatically from source packs. | `tools/generate_*.py`, `assets/sprites/units/`, `assets/sprites/effects/` |

### Responsibility Boundaries (Who Does What)

**"Where does this go?"** quick reference:

| Task | Agent |
|------|-------|
| New game feature design / balance numbers | A0 |
| Nakama multiplayer, web export, project settings | A1 |
| Menu screen, HUD element, card layout, tutorial UI | A2 |
| New sound effect, music track, audio routing | A3 |
| Bug report, test creation, balance test | A4 |
| Unit behavior, combat, AI, pathfinding, skills, economy | A5 |
| New unit sprite, animation strip, projectile art, mount | A6 |
| Sprite registry mapping (UNIT_MAP, BUILDING_MAP) | A2 (owns file), coordinates with A6 |
| game_arena.gd terrain/decorations/effects | A2 (visual), A5 (AI/gameplay), coordinate via dispatch |

### A6 (Technical Artist) — Full Role Definition

**You are the Technical Artist (A6).** You create unit sprites, animations, and projectiles for Castle Fight using **PIL/Pillow + NumPy** compositing scripts. You do NOT use Godot, drawing tools, or AI image generators. You build sprites programmatically by compositing existing pixel art assets.

#### Your Core Skill
You are an expert at creating 2D pixel art sprite strips using Python PIL/Pillow and NumPy by:
1. Loading multiple source PNG sprite sheets (different resolutions, scales, frame counts)
2. Normalizing them to a common frame size (typically 192x192 or 320x320)
3. Extracting individual frames from horizontal sprite strips
4. Compositing characters with mounts, weapons, or accessories (correct layer order, positioning, scaling)
5. Outputting horizontal sprite strips compatible with Godot's AnimatedSprite2D (all frames same height, laid out left-to-right)

#### Source Assets (READ-ONLY — never modify originals)
All source art is in `/Users/paulinecolobong/Downloads/Dowloaded_Game_Assets/`:

| Pack | Path | What's Inside | Resolution |
|------|------|---------------|-----------|
| **Tiny Swords (primary)** | `Tiny Swords (Free Pack)/Units/Blue Units/` | Warrior, Archer, Lancer, Monk, Pawn — each has Idle, Walk, Attack, Death strips | 192×192 per frame |
| **Tiny Swords (red)** | `Tiny Swords (Free Pack)/Units/Red Units/` | Same 5 types in red palette | 192×192 |
| **Tiny Swords (purple/yellow)** | `Tiny Swords (Free Pack)/Units/Purple Units/`, `Yellow Units/` | Palette swaps for future factions | 192×192 |
| **Tiny RPG Full (20 chars)** | `Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/Characters(100x100)/` | Archer, Knight, Wizard, Priest, Skeleton, Werewolf, Orc, Slime, + 12 more | 100×100 per frame |
| **Tiny RPG Projectiles** | `Tiny RPG Character Asset Pack v1.03 -Full 20 Characters/Arrow(Projectile)/`, `Magic(Projectile)/` | Arrow and magic projectile sprites | Various |
| **Knight_and_Horse** | `Knight_and_Horse/` | Horse with rider — Idle, Walk, Gallop, Attack, Death animations | Various |
| **Pixel Crawler** | `Pixel Crawler/` | Knight, Wizard, Rogue, Orc Crew, Skeleton Crew | Various |
| **Birds.png** | `Birds.png` | Small bird sprite (used for gryphon mount base) | ~27×27 |
| **Catapulta** | `Catapulta_basico.png`, `Catapulta_piedra.png`, `Catapulta_animacion.gif` | Catapult base + stone projectile + animation reference | Various |

#### Output Directory
All generated sprites go to: `/Users/paulinecolobong/game/castle_clash/assets/sprites/units/`

Each unit gets a folder: `blue_{unit_name}/` and `red_{unit_name}/`
Inside: `{UnitName}_{Animation}.png` sprite strips (e.g., `Knight_Idle.png`, `Knight_Walk.png`, `Knight_Attack.png`)

#### Existing Scripts (reference these patterns)
- `tools/generate_knight.py` — Composites Tiny Swords lancer frames + procedural armored horse → mounted knight
- `tools/generate_gryphon.py` — Composites archer frames + procedural gryphon (bird body + wings) → flying archer
- `tools/generate_ballista.py` — Composites pawn frames + procedural ballista weapon → siege unit

**Key patterns from existing scripts:**
- Use team-color palettes (BLUE dict, RED dict) with outline, armor, accent, metal colors
- Frame size: 192×192 for Tiny Swords-based, 320×320 for composite mounts
- Sprite strips: horizontal layout, all frames same height, transparent background
- Compositing order: mount/vehicle BACK → character MIDDLE → accessories FRONT
- Character scaling: ~0.72× of frame height for rider on mount
- Mount scaling: 3× from small sprites, centered in lower frame portion
- Always generate both blue and red team variants

#### Sprite Integration Pipeline
After generating sprites, ALWAYS run these steps in order:
1. Place in `assets/sprites/units/blue_{name}/` and `red_{name}/`
2. **FORCE REIMPORT** — run `godot --path /Users/paulinecolobong/game/castle_clash --headless --import` **every time** you regenerate a sprite strip. Godot caches `.ctex` files in `.godot/imported/` and silently serves the stale version when you change PNG dimensions or frame counts. Skipping this step has burned us: a regenerated catapult attack strip with 11 frames kept loading as 6 frames in-game, and the showcase report PASSED against the stale cache. The user cannot see your new animation until you reimport.
3. Notify A2 to add UNIT_MAP entry in `autoload/sprite_registry.gd` via dispatch coordination log (only needed for NEW units, not regenerations)
4. `sprite_unit_visual.gd` auto-scales sprites to ~58px game size regardless of source frame size
5. Run `godot --headless -- --showcase --unit <name>` to verify — check `frame_counts` in `/tmp/castle_clash_showcase/showcase_report.json` matches what your generator printed. A PASS verdict alone is not enough; the frame counts prove the reimport worked.
4. Test: just open the output PNG to verify — no need to run full game for sprite checking

#### Compositing Rules (from team feedback)
- **Layer order**: Character (rider) BEHIND mount → Mount MIDDLE → Wings/accessories FRONT
- **Sizing**: Mount at 3× from small pixel art, character at ~0.72× frame height
- **Positioning**: Mount centered low, character shifted LEFT+UP to sit on mount's back
- **Wings**: Shifted LEFT+DOWN to attach at mount's chest level (~65% down)
- **Always preview** at 4× zoom on a single frame before building full strips
- **Test by opening the PNG directly** — no need for video tests for sprite work

#### What You Create (typical tasks)
- New unit sprite strips (idle, walk, attack, death) by compositing existing characters with mounts/weapons
- Team color variants (blue + red, potentially purple + yellow for future factions)
- Projectile sprites (arrows, magic bolts, siege stones)
- Animation frame adjustments (timing, positioning, scaling)
- Mount/vehicle procedural art (horses, gryphons, ballistas, war machines)

### QA Sign-Off Required
No feature is "done" until A4 sets QA-verdict = PASS in dispatch.md. See `tasks/team-protocol.md` for QA testing capabilities.

### File Ownership Map

| Owner | Files |
|-------|-------|
| **A0** | `tasks/dispatch.md` (task creation), `tasks/design-*.md`, `tasks/todo.md` |
| **A1** | `autoload/game_manager.gd`, `autoload/network_manager.gd`, `autoload/event_bus.gd`, `autoload/player_data.gd`, `project.godot`, `export_presets.cfg` |
| **A2** | `scripts/ui/*.gd`, `scripts/game/sprite_*.gd`, `scripts/game/building_visual.gd`, `scripts/game/unit_visual.gd`, `scripts/game/castle_visual.gd`, `scripts/game/building_grid.gd`, `scenes/**/*.tscn`, `autoload/sprite_registry.gd` |
| **A3** | `autoload/sfx.gd`, `assets/audio/**`, `default_bus_layout.tres` |
| **A4** | `tests/**`, `tasks/qa-*.md` |
| **A5** | `core/simulation.gd`, `core/*.gd`, `data/units/*.tres`, `data/buildings/*.tres`, `data/factions/*.tres`, `data_scripts/*.gd` |
| **A6** | `tools/generate_*.py`, `assets/sprites/units/` (generated output), `assets/sprites/effects/` (generated output) |
| **SHARED** | `scripts/game/game_arena.gd` — A2 owns visual/terrain, A5 owns AI logic. Coordinate via dispatch. |
| **NOBODY** | `addons/**` — third-party, do not modify |

### File Conflict Prevention
- Check File Ownership Map before editing any file
- SHARED files require coordination via dispatch.md Coordination Log
- Never edit a SHARED file if another agent's IN_PROGRESS task touches it
- When A6 creates new sprites, A2 adds the UNIT_MAP/BUILDING_MAP entries in sprite_registry.gd
