## Scenario driver autoload (registered in project.godot, same pattern as
## AutoScreenshot/VideoTest). Inert unless `--scenario <name>` is passed as a
## user arg in a WINDOWED run:
##   godot --path castle_clash -- --scenario place_building
##
## Loads res://tests/scenarios/<name>.gd (must extend ScenarioBase), runs its
## step sequence, and quits with exit code 0 (all checks passed) or 1.
## Output: /tmp/castle_clash_scenarios/<name>/NN_<label>.{png,json} + result.json
##
## NOTE: video_test.gd also reads `--scenario` but only as a sub-flag of
## `--videotest`; this runner stands down when --videotest is present.
extends Node

const SCENARIO_DIR := "res://tests/scenarios/"
const OUT_ROOT := "/tmp/castle_clash_scenarios"
const TIMEOUT_SEC: float = 150.0

var _scenario: ScenarioBase = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var name := ""
	var videotest := false
	for i in args.size():
		if args[i] == "--videotest":
			videotest = true
		if args[i] == "--scenario" and i + 1 < args.size():
			name = args[i + 1]
	if name == "" or videotest:
		return
	var path := SCENARIO_DIR + name + ".gd"
	if not ResourceLoader.exists(path):
		push_error("[ScenarioRunner] scenario script not found: %s" % path)
		print("FAIL: unknown scenario '%s' (%s not found)" % [name, path])
		print("\n=== Results: 0 passed, 1 failed ===")
		get_tree().quit.call_deferred(1)
		return
	var script: GDScript = load(path)
	_scenario = script.new()
	_scenario.scenario_name = name
	_scenario.out_dir = "%s/%s" % [OUT_ROOT, name]
	DirAccess.make_dir_recursive_absolute(_scenario.out_dir)
	_clear_old_captures(_scenario.out_dir)
	add_child(_scenario)
	_run()


func _run() -> void:
	print("[ScenarioRunner] running '%s' -> %s" % [_scenario.scenario_name, _scenario.out_dir])
	# Watchdog: a hung scenario must still exit nonzero, never wedge a runner.
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	# Let the main scene (loading screen) enter the tree first.
	await get_tree().process_frame
	await get_tree().process_frame
	await _scenario._calibrate_input()
	await _scenario.run()
	_scenario.finish()


func _on_timeout() -> void:
	if _scenario == null or _scenario._finished:
		return
	_scenario.check("scenario completed within %ds" % int(TIMEOUT_SEC), false,
		"watchdog timeout — forcing quit")
	await _scenario.capture("timeout")
	_scenario.finish()


## Remove stale captures so a fresh run's contact sheet has no leftovers.
func _clear_old_captures(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".png") or f.ends_with(".json"):
			d.remove(f)
