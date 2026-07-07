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
