## Combat/movement FEEL regression. Logic-level checks on the visual layer's
## speed/timing math — no rendering, runs headless. Grows with each 1C fix.
## Run: godot --headless -s tests/test_combat_feel.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	print("\n=== COMBAT FEEL ===\n")
	_test_walk_cadence()
	_test_ability_activation()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


func _test_walk_cadence() -> void:
	print("[Walk cadence ratio (BUG-40)]")
	# Footman reference speed (4.48 px/tick) → legs at 1.0x, matching ground travel.
	var footman: float = CombatTuning.walk_ratio_for_speed(4.48)
	_ok("footman (4.48 px/tick) -> ~1.0x cadence", is_equal_approx(footman, 1.0),
		"got %f" % footman)
	# Guards against the old bug: baseline 44.8 (px/SEC) gave ratio ~0.10 = foot-skate.
	_ok("not the old ~10%% foot-skate cadence", footman > 0.5,
		"ratio %f looks like the px/sec-baseline bug" % footman)
	# Faster unit cycles legs faster; slower slower; stationary safe.
	_ok("2x speed -> ~2x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(8.96), 2.0),
		"got %f" % CombatTuning.walk_ratio_for_speed(8.96))
	_ok("half speed -> ~0.5x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(2.24), 0.5),
		"got %f" % CombatTuning.walk_ratio_for_speed(2.24))
	_ok("stationary -> 1.0 (no divide-by-zero)", CombatTuning.walk_ratio_for_speed(0.0) == 1.0)


func _test_ability_activation() -> void:
	print("[Ability activation event (1D)]")
	var sim := Simulation.new()
	var buildings: Array = []
	var dir := DirAccess.open("res://data/buildings/")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				var bd = load("res://data/buildings/" + f)
				if bd:
					buildings.append(bd)
			f = dir.get_next()
	sim.register_buildings(buildings)
	sim.initialize(12345, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(1000)
	# War Horn requires a Barracks; place it first.
	sim.step([Command.place_building(0, &"barracks", 0, 0)])
	sim.step([Command.place_building(0, &"war_horn", 4, 0)])
	var wh = null
	for e in sim.entities:
		if e.get("building_type", &"") == &"war_horn":
			wh = e
			break
	_ok("war_horn placed", wh != null, "not found")
	if wh == null:
		return
	wh.ability_mana = wh.ability_max_mana  # fully charge (skip the timed ramp)
	var result = sim.step([Command.activate_building(0, wh.id)])
	var ev = null
	for e in result.events:
		if e.get("type", "") == "ability_activated":
			ev = e
			break
	# The bug: this event was emitted by the sim but game_manager had no dispatch
	# arm for it, so enemy War Horn/Blood Totem activations were invisible. This
	# asserts the sim contract the new arm reads.
	_ok("activation emits ability_activated", ev != null, "no ability_activated event")
	if ev:
		_ok("event carries building_id/team/ability/duration",
			ev.get("building_id", -1) == wh.id and ev.get("team", -99) == 0
			and ev.get("ability", "") == "rally_cry" and ev.get("duration", 0) == 100,
			"got %s" % str(ev))
