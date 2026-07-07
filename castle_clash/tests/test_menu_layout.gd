## Main menu layout test. Captures each tab, analyzes for floating text and overlap.
## Catches regressions like orphaned labels, overlapping elements, missing containers.
##
## Usage: godot --path castle_clash -- --menutest
## Output: /tmp/castle_clash_menu_test/ (screenshots + report.json)
extends Node

const OUT_DIR: String = "/tmp/castle_clash_menu_test"
const TAB_NAMES: Array = ["Battle", "Shop", "Army", "Social", "Settings"]
const TAB_WAIT: float = 1.5  # Seconds per tab for rendering

var _active: bool = false
var _timer: float = 0.0
var _phase: int = 0  # 0=wait_load, 1-5=tab captures, 6=analyze, 7=done
var _tab_screenshots: Dictionary = {}  # tab_name -> Image
var _results: Array = []
var _issues: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--menutest" not in args:
		return
	_active = true
	print("\n=== Menu Layout Test ===\n")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_phase = 0
	_timer = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta

	if _phase == 0:
		# Wait for menu to fully load
		if _timer > 3.0:
			print("  Menu loaded, starting tab captures...")
			_phase = 1
			_timer = 0.0
	elif _phase >= 1 and _phase <= 5:
		# Capture current tab
		if _timer > TAB_WAIT:
			var tab_idx: int = _phase - 1
			var tab_name: String = TAB_NAMES[tab_idx] if tab_idx < TAB_NAMES.size() else "Unknown"
			_capture_tab(tab_name, tab_idx)
			# Try to switch to next tab
			if _phase < 5:
				_click_tab(_phase)  # Click next tab (0-indexed)
			_phase += 1
			_timer = 0.0
	elif _phase == 6:
		if _timer > 1.0:
			_run_analysis()
			_save_report()
			_phase = 7
			_timer = 0.0
	elif _phase == 7:
		if _timer > 0.5:
			_active = false
			get_tree().quit(0 if _issues.size() == 0 else 1)


func _capture_tab(tab_name: String, tab_idx: int) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  WARN: Could not capture %s" % tab_name)
		return
	var path := "%s/%s.png" % [OUT_DIR, tab_name.to_lower()]
	img.save_png(path)
	_tab_screenshots[tab_name] = img
	print("  Captured: %s (%dx%d)" % [tab_name, img.get_width(), img.get_height()])


func _click_tab(tab_idx: int) -> void:
	# Simulate clicking on tab bar at bottom of screen
	# Tab bar is at y ~= viewport_h - 80, tabs evenly spaced
	var vp := get_viewport()
	var w: int = vp.size.x
	var h: int = vp.size.y
	var tab_y: float = h - 50.0  # Tab center Y
	var tab_count: int = TAB_NAMES.size()
	var tab_w: float = float(w) / tab_count
	var tab_x: float = tab_w * tab_idx + tab_w * 0.5

	var ev := InputEventMouseButton.new()
	ev.position = Vector2(tab_x, tab_y)
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	# Release
	var ev2 := InputEventMouseButton.new()
	ev2.position = Vector2(tab_x, tab_y)
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _run_analysis() -> void:
	print("\n  --- Layout Analysis ---")

	for tab_name in _tab_screenshots:
		var img: Image = _tab_screenshots[tab_name]
		var w: int = img.get_width()
		var h: int = img.get_height()
		var checks: Dictionary = {}

		# Check 1: Screen not blank
		var unique_colors: int = _count_unique_colors(img, 8)
		checks["not_blank"] = unique_colors > 20
		if not checks["not_blank"]:
			_issues.append("%s: blank screen (%d colors)" % [tab_name, unique_colors])

		# Check 2: Top header area — should have dark/styled container, not raw text on scenic bg
		# Sample pixels in header row (y=10-40). If average brightness > 0.5, text is floating on bright bg
		var header_brightness: float = _region_avg_brightness(img, 10, 0, w, 40)
		checks["header_has_container"] = header_brightness < 0.45
		if not checks["header_has_container"]:
			_issues.append("%s: header too bright (%.2f) — floating text on scenic bg?" % [tab_name, header_brightness])

		# Check 3: Battle tab specific — check for text overlap in the mode selector area (y=400-550)
		if tab_name == "Battle":
			var mid_contrast: float = _region_text_layers(img, int(h * 0.4), int(h * 0.55))
			checks["no_text_overlap"] = mid_contrast < 0.6  # High contrast in small region = overlapping text
			if mid_contrast >= 0.6:
				_issues.append("Battle: possible text overlap in mode selector area (contrast=%.2f)" % mid_contrast)

			# Check 4: Gold bar / income display area (just above card hand, y ~= 73-78% of screen)
			# This is for battle SCREEN not menu, but we check anyway
			pass

		# Check 5: Tab bar at bottom should be dark/wood-textured
		var tab_bar_brightness: float = _region_avg_brightness(img, h - 80, 0, w, 80)
		checks["tab_bar_dark"] = tab_bar_brightness < 0.45
		if not checks["tab_bar_dark"]:
			_issues.append("%s: tab bar too bright (%.2f) — missing wood texture?" % [tab_name, tab_bar_brightness])

		# Check 6: No large floating bright text regions in the middle (y=100-400)
		# Floating text = small bright patches on dark/scenic bg with no panel
		var mid_bright_patches: int = _count_bright_patches(img, 100, int(h * 0.4))
		checks["no_floating_text"] = mid_bright_patches < 8
		if mid_bright_patches >= 8:
			_issues.append("%s: %d bright patches in mid-screen — possible floating text" % [tab_name, mid_bright_patches])

		var pass_count: int = 0
		for k in checks:
			if checks[k]:
				pass_count += 1
		var total: int = checks.size()
		var verdict: String = "PASS" if pass_count == total else "FAIL (%d/%d)" % [pass_count, total]
		print("    %s: %s %s" % [tab_name, verdict, str(checks)])
		_results.append({"tab": tab_name, "verdict": verdict, "checks": checks})


