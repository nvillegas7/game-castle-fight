## BUG-DESYNC1: verify simulation determinism by running the same scenario twice.
## If checksums match between runs, the sim is deterministic and the desync is
## in game_manager/network_manager (seed or mode_config not synchronized).
## Run: godot --headless --path castle_clash -s tools/verify_determinism.gd
extends SceneTree


func _init() -> void:
	await process_frame
	_run()
	quit(0)


func _load_buildings() -> Array:
	var results := []
	var dir := DirAccess.open("res://data/buildings/")
	if dir == null:
		return results
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var bd = load("res://data/buildings/" + fname)
			if bd:
				results.append(bd)
		fname = dir.get_next()
	return results


func _run_scenario(label: String) -> Array:
	var sim := Simulation.new()
	sim.register_buildings(_load_buildings())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"kingdom", "perk": &""},
	])
	# Place buildings (to exercise spawn, combat, RNG)
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 4, 0),
		Command.place_building(1, &"barracks", 4, 4),
	])
	var checksums: Array = []
	for i in 500:
		sim.step([])
		if sim.tick % 50 == 0:
			var cs := sim.compute_checksum()
			checksums.append({"tick": sim.tick, "checksum": cs})
			var rng_s := sim.rng.get_state()
			print("  %s tick %d: checksum=%d rng=[%d,%d,%d,%d] entities=%d" % [
				label, sim.tick, cs, rng_s[0], rng_s[1], rng_s[2], rng_s[3], sim.entities.size()])
	return checksums


func _run() -> void:
	print("\n=== BUG-DESYNC1: Determinism Verification ===\n")
	print("[Run A]")
	var run_a := _run_scenario("A")
	print("\n[Run B]")
	var run_b := _run_scenario("B")

	print("\n[Comparison]")
	var all_match := true
	for i in run_a.size():
		var a: Dictionary = run_a[i]
		var b: Dictionary = run_b[i]
		var match_str: String = "MATCH" if a.checksum == b.checksum else "MISMATCH"
		if a.checksum != b.checksum:
			all_match = false
		print("  tick %d: A=%d B=%d → %s" % [a.tick, a.checksum, b.checksum, match_str])

	print("\nVERDICT: %s" % ("DETERMINISTIC — sim is clean, desync is in game_manager/network layer" if all_match else "NON-DETERMINISTIC — bug is in simulation.gd"))
