# PROCESS — How Castle Fight is built (single source of truth)

**Effective 2026-07-07.** Supersedes the 7-agent markdown-polling protocol
(`dispatch.md`, `team-protocol.md`, `agent-loop-prompts.md`, all now in `tasks/archive/`).
The A-roles below survive only as **subagent scopes** (which files a fix agent may touch),
not as standing cron processes.

---

## 1. Operating model

**One orchestrator (a single Claude session) + ephemeral, scoped subagents.**
The orchestrator owns the plan and the merge button. It spawns short-lived subagents to
do focused work, verifies their output against the gate, and integrates. Subagents do not
persist, do not poll, and do not talk to each other.

### Retired (do not resurrect)
- **`/loop` cron polling** — the ~13-min self-re-invoking sessions. 68% of the old
  coordination log was no-op ticks; order of 30M+ tokens caught zero regressions.
- **Agent Registry / IDLE-BUSY status** — no standing agents to register.
- **`dispatch.md` coordination-log messaging** — the 3,775-line task DB + inter-agent
  chat. Archived read-only.
- **Per-agent onboarding / boot sequence** — subagents get a scoped prompt, not a role.
- **Timer-driven QA** — QA is now event-driven (merge gate + post-merge smoke), never on a clock.

### Kept, repurposed
- **File Ownership Map → subagent SCOPING** (§6). One domain per fix subagent so parallel
  worktrees never touch the same file.
- **Detector-first QA** — a visual bug needs a pixel/layout detector that fails RED before
  the fix and passes GREEN after.
- **Test-before / test-after discipline** — capture the baseline, prove the delta.
- **`tasks/lessons.md`** — the mistake ledger; still updated after every correction.

---

## 2. Per-task pipeline

Every task walks this line. One task = one branch = one evidence-citing commit.

> **VISUAL/ART tasks** (screen look, terrain, menu styling) follow
> `tasks/design-flow.md` FIRST: compose the target in image space
> (`tools/compose_*.py`, ~0.1s/iteration) → user approves the target PNG →
> mechanical port to code → perceptual gate. Never art-direct by editing GDScript
> against a 90-second capture loop — that flow demonstrably never converges
> (see design-flow.md §failure).

1. **TRIAGE** — orchestrator picks the next `tasks/backlog.md` row, confirms it still
   reproduces, decides the domain scope and whether it can run in parallel.
2. **RED** — write the failing test / pixel detector FIRST and commit it (or stage it) so
   the gate is red before any fix exists. No RED artifact ⇒ the bug is not yet triaged.
3. **FIX** — spawn a subagent scoped to exactly one domain (§6). Parallel tasks run in
   isolated git worktrees over disjoint file domains; shared-file work (Phase 2) is sequential.
4. **VERIFY** — run the gate suite (§3). Paste the passing output. Risky diffs (sim math,
   lockstep, coordinate transforms) get an adversarial second read.
5. **INTEGRATE** — one commit per task; the message cites the evidence (test name + PASS line,
   or detector RED→GREEN). Main advances only via verified merges.
6. **POST-MERGE SMOKE** — re-run the gate on main. Any newly-red detector = immediate re-open;
   do not wait for a human to re-flag.

---

## 3. The gate — exact commands

Run from the `castle_clash/` project dir. Layers defined in `tests/run_all.sh`
(spec: `tasks/design-verification-workflow.md`).

| Layer | Command | Cost | When |
|-------|---------|------|------|
| **L0** headless hard gate | `SKIP_VISUAL=1 bash tests/run_all.sh` | <1 min, no display | every task branch |
| **L1** visual hard gate | `bash tests/run_all.sh` | + capture + detectors, **needs a display** | before merge of any UI/visual change |
| **L3** nightly (non-fatal) | `RUN_NIGHTLY=1 bash tests/run_all.sh` | minutes | nightly / on-demand |

### L0 suites and what each guards
- `test_simulation.gd` (395 asserts, ~2s) — FP Q16.16 math, combat, income, targeting, buildings.
- `test_banned_api.gd` — determinism lint over `core/*.gd`: rejects `randf/randomize/Time./sin(/cos(/float` literals that leak nondeterminism into the lockstep sim.
- `test_replay_determinism.gd` — replays the checked-in match corpus and compares final checksum to a pinned golden; catches silent sim-outcome drift.
- `test_behavior_audit.gd` — movement quality: zigzags, stuck units, targeting consistency.
- `test_targeting_diag.gd` — targeting acquisition diagnostics.
- `test_unit_behavior.gd` — per-unit behavior scenarios.
- `test_multiplayer.gd` — checksum / config-ACK / command routing.
- **Scene resource validation** (inline python) — every `res://…` path referenced by a `.tscn`
  exists on disk; catches missing `.ctex` / broken refs (the BUG-IMPORT class).

