## T-077 Fix 4 measurement: footman march time from spawn to castle attack range.
## Run: godot --headless --path castle_clash -s tools/measure_pacing.gd
##
## Spawns one team-0 footman with no enemies and steps the simulation until the
## footman gets in attack range of castle 1. Reports tick count and seconds.
extends SceneTree


func _init() -> void:
	await process_frame
	_measure()
	quit(0)


func _load_all_building_data() -> Array:
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


func _measure() -> void:
	print("\n=== T-077 Fix 4: March Time Measurement ===\n")

	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	# skip_prep so spawn timers tick from t=0 — we want to measure the spawn+march cycle
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})

	sim.players[0].gold = FP.from_int(500)
	sim.step([Command.place_building(0, &"barracks", 4, 5)])  # mid build zone, central
	var bld_count: int = sim.entities.filter(func(e): return e.type == "building" and e.team == 0).size()
	print("Placed barracks at (4, 5). bld_count=%d. spawn_interval = 130 ticks (post Fix 3)." % bld_count)
	print("prep_phase=%s" % str(sim.prep_phase))

	var spawn_tick := -1
	var first_unit_id := -1
	var attack_tick := -1
	var max_ticks := 800  # 80s, enough for spawn + march

	for i in max_ticks:
		sim.step([])
		# Detect first spawn
		if spawn_tick == -1:
			for e in sim.entities:
				if e.type == "unit" and e.team == 0:
					spawn_tick = sim.tick
					first_unit_id = e.id
					var sx: int = FP.to_int(e.x)
					var sy: int = FP.to_int(e.y)
					print("Tick %d: footman #%d spawned at (%d, %d)" % [sim.tick, e.id, sx, sy])
					break
		# Detect when first unit enters castle attack range
		if attack_tick == -1 and first_unit_id != -1:
			for e in sim.entities:
				if e.id != first_unit_id:
					continue
				if FP.lte(e.hp, FP.ZERO):
					break
				# Castle 1 at y=70. Footman attack_range = 1 cell = 28px FP.
				# Use Y-only distance (matches sim _in_attack_range castle logic)
				var ux: int = FP.to_int(e.x)
				var uy: int = FP.to_int(e.y)
				var y_dist: int = uy - 70
				# Castle 1 has hh=40 in attack range check, so effective y_dist = max(0, |uy-70|-40)
				var eff: int = maxi(0, abs(y_dist) - 40)
				if eff <= 28:
					attack_tick = sim.tick
					print("Tick %d: footman reached castle attack range at (%d, %d). eff_y_dist=%d" % [sim.tick, ux, uy, eff])
					break
		if attack_tick != -1:
			break

	if spawn_tick == -1:
		print("ERROR: no unit spawned in %d ticks" % max_ticks)
		return
	if attack_tick == -1:
		print("ERROR: unit never reached castle in %d ticks" % max_ticks)
		return

	var march_ticks := attack_tick - spawn_tick
	var march_seconds := float(march_ticks) / 10.0

	print("\n--- RESULTS ---")
	print("Spawn tick:       %d (%.1fs)" % [spawn_tick, float(spawn_tick) / 10.0])
	print("Castle reach tick: %d (%.1fs)" % [attack_tick, float(attack_tick) / 10.0])
	print("MARCH TIME:       %d ticks (%.1fs)" % [march_ticks, march_seconds])
	print("")
	print("Target: 25-35s march time per task spec")
	if march_seconds < 20.0:
		print("VERDICT: < 20s — Fix 4 NEEDED. Apply 20%% speed reduction.")
	elif march_seconds <= 35.0:
		print("VERDICT: %.1fs in target range — Fix 4 NOT needed." % march_seconds)
	else:
		print("VERDICT: %.1fs > 35s — units too slow, consider speed BOOST." % march_seconds)
