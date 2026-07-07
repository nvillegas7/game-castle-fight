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
	
	print("=== T-085 Player 2 Grid Placement Test ===")
	
	# Test all building sizes
	var test_buildings := [&"barracks", &"wall", &"gold_mine", &"guard_tower"]
	for btype in test_buildings:
		var bd = sim.building_registry.get(btype)
		if not bd:
			continue
		var sz = bd.grid_size
		print("\n%s (size %dx%d):" % [btype, sz.x, sz.y])
		
		# Sim placement grid for player 1
		print("  Sim rows (can_place at col 3):")
		for row in 10:
			var can: bool = sim.can_place_building(1, btype, 3, row)
			if can:
				print("    sim_row %d: CAN BUILD" % row)
		
		# Visual→sim mapping with inversion
		var max_gy: int = 10 - sz.y
		print("  Visual→Sim (inversion formula: sim = %d - visual):" % max_gy)
		var all_ok := true
		for vr in range(0, max_gy + 1):
			var sr: int = max_gy - vr
			var can: bool = sim.can_place_building(1, btype, 3, sr)
			var status: String = "CAN BUILD" if can else "BLOCKED"
			# Visual row 0 = top of zone (front for flipped player) → should be buildable
			# Visual row max = bottom of zone (near castle) → should be blocked
			var expected_ok: bool = true
			if sr <= 1:  # Castle rows
				expected_ok = false
			if sr + sz.y > 10:  # OOB
				expected_ok = false
			var match_str: String = "OK" if (can == expected_ok) else "MISMATCH!"
			if can != expected_ok:
				all_ok = false
			print("    visual %d → sim %d → %s [%s]" % [vr, sr, status, match_str])
		
		if all_ok:
			print("  RESULT: ALL CORRECT")
		else:
			print("  RESULT: HAS MISMATCHES")
	
	# Verify ghost drawing: sim_row back to visual_row
	print("\n=== Ghost Drawing Verification (2x2 barracks) ===")
	var sz_y: int = 2
	for vr in range(0, 10 - sz_y + 1):
		var sr: int = (10 - sz_y) - vr
		var back_to_visual: int = (10 - sz_y) - sr
		var match_str: String = "OK" if back_to_visual == vr else "OFF BY %d" % (back_to_visual - vr)
		print("  visual %d → sim %d → ghost_visual %d [%s]" % [vr, sr, back_to_visual, match_str])
	
	print("\n=== Player 0 (blue) for comparison ===")
	print("Barracks (2x2) sim rows for player 0:")
	for row in 10:
		var can: bool = sim.can_place_building(0, &"barracks", 3, row)
		if not can:
			print("  sim_row %d: BLOCKED" % row)
	
	print("\n=== DONE ===")
	quit()
