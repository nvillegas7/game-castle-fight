## 2.5-core: O(1) entity lookup. _find_entity_by_id was a LINEAR scan called
## per unit per tick from targeting/combat (simulation.gd ~1361/1487/1910/…)
## → O(units × entities) every tick. This suite pins the public get_entity
## facade + proves the id→entity index stays correct across placement, sell,
## spawning and the death sweep, and that adding it perturbs NOTHING
## (same-seed checksums identical — the determinism golden also guards this).
## Run: godot --headless --path castle_clash -s tests/test_sim_facade.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _all_buildings: Array = []


func _init() -> void:
	print("\n=== SIM FACADE (2.5-core) ===\n")
	_load_buildings()
	# Construction gate — the whole point of the package. RED until the sim
	# grows the public method.
	var src: String = FileAccess.get_file_as_string("res://core/simulation.gd")
	var has_get: bool = src.contains("func get_entity(")
	_ok("Simulation.get_entity() exists", has_get, "no public O(1) lookup")
	# get_entity must consult the index FIRST (O(1) fast path); a scan is only
	# permitted as a self-heal fallback (regression guard: an edit that drops
	# the index and pure-scans silently restores O(n) per lookup).
	var g0: int = src.find("func get_entity(")
	var g_body: String = src.substr(g0, 260) if g0 >= 0 else ""
	var idx_before_scan: bool = g_body.find("_entity_index.get") >= 0 \
		and (g_body.find("_entity_index.get") < g_body.find("for entity in entities") \
			or g_body.find("for entity in entities") < 0)
	_ok("get_entity consults _entity_index before any scan", idx_before_scan,
		"index fast-path missing or a scan runs first")
	# The retained internal name must delegate, not keep its own scan.
	var f0: int = src.find("func _find_entity_by_id")
	var f_body: String = src.substr(f0, 160) if f0 >= 0 else ""
	_ok("_find_entity_by_id delegates to get_entity (no private scan)",
		f0 >= 0 and f_body.contains("get_entity(") and not f_body.contains("for entity in entities"),
		"still contains its own `for entity in entities` scan")
	if has_get:
		_test_lookup_matches_scan()
		_test_removal_evicts()
		_test_index_is_determinism_neutral()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: " + name)
	else:
		_fail += 1
		print("  FAIL: " + name + ("" if detail.is_empty() else " — " + detail))


func _load_buildings() -> void:
	var dir := DirAccess.open("res://data/buildings/")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var bd = load("res://data/buildings/" + f)
			if bd:
				_all_buildings.append(bd)
		f = dir.get_next()


func _fresh_sim(seed_val: int) -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_all_buildings)
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(99999)
	sim.players[1].gold = FP.from_int(99999)
	return sim


## Linear reference — the exact loop that used to live in _find_entity_by_id.
func _scan(sim: Simulation, id: int):
	for e in sim.entities:
		if e.id == id:
			return e
	return null


## get_entity must equal the linear scan for EVERY id (present or absent).
func _test_lookup_matches_scan() -> void:
	print("[get_entity == linear scan across a live match]")
	var sim := _fresh_sim(4242)
	# Barracks (spawner) both sides so units spawn and fight over time.
	sim.step([Command.place_building(0, &"barracks", 2, 4)])
	sim.step([Command.place_building(1, &"barracks", 2, 4)])
	var mismatches: int = 0
	var max_id_seen: int = 0
	for t in 400:
		sim.step([])
		for e in sim.entities:
			max_id_seen = maxi(max_id_seen, e.id)
		if t % 40 == 0:
			# Every live id resolves identically...
			for e in sim.entities:
				if sim.get_entity(e.id) != e:
					mismatches += 1
			# ...and ids never issued / already gone resolve to null.
			if sim.get_entity(max_id_seen + 9999) != null:
				mismatches += 1
	_ok("get_entity matched the scan for all live ids + absent ids", mismatches == 0,
		"%d mismatches over 400 ticks" % mismatches)
	_ok("match actually produced entities to test", max_id_seen > 2,
		"only %d ids ever seen — spawners never fired" % max_id_seen)


## Sold buildings and dead units must be EVICTED (the classic index bug is a
## stale entry surviving removal).
func _test_removal_evicts() -> void:
	print("[Index evicts on sell + death sweep]")
	var sim := _fresh_sim(77)
	sim.step([Command.place_building(0, &"barracks", 2, 4)])
	var bid: int = -1
	for e in sim.entities:
		if e.get("building_type", &"") == &"barracks":
			bid = e.id
			break
	_ok("placed barracks resolves via get_entity", bid >= 0 and sim.get_entity(bid) != null)
	sim.step([Command.sell_building(0, bid)])
	_ok("sold building evicted from the index", sim.get_entity(bid) == null,
		"stale entry survived sell")
	# Run long combat, then verify every id the index still returns is really
	# present, and everything present is indexed (no leak either direction).
	sim.step([Command.place_building(1, &"barracks", 2, 4)])
	for t in 600:
		sim.step([])
	var leaked: int = 0
	for e in sim.entities:
		if sim.get_entity(e.id) != e:
			leaked += 1
	# Probe a spread of ids; any that the index returns must be a live entity.
	var ghosts: int = 0
	for id in range(0, 400):
		var got = sim.get_entity(id)
		if got != null and _scan(sim, id) == null:
			ghosts += 1
	_ok("no live entity missing from the index after 600 combat ticks", leaked == 0,
		"%d live entities not indexed" % leaked)
	_ok("no ghost ids after the death sweep", ghosts == 0,
		"%d dead ids still resolve" % ghosts)


## Adding the index must not change simulation outcomes — same seed, same
## checksum trajectory (the replay golden is the stronger guard; this fails
## fast and locally if the index mutates anything).
func _test_index_is_determinism_neutral() -> void:
	print("[Index is determinism-neutral]")
	var a := _fresh_sim(1313)
	var b := _fresh_sim(1313)
	for s in [a, b]:
		s.step([Command.place_building(0, &"barracks", 2, 4)])
		s.step([Command.place_building(1, &"barracks", 2, 4)])
	var diverged: int = -1
	for t in 500:
		a.step([])
		b.step([])
		if a.compute_checksum() != b.compute_checksum():
			diverged = t
			break
	_ok("two same-seed runs stay checksum-identical for 500 ticks", diverged == -1,
		"diverged at tick %d" % diverged)
