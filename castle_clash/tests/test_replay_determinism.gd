## Determinism regression (see tasks/design-verification-workflow.md L0).
## Two guarantees, both built on the order-sensitive checksum:
##   1. RE-RUN IDENTITY — the same seed replayed twice yields a byte-identical
##      per-tick checksum trace. This is "determinism is a tested property"
##      (Factorio FFF-60): a non-deterministic sim change fails here immediately,
##      no golden maintenance required.
##   2. GOLDEN TRACE — the seed-12345 trace matches a checked-in baseline, so a
##      change that silently alters sim OUTCOMES (balance, timing, spawns) fails
##      loudly and the golden must be re-blessed on purpose.
##
## Run:      godot --headless --path castle_clash -s tests/test_replay_determinism.gd
## Re-bless: godot --headless --path castle_clash -s tests/test_replay_determinism.gd -- --rebless
extends SceneTree

const GOLDEN_PATH: String = "res://tests/goldens/determinism_seed12345.json"
const GOLDEN_SEED: int = 12345
const SECOND_SEED: int = 777
const STRIDE: int = 25          # record a checksum every 25 ticks
const MAX_TICKS: int = 3000     # deterministic build match resolves well within this

# Same deterministic mirror build order the balance harness uses.
const BUILD_ORDER: Array[StringName] = [
	&"barracks", &"archer_range", &"gold_mine", &"barracks",
	&"priest_temple", &"guard_tower", &"knight_hall", &"siege_workshop",
	&"armory", &"war_horn",
]
const BUILD_INTERVAL: int = 30

var _pass: int = 0
var _fail: int = 0
var _all_buildings: Array = []
var _building_costs: Dictionary = {}


func _init() -> void:
	await process_frame
	_load_buildings()
	print("\n=== REPLAY DETERMINISM ===\n")

	var rebless := "--rebless" in OS.get_cmdline_user_args()
	var run_a := _run_traced(GOLDEN_SEED)

	if rebless:
		_write_golden(run_a)
		print("  RE-BLESSED golden at %s (%d checkpoints, winner=%d, ticks=%d)" % [
			GOLDEN_PATH, run_a.trace.size(), run_a.winner, run_a.ticks])
		quit(0)
		return

	# 1. Re-run identity — same seed twice must match exactly.
	print("[Re-run identity]")
	var run_a2 := _run_traced(GOLDEN_SEED)
	_assert_trace_equal("seed %d replayed twice" % GOLDEN_SEED, run_a.trace, run_a2.trace)
	var run_b := _run_traced(SECOND_SEED)
	var run_b2 := _run_traced(SECOND_SEED)
	_assert_trace_equal("seed %d replayed twice" % SECOND_SEED, run_b.trace, run_b2.trace)
	_assert("different seeds diverge", run_a.trace != run_b.trace,
		"seeds %d and %d produced identical traces — RNG not seeding" % [GOLDEN_SEED, SECOND_SEED])

	# 2. Golden regression.
	print("[Golden trace]")
	_check_golden(run_a)

	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


func _assert_trace_equal(name: String, a: Array, b: Array) -> void:
	if a.size() != b.size():
		_assert(name, false, "trace lengths differ: %d vs %d" % [a.size(), b.size()])
		return
	for i in a.size():
		if a[i] != b[i]:
			_assert(name, false, "diverged at checkpoint %d (tick %d): %d vs %d" % [
				i, i * STRIDE, a[i], b[i]])
			return
	_assert(name, true)


