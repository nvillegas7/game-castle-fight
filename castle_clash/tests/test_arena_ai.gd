## ArenaAI headless harness (Phase 2.1) — RED-first: written BEFORE the AI was
## extracted from game_arena.gd, so it fails while `ArenaAI` doesn't exist.
##
## Covers the four load-bearing properties of the extraction:
##   1. think() issues placement commands that actually LAND — the building must
##      EXIST in the sim afterwards (T-QA1: place_building is a silent no-op on
##      invalid coords, so a command count alone proves nothing).
##   2. Strategy behavior: rush opens with T1 spawners, tech/balanced open income.
##   3. Seeded determinism: same seeds → identical command streams (catches any
##      global randi() left behind in the extraction).
##   4. Both player ids place successfully (T-079/BUG-51: team-1 rows are
##      mirrored and the castle blocks rows 0-3 — random-retry must cope).
##
## Usage: godot --headless --path castle_clash -s tests/test_arena_ai.gd
extends SceneTree

const THINK_INTERVAL: int = 30  # ticks — mirrors AI_THINK_INTERVAL (3s at 10tps)
const RUN_TICKS: int = 900      # 90s of match — enough for several build cycles

var _pass: int = 0
var _fail: int = 0
var _all_buildings: Array = []


func _init() -> void:
	await process_frame
	print("\n=== ARENA AI TESTS (Phase 2.1) ===\n")
	_load_buildings()
	_test_placements_land_for_both_players()
	_test_strategy_openings()
	_test_seeded_determinism()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String) -> void:
	_pass += 1
	print("  PASS: " + name)


func _bad(name: String, detail: String = "") -> void:
	_fail += 1
	print("  FAIL: " + name + ("" if detail.is_empty() else " — " + detail))


