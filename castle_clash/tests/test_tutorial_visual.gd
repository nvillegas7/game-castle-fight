## Tutorial visual E2E test. Drives through all tutorial steps, captures screenshots,
## and analyzes each frame for expected visual elements (dark overlay, spotlight, text).
## Usage: godot --path castle_clash -- --tutorialtest
## Output: /tmp/castle_clash_tutorial/ (screenshots + report.json)
extends Node

const OUT_DIR: String = "/tmp/castle_clash_tutorial"
const STEP_WAIT: float = 2.0  # Seconds to wait per step before capture
const OVERLAY_DARKNESS_THRESHOLD: float = 0.25  # Avg brightness below this = dark overlay present
const SPOTLIGHT_BRIGHTNESS_DIFF: float = 0.15  # Spotlight region must be this much brighter than overlay

var _active: bool = false
var _timer: float = 0.0
var _current_phase: int = 0  # 0=wait_for_menu, 1=start_match, 2-5=tutorial steps, 6=verify_complete, 7=done
var _step_results: Array = []
var _match_started: bool = false
var _frame_count: int = 0
var _build_placed: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--tutorialtest" not in args:
		return
	_active = true
	print("\n=== Tutorial Visual E2E Test ===\n")
	# Force tutorial mode
	PlayerData.set_value("tutorial_complete", false)
	PlayerData.games_played = 0
	# Ensure output directory
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_current_phase = 0
	_timer = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	_frame_count += 1

	match _current_phase:
		0:  # Wait for scene to load
			if _timer > 3.0:
				_capture_screenshot("00_menu")
				print("  Phase 0: Menu loaded, starting match...")
				# Start a match — the tutorial should trigger
				_current_phase = 1
				_timer = 0.0
		1:  # Click battle / start match
			if _timer > 1.0 and not _match_started:
				# Try to start match via GameManager
				if GameManager.has_method("start_test_match"):
					GameManager.start_test_match()
					_match_started = true
				_timer = 0.0
			if _match_started and _timer > 2.0:
				_capture_screenshot("01_tutorial_start")
				_analyze_tutorial_step(1, "01_tutorial_start")
				print("  Phase 1: Match started, tutorial_mode=%s step=%d" % [
					GameManager.tutorial_mode, GameManager.tutorial_step])
				_current_phase = 2
				_timer = 0.0
		2:  # Tutorial Step 1: Place a building (card select)
			if _timer > STEP_WAIT:
				_capture_screenshot("02_step1_card_select")
				_analyze_tutorial_step(1, "02_step1_card_select")
				_log_game_state("step1")
				# Now place a building to advance tutorial
				if not _build_placed:
					_try_place_building()
					_build_placed = true
				_current_phase = 3
				_timer = 0.0
		3:  # Tutorial Step 2: Earn gold
			if _timer > STEP_WAIT:
				_capture_screenshot("03_step2_earn_gold")
				_analyze_tutorial_step(2, "03_step2_earn_gold")
				_log_game_state("step2")
				print("  Phase 3: Step 2 (earn gold), tutorial_step=%d" % GameManager.tutorial_step)
				_current_phase = 4
				_timer = 0.0
		4:  # Tutorial Step 3: Destroy castle
			if _timer > STEP_WAIT * 2:  # Extra wait for combat to start
				_capture_screenshot("04_step3_destroy")
				_analyze_tutorial_step(3, "04_step3_destroy")
				_log_game_state("step3")
				print("  Phase 4: Step 3 (destroy), tutorial_step=%d" % GameManager.tutorial_step)
				_current_phase = 5
				_timer = 0.0
		5:  # Tutorial Step 4: Complete / auto-advance
			if _timer > STEP_WAIT * 3:
				_capture_screenshot("05_step4_complete")
				_log_game_state("step4_complete")
				print("  Phase 5: tutorial_mode=%s, tutorial_step=%d" % [
					GameManager.tutorial_mode, GameManager.tutorial_step])
				_current_phase = 6
				_timer = 0.0
		6:  # Final verification
			if _timer > 1.0:
				_run_final_verification()
				_save_report()
				_current_phase = 7
				_timer = 0.0
		7:  # Exit
			if _timer > 1.0:
				_active = false
				get_tree().quit(0 if _all_passed() else 1)


func _capture_screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var path := "%s/%s.png" % [OUT_DIR, name]
		img.save_png(path)
		print("    Captured: %s (%dx%d)" % [name, img.get_width(), img.get_height()])


func _analyze_tutorial_step(expected_step: int, screenshot_name: String) -> void:
	var result: Dictionary = {
		"screenshot": screenshot_name,
		"expected_step": expected_step,
		"actual_step": GameManager.tutorial_step,
		"tutorial_mode": GameManager.tutorial_mode,
		"checks": {},
	}

	# State checks
	result.checks["tutorial_mode_active"] = GameManager.tutorial_mode
	result.checks["step_matches"] = GameManager.tutorial_step == expected_step or GameManager.tutorial_step == expected_step + 1

	# Pixel analysis on captured screenshot
	var img_path := "%s/%s.png" % [OUT_DIR, screenshot_name]
	var img := Image.load_from_file(img_path)
	if img:
		var analysis := _analyze_image(img)
		result.checks["not_blank"] = analysis.unique_colors > 10
		result.checks["has_dark_overlay"] = analysis.avg_brightness < OVERLAY_DARKNESS_THRESHOLD
		result.checks["has_spotlight"] = analysis.spotlight_diff > SPOTLIGHT_BRIGHTNESS_DIFF
		result.checks["has_text_region"] = analysis.text_region_contrast > 0.1
		result.merge(analysis)
	else:
		result.checks["screenshot_loaded"] = false

	var passed: int = 0
	var total: int = 0
	for key in result.checks:
		total += 1
		if result.checks[key]:
			passed += 1
	result["verdict"] = "PASS" if passed == total else "FAIL (%d/%d)" % [passed, total]
	print("    Step %d analysis: %s" % [expected_step, result.verdict])
	_step_results.append(result)


