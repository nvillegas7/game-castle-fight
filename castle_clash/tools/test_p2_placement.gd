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
	
	print("=== WALL (1x1) - Player 2 with inversion ===")
	print("Visual grid (top=front, bottom=back/castle):")
	for vrow in 10:
		var sim_row = 9 - vrow
		var s := "  vrow%d: " % vrow
		for col in 11:
			s += "." if sim.can_place_building(1, &"wall", col, sim_row) else "X"
		print(s)
	
	print("\n=== BARRACKS (2x2) - Player 2 with inversion ===")
	for vrow in 9:
		var sim_row = 8 - vrow
		var s := "  vrow%d: " % vrow
		for col in 10:
			s += "." if sim.can_place_building(1, &"barracks", col, sim_row) else "X"
		print(s)
	
	print("\n=== Castle overlay: sim→visual mapping ===")
	var grid = sim.grid_cells[1]
	for row in 10:
		for col in 11:
			if grid[row][col] == -2:
				print("  Castle sim_row=%d col=%d → visual_row=%d" % [row, col, 9 - row])
				break  # one per row is enough
	
	print("\n=== KEY TEST: What happens WITHOUT inversion? ===")
	print("(This is what the user sees - bug behavior)")
	for vrow in 10:
		var sim_row = vrow  # NO inversion
		var s := "  vrow%d: " % vrow
		for col in 11:
			s += "." if sim.can_place_building(1, &"wall", col, sim_row) else "X"
		print(s)
	
	print("\nIf rows 0-1 cols 1-9 are X, that matches the user's bug exactly.")
	print("This proves the inversion is NOT being applied in the web build.")
	quit()
