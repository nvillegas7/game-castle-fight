#!/usr/bin/env bash
# Capture-pipeline wrapper for the visual (L1) gate.
#
# Runs the windowed --autotest, then verifies it produced a VALID manifest
# (ok:true, non-zero captures). Retries once on failure (Rare's flake policy:
# a single pass-after-retry is logged as intermittent, not red). Exits non-zero
# if captures are still missing/failed — so the pixel gate can never pass on
# stale or zero screenshots (the "0 captures, exit 0" hole).
#
# Requires a display (opens a window on the dev Mac). The Xvfb/Docker path for
# invisible, deterministic capture is the nightly-tier improvement — see
# tasks/design-verification-workflow.md L1 phase B.
set -uo pipefail

CLASH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$CLASH_DIR/test_output/autotest/manifest.json"

run_once() {
	rm -f "$MANIFEST"
	( cd "$CLASH_DIR" && godot --path . -- --autotest ) || true
	[[ -f "$MANIFEST" ]] && grep -q '"ok": true' "$MANIFEST"
}

if run_once; then
	echo "[capture] OK — $(grep '"count"' "$MANIFEST" | tr -d ' ,')"
	exit 0
fi
echo "[capture] first attempt failed — retrying once"
if run_once; then
	echo "[capture] OK on retry (logged as intermittent)"
	exit 0
fi
echo "[capture] FAILED after retry — no valid manifest at $MANIFEST"
exit 1
