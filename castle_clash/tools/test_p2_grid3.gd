extends SceneTree

func _init():
	var sim = Simulation.new()
	for fname in ["kingdom", "horde"]:
		var faction = load("res://data/factions/%s.tres" % fname)
		if faction:
			sim.register_buildings(faction.buildings)
	var player_data := [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"kingdom", "perk": &""},
	]
	sim.initialize(12345, player_data, {"skip_prep": true})
	
	# Test every row x col for player 1
	print("=== Full can_place_building grid for player 1 (barracks 1x1) ===")
	for row in 10:
		var row_str := "row %d: " % row
		for col in 11:
			var can: bool = sim.can_place_building(1, &"barracks", col, row)
			row_str += ("." if can else "X")
		print(row_str)
	
	# Check barracks size
	var bd = sim.building_registry.get(&"barracks")
	if bd:
		print("\nBarracks grid_size: %s" % str(bd.grid_size))
	
	quit()
