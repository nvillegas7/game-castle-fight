## Auto-screenshot + AI-vs-AI test tool.
## Activated by --autotest flag. Captures: loading → menu (all 5 tabs) → in-game
## (12 frames) → end screen (force-killed enemy castle for victory state).
## Usage: godot --path castle_clash -- --autotest

extends Node

var _active: bool = false
var _timer: float = 0.0
var _frame_count: int = 0
var _out_dir: String = "/tmp/castle_clash_test"
var _match_started: bool = false
var _build_timer: float = 0.0
var _builds_done: int = 0
var _end_screen_captured: bool = false
const INTERVAL: float = 5.0   # Capture every 5 seconds (less overhead)
const MAX_FRAMES: int = 12   # 60 seconds of gameplay
const BUILD_INTERVAL: float = 3.0  # Place a building every 3 seconds
# Tab indexes from main_menu.gd: 0=Shop, 1=Army, 2=Battle, 3=Social, 4=Settings.
const TAB_NAMES: Array[String] = ["shop", "army", "battle", "social", "settings"]


func _ready() -> void:
	var loading_only: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg == "--autotest":
			_active = true
		elif arg == "--autotest-loading":
			_active = true
			loading_only = true
	if not _active:
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[AutoTest] Active. AI-vs-AI mode. Saving to %s/" % _out_dir)
	# 1) Loading screen
	await get_tree().create_timer(0.5).timeout
	await _capture_frame("loading")
	if loading_only:
		print("[AutoTest] --autotest-loading: captured loading, quitting.")
		get_tree().quit()
		return
	# 2) Wait for main menu to render
	await get_tree().create_timer(4.0).timeout
	await _capture_frame("menu")
	# 3) Capture each main-menu tab (Battle is the default landing tab so already
	# captured above as menu_000.png — we still recapture as menu_battle to keep
	# naming uniform across all tabs).
	await _capture_all_menu_tabs()
	print("[AutoTest] Menu+tabs captured. Auto-starting match (Kingdom vs Horde)...")
	GameManager.selected_faction = &"kingdom"
	SceneTransition.change_scene("res://scenes/game/game_arena.tscn")
	await get_tree().create_timer(2.0).timeout
	_match_started = true


## Walks through every main-menu tab, waits for transition, captures.
func _capture_all_menu_tabs() -> void:
	var menu := _find_main_menu()
	if menu == null:
		print("[AutoTest] WARN: main_menu not found — skipping per-tab capture")
		return
	for i in TAB_NAMES.size():
		if menu.has_method("_select_tab"):
			menu._select_tab(i)
		# Wait for tab fade transition (~350ms per T-099) + 1 extra frame to be safe.
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		# IMPORTANT: await `_capture_frame` — it's an async function that awaits
		# another frame_post_draw internally. Without the await, the loop
		# iterates to the next `_select_tab` before the viewport is read, so the
		# saved PNG reflects the *next* tab's state (found via BUG-52 debug).
		await _capture_frame("menu_%s" % TAB_NAMES[i])
	# Leave on Battle tab so the existing change_scene flow proceeds normally.
	if menu.has_method("_select_tab"):
		menu._select_tab(2)
	await get_tree().create_timer(0.4).timeout


func _find_main_menu() -> Node:
	for child in get_tree().root.get_children():
		# Main menu is loaded as a Control scene under root via SceneTransition.
		if child.has_method("_select_tab"):
			return child
		# Also scan one level deeper for SceneTransition wrappers.
		for c2 in child.get_children():
			if c2.has_method("_select_tab"):
				return c2
	return null


func _process(delta: float) -> void:
	if not _active or not _match_started:
		return
	# Capture screenshots at interval
	_timer += delta
	if _timer >= INTERVAL:
		_timer = 0.0
		_capture_frame("game")
		_frame_count += 1
		if _frame_count >= MAX_FRAMES and not _end_screen_captured:
			_end_screen_captured = true  # set BEFORE await so _process can't re-enter
			_dump_game_state()
			print("[AutoTest] Captured %d frames. Forcing victory for end-screen capture..." % _frame_count)
			_force_victory_and_capture_end_screen()
			return

	# Auto-place buildings for player 0 (simulates human player)
	_build_timer += delta
	if _build_timer >= BUILD_INTERVAL:
		_build_timer = 0.0
		_auto_build()


