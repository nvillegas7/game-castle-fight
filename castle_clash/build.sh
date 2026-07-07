#!/usr/bin/env bash
# build.sh — Export, compress, and deploy Castle Fight to Cloudflare Pages.
# Run from the castle_clash/ directory: ./build.sh
#
# Anti-stale-cache design (multiplayer desync prevention):
#   1. BUILD_ID is stamped into project.godot's config/version before export.
#      NetworkManager reads it and includes it in MATCH_CONFIG — clients on
#      different builds abort the match instead of checksum-desyncing.
#   2. index.{pck,wasm,js} (+ audio worklets) are renamed with a short content
#      hash and index.html is rewritten to reference the hashed names. Hashed
#      files are immutable-cacheable forever; index.html itself is no-cache,
#      so every page load picks up the newest build atomically.

set -euo pipefail

EXPORT_DIR="export/web"
PROJECT_NAME="castlefight"

# --- 1. Preflight checks ---
command -v godot >/dev/null || { echo "godot not found in PATH"; exit 1; }
command -v brotli >/dev/null || { echo "brotli not found — install with: brew install brotli"; exit 1; }
command -v wrangler >/dev/null || { echo "wrangler not found — install with: npm install -g wrangler"; exit 1; }
[ -f project.godot ] || { echo "project.godot not found — run from the castle_clash/ directory"; exit 1; }

# --- 2. Stamp build identity into project.godot (restored after export) ---
# NetworkManager.build_id reads application/config/version at runtime.
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
BUILD_ID="${GIT_SHA}-$(date -u +%Y%m%d%H%M%S)"
BASE_VERSION=$(sed -n 's/^config\/version="\([^"+]*\).*/\1/p' project.godot)
echo "→ Stamping build id: ${BASE_VERSION}+${BUILD_ID}"
cp project.godot project.godot.prebuild
restore_project_godot() {
  if [ -f project.godot.prebuild ]; then
    mv -f project.godot.prebuild project.godot
  fi
}
trap restore_project_godot EXIT
sed -i '' "s|^config/version=\".*\"|config/version=\"${BASE_VERSION}+${BUILD_ID}\"|" project.godot

# --- 3. Export from Godot ---
echo "→ Exporting web build…"
# Remove hashed artifacts from previous builds so the deploy stays clean.
rm -f "$EXPORT_DIR"/index.[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f].*
godot --headless --export-release "Web" "$EXPORT_DIR/index.html"

# Restore the un-stamped project.godot now that the pck is baked.
restore_project_godot
trap - EXIT

# --- 4. Content-hash the cacheable payload files ---
# A fixed filename + immutable Cache-Control let clients keep serving an OLD
# index.pck after a deploy — old sim code vs new sim code desyncs EVERY match.
# Hashed names make each build's files unique URLs.
HASH=$(cat "$EXPORT_DIR/index.pck" "$EXPORT_DIR/index.wasm" "$EXPORT_DIR/index.js" | shasum -a 256 | cut -c1-8)
echo "→ Content hash: ${HASH}"
mv "$EXPORT_DIR/index.pck"  "$EXPORT_DIR/index.${HASH}.pck"
mv "$EXPORT_DIR/index.wasm" "$EXPORT_DIR/index.${HASH}.wasm"
mv "$EXPORT_DIR/index.js"   "$EXPORT_DIR/index.${HASH}.js"
# Godot's loader derives worklet paths from the executable name (loadPath),
# so they must carry the same prefix as the renamed js/wasm.
mv "$EXPORT_DIR/index.audio.worklet.js"          "$EXPORT_DIR/index.${HASH}.audio.worklet.js"
mv "$EXPORT_DIR/index.audio.position.worklet.js" "$EXPORT_DIR/index.${HASH}.audio.position.worklet.js"

