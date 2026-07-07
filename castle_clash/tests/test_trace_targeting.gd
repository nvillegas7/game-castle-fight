## Minimal trace: why do units near the castle have target_id=-1?
extends SceneTree

func _init() -> void:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(500)
	sim.step([Command.place_building(0, &"barracks", 0, 0)])

	# List castle entities
	print("=== Castle entities ===")
	for e in sim.entities:
		if e.type == "castle":
			print("  Castle id=%d team=%d y=%d hp=%d" % [e.id, e.team, FP.to_int(e.y), FP.to_int(e.hp)])

	# Run and trace unit targeting every 100 ticks
	for tick_i in 1500:
		sim.step([])
		if sim.tick % 100 == 0:
			print("\n=== Tick %d ===" % sim.tick)
			for e in sim.entities:
				if e.type != "unit" or e.team != 0 or FP.lte(e.hp, FP.ZERO):
					continue
				var py: int = FP.to_int(e.y)
				print("  Unit #%d y=%d state=%d target=%d moving=%s" % [
					e.id, py, e.get("state", -1), e.target_id, e.get("is_moving", false)])

	# Final state
	print("\n=== FINAL (tick %d) ===" % sim.tick)
	print("Castle 1 HP: %d" % FP.to_int(sim.castles[1].hp))
	for e in sim.entities:
		if e.type != "unit" or e.team != 0 or FP.lte(e.hp, FP.ZERO):
			continue
		var py: int = FP.to_int(e.y)
		var tgt_type: String = "none"
		if e.target_id != -1:
			for other in sim.entities:
				if other.id == e.target_id:
					tgt_type = other.type
					break
		print("  Unit #%d y=%d state=%d target=%d (%s) moving=%s" % [
			e.id, py, e.get("state", -1), e.target_id, tgt_type, e.get("is_moving", false)])
	quit()

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
