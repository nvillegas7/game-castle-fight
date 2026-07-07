# A1 Session Handover — 2026-04-14 to 2026-04-17

## Role
A1 — Lead Programmer. Owns: network_manager.gd, game_manager.gd, event_bus.gd, player_data.gd, project.godot, export_presets.cfg, build.sh.

## What Was Completed

### 1. Multiplayer Desync Fix — DONE, USER CONFIRMED WORKING
**Root cause**: Race condition in lockstep flush. `flush_commands_for_tick()` sent empty commands before player placed a building. Remote advanced tick with empty commands; later re-flush arrived too late.

**Fix in `autoload/network_manager.gd`**:
- `send_command()` buffers for `current_tick + 2` (was +1) in online mode
- `commit_tick_commands()` marks tick committed (`_committed_ticks`), sends definitive re-flush via `_send_definitive_flush()`
- `flush_commands_for_tick()` early-returns for committed ticks
- New state cleaned in `_begin_match()` and `_reset_to_offline()`
- Offline mode unchanged (still +1 via submit_command)

### 2. Debug Logging Cleanup — DONE
- Removed `compute_checksum_debug()` from `core/simulation.gd`
- Removed all `[DESYNC-*]`, `[CS-DETAIL]`, `[POST-STEP]`, `[CMD-TRACE]` prints from game_manager.gd and network_manager.gd
- Kept `push_error("DESYNC at tick...")` in network_manager.gd (production desync detection)

### 3. Cloudflare Pages Deployment — LIVE
- Project: `castlefight` → https://castlefight.pages.dev (working)
- WASM: 36MB → 6.2MB brotli compressed
- PCK: 11MB → 9.8MB brotli compressed
- `build.sh` does full export → compress → deploy in one command
- `export/web/_headers` serves `Content-Encoding: br` for WASM/PCK
- Wrangler authenticated as neilalvin.villegas@gmail.com
- Python HTTP servers killed (no longer needed for game serving)
- Tunnel config updated: removed `play.castlefight.net`, kept only `nakama.castlefight.net`

### 4. Custom domain `play.castlefight.net` — PARTIALLY DONE
- Added in Cloudflare Pages dashboard by user
- **Still returns 404** — old tunnel DNS A record overrides the Pages CNAME
- **Fix needed**: In Cloudflare Dashboard → DNS → Records, delete the old `play` A/CNAME record (from tunnel), let Pages create its own
- No rebuild needed, purely a DNS change

## What Is NOT Working

### Web Audio — BROKEN (no sound in browser)
**Symptoms**: "Error: Failed to create PositionWorklet" in console, zero audio output.

**Approaches tried (all failed)**:
1. AudioWorklet mock with `Promise.resolve()` → fake AudioWorkletNode broke audio graph (`connect()` returned wrong type)
2. AudioWorklet mock with `Promise.reject()` → Godot logged error, unhandled promise rejection, didn't fall back to ScriptProcessorNode
3. No mock at all, only AudioContext resume-on-gesture → PositionWorklet errors persist, still no audio

**Current `export/web/custom_shell.html` state**: All AudioWorklet mocking removed. Only has AudioContext resume via document event listeners (click/touch/keydown/pointerdown). This is the cleanest state to debug from.

**Next steps**:
- Add `console.log('AudioContext state:', ctx.state)` to diagnose if context actually resumes
- Check Godot 4.6.2 issue tracker — this is a known engine bug (github.com/godotengine/godot/issues/107390)
- Try building a custom Godot web export template with AudioWorklet disabled at C++ level
- Check if `sfx.gd` audio players are actually connected and getting signal — add GDScript-side diagnostics
- Audio works fine in native (desktop) Godot — this is web-export-specific

## Uncommitted Changes
173 files modified across repo (includes other agents' work). Key A1 changes since last commit (268c84b):
- `autoload/network_manager.gd` — desync fix + debug cleanup
- `autoload/game_manager.gd` — debug logging cleanup  
- `core/simulation.gd` — removed compute_checksum_debug()
- `export/web/custom_shell.html` — audio attempts, currently clean
- `export/web/_headers` — new: Cloudflare br encoding
- `build.sh` — new: export/compress/deploy script
- `~/.cloudflared/config.yml` — removed play.castlefight.net tunnel entry

## Infrastructure Map

| Service | URL | Backend | Status |
|---------|-----|---------|--------|
| Game (Pages) | castlefight.pages.dev | Cloudflare CDN | ✅ Working |
| Game (custom domain) | play.castlefight.net | Should be Pages | ❌ DNS needs fix |
| Nakama (tunnel) | nakama.castlefight.net | localhost:7350 | ✅ Working |
| Tunnel ID | 6a4431b7 | ~/.cloudflared/config.yml | ✅ Updated |

## Architecture Notes
- Autoload order: EventBus → GameManager → NetworkManager → ... → Nakama (plugin). GameManager._process runs BEFORE NakamaSocketAdapter._process — this caused the desync race.
- Lockstep: both clients exchange COMMANDS per tick via Nakama relay. Checksums every 50 ticks.
- 331 simulation tests passing (`godot --headless -s tests/test_simulation.gd`)
- Web export: Godot 4.6.2, WASM, custom HTML shell at `export/web/custom_shell.html`
- Audio: 80+ .ogg files, 3-bus system (SFX/Music/UI), sfx.gd skips procedural synthesis on web
