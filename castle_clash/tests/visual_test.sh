#!/bin/bash
# Visual test: capture game screenshots and analyze them.
# Usage: bash tests/visual_test.sh
# Output: /tmp/castle_clash_test/ with numbered PNGs + analysis

set -e

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="/tmp/castle_clash_test"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== Castle Clash Visual Test ==="
echo "Capturing 60 frames of game arena..."

# Capture game arena frames (bypasses menu with --scene)
godot --path "$PROJ_DIR" \
  --scene res://scenes/game/game_arena.tscn \
  --write-movie "$OUT_DIR/arena.png" \
  --fixed-fps 10 \
  --quit-after 60 \
  --disable-vsync \
  2>/dev/null

echo "Capturing 30 frames of main menu..."

# Capture main menu frames
godot --path "$PROJ_DIR" \
  --write-movie "$OUT_DIR/menu.png" \
  --fixed-fps 10 \
  --quit-after 30 \
  --disable-vsync \
  2>/dev/null

ARENA_COUNT=$(ls "$OUT_DIR"/arena*.png 2>/dev/null | wc -l | tr -d ' ')
MENU_COUNT=$(ls "$OUT_DIR"/menu*.png 2>/dev/null | wc -l | tr -d ' ')

echo "Captured $ARENA_COUNT arena frames, $MENU_COUNT menu frames"
echo "Frames saved to $OUT_DIR/"

# Run pixel analysis
python3 - "$OUT_DIR" <<'PYEOF'
import sys, os, glob
try:
    from PIL import Image
except ImportError:
    print("WARNING: Pillow not installed, skipping pixel analysis")
    sys.exit(0)

out_dir = sys.argv[1]
results = {"arena": {}, "menu": {}}

# Analyze last arena frame (most representative - units spawned, combat happening)
arena_frames = sorted(glob.glob(os.path.join(out_dir, "arena*.png")))
if arena_frames:
    img = Image.open(arena_frames[-1])
    w, h = img.size
    pixels = list(img.getdata())
    total = len(pixels)

    # Check if screen is blank
    unique_colors = len(set(pixels[:1000]))
    results["arena"]["unique_colors_sample"] = unique_colors
    results["arena"]["is_blank"] = unique_colors < 5

    # Check green pixels (trees/grass)
    green_count = sum(1 for p in pixels if p[1] > p[0] + 15 and p[1] > 50)
    results["arena"]["green_percentage"] = round(green_count / total * 100, 1)
    results["arena"]["has_vegetation"] = green_count / total > 0.15

    # Check HUD region (top 48px)
    hud_pixels = [pixels[y * w + x] for y in range(48) for x in range(w)]
    hud_dark = sum(1 for p in hud_pixels if sum(p[:3]) < 200)
    results["arena"]["hud_rendering"] = hud_dark / len(hud_pixels) > 0.3

    # Check card hand region (bottom 240px)
    card_pixels = [pixels[y * w + x] for y in range(h - 240, h) for x in range(w)]
    card_variety = len(set(card_pixels[:500]))
    results["arena"]["cards_rendering"] = card_variety > 20

    # Check brown pixels (combat lane)
    brown_count = sum(1 for p in pixels if p[0] > 100 and p[1] > 80 and p[1] < p[0] and p[2] < p[1])
    results["arena"]["has_combat_lane"] = brown_count / total > 0.05

    print(f"\nArena Analysis ({w}x{h}):")
    print(f"  Blank screen: {'YES - BUG!' if results['arena']['is_blank'] else 'No (good)'}")
    print(f"  Vegetation: {results['arena']['green_percentage']}% green pixels ({'OK' if results['arena']['has_vegetation'] else 'MISSING!'})")
    print(f"  HUD rendering: {'Yes' if results['arena']['hud_rendering'] else 'MISSING!'}")
    print(f"  Cards rendering: {'Yes' if results['arena']['cards_rendering'] else 'MISSING!'}")
    print(f"  Combat lane: {'Yes' if results['arena']['has_combat_lane'] else 'MISSING!'}")
    print(f"  Last frame: {arena_frames[-1]}")

# Analyze menu
menu_frames = sorted(glob.glob(os.path.join(out_dir, "menu*.png")))
if menu_frames:
    img = Image.open(menu_frames[-1])
    pixels = list(img.getdata())
    total = len(pixels)
    unique = len(set(pixels[:2000]))
    results["menu"]["unique_colors_sample"] = unique
    results["menu"]["is_blank"] = unique < 5
    print(f"\nMenu Analysis ({img.size[0]}x{img.size[1]}):")
    print(f"  Blank screen: {'YES - BUG!' if results['menu']['is_blank'] else 'No (good)'}")
    print(f"  Color variety: {unique} unique colors in sample")
    print(f"  Last frame: {menu_frames[-1]}")

# Save analysis as JSON
import json
with open(os.path.join(out_dir, "analysis.json"), "w") as f:
    json.dump(results, f, indent=2)
print(f"\nAnalysis saved to {out_dir}/analysis.json")
PYEOF

echo ""
echo "Done. Review frames at: $OUT_DIR/"
echo "Key frames to inspect:"
echo "  Arena (late game): $OUT_DIR/$(ls $OUT_DIR/arena*.png 2>/dev/null | tail -1 | xargs basename 2>/dev/null || echo 'N/A')"
echo "  Menu: $OUT_DIR/$(ls $OUT_DIR/menu*.png 2>/dev/null | tail -1 | xargs basename 2>/dev/null || echo 'N/A')"
