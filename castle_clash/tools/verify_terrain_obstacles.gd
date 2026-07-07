## T-074 smoke test: terrain obstacle architecture.
## Run: godot --headless --path castle_clash -s tools/verify_terrain_obstacles.gd
##
## This is an A5 engineering verification script, NOT a permanent regression test.
## It exercises the new place/remove API, flow field rebuild, targeting skip, and
## flying pass-through. Can be deleted after A4 adds permanent tests to test_simulation.gd.
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _failures: Array = []


func _init() -> void:
	await process_frame
	_run()
	_print_report()
	quit(1 if _fail > 0 else 0)


func _assert(cond: bool, desc: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % desc)
	else:
		_fail += 1
		_failures.append(desc)
		print("  FAIL: %s" % desc)


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


func _fresh_sim() -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	return sim


func _run() -> void:
	print("\n=== T-074 Terrain Obstacle Smoke Test ===\n")

	_scenario_combat_place_remove()
	_scenario_build_place_remove()
	_scenario_blocks_building_placement()
	_scenario_flow_field_rebuild()
	_scenario_non_targetable()
	_scenario_ground_collision()
	_scenario_flying_passes_through_combat()
	_scenario_flying_passes_through_build()
	_scenario_flying_still_collides_with_building()


# --- Scenario 1: combat zone place/remove round-trip ---
func _scenario_combat_place_remove() -> void:
	print("[1] Combat zone place/remove")
	var sim := _fresh_sim()

	_assert(not sim.is_terrain_obstacle_combat(5, 6), "cell 5,6 initially empty")
	_assert(sim.place_terrain_obstacle_combat(5, 6), "place returns true")
	_assert(sim.combat_grid[6][5] == sim.TERRAIN_OBSTACLE_MARKER, "marker stored")
	_assert(sim.is_terrain_obstacle_combat(5, 6), "is_terrain_obstacle_combat == true")

	# Double-place on occupied cell → fail
	_assert(not sim.place_terrain_obstacle_combat(5, 6), "double-place rejected")

	_assert(sim.remove_terrain_obstacle_combat(5, 6), "remove returns true")
	_assert(sim.combat_grid[6][5] == -1, "cell cleared")
	_assert(not sim.is_terrain_obstacle_combat(5, 6), "no longer an obstacle")
	_assert(not sim.remove_terrain_obstacle_combat(5, 6), "double-remove rejected")

	# Out of bounds
	_assert(not sim.place_terrain_obstacle_combat(-1, 0), "OOB col rejected")
	_assert(not sim.place_terrain_obstacle_combat(0, 99), "OOB row rejected")


# --- Scenario 2: build zone place/remove round-trip ---
func _scenario_build_place_remove() -> void:
	print("[2] Build zone place/remove")
	var sim := _fresh_sim()

	# Use a mid-zone cell to avoid castle footprint (which marks -2 in some rows)
	var gx := 3
	var gy := 4
	_assert(not sim.is_terrain_obstacle_build(0, gx, gy), "cell empty initially")
	_assert(sim.place_terrain_obstacle_build(0, gx, gy), "place returns true")
	_assert(sim.grid_cells[0][gy][gx] == sim.TERRAIN_OBSTACLE_MARKER, "marker stored")
	_assert(sim.is_terrain_obstacle_build(0, gx, gy), "is_terrain_obstacle_build == true")
	_assert(not sim.place_terrain_obstacle_build(0, gx, gy), "double-place rejected")

	_assert(sim.remove_terrain_obstacle_build(0, gx, gy), "remove returns true")
	_assert(sim.grid_cells[0][gy][gx] == -1, "cell cleared")

	# Invalid player_index
	_assert(not sim.place_terrain_obstacle_build(99, gx, gy), "invalid player rejected")


# --- Scenario 3: terrain obstacle blocks building placement ---
func _scenario_blocks_building_placement() -> void:
	print("[3] Terrain obstacle blocks building placement")
	var sim := _fresh_sim()
	sim.players[0].gold = FP.from_int(5000)

	# Place terrain at grid (3, 4) — mid-zone, away from castle
	sim.place_terrain_obstacle_build(0, 3, 4)

	# Try to place a 2x2 building overlapping that cell → should fail
	# barracks is 2x2, placing at (2, 3) covers rows 3-4 cols 2-3, overlapping (3, 4)
	var can := sim.can_place_building(0, &"barracks", 2, 3)
	_assert(not can, "can_place_building rejects overlap with terrain")

	# Placing adjacent (not overlapping) should succeed
	var can_adj := sim.can_place_building(0, &"barracks", 5, 5)
	_assert(can_adj, "can_place_building accepts adjacent cell")


# --- Scenario 4: flow field is rebuilt after place/remove ---
func _scenario_flow_field_rebuild() -> void:
	print("[4] Flow field rebuilds after place/remove")
	var sim := _fresh_sim()

	# Snapshot team 0 flow field before
	var before: Array = sim.flow_fields[0].duplicate()

	# Place a mid-zone terrain obstacle
	sim.place_terrain_obstacle_build(0, 5, 5)
	var idx := 5 * sim.GRID_COLS + 5
	# That cell should now be unreachable in BFS → -1
	_assert(sim.flow_fields[0][idx] == -1, "obstacle cell has no direction after rebuild")

	# Remove and verify it's back to a valid direction or -2 (goal)
	sim.remove_terrain_obstacle_build(0, 5, 5)
	var after_dir: int = sim.flow_fields[0][idx]
	_assert(after_dir != -1, "cell has direction after removal (got %d)" % after_dir)