# Rewrite the exported shell to reference the hashed names:
#   <script src="index.js">            → index.<hash>.js
#   "executable":"index"               → "index.<hash>" (drives wasm/pck/worklet paths)
#   fileSizes keys                     → hashed (load progress bar)
sed -i '' \
  -e "s|\"index.js\"|\"index.${HASH}.js\"|g" \
  -e "s|\"executable\":\"index\"|\"executable\":\"index.${HASH}\"|g" \
  -e "s|\"index.pck\"|\"index.${HASH}.pck\"|g" \
  -e "s|\"index.wasm\"|\"index.${HASH}.wasm\"|g" \
  "$EXPORT_DIR/index.html"

# --- 5. Compress WASM + PCK with Brotli ---
echo "→ Compressing WASM (this takes ~30s)…"
WASM_BEFORE=$(stat -f%z "$EXPORT_DIR/index.${HASH}.wasm")
brotli -q 11 -f "$EXPORT_DIR/index.${HASH}.wasm" -o "$EXPORT_DIR/index.${HASH}.wasm.tmp"
mv "$EXPORT_DIR/index.${HASH}.wasm.tmp" "$EXPORT_DIR/index.${HASH}.wasm"
WASM_AFTER=$(stat -f%z "$EXPORT_DIR/index.${HASH}.wasm")

echo "→ Compressing PCK…"
PCK_BEFORE=$(stat -f%z "$EXPORT_DIR/index.${HASH}.pck")
brotli -q 11 -f "$EXPORT_DIR/index.${HASH}.pck" -o "$EXPORT_DIR/index.${HASH}.pck.tmp"
mv "$EXPORT_DIR/index.${HASH}.pck.tmp" "$EXPORT_DIR/index.${HASH}.pck"
PCK_AFTER=$(stat -f%z "$EXPORT_DIR/index.${HASH}.pck")

printf "  index.%s.wasm: %s → %s (%.0f%% reduction)\n" "$HASH" \
  "$(numfmt --to=iec "$WASM_BEFORE")" "$(numfmt --to=iec "$WASM_AFTER")" \
  "$(echo "scale=0; (1 - $WASM_AFTER / $WASM_BEFORE) * 100" | bc -l)"
printf "  index.%s.pck:  %s → %s (%.0f%% reduction)\n" "$HASH" \
  "$(numfmt --to=iec "$PCK_BEFORE")" "$(numfmt --to=iec "$PCK_AFTER")" \
  "$(echo "scale=0; (1 - $PCK_AFTER / $PCK_BEFORE) * 100" | bc -l)"

# Check Cloudflare Pages 25 MiB per-file limit
MAX_BYTES=$((25 * 1024 * 1024))
if [ "$WASM_AFTER" -gt "$MAX_BYTES" ]; then
  echo "✗ index.${HASH}.wasm still over 25 MiB after compression. Cannot deploy to Cloudflare Pages free tier."
  exit 1
fi

# --- 6. Write _headers so Cloudflare sends the right Content-Encoding ---
# Hashed files: immutable forever (their URL changes every build).
# index.html: no-cache so every load revalidates and finds the new build.
echo "→ Writing _headers for Cloudflare Pages…"
cat > "$EXPORT_DIR/_headers" <<EOF
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: credentialless

/
  Cache-Control: no-cache

/index.html
  Cache-Control: no-cache

/index.${HASH}.wasm
  Content-Type: application/wasm
  Content-Encoding: br
  Cache-Control: public, max-age=31536000, immutable

/index.${HASH}.pck
  Content-Encoding: br
  Cache-Control: public, max-age=31536000, immutable

/index.${HASH}.js
  Cache-Control: public, max-age=31536000, immutable

/index.${HASH}.audio.worklet.js
  Cache-Control: public, max-age=31536000, immutable

/index.${HASH}.audio.position.worklet.js
  Cache-Control: public, max-age=31536000, immutable
EOF

# --- 7. Deploy to Cloudflare Pages ---
echo "→ Deploying to Cloudflare Pages…"
wrangler pages deploy "$EXPORT_DIR" --project-name="$PROJECT_NAME"

echo "✓ Done. Live at https://${PROJECT_NAME}.pages.dev"
echo "  Build: ${BASE_VERSION}+${BUILD_ID} assets index.${HASH}.*"
echo "  Custom domain (play.castlefight.net) will serve this too if configured in the Cloudflare dashboard."