### L1 (visual)
`tests/capture.sh` writes a `manifest.json`, hard-fails on missing/stale captures, retries once,
and writes outside `/tmp` (macOS purges it). Only if capture succeeds does
`test_screen_layout.gd` run its pixel detectors. **A missing capture is a FAIL, never a vacuous PASS.**

### L3 (nightly, non-fatal)
`test_balance.gd` (100 AI-vs-AI matches, ~176s measured — not the ~30s the old CLAUDE.md table
claimed) + audio regression (needs display).

### Evidence rule (hard)
- **No status moves to done without pasted passing gate output.** A verdict without the
  output line is not a verdict.
- **Visual/UI bugs require a pixel or layout detector that fails RED on the pre-fix build**
  and passes on the fixed build. Cite the detector function name.
- Checksum/golden re-pins are deliberate, reviewed commits that show the value/image diff —
  never a silent recalibration.

---

## 4. Task tracking

- **`tasks/backlog.md`** — the live list: a compact table of OPEN work only. Short by design.
  When a row is done, delete it (git history is the record) — do not append a status log.
- **git history** — the permanent, bisectable log. One evidence-citing commit per task.
- **`tasks/dispatch.md`** — archived (`tasks/archive/`), read-only. Do not add to it.
- **`tasks/qa-bug-tracker.md`** — retained as the detailed bug write-ups (root cause, files,
  detector). New OPEN bugs get a one-line row in `backlog.md` pointing at their detail here.
- **`tasks/lessons.md`** — updated after any correction with a rule that prevents the repeat.

---

## 5. Layered verification philosophy (why L0/L1/L3 exist)

Do not answer every question with one 60–90s end-to-end run. Route the question to the
cheapest layer that can answer it (full rationale in `tasks/design-verification-workflow.md`):

- **Logic** ("did my sim change break rules?") → headless sim asserts (ms).
- **Layout** ("is the button off-screen / overlapping?") → scene-tree assertions, no rendering.
- **Appearance** ("does the shop still look right?") → single-frame golden diff (~10s), not 90s.
- **Input** ("does placement work at zoom 1.5 on touch?") → synthesized-input scenario asserting
  sim state (`tests/scenarios/`).
- **Network** ("will two clients desync?") → two-peers-in-one-process lockstep harness (<1s).
- **Feel** ("is it fun / smooth?") → **human only** (Neil). Agents never claim "feels right"
  from a screenshot; they claim "matches spec / golden / invariant."

The full windowed autotest survives only as a nightly end-to-end smoke, not an iteration loop.

---

## 6. Domain / ownership map (subagent scopes)

Copied from CLAUDE.md's File Ownership Map, reframed: **each row is the file scope a fix
subagent is allowed to touch.** Give a subagent exactly one row so parallel worktrees never
collide.

| Scope | Files |
|-------|-------|
| **A1** — infra / net | `autoload/game_manager.gd`, `autoload/network_manager.gd`, `autoload/event_bus.gd`, `autoload/player_data.gd`, `project.godot`, `export_presets.cfg` |
| **A2** — UI / visual | `scripts/ui/*.gd`, `scripts/game/sprite_*.gd`, `scripts/game/building_visual.gd`, `scripts/game/unit_visual.gd`, `scripts/game/castle_visual.gd`, `scripts/game/building_grid.gd`, `scenes/**/*.tscn`, `autoload/sprite_registry.gd` |
| **A3** — audio | `autoload/sfx.gd`, `assets/audio/**`, `default_bus_layout.tres` |
| **A4** — tests | `tests/**`, `tasks/qa-*.md` |
| **A5** — gameplay sim | `core/simulation.gd`, `core/*.gd`, `data/units/*.tres`, `data/buildings/*.tres`, `data/factions/*.tres`, `data_scripts/*.gd` |
| **A6** — sprites | `tools/generate_*.py`, `assets/sprites/units/` (generated), `assets/sprites/effects/` (generated) |
| **SHARED** | `scripts/game/game_arena.gd` — A2 owns visual/terrain, A5 owns AI logic. **Phase 2 splits this file** (`arena_ai.gd` + `arena_terrain.gd`) to end the contention. Until then, one owner at a time. |
| **NOBODY** | `addons/**` — third-party, do not modify |

A0 (design) has no code scope: it authors `tasks/design-*.md`, `tasks/plan-polish-parity.md`,
and files backlog rows. In the new model that is the orchestrator's planning role.
