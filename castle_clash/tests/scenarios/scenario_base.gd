## Base class for scripted interaction scenarios (--scenario <name> CLI mode).
## Replaces human screen-recorded playtests: each scenario is a reproducible
## sequence of steps (waits, forced state, synthesized taps/drags/zooms,
## captures, assertions) driven by scenario_runner.gd.
##
## ALL pointer interaction is synthesized through Input.parse_input_event()
## in WINDOW coordinates, so events travel the SAME path as real play:
## window -> canvas_items stretch transform -> viewport -> _input / GUI.
## Never call game handlers directly — the input->world transform IS the
## thing under test.
##
## Print/exit conventions match the existing suites:
##   "  PASS: ..." / "  FAIL: ... — detail"
##   "=== Results: N passed, M failed ===" and quit(0/1).
class_name ScenarioBase
extends Node

var scenario_name: String = "unnamed"
var out_dir: String = "/tmp/castle_clash_scenarios/unnamed"

var _pass: int = 0
var _fail: int = 0
var _checks: Array = []
var _capture_index: int = 0
var _finished: bool = false

# Viewport -> window transform for synthesized events (calibrated at start).
var _input_xform: Transform2D = Transform2D.IDENTITY
var _input_calibrated: bool = false

const UNIT_STATE_NAMES := ["march", "chase", "attack", "siege"]


## Override in each scenario. Runs after the main scene enters the tree.
func run() -> void:
	push_error("ScenarioBase.run() not overridden by %s" % scenario_name)
	check("scenario implements run()", false, "run() not overridden")


# --- Assertions ---

func check(name: String, cond: bool, detail: String = "") -> void:
	_checks.append({"name": name, "ok": cond, "detail": detail})
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


## assert_state(Callable) — truth-test a predicate against live state.
## assert_state(Dictionary) — compare dot-paths into the state dump, e.g.
##   assert_state({"sim.prep_phase": false, "camera.zoom": 2.0})
func assert_state(spec, name: String = "assert_state") -> void:
	if spec is Callable:
		check(name, bool(spec.call()))
	elif spec is Dictionary:
		var dump: Dictionary = ScenarioStateDump.build(get_tree())
		for path in spec:
			var actual = _dig(dump, str(path))
			var expected = spec[path]
			var ok: bool
			if expected is float and (actual is float or actual is int):
				ok = is_equal_approx(float(actual), expected)
			else:
				ok = actual == expected
			check("%s[%s]" % [name, path], ok, "expected %s, got %s" % [str(expected), str(actual)])
	else:
		check(name, false, "assert_state spec must be Callable or Dictionary")


func _dig(dict: Dictionary, dot_path: String):
	var cur = dict
	for key in dot_path.split("."):
		if cur is Dictionary and cur.has(key):
			cur = cur[key]
		elif cur is Array and key.is_valid_int() and int(key) < cur.size():
			cur = cur[int(key)]
		else:
			return null
	return cur


## Print summary, write result.json, quit with 0/1. Called by the runner.
func finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	var f := FileAccess.open(out_dir + "/result.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"scenario": scenario_name,
			"passed": _pass,
			"failed": _fail,
			"checks": _checks,
		}, "  "))
		f.close()
	get_tree().quit(1 if _fail > 0 else 0)


# --- Waiting ---

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Wait until the simulation has advanced n ticks (or the match ended).
func wait_ticks(n: int) -> void:
	var target: int = GameManager.current_tick + n
	while GameManager.current_tick < target:
		if GameManager.state != GameManager.State.PLAYING:
			return
		await get_tree().process_frame


## Poll for the main menu scene (loading screen auto-transitions ~4s after
## boot). Returns the menu node or null on timeout.
func wait_for_main_menu(timeout_sec: float = 15.0) -> Node:
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var menu := _find_main_menu()
		if menu != null:
			# Let the SceneTransition fade-in finish so input isn't blocked.
			await wait(1.0)
			return menu
		await get_tree().process_frame
	return null


func _find_main_menu() -> Node:
	var cs := get_tree().current_scene
	if cs and cs.has_method("_select_tab"):
		return cs
	for child in get_tree().root.get_children():
		if child.has_method("_select_tab"):
			return child
	return null


# --- Match setup / forced state ---

