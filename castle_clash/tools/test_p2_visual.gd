extends SceneTree

func _init():
	# Simulate what happens in multiplayer for player 2
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
	
	print("=== TERRAIN LAYOUT ===")
	print("ENEMY_ZONE_Y=55 (team 1 build zone top)")
	print("PLAYER_ZONE_Y=695 (team 0 build zone top)")
	print("CASTLE_0_Y=920 (blue castle, bottom)")
	print("CASTLE_1_Y=70 (red castle, top)")
	print("BuildZone0 position: y=695 (bottom of screen)")
	print("BuildZone1 position: y=55 (top of screen)")
	print("")
	
	print("=== GRID CELLS FOR BOTH PLAYERS ===")
	for pi in 2:
		print("Player %d grid_cells (C=castle, .=empty):" % pi)
		for row in 10:
			var s := "  row%d: " % row
			for col in 11:
				var v = sim.grid_cells[pi][row][col]
				s += "C" if v == -2 else ("." if v == -1 else "B")
			s += "  (sim y=%d)" % (695 + row * 28 if pi == 0 else 55 + row * 28)
			print(s)
		print("")
	
	print("=== PERSPECTIVE FLIP ANALYSIS ===")
	print("In multiplayer, player 2 (local_player_id=1, team 1):")
	print("  _apply_perspective_flip() swaps grid overlay player_index:")
	print("    grid_overlay_0 (BuildZone0, y=695) gets player_index=1")
	print("    grid_overlay_1 (BuildZone1, y=55) gets player_index=0")
	print("")
	print("  grid_overlay_0 reads grid_cells[1] (team 1's data)")
	print("  grid_overlay_0 draws at BuildZone0 (y=695, bottom of screen)")
	print("")
	
	print("=== THE PROBLEM ===")
	print("grid_cells[1] has castle at rows 0-1.")
	print("BuildZone0 draws row 0 at the TOP of the zone (y=695).")
	print("So castle markers appear at the TOP of the zone.")
	print("For flipped player, TOP = FRONT (combat side).")
	print("Castle should appear at BOTTOM (back/castle side).")
	print("")
	print("_visual_row should invert: sim row 0 → visual row 9 (bottom)")
	print("But _draw_occupied_cells iterates sim rows and draws them.")
	print("")
	
	# Simulate what _draw_occupied_cells does
	print("=== SIMULATING _draw_occupied_cells for grid_overlay_0 (player_index=1) ===")
	var grid = sim.grid_cells[1]
	for row in 10:
		# This is what _visual_row does with player_index==1
		var visual_row_inv: int = (10 - 1) - row  # inverted
		for col in 11:
			if grid[row][col] != -1:
				print("  sim_row=%d col=%d → visual_row=%d (inverted) vs visual_row=%d (NOT inverted)" % [row, col, visual_row_inv, row])
	
	print("")
	print("=== WALL PLACEMENT TEST (1x1) ===")
	print("Player clicks at visual positions in BuildZone0:")
	for visual_gy in 10:
		# Inversion: sim_gy = (GRID_ROWS - size_y) - visual_gy = 9 - visual_gy
		var sim_gy: int = 9 - visual_gy
		var can: bool = sim.can_place_building(1, &"wall", 5, sim_gy)
		var screen_y: int = 695 + visual_gy * 28
		print("  screen_y=%d visual_row=%d → sim_row=%d → %s" % [screen_y, visual_gy, sim_gy, "BUILD" if can else "BLOCKED"])
	
	print("")
	print("=== WHAT THE USER SEES (occupied cell overlay) ===")
	print("With _visual_row inversion (player_index==1):")
	for row in 10:
		var has_castle: bool = false
		for col in 11:
			if grid[row][col] == -2:
				has_castle = true
				break
		if has_castle:
			var vr: int = 9 - row
			print("  Castle at sim_row %d → draws at visual_row %d (y=%d)" % [row, vr, 695 + vr * 28])
	
	print("")
	print("=== CHECKING: Does _visual_row actually run? ===")
	print("Condition: player_index == 1")
	print("After _apply_perspective_flip, grid_overlay_0.player_index = 1")
	print("So condition is TRUE → inversion applies")
	print("")
	print("BUT WAIT: Does _draw_occupied_cells even get called?")
	print("_draw() calls both _draw_grid_lines() and _draw_occupied_cells()")
	print("_draw_grid_lines checks: if selected_building == null: return")
	print("So occupied cells only draw when a building is selected!")
	print("")
	print("=== CHECKING _draw() flow ===")
	
	quit()
