# Design: Verification Workflow v2 (2026-07-07)

**Question from Neil**: "Is what we're doing efficient in terms of running the game, taking screenshots to test changes? At one point we're running the game and recording just for you to test. How do established game companies do this testing?"

**Evidence base**: 5 research agents (Riot/Factorio/Rare/Ubisoft/EA/King practices with sources; Godot 4 tooling truth; lockstep-testing prior art; golden-image best practices; measured audit of our own suites on this machine, 2026-07-07).

---

## Part 1 — Direct answer: are we efficient?

**Half of our stack is already industry-grade. The other half is the most expensive possible way to do it.**

- **Efficient (keep)**: the headless deterministic layer. Sim suite (395 asserts, ~2s), behavior audit, in-process lockstep logic tests. The sim steps at ~1,300 ticks/sec headless — a full match replays in <2s. This is exactly the architecture Riot and Factorio built *on purpose* for testing; we got it for free from the lockstep design.
- **Inefficient (redesign)**: using the 60–90s windowed autotest as the *only* path to visual truth. Every UI check pays: real-time game boot + full menu walk + 60s of real-time gameplay + a window on the one dev machine — to produce 19 PNGs, which absolute-coordinate detectors then scan. Historical cost: a UI bug took 3–10 windowed reruns (the 10-round loading-screen saga). And the pipeline can produce **zero captures with exit code 0**, while missing captures make detectors **pass vacuously** — so all that cost bought a gate that could silently go blind.

**How established companies do it** (all citable, sources in research journal):

| Studio | Practice | Our analog |
|---|---|---|
| **Riot (LoL)** | Build Verification System: ~100k test cases/day drive the live game via RPC; **no bare sleeps — every wait is condition-polling**; replays 2–3k recorded real games/day against key-value state logs to catch determinism divergence | Replay pack + condition-polled captures + state-dump-on-divergence |
| **Factorio** (lockstep, like us) | **Every** scenario test ends with a CRC of full game state vs a pre-saved golden — determinism is a regression-tested property of the whole suite, not a separate audit; "heavy mode" save/loads every tick to localize desyncs; desync reports = state dumps from both peers | Checksum goldens per sim test; heavy mode; desync triage bundle |
| **Rare (Sea of Thieves)** | 23,212 tests: 70% fast "actor" tests, 5% integration maps (golden path only), 1.4% screenshot tests vs pinned goldens; networked tests = server + 2 clients **in one process**; auto-retry-once flake policy + quarantine suite; every change lands with its test | Our pyramid below is this, at solo scale |
| **King (Candy Crush)** | Bots play every level 1,000+ times in minutes to score solvability | Our 100-match balance bots, extended with personas + invariants |
| **Everyone** | Game **feel** is deliberately left to humans; automation owns regression, precision state checks, throughput | Neil playtests feel; agents never claim "feels right" from a screenshot |

**The key structural insight from the research**: we've been using one giant end-to-end run (boot → menus → 60s match → end screen) to answer *every* kind of question. Studios separate the questions: logic questions go to millisecond tests against the sim; layout questions go to scene-tree assertions (no rendering at all); appearance questions go to deterministic single-frame goldens; input questions go to synthesized-event scenarios; network questions go to two-peers-in-one-process harnesses. The full end-to-end run survives only as a **nightly smoke**, not an iteration loop.

**A discovery from our own repo audit**: a `tests/scenarios/` harness (July 2) already exists and covers camera zoom, placement-under-zoom (as an expected-fail repro), ability activation, and a menu tour with synthesized input at fixed seed — it's the right shape and becomes the official L2 layer below. Also: current baseline is NOT green — `test_targeting_diag.gd` and `test_unit_behavior.gd` are failing, and with real captures present the layout suite reports 2 live failures (BUG-47 tree band, BUG-49 ribbons). CLAUDE.md's test table has drifted (balance = **176s measured**, not ~30s; audio/tutorial tests are windowed flags, not headless scripts).

---

## Part 2 — The verification pyramid for Castle Fight

