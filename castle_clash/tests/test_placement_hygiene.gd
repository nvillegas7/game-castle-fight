## T-QA1: placement-test hygiene — static gate against DEAD test placements.
## place_building is a silent no-op on invalid coords; BUG-51 proved several
## team-1 test placements sat inside the 7x4 castle footprint for months with
## no assertion noticing. Rather than patching 114 inline call sites, this
## suite extracts every LITERAL `Command.place_building(pid, &"id", x, y)`
## from tests/*.gd and validates it against a fresh Simulation via
## can_place_building. A fresh-board failure is a statically dead placement
## (earlier placements in a scenario only ADD occupancy — they can't make an
## invalid placement valid). Deliberate rejection-tests opt out with a
## `# hygiene:allow-invalid` comment on the same line.
## Usage: godot --headless --path castle_clash -s tests/test_placement_hygiene.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	await process_frame
	print("\n=== PLACEMENT HYGIENE (T-QA1) ===\n")
	var buildings: Array = []
	var dir := DirAccess.open("res://data/buildings/")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var bd = load("res://data/buildings/" + fname)
				if bd:
					buildings.append(bd)
			fname = dir.get_next()

	# GEOMETRY-ONLY check: neutralize requires_building — prerequisites are
	# legitimately satisfied by earlier placements in a scenario (they'd
	# false-positive here), while occupancy/bounds violations can only get
	# WORSE as a scenario progresses. Safe: this process is standalone, the
	# mutated Resource cache dies with it.
	for bd in buildings:
		bd.requires_building = &""
	var sim := Simulation.new()
	sim.register_buildings(buildings)
	sim.initialize(1, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	# Gold is irrelevant to geometry: make everything affordable so the check
	# isolates bounds/footprint/occupancy, not economy.
	sim.players[0].gold = FP.from_int(99999)
	sim.players[1].gold = FP.from_int(99999)

	var re := RegEx.new()
	re.compile("Command\\.place_building\\(\\s*(\\d)\\s*,\\s*&\"([a-z_]+)\"\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)")
	var checked: int = 0
	var skipped_dynamic: int = 0
	var whitelisted: int = 0
	var dead: Array = []

	var tdir := DirAccess.open("res://tests/")
	tdir.list_dir_begin()
	var tf := tdir.get_next()
	while tf != "":
		if tf.ends_with(".gd") and tf != "test_placement_hygiene.gd":
			var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/" + tf).split("\n")
			for i in lines.size():
				var line: String = lines[i]
				if not line.contains("place_building("):
					continue
				var m := re.search(line)
				if m == null:
					if line.contains("Command.place_building("):
						skipped_dynamic += 1
					continue
				if line.contains("hygiene:allow-invalid"):
					whitelisted += 1
					continue
				checked += 1
				var pid: int = int(m.get_string(1))
				var bid := StringName(m.get_string(2))
				if not sim.building_registry.has(bid):
					dead.append("%s:%d — unknown building id &\"%s\"" % [tf, i + 1, bid])
					continue
				if not sim.can_place_building(pid, bid, int(m.get_string(3)), int(m.get_string(4))):
					dead.append("%s:%d — p%d %s at (%s,%s) invalid on a fresh board" %
						[tf, i + 1, pid, bid, m.get_string(3), m.get_string(4)])
		tf = tdir.get_next()

	print("  literal placements checked: %d (dynamic skipped: %d, whitelisted: %d)"
		% [checked, skipped_dynamic, whitelisted])
	if dead.is_empty():
		_pass += 1
		print("  PASS: no statically dead test placements")
	else:
		_fail += 1
		print("  FAIL: %d dead placements (silent no-ops weakening their tests):" % dead.size())
		for d in dead:
			print("    " + d)
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
