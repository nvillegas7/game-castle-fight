## Multi-scenario video test suite for QA behavior analysis.
## Captures frames + logs unit positions every sim tick, then analyzes pathing issues.
## Usage:
##   godot --path castle_clash -- --videotest                    # Run all scenarios
##   godot --path castle_clash -- --videotest --scenario melee   # Run one scenario
extends Node

var _active: bool = false
var _scenario_name: String = ""
var _run_all: bool = false
var _scenario_queue: Array = []

# Per-scenario state
var _timer: float = 0.0
var _frame_count: int = 0
var _match_started: bool = false
var _tick_log: Array = []
var _last_tick: int = -1
var _build_timer: float = 0.0
var _builds_done_p0: int = 0
var _builds_done_p1: int = 0
var _scenario_start_time: float = 0.0
var _match_ended: bool = false

const CAPTURE_INTERVAL: float = 2.0
const MAX_FRAMES: int = 90  # ~3 min per scenario
const BUILD_INTERVAL: float = 2.5
const BASE_OUT_DIR: String = "/tmp/castle_clash_video"

# --- Scenario Definitions ---
# Each scenario defines what buildings each player places.
# p0 = player (kingdom, bottom), p1 = AI (horde, top)
# Empty array = no buildings (defend only)
# "ai_auto" key = let the AI use its own strategy instead of manual placement
var SCENARIOS: Dictionary = {
	"player_only": {
		"desc": "Player builds, AI defends (no buildings)",
		"p0": [&"barracks", &"archer_range", &"knight_hall"],
		"p1": [],
		"ai_auto": false,
	},
	"ai_only": {
		"desc": "AI builds normally, player defends (no buildings)",
		"p0": [],
		"p1": [],
		"ai_auto": true,
	},
	"melee": {
		"desc": "Both sides melee only (barracks vs war_camp)",
		"p0": [&"barracks"],
		"p1": [&"war_camp"],
		"ai_auto": false,
	},
	"ranged": {
		"desc": "Both sides ranged only (archers vs axe throwers)",
		"p0": [&"archer_range"],
		"p1": [&"axe_range"],
		"ai_auto": false,
	},
	"full_army": {
		"desc": "Both sides build all unit-spawning buildings",
		"p0": [&"barracks", &"archer_range", &"priest_temple", &"knight_hall", &"siege_workshop"],
		"p1": [&"war_camp", &"axe_range", &"war_drums", &"berserker_pit", &"demolisher_works"],
		"ai_auto": false,
	},
	"building_solo": {
		"desc": "Each T1 building type isolated — cycles through them",
		"p0": [&"barracks"],  # Overridden per sub-round
		"p1": [&"war_camp"],  # Overridden per sub-round
		"ai_auto": false,
	},
	"wall_maze": {
		"desc": "Walls/palisades + melee — pathing stress test",
		"p0": [&"wall", &"wall", &"wall", &"barracks"],
		"p1": [&"palisade", &"palisade", &"palisade", &"war_camp"],
		"ai_auto": false,
	},
	"defend_test": {
		"desc": "Player barracks LEFT vs 2 enemy war_camps RIGHT — do nearby grunts defend?",
		"p0": [&"barracks"],
		"p1": [&"war_camp", &"war_camp"],
		"ai_auto": false,
		"max_buildings": 2,
		"p0_start_col": 0,   # Player places left side
		"p1_start_col": 7,   # Enemy places right side
	},
	"gryphon_test": {
		"desc": "Gryphon roost + wyvern nest — verify flying unit sprites",
		"p0": [&"archer_range", &"gryphon_roost"],
		"p1": [&"axe_range", &"wyvern_nest"],
		"ai_auto": false,
	},
	"composite_units": {
		"desc": "All composite units: gryphon, knight, ballista, catapult — verify sprites + projectiles",
		"p0": [&"archer_range", &"gryphon_roost", &"knight_hall", &"royal_stable", &"siege_workshop", &"ballista_workshop"],
		"p1": [&"axe_range", &"wyvern_nest", &"berserker_pit", &"beast_pen", &"demolisher_works", &"scorpion_foundry"],
		"ai_auto": false,
	},
}

# Building solo sub-rounds: pairs of (kingdom_building, horde_building)
const SOLO_PAIRS: Array = [
	[&"barracks", &"war_camp"],
	[&"archer_range", &"axe_range"],
	[&"priest_temple", &"war_drums"],
	[&"knight_hall", &"berserker_pit"],
	[&"siege_workshop", &"demolisher_works"],
]
var _solo_index: int = 0

