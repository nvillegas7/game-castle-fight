#!/bin/bash
# Scenario harness runner — runs every scenario sequentially (each in its own
# windowed godot invocation), builds per-scenario contact sheets, and prints a
# pass/fail table. Windowed runs share one display, so this waits for any
# other windowed godot test (autotest/videotest/scenario) to finish first.
#
# Usage: bash tools/run_scenarios.sh                 # all scenarios
#        bash tools/run_scenarios.sh camera menu_tour  # subset
#
# Exit code: 0 if every scenario passed, 1 otherwise.
# NOTE: a failing scenario is not always a harness bug — bug-repro scenarios
# (e.g. place_building_zoomed) are EXPECTED to fail until the game bug is fixed.

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="/tmp/castle_clash_scenarios"
GODOT="${GODOT:-godot}"
SHELL_TIMEOUT=210   # seconds; in-game watchdog is 150s — this is the backstop

ALL_SCENARIOS=(place_building place_building_zoomed castle_wrath camera menu_tour end_screen)
if [ "$#" -gt 0 ]; then
    SCENARIOS=("$@")
else
    SCENARIOS=("${ALL_SCENARIOS[@]}")
fi

# Another process may own the display — wait (up to 3 min) until no other
# windowed godot test is running.
wait_for_display() {
    local waited=0
    while pgrep -f "godot.*(autotest|videotest|tutorialtest|audiotest|showcase|--scenario)" >/dev/null 2>&1; do
        if [ "$waited" -ge 180 ]; then
            echo "  WARN: display still busy after 180s — proceeding anyway"
            break
        fi
        echo "  display busy (another windowed godot test running) — waiting ${waited}s..."
        sleep 5
        waited=$((waited + 5))
    done
}

RESULTS=()
FAILED=0

echo "============================================"
echo "  Castle Fight — Scenario Test Harness"
echo "============================================"

for name in "${SCENARIOS[@]}"; do
    echo ""
    echo "--- scenario: $name ---"
    wait_for_display
    "$GODOT" --path "$PROJ_DIR" -- --scenario "$name" &
    GPID=$!
    SECS=0
    while kill -0 "$GPID" 2>/dev/null; do
        sleep 2
        SECS=$((SECS + 2))
        if [ "$SECS" -ge "$SHELL_TIMEOUT" ]; then
            echo "  TIMEOUT after ${SHELL_TIMEOUT}s — killing pid $GPID"
            kill -9 "$GPID" 2>/dev/null
            break
        fi
    done
    wait "$GPID"
    CODE=$?
    # Per-scenario pass/fail detail from the result.json the scenario wrote
    DETAIL=""
    if [ -f "$OUT_ROOT/$name/result.json" ]; then
        DETAIL=$(python3 -c "import json;d=json.load(open('$OUT_ROOT/$name/result.json'));print('%d passed, %d failed' % (d['passed'], d['failed']))" 2>/dev/null)
    fi
    if [ "$CODE" -eq 0 ]; then
        RESULTS+=("PASS  $name  ($DETAIL)")
    else
        RESULTS+=("FAIL  $name  (exit $CODE${DETAIL:+, $DETAIL})")
        FAILED=1
    fi
    # Contact sheet for instant eyeballing
    if [ -d "$OUT_ROOT/$name" ]; then
        python3 "$PROJ_DIR/tools/contact_sheet.py" "$OUT_ROOT/$name" \
            -o "$OUT_ROOT/${name}_sheet.png" 2>/dev/null || true
    fi
done

echo ""
echo "============================================"
echo "  Scenario Results"
echo "============================================"
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
echo "  captures + sheets: $OUT_ROOT/"
echo "============================================"
exit $FAILED
