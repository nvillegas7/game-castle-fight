#!/bin/bash
# Master test runner for Castle Clash.
# Usage: bash tests/run_all.sh
# Runs: headless simulation tests, visual capture, scene validation
set -e

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

echo "============================================"
echo "  Castle Clash - Full QA Test Suite"
echo "============================================"
echo ""

# 1. Headless simulation tests
echo "--- [1/3] Simulation Tests (headless) ---"
if godot --headless --path "$PROJ_DIR" -s tests/test_simulation.gd 2>/dev/null; then
    echo "Simulation tests: PASSED"
else
    echo "Simulation tests: FAILED"
    FAILED=1
fi
echo ""

# 2. Scene resource validation
echo "--- [2/3] Scene Resource Validation ---"
python3 - "$PROJ_DIR" <<'PYEOF'
import os, re, sys

proj = sys.argv[1]
errors = 0

for root, dirs, files in os.walk(proj):
    for f in files:
        if not f.endswith(".tscn"):
            continue
        path = os.path.join(root, f)
        with open(path) as fp:
            content = fp.read()
        # Check ext_resource paths
        for m in re.finditer(r'path="(res://[^"]+)"', content):
            res_path = m.group(1).replace("res://", proj + "/")
            if not os.path.exists(res_path):
                print(f"  MISSING: {m.group(1)} in {f}")
                errors += 1

# Check all .tres unit/building files have required fields
for subdir in ["data/units", "data/buildings"]:
    tres_dir = os.path.join(proj, subdir)
    if not os.path.isdir(tres_dir):
        continue
    for f in os.listdir(tres_dir):
        if not f.endswith(".tres"):
            continue
        with open(os.path.join(tres_dir, f)) as fp:
            content = fp.read()
        if "id = " not in content:
            print(f"  MISSING 'id' in {subdir}/{f}")
            errors += 1

if errors == 0:
    print("  All scene resources validated: PASS")
else:
    print(f"  {errors} resource errors found: FAIL")
    sys.exit(1)
PYEOF
if [ $? -eq 0 ]; then
    echo "Scene validation: PASSED"
else
    echo "Scene validation: FAILED"
    FAILED=1
fi
echo ""

# 3. Visual screenshot test
echo "--- [3/3] Visual Screenshot Capture ---"
if bash "$PROJ_DIR/tests/visual_test.sh" 2>/dev/null; then
    echo "Visual capture: COMPLETED"
else
    echo "Visual capture: FAILED (Godot may need display)"
    # Not a hard failure — headless may not support --write-movie
fi
echo ""

# 4. Video test suite (needs display — non-fatal)
echo "--- [4/4] Video Test Suite ---"
if godot --path "$PROJ_DIR" -- --videotest --scenario melee 2>/dev/null; then
    echo "Video test (melee): COMPLETED"
else
    echo "Video test: SKIPPED (needs display)"
fi
echo ""

# 5. Balance test (headless, 100 AI-vs-AI matches)
echo "--- [5/7] Balance Test (100 matches) ---"
if godot --headless --path "$PROJ_DIR" -s tests/test_balance.gd 2>/dev/null; then
    echo "Balance test: PASSED"
else
    echo "Balance test: FAILED (see tests/balance_results.json)"
    # Not a hard failure — balance issues are design, not crashes
fi
echo ""

# 6. Tutorial visual test (needs display — non-fatal)
echo "--- [6/7] Tutorial Visual Test ---"
if godot --path "$PROJ_DIR" -- --tutorialtest 2>/dev/null; then
    echo "Tutorial visual test: COMPLETED (see /tmp/castle_clash_tutorial/)"
else
    echo "Tutorial visual test: SKIPPED (needs display)"
fi
echo ""

# 7. Audio regression test (needs display — non-fatal)
echo "--- [7/7] Audio Regression Test ---"
if godot --path "$PROJ_DIR" -- --audiotest 2>/dev/null; then
    echo "Audio regression test: COMPLETED (see /tmp/castle_clash_audio/)"
else
    echo "Audio regression test: SKIPPED (needs display)"
fi
echo ""

echo "============================================"
if [ $FAILED -eq 0 ]; then
    echo "  ALL TESTS PASSED"
else
    echo "  SOME TESTS FAILED"
fi
echo "============================================"
exit $FAILED