### L0 — Per-change, headless, <1 minute total. Runs on EVERY task branch.
1. **Sim suite** (395 asserts, ~2s) — as today.
2. **Determinism goldens** (Factorio pattern): every sim scenario ends by comparing the final checksum to a pre-saved golden value. Any commit that changes sim outcomes fails loudly; intentional changes re-pin the golden consciously.
3. **Fixed checksum first** (prerequisite for everything desync-related): replace the order-insensitive XOR (`simulation.gd:431-446` — swapped values cancel!) with an ordered FNV-1a-style hash covering ALL mutable state: gold, income timers, unit states, target ids, cooldowns. Add `compute_subchecksums()` (units/buildings/economy/RNG/grid) + `dump_state_json()` so any mismatch names the diverging subsystem (Riot's key-value pattern), replacing the empty debug stub.
4. **Lockstep peer harness** (`test_lockstep_determinism.gd`): extract the flush/commit/redundant-send/stall state machine into a plain `LockstepPeer` RefCounted with injected transport+clock; run TWO peers + TWO sims in one headless process over a FakeRelay with scripted delays/stalls; assert identical (tick, command) application and per-tick checksums. **Encode BUG-DESYNC1's stall-boundary timing as a permanent scenario** — this <1s test is the one that would have caught our historical desync. (GGPO "synctest" / Rare networked-test / Factorio black-box pattern.)
5. **Determinism soak (short)** (`test_determinism_soak.gd`): 20 fixed seeds × random valid command scripts × random latency/stall schedules, each run as re-run determinism + through the peer harness, per-10-tick checksum traces + invariants (HP bounds, gold ≥ 0, occupancy == alive units). ~30s. (500-seed version runs nightly.)
6. **Replay pack** (Riot SNR / Factorio CRC corpus): every match anywhere (autotest, balance, scenarios, REAL online matches) dumps `{sim_version, seed, setup, tick-stamped commands, checksums}` to JSON. Checked-in corpus replays headless per-commit (~2s per match). Every desync ever hit becomes a permanent regression test, and a live desync auto-produces its own offline repro + triage bundle on both clients.
7. **Banned-API lint** over `core/*.gd`: reject `randf/randomize/Time./sin(/cos(/float` literals etc. — fences the fixed-point sim against nondeterminism leaks that same-binary re-runs can't catch. Milliseconds.
8. **Behavior audit** (~2s) — as today.
9. **Layout assertions (NEW layer, headless, no rendering)**: instantiate UI scenes headless and assert on the Control tree — overlap, offscreen, touch-target ≥ 88px, anchoring, non-empty labels. The DOM-testing equivalent; survives redesigns better than any pixel technique and costs seconds. Catches the "button half off-screen" class without a single rendered frame.

### L1 — Visual truth: deterministic single-frame goldens (seconds per screen, not 90s per everything)
1. **Per-screen capture flags**: generalize `--autotest-loading` into `--capture menu_shop`, `--capture end_victory`, `--capture game@tick:300`. `_select_tab(i)` and forced-victory paths already exist. Target ~10s per single-screen capture vs 60–90s for all 19.
2. **State-at-tick-N tool** (the single biggest win our decoupled sim enables): step the sim headlessly to tick N in milliseconds, hand it to the visual layer, render ONE frame, capture. Kills the 60s real-time gameplay tax for gameplay-visual checks.
3. **Golden-image diffs replace absolute-coordinate detectors**: per-screen golden PNGs committed to the repo; pixelmatch-style AA-aware diff (threshold ~0.1, image budget ≤0.5–1% differing pixels); mask rects over dynamic regions (timers, damage numbers, particles); explicit `--update-goldens` re-bless whose image diff is reviewed like code. A legitimate redesign costs one deliberate re-bless, not a detector recalibration session.
4. **Surviving semantic detectors go two-phase**: (1) LOCATE the element at runtime (live node rect via scene query, or signature scan — "widest wood-colored run", not "wood at y=920"); (2) assert the invariant inside the found region. Keep only where a golden can't express the check (readability, continuity).
5. **Capture integrity is non-negotiable**: capture tool writes a `manifest.json` (run id, expected file list); wrapper counts PNGs, exits non-zero on shortfall, retries once (Rare's flake policy: second failure = red; single pass-after-retry = logged intermittent). Missing/stale capture = **FAIL** in the layout suite (fix at `test_screen_layout.gd:678`). Captures move out of `/tmp` (macOS purges it) to a repo-ignored `test_output/`.
6. **Determinism of pixels — phased**: Phase A (now): windowed capture on this Mac, fixed seed, capture keyed to sim tick, animations masked. Single-machine goldens are actually an advantage (no cross-platform drift). Phase B (when flake or CI demands it): Linux arm64 Godot in Docker + `xvfb-run --rendering-driver opengl3` (llvmpipe software rendering = bit-stable pixels, no window stealing focus, same container runs in CI later). Note: Godot `--headless` can NEVER produce pixels (dummy rendering server; `--write-movie` incompatible; offscreen proposal unmerged) — a display server is mandatory for rendering, so Xvfb-in-Docker is the only "invisible" option. Movie Maker mode (`--write-movie frames.png --fixed-fps 10` under Xvfb) gives one lossless PNG per sim tick for gameplay sequences — strictly better than timer-based screenshots.

### L2 — Input & integration scenarios (the ONLY windowed layer; seconds each)
1. **Adopt `tests/scenarios/` as the official harness** (it already exists and is the right shape: real synthesized input, fixed seed 12345, per-scenario dirs). Migrate remaining `--autotest` duties into targeted scenarios; **no bare sleeps — condition-poll state with timeouts** (Riot/Rare rule; also fixes the frame-race capture bugs).
2. **Add touch primitives** (`InputEventScreenTouch`/`ScreenDrag`) to `scenario_base.gd` — touch has literally zero coverage while we ship portrait mobile. Add scenarios: `place_building_zoomed_touch`, `pinch_zoom_pan`, `radial_menu_under_zoom`, `emulated_mouse_dedup` (the P0 mobile bug). Assert on SIM state (building landed on cell X) + camera transform, plus one capture into the golden suite. Note: `Input.parse_input_event` does not dispatch under `--headless` (godot#73557) — input scenarios need the windowed/Xvfb path.
3. Consider gdUnit4 SceneRunner later for its input-simulation API (multi-touch press/drag, `await_input_processed`) — but do NOT migrate the 395-assert sim suite; plain `-s` scripts are fine.

### L3 — Nightly / on-demand (minutes; never blocks iteration)
1. **Balance suite** (measured 176s): 100 AI-vs-AI matches; after Phase 2 extracts the AI, it finally tests the REAL shipped AI. Extend toward King/SEED-style coverage: bot personas (rush/turtle/economy/random-legal "curiosity"), invariants (terminates, 45–55% faction win-rate, no stuck units); any crash or invariant breach auto-saves its command recording into the replay pack.
2. **Two-client Nakama match test**: `docker compose up` local Nakama + two Godot instances with a `--bot` flag playing a scripted 60s match over the REAL websocket; assert checksums agree every N ticks, match completes, both agree on winner. Turns `tasks/multiplayer-test-guide.md` from a manual procedure into a suite. This is Rare's server+2-client test at our scale.
3. **Web-export smoke via Playwright** (headless Chromium, SwiftShader WebGL, `hasTouch: true`, 720×1280): serve `export/web` with COOP/COEP headers, assert boot-to-menu <30s, fail on any pageerror (catches the WASM/web-audio breakage class), screenshot into the golden suite. Extension: two browser contexts + local Nakama = automated multiplayer test of the SHIPPED artifact with real browser touch events.
4. **Full windowed autotest** survives only here, as the end-to-end smoke.

### L4 — Human (Neil): game feel only
Automation owns regression/state/throughput. Short exploratory playtests of the web export focus on feel, visuals, audio, fun — the things every studio deliberately leaves to humans. Agents must never claim "feels right" from a screenshot; they claim "matches spec/golden/invariant."

---

## Part 3 — Policy gates (no new tech, borrowed from Rare/Riot)
1. **Every gameplay/UI change lands with the test or detector that covers it**, written by the implementing agent (red → green in the same branch).
2. **Artifact self-verification everywhere**: any job that produces files verifies count + manifest before exiting 0.
3. **Retry-once flake policy + quarantine**: flaky test → quarantine suite (runs, reports, can't fail the build) → fix or delete by deadline. Keeps the gate credible instead of ignored.
4. **Confirmed bugs before new features** (Rare's open-bug-cap discipline).
5. **Checksum/golden re-pins are deliberate, reviewed acts** — a re-bless commit shows the image/value diff.

## Part 4 — What changes in practice (cost math)

| Question being asked | Today | Redesigned |
|---|---|---|
| "Did my sim change break logic?" | 2s headless ✅ | same, + determinism golden catches silent outcome drift |
| "Does the shop screen still look right?" | 60–90s windowed full run × 3–10 iterations | ~10s single-screen capture + golden diff |
| "Does placement work at zoom 1.5 with touch?" | ZERO coverage (manual phone test) | seconds: synthesized-input scenario asserting sim state |
| "Will two clients desync?" | ZERO automated coverage; find out live | <1s peer harness per-commit + 30s soak + nightly real-socket test |
| "Does the shipped web build boot?" | manual browser check | nightly Playwright smoke |
| "0 captures produced" | silent green | hard red + one retry |

## Part 5 — Build order (folds into campaign Phase 0; ~1 day of orchestrated agent work)
1. Checksum fix + subchecksums + state dump (everything desync depends on it).
2. Capture integrity: manifest, hard-fail on missing/stale, retry-once, move out of /tmp, fix unawaited-coroutine races, per-screen `--capture` flags.
3. Determinism goldens on the sim suite + banned-API lint + replay-pack recorder.
4. LockstepPeer extraction + `test_lockstep_determinism.gd` (with BUG-DESYNC1 scenario) + short soak.
5. Layout-assertion layer + two-phase rewrite of surviving detectors + first golden set (bless current-good screens only — BUG-47/49 stay red until fixed).
6. Touch primitives + the 4 input scenarios.
7. Triage the currently-failing `test_targeting_diag.gd` / `test_unit_behavior.gd` (fix or quarantine with deadline).
8. Correct CLAUDE.md test table (balance 176s, real invocations, new pyramid).
9. Nightly tier (Nakama 2-client, Playwright, Docker/Xvfb goldens) — during Phase 1B, not blocking.

**Sources**: Riot engineering blog (automated testing, determinism ×2), Factorio FFF-60/62/340/366 + wiki, Rare GDC 2019 (Masella), King/Ubisoft/EA-SEED GDC talks, gdUnit4 docs, godot#73557/#101773, proposals#5790, measured timings this machine 2026-07-07. Full research in workflow journal `wf_12d67fe1-256`.