func _check_golden(run: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		_assert("golden present", false,
			"no golden — run once with `-- --rebless` to create %s" % GOLDEN_PATH)
		return
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	var golden = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(golden) != TYPE_DICTIONARY:
		_assert("golden parseable", false, "could not parse %s" % GOLDEN_PATH)
		return
	var g_trace: Array = golden.get("trace", [])
	# Checksums are stored as decimal STRINGS: 64-bit ints exceed JSON double
	# precision (2^53), so int-typed JSON would silently truncate on parse.
	var g_ints: Array = []
	for v in g_trace:
		g_ints.append(int(v))
	_assert("winner matches golden (%d)" % int(golden.get("winner", -99)),
		run.winner == int(golden.get("winner", -99)),
		"winner drift: live=%d golden=%d" % [run.winner, int(golden.get("winner", -99))])
	_assert("tick count matches golden (%d)" % int(golden.get("ticks", -1)),
		run.ticks == int(golden.get("ticks", -1)),
		"match length drift: live=%d golden=%d" % [run.ticks, int(golden.get("ticks", -1))])
	if run.trace.size() != g_ints.size():
		_assert("golden trace length", false,
			"live %d vs golden %d checkpoints — re-bless if intentional" % [run.trace.size(), g_ints.size()])
		return
	for i in run.trace.size():
		if run.trace[i] != g_ints[i]:
			_assert("golden trace", false,
				"diverged at checkpoint %d (tick %d): live=%d golden=%d — re-bless if intentional" % [
					i, i * STRIDE, run.trace[i], g_ints[i]])
			return
	_assert("golden trace (%d checkpoints)" % run.trace.size(), true)


func _write_golden(run: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/goldens"))
	# Store checksums as decimal strings — JSON's double-typed numbers cannot
	# hold 64-bit ints without truncating below the low bits (2^53 limit).
	var trace_strs: Array = []
	for v in run.trace:
		trace_strs.append(str(v))
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"seed": GOLDEN_SEED,
		"stride": STRIDE,
		"winner": run.winner,
		"ticks": run.ticks,
		"trace": trace_strs,
	}, "  "))
	f.close()


## Deterministic mirror-build match; records compute_checksum() every STRIDE ticks
## plus a final checkpoint. Returns {trace, winner, ticks}.
func _run_traced(seed_val: int) -> Dictionary:
	var sim := Simulation.new()
	sim.register_buildings(_all_buildings)
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(0)
	sim.players[1].gold = FP.from_int(0)

	var trace: Array[int] = []
	var p0_idx: int = 0
	var p1_idx: int = 0
	var p0_pos: int = 0
	var p1_pos: int = 0

	for tick_i in MAX_TICKS:
		var cmds: Array = []
		if tick_i > 0 and tick_i % BUILD_INTERVAL == 0:
			if p0_idx < BUILD_ORDER.size():
				var bt: StringName = BUILD_ORDER[p0_idx]
				if FP.to_int(sim.players[0].gold) >= _building_costs.get(bt, 999):
					var gx: int = (p0_pos % 5) * 2
					var gy: int = (p0_pos / 5) * 2
					if sim.can_place_building(0, bt, gx, gy):
						cmds.append(Command.place_building(0, bt, gx, gy))
						p0_idx += 1
					p0_pos = (p0_pos + 1) % 20
			if p1_idx < BUILD_ORDER.size():
				var bt: StringName = BUILD_ORDER[p1_idx]
				if FP.to_int(sim.players[1].gold) >= _building_costs.get(bt, 999):
					var gx: int = (p1_pos % 5) * 2
					var gy: int = 8 - (p1_pos / 5) * 2
					if sim.can_place_building(1, bt, gx, gy):
						cmds.append(Command.place_building(1, bt, gx, gy))
						p1_idx += 1
					p1_pos = (p1_pos + 1) % 20

		sim.step(cmds)
		if sim.tick % STRIDE == 0:
			trace.append(sim.compute_checksum())
		if sim.match_over:
			break

	trace.append(sim.compute_checksum())  # final checkpoint
	var winner: int = sim.winning_team
	if not sim.match_over:
		var hp0: int = FP.to_int(sim.castles[0].hp)
		var hp1: int = FP.to_int(sim.castles[1].hp)
		winner = 0 if hp0 > hp1 else (1 if hp1 > hp0 else -1)
	return {"trace": trace, "winner": winner, "ticks": sim.tick}


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
				_building_costs[bd.id] = bd.gold_cost
		fname = dir.get_next()
