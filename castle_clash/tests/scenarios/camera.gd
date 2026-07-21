## SCENARIO: camera zoom + pan limits.
## Drives the camera exclusively through the inputs it listens to (mouse wheel
## zoom, middle-click-drag pan) and asserts zoom clamps to [1.0, 2.0] and pan
## clamps to the arena bounds. Captures at every extreme.
## Run: godot --path castle_clash -- --scenario camera
extends ScenarioBase


func run() -> void:
	await start_match(&"kingdom", true)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	var arena := find_arena()
	var cam: Camera2D = arena.camera
	check("camera starts at home (360,640) zoom 1.0",
		cam.position.is_equal_approx(Vector2(360, 640)) and is_equal_approx(cam.zoom.x, 1.0),
		"pos=%s zoom=%f" % [cam.position, cam.zoom.x])
	await capture("default_view")

	# Zoom IN well past the limit — must clamp at ZOOM_MAX (2.0)
	await wheel(20)
	check("zoom-in clamps at 2.0 (sent 20 notches)", is_equal_approx(cam.zoom.x, 2.0),
		"zoom=%f" % cam.zoom.x)
	await capture("zoom_max")

	# Zoom OUT well past the limit — must clamp at ZOOM_MIN (1.0, arena exactly
	# fills the viewport; below that would reveal void) and recenter to home.
	await wheel(-40)
	check("zoom-out clamps at 1.0 (sent 40 notches)", is_equal_approx(cam.zoom.x, 1.0),
		"zoom=%f" % cam.zoom.x)
	check("camera recenters to home when fully zoomed out",
		cam.position.is_equal_approx(Vector2(360, 640)), "pos=%s" % cam.position)
	await capture("zoom_min")

	# Back to 2x and pan to each extreme. At zoom 2 the visible area is
	# 360x640, so the camera center must clamp to x:[180,540] y:[320,960].
	await wheel(20)
	check("re-zoomed to 2.0", is_equal_approx(cam.zoom.x, 2.0), "zoom=%f" % cam.zoom.x)

	# BUG REPRO: middle-click-drag pan is implemented in _unhandled_input, but
	# the full-screen STOP-filter terrain ColorRects (GrassMain et al) consume
	# the middle press in the GUI phase first. Expected FAIL until fixed.
	await pan_middle_drag(Vector2(60, 60))
	check("middle-drag pan moves the camera (known-broken input path)",
		not cam.position.is_equal_approx(Vector2(360, 640)),
		"camera still at %s after middle-drag — press consumed by STOP ColorRect" % cam.position)

	# Keyboard pan (WASD polling — works) drives the clamp assertions.
	await pan_keys(Vector2(-1, -1), 2.5)
	check("pan clamps at top-left extreme (180,320)",
		cam.position.is_equal_approx(Vector2(180, 320)), "pos=%s" % cam.position)
	await capture("pan_top_left")

	await pan_keys(Vector2(1, 0), 2.5)
	check("pan clamps at right extreme (x=540)",
		is_equal_approx(cam.position.x, 540.0), "pos=%s" % cam.position)
	await capture("pan_top_right")

	await pan_keys(Vector2(0, 1), 3.0)
	check("pan clamps at bottom extreme (y=960)",
		is_equal_approx(cam.position.y, 960.0), "pos=%s" % cam.position)
	await capture("pan_bottom_right")

	await pan_keys(Vector2(-1, 0), 2.5)
	check("pan clamps at left extreme (x=180)",
		is_equal_approx(cam.position.x, 180.0), "pos=%s" % cam.position)
	await capture("pan_bottom_left")

	# Sanity: state dump agrees with the live camera
	assert_state({"camera.zoom": 2.0, "camera.x": 180.0, "camera.y": 960.0}, "state_dump_camera")

	# --- 1A-5: zoom must anchor at the CURSOR, not the camera center ---
	# Pan off the clamp extremes first so clamping can't mask the assert.
	await pan_keys(Vector2(1, -1), 1.2)
	var world_before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2(500, 400)
	await wheel(-2, Vector2(500, 400))
	var world_after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2(500, 400)
	check("zoom anchors at cursor (world point under (500,400) stays put)",
		world_before.distance_to(world_after) < 8.0,
		"world under cursor slid %s -> %s (center-anchored zoom)" % [world_before, world_after])
	await capture("zoom_to_cursor")

	# --- 1A-5: Blocked! popup must render in SCREEN space (UILayer) ---
	# Root-parented canvas items are camera-transformed: under zoom/pan the
	# popup drifts up to half a screen from the tap. Trigger: place a
	# barracks, then tap the SAME cell with another card selected.
	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)
	var selected := await select_card(&"barracks")
	check("card selected for popup repro", selected)
	await tap_touch(world_to_screen(tile_world_center(Vector2i(2, 4))))
	await wait_ticks(3)
	check("barracks placed for popup repro", sim.grid_cells[pi][4][2] >= 0)
	selected = await select_card(&"wall")
	check("second card selected", selected)
	await tap_touch(world_to_screen(tile_world_center(Vector2i(2, 4))))
	await _pump(4)
	var popup := _find_blocked_popup()
	check("Blocked! popup appeared", popup != null, "no node with a Blocked!/No gold! label")
	if popup:
		check("popup lives in a CanvasLayer (screen space, 1A-5)",
			popup.get_parent() is CanvasLayer,
			"parented to %s — root canvas items drift under camera zoom/pan" % popup.get_parent().name)
	await capture("blocked_popup")


## The Blocked!/No gold! toast is Effects.create_damage_number's Node2D with
## a Label child — search the whole tree for it.
func _find_blocked_popup() -> Node2D:
	var queue: Array = [get_tree().root as Node]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Node2D and n.get_child_count() > 0 and n.get_child(0) is Label:
			var t: String = (n.get_child(0) as Label).text
			if t == "Blocked!" or t == "No gold!":
				return n
		for c in n.get_children():
			queue.append(c)
	return null
