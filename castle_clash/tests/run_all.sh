#!/usr/bin/env bash
# Layered verification gate for Castle Fight.
# See tasks/design-verification-workflow.md for the pyramid.
#
#   L0  headless, <1 min, HARD gate      — runs by default, any failure = red
#   L1  visual (needs a display), HARD   — capture + pixel detectors; SKIP_VISUAL=1 to skip
#   L3  nightly/on-demand, non-fatal     — RUN_NIGHTLY=1 to include (balance, audio)
#
# Usage:
#   bash tests/run_all.sh                 # L0 + L1
#   SKIP_VISUAL=1 bash tests/run_all.sh   # L0 only (pure headless / CI without display)
#   RUN_NIGHTLY=1 bash tests/run_all.sh   # L0 + L1 + L3
set -uo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

run_headless() {  # name, script
	echo "--- $1 ---"
	# Capture fully before grepping: `grep -q` would close the pipe early and,
	# under pipefail, godot's SIGPIPE would false-fail the larger suites.
	local out
	out="$(godot --headless --path "$PROJ_DIR" -s "$2" 2>&1)"
	if echo "$out" | grep -qE "Results:.*, 0 failed|TOTAL: [0-9]+ PASS, 0 FAIL"; then
		echo "  PASS"
	else
		echo "  FAIL ($2)"
		FAILED=1
	fi
}

echo "============================================"
echo "  Castle Fight — Verification Gate"
echo "============================================"

echo ""
echo "### L0 — headless hard gate ###"
run_headless "Simulation (395 asserts)"        tests/test_simulation.gd
run_headless "Determinism lint (banned APIs)"  tests/test_banned_api.gd
run_headless "Replay determinism + golden"     tests/test_replay_determinism.gd
run_headless "Behavior audit (movement)"       tests/test_behavior_audit.gd
run_headless "Combat feel (walk cadence)"      tests/test_combat_feel.gd
run_headless "Targeting diagnostics"           tests/test_targeting_diag.gd
run_headless "Unit behavior scenarios"         tests/test_unit_behavior.gd
run_headless "Arena AI (Phase 2.1 extraction)" tests/test_arena_ai.gd
run_headless "Placement hygiene (T-QA1)"        tests/test_placement_hygiene.gd
run_headless "Multiplayer (checksum/config)"   tests/test_multiplayer.gd
run_headless "UIStyle kit contract"            tests/test_ui_style.gd

echo ""
echo "### L0 — scene resource validation ###"
python3 - "$PROJ_DIR" <<'PYEOF'
import os, re, sys
proj = sys.argv[1]
errors = 0
for root, _, files in os.walk(proj):
    for f in files:
        if not f.endswith(".tscn"):
            continue
        with open(os.path.join(root, f)) as fp:
            content = fp.read()
        for m in re.finditer(r'path="(res://[^"]+)"', content):
            res_path = m.group(1).replace("res://", proj + "/")
            if not os.path.exists(res_path):
                print(f"  MISSING: {m.group(1)} in {f}"); errors += 1
print("  PASS" if errors == 0 else f"  FAIL - {errors} missing resources")
sys.exit(1 if errors else 0)
PYEOF
[ $? -eq 0 ] || FAILED=1

if [ "${SKIP_VISUAL:-0}" != "1" ]; then
	echo ""
	echo "### L1 - visual gate (capture + pixel detectors) ###"
	echo "--- Capture pipeline (windowed) ---"
	if bash "$PROJ_DIR/tests/capture.sh"; then
		echo "  capture PASS"
		run_headless "Screen-layout pixel detectors" tests/test_screen_layout.gd
	else
		echo "  FAIL - capture pipeline produced no valid manifest"
		FAILED=1
	fi
else
	echo ""
	echo "### L1 - SKIPPED (SKIP_VISUAL=1) ###"
fi

if [ "${RUN_NIGHTLY:-0}" = "1" ]; then
	echo ""
	echo "### L3 - nightly (non-fatal) ###"
	echo "--- Balance (2x100 matches: scripted mirror + real ArenaAI, ~6 min) ---"
	godot --headless --path "$PROJ_DIR" -s tests/test_balance.gd 2>&1 | grep -E "Balance Test Results|wins:|verdict|Crashes" || echo "  (see balance_results.json)"
	echo "--- Audio regression (needs display) ---"
	godot --path "$PROJ_DIR" -- --audiotest 2>/dev/null && echo "  audio done" || echo "  audio SKIPPED (needs display)"
fi

echo ""
echo "============================================"
if [ $FAILED -eq 0 ]; then
	echo "  GATE PASSED"
else
	echo "  GATE FAILED"
fi
echo "============================================"
exit $FAILED
