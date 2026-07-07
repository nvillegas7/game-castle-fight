# Plan: Polish-to-Parity Campaign (2026-07-07)

**Goal**: Bring every screen and every shipped gameplay mechanic to Kingdom Rush / Clash Royale parity, fix the six user-reported areas (blast skill, unit placement, unit fighting, camera zoom/scroll, tile placement under zoom, multiplayer sync), and replace the 7-agent markdown-polling process with orchestrator-driven execution.

**Evidence base**: 7 parallel read-only audits (input/camera, abilities, multiplayer, combat, visual architecture, UI parity, process) + fresh autotest captures + baseline test runs (sim 373/373 PASS, behavior audit 24/24 PASS, balance 48/52 PASS).

---

## Part 1 — Verdict: what is wrong with our architecture and process

### Architecture: the core is sound; the shell is not
- **Simulation core is healthy.** `core/simulation.gd` has zero node/EventBus references, events flow one-way, fixed-point math is clean, 373 tests pass, behavior audit is clean. It can support KR/CR-level polish as-is.
- **The visual layer is the problem.** `game_arena.gd` is a 13-concern god file (2,316 lines) that mixes opponent AI (A5 logic) with terrain painting and HUD (A2) — which is exactly why it was the contended SHARED file. `main_menu.gd` (2,197 lines) fights its own scene with ~98 hardcoded coordinates. No theme system exists (27 ad-hoc StyleBoxFlat sites, 62 font-size overrides); the themed font (MorkDungeon.ttf) ships but is used nowhere.
- **Dead architecture is lying to us.** The documented flow-field pathfinding, aggro-range, and LOS systems are dead code — movement is straight-line-to-nearest-enemy. It works (audits pass) but docs and code disagree, and the dead code burns CPU.
- **Input layer has systemic coordinate-space bugs.** Every screen→grid conversion in `building_grid.gd` ignores the camera transform (`event.position - global_position`). Placement/sell/radial are wrong under any zoom≠1 or pan, and single-finger tap-to-place NEVER commits on touchscreens (emulated-mouse event trips the multi-touch cancel guard). The camera feature itself is desktop-only: pinch/pan gestures used don't exist on mobile web.
- **The multiplayer "sync error" is a deployment problem, not (only) a code problem.** The uncommitted lockstep rework (+2 tick staging, committed-tick guard, definitive re-flush, config ACK) survived adversarial audit — no divergence constructible. But the LIVE web build is from Apr 19 and still runs the pre-fix `current_tick+1` race. The fix has never been committed, built, or deployed.

### Process: the QA backbone was a rubber stamp
1. **P0 — Vacuous QA gate.** Every pixel detector in `test_screen_layout.gd` silently PASSES when its capture is missing. Captures live in `/tmp` (macOS purges every ~3 days). The "hard QA gate" has been green-with-zero-pixels-examined for ~10 weeks.
2. **P1 — Capture pipeline has no integrity.** `save_png()` errors ignored, always exits 0, output dir never cleaned (stale-build verdicts), zero-capture run indistinguishable from a passing run (reproduced today).
3. **P1 — Git hygiene.** ~10,400 inserted lines across 56 files uncommitted on main since Apr 14. Zero bisectability; one `git reset --hard` from losing months of work.
4. **P1 — Cron-polling waste.** 68% of the coordination log is no-op ticks (~505 A4 ticks at ~13-min intervals, each a full session re-reading a 3,775-line file). Order of 30M+ tokens spent producing zero caught regressions.
5. **P2 — Recurring failure class is process, not model.** lessons.md documents "declared fixed without verification artifact" four times in 14 days. The fixes were prose rules, not mechanical gates.
6. **P2 — Protocol docs triplicated and contradictory** (CLAUDE.md vs team-protocol.md vs agent-loop-prompts.md; drifted facts throughout).

### New operating model (replaces the 7-agent protocol)
- **One orchestrator (this session) + ephemeral scoped subagents.** Retire: /loop cron polling, Agent Registry, Coordination Log, per-agent onboarding, agent-loop-prompts.md, team-protocol.md.
- **Keep, repurposed**: File Ownership Map → subagent *scoping* (one domain per fix agent, parallel via worktrees); detector-first QA; test-before/after discipline; lessons.md.
- **Per-task pipeline**: TRIAGE → RED (failing test/detector committed first) → FIX (scoped subagent, worktree if parallel) → VERIFY (full gate suite + pixel evidence; adversarial review for risky diffs) → INTEGRATE (one commit per task citing evidence) → post-merge smoke.
- **Task tracking**: `tasks/backlog.md` (compact OPEN/IN_PROGRESS table only) + git history as the permanent log. dispatch.md archived read-only.
- **QA is event-driven**: full suite as merge gate per task + post-merge smoke. Never on a timer.

---

## Part 2 — Execution phases

