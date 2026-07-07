## SCENARIO: place a building with a single-finger TOUCH tap (mobile path).
## Repro for the reported "can't place units on mobile" bug: a real touchscreen
## delivers a ScreenTouch AND an emulated MouseButton per finger; building_grid's
## multi-touch cancel guard saw the two as different fingers and cancelled the
## placement, so tap-to-place never committed on a phone (even at zoom 1).
## A FAIL here is the bug reproduction. Run:
##   godot --path castle_clash -- --scenario place_building_touch
extends ScenarioBase

const BUILDING := &"barracks"
const TARGET := Vector2i(2, 4)


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()

	# Select the card (works on device via the emulated-mouse path on the Control).
	var selected := await select_card(BUILDING)
	check("card '%s' selected" % BUILDING, selected, "card tap did not select building")

	# Place with a single-finger touch tap at the tile's on-screen position.
	var target_screen := world_to_screen(tile_world_center(TARGET))
	await tap_touch(target_screen)
	await wait_ticks(3)

	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)
	var eid: int = sim.grid_cells[pi][TARGET.y][TARGET.x]
	check("single-finger touch placed building at (%d,%d)" % [TARGET.x, TARGET.y], eid >= 0,
		"touch tap committed nothing — emulated-mouse twin cancelled placement")
	if eid >= 0:
		var ent = sim._find_entity_by_id(eid)
		check("placed entity is a %s" % BUILDING,
			ent != null and ent.get("building_type", &"") == BUILDING,
			"got %s" % (str(ent.get("building_type", &"?")) if ent else "null"))
	await capture("after_touch_place")