# Combined report across all scenarios
var _report: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--videotest":
			_active = true
		if args[i] == "--scenario" and i + 1 < args.size():
			_scenario_name = args[i + 1]
	if not _active:
		return

	DirAccess.make_dir_recursive_absolute(BASE_OUT_DIR)

	if _scenario_name == "" or _scenario_name == "all":
		_run_all = true
		_scenario_queue = SCENARIOS.keys().duplicate()
	elif SCENARIOS.has(_scenario_name):
		_scenario_queue = [_scenario_name]
	else:
		print("[VideoTest] ERROR: Unknown scenario '%s'" % _scenario_name)
		print("[VideoTest] Available: %s" % ", ".join(SCENARIOS.keys()))
		get_tree().quit()
		return

	print("[VideoTest] Suite: %d scenario(s) queued" % _scenario_queue.size())
	await get_tree().create_timer(0.5).timeout
	_start_next_scenario()


func _start_next_scenario() -> void:
	if _scenario_queue.is_empty():
		_print_final_report()
		get_tree().quit()
		return

	var name: String = _scenario_queue.pop_front()
	_scenario_name = name
	_reset_state()

	var scenario: Dictionary = SCENARIOS[name]

	# Handle building_solo sub-rounds
	if name == "building_solo" and _solo_index < SOLO_PAIRS.size():
		var pair: Array = SOLO_PAIRS[_solo_index]
		scenario = scenario.duplicate()
		scenario.p0 = [pair[0]]
		scenario.p1 = [pair[1]]
		print("\n[VideoTest] === SCENARIO: %s (%s vs %s) ===" % [name, pair[0], pair[1]])
	else:
		print("\n[VideoTest] === SCENARIO: %s ===" % name)
	print("[VideoTest] %s" % scenario.desc)

	var out_dir: String = _get_out_dir(name)
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Start match
	GameManager.selected_faction = &"kingdom"
	GameManager.tutorial_mode = false
	get_tree().change_scene_to_file("res://scenes/game/game_arena.tscn")
	await get_tree().create_timer(1.5).timeout

	# Disable AI if scenario controls both sides
	if not scenario.get("ai_auto", false):
		var arena = _find_game_arena()
		if arena:
			arena.ai_disabled = true

	_match_started = true
	_scenario_start_time = Time.get_ticks_msec() / 1000.0


func _reset_state() -> void:
	_timer = 0.0
	_frame_count = 0
	_match_started = false
	_match_ended = false
	_tick_log = []
	_last_tick = -1
	_build_timer = 0.0
	_builds_done_p0 = 0
	_builds_done_p1 = 0


func _get_out_dir(name: String) -> String:
	if name == "building_solo" and _solo_index < SOLO_PAIRS.size():
		return "%s/%s_%s" % [BASE_OUT_DIR, name, SOLO_PAIRS[_solo_index][0]]
	return "%s/%s" % [BASE_OUT_DIR, name]


func _find_game_arena():
	# game_arena.gd is the root of the game scene
	var root := get_tree().current_scene
	if root and root.has_method("_update_ai"):
		return root
	# Fallback: search children
	for child in get_tree().root.get_children():
		if child.has_method("_update_ai"):
			return child
	return null


func _process(delta: float) -> void:
	if not _active or not _match_started or _match_ended:
		return

	var scenario: Dictionary = SCENARIOS[_scenario_name]
	var current_scenario := scenario.duplicate() if _scenario_name != "building_solo" else scenario.duplicate()
	if _scenario_name == "building_solo" and _solo_index < SOLO_PAIRS.size():
		current_scenario.p0 = [SOLO_PAIRS[_solo_index][0]]
		current_scenario.p1 = [SOLO_PAIRS[_solo_index][1]]

	# Place buildings for both sides on timer
	_build_timer += delta
	if _build_timer >= BUILD_INTERVAL:
		_build_timer = 0.0
		_place_for_player(0, current_scenario.get("p0", []))
		if not current_scenario.get("ai_auto", false):
			_place_for_player(1, current_scenario.get("p1", []))

	# Log unit positions every simulation tick
	if GameManager.simulation and GameManager.current_tick > _last_tick:
		_last_tick = GameManager.current_tick
		_log_tick()

	# Check for match end
	if GameManager.state == GameManager.State.MATCH_OVER:
		_match_ended = true
		_capture_frame()
		_finish_scenario()
		return

	# Capture frame for video
	_timer += delta
	if _timer >= CAPTURE_INTERVAL:
		_timer = 0.0
		_capture_frame()
		_frame_count += 1
		if _frame_count >= MAX_FRAMES:
			_match_ended = true
			_finish_scenario()