Ordering rationale: you cannot trust any fix until verification is trustworthy (Phase 0); you cannot polish UI efficiently until the style system and god-file extractions exist (Phase 2 before 3); correctness fixes (Phase 1) are user-facing P0s and only need Phase 0.

### Phase 0 — Stabilize the foundation (sequential, ~1 day) — GATES EVERYTHING
Verification redesign is specified in `tasks/design-verification-workflow.md` (researched 2026-07-07: Riot/Factorio/Rare practices + Godot tooling truth + measured suite costs). Phase 0 executes its Build Order:
- [ ] **0.1 Git checkpoint**: commit the current working tree as a reviewed checkpoint series (sim / net / UI / assets slices). Then: task-branch discipline — main advances only via verified merges, every commit cites its evidence.
- [ ] **0.2 Verification pyramid, build order 1-8** (from design doc): checksum fix + subchecksums + state dump → capture integrity (manifest, hard-fail, retry-once, out of /tmp, per-screen `--capture` flags) → determinism goldens + banned-API lint + replay-pack recorder → LockstepPeer extraction + `test_lockstep_determinism.gd` (BUG-DESYNC1 scenario) + soak → layout-assertion layer + two-phase detectors + first golden set → touch input primitives + 4 zoom/touch scenarios → triage the 2 currently-failing suites (`test_targeting_diag.gd`, `test_unit_behavior.gd`) → fix CLAUDE.md test table (balance is 176s measured, not 30s).
- [ ] **0.3 Process docs**: write `tasks/PROCESS.md` (pipeline, domain map, gate definition, evidence rules); update CLAUDE.md (remove 7-agent protocol, fix drifted facts); archive dispatch.md/team-protocol.md/agent-loop-prompts.md; create `tasks/backlog.md` seeded from the audit findings.
- [ ] **0.4 Nightly tier** (during Phase 1B, non-blocking): 2-client Nakama match test, Playwright web-export smoke, Docker/Xvfb deterministic goldens.
- **Gate**: deliberately delete one capture → suite must FAIL. Kill a capture run mid-flight → non-zero exit. Fresh clone + checkout reproduces the build. BUG-DESYNC1 scenario red on pre-fix code, green on fixed code.

### Phase 1 — Correctness: the six reported areas (parallel worktree subagents, detector-first)
Each item: RED failing test first → fix → GREEN + evidence.

**1A. Input & camera (P0 — placement broken under zoom, broken on touch)**
- [ ] Canvas-transform-inverse conversion in `building_grid.gd` (placement :272, sell :352, radial :374) — the correct pattern already exists at :173.
- [ ] Dedup emulated-mouse vs touch (ignore `DEVICE_ID_EMULATION` mouse events) — fixes tap-to-place on mobile.
- [ ] Hand-rolled two-finger pinch-zoom + pan from ScreenTouch/ScreenDrag (mobile web has no Magnify/PanGesture); enable Android pan-and-scale setting.
- [ ] Radial menu spawns at the building's true cell center; scale hit radius by canvas zoom; kill the double-fire path.
- [ ] Reparent Blocked!/No-gold popup + info panel to UILayer; wheel-zoom `event.pressed` guard; zoom-to-cursor; ZOOM_MIN 1.0.
- [ ] **RED test**: synthetic-input zoom test — set camera zoom/pan, inject touch at computed screen pos of a known cell, assert ghost + placement land on that cell. (No test today references camera or zoom at all.)

**1B. Multiplayer sync (P0 — live build predates the fix)**
- [ ] Commit lockstep rework (part of 0.1), run `build.sh` to a hashed deploy, verify served artifacts.
- [ ] Surface lobby aborts (version_mismatch/config_timeout) in main_menu instead of hanging on "Starting…".
- [ ] Total command ordering: per-player seq number; sort `(player_id, seq)`.
- [ ] Freeze match on desync (stop simulating divergent games behind the overlay).
- [ ] Stronger checksum (gold + next_entity_id, order-sensitive rolling hash; dense checksums for first 200 ticks).
- [ ] Add `test_multiplayer.gd` to the gate; integration test driving send→flush→stall→commit across frame boundaries. Final: scripted two-client match vs docker Nakama + manual 2-tab validation.

**1C. Combat feel (unit fighting)**
- [ ] Walk-cadence divisor bug (`game_arena.gd:729` px/sec vs px/tick baseline) — every unit foot-skates at ~10% cadence.
- [ ] Make hit-stop real (pause sprite + skip position sync during stop) or delete the claim.
- [ ] Impact timing: delay damage number/flash to strike frame (melee) / projectile arrival (ranged); impact puff on arrows.
- [ ] Dedupe attacker swing VFX on AoE multi-victim events.
- [ ] **Decision applied**: delete dead flow-field/LOS/aggro code paths and fix docs (simplicity first), OR wire aggro_range if we want march-then-engage. Default: delete; revisit lanes in design.
- [ ] Guard/stub `set_walk_speed_ratio` on the procedural fallback (per-frame error spam).

