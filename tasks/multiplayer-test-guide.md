# Local Multiplayer Test Guide
> **Task**: T-032 | **Author**: A1 | **Updated**: 2026-04-11

## Prerequisites

- Docker Desktop installed and running
- Godot 4.6.2 with Web export templates installed
- Python 3 (for local web server with CORS headers)

## Step 1: Start Nakama Server

```bash
cd server
docker compose up -d
```

First run pulls images (~150MB Nakama, ~30MB Postgres) and auto-runs database migrations.

Verify:
- API health: `curl http://localhost:7350/healthcheck` → should return `{}`
- Admin console: http://localhost:7351 (admin / password)

Ports: 7350 (HTTP/WebSocket API), 7351 (Console), 7349 (gRPC)

> **Apple Silicon note**: The Nakama image is AMD64 — Docker runs it via Rosetta emulation. The platform mismatch warning is expected and harmless.

## Step 2: Export Web Build

```bash
cd castle_clash
godot --headless --export-release "Web" export/web/index.html
```

Output: ~38MB WASM + JS + HTML in `castle_clash/export/web/`.

## Step 3: Serve with CORS Headers

Godot 4 requires Cross-Origin-Isolation headers for `SharedArrayBuffer` threading:

```bash
cd castle_clash/export/web
python3 serve.py 8090
```

This custom server sends the required headers:
- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

> **Do NOT use** `python3 -m http.server` — it lacks these headers and Godot will fail to load.

## Step 4: Open Two Browser Instances

**IMPORTANT**: Both tabs on the same browser share IndexedDB → same Nakama device_id → same user account. Matchmaking requires 2 different users.

**Use one of these approaches:**
- **Chrome + Chrome Incognito** (Cmd+Shift+N) — separate IndexedDB
- **Chrome + Firefox** — completely separate storage
- **Chrome + Safari** — completely separate storage

Open `http://localhost:8090` in both browser instances.

## Step 5: Test Matchmaking

1. Wait for both instances to load WASM (~5 seconds)
2. In both: select faction (Kingdom is default)
3. **Tab 1**: click **PLAY ONLINE** → "Connecting..." → "Finding match..."
4. **Tab 2**: click **PLAY ONLINE** → "Connecting..." → "Match found!"
5. Match begins automatically when both players signal ready

## Step 6: Verification Checklist

| Check | How to Verify | Pass? |
|-------|---------------|-------|
| Both tabs connect to Nakama | Status shows "Connected!" | |
| Matchmaking pairs the tabs | "Match found!" appears in both | |
| Building placement syncs | Place a building in Tab 1, see it in Tab 2 | |
| Units spawn identically | Same units appear on both screens at same time | |
| Combat plays out identically | Units fight the same way in both tabs | |
| Match end matches | Winner/loser is the same on both screens | |
| No desync warnings | No "DESYNC" errors in browser console (F12) | |

## Architecture Notes

- **Lockstep relay**: Both clients send commands each tick via Nakama WebSocket. Simulation only advances when both sides have submitted.
- **Deterministic**: All game logic uses FP Q16.16 fixed-point math. No floats in simulation.
- **Checksum**: Every 50 ticks, clients exchange checksums. Mismatch triggers `desync_detected` signal.
- **Command types**: PLACE_BUILDING, SELL_BUILDING, USE_ABILITY, ACTIVATE_BUILDING — all serialized via `network_manager.gd`.
- **Player assignment**: Lexicographic sort of session IDs determines player 0 vs player 1.
- **Device auth**: Auto-creates anonymous accounts. Device ID stored in `user://device_id.cfg` (IndexedDB in browser).

### Connection Flow
1. UI: "PLAY ONLINE" → `NetworkManager.connect_to_server()`
2. Auth: Device ID auth via Nakama REST API (auto-creates account)
3. WebSocket: Opens persistent connection for real-time relay
4. Matchmaking: `add_matchmaker_async("*", 2, 2)` — exactly 2 players
5. Lobby: Players exchange faction selections, both signal ready
6. Match Start: Player 0 sends config (seed, factions), both init simulation
7. Lockstep: Each tick, both send commands → wait for both → advance

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Nakama restart loop | First run needs migrations — docker-compose entrypoint handles this. Check: `docker compose logs nakama` |
| "Nakama addon not found" | Verify `Nakama` autoload in `project.godot` (line 28) |
| Connection refused | Check Docker: `docker compose ps` — Nakama should be on port 7350 |
| Stuck on "Finding match..." | Both tabs must click PLAY ONLINE. Need 2 different users (see Step 4) |
| Same user in both tabs | Use different browsers or incognito mode — same browser shares device_id |
| Desync detected | Check browser console for tick number. Indicates non-determinism in simulation |
| SharedArrayBuffer error | Use `serve.py` instead of plain `python3 -m http.server` |
| Port 8080 in use | Use a different port: `python3 serve.py 8090` |

## Known Limitations

- No reconnection handling — disconnect causes match to stall (5s timeout → error)
- No spectator mode
- No account system (device auth only)
- No lobby UI — matchmaking is automatic (first 2 players get paired)
- Same-browser tabs share device_id via IndexedDB

## Shutdown

```bash
cd server
docker compose down      # Stop containers
docker compose down -v   # Also remove database volume
```
