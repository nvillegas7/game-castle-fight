## SCENARIO: place a building while ZOOMED IN 2x and panned.
## Repro harness for the reported "placement breaks under zoom" bug: the drag
## aims at the tile's true ON-SCREEN position (what a player's finger sees);
## the assert requires the building to land in that same sim cell.
## A FAIL here is the bug reproduction, captured with screenshots + state.
## Run: godot --path castle_clash -- --scenario place_building_zoomed
extends ScenarioBase

const BUILDING := &"barracks"
const TARGET := Vector2i(2, 4)


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()

	# Zoom to 2x through real wheel events, then pan down (keyboard path —
	# middle-drag pan is dead, see camera.gd repro) so the player's build
	# zone is on screen (camera y 640 -> ~940).
	await zoom(2.0)
	check("zoomed in to 2.0", is_equal_approx(arena.camera.zoom.x, 2.0),
		"zoom=%f" % arena.camera.zoom.x)
	await pan_keys(Vector2(0, 1), 1.0)
	var cam_pos: Vector2 = arena.camera.position
	check("panned down to build zone (cam y in 800..960)",
		cam_pos.y > 800.0 and cam_pos.y <= 960.0, "camera=%s" % str(cam_pos))
	await capture("zoomed_panned")

	# Where the target tile ACTUALLY is on screen under this camera:
	var target_world := tile_world_center(TARGET)
	var target_screen := world_to_screen(target_world)
	# Bug probe: building_grid treats event.position as world coords. Compute
	# the cell the game will derive from this screen position and log the
	# offset so the repro report has a measured error, not just a FAIL.
	var grid := local_grid(arena)
	var raw_local: Vector2 = target_screen - grid.global_position
	var derived_cell := Vector2i(int(floor(raw_local.x / 28.0)), int(floor(raw_local.y / 28.0)))
	var offset_px: Vector2 = raw_local - (target_world - grid.global_position)
	print("[Scenario] tile %s world=%s screen=%s -> game derives grid-local %s (cell %s, expected %s, error %spx / %s cells)" % [
		TARGET, target_world, target_screen, raw_local, derived_cell, TARGET,
		offset_px, offset_px / 28.0])

	var eid: int = await place_building_via_input(BUILDING, TARGET)

	var sim = GameManager.simulation
	check("tap-target cell (%d,%d) == placed cell (zoom 2x)" % [TARGET.x, TARGET.y], eid >= 0,
		"nothing placed at target; derived cell would be %s (offset %s cells)" % [
			str(derived_cell), str(offset_px / 28.0)])
	if eid >= 0:
		var ent = sim.get_entity(eid)
		check("building origin cell == drag target cell",
			ent != null and ent.grid_x == TARGET.x and ent.grid_y == TARGET.y,
			"placed at (%s,%s), targeted (%d,%d)" % [
				str(ent.grid_x) if ent else "?", str(ent.grid_y) if ent else "?",
				TARGET.x, TARGET.y])
	else:
		# Did the building land somewhere else entirely?
		var stray: String = "none"
		for e in sim.entities:
			if e.type == "building" and e.get("building_type", &"") == BUILDING and e.team == 0:
				stray = "(%d,%d)" % [e.grid_x, e.grid_y]
		print("[Scenario] stray %s placement under zoom: %s" % [BUILDING, stray])

	await capture("after_place_zoomed")