func _place_for_player(player_id: int, building_ids: Array) -> void:
	if building_ids.is_empty():
		return
	# Check max_buildings cap if set
	var scenario: Dictionary = SCENARIOS[_scenario_name]
	var max_bldg: int = scenario.get("max_buildings", 0)
	if max_bldg > 0:
		var builds_done: int = _builds_done_p0 if player_id == 0 else _builds_done_p1
		if builds_done >= building_ids.size():
			return  # Already placed all buildings in the list
	if GameManager.simulation == null:
		return
	var sim: Simulation = GameManager.simulation
	var pi: int = sim.get_player_index(player_id)
	if pi == -1:
		return

	# Unlimited gold
	sim.players[pi].gold = FP.from_int(9999)

	var faction: FactionData = GameManager.get_player_faction(player_id)
	if faction == null:
		return

	# Pick next building from the allowed list (cycle through)
	var builds_done: int = _builds_done_p0 if player_id == 0 else _builds_done_p1
	var target_id: StringName = building_ids[builds_done % building_ids.size()]

	# Find matching BuildingData from faction
	var chosen: BuildingData = null
	for bd: BuildingData in faction.buildings:
		if bd.id == target_id:
			# Check prerequisites
			if bd.requires_building == &"" or sim.player_has_building(pi, bd.requires_building):
				chosen = bd
			break

	if chosen == null:
		# Fallback: try first available from the list
		for bid in building_ids:
			for bd: BuildingData in faction.buildings:
				if bd.id == bid:
					if bd.requires_building == &"" or sim.player_has_building(pi, bd.requires_building):
						chosen = bd
						break
			if chosen:
				break

	if chosen == null:
		return

	# Find open grid position (use scenario start_col if specified)
	var start_col_key: String = "p0_start_col" if player_id == 0 else "p1_start_col"
	var start_col: int = scenario.get(start_col_key, 0)
	for row in range(sim.GRID_ROWS - 3):
		for col in range(start_col, sim.GRID_COLS):
			if sim.can_place_building(player_id, chosen.id, col, row):
				var cmd := Command.place_building(player_id, chosen.id, col, row)
				NetworkManager.send_command(cmd)
				if player_id == 0:
					_builds_done_p0 += 1
				else:
					_builds_done_p1 += 1
				return


func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out_dir := _get_out_dir(_scenario_name)
	var path := "%s/frame_%04d.png" % [out_dir, _frame_count]
	img.save_png(path)


func _log_tick() -> void:
	var sim := GameManager.simulation
	var entry := {
		"tick": sim.tick,
		"castle_0_hp": FP.to_int(sim.castles[0].hp),
		"castle_1_hp": FP.to_int(sim.castles[1].hp),
		"units": [],
	}
	for e in sim.entities:
		if e.type == "unit" and FP.gt(e.hp, FP.ZERO):
			entry.units.append({
				"id": e.id, "team": e.team, "type": e.unit_type,
				"x": FP.to_int(e.x), "y": FP.to_int(e.y),
				"tgt": e.target_id,
				"moving": e.get("is_moving", false),
				"hp": FP.to_int(e.hp),
			})
	_tick_log.append(entry)


func _finish_scenario() -> void:
	var out_dir := _get_out_dir(_scenario_name)
	_save_tick_log(out_dir)
	var result := _analyze_behavior()
	_report.append(result)

	var elapsed := (Time.get_ticks_msec() / 1000.0) - _scenario_start_time
	print("[VideoTest] Scenario '%s' done: %d frames, %d ticks, %.0fs elapsed" % [
		_scenario_name, _frame_count, _tick_log.size(), elapsed])

	# Handle building_solo sub-rounds
	if _scenario_name == "building_solo":
		_solo_index += 1
		if _solo_index < SOLO_PAIRS.size():
			# Re-queue building_solo for next pair
			_scenario_queue.push_front("building_solo")

	await get_tree().create_timer(1.0).timeout
	_start_next_scenario()