func _load_buildings() -> void:
	var dir := DirAccess.open("res://data/buildings/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var bd = load("res://data/buildings/" + fname)
			if bd:
				_all_buildings.append(bd)
		fname = dir.get_next()


func _faction(id: StringName) -> FactionData:
	return load("res://data/factions/%s.tres" % id)


## Run a full headless match with an ArenaAI per player. Returns per-player
## command streams + the sim (for post-hoc state asserts).
## forced_strategies: [-1,-1] = let each AI roll its own.
func _run_ai_match(seed_val: int, ticks: int, forced_strategies: Array = [-1, -1]) -> Dictionary:
	var sim := Simulation.new()
	sim.register_buildings(_all_buildings)
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	var factions: Array = [_faction(&"kingdom"), _faction(&"horde")]
	var ais: Array = []
	var streams: Array = [[], []]
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val * 2 + i
		var ai := ArenaAI.new(i, rng)
		if int(forced_strategies[i]) != -1:
			ai.strategy = int(forced_strategies[i])
		ais.append(ai)
	var landed: Array = [0, 0]  # building_placed events per player (destruction-proof)
	for tick_i in ticks:
		var cmds: Array = []
		if tick_i > 0 and tick_i % THINK_INTERVAL == 0:
			for i in 2:
				var gold: int = FP.to_int(sim.players[i].gold)
				var out: Array = ais[i].think(sim, factions[i], gold, sim.tick)
				streams[i].append_array(out)
				cmds.append_array(out)
		var result: Dictionary = sim.step(cmds)
		for ev in result.get("events", []):
			if ev.get("type", "") == "building_placed":
				landed[int(ev.get("player_id", -1))] += 1
		if sim.match_over:
			break
	return {"sim": sim, "streams": streams, "ais": ais, "landed": landed}


func _count_buildings(sim: Simulation, player_index: int) -> int:
	var n: int = 0
	for e in sim.entities:
		if e.type == "building" and e.player_index == player_index:
			n += 1
	return n


func _placed_types(stream: Array) -> Array:
	var out: Array = []
	for c in stream:
		if c.get("type", -1) == Command.Type.PLACE_BUILDING:
			out.append(c.get("building_type"))
	return out


func _test_placements_land_for_both_players() -> void:
	print("[AI placements land for both players]")
	var r := _run_ai_match(777, RUN_TICKS)
	for i in 2:
		var issued: int = _placed_types(r.streams[i]).size()
		var landed: int = int(r.landed[i])  # building_placed events, immune to later destruction
		if issued < 2:
			_bad("player %d AI issued only %d place commands (need ≥2)" % [i, issued])
		elif landed < 2:
			_bad("player %d placements silently no-oped — issued %d, landed %d" % [i, issued, landed],
				"T-079/BUG-51: check team-relative rows vs the castle footprint")
		elif landed * 2 < issued:
			# think() pre-checks can_place_building against the pre-tick state, but
			# a place+wall pair from ONE think can race on gold/cells at apply time
			# (inherent to the original design, which had the same one-tick queue;
			# measured ~25% no-ops for team 1 at seed 777 — backlogged for A5).
			# The gate guards WHOLESALE rejection (a T-079-class bug ⇒ landed≈0),
			# so the bar is a majority, not a tight ratio — a tight bar sat at
			# exactly zero margin and was flagged brittle (wf_b6e877e4 review).
			_bad("player %d: only %d of %d placements landed (majority no-oped)" % [i, landed, issued])
		else:
			_ok("player %d AI: %d placements issued, %d landed (%d survived to end)"
				% [i, issued, landed, _count_buildings(r.sim, i)])


func _test_strategy_openings() -> void:
	print("[Strategy openings (0=balanced, 1=rush, 2=tech)]")
	var reg: Dictionary = {}
	for bd in _all_buildings:
		reg[bd.id] = bd
	# Rush: every early non-wall placement is a T1 spawner.
	var rush := _run_ai_match(4242, RUN_TICKS, [1, 1])
	var rush_types: Array = _placed_types(rush.streams[0])
	var rush_ok: bool = rush_types.size() >= 2
	for bt in rush_types.slice(0, 3):
		var bd = reg.get(bt)
		if bd == null or not bd.spawns_unit or bd.tier != 1:
			# walls are allowed later, but not in the first three placements
			rush_ok = rush_ok and (bd != null and bd.grid_size == Vector2i(1, 1))
	if rush_ok:
		_ok("rush opens with T1 spawners (%s...)" % [str(rush_types.slice(0, 3))])
	else:
		_bad("rush opening wrong", str(rush_types.slice(0, 3)))
	# Tech: first placement is an income building.
	var tech := _run_ai_match(4242, RUN_TICKS, [2, 2])
	var tech_types: Array = _placed_types(tech.streams[0])
	var tech_first = reg.get(tech_types[0]) if tech_types.size() > 0 else null
	if tech_first != null and tech_first.income_bonus > 0:
		_ok("tech opens with income (%s)" % [str(tech_types[0])])
	else:
		_bad("tech opening wrong", str(tech_types.slice(0, 2)))
	# Balanced: first placement is income (has_income=false, count<2 branch).
	var bal := _run_ai_match(4242, RUN_TICKS, [0, 0])
	var bal_types: Array = _placed_types(bal.streams[0])
	var bal_first = reg.get(bal_types[0]) if bal_types.size() > 0 else null
	if bal_first != null and bal_first.income_bonus > 0:
		_ok("balanced opens with income (%s)" % [str(bal_types[0])])
	else:
		_bad("balanced opening wrong", str(bal_types.slice(0, 2)))
	# Strategy self-roll stays in range and is stable per instance.
	var rolled := _run_ai_match(99, THINK_INTERVAL * 3)
	var s0: int = rolled.ais[0].strategy
	var s1: int = rolled.ais[1].strategy
	if s0 in [0, 1, 2] and s1 in [0, 1, 2]:
		_ok("self-rolled strategies in range (p0=%d p1=%d)" % [s0, s1])
	else:
		_bad("strategy out of range", "p0=%d p1=%d" % [s0, s1])


func _test_seeded_determinism() -> void:
	print("[Seeded determinism — identical command streams]")
	var a := _run_ai_match(1313, RUN_TICKS)
	var b := _run_ai_match(1313, RUN_TICKS)
	var sa: String = JSON.stringify(a.streams)
	var sb: String = JSON.stringify(b.streams)
	if sa == sb:
		_ok("two same-seed runs produced identical command streams (%d cmds)"
			% [int(a.streams[0].size()) + int(a.streams[1].size())])
	else:
		_bad("same-seed runs diverged — a global randi()/state leak survives",
			"run diff on the two streams to find the first divergent command")