# --- Scenario 5: terrain obstacles are not targetable ---
func _scenario_non_targetable() -> void:
	print("[5] Terrain obstacles not in entities[] and not targetable")
	var sim := _fresh_sim()

	var entities_before := sim.entities.size()
	sim.place_terrain_obstacle_combat(5, 6)
	sim.place_terrain_obstacle_build(0, 5, 5)
	var entities_after := sim.entities.size()
	_assert(entities_before == entities_after, "entities[] size unchanged after placing obstacles")

	# Verify no entity has the sentinel marker as id/type
	var has_terrain_entity := false
	for e in sim.entities:
		if e.type == "terrain_obstacle":  # must never appear
			has_terrain_entity = true
			break
	_assert(not has_terrain_entity, "no 'terrain_obstacle' entity type exists")


# --- Scenario 6: ground units collide with terrain ---
func _scenario_ground_collision() -> void:
	print("[6] Ground unit blocked by terrain (pixel-space)")
	var sim := _fresh_sim()

	# Place a terrain obstacle in the combat zone at (5, 6).
	# Combat-grid to pixel: x_px = GRID_ORIGIN_X + 5*28 + 14 = 206 + 154 = 360
	#                      y_px = COMBAT_Y + 6*28 + 14 = 345 + 182 = 527
	sim.place_terrain_obstacle_combat(5, 6)
	var obstacle_x_fp := FP.from_int(360)
	var obstacle_y_fp := FP.from_int(527)

	# Call _is_inside_obstacle via a dummy ground unit (role 0)
	var ground_unit := {"role": 0}
	var blocked_ground: bool = sim._is_inside_obstacle(obstacle_x_fp, obstacle_y_fp, ground_unit)
	_assert(blocked_ground, "ground unit is_inside_obstacle returns true at terrain")

	# Default unit (no role dict field) should also be blocked (fallback role=0)
	var blocked_default: bool = sim._is_inside_obstacle(obstacle_x_fp, obstacle_y_fp, {})
	_assert(blocked_default, "default unit blocked by terrain")


# --- Scenario 7: flying unit passes through combat terrain ---
func _scenario_flying_passes_through_combat() -> void:
	print("[7] Flying unit passes through combat terrain")
	var sim := _fresh_sim()
	sim.place_terrain_obstacle_combat(5, 6)

	var flying := {"role": 3}
	var obstacle_x_fp := FP.from_int(360)
	var obstacle_y_fp := FP.from_int(527)
	var blocked: bool = sim._is_inside_obstacle(obstacle_x_fp, obstacle_y_fp, flying)
	_assert(not blocked, "flying unit NOT blocked by combat terrain")


# --- Scenario 8: flying unit passes through build terrain ---
func _scenario_flying_passes_through_build() -> void:
	print("[8] Flying unit passes through build-zone terrain")
	var sim := _fresh_sim()
	sim.place_terrain_obstacle_build(0, 5, 5)

	# Build-zone pixel: GRID_ORIGIN_X + 5*28 + 14 = 360
	#                   zone_y=695 + 5*28 + 14 = 849
	var obstacle_x_fp := FP.from_int(360)
	var obstacle_y_fp := FP.from_int(849)

	var ground := {"role": 0}
	var flying := {"role": 3}
	var blocked_ground: bool = sim._is_inside_obstacle(obstacle_x_fp, obstacle_y_fp, ground)
	var blocked_flying: bool = sim._is_inside_obstacle(obstacle_x_fp, obstacle_y_fp, flying)
	_assert(blocked_ground, "ground unit blocked by build-zone terrain")
	_assert(not blocked_flying, "flying unit NOT blocked by build-zone terrain")


# --- Scenario 9: flying units bypass buildings (per A4 user-directive 2026-04-11) ---
# UPDATED 2026-04-11 (cycle 5): A4's coord log entry says "FLYING UNITS NOW BYPASS
# BUILDINGS (user directive)". Original T-074/T-075 spec said flying should collide
# with buildings; that was overridden. Flying still collides with castle wall.
func _scenario_flying_still_collides_with_building() -> void:
	print("[9] Flying unit bypasses buildings (and ground unit collides)")
	var sim := _fresh_sim()
	sim.players[0].gold = FP.from_int(5000)
	# Place a barracks at (5, 5) — 2x2 building
	sim.step([Command.place_building(0, &"barracks", 5, 5)])

	# Building center pixel: GRID_ORIGIN_X + 5*28 + (2*28)/2 = 206 + 140 + 28 = 374
	#                        zone_y=695 + 5*28 + 28 = 863
	var b_x_fp := FP.from_int(374)
	var b_y_fp := FP.from_int(863)

	var ground := {"role": 0}
	var flying := {"role": 3}
	var blocked_ground: bool = sim._is_inside_obstacle(b_x_fp, b_y_fp, ground)
	var blocked_flying: bool = sim._is_inside_obstacle(b_x_fp, b_y_fp, flying)
	_assert(blocked_ground, "ground unit IS blocked by building interior")
	_assert(not blocked_flying, "flying unit BYPASSES building (per user directive)")


func _print_report() -> void:
	print("\n=== T-074 Smoke Test Results ===")
	print("PASS: %d / FAIL: %d" % [_pass, _fail])
	if _fail > 0:
		print("\nFAILURES:")
		for f in _failures:
			print("  - %s" % f)
	else:
		print("ALL PASS")