func _save_tick_log(out_dir: String) -> void:
	var json := JSON.stringify(_tick_log)
	var f := FileAccess.open(out_dir + "/tick_log.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()


func _analyze_behavior() -> Dictionary:
	print("\n  --- BEHAVIOR ANALYSIS: %s ---" % _scenario_name)
	var result := {"scenario": _scenario_name, "zigzag": 0, "bounce": 0, "stuck": 0, "units": 0}

	if _tick_log.size() < 10:
		print("  Not enough ticks to analyze")
		return result

	# Track each unit's position history
	var unit_histories: Dictionary = {}
	for entry in _tick_log:
		for u in entry.units:
			if not unit_histories.has(u.id):
				unit_histories[u.id] = []
			unit_histories[u.id].append({
				"tick": entry.tick, "x": u.x, "y": u.y,
				"tgt": u.tgt, "moving": u.moving,
				"team": u.team, "type": u.type,
			})

	result.units = unit_histories.size()

	for uid in unit_histories:
		var hist: Array = unit_histories[uid]
		if hist.size() < 5:
			continue
		var team: int = hist[0].team
		var utype: String = hist[0].type

		# Zigzag: Y-direction reversals
		var reversals: int = 0
		for i in range(2, hist.size()):
			var dy1: int = hist[i-1].y - hist[i-2].y
			var dy2: int = hist[i].y - hist[i-1].y
			if (dy1 > 2 and dy2 < -2) or (dy1 < -2 and dy2 > 2):
				reversals += 1
		if reversals > 5:
			result.zigzag += 1
			print("    ZIGZAG: %s #%d (team %d) — %d Y-reversals" % [utype, uid, team, reversals])

		# Bounce: oscillating near castle
		var castle_y: int = 920 if team == 0 else 70
		var bounce_ticks: int = 0
		for h in hist:
			if abs(h.y - castle_y) < 40 and h.moving:
				bounce_ticks += 1
		if bounce_ticks > 10:
			result.bounce += 1
			print("    BOUNCE: %s #%d (team %d) — %d ticks near castle" % [utype, uid, team, bounce_ticks])

		# Stuck: no movement for 20+ ticks
		# EXCLUDE: units near enemy castle (attacking it) or units with a target (fighting)
		var max_stuck: int = 0
		var stuck_run: int = 0
		for i in range(1, hist.size()):
			if abs(hist[i].x - hist[i-1].x) < 2 and abs(hist[i].y - hist[i-1].y) < 2:
				var near_castle: bool = (team == 0 and hist[i].y < 110) or (team == 1 and hist[i].y > 880)
				var has_target: bool = hist[i].tgt != -1
				if not near_castle and not has_target:
					stuck_run += 1
					max_stuck = maxi(max_stuck, stuck_run)
				else:
					stuck_run = 0
			else:
				stuck_run = 0
		if max_stuck > 20:
			result.stuck += 1
			print("    STUCK: %s #%d (team %d) — %d consecutive ticks (no target)" % [utype, uid, team, max_stuck])

	# Castle damage timeline
	var first_tick: Dictionary = _tick_log[0]
	var last_tick: Dictionary = _tick_log[_tick_log.size() - 1]
	print("  Castle HP: P0 %d->%d, P1 %d->%d (%d ticks)" % [
		first_tick.castle_0_hp, last_tick.castle_0_hp,
		first_tick.castle_1_hp, last_tick.castle_1_hp,
		last_tick.tick - first_tick.tick])
	print("  Summary: %d zigzag, %d bounce, %d stuck / %d units" % [
		result.zigzag, result.bounce, result.stuck, result.units])

	return result


func _print_final_report() -> void:
	print("\n")
	print("=" .repeat(60))
	print("  VIDEO TEST SUITE — FINAL REPORT")
	print("=" .repeat(60))

	var total_zigzag: int = 0
	var total_bounce: int = 0
	var total_stuck: int = 0
	var total_units: int = 0

	for r in _report:
		var status := "PASS"
		if r.zigzag > 5 or r.bounce > 3 or r.stuck > 5:
			status = "FAIL"
		elif r.zigzag > 0 or r.bounce > 0 or r.stuck > 0:
			status = "WARN"
		print("  [%s] %-20s  zigzag=%d  bounce=%d  stuck=%d  units=%d" % [
			status, r.scenario, r.zigzag, r.bounce, r.stuck, r.units])
		total_zigzag += r.zigzag
		total_bounce += r.bounce
		total_stuck += r.stuck
		total_units += r.units

	print("-" .repeat(60))
	print("  TOTAL: %d zigzag, %d bounce, %d stuck across %d units" % [
		total_zigzag, total_bounce, total_stuck, total_units])

	var verdict := "PASS"
	if total_zigzag > 20 or total_bounce > 10 or total_stuck > 20:
		verdict = "FAIL"
	elif total_zigzag > 0 or total_bounce > 0 or total_stuck > 0:
		verdict = "WARN"
	print("  VERDICT: %s" % verdict)
	print("=" .repeat(60))
	print("  Output: %s/" % BASE_OUT_DIR)

	# Save report as JSON
	var json := JSON.stringify(_report, "  ")
	var f := FileAccess.open(BASE_OUT_DIR + "/report.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