func _analyze_image(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w == 0 or h == 0:
		return {"unique_colors": 0, "avg_brightness": 1.0, "spotlight_diff": 0.0, "text_region_contrast": 0.0}

	# Sample pixels for analysis
	var total_brightness: float = 0.0
	var colors: Dictionary = {}
	var sample_count: int = 0
	var overlay_brightness: float = 0.0
	var overlay_samples: int = 0
	var center_brightness: float = 0.0
	var center_samples: int = 0

	# Sample grid (every 8th pixel for speed)
	var step: int = 8
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			var b: float = (c.r + c.g + c.b) / 3.0
			total_brightness += b
			sample_count += 1
			var key: int = (int(c.r * 15) << 8) | (int(c.g * 15) << 4) | int(c.b * 15)
			colors[key] = true

			# Overlay region: edges of screen (corners)
			if (x < w * 0.15 or x > w * 0.85) and (y < h * 0.15 or y > h * 0.85):
				overlay_brightness += b
				overlay_samples += 1
			# Center region: where spotlight likely is
			if x > w * 0.3 and x < w * 0.7 and y > h * 0.3 and y < h * 0.7:
				center_brightness += b
				center_samples += 1

	var avg_b: float = total_brightness / maxf(sample_count, 1.0)
	var overlay_avg: float = overlay_brightness / maxf(overlay_samples, 1.0)
	var center_avg: float = center_brightness / maxf(center_samples, 1.0)

	# Text region: bottom third often has text bubbles — check contrast
	var text_min: float = 1.0
	var text_max: float = 0.0
	for x in range(w / 4, 3 * w / 4, step):
		for y in range(2 * h / 3, h, step):
			var c: Color = img.get_pixel(x, y)
			var b: float = (c.r + c.g + c.b) / 3.0
			text_min = minf(text_min, b)
			text_max = maxf(text_max, b)

	return {
		"unique_colors": colors.size(),
		"avg_brightness": avg_b,
		"overlay_avg_brightness": overlay_avg,
		"center_avg_brightness": center_avg,
		"spotlight_diff": center_avg - overlay_avg,
		"text_region_contrast": text_max - text_min,
	}


func _try_place_building() -> void:
	# Submit a building placement command to advance tutorial from step 1
	if GameManager.has_method("submit_command"):
		GameManager.submit_command(Command.place_building(0, &"barracks", 3, 3))
		print("    Placed barracks at (3,3) to advance tutorial")


func _log_game_state(label: String) -> void:
	var state: Dictionary = {
		"label": label,
		"tutorial_mode": GameManager.tutorial_mode,
		"tutorial_step": GameManager.tutorial_step,
		"gold": GameManager.get_player_gold(0) if GameManager.has_method("get_player_gold") else -1,
	}
	print("    State [%s]: mode=%s step=%d" % [label, state.tutorial_mode, state.tutorial_step])


func _run_final_verification() -> void:
	print("\n  --- Final Verification ---")
	var result: Dictionary = {
		"screenshot": "final",
		"checks": {},
	}
	# Tutorial should have completed (or at least progressed)
	result.checks["tutorial_progressed"] = GameManager.tutorial_step >= 1
	result.checks["persistence_set"] = PlayerData.get_value("tutorial_complete", false) == true or GameManager.tutorial_step >= 2
	# Verify match is still running (tutorial didn't crash the sim)
	result.checks["match_alive"] = not GameManager.get("match_over") if GameManager.get("match_over") != null else true

	for key in result.checks:
		var status: String = "PASS" if result.checks[key] else "FAIL"
		print("    %s: %s" % [key, status])
	_step_results.append(result)


func _all_passed() -> bool:
	for r in _step_results:
		if r.has("verdict") and "FAIL" in str(r.verdict):
			return false
		if r.has("checks"):
			for key in r.checks:
				if not r.checks[key]:
					return false
	return true


func _save_report() -> void:
	var report: Dictionary = {
		"test": "tutorial_visual_e2e",
		"date": Time.get_datetime_string_from_system(),
		"total_frames": _frame_count,
		"steps_captured": _step_results.size(),
		"all_passed": _all_passed(),
		"step_results": _step_results,
	}
	var json := JSON.stringify(report, "  ")
	var f := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	print("\n=== Tutorial Test Report ===")
	print("Steps captured: %d" % _step_results.size())
	print("All passed: %s" % _all_passed())
	print("Output: %s/" % OUT_DIR)
	print("Report: %s/report.json" % OUT_DIR)
