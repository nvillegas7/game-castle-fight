## SCENARIO: radial menu under camera zoom (1A-4).
## Three defects this reproduces (RED pre-fix):
##   1. Menu anchors at the raw tap position, not the building's footprint
##      center — placement wobbles with where in the cell you tapped.
##   2. The _input hit-test compares a SCREEN-px distance to a WORLD-px
##      radius: at zoom 2 the button draws 2x but its tappable circle stays
##      18 screen px — taps on the visual edge dismiss instead of acting.
##   3. _RadialButton's Area2D ALSO dispatches the action (double-fire) —
##      benign for sell (sim validates), wrong for info; structurally dead
##      after the fix (construction check).
## Run: godot --path castle_clash -- --scenario radial_menu_under_zoom
extends ScenarioBase

const BUILDING := &"barracks"
const TARGET := Vector2i(2, 4)
const ZOOM := 2.0


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()
	var grid: Node2D = local_grid(arena)
	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)

	# Place at zoom 1 (placement-under-zoom is 1A-1's scenario), then zoom in.
	var selected := await select_card(BUILDING)
	check("card '%s' selected" % BUILDING, selected)
	await tap_touch(world_to_screen(tile_world_center(TARGET)))
	await wait_ticks(3)
	var eid: int = sim.grid_cells[pi][TARGET.y][TARGET.x]
	check("barracks placed", eid >= 0)
	if eid < 0:
		return
	var ent = sim.get_entity(eid)
	await tap_right(world_to_screen(Vector2(360, 850)))
	check("card deselected", grid.selected_building == null)

	force_state({"camera_zoom": ZOOM, "camera_pos": tile_world_center(TARGET)})
	await _pump(3)

	# --- Defect 1: open with a deliberately OFF-center tap ---
	await tap_touch(world_to_screen(tile_world_center(TARGET) + Vector2(10, 8)))
	await _pump(3)
	check("radial opens under zoom %.1f" % ZOOM, grid._radial_menu != null,
		"tap on owned building did not open the radial at zoom")
	if grid._radial_menu == null:
		return
	await capture("radial_open_zoom2")
	var cell: float = float(grid.CELL_SIZE)
	var expected := Vector2(
		(ent.grid_x + ent.grid_size_x / 2.0) * cell,
		(ent.grid_y + ent.grid_size_y / 2.0) * cell)  # view_flipped=false offline
	var anchor: Vector2 = grid._radial_menu.position
	check("menu anchored at footprint center %s (1A-4)" % expected,
		anchor.distance_to(expected) < 1.0,
		"anchored at %s — follows the tap position, not the cell" % anchor)

	# --- Defect 2: tap the sell button at its VISUAL edge ---
	var sell_btn: Node2D = null
	for child in grid._radial_menu.get_children():
		if "action" in child and child.action == "sell":
			sell_btn = child
			break
	check("sell button found", sell_btn != null)
	if sell_btn == null:
		return
	var refund: int = 0
	var bd = sim.building_registry.get(BUILDING)
	if bd:
		refund = bd.gold_cost * bd.sell_refund_percent / 100
	# 0.45 * btn_size world px from center = inside the drawn circle (r=0.5),
	# scaled to screen px by the zoom the player actually sees.
	var edge_screen: Vector2 = world_to_screen(sell_btn.global_position) \
		+ Vector2(0.45 * sell_btn.btn_size * ZOOM, 0)
	var gold_before: int = FP.to_int(sim.players[pi].gold)
	await tap_touch(edge_screen)
	await wait_ticks(3)
	check("edge tap on sell button SELLS at zoom (hit radius zoom-scaled)",
		sim.grid_cells[pi][TARGET.y][TARGET.x] == -1,
		"visual-edge tap missed the unscaled 18px hit circle — menu dismissed instead")
	check("exactly ONE refund (+%d)" % refund,
		FP.to_int(sim.players[pi].gold) == gold_before + refund,
		"gold %d -> %d" % [gold_before, FP.to_int(sim.players[pi].gold)])
	check("radial dismissed after action", grid._radial_menu == null)
	await capture("after_edge_sell_zoom2")

	# --- Defect 3 (construction): Area2D no longer dispatches actions ---
	var src: String = FileAccess.get_file_as_string("res://scripts/game/building_grid.gd")
	var btn_cls: int = src.find("class _RadialButton")
	var handler: int = src.find("func _on_input_event", btn_cls)
	var handler_src: String = src.substr(handler, 400) if handler >= 0 else ""
	check("Area2D handler does not double-dispatch _on_radial_action",
		handler < 0 or not handler_src.contains("_on_radial_action"),
		"both the _input hit-test and the Area2D fire the action per tap")


## Right-click tap — deselects the card (same helper as radial_menu.gd).
func tap_right(vp_pos: Vector2) -> void:
	_feed_button(vp_pos, MOUSE_BUTTON_RIGHT, true, MOUSE_BUTTON_MASK_RIGHT)
	await _pump(2)
	_feed_button(vp_pos, MOUSE_BUTTON_RIGHT, false, 0)
	await _pump(2)