## Start an offline match. GameManager.start_test_match() seeds the sim with
## the FIXED seed 12345, so captures are comparable run-to-run.
## disable_ai=true also suppresses the opponent AI (wall-clock timed, hence
## nondeterministic) for stable golden-ish captures.
func start_match(faction: StringName = &"kingdom", disable_ai: bool = true) -> void:
	# Ride the normal boot flow first (loading -> menu) so no pending
	# SceneTransition tween can yank us back to the menu mid-scenario.
	await wait_for_main_menu()
	GameManager.selected_faction = faction
	GameManager.selected_perk = &""
	GameManager.selected_game_mode = GameManager.GameMode.STANDARD
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game_arena.tscn")
	var deadline: int = Time.get_ticks_msec() + 15000
	while GameManager.state != GameManager.State.PLAYING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if GameManager.state != GameManager.State.PLAYING:
		check("match started", false, "GameManager never reached PLAYING")
		return
	if disable_ai:
		var arena := find_arena()
		if arena:
			arena.ai_disabled = true
	await wait(0.5)


## Force game state outside the command stream (test-only hook; offline only).
## Supported keys:
##   gold: int                     — local player's gold (display units)
##   castle0_hp_pct / castle1_hp_pct: int — castle HP as % of max
##   castle0_hp / castle1_hp: int  — castle HP absolute (display units)
##   camera_zoom: float            — arena camera zoom (also clamps position)
##   camera_pos: Vector2           — arena camera position (clamped)
##   ai_disabled: bool             — suppress opponent AI building
func force_state(state: Dictionary) -> void:
	var sim = GameManager.simulation
	if sim != null:
		if state.has("gold"):
			var pi: int = sim.get_player_index(GameManager.local_player_id)
			if pi >= 0:
				sim.players[pi].gold = FP.from_int(int(state.gold))
		for team in 2:
			var new_hp: int = -1
			if state.has("castle%d_hp_pct" % team):
				var pct: int = int(state["castle%d_hp_pct" % team])
				new_hp = FP.div(FP.mul(sim.castles[team].max_hp, FP.from_int(pct)), FP.from_int(100))
			elif state.has("castle%d_hp" % team):
				new_hp = FP.from_int(int(state["castle%d_hp" % team]))
			if new_hp >= 0:
				sim.castles[team].hp = new_hp
				var ce = sim._find_entity_by_id(sim.castles[team].get("entity_id", -1))
				if ce:
					ce.hp = new_hp
	var arena := find_arena()
	if arena:
		if state.has("camera_zoom"):
			arena._zoom_level = float(state.camera_zoom)
			arena.camera.zoom = Vector2(arena._zoom_level, arena._zoom_level)
			arena._clamp_camera_position()
		if state.has("camera_pos"):
			arena.camera.position = state.camera_pos
			arena._clamp_camera_position()
		if state.has("ai_disabled"):
			arena.ai_disabled = bool(state.ai_disabled)


# --- Scene lookups ---

func find_arena() -> Node2D:
	var cs := get_tree().current_scene
	if cs and cs.has_method("grid_to_screen"):
		return cs
	return null


## The grid overlay that accepts the LOCAL player's placement input.
func local_grid(arena: Node2D) -> Node2D:
	if arena == null or GameManager.simulation == null:
		return null
	var local_idx: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	var g0: Node2D = arena.grid_overlay_0
	var g1: Node2D = arena.grid_overlay_1
	return g0 if g0.player_index == local_idx else g1


## Center of a player-0 build-zone tile in WORLD coordinates.
func tile_world_center(cell: Vector2i) -> Vector2:
	var arena := find_arena()
	var margin_x: int = arena.GRID_MARGIN_X if arena else 206
	var zone_y: int = arena.PLAYER_ZONE_Y if arena else 695
	var cs: int = arena.CELL_SIZE if arena else 28
	return Vector2(margin_x + cell.x * cs + cs * 0.5, zone_y + cell.y * cs + cs * 0.5)


## World (canvas) position -> viewport screen position under current camera.
func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


# --- Input synthesis (Input.parse_input_event, window coordinates) ---