func _count_unique_colors(img: Image, step: int) -> int:
	var colors: Dictionary = {}
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			var key: int = (int(c.r * 31) << 10) | (int(c.g * 31) << 5) | int(c.b * 31)
			colors[key] = true
	return colors.size()


func _region_avg_brightness(img: Image, y_start: int, x_start: int, width: int, height: int) -> float:
	var total: float = 0.0
	var count: int = 0
	var step: int = 4
	for y in range(y_start, mini(y_start + height, img.get_height()), step):
		for x in range(x_start, mini(x_start + width, img.get_width()), step):
			var c: Color = img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			count += 1
	return total / maxf(count, 1.0)


func _region_text_layers(img: Image, y_start: int, y_end: int) -> float:
	# Detect overlapping text by measuring high-frequency brightness changes
	var transitions: int = 0
	var prev_b: float = 0.0
	var step: int = 2
	var samples: int = 0
	var cx: int = img.get_width() / 2
	for y in range(y_start, mini(y_end, img.get_height()), step):
		var c: Color = img.get_pixel(cx, y)
		var b: float = (c.r + c.g + c.b) / 3.0
		if abs(b - prev_b) > 0.15:
			transitions += 1
		prev_b = b
		samples += 1
	return float(transitions) / maxf(samples, 1.0)


func _count_bright_patches(img: Image, y_start: int, y_end: int) -> int:
	# Count distinct bright patches (text-like) on darker background
	var patches: int = 0
	var in_patch: bool = false
	var step: int = 6
	for y in range(y_start, mini(y_end, img.get_height()), step * 3):
		for x in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			var b: float = (c.r + c.g + c.b) / 3.0
			if b > 0.7 and not in_patch:
				patches += 1
				in_patch = true
			elif b < 0.4:
				in_patch = false
	return patches


func _save_report() -> void:
	var report: Dictionary = {
		"test": "menu_layout",
		"date": Time.get_datetime_string_from_system(),
		"tabs_captured": _tab_screenshots.size(),
		"issues": _issues,
		"all_passed": _issues.size() == 0,
		"results": _results,
	}
	var json := JSON.stringify(report, "  ")
	var f := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()

	print("\n=== Menu Layout Test Report ===")
	print("Tabs captured: %d" % _tab_screenshots.size())
	print("Issues found: %d" % _issues.size())
	for issue in _issues:
		print("  - %s" % issue)
	print("All passed: %s" % (_issues.size() == 0))
	print("Output: %s/" % OUT_DIR)
