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
	
	# Check why row 9 is blocked for player 1
	print("=== Why is sim row 9 blocked? ===")
	print("grid_cells[1][9]:")
	for col in 11:
		print("  col %d: %d" % [col, sim.grid_cells[1][9][col]])
	
	# Check castle footprint overlap
	var cfp = sim._castle_grid_footprint(1)
	print("Castle footprint team 1: rows %d-%d, cols %d-%d" % [cfp[0], cfp[1], cfp[2], cfp[3]])
	
	# Check would_block_path
	print("_would_block_path for row 9, col 5: %s" % str(sim._would_block_path(1, 5, 9, 1, 1)))
	print("_would_block_path for row 8, col 5: %s" % str(sim._would_block_path(1, 5, 8, 1, 1)))
	
	# Check BOTH teams row 9
	print("\nTeam 0 grid_cells[0][9]:")
	for col in 11:
		print("  col %d: %d" % [col, sim.grid_cells[0][9][col]])
	
	var cfp0 = sim._castle_grid_footprint(0)
	print("Castle footprint team 0: rows %d-%d, cols %d-%d" % [cfp0[0], cfp0[1], cfp0[2], cfp0[3]])
	
	quit()
