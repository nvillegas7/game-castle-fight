# Scenario Test Harness

Automated, reproducible interaction tests — replaces human screen-recorded
playtests. Each scenario scripts a sequence of real interactions (taps, drags,
wheel zooms, middle-drag pans) plus forced game states, captures screenshots
with state-dump JSON, and asserts against sim/UI state.

## Run

```bash
# One scenario (windowed — needs the display):
godot --path castle_clash -- --scenario place_building

# All scenarios + contact sheets + summary table:
bash castle_clash/tools/run_scenarios.sh

# Subset:
bash castle_clash/tools/run_scenarios.sh camera menu_tour
```

Output per scenario: `/tmp/castle_clash_scenarios/<name>/NN_<label>.png`
(screenshot) + `NN_<label>.json` (sim/UI state dump) + `result.json`
(check list). The runner also builds `/tmp/castle_clash_scenarios/<name>_sheet.png`
(labeled contact sheet, see `tools/contact_sheet.py`).

Exit code 0 = all checks passed. Console prints `PASS:`/`FAIL:` per check and
`=== Results: N passed, M failed ===`, same as the other suites.

## Scenarios (v1)

| Scenario | What it proves |
|---|---|
| `place_building` | Card tap + hold-drag-release places the building in the exact sim cell targeted (default zoom) |
| `place_building_zoomed` | Same placement while zoomed 2x + panned. **Repro for the placement-under-zoom bug — expected to FAIL until fixed** (logs measured px/cell offset) |
| `castle_wrath` | Wrath button appears at <30% castle HP, tap activates the sim ability, enemy units in range take damage |
| `camera` | Wheel zoom clamps to [0.5, 2.0]; middle-drag pan clamps to arena bounds; captures at every extreme |
| `menu_tour` | Taps all 5 menu tabs via the real tab buttons, captures each panel |
| `end_screen` | Victory (units finish a 1-HP castle), restart via real button, defeat variant |

A FAILing scenario that reproduces a reported bug is a *successful repro*,
not a harness defect — fix the game, then the scenario becomes the regression
test.

## Writing a scenario

Create `tests/scenarios/<name>.gd` extending `ScenarioBase` and override
`run()`. Primitives (all `await`-able):

- `wait(seconds)` / `wait_ticks(n)`
- `start_match(faction, disable_ai)` — offline match, FIXED seed 12345
  (captures comparable run-to-run; disable AI for determinism, keep it on
  when you need enemy units)
- `force_state({...})` — `gold`, `castle0_hp_pct`, `castle1_hp`, `camera_zoom`,
  `camera_pos`, `ai_disabled` (test-only hook; reaches into autoloads, no
  production-code flags)
- `tap(vp_pos)` / `drag(from, to, duration)` / `wheel(notches)` /
  `zoom(factor)` / `pan_keys(dir, seconds)` / `pan_middle_drag(world_delta)` /
  `key(keycode, pressed)` — synthesized via `Input.parse_input_event()` in
  **window coordinates** so the canvas_items stretch transform applies
  exactly as for real input. Never call game handlers directly.
  (`pan_middle_drag` is currently a bug-repro path: STOP-filter terrain
  ColorRects eat the middle press before `_unhandled_input` — use `pan_keys`
  when a scenario needs panning that works.)
- `select_card(id)` / `place_building_via_input(id, cell)` — composite flows
- `capture(label)` — PNG + state-dump JSON
- `check(name, cond, detail)` / `assert_state(callable_or_dict)`

The driver (`tests/scenarios/scenario_runner.gd`, autoload) has a 150s
watchdog; `tools/run_scenarios.sh` adds a 210s process-kill backstop and
waits for any other windowed godot test before starting.