## Events fed to Input.parse_input_event() must be in WINDOW coordinates —
## the root Window applies the canvas_items stretch transform (720x1280
## viewport rendered in a 504x896 window) to them exactly as it does for
## real OS events. Verify the viewport->window transform empirically: feed a
## probe motion and observe where a probe Control's _input receives it.
## (Viewport.get_mouse_position() is NOT a valid oracle — it tracks the real
## OS cursor, not the synthesized stream.)
func _calibrate_input() -> void:
	if _input_calibrated:
		return
	var window := get_window()
	var probe_ctl := _InputProbe.new()
	probe_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # observe only, never consume
	get_tree().root.add_child(probe_ctl)
	var candidates: Array[Transform2D] = [
		window.get_final_transform(),          # viewport -> window (expected)
		window.get_final_transform().affine_inverse(),
		Transform2D.IDENTITY,
	]
	var probe := Vector2(360, 640)
	for xform in candidates:
		probe_ctl.last_pos = Vector2(-9999, -9999)
		var ev := InputEventMouseMotion.new()
		ev.position = xform * probe
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame
		await get_tree().process_frame
		if probe_ctl.last_pos.distance_to(probe) < 2.0:
			_input_xform = xform
			_input_calibrated = true
			print("[Scenario] input calibrated: viewport %s -> window %s" % [probe, ev.position])
			probe_ctl.queue_free()
			return
	push_warning("[Scenario] input calibration failed — falling back to identity")
	probe_ctl.queue_free()
	_input_calibrated = true


## Observes where synthesized events arrive in viewport coordinates.
class _InputProbe extends Control:
	var last_pos := Vector2(-9999, -9999)

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			last_pos = event.position


