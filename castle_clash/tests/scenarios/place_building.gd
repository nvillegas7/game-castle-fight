## SCENARIO: place a building at default zoom.
## Start match (fixed seed 12345), tap the barracks card, hold-drag-release
## onto tile (2,4) through the real input path, then assert the sim occupancy
## grid cell matches the tile the drag targeted.
## Run: godot --path castle_clash -- --scenario place_building
extends ScenarioBase

const BUILDING := &"barracks"        # 2x2, 50g — affordable from 100 start gold
const TARGET := Vector2i(2, 4)       # top-left cell aimed at (castle is rows 8-9, cols 3-7)


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()
	check("arena camera at default zoom", arena != null and is_equal_approx(arena.camera.zoom.x, 1.0),
		"zoom=%s" % (str(arena.camera.zoom.x) if arena else "no arena"))
	await capture("before_place")

	var gold_before: int = GameManager.get_player_gold(GameManager.local_player_id)
	var eid: int = await place_building_via_input(BUILDING, TARGET)

	var sim = GameManager.simulation
	check("target cell (%d,%d) occupied after drag" % [TARGET.x, TARGET.y], eid >= 0,
		"grid_cells[0][%d][%d]=%d" % [TARGET.y, TARGET.x, sim.grid_cells[0][TARGET.y][TARGET.x]])
	if eid >= 0:
		var ent = sim._find_entity_by_id(eid)
		check("placed entity is a %s" % BUILDING,
			ent != null and ent.get("building_type", &"") == BUILDING,
			"entity=%s" % str(ent.get("building_type", "null") if ent else "null"))
		check("building origin cell == drag target cell",
			ent != null and ent.grid_x == TARGET.x and ent.grid_y == TARGET.y,
			"placed at (%s,%s), targeted (%d,%d)" % [
				str(ent.grid_x) if ent else "?", str(ent.grid_y) if ent else "?",
				TARGET.x, TARGET.y])
		# 2x2 footprint: all four cells must carry the same entity id
		var footprint_ok := true
		for dy in 2:
			for dx in 2:
				if sim.grid_cells[0][TARGET.y + dy][TARGET.x + dx] != eid:
					footprint_ok = false
		check("2x2 footprint registered in occupancy grid", footprint_ok)
	var gold_after: int = GameManager.get_player_gold(GameManager.local_player_id)
	check("gold deducted (50g barracks)", gold_after == gold_before - 50,
		"gold %d -> %d" % [gold_before, gold_after])

	await capture("after_place")
