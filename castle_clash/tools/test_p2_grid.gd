extends SceneTree

func _init():
	var sim = Simulation.new()
	# Load factions manually
	for fname in ["kingdom", "horde"]:
		var faction = load("res://data/factions/%s.tres" % fname)
		if faction:
			for bd in faction.buildings:
				sim.register_buildings([bd])
	
	var player_data := [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"kingdom", "perk": &""},
	]
	sim.initialize(12345, player_data, {"skip_prep": true})
	
	print("=== Player 2 (team 1) Grid Analysis ===")
	
	print("\nGrid cells[1] (player 2 build zone):")
	for row in 10:
		var row_str := "  row %d: " % row
		for col in 11:
			var val: int = sim.grid_cells[1][row][col]
			if val == -1:
				row_str += "."
			elif val == -2:
				row_str += "C"
			else:
				row_str += str(val).left(1)
		print(row_str)
	
	print("\ncan_place_building for player_id=1, barracks, col=5:")
	for row in 10:
		var can: bool = sim.can_place_building(1, &"barracks", 5, row)
		print("  sim_row %d: %s" % [row, "CAN BUILD" if can else "BLOCKED"])
	
	print("\nT-085 visual→sim mapping (GRID_ROWS=10):")
	for vr in 10:
		var sr: int = 9 - vr
		var can: bool = sim.can_place_building(1, &"barracks", 5, sr)
		print("  visual_row %d → sim_row %d → %s" % [vr, sr, "CAN BUILD" if can else "BLOCKED"])
	
	quit()
