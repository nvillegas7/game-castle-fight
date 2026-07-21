## SCENARIO: two-finger pinch-zoom + pan from raw ScreenTouch/ScreenDrag
## (1A-3). Android emits ONLY touch events — the Magnify/PanGesture branches
## are macOS-trackpad-only, so phones had no camera zoom or pan at all.
## A FAIL on the zoom/pan asserts is the bug reproduction.
## Run: godot --path castle_clash -- --scenario pinch_zoom_pan
extends ScenarioBase


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()
	var cam: Camera2D = arena.camera
	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)

	# --- Pinch OUT (spread) around midpoint (360,600) ---
	var mid := Vector2(360, 600)
	var world_mid_before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * mid
	_feed_touch(Vector2(300, 600), 0, true)
	_feed_touch(Vector2(420, 600), 1, true)
	await _pump(2)
	for step in 8:
		var spread: float = 12.0 * (step + 1)
		_feed_touch_drag(Vector2(300 - spread, 600), 0, Vector2(-12, 0))
		_feed_touch_drag(Vector2(420 + spread, 600), 1, Vector2(12, 0))
		await _pump(1)
	await _pump(2)
	var zoom_after_pinch: float = cam.zoom.x
	check("pinch-out zooms the camera in (touch-only path)", zoom_after_pinch > 1.05,
		"zoom still %.2f — ScreenTouch pinch not handled (Android has no Magnify gesture)" % zoom_after_pinch)
	var world_mid_after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * mid
	check("pinch anchors at the finger midpoint",
		world_mid_before.distance_to(world_mid_after) < 10.0,
		"world under midpoint slid %s -> %s" % [world_mid_before, world_mid_after])
	await capture("after_pinch_out")

	# --- Two-finger parallel drag pans ---
	var pos_before_pan: Vector2 = cam.position
	for step in 6:
		_feed_touch_drag(Vector2(300 - 96 - 10 * step, 600 - 10 * step), 0, Vector2(-10, -10))
		_feed_touch_drag(Vector2(420 + 96 - 10 * step, 600 - 10 * step), 1, Vector2(-10, -10))
		await _pump(1)
	await _pump(2)
	check("two-finger drag pans the camera", cam.position.distance_to(pos_before_pan) > 5.0,
		"camera stayed at %s" % pos_before_pan)

	# --- Releasing one finger must not teleport the camera ---
	_feed_touch(Vector2(420 + 96 - 50, 550), 1, false)
	await _pump(2)
	var pos_after_release: Vector2 = cam.position
	_feed_touch_drag(Vector2(200, 500), 0, Vector2(-4, -6))
	await _pump(2)
	check("surviving finger does not jump the camera",
		cam.position.distance_to(pos_after_release) < 30.0,
		"camera teleported %s -> %s on the leftover finger" % [pos_after_release, cam.position])
	_feed_touch(Vector2(200, 500), 0, false)
	await _pump(3)

	# --- No placement happened during any of that ---
	var occupied: int = 0
	for row in sim.grid_cells[pi]:
		for cell in row:
			if cell >= 0:
				occupied += 1
	check("pinch/pan placed no buildings", occupied == 0, "%d cells occupied" % occupied)

	# --- Single-finger placement still works afterwards (no stuck state) ---
	var selected := await select_card(&"barracks")
	check("card selectable after pinch", selected)
	await tap_touch(world_to_screen(tile_world_center(Vector2i(2, 4))))
	await wait_ticks(3)
	check("single-finger tap-to-place still works after pinch",
		sim.grid_cells[pi][4][2] >= 0, "placement broken after two-finger session")
	await capture("after_place")