func _auto_build() -> void:
	if GameManager.simulation == null:
		return
	var sim: Simulation = GameManager.simulation
	var pi: int = sim.get_player_index(GameManager.local_player_id)
	if pi == -1:
		return
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var faction: FactionData = GameManager.get_player_faction(GameManager.local_player_id)
	if faction == null:
		return

	# Build order: combat first, then variety
	var build_order := [&"barracks", &"barracks", &"archer_range",
		&"gold_mine", &"guard_tower", &"knight_hall", &"siege_workshop"]
	var target_type: StringName = build_order[mini(_builds_done, build_order.size() - 1)]

	# Find the building data
	var chosen: BuildingData = null
	for bd: BuildingData in faction.buildings:
		if bd.id == target_type and bd.gold_cost <= gold:
			if bd.requires_building == &"" or sim.player_has_building(pi, bd.requires_building):
				chosen = bd
				break
	# Fallback: buy cheapest affordable
	if chosen == null:
		for bd: BuildingData in faction.buildings:
			if bd.gold_cost <= gold and bd.spawns_unit:
				if bd.requires_building == &"" or sim.player_has_building(pi, bd.requires_building):
					chosen = bd
					break
	if chosen == null:
		return

	# Find open grid position
	for row in range(sim.GRID_ROWS):
		for col in range(sim.GRID_COLS):
			if sim.can_place_building(GameManager.local_player_id, chosen.id, col, row):
				var cmd := Command.place_building(GameManager.local_player_id, chosen.id, col, row)
				NetworkManager.send_command(cmd)
				_builds_done += 1
				print("[AutoTest] Placed %s at (%d,%d) [build #%d]" % [chosen.display_name, col, row, _builds_done])
				return


## Drain enemy castle HP to 0, wait for match_over → end_screen render, capture.
func _force_victory_and_capture_end_screen() -> void:
	if GameManager.simulation == null:
		print("[AutoTest] WARN: simulation null at end-screen step — quitting")
		get_tree().quit()
		return
	# Force enemy castle to 0 HP. Sim's tick check will emit match_over.
	GameManager.simulation.castles[1].hp = 0
	# Wait long enough for the next sim tick + end_screen scene transition.
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	_capture_frame("end_victory")
	# Also capture defeat-state end screen by overriding (can't replay the match
	# easily within one autotest run, so skip — file follow-up if needed).
	await get_tree().create_timer(0.5).timeout
	print("[AutoTest] End screen captured. Quitting.")
	get_tree().quit()


func _capture_frame(prefix: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%03d.png" % [_out_dir, prefix, _frame_count]
	img.save_png(path)
	print("[AutoTest] Saved %s" % path)


func _dump_game_state() -> void:
	if GameManager.simulation == null:
		return
	var sim := GameManager.simulation
	var state := {
		"tick": sim.tick,
		"player_0_gold": FP.to_int(sim.players[0].gold),
		"player_1_gold": FP.to_int(sim.players[1].gold),
		"castle_0_hp": FP.to_int(sim.castles[0].hp),
		"castle_1_hp": FP.to_int(sim.castles[1].hp),
		"total_entities": sim.entities.size(),
		"units": [],
		"buildings": [],
	}
	for e in sim.entities:
		if e.type == "unit":
			state.units.append({
				"id": e.id, "type": e.unit_type, "team": e.team,
				"hp": FP.to_int(e.hp), "x": FP.to_int(e.get("x", 0)), "y": FP.to_int(e.get("y", 0)),
				"target_id": e.target_id,
			})
		elif e.type == "building":
			state.buildings.append({
				"id": e.id, "type": e.building_type, "team": e.team,
				"hp": FP.to_int(e.hp),
			})
	var json := JSON.stringify(state, "  ")
	var f := FileAccess.open(_out_dir + "/game_state.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	print("[AutoTest] Game state dumped: %d units, %d buildings, castles %d/%d HP" % [
		state.units.size(), state.buildings.size(),
		state.castle_0_hp, state.castle_1_hp])
