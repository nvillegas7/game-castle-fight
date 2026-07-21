## SCENARIO: radial menu tap contract (BUG-34 verification).
## Tracker BUG-34 reported taps on the radial's SELL/INFO buttons racing the
## menu dismiss ("can't sell or inspect buildings"). The prescribed fix cites
## code that no longer exists; the shipped fix (direct button hit-testing in
## building_grid._input) landed unverified in checkpoint bdb34e6. This is the
## missing verification, plus a double-dispatch probe: the _input hit-test AND
## the _RadialButton Area2D can both fire the same action — the exact-refund
## assert catches a double sell ever refunding twice.
## Run: godot --path castle_clash -- --scenario radial_menu
extends ScenarioBase

const BUILDING := &"barracks"
const TARGET := Vector2i(2, 4)
const TARGET2 := Vector2i(6, 4)


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()
	var grid: Node2D = local_grid(arena)
	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)

	# --- Place a barracks (mirrors place_building_touch) ---
	var selected := await select_card(BUILDING)
	check("card '%s' selected" % BUILDING, selected, "card tap did not select building")
	await tap_touch(world_to_screen(tile_world_center(TARGET)))
	await wait_ticks(3)
	var eid: int = sim.grid_cells[pi][TARGET.y][TARGET.x]
	check("barracks placed at (%d,%d)" % [TARGET.x, TARGET.y], eid >= 0, "placement failed")
	if eid < 0:
		return

	# Selection persists after placement (repeat-place UX) — the radial only
	# opens with no card selected, so deselect the real way: right-click.
	await tap_right(world_to_screen(Vector2(360, 850)))
	check("card deselected", grid.selected_building == null,
		"right-click did not clear selection — radial can't open")

	# --- Open the radial on the placed building ---
	await tap_touch(world_to_screen(tile_world_center(TARGET)))
	await _pump(3)
	check("radial menu opened on tap", grid._radial_menu != null,
		"tap on owned building did not open the radial")
	await capture("radial_open")
	if grid._radial_menu == null:
		return

	# --- Tap SELL: action must land exactly once ---
	var refund: int = 0
	var bd = sim.building_registry.get(BUILDING)
	if bd:
		refund = bd.gold_cost * bd.sell_refund_percent / 100
	check("refund lookup sane", refund > 0, "sell_refund_percent/gold_cost missing")
	var sell_screen := Vector2.ZERO
	for child in grid._radial_menu.get_children():
		if "action" in child and child.action == "sell":
			sell_screen = world_to_screen(child.global_position)
			break
	check("sell button found in radial", sell_screen != Vector2.ZERO, "no sell _RadialButton")
	var gold_before: int = FP.to_int(sim.players[pi].gold)
	await tap_touch(sell_screen)
	await wait_ticks(3)
	var gold_after: int = FP.to_int(sim.players[pi].gold)
	check("SELL landed — building removed (BUG-34 race would dismiss instead)",
		sim.grid_cells[pi][TARGET.y][TARGET.x] == -1,
		"tap on sell button did not sell — dismiss raced the action")
	check("exactly ONE refund (+%d) — no double dispatch" % refund,
		gold_after == gold_before + refund,
		"gold %d -> %d, expected +%d" % [gold_before, gold_after, refund])
	check("radial dismissed after action", grid._radial_menu == null,
		"menu still open after sell")
	await capture("after_sell")

	# --- Tap OUTSIDE: dismisses without touching the building ---
	selected = await select_card(BUILDING)
	check("second card selected", selected)
	await tap_touch(world_to_screen(tile_world_center(TARGET2)))
	await wait_ticks(3)
	var eid2: int = sim.grid_cells[pi][TARGET2.y][TARGET2.x]
	check("second barracks placed", eid2 >= 0)
	if eid2 < 0:
		return
	await tap_right(world_to_screen(Vector2(360, 850)))
	await tap_touch(world_to_screen(tile_world_center(TARGET2)))
	await _pump(3)
	check("radial reopened", grid._radial_menu != null)
	var gold_pre_dismiss: int = FP.to_int(sim.players[pi].gold)
	# Far outside the menu — enemy half of the arena.
	await tap_touch(world_to_screen(Vector2(360, 300)))
	await _pump(3)
	await wait_ticks(2)
	check("tap outside dismissed the radial", grid._radial_menu == null,
		"menu did not dismiss on outside tap")
	check("outside tap did not sell/damage the building",
		sim.grid_cells[pi][TARGET2.y][TARGET2.x] == eid2
		and FP.to_int(sim.players[pi].gold) == gold_pre_dismiss,
		"outside tap mutated state")
	await capture("after_outside_dismiss")

	# --- MOUSE-path sell: the double-dispatch suspicion lives here ---
	# A real mouse tap reaches BOTH the _input hit-test and the button's
	# Area2D handler (touch twins are filtered, mouse isn't). The sim's sell
	# validation must eat the second dispatch: exactly one refund.
	await tap(world_to_screen(tile_world_center(TARGET2)))
	await _pump(3)
	check("radial opens via mouse tap", grid._radial_menu != null)
	if grid._radial_menu == null:
		return
	sell_screen = Vector2.ZERO
	for child in grid._radial_menu.get_children():
		if "action" in child and child.action == "sell":
			sell_screen = world_to_screen(child.global_position)
			break
	gold_before = FP.to_int(sim.players[pi].gold)
	await tap(sell_screen)
	await wait_ticks(3)
	check("mouse SELL landed with exactly ONE refund (+%d)" % refund,
		sim.grid_cells[pi][TARGET2.y][TARGET2.x] == -1
		and FP.to_int(sim.players[pi].gold) == gold_before + refund,
		"gold %d -> %d, expected +%d" % [gold_before, FP.to_int(sim.players[pi].gold), refund])
	await capture("after_mouse_sell")


## Right-click tap (press+release) — deselects a selected card. ScenarioBase
## only ships left-tap helpers; this reuses its calibrated feed path.
func tap_right(vp_pos: Vector2) -> void:
	_feed_button(vp_pos, MOUSE_BUTTON_RIGHT, true, MOUSE_BUTTON_MASK_RIGHT)
	await _pump(2)
	_feed_button(vp_pos, MOUSE_BUTTON_RIGHT, false, 0)
	await _pump(2)
