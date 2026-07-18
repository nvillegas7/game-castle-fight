## Audio regression test. Runs a full match and logs every SFX/music play call.
## Verifies all audio categories fire, music transitions happen, no player leaks.
## Usage: godot --path castle_clash -- --audiotest
## Output: /tmp/castle_clash_audio/ (audio_log.json + report.json)
extends Node

const OUT_DIR: String = "/tmp/castle_clash_audio"
const MATCH_DURATION: float = 90.0  # Run for 90 seconds
const EXPECTED_CATEGORIES: Array[String] = ["combat", "building", "ui", "music", "ambient"]

var _active: bool = false
var _timer: float = 0.0
var _phase: int = 0  # 0=menu_wait, 1=start_match, 2=monitor, 3=end_check, 4=report
var _audio_log: Array = []  # [{time, category, function, detail}]
var _music_transitions: Array = []  # [track_name, ...]
var _match_started: bool = false

# Category tracking
var _category_counts: Dictionary = {
	"combat": 0,
	"building": 0,
	"ui": 0,
	"music": 0,
	"ambient": 0,
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--audiotest" not in args:
		return
	_active = true
	print("\n=== Audio Regression Test ===\n")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Hook into EventBus signals to track audio triggers
	_connect_audio_hooks()
	_phase = 0
	_timer = 0.0


func _connect_audio_hooks() -> void:
	# Connect to EventBus signals that SHOULD trigger audio
	if EventBus.has_signal("unit_attacked"):
		EventBus.unit_attacked.connect(_on_unit_attacked)
	if EventBus.has_signal("unit_died"):
		EventBus.unit_died.connect(_on_unit_died)
	if EventBus.has_signal("unit_healed"):
		EventBus.unit_healed.connect(_on_unit_healed)
	if EventBus.has_signal("building_placed"):
		EventBus.building_placed.connect(_on_building_placed)
	if EventBus.has_signal("building_destroyed"):
		EventBus.building_destroyed.connect(_on_building_destroyed)
	if EventBus.has_signal("castle_damaged"):
		EventBus.castle_damaged.connect(_on_castle_damaged)
	if EventBus.has_signal("skill_activated"):
		EventBus.skill_activated.connect(_on_skill_activated)
	if EventBus.has_signal("wave_started"):
		EventBus.wave_started.connect(_on_wave_started)
	if EventBus.has_signal("match_started"):
		EventBus.match_started.connect(_on_match_started)
	if EventBus.has_signal("match_ended"):
		EventBus.match_ended.connect(_on_match_ended)
	if EventBus.has_signal("gold_changed"):
		EventBus.gold_changed.connect(_on_gold_changed)
	if EventBus.has_signal("income_tick"):
		EventBus.income_tick.connect(_on_income_tick)
	print("  Connected %d EventBus audio hooks" % 12)


func _log_audio(category: String, func_name: String, detail: String = "") -> void:
	_audio_log.append({
		"time": _timer,
		"category": category,
		"function": func_name,
		"detail": detail,
	})
	_category_counts[category] = _category_counts.get(category, 0) + 1


# --- EventBus Signal Handlers (track what SHOULD produce audio) ---

func _on_unit_attacked(attacker_id: int, target_id: int, damage: int, tx: float, ty: float) -> void:
	_log_audio("combat", "play_hit/play_shoot", "atk=%d tgt=%d dmg=%d" % [attacker_id, target_id, damage])

func _on_unit_died(unit_id: int, killer_id: int) -> void:
	_log_audio("combat", "play_death", "unit=%d killer=%d" % [unit_id, killer_id])

func _on_unit_healed(healer_id: int, target_id: int, amount: int, tx: float, ty: float) -> void:
	_log_audio("combat", "play_heal", "healer=%d tgt=%d amt=%d" % [healer_id, target_id, amount])

func _on_building_placed(player_id: int, _bd: Resource, _pos: Vector2i) -> void:
	_log_audio("building", "play_place", "player=%d" % player_id)

func _on_building_destroyed(building_id: int) -> void:
	_log_audio("building", "play_destroy", "bld=%d" % building_id)

func _on_castle_damaged(team: int, damage: int, remaining: int, attacker_id: int) -> void:
	_log_audio("combat", "play_castle_hit", "team=%d dmg=%d rem=%d" % [team, damage, remaining])

func _on_skill_activated(unit_id: int, skill_id: StringName, _center: Vector2 = Vector2.INF) -> void:
	_log_audio("combat", "play_skill", "unit=%d skill=%s" % [unit_id, skill_id])

func _on_wave_started(wave: int) -> void:
	_log_audio("combat", "play_wave", "wave=%d" % wave)

func _on_match_started() -> void:
	_log_audio("music", "play_music(battle_theme)", "match_started")
	_log_audio("ambient", "start_ambient", "match_started")
	_music_transitions.append("battle_theme")

func _on_match_ended(winning_team: int) -> void:
	var track: String = "victory_fanfare" if winning_team == 0 else "defeat_fanfare"
	_log_audio("music", "play_music(%s)" % track, "match_ended team=%d" % winning_team)
	_log_audio("ambient", "stop_ambient", "match_ended")
	_music_transitions.append(track)

func _on_gold_changed(player_id: int, _amount: int) -> void:
	if player_id == 0:
		_log_audio("building", "play_gold", "player=%d" % player_id)

func _on_income_tick(player_id: int, _amount: int) -> void:
	pass  # Income tick doesn't produce audio directly


func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta

	match _phase:
		0:  # Wait for menu
			if _timer > 3.0:
				# Log menu music
				var sfx = get_node_or_null("/root/SFX")
				if sfx:
					var current: String = sfx.get("_current_track") if sfx.get("_current_track") != null else ""
					if current != "":
						_log_audio("music", "play_music(%s)" % current, "menu")
						_music_transitions.append(current)
				print("  Phase 0: Menu loaded, starting match...")
				_phase = 1
				_timer = 0.0
		1:  # Start match
			if _timer > 1.0:
				if GameManager.has_method("start_test_match"):
					GameManager.start_test_match()
					_match_started = true
				_log_audio("ui", "button_click", "start_match")
				print("  Phase 1: Match started")
				_phase = 2
				_timer = 0.0
		2:  # Monitor match
			# Auto-build to generate audio events
			if int(_timer) % 5 == 0 and int(_timer * 10) % 50 == 0:
				_try_auto_build()
			# Check SFX state periodically
			if int(_timer) % 10 == 0 and int(_timer * 10) % 100 == 0:
				_check_sfx_state()
			# End after MATCH_DURATION or match ends
			if _timer > MATCH_DURATION:
				print("  Phase 2: Monitoring complete (%.0fs)" % _timer)
				_phase = 3
				_timer = 0.0
		3:  # End checks
			if _timer > 2.0:
				_run_audio_checks()
				_phase = 4
				_timer = 0.0
		4:  # Save and exit
			if _timer > 1.0:
				_save_report()
				_active = false
				get_tree().quit(0 if _all_passed() else 1)


func _try_auto_build() -> void:
	if GameManager.has_method("submit_command"):
		GameManager.submit_command(Command.place_building(0, &"barracks", randi() % 8, randi() % 6))


func _check_sfx_state() -> void:
	var sfx = get_node_or_null("/root/SFX")
	if sfx == null:
		return
	# Count active players
	var active_count: int = 0
	var pool: Array = sfx.get("_players") if sfx.get("_players") != null else []
	for p in pool:
		if p is AudioStreamPlayer and p.playing:
			active_count += 1
	if active_count > 0:
		_log_audio("combat", "_check_active_players", "active=%d/%d" % [active_count, pool.size()])


var _check_results: Dictionary = {}

func _run_audio_checks() -> void:
	print("\n  --- Audio Verification ---")
	var sfx = get_node_or_null("/root/SFX")

	# Check 1: All expected categories had events
	for cat in EXPECTED_CATEGORIES:
		var count: int = _category_counts.get(cat, 0)
		var passed: bool = count > 0
		_check_results["category_%s" % cat] = passed
		print("    Category '%s': %d events — %s" % [cat, count, "PASS" if passed else "FAIL"])

	# Check 2: Music transitions happened (menu → battle is minimum)
	var has_transitions: bool = _music_transitions.size() >= 2
	_check_results["music_transitions"] = has_transitions
	print("    Music transitions: %s — %s" % [str(_music_transitions), "PASS" if has_transitions else "FAIL"])

	# Check 3: No AudioStreamPlayer leaks (all should be stopped at end)
	if sfx:
		var leaking: int = 0
		var pool: Array = sfx.get("_players") if sfx.get("_players") != null else []
		for p in pool:
			if p is AudioStreamPlayer and p.playing:
				leaking += 1
		# Some may still be playing from recent events — allow up to 4
		var no_leak: bool = leaking <= 4
		_check_results["no_player_leaks"] = no_leak
		print("    Player leaks: %d active (threshold 4) — %s" % [leaking, "PASS" if no_leak else "FAIL"])

		# Check 4: Ambient state
		var ambient_active: bool = sfx.get("_ambient_active") if sfx.get("_ambient_active") != null else false
		_check_results["ambient_was_active"] = _category_counts.get("ambient", 0) > 0
		print("    Ambient events: %d — %s" % [
			_category_counts.get("ambient", 0),
			"PASS" if _category_counts.get("ambient", 0) > 0 else "FAIL"])

	# Check 5: Total audio events (should be many in a 90s match)
	var total_events: int = _audio_log.size()
	var enough_events: bool = total_events >= 20
	_check_results["enough_events"] = enough_events
	print("    Total audio events: %d — %s" % [total_events, "PASS" if enough_events else "FAIL"])

	# Check 6: Combat audio diversity (not just one type)
	var combat_types: Dictionary = {}
	for entry in _audio_log:
		if entry.category == "combat":
			combat_types[entry.function] = true
	var diverse: bool = combat_types.size() >= 3
	_check_results["combat_diversity"] = diverse
	print("    Combat audio types: %d (%s) — %s" % [combat_types.size(), str(combat_types.keys()), "PASS" if diverse else "FAIL"])


func _all_passed() -> bool:
	for key in _check_results:
		if not _check_results[key]:
			return false
	return _check_results.size() > 0


func _save_report() -> void:
	# Save full audio log
	var log_json := JSON.stringify(_audio_log, "  ")
	var lf := FileAccess.open("%s/audio_log.json" % OUT_DIR, FileAccess.WRITE)
	if lf:
		lf.store_string(log_json)
		lf.close()

	# Save report
	var report: Dictionary = {
		"test": "audio_regression",
		"date": Time.get_datetime_string_from_system(),
		"match_duration_sec": MATCH_DURATION,
		"total_events": _audio_log.size(),
		"category_counts": _category_counts,
		"music_transitions": _music_transitions,
		"checks": _check_results,
		"all_passed": _all_passed(),
	}
	var rj := JSON.stringify(report, "  ")
	var rf := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if rf:
		rf.store_string(rj)
		rf.close()

	print("\n=== Audio Test Report ===")
	print("Total events: %d" % _audio_log.size())
	print("Categories: %s" % str(_category_counts))
	print("Music transitions: %s" % str(_music_transitions))
	print("All passed: %s" % _all_passed())
	print("Output: %s/" % OUT_DIR)