**1D. Abilities ("blast skill" et al.)**
- [ ] Route `ability_activated` sim event → EventBus → VFX/SFX (enemy War Horn/Blood Totem activations are currently invisible+inaudible; local ring is press-time prediction).
- [ ] Fireball splash uses event payload coords (kills the live sim re-lookup anti-pattern).
- [ ] `castle_wrath_refused` → button shake/toast; ready-chime only for the LOCAL player's castle.
- [ ] Emit skill_proc for the six silent skills or delete their dead VFX/SFX branches.
- [ ] Offline AI uses Castle Wrath; fix `test_multiplayer.gd` to use a real ability id.
- [ ] Rally/Rage buff readability: brief tint or speed-lines on buffed units.

### Phase 2 — Architecture enablers (sequential, small, no rewrite; ~1 day)
- [ ] **2.1 Extract opponent AI** → `arena_ai.gd` (mechanical move; ends SHARED-file contention; balance suite then tests the REAL AI — today it tests a different, hand-rolled one).
- [ ] **2.2 Extract terrain/decoration builder** → `arena_terrain.gd` (~670 one-shot lines; verify pixel-identical autotest captures).
- [ ] **2.3 Shared style module** `ui_style.gd` + project Theme resource with MorkDungeon.ttf defaults (single highest-leverage visual change in the audit).
- [ ] **2.4 Shared `scenic_background.gd`** (delete the 250-line verbatim copy).
- [ ] **2.5 Sim read facade** (O(1) `get_entity`, castle_ratio, player_gold) — removes 80+ private reads and per-frame O(n²) scans; `z_layers.gd` constants.
- **Rule**: no big-bang scene rewrite; migrate per-screen as each is polished.

### Phase 3 — UI/UX parity polish (parallel per-screen subagents on the new theme)
- [ ] **3.1 Re-enable buried features** (finished code, currently unreachable): tutorial (gate on games_played==0), game-mode selector (sim already supports Blitz/Mirror), faction selection (or formally cut Horde — decision below).
- [ ] **3.2 Battle tab**: single CTA hierarchy (merge BATTLE ribbon + PLAY ONLINE), legible inactive tab labels, progression display restored.
- [ ] **3.3 Battle zone readability (KR benchmark)**: lane/path markings through the dead mid-band, restore gold elixir-bar fill + cheapest-card marker (code exists), locked cards → grayscale + padlock (kill permanent red noise), wave preview strip (icons + counts, 5s warning).
- [ ] **3.4 Mobile hardening**: ability/wrath buttons ≥88px, safe-area insets on header/tab bar, tap-and-hold replaces hover info.
- [ ] **3.5 End screen takeover**: hide HUD/gold bar/card hand behind results; restore on replay.
- [ ] **3.6 Army tab**: real unit sprites (not spawner buildings), tappable detail popup, de-spreadsheet the rows.
- [ ] **3.7 Shop/Social**: per decision below (rename Shop→Avatars + hide Social is the minimal honest ship).
- [ ] **3.8 Theme rollout**: migrate remaining screens to Theme/ui_style; delete per-label overrides opportunistically.
- **Gate per screen**: updated/new pixel detectors (relative coords, not absolute) + capture diff + reference-image side-by-side check.

### Phase 4 — Regression net & ship
- [ ] Merge-gate suite: sim (373) + behavior audit + screen-layout (hard-fail mode) + multiplayer + zoom-input + balance (real AI).
- [ ] Device pass: browser touch emulation + at least one real phone; full checklist of the six user-reported areas.
- [ ] Hashed web deploy; 2-browser online match; desync watch for a full match.
- [ ] Update lessons.md + memory with campaign outcomes.

---

## Part 3 — Decisions (resolved by Neil, 2026-07-07)
1. **Shop/Social tabs**: keep the tabs, show a polished "Coming Soon!" empty state. (Avatar picker currently squatting in Shop — relocate behind the header avatar tap or park under Settings; no new economy work this campaign.)
2. **Faction selection**: DEFERRED. Iron out current features and the core game first. (Remove from Phase 3.1 scope; tutorial + game-mode selector re-enable still in.)
3. **Dead pathfinding code**: CLEANUP — delete flow-field/LOS/aggro dead code, fix docs to match reality.
4. **Verification workflow**: redesign BEFORE implementation begins — see `tasks/design-verification-workflow.md`. Implementation starts only on Neil's go-ahead.

## Efficiency notes
- Phase 1's four tracks run as **parallel worktree-isolated subagents** (disjoint file domains via the ownership map). Phase 2 is sequential (shared files). Phase 3 fans out per-screen after 2.3.
- Every fix lands as one commit with test evidence in the message — bisectable, revertable, reviewable.
- Estimated wall-clock: Phase 0 ~half day; Phases 1+2 ~1-2 days orchestrated; Phase 3 ~1-2 days; Phase 4 ~half day.