func _feed_button(vp_pos: Vector2, button: MouseButton, pressed: bool, mask: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = _input_xform * vp_pos
	ev.global_position = ev.position
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask
	Input.parse_input_event(ev)


func _feed_motion(vp_pos: Vector2, mask: int, rel_vp: Vector2 = Vector2.ZERO) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _input_xform * vp_pos
	ev.global_position = ev.position
	ev.button_mask = mask
	ev.relative = _input_xform.basis_xform(rel_vp)
	Input.parse_input_event(ev)


## Deliver buffered events, then let handlers/redraws run for a few frames.
func _pump(frames: int = 2) -> void:
	Input.flush_buffered_events()
	for i in frames:
		await get_tree().process_frame


## Tap (press+release) at a viewport position. Drives both GUI (_gui_input,
## e.g. cards/buttons) and world input (_input/_unhandled_input) paths.
func tap(vp_pos: Vector2) -> void:
	await _calibrate_input()
	_feed_motion(vp_pos, 0)
	await _pump()
	_feed_button(vp_pos, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	await _pump()
	_feed_button(vp_pos, MOUSE_BUTTON_LEFT, false, 0)
	await _pump()


## Press-drag-release between two viewport positions over `duration` seconds.
func drag(from_vp: Vector2, to_vp: Vector2, duration: float = 0.3,
		button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _calibrate_input()
	var mask: int = MOUSE_BUTTON_MASK_LEFT
	if button == MOUSE_BUTTON_MIDDLE:
		mask = MOUSE_BUTTON_MASK_MIDDLE
	elif button == MOUSE_BUTTON_RIGHT:
		mask = MOUSE_BUTTON_MASK_RIGHT
	_feed_motion(from_vp, 0)
	await _pump()
	_feed_button(from_vp, button, true, mask)
	await _pump()
	var steps: int = maxi(int(duration * 30.0), 4)
	var prev := from_vp
	for i in steps:
		var p := from_vp.lerp(to_vp, float(i + 1) / float(steps))
		_feed_motion(p, mask, p - prev)
		prev = p
		Input.flush_buffered_events()
		await get_tree().process_frame
	_feed_button(to_vp, button, false, 0)
	await _pump()


## Raw mouse-wheel notches (positive = wheel up = zoom in). Sends pressed +
## released pairs like real OS wheel input — a lone pressed event leaves the
## GUI's mouse_focus stuck on whatever Control was under the cursor, which
## then swallows every later click.
func wheel(notches: int, vp_pos: Vector2 = Vector2(360, 520)) -> void:
	await _calibrate_input()
	var btn: MouseButton = MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN
	for i in absi(notches):
		_feed_button(vp_pos, btn, true, 0)
		_feed_button(vp_pos, btn, false, 0)
		await _pump(1)
	await _pump()


## Zoom toward a target zoom factor through real wheel events (bounded loop).
func zoom(target_factor: float, vp_pos: Vector2 = Vector2(360, 520)) -> void:
	var arena := find_arena()
	if arena == null:
		return
	for i in 40:
		var cur: float = arena.camera.zoom.x
		if absf(cur - target_factor) < 0.051:
			break
		await wheel(1 if cur < target_factor else -1, vp_pos)


## Synthesize a keyboard key press/release (Input.is_key_pressed sees it).
func key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Pan the camera by holding WASD for `seconds` — the keyboard path the
## camera polls in _process (600 px/s / zoom). dir is the world direction.
func pan_keys(dir: Vector2, seconds: float) -> void:
	await _calibrate_input()
	var keys: Array = []
	if dir.y < 0.0:
		keys.append(KEY_W)
	if dir.y > 0.0:
		keys.append(KEY_S)
	if dir.x < 0.0:
		keys.append(KEY_A)
	if dir.x > 0.0:
		keys.append(KEY_D)
	for k in keys:
		key(k, true)
	Input.flush_buffered_events()
	await wait(seconds)
	for k in keys:
		key(k, false)
	await _pump()


## Pan the camera by world_delta (world px) via MIDDLE-CLICK DRAG. NOTE: as of
## 2026-07-02 this input path is dead in the real game too — full-screen
## STOP-filter ColorRects (GrassMain et al) consume the middle press before
## game_arena._unhandled_input sees it. Kept as the honest repro path; use
## pan_keys() when a scenario needs panning that actually works.
func pan_middle_drag(world_delta: Vector2) -> void:
	var arena := find_arena()
	var zoom_f: float = arena.camera.zoom.x if arena else 1.0
	var center := Vector2(360, 640)
	var remaining := world_delta
	# Camera moves by (drag_start - drag_end) / zoom, so cursor movement is
	# -world_delta * zoom. Keep each segment within the viewport.
	var seg_limit := 500.0 / zoom_f
	var guard: int = 0
	while remaining.length() > 0.5 and guard < 20:
		guard += 1
		var chunk := remaining.clamp(Vector2(-seg_limit, -seg_limit), Vector2(seg_limit, seg_limit))
		var cursor_move := -chunk * zoom_f
		var from := center - cursor_move * 0.5
		var to := center + cursor_move * 0.5
		await drag(from, to, 0.25, MOUSE_BUTTON_MIDDLE)
		remaining -= chunk


# --- High-level interactions ---

## Tap the card for `building_id` in the card hand (GUI input path).
## Returns true when the grid confirms the building is selected.
func select_card(building_id: StringName) -> bool:
	var arena := find_arena()
	if arena == null:
		return false
	var hand: Control = arena.get_node_or_null("UILayer/CardHand")
	if hand == null:
		return false
	var card: Control = null
	for child in hand.get_children():
		var bd = child.get("bd")
		if bd != null and bd.id == building_id:
			card = child
			break
	if card == null:
		return false
	var grid := local_grid(arena)
	if grid == null:
		return false
	# Up to 3 attempts: transient overlays/frame timing can eat a single tap
	# (a human re-taps too). Persistent failures still fail, with the hovered
	# control logged for diagnosis.
	for attempt in 3:
		await tap(card.get_global_rect().get_center())
		if grid.selected_building != null and grid.selected_building.id == building_id:
			return true
		var hovered := get_viewport().gui_get_hovered_control()
		print("[Scenario] card tap attempt %d missed (hovered=%s) — retrying" % [
			attempt + 1, hovered.get_path() if hovered else "none"])
		await wait(0.3)
	return false


## Full placement interaction: tap card, then hold-drag-release onto the
## target tile (T-097 flow). Returns the entity id occupying the target cell
## afterwards, or -1. The drag AIMS at the tile's on-screen position under
## the CURRENT camera — that mapping is exactly what's under test.
func place_building_via_input(building_id: StringName, cell: Vector2i) -> int:
	var selected := await select_card(building_id)
	if not selected:
		check("card '%s' selected" % building_id, false, "card tap did not select building")
		return -1
	var target_screen := world_to_screen(tile_world_center(cell))
	var from_screen := world_to_screen(tile_world_center(cell) + Vector2(30, 44))
	await drag(from_screen, target_screen, 0.35)
	await wait_ticks(3)
	var sim = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)
	var eid: int = sim.grid_cells[pi][cell.y][cell.x]
	return eid if eid >= 0 else -1


# --- Capture ---

## Screenshot + state-dump JSON to <out_dir>/<NN>_<label>.{png,json}.
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := "%s/%02d_%s" % [out_dir, _capture_index, label]
	img.save_png(base + ".png")
	var dump: Dictionary = ScenarioStateDump.build(get_tree())
	dump["label"] = label
	dump["capture_index"] = _capture_index
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(dump, "  "))
		f.close()
	print("[Scenario] captured %s.png" % base)
	_capture_index += 1
