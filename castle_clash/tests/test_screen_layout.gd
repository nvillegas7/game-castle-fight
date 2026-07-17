## Screen layout regression test — detects programmatic-creation artifacts:
## (1) Same texture loaded ≥3 times in close succession (potential duplicate sprites)
## (2) Multiple Label/TextureRect siblings at identical position (overlap)
## (3) Sub-12px font sizes (BUG-41 mobile readability)
## (4) Labels with text-overflow risk (label.size.x too small for typical content)
##
## This is a STATIC analysis: scans .gd source for suspicious patterns + loads UI
## scenes to inspect node trees. Catches the kinds of bugs A4 found in 2026-04-18
## screen-polish review (BUG-43 loading bar duplication, BUG-44 NinePatch edges,
## BUG-45 card text overlap).
##
## Run: godot --headless --path castle_clash -s tests/test_screen_layout.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _quarantine: int = 0
var _findings: Array = []  # list of {severity, file, line, msg}

# Detectors for known, tracked, unresolved bugs. They report RED but don't fail
# the gate (Rare quarantine policy). Removing a ref here means the bug is truly
# fixed. 2026-07-18: BUG-47/49 resolved as STALE-CALIBRATION false positives —
# their artifacts (church spire, floating ribbons) were removed by the P2 menu
# redesign; both detectors recalibrated to guard the invariant on the current
# layout and un-quarantined. List now empty — keep the mechanism for the next
# genuinely-tracked-but-unfixed bug.
const QUARANTINED: Array = []

const UI_SCRIPTS: Array = [
	"res://scripts/ui/loading_screen.gd",
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/card_hand.gd",
	"res://scripts/ui/end_screen.gd",
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/tutorial.gd",
]

const UI_SCENES: Array = [
	"res://scenes/ui/loading_screen.tscn",
	"res://scenes/ui/main_menu.tscn",
]

# Mobile readability thresholds.
const MIN_BODY_FONT_SIZE: int = 12
const MIN_HEADER_FONT_SIZE: int = 14
# Color-on-background contrast: alpha and lightness combinations that pass the
# literal pixel-size check but fail in practice. BUG-41 RE-OPEN (2026-04-18):
# tagline "(0.75, 0.7, 0.55, 0.9)" font_size 13 on green scenic = ~2:1 contrast.
# Rule of thumb: if alpha < 0.85 AND font_size <= 14 AND no outline_size, flag it.
const MIN_LOW_CONTRAST_ALPHA: float = 0.95
const MIN_NON_OUTLINED_FONT: int = 14


func _init() -> void:
	await process_frame
	print("\n=== SCREEN LAYOUT REGRESSION ===\n")
	_check_sub_min_font_sizes()
	_check_low_contrast_text()           # BUG-41 RE-OPEN: alpha + size combos
	_check_repeat_texture_load()
	_check_locked_card_overlap_pattern()
	_check_progress_bar_construction()
	_check_progress_bar_pixel_continuity()  # BUG-43: recalibrated 2026-07-17, no vacuous pass
	_check_roof_icon_visibility()           # BUG-32: upgraded-building roof icons readable
	_check_occupancy_overlay_mapping()      # BUG-50: overlay rows == building-visual rows
	_check_tip_strip_construction()
	# Phase-1 detector suite (BUG-46/48/49) — pixel-level, run on
	# /tmp/castle_clash_test/menu_battle_000.png from latest --autotest run.
	# BUG-47 (tree z-clips church spire) RETIRED 2026-07-18: the P2 redesign
	# removed all scenic structures, leaving the detector nothing to guard —
	# every recalibration attempt only found new false-positive classes (logo
	# art, sky-grass gradient, inter-tree gaps, birch trunks). If scenic
	# structures return, write a calibrated detector against that real layout.
	_check_chimney_smoke_vertical()       # BUG-46
	_check_fence_row_repetition()         # BUG-48
	_check_ribbon_edge_clipping()         # BUG-49 (recalibrated 2026-07-18)
	# Phase-2 detector suite (BUG-51/52) — user-reported 2026-04-21.
	_check_battle_tab_always_lifted()     # BUG-51
	_check_non_battle_tab_scenic_bleed()  # BUG-52
	# Arena composition-parity suite (design-flow.md, 2026-07-08) — the approved
	# pixel spec is design/arena_target.png; these detectors pin its four
	# load-bearing properties so the port can't drift back.
	_check_arena_water_native()           # native teal, no modulate tint
	_check_arena_castle_scale()           # calibrated castle scale band
	_check_arena_castle_cliff()           # integrated stone cliff band under the castle
	_check_arena_fortress_towers()        # decorative towers flank each castle
	_check_arena_coastline_platform()     # platform edge at design x=72
	_check_arena_no_floating_foliage()    # no cropped/floating tree art in water
	# 3.3b terrain overhaul suite (2026-07-17) — approved arena_target.png rev B:
	# side plateaus + worn center path + big central gold (density parity vs v2).
	_check_arena_side_plateaus()          # elevated shelves' stone faces, both sides
	_check_arena_worn_path()              # color4 worn-grass lane down the combat zone
	_check_arena_central_gold()           # chunky gold cluster at field center
	# Screen-parity P1 + HUD-alignment (2026-07-11). Pixel + static detectors.
	# (HUD realigned to design/references/hud_target.png: transparent strip, yellow gold
	# ribbon w/ no fill, cream cards + slate locked — several P1 detectors re-targeted.)
	_check_hud_strip_transparent()        # top strip transparent (arena shows), not a wood/red strip
	_check_gold_bar_yellow()              # gold bar is a yellow ribbon, no red, no fill meter
	_check_hud_fonts_quantized()          # hud.gd + card_hand.gd fonts in {16,32}
	_check_hud_touch_targets()            # HP pill / card / ability / wrath sizes
	# Screen-parity P2 — Menu shell + Battle tab (2026-07-10).
	_check_menu_sky_not_flat_green()      # sky is a gradient, not a flat green wall
	_check_tab_labels_legible()           # inactive tab labels cream, not 2.1:1 void
	_check_trophy_not_shield()            # header trophy icon is a trophy, not a shield
	_check_online_cta_demoted()           # PLAY ONLINE is a compact chip, not a rival CTA
	# Screen-parity P3 — End screen (2026-07-11).
	_check_end_screen_takeover()          # in-match card tray hidden behind the results panel
	_check_victory_ribbon_bright()        # VICTORY ribbon at full parchment opacity
	_check_end_buttons_size()             # end-screen buttons >=80px
	# Screen-parity P4 — Army + Avatars tabs (2026-07-15).
	_check_army_cards_not_navy()          # army cards warm wood/paper, not cold-navy boxes
	_check_avatars_selected_ring()        # equipped avatar shows a visible gold ring
	# Screen-parity P5 — Social + Settings tabs (2026-07-16).
	_check_social_not_navy()              # social cards warm paper, not cold-navy boxes
	_check_settings_sliders_themed()      # volume sliders themed, not raw Godot gray
	_check_reset_demoted()                # Reset All Progress is an outline, not a filled primary
	_print_results()
	quit(1 if _fail > 0 else 0)


func _record(severity: String, src: String, line: int, msg: String) -> void:
	_findings.append({"severity": severity, "src": src, "line": line, "msg": msg})


# Captures now live under the project (test_output/, gitignored) instead of /tmp,
# which macOS purges every ~3 days. Writer: tests/auto_screenshot.gd.
const CAPTURE_DIR: String = "res://test_output/autotest"


func _cap(name: String) -> String:
	return ProjectSettings.globalize_path("%s/%s" % [CAPTURE_DIR, name])


# True once a capture run has written its manifest (tests/capture.sh / --autotest).
func _capture_manifest_present() -> bool:
	return FileAccess.file_exists(_cap("manifest.json"))


func _assert_pass(name: String) -> void:
	_pass += 1
	print("  PASS: %s" % name)


func _assert_fail(name: String, detail: String = "") -> void:
	# Quarantine (Rare flake policy): a detector whose title names a tracked-but-
	# unresolved bug reports RED but does not fail the build, so a known Phase-3
	# item can't block unrelated merges. It stays loudly visible every run. When
	# the underlying bug is fixed (or the detector is proven miscalibrated and
	# rewritten two-phase in Phase 3), remove its ref from QUARANTINED.
	for ref in QUARANTINED:
		if name.begins_with(ref):
			_quarantine += 1
			print("  QUARANTINED [%s, Phase 3]: %s — %s" % [ref, name, detail])
			return
	_fail += 1
	print("  FAIL: %s — %s" % [name, detail])


## Detects font_size_override calls under MIN_BODY_FONT_SIZE.
func _check_sub_min_font_sizes() -> void:
	print("[Mobile readability — sub-12px text]")
	var hits: Array = []
	for path in UI_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var content := _read_file(path)
		if content.is_empty():
			continue
		var lines := content.split("\n")
		for i in lines.size():
			var ln: String = lines[i]
			# Match: add_theme_font_size_override("font_size", N)
			var rx := RegEx.new()
			rx.compile('add_theme_font_size_override\\("font_size", (\\d+)\\)')
			var m := rx.search(ln)
			if m:
				var size_val: int = int(m.get_string(1))
				if size_val < MIN_BODY_FONT_SIZE:
					hits.append({"file": path, "line": i + 1, "size": size_val, "snippet": ln.strip_edges()})
	if hits.is_empty():
		_assert_pass("no sub-%dpx font_size_override calls found" % MIN_BODY_FONT_SIZE)
	else:
		_assert_fail("%d sub-%dpx font usages (mobile readability)" % [hits.size(), MIN_BODY_FONT_SIZE], "see findings")
		for h in hits:
			_record("HIGH", h.file, h.line, "font_size=%d (min %d) :: %s" % [h.size, MIN_BODY_FONT_SIZE, h.snippet])


## BUG-41 RE-OPEN: catches combinations of low alpha + small font + no outline
## that produce unreadable text even when font_size >= MIN_BODY_FONT_SIZE.
## Greps for `add_theme_color_override("font_color", Color(...))` and pairs each
## hit with the nearest preceding `add_theme_font_size_override` and lookahead
## for `outline_size`. Flags: alpha < MIN_LOW_CONTRAST_ALPHA AND size < MIN_NON_OUTLINED_FONT
## AND no outline_size > 0 in next 3 lines.
func _check_low_contrast_text() -> void:
	print("[Low-contrast text (alpha + size + no outline)]")
	var hits: Array = []
	for path in UI_SCRIPTS:
		var content := _read_file(path)
		if content.is_empty():
			continue
		var lines := content.split("\n")
		var pending_size: int = -1
		var pending_size_line: int = -1
		for i in lines.size():
			var ln: String = lines[i]
			# Track most recent font_size override (within ~5 lines)
			var rx_size := RegEx.new()
			rx_size.compile('add_theme_font_size_override\\("font_size",\\s*(\\d+)\\)')
			var ms := rx_size.search(ln)
			if ms:
				pending_size = int(ms.get_string(1))
				pending_size_line = i
				continue
			# Look for color override with alpha < threshold
			var rx_color := RegEx.new()
			rx_color.compile('add_theme_color_override\\("font_color",\\s*Color\\(([^)]+)\\)\\)')
			var mc := rx_color.search(ln)
			if mc and pending_size > 0 and i - pending_size_line < 8:
				var args: PackedStringArray = mc.get_string(1).split(",")
				if args.size() >= 4:
					var alpha: float = float(args[3].strip_edges())
					if alpha < MIN_LOW_CONTRAST_ALPHA and pending_size < MIN_NON_OUTLINED_FONT:
						# Check for outline in next 3 lines
						var has_outline: bool = false
						for j in range(i, mini(lines.size(), i + 4)):
							if lines[j].contains("outline_size") and not lines[j].contains("outline_size, 0"):
								has_outline = true
								break
						if not has_outline:
							hits.append({
								"file": path, "line": i + 1,
								"msg": "size=%d alpha=%.2f no outline — likely unreadable on busy bg" % [pending_size, alpha],
							})
	if hits.is_empty():
		_assert_pass("no low-contrast (small + faded + un-outlined) labels found")
	else:
		_assert_fail("%d low-contrast text labels (BUG-41 RE-OPEN risk)" % hits.size(), "see findings")
		for h in hits:
			_record("HIGH", h.file, h.line, h.msg)


## Detects "for X in Y: ... add_child(...)" patterns where same texture is loaded
## inside the loop body — high risk of duplicate-sprite layout bugs.
func _check_repeat_texture_load() -> void:
	print("[Repeated texture load inside loops]")
	var hits: Array = []
	for path in UI_SCRIPTS:
		var content := _read_file(path)
		if content.is_empty():
			continue
		var lines := content.split("\n")
		var in_loop: bool = false
		var loop_start: int = -1
		var loop_indent: int = -1
		var loop_body: Array = []
		for i in lines.size():
			var ln: String = lines[i]
			var indent: int = _indent_level(ln)
			var stripped: String = ln.strip_edges()
			# Detect for/while loop start
			var rx_for := RegEx.new()
			rx_for.compile('^(for|while)\\b')
			if rx_for.search(stripped):
				in_loop = true
				loop_start = i + 1
				loop_indent = indent
				loop_body.clear()
				continue
			if in_loop:
				if not stripped.is_empty() and indent <= loop_indent:
					# Loop ended — analyze body
					_analyze_loop_body(path, loop_start, loop_body, hits)
					in_loop = false
				else:
					loop_body.append({"text": stripped, "line": i + 1})
		# Trailing loop at EOF
		if in_loop:
			_analyze_loop_body(path, loop_start, loop_body, hits)
	if hits.is_empty():
		_assert_pass("no suspicious repeat-texture-in-loop patterns")
	else:
		_assert_fail("%d loops repeat texture loads (potential duplicate-sprite bug)" % hits.size(), "see findings")
		for h in hits:
			_record("MEDIUM", h.file, h.line, h.msg)


func _analyze_loop_body(path: String, line: int, body: Array, hits: Array) -> void:
	# Count load() / preload() calls of the same path inside the loop body
	var texture_loads: Dictionary = {}  # path -> count
	for entry in body:
		var t: String = entry.text
		var rx_load := RegEx.new()
		rx_load.compile('(load|preload)\\("([^"]+\\.(png|tres|svg))"\\)')
		var m := rx_load.search(t)
		if m:
			var tex_path: String = m.get_string(2)
			texture_loads[tex_path] = texture_loads.get(tex_path, 0) + 1
	for tex in texture_loads:
		if texture_loads[tex] >= 2:
			hits.append({
				"file": path, "line": line,
				"msg": "loop loads %s %d times — extract to const or cache before loop" % [tex, texture_loads[tex]],
			})


## Detects card_hand.gd LOCKED-state pattern where multiple labels are added at
## the same position regardless of lock state (BUG-45).
func _check_locked_card_overlap_pattern() -> void:
	# HUD-align retarget (2026-07-11): the reference locked card is a dark slate box with a
	# red ✕ + "LOCKED" + "Need: X". Assert that treatment (reverses the P1 padlock).
	print("[Locked card slate + red-X + LOCKED treatment (HUD-align)]")
	var path: String = "res://scripts/ui/card_hand.gd"
	var content := _read_file(path)
	if content.is_empty():
		_assert_pass("card_hand.gd not present (skipped)")
		return
	var has_locked_text: bool = false
	for ln in content.split("\n"):
		if ln.contains("draw_string") and ln.contains('"LOCKED"'):
			has_locked_text = true
			break
	var has_slate: bool = content.contains("_slate_style")
	var has_x: bool = content.contains("_x_tex") and content.contains("draw_texture_rect(_x_tex")
	if has_locked_text and has_slate and has_x:
		_assert_pass("locked cards use slate box + red ✕ + LOCKED (reference)")
	else:
		_assert_fail("locked-card reference treatment missing (LOCKED=%s slate=%s X=%s)" % [has_locked_text, has_slate, has_x],
			"draw slate box + _x_tex + \"LOCKED\" on the not-_has_prereq branch")
		_record("MED", path, 1, "HUD-align — locked-card slate/X/LOCKED treatment incomplete")


## Detects progress bar construction that adds wood-plank textures multiple times
## (BUG-43 — 3 detached planks instead of one stretched NinePatch).
func _check_progress_bar_construction() -> void:
	print("[Progress bar single-NinePatch (BUG-43)]")
	var path: String = "res://scripts/ui/loading_screen.gd"
	var content := _read_file(path)
	if content.is_empty():
		_assert_pass("loading_screen.gd not present (skipped)")
		return
	var lines := content.split("\n")
	# Count BigBar texture loads
	var big_bar_loads: int = 0
	var add_child_count_in_func: Dictionary = {}  # func_name -> int
	var current_func: String = ""
	for ln in lines:
		var stripped: String = ln.strip_edges()
		var rx_func := RegEx.new()
		rx_func.compile('^func\\s+(\\w+)')
		var m := rx_func.search(stripped)
		if m:
			current_func = m.get_string(1)
		if stripped.contains("BigBar"):
			big_bar_loads += 1
		if stripped.contains("add_child(") and current_func != "" and current_func.contains("progress"):
			add_child_count_in_func[current_func] = add_child_count_in_func.get(current_func, 0) + 1
	# Heuristic: progress bar can be (a) NinePatchRect + Fill (2 children), or
	# (b) StyleBox-styled Panel + Fill + a few rivet/decoration stamps (~5 max).
	# Above 6 children is suspicious — likely a loop instantiating the trough
	# texture multiple times across the bar's length (the BUG-43 root cause).
	var found_issue: bool = false
	for fn in add_child_count_in_func:
		if add_child_count_in_func[fn] > 6:
			_assert_fail("%s adds %d children (progress bar likely has duplicate trough/plank instances)" % [fn, add_child_count_in_func[fn]],
				"check for repeated TextureRect.add_child inside a loop")
			_record("HIGH", path, 0, "BUG-43 — %s adds %d children" % [fn, add_child_count_in_func[fn]])
			found_issue = true
	if not found_issue:
		_assert_pass("progress bar construction within reasonable child count")


## BUG-43 RE-OPEN: pixel-continuity check on the loading bar.
## Loads `/tmp/castle_clash_test/loading_000.png` (last autotest capture, 504×896
## BUG-43: the loading bar must read as ONE continuous piece, not detached planks.
## RECALIBRATED 2026-07-17 — the previous version sampled y=648 (43px ABOVE the
## bar, which lives at design y=990..1062 per loading_screen.gd bar_y=990/h=72),
## found ZERO wood runs and passed that as "continuous": a vacuous green
## (lessons.md "silent green" class). Now resolution-aware (works at 504x896 and
## 720x1280) and ZERO runs = FAIL, never a pass. Calibrated by scanning the real
## 504x896 capture: trough rows 715-725 give one wood|fill run x=162..344
## (~182px vs 188 expected). Bar CONTENT = wood frame | red fill | bright shine
## (the sweep can carve a >8px near-white gap in the fill mid-animation).
func _check_progress_bar_pixel_continuity() -> void:
	print("[Progress bar pixel continuity (BUG-43 pixel-level)]")
	var img := _load_capture("loading_000.png")
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var sx: float = w / 720.0
	var expected_w: int = roundi(269.0 * sx)  # design bar_w = 269
	var min_w: int = int(expected_w * 0.75)
	var x_start: int = roundi(160.0 * sx)
	var x_end: int = roundi(560.0 * sx)
	var bad_rows: int = 0
	var row_reports: Array = []
	# Trough-band rows, clear of the fill's dark top seam (design ~1018-1022
	# scans as outline, not content — measured on the 504x896 capture).
	for y_design in [1024.0, 1029.0, 1034.0]:
		var y_sample: int = roundi(y_design * h / 1280.0)
		var runs: Array = []
		var in_bar: bool = false
		var run_start: int = -1
		for x in range(x_start, x_end):
			var c: Color = img.get_pixel(x, y_sample)
			var is_wood: bool = c.r > c.g and c.r > 0.25 and c.r < 0.75 and c.b < 0.5
			var is_fill: bool = c.r > 0.59 and c.g < 0.39 and c.b < 0.39
			# Shine sweep: bright + near-neutral (grass is green-dominant with
			# channel spread > 0.25, so it stays background).
			var spread: float = maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var is_shine: bool = c.r > 0.6 and c.g > 0.5 and spread < 0.25
			var is_content: bool = is_wood or is_fill or is_shine
			if is_content and not in_bar:
				in_bar = true
				run_start = x
			elif not is_content and in_bar:
				in_bar = false
				runs.append({"start": run_start, "end": x - 1})
		if in_bar:
			runs.append({"start": run_start, "end": x_end - 1})
		# Coalesce runs separated by <8px (anti-alias artifacts only)
		var merged: Array = []
		for r in runs:
			if merged.size() > 0 and r.start - merged[-1].end < 8:
				merged[-1].end = r.end
			else:
				merged.append({"start": r.start, "end": r.end})
		var main_w: int = 0
		for m in merged:
			main_w = maxi(main_w, m.end - m.start)
		row_reports.append("y=%d runs=%d main=%dpx" % [y_sample, merged.size(), main_w])
		if merged.size() != 1 or main_w < min_w:
			bad_rows += 1
			for i in merged.size():
				_record("HIGH", "loading_000.png", y_sample,
					"bar run #%d: x=%d..%d (width %d)" % [i + 1, merged[i].start, merged[i].end, merged[i].end - merged[i].start])
	if bad_rows == 0:
		_assert_pass("loading bar continuous at all 3 trough rows (%s; min %dpx)" % [", ".join(PackedStringArray(row_reports)), min_w])
	else:
		_assert_fail("loading bar broken or missing on %d/3 trough rows (%s)" % [bad_rows, ", ".join(PackedStringArray(row_reports))],
			"BUG-43 — detached planks OR bar not at design y 1020-1034 (0 runs = stale calibration, not a pass)")


## BUG-32: roof icons on upgraded buildings must be READABLE at game scale.
## The autotest build order places a gryphon_roost (wing icon) and dumps its
## grid coords to game_state.json; this detector converts grid→capture px.
## Autotest runs OFFLINE and UNFLIPPED, so player-0 uses the direct mapping
## x = 206 + gx*28, y = 695 + gy*28 (grid_to_screen's first branch — NOT the
## T-085 flipped formula). Building 2x2 → center +28; icon at center
## + (0, -height*0.30) = -15.6 (see sprite_building_visual.gd).
## and counts icon-signature pixels in the icon window: pale-cyan wing art
## (wing_icon.png opaque mean RGB ≈ (198,228,228)). The dark backing is NOT a
## detector signal — the building's own outline pixels measure ~137 dark px
## either way, so only the pale count discriminates. Calibrated 2026-07-17 on
## game_010.png @504x896 via git-stash controlled baseline: pre-fix build =
## 16 pale px (22px icon — the user's "barely visible" complaint), fixed
## build (44px + dark backing) = 60. Bar at 30: two-sided margins 14/30.
func _check_roof_icon_visibility() -> void:
	print("[Roof icon visibility (BUG-32 pixel-level)]")
	var img := _load_capture("game_010.png")
	if img == null:
		return
	# Locate the roost from the state dump — placement can drift if the build
	# order changes, so never hardcode the grid slot.
	var state_path := _cap("game_state.json")
	if not FileAccess.file_exists(state_path):
		_assert_fail("game_state.json missing from capture run", "auto_screenshot dumps it at end of the game phase")
		return
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	var roost: Dictionary = {}
	for b in state.get("buildings", []):
		if b.get("type", "") == "gryphon_roost" and int(b.get("team", -1)) == 0:
			roost = b
			break
	if roost.is_empty():
		_assert_fail("no player-0 gryphon_roost in the capture run",
			"auto_screenshot build order must place one (BUG-32 detector support)")
		return
	var gx: int = int(roost.get("grid_x", -1))
	var gy: int = int(roost.get("grid_y", -1))
	if gx < 0 or gy < 0:
		_assert_fail("gryphon_roost dumped without grid coords", "state dump must include grid_x/grid_y")
		return
	var sx: float = img.get_width() / 720.0
	var sy: float = img.get_height() / 1280.0
	# Building visual center (2x2 footprint, unflipped player-0 zone), icon
	# 30% of height (52) above it → icon center ≈ center - 15.6 design px.
	var cx: float = (206.0 + gx * 28.0 + 28.0) * sx
	var cy: float = (695.0 + gy * 28.0 + 28.0 - 15.6) * sy
	var half: int = roundi(24.0 * sx)  # window covers the 44px icon + backing rim
	var pale: int = 0
	var dark: int = 0
	for y in range(int(cy) - half, int(cy) + half + 1):
		for x in range(int(cx) - half, int(cx) + half + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c: Color = img.get_pixel(x, y)
			if c.g > 0.78 and c.b > 0.78 and c.r < 0.88 and c.g > c.r:
				pale += 1
			elif (c.r + c.g + c.b) < 0.42:
				dark += 1
	if pale >= 30:
		_assert_pass("roost wing icon readable (pale=%d px in icon window; dark=%d informational)" % [pale, dark])
	else:
		_assert_fail("roof icon invisible at game scale — pale=%d px (need ≥30; pre-fix baseline 16)" % pale,
			"BUG-32 — icon target px too small (sprite_building_visual.gd)")


## BUG-50: the gray "occupied" overlay must mark the SAME rows the building
## visual occupies, for every (player, view_flipped) combination. User report:
## a red-zone building drew its occupied tiles at different coordinates.
## Root cause: building_grid._visual_row() inverted rows for player_index==1
## UNCONDITIONALLY, while grid_to_screen (game_arena.gd) inverts only when
## view_flipped — so in offline (unflipped) view the enemy overlay was drawn
## row-mirrored under correctly-placed building visuals. Headless layout-layer
## invariant (PROCESS §5): instance building_grid.gd, compare its drawn row set
## against the grid_to_screen row band (formula mirrored here).
func _check_occupancy_overlay_mapping() -> void:
	print("[Occupancy overlay row mapping (BUG-50 invariant)]")
	var script = load("res://scripts/game/building_grid.gd")
	var grid: Node2D = Node2D.new()
	grid.set_script(script)
	var rows: int = grid.GRID_ROWS
	var mismatches: Array = []
	for flipped in [false, true]:
		for p_idx in [0, 1]:
			grid.player_index = p_idx
			grid.set("view_flipped", flipped)  # no-op pre-fix (property absent) → RED
			for h in [1, 2]:               # 1-cell walls and 2x2 buildings
				for r in range(0, rows - h + 1):
					# Overlay: the set of visual rows _visual_row maps the
					# occupied sim rows onto.
					var drawn: Array = []
					for i in h:
						drawn.append(grid._visual_row(r + i))
					drawn.sort()
					# Building visual: grid_to_screen's row band (game_arena.gd
					# 345-356): direct rows unflipped, (rows - r - h) top when flipped.
					var band_top: int = r if not flipped else (rows - r - h)
					var expect: Array = []
					for i in h:
						expect.append(band_top + i)
					if drawn != expect:
						mismatches.append("p%d flip=%s r=%d h=%d drawn=%s expect=%s"
							% [p_idx, flipped, r, h, str(drawn), str(expect)])
	grid.free()
	if mismatches.is_empty():
		_assert_pass("overlay rows match building-visual rows for all (player, flip, row, size)")
	else:
		_assert_fail("BUG-50 — occupied-tile rows diverge from building visual in %d cases (e.g. %s)"
			% [mismatches.size(), mismatches[0]],
			"building_grid._visual_row must invert iff view_flipped, matching grid_to_screen")


## Detects tip strip / NinePatch edge artifacts (BUG-44).
func _check_tip_strip_construction() -> void:
	print("[Tip strip NinePatch usage (BUG-44)]")
	var path: String = "res://scripts/ui/loading_screen.gd"
	var content := _read_file(path)
	if content.is_empty():
		_assert_pass("loading_screen.gd not present (skipped)")
		return
	# Heuristic: check that RegularPaper / SpecialPaper / parchment textures are
	# used via NinePatchRect (not raw TextureRect, which doesn't stretch edges).
	var lines := content.split("\n")
	var paper_uses: Array = []
	for i in lines.size():
		var ln: String = lines[i]
		if ln.contains("Paper") and (ln.contains("load(") or ln.contains("preload(")):
			# Look at next 10 lines for NinePatchRect usage
			var found_ninepatch: bool = false
			for j in range(i, mini(lines.size(), i + 10)):
				if lines[j].contains("NinePatchRect"):
					found_ninepatch = true
					break
			paper_uses.append({"line": i + 1, "ninepatch": found_ninepatch, "snippet": ln.strip_edges()})
	if paper_uses.is_empty():
		_assert_pass("no parchment textures loaded (skipped)")
		return
	var bad: Array = []
	for u in paper_uses:
		if not u.ninepatch:
			bad.append(u)
	if bad.is_empty():
		_assert_pass("all parchment loads followed by NinePatchRect")
	else:
		_assert_fail("%d parchment textures may be used via raw TextureRect (NinePatch edge bug)" % bad.size(),
			"BUG-44 risk")
		for b in bad:
			_record("MEDIUM", path, b.line, "BUG-44 — %s :: no NinePatchRect within 10 lines" % b.snippet)


# --- Phase-1 pixel detectors for outstanding visual bugs ---
# Each detector is "is the bug visible in the latest --autotest capture?"
# Calibrated against menu_battle_000.png (504×896) on the buggy build 2026-04-18.
# Per QA gate: a bug cannot be moved to DONE until its detector flips PASS.

const MENU_CAPTURE: String = "menu_battle_000.png"


## BUG-46: Chimney smoke renders as horizontal LINE of small light puffs at the
## same Y instead of vertical columns rising from chimneys. Calibrated cluster
## centers on buggy build (2026-04-18): y=525-535, X centers ≈ [220, 227, 238,
## 268, 279] = 5 puffs in a 60-px horizontal band.
##
## PASS rule: at any single Y-row in the puff zone (y=510-560) there should be
## NO row containing >= 4 small (2-12 px wide) bright-non-green clusters whose
## X centers all sit within a 100-px horizontal band. That pattern means puffs
## are aligned in a row instead of rising vertically.
func _check_chimney_smoke_vertical() -> void:
	print("[Chimney smoke vertical (BUG-46 pixel)]")
	var img := _load_capture(MENU_CAPTURE)
	if img == null:
		return
	var w: int = img.get_width()
	var max_clusters: int = 0
	var max_y: int = -1
	var max_centers: Array = []
	for y in range(510, 565):
		var clusters := _find_bright_nongreen_clusters(img, y, w)
		if clusters.size() < 3:
			continue
		# Filter to 2-12 px wide (puff-sized, not larger sprites)
		var puffs: Array = []
		for c in clusters:
			var width: int = c.end - c.start + 1
			if width >= 2 and width <= 12:
				puffs.append((c.start + c.end) / 2)
		if puffs.size() < 3:
			continue
		# Within how tight an X-band do these puffs sit?
		var span: int = puffs[-1] - puffs[0]
		if puffs.size() >= 4 and span <= 120:
			if puffs.size() > max_clusters:
				max_clusters = puffs.size()
				max_y = y
				max_centers = puffs
	if max_clusters == 0:
		_assert_pass("no horizontal puff-line pattern in y=510-565")
	else:
		_assert_fail("BUG-46 — %d puffs aligned at y=%d within a %d-px X band" %
			[max_clusters, max_y, max_centers[-1] - max_centers[0]],
			"chimney smoke should rise vertically, not array horizontally")
		_record("HIGH", MENU_CAPTURE, max_y,
			"BUG-46 — puff X-centers: %s" % str(max_centers))


## BUG-47: Tree foliage z-clips through cottage spire silhouette on the left
## side. Calibrated on buggy build (2026-04-18): scanning the left scenic strip
## (x=0-250, y=140-340) shows multiple Y rows where green-foliage and gray-spire
## pixels co-exist in the same row at >30 px each — a "sandwich" pattern only
## possible when foliage and building lack consistent z-ordering.
##
## PASS rule: at most ONE Y row in the left scenic strip may have both
## green > 30 AND gray > 30 simultaneously. (The cottage roof apex is one
## legitimate row of mixing; multi-row mixing means trees pass through.)
## BUG-48: Top-right corner shows 3 identical fence sprites in a row at evenly
## spaced X. Calibrated on buggy build (2026-04-18): y=160-180, brown-wood
## clusters at x=[470, 488, 497] in the top-right region (x=320..504).
##
## PASS rule: in the top-right scenic region (x>=300, y=120..220) no Y row may
## contain >= 3 wood-color clusters spaced within 30 px of each other (an
## evenly-spaced row of repeated decorations is the BUG-48 signature).
func _check_fence_row_repetition() -> void:
	print("[Fence row repetition (BUG-48 pixel)]")
	var img := _load_capture(MENU_CAPTURE)
	if img == null:
		return
	var w: int = img.get_width()
	var hits: Array = []
	for y in range(120, 220):
		var clusters: Array = []
		var in_c: bool = false
		var run_start: int = -1
		for x in range(300, w):
			var c: Color = img.get_pixel(x, y)
			var is_wood: bool = c.r > c.g and c.g > c.b and c.r > 0.39 and c.r < 0.78 and c.b < 0.39
			if is_wood and not in_c:
				in_c = true
				run_start = x
			elif not is_wood and in_c:
				in_c = false
				if x - run_start >= 2:
					clusters.append((run_start + x - 1) / 2)
		if in_c:
			clusters.append((run_start + w - 1) / 2)
		if clusters.size() >= 3:
			# Check pairwise gaps — is this a regular row?
			var max_gap: int = 0
			for i in range(clusters.size() - 1):
				var g: int = clusters[i + 1] - clusters[i]
				if g > max_gap:
					max_gap = g
			if max_gap <= 30:
				hits.append({"y": y, "centers": clusters, "max_gap": max_gap})
	if hits.is_empty():
		_assert_pass("no evenly-spaced wood/fence row in top-right scenic strip")
	else:
		_assert_fail("BUG-48 — %d rows show 3+ evenly-spaced wood clusters" % hits.size(),
			"likely a `for x in range(...): add_child(fence)` loop")
		var first: Dictionary = hits[0]
		_record("MEDIUM", MENU_CAPTURE, first.y,
			"BUG-48 — y=%d centers=%s max_gap=%dpx" % [first.y, str(first.centers), first.max_gap])


## BUG-49 (RECALIBRATED 2026-07-18): originally "partial ribbons clipped at
## screen edges". The old rule flagged ANY decoration pixels in the edge
## columns — but the CURRENT approved design is full-bleed on purpose: the
## header bar spans edge-to-edge, parallax clouds drift across the frame, the
## side groves and plateau bleed off-frame exactly like the approved loading
## screen and the v2/v3 reference mockups. Its 30 quarantined hits were all
## intended composition (verified by edge-strip crops 2026-07-18); the actual
## floating-ribbon artifact was removed in the P2 redesign. The invariant kept:
## no RIBBON/BANNER-family art (saturated red or gold, the Tiny Swords ribbon
## palette) may sit half-clipped at an edge OUTSIDE the header band (y<130).
func _check_ribbon_edge_clipping() -> void:
	print("[Edge-clipped ribbons (BUG-49 pixel)]")
	var img := _load_capture(MENU_CAPTURE)
	if img == null:
		return
	var h: int = img.get_height()
	var w: int = img.get_width()
	var hits: Array = []
	for y0 in range(130, h - 80, 40):
		var y1: int = y0 + 80
		var left: int = 0
		var right: int = 0
		for y in range(y0, y1):
			for x in range(0, 16):
				if _is_ribbon_pixel(img.get_pixel(x, y)):
					left += 1
			for x in range(w - 16, w):
				if _is_ribbon_pixel(img.get_pixel(x, y)):
					right += 1
		if left > 60:
			hits.append({"side": "LEFT", "y0": y0, "y1": y1, "px": left})
		if right > 60:
			hits.append({"side": "RIGHT", "y0": y0, "y1": y1, "px": right})
	if hits.is_empty():
		_assert_pass("no ribbon/banner art clipped at screen edges (below header)")
	else:
		_assert_fail("BUG-49 — %d edge-clipped ribbon zones" % hits.size(),
			"a ribbon/banner sits half-outside the viewport")
		for h_entry in hits.slice(0, 4):
			_record("LOW", MENU_CAPTURE, h_entry.y0,
				"BUG-49 — %s edge y=%d-%d ribbon_px=%d" %
				[h_entry.side, h_entry.y0, h_entry.y1, h_entry.px])


## Tiny Swords ribbon/banner palette: saturated red (Ribbon_Red family) or
## warm gold (Ribbon_Yellow) — distinct from foliage, sky, wood and grass.
func _is_ribbon_pixel(c: Color) -> bool:
	var is_red: bool = c.r > 0.62 and c.r > c.g + 0.28 and c.b < 0.35
	var is_gold: bool = c.r > 0.75 and c.g > 0.55 and c.g < c.r - 0.08 and c.b < 0.30
	return is_red or is_gold


## BUG-51: Battle tab button is permanently styled as active (gold + lifted)
## instead of only-when-selected. Calibrated 2026-04-21 on the menu_army_000.png
## capture (Army is selected): Battle tab has ~395 gold pixels while Army has
## 0 gold. Source: `_apply_center_tab_emphasis` in main_menu.gd:982 applies the
## lift + gold ring once on _ready and never removes them when switching tabs.
##
## PASS rule: in a non-Battle tab capture, Battle tab slice (x=200..300 of tab
## bar y=815..890) must have fewer gold pixels than the max across the four
## NON-active tabs + a small margin. In other words Battle shouldn't dominate
## when it's not the active tab.
func _check_battle_tab_always_lifted() -> void:
	print("[Battle tab always lifted/gold (BUG-51 pixel)]")
	var img := _load_capture("menu_army_000.png")
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	# Tab bar at bottom ~10% of screen
	var y0: int = int(h * 0.91)
	var y1: int = int(h * 0.994)
	var tab_slices: Array = []
	for i in range(5):
		var sx0: int = int(w * (float(i) / 5.0))
		var sx1: int = int(w * (float(i + 1) / 5.0))
		var gold: int = 0
		for y in range(y0, y1):
			for x in range(sx0, sx1):
				var c: Color = img.get_pixel(x, y)
				if c.r > 0.59 and c.g > 0.39 and c.b < 0.39 and c.r > c.b + 0.27:
					gold += 1
		tab_slices.append({"idx": i, "gold": gold})
	var battle_gold: int = tab_slices[2].gold
	var non_battle_gold: Array = []
	for i in range(5):
		if i != 2:
			non_battle_gold.append(tab_slices[i].gold)
	non_battle_gold.sort()
	var max_non_battle: int = non_battle_gold[-1] if non_battle_gold.size() > 0 else 0
	# Battle is permanently gold if it has >80 gold px AND dominates the others
	if battle_gold > 80 and battle_gold > max_non_battle + 60:
		_assert_fail("BUG-51 — Battle tab has %d gold px vs max non-Battle %d on army_tab capture" % [battle_gold, max_non_battle],
			"Battle tab styled as always-active; `_apply_center_tab_emphasis` at main_menu.gd:982 needs conditional application")
		_record("HIGH", "menu_army_000.png", y0,
			"BUG-51 — gold_px per tab: Shop=%d Army=%d Battle=%d Social=%d Settings=%d" %
			[tab_slices[0].gold, tab_slices[1].gold, tab_slices[2].gold, tab_slices[3].gold, tab_slices[4].gold])
	else:
		_assert_pass("Battle tab not permanently styled (gold %d ~ comparable to others)" % battle_gold)


## BUG-52: Non-Battle tabs show scenic background + Battle panel content bleeding
## through the translucent tab panel. Calibrated 2026-04-21: army tab edge bands
## (leftmost 30 px + rightmost 30 px, y=150..770) contain ~330 grass + ~200 stone
## pixels on left; 1584 grass + 1353 stone on right. The scenic SceneLayer is
## added at root z-index 0 and panels only have 88% alpha — so buildings + grass
## leak through. Also Battle's "BATTLE" text + "(1v1)" button visibly bleed.
##
## PASS rule: non-Battle tab edge bands (first/last 30 px, y=150-770) must not
## contain more than 150 grass+stone palette pixels combined. Anything higher
## indicates scenic bleed-through.
func _check_non_battle_tab_scenic_bleed() -> void:
	print("[Non-Battle tab scenic bleed-through (BUG-52 pixel)]")
	var img := _load_capture("menu_army_000.png")
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var y0: int = int(h * 0.17)
	var y1: int = int(h * 0.86)
	var band_w: int = 30
	var left_scenic: int = 0
	var right_scenic: int = 0
	for y in range(y0, y1):
		for x in range(band_w):
			if _is_scenic_palette(img.get_pixel(x, y)):
				left_scenic += 1
			if _is_scenic_palette(img.get_pixel(w - 1 - x, y)):
				right_scenic += 1
	var threshold: int = 150
	if left_scenic > threshold or right_scenic > threshold:
		_assert_fail("BUG-52 — scenic palette pixels leak into army tab edges: left=%d right=%d (threshold %d)" %
			[left_scenic, right_scenic, threshold],
			"`_build_scenic_background` at main_menu.gd:636 stays visible under all tabs; non-Battle tabs need opaque backgrounds OR hide scenic when not on Battle")
		_record("HIGH", "menu_army_000.png", y0,
			"BUG-52 — grass+stone bleed: L=%d R=%d y=%d-%d band=30px" % [left_scenic, right_scenic, y0, y1])
	else:
		_assert_pass("non-Battle tab edges have clean UI background (L=%d R=%d)" % [left_scenic, right_scenic])


func _is_scenic_palette(c: Color) -> bool:
	# Grass green: g > r by margin, g > 0.31
	if c.g > c.r + 0.059 and c.g > 0.31:
		return true
	# Blue-gray stone (cold, R≈G≈B in low-mid range, slight blue tint)
	if c.b > c.r and absf(c.g - c.b) < 0.12 and c.r > 0.24 and c.r < 0.63:
		return true
	return false


# --- Arena composition-parity suite (design-flow.md) ---
# Spec: design/arena_target.png (approved 2026-07-08), capture-res twin
# design/arena_target_capture_res.png. Calibrated 2026-07-08 on 504x896 captures
# (0.7x of 720x1280 design space). RED-verified against the pre-port build:
# water (28,85,93) tinted, castle 96px, no towers, coastline at x=28.

const ARENA_CAPTURE: String = "game_002.png"


## Grass/foliage family: green dominant, blue clearly below green.
func _arena_is_green(c: Color) -> bool:
	return c.g > 0.35 and c.g > c.r and (c.g - c.b) > 0.15


## Native Tiny Swords water teal (71,171,169)/255 = (0.28,0.67,0.66).
func _arena_is_teal(c: Color) -> bool:
	return c.b > 0.45 and absf(c.g - c.b) < 0.12 and c.g > c.r + 0.15


## Tiny Swords cliff/elevation STONE: cool blue-gray, R≈G≈B in the low-mid band,
## blue not below red, and clearly not grass. (matches Tilemap_color1 cols 5-8
## rows 4-5, the stone cliff face.)
func _arena_is_stone(c: Color) -> bool:
	var avg: float = (c.r + c.g + c.b) / 3.0
	return absf(c.r - c.g) < 0.12 and absf(c.g - c.b) < 0.18 \
		and avg > 0.24 and avg < 0.71 and c.b >= c.r - 0.05 \
		and not (c.g > c.r + 0.09 and c.g > c.b + 0.06)


## Water must be the NATIVE pack teal — no modulate tint. The old build multiplied
## (71,171,169) by (0.4,0.5,0.55) → (28,85,93), a murky near-black gutter.
func _check_arena_water_native() -> void:
	print("[Arena water native teal (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	# Sample well inside the water bands (design x<72 → capture x<50, both sides).
	var samples := [Vector2i(12, 300), Vector2i(12, 500), Vector2i(492, 350), Vector2i(492, 550)]
	var bad: int = 0
	var worst := ""
	for p in samples:
		var c: Color = img.get_pixel(p.x, p.y)
		var dr: float = absf(c.r - 71.0 / 255.0)
		var dg: float = absf(c.g - 171.0 / 255.0)
		var db: float = absf(c.b - 169.0 / 255.0)
		if dr > 0.14 or dg > 0.14 or db > 0.14:
			bad += 1
			worst = "(%d,%d)=(%d,%d,%d)" % [p.x, p.y, c.r8, c.g8, c.b8]
	if bad == 0:
		_assert_pass("water bands are native teal (71,171,169) at all 4 samples")
	else:
		_assert_fail("arena water tinted off native palette — %d/4 samples off, e.g. %s" % [bad, worst],
			"expected ~(71,171,169); remove modulate tints on water layers")


## Castle must render at mockup scale: red-roof bbox ≥160px wide in the top strip
## (target: ~197px capture; pre-port build: ~96px).
func _check_arena_castle_scale() -> void:
	print("[Arena castle scale (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	# Largest CONTIGUOUS red-roof run on any single row (gaps ≤8px bridged) —
	# a global bbox would false-pass on scattered small red-roofed buildings
	# (pre-port build measured a 343px bbox from grid houses vs a 96px castle).
	# Scan starts at y=34 — BELOW the top HUD ribbon (capture y 0..30), whose
	# red-leather texture otherwise reads as a full-width "roof" (false PASS).
	var best_run: int = 0
	for y in range(34, 170):
		var run: int = 0
		var gap: int = 99
		var cur: int = 0
		for x in range(100, 404):
			var c: Color = img.get_pixel(x, y)
			# Tiny Swords red roof family: strong red, muted green/blue
			if c.r > 0.55 and c.r > c.g + 0.25 and c.b < 0.40:
				if gap > 8:
					cur = 0
				cur += 1 + mini(gap, 8) if cur > 0 else 1
				gap = 0
			else:
				gap += 1
			run = maxi(run, cur)
		best_run = maxi(best_run, run)
	# Calibrated band (recalibrated 2026-07-08b — castle 0.544 = 0.68 x0.8 after
	# user feedback that placed buildings overlapped the castle body):
	# spec = 0.544 native = 170px design = ~119px capture. Two-sided so the scale
	# can neither shrink back to the old 94px nor balloon to 148px+ again.
	if best_run >= 105 and best_run <= 135:
		_assert_pass("enemy castle red-roof run %dpx in calibrated band 105..135 (0.544 native)" % best_run)
	else:
		_assert_fail("enemy castle off calibrated scale — red-roof run %dpx outside 105..135" % best_run,
			"spec 0.296x0.8 of playfield width = ~119px capture (design/arena_target.png)")


## CASTLE-CLIFF (user-flagged 2026-07-11, ref design/references/v1.png red castle):
## each castle must sit on an INTEGRATED stone cliff band directly under its south
## front (compose_arena.py cliff_base → game_arena.gd _add_fortress_dressing). The
## detector window is the enemy castle's cliff FACE, clear of the castle's own gray
## foundation (which ends ~cap y115) so the no-cliff baseline is pure grass — capture
## x[188,316] y[116,138] (calibrated 2026-07-14 by scanning game_000/002.png @504x896).
## Pre-cliff build: 0 stone px (grass). With the cliff: substantial stone (~600+, run
## full-width). Assert a SUBSTANTIAL + CONTINUOUS band so a stray rock can't false-pass.
## NB: the cliff sits ~31px higher than the compositor target because castle_visual.gd
## renders the castle above compose_arena.py's CASTLE_CENTERS (see game_arena.gd
## _add_fortress_dressing) — this window tracks the GAME render, not the target.
func _check_arena_castle_cliff() -> void:
	print("[Arena castle cliff base (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var wx0: int = 188
	var wx1: int = 316
	var wy0: int = 116
	var wy1: int = 138
	var total: int = 0
	var best_run: int = 0
	for y in range(wy0, wy1):
		var run: int = 0
		var gap: int = 99
		var cur: int = 0
		for x in range(wx0, wx1):
			if _arena_is_stone(img.get_pixel(x, y)):
				total += 1
				cur = cur + 1 + mini(gap, 6) if cur > 0 else 1
				gap = 0
			else:
				gap += 1
				if gap > 6:
					cur = 0
			run = maxi(run, cur)
		best_run = maxi(best_run, run)
	# Calibrated on the real captures (2026-07-14): pre-cliff build total=0 (grass, RED);
	# cliff build total≈600+ run full-width (GREEN). The stone px count is the load-
	# bearing signal (a stray rock is <200px here); the run asserts lateral extent.
	# Bar = 400 px / 60 px run — clean separation from the 0 baseline.
	if total >= 400 and best_run >= 60:
		_assert_pass("integrated cliff band under enemy castle (stone px=%d, run=%dpx)" % [total, best_run])
	else:
		_assert_fail("no integrated cliff band under enemy castle — stone px=%d run=%dpx (need ≥400 & ≥60px)" % [total, best_run],
			"stone cliff FACE directly under the castle foot per design/arena_target.png (cliff_base)")


## Decorative fortress towers must flank the castle at design (140,268)/(580,268)
## → capture windows around (98,150)/(406,150). Structure = non-green, non-teal,
## non-dark pixels (cream walls / red roofs), ≥250 px per window.
func _check_arena_fortress_towers() -> void:
	print("[Arena fortress towers (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var windows := [Rect2i(76, 96, 44, 92), Rect2i(384, 96, 44, 92)]
	var counts: Array = []
	for wrect in windows:
		var n: int = 0
		for y in range(wrect.position.y, wrect.position.y + wrect.size.y):
			for x in range(wrect.position.x, wrect.position.x + wrect.size.x):
				var c: Color = img.get_pixel(x, y)
				if not _arena_is_green(c) and not _arena_is_teal(c) and (c.r + c.g + c.b) > 0.9:
					n += 1
		counts.append(n)
	if counts[0] >= 250 and counts[1] >= 250:
		_assert_pass("fortress towers present both flanks (structure px L=%d R=%d)" % [counts[0], counts[1]])
	else:
		_assert_fail("fortress towers missing — structure px L=%d R=%d (need ≥250 each)" % [counts[0], counts[1]],
			"decorative Tower.png at design (140,268)/(580,268) per arena_target.png")


## The grass platform edge must sit at design x=72 (capture x≈50), not the old
## full-bleed rectangle at design x=40 (capture x=28).
func _check_arena_coastline_platform() -> void:
	print("[Arena coastline platform edge (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	# Rows chosen CLEAR of the left tree clusters, of the fortress wall/houses,
	# AND (3.3b) of the side plateau (design y[328,712], whose coast edge is
	# elevation stone, not grass): design y = 243, 750, 900.
	var edges: Array = []
	for y in [170, 525, 630]:
		var first_green: int = -1
		for x in range(0, 200):
			if _arena_is_green(img.get_pixel(x, y)):
				first_green = x
				break
		edges.append(first_green)
	var ok: bool = true
	for e in edges:
		if e < 42 or e > 62:
			ok = false
	if ok:
		_assert_pass("platform edge at capture x=%s (target 50±6 incl. edge-tile fringe)" % str(edges))
	else:
		_assert_fail("platform edge off-spec — first grass x=%s per row (want 44..62)" % str(edges),
			"grass platform must start at design x=72 with edge tiles, water outside")


## No foliage floating in the water: green tree/bush pixels must stay within
## a small overhang band of the island rim. Catches BOTH deep over-water
## canopies AND disconnected sprite fragments (the Tree1/2 square-crop bug that
## bled a sliver of the next animation frame — user-reported "cropped trees",
## 2026-07-10). Rim at design x=72/648 → capture 50/453; allowance 17px.
func _check_arena_no_floating_foliage() -> void:
	print("[Arena no floating foliage (design-flow parity)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	# Intentional water decor is exempt: LAYOUT water-rock spots (mossy green
	# tops read as "foliage"). Capture-space centers of the 16 mirrored rocks
	# (3.3b: WROCK_L grew to 4 authored spots → 16 after 4-way mirroring).
	var wrock_boxes: Array = []
	for d in [[28, 210], [24, 329], [476, 210], [480, 329],
			[28, 518], [24, 399], [476, 518], [480, 399],
			[27, 118], [477, 118], [27, 610], [477, 610],
			[25, 448], [479, 448], [25, 280], [479, 280]]:
		wrock_boxes.append(Rect2i(d[0] - 14, d[1] - 14, 28, 28))
	# Rubber-duck easter egg: pinned at design (36,500), drifts x+8/bob y±4 —
	# its yellow-green shading reads as "foliage". Exempt the drift envelope.
	wrock_boxes.append(Rect2i(9, 334, 32, 32))
	var bad_l: int = 0
	var bad_r: int = 0
	var worst := ""
	for y in range(40, 680):
		for x in range(0, 33):  # left water beyond 17px overhang (50-17=33)
			if _arena_is_green(img.get_pixel(x, y)) and not _in_any_box(wrock_boxes, x, y):
				bad_l += 1
				worst = "(%d,%d)" % [x, y]
		for x in range(471, 504):  # right water beyond overhang (453+17+1)
			if _arena_is_green(img.get_pixel(x, y)) and not _in_any_box(wrock_boxes, x, y):
				bad_r += 1
				worst = "(%d,%d)" % [x, y]
	if bad_l + bad_r <= 12:  # tolerate a few anti-aliased/foam-adjacent pixels
		_assert_pass("no floating foliage in water (L=%d R=%d stray px)" % [bad_l, bad_r])
	else:
		_assert_fail("foliage floating in water — L=%d R=%d px beyond the rim band, e.g. %s" % [bad_l, bad_r, worst],
			"tree canopies must stay within 17px of the island rim; check frame-crop bleed")


func _in_any_box(boxes: Array, x: int, y: int) -> bool:
	for b in boxes:
		if b.has_point(Vector2i(x, y)):
			return true
	return false


## Plateau/cliff STONE, tuned on Tilemap_color1 tile (5..7,4) texels at capture
## scale (2026-07-17): blue-gray-teal where b>r clearly, NOT saturated water teal
## (g<1.6r kills (71,171,169)) and NOT grass/worn (b>r+8 kills both greens).
## Measured hit-rates: stone 0.79, grass 0.00, worn-path 0.00, water 0.00.
## (Separate from _arena_is_stone, which the castle-cliff detector is calibrated on.)
func _arena_is_plateau_stone(c: Color) -> bool:
	var avg: float = (c.r + c.g + c.b) / 3.0
	return c.b >= c.g - 0.024 and c.b > c.r + 0.031 and avg > 0.274 and avg < 0.804 \
		and c.g >= c.r and absf(c.g - c.b) < 0.157 and c.g < c.r * 1.6


## 3.3b: side plateaus (approved arena_target.png rev B) — an elevated shelf per
## side band (design x[72,200]/[520,648], grass y[328,648], stone face y[648,712])
## frames the combat zone. The mirrored corner tower (design x 95..185) occludes
## the face's middle, so we sample the four tower-free FLANKS of the two stone
## bands: cap x [50,67]+[129,141] (left) and [363,375]+[437,454] (right), y[458,494].
## Calibrated 2026-07-17 on the 0.7x-scaled target vs the pre-port capture:
## target total=1072 (per-window 376/154/151/391), pre-port build=172 (51/33/33/55).
func _check_arena_side_plateaus() -> void:
	print("[Arena side plateaus (3.3b terrain)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var wins := [Vector2i(50, 67), Vector2i(129, 141), Vector2i(363, 375), Vector2i(437, 454)]
	var parts: Array = []
	var total: int = 0
	for w in wins:
		var n: int = 0
		for y in range(458, 494):
			for x in range(w.x, w.y):
				if _arena_is_plateau_stone(img.get_pixel(x, y)):
					n += 1
		parts.append(n)
		total += n
	# Bar: total ≥550 AND both outer flanks ≥150 — clean separation from the
	# 172-total / 51-55-outer pre-port baseline, with margin under the 1072 target.
	if total >= 550 and int(parts[0]) >= 150 and int(parts[3]) >= 150:
		_assert_pass("side plateau stone faces present (stone px %s total=%d)" % [str(parts), total])
	else:
		_assert_fail("side plateaus missing — stone px %s total=%d (need ≥550, outers ≥150)" % [str(parts), total],
			"elevated shelf stone faces at design y[648,712] x[72,200]/[520,648] per arena_target.png")


## 3.3b: worn-grass lane (approved rev B) — a contiguous Tilemap_color4 patch at
## design x[296,424] y[360,680]. Olive is separable from color1 grass: g-r in
## (5,34) vs grass's ~30+ at higher g, b<r. Measured olive-fraction in the cap
## window x[217,287] y[280,448]: target 0.92, color1 grass 0.00, pre-port capture
## 0.0004. Units mid-match can occlude some of the window — bar set at 0.45.
func _check_arena_worn_path() -> void:
	print("[Arena worn lane path (3.3b terrain)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var n: int = 0
	var area: int = 0
	for y in range(280, 448):
		for x in range(217, 287):
			area += 1
			var c: Color = img.get_pixel(x, y)
			var d_gr: float = c.g - c.r
			if d_gr > 0.02 and d_gr < 0.133 and c.g > 0.431 and c.g < 0.725 and c.b < c.r:
				n += 1
	var frac: float = float(n) / float(area)
	if frac >= 0.45:
		_assert_pass("worn lane path present (olive fraction %.2f in center window)" % frac)
	else:
		_assert_fail("worn lane path missing — olive fraction %.2f (need ≥0.45)" % frac,
			"color4 patch at design x[296,424] y[360,680] per arena_target.png rev B")


## 3.3b: central gold cluster (approved rev B) — Gold_Resource chunks + nuggets
## around the pivot (design x[300,420] y[450,590] → cap x[210,294] y[315,413]).
## Bright gold (r>200,g>150,b<110 at 8-bit): target=515 px, pre-port capture=0.
func _check_arena_central_gold() -> void:
	print("[Arena central gold cluster (3.3b terrain)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var n: int = 0
	for y in range(315, 413):
		for x in range(210, 294):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.784 and c.g > 0.588 and c.b < 0.431:
				n += 1
	if n >= 150:
		_assert_pass("central gold cluster present (%d gold px)" % n)
	else:
		_assert_fail("central gold cluster missing — %d gold px (need ≥150)" % n,
			"Gold_Resource cluster at design (340,500)/(384,478)+mirrors per arena_target.png")


# --- Pixel-detector helpers ---

## Loads a capture PNG by bare filename. A MISSING capture is a FAIL, not a pass —
## this closes the "silent green" hole where every pixel detector passed with zero
## pixels examined whenever /tmp had been purged (lessons.md 2026-04-18).
func _load_capture(name: String) -> Image:
	var path := _cap(name)
	if not FileAccess.file_exists(path):
		if _capture_manifest_present():
			_assert_fail("capture %s missing from the last run" % name,
				"pipeline ran but did not produce this PNG — check auto_screenshot manifest")
		else:
			_assert_fail("no capture manifest — run `tests/capture.sh` before the pixel gate",
				"pixel detectors cannot pass without a fresh capture run")
		return null
	var img := Image.load_from_file(path)
	if img == null:
		_assert_fail("could not load %s" % path, "Image.load_from_file returned null")
	return img


func _find_bright_nongreen_clusters(img: Image, y: int, w: int) -> Array:
	var clusters: Array = []
	var in_c: bool = false
	var run_start: int = -1
	for x in range(w):
		var c: Color = img.get_pixel(x, y)
		var brightness: float = (c.r + c.g + c.b) / 3.0
		var is_green: bool = c.g > c.r + 0.04 and c.g > c.b + 0.04
		var hit: bool = brightness > 0.69 and not is_green
		if hit and not in_c:
			in_c = true
			run_start = x
		elif not hit and in_c:
			in_c = false
			clusters.append({"start": run_start, "end": x - 1})
	if in_c:
		clusters.append({"start": run_start, "end": w - 1})
	return clusters


# (2026-07-18: the loose _is_ribbon_pixel + _is_decoration_pixel helpers were
# deleted with the old over-broad BUG-49 rule — the strict ribbon/banner
# palette helper next to _check_ribbon_edge_clipping replaced them.)


# --- Helpers ---

func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content: String = f.get_as_text()
	f.close()
	return content


func _indent_level(line: String) -> int:
	var n: int = 0
	for c in line:
		if c == "\t":
			n += 1
		elif c == " ":
			n += 1
		else:
			break
	return n


# ============================ Screen-parity P1 (Game HUD) =============================
# Calibrated against game_*.png at 504x896 (0.7x design) — RED baseline verified 2026-07-10:
# HUD corners (34,32,23) void; zero gold-fill pixels in the right bar band.

## HUD-alignment: the top strip is transparent (bars + TIME banner float over the arena),
## NOT the P1 warm-wood HUDBg. The corners must read as arena (green/teal), not the wood
## (~61,50,32) strip. Calibrated on P1 baseline: corners (61,50,32) wood.
func _check_hud_strip_transparent() -> void:
	print("[HUD top strip transparent — arena shows through (HUD-align)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var w: int = img.get_width()
	var samples := [Vector2i(5, 8), Vector2i(w - 6, 8), Vector2i(5, 30), Vector2i(w - 6, 30)]
	var wood_hits: int = 0
	var worst := ""
	for p in samples:
		var c: Color = img.get_pixel(p.x, p.y)
		# P1 wood HUDBg signature (~61,50,32): warm brown, r>g>b, none of it green/teal.
		var arena_ish: bool = (c.g > c.r + 0.04) or (c.b > c.r + 0.04)  # grass or water
		if not arena_ish:
			wood_hits += 1
			worst = "(%d,%d)=(%d,%d,%d)" % [p.x, p.y, c.r8, c.g8, c.b8]
	if wood_hits == 0:
		_assert_pass("HUD corners show the arena (transparent strip)")
	else:
		_assert_fail("HUD strip not transparent — %d/4 corners still a wood/ribbon strip, e.g. %s" % [wood_hits, worst],
			"set HUDBg alpha 0 + remove the top HUD ribbon (game_arena.gd)")


## HUD-alignment: the gold bar is a YELLOW ribbon (reference) — no red ribbon, no fill meter.
## Calibrated on P1 baseline: gold band red_px ~10184 >> yellow_px ~407.
func _check_gold_bar_yellow() -> void:
	print("[Gold bar is a yellow ribbon (HUD-align)]")
	var img := _load_capture(ARENA_CAPTURE)
	if img == null:
		return
	var yellow: int = 0
	var red: int = 0
	for y in range(695, 726):  # design y990-1040 -> capture band
		for x in range(0, img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.58 and c.g > 0.55 and c.b < 0.47:            # ribbon_yellow (~187,181,82)
				yellow += 1
			elif c.r > 0.55 and c.r > c.g + 0.16 and c.b < 0.43:     # ribbon_red (~166,72,54)
				red += 1
	if yellow > 1500 and yellow > red:
		_assert_pass("gold bar reads as a yellow ribbon (yellow=%d, red=%d)" % [yellow, red])
	else:
		_assert_fail("gold bar not yellow (yellow=%d, red=%d)" % [yellow, red],
			"use ribbon_yellow.png for the gold bar (game_arena.gd)")


## hud.gd + card_hand.gd font sizes must be quantized to {16,32} (Pixel Operator Bold is
## 16px-native; other sizes render mushy). Scoped to these two so P1's rule doesn't red-gate
## the other packages' sizes.
func _check_hud_fonts_quantized() -> void:
	print("[HUD fonts quantized to 16/32 (P1)]")
	var allowed := [16, 32]
	var rx_override := RegEx.new()
	rx_override.compile('add_theme_font_size_override\\("font_size", (\\d+)\\)')
	var rx_draw := RegEx.new()
	rx_draw.compile('HORIZONTAL_ALIGNMENT_\\w+,\\s*[^,]+,\\s*(\\d+)')  # draw_string font-size arg
	var bad: Array = []
	for path in ["res://scripts/ui/hud.gd", "res://scripts/ui/card_hand.gd"]:
		var content := _read_file(path)
		var lines := content.split("\n")
		for i in lines.size():
			for m in [rx_override.search(lines[i]), rx_draw.search(lines[i])]:
				if m:
					var sz: int = int(m.get_string(1))
					if not allowed.has(sz):
						bad.append({"file": path, "line": i + 1, "size": sz})
	if bad.is_empty():
		_assert_pass("all hud.gd + card_hand.gd font sizes are 16 or 32")
	else:
		_assert_fail("%d non-16/32 HUD font size(s)" % bad.size(), "quantize to 16 or 32")
		for b in bad:
			_record("MED", b.file, b.line, "font_size=%d (must be 16/32)" % b.size)


## Combat-critical touch targets meet the >=80px HIG floor (audit + backlog 3.4).
func _check_hud_touch_targets() -> void:
	print("[HUD touch targets >=80px (P1)]")
	var fails: Array = []
	var hud := _read_file("res://scripts/ui/hud.gd")
	var cards := _read_file("res://scripts/ui/card_hand.gd")
	var arena := _read_file("res://scripts/game/game_arena.gd")
	var bar_h := _grab_const_float(hud, "BAR_H")
	if bar_h < 32.0:
		fails.append("HP pill BAR_H=%.0f < 32" % bar_h)
	var card_w := _grab_const_float(cards, "CARD_W")
	if card_w < 88.0:
		fails.append("CARD_W=%.0f < 88" % card_w)
	if not arena.contains("Vector2(88, 88)"):
		fails.append("ability button not 88x88")
	if not arena.contains("Vector2(150, 88)"):
		fails.append("castle-wrath button not 150x88")
	if fails.is_empty():
		_assert_pass("HP pill / card / ability / wrath all meet the size floor")
	else:
		_assert_fail("%d touch target(s) below floor: %s" % [fails.size(), ", ".join(fails)], "raise to >=80/88px")


## Parse `const NAME: float = VALUE` from source; returns 0.0 if not found.
func _grab_const_float(content: String, name: String) -> float:
	var rx := RegEx.new()
	rx.compile("const %s: float = ([0-9.]+)" % name)
	var m := rx.search(content)
	return float(m.get_string(1)) if m else 0.0


# ============================ Screen-parity P2 (Menu shell) ===========================
# Calibrated on menu_battle_000.png @ 504x896 — RED baseline verified 2026-07-10:
# side sky (52,92,42) flat green; inactive tab labels peak (90,80,56); trophy=shield.

const MENU_BATTLE_CAP: String = "menu_battle_000.png"


## The menu "sky" must be the loading-screen blue→haze gradient, not a flat green wall
## (clouds read as blobs on green; loading→menu flashed green). Sample the side sky band
## between the tagline and logo where the sky shows clean.
func _check_menu_sky_not_flat_green() -> void:
	print("[Menu sky is a gradient, not flat green (P2)]")
	var img := _load_capture(MENU_BATTLE_CAP)
	if img == null:
		return
	var blue: int = 0
	var total: int = 0
	for y in [175, 200, 230]:
		for x in [30, 70, 430, 470]:
			var c: Color = img.get_pixel(x, y)
			total += 1
			if c.b > c.r + 0.05 and c.b > 0.45:  # sky blue/haze, not green
				blue += 1
	if blue >= 8:
		_assert_pass("menu sky reads as blue gradient (%d/%d side samples blue)" % [blue, total])
	else:
		_assert_fail("menu sky still flat green (%d/%d blue) — port loading_screen's gradient" % [blue, total],
			"main_menu.gd _build_scenic_background: GradientTexture2D sky")


## Inactive bottom-tab labels must be legible cream (audit: 2.1:1 → ~8:1). Baseline the
## brightest label pixel per inactive tab was (90,80,56); cream is ~(237,222,184).
func _check_tab_labels_legible() -> void:
	print("[Inactive tab labels legible (P2)]")
	var img := _load_capture(MENU_BATTLE_CAP)
	if img == null:
		return
	var dim: Array = []
	for entry in [["Shop", 55], ["Army", 150], ["Social", 350], ["Settings", 450]]:
		var xc: int = entry[1]
		var best_r: float = 0.0
		var best_sum: float = 0.0
		for y in range(864, 888):
			for x in range(xc - 40, xc + 40):
				var c: Color = img.get_pixel(x, y)
				var s: float = c.r + c.g + c.b
				if s > best_sum:
					best_sum = s
					best_r = c.r
		# cream text: bright and warm. Baseline dim label maxed at r=0.35, sum=0.89.
		if best_r < 0.70 or best_sum < 1.8:
			dim.append("%s(r=%.2f,sum=%.2f)" % [entry[0], best_r, best_sum])
	if dim.is_empty():
		_assert_pass("all 4 inactive tab labels render bright cream text")
	else:
		_assert_fail("%d inactive tab label(s) still dim: %s" % [dim.size(), ", ".join(dim)],
			"_select_tab unselected branch: cream label + outline + icon 0.85")


## Header trophy icon must be an actual trophy, not the army shield (Icon_06). Static.
func _check_trophy_not_shield() -> void:
	print("[Header trophy icon not a shield (P2)]")
	var tscn := _read_file("res://scenes/ui/main_menu.tscn")
	if tscn.is_empty():
		_assert_pass("main_menu.tscn not present (skipped)")
		return
	# Find the TrophyIcon node block and check its texture reference.
	var idx: int = tscn.find('name="TrophyIcon"')
	var ok := false
	if idx != -1:
		var block: String = tscn.substr(idx, 260)
		ok = block.contains('ExtResource("icon_trophy")') and not block.contains('ExtResource("icon_army")')
	if ok and tscn.contains("res://assets/sprites/ui/trophy.png"):
		_assert_pass("TrophyIcon uses trophy.png, not the army shield")
	else:
		_assert_fail("header trophy icon is still the shield (Icon_06)", "set TrophyIcon.texture to trophy.png")


## PLAY ONLINE must be demoted to a compact secondary chip (single-CTA hierarchy). Static:
## the online button width is < 300 (vs the ~440px BATTLE ribbon).
func _check_online_cta_demoted() -> void:
	print("[PLAY ONLINE demoted to a compact chip (P2)]")
	var src := _read_file("res://scripts/ui/main_menu.gd")
	var rxl := RegEx.new()
	rxl.compile("online_btn.offset_left = (-?[0-9.]+)")
	var rxr := RegEx.new()
	rxr.compile("online_btn.offset_right = (-?[0-9.]+)")
	var ml := rxl.search(src)
	var mr := rxr.search(src)
	if ml == null or mr == null:
		_assert_fail("could not find online_btn offsets", "expected online_btn.offset_left/right in main_menu.gd")
		return
	var width: float = float(mr.get_string(1)) - float(ml.get_string(1))
	var blue_chip: bool = src.contains("ribbon_blue.png")
	if width < 300.0 and blue_chip:
		_assert_pass("online CTA is a compact %.0fpx blue-ribbon chip" % width)
	else:
		_assert_fail("online CTA not demoted (width=%.0f, blue_chip=%s)" % [width, blue_chip],
			"restyle online_btn as a <300px ribbon_blue chip")


# ============================ Screen-parity P3 (End screen) ===========================
# Calibrated on end_victory_000.png @ 504x896 — RED baseline verified 2026-07-11:
# card-tray band 7965 wood px (HUD/cards bleed through); VICTORY ribbon muddy (158,145,61).

const END_CAPTURE: String = "end_victory_000.png"


## The results panel must take over: the in-match card tray / gold bar / HUD are hidden
## (backlog 3.5). Detect the card-tray wood in the bottom band — baseline ~7965 px bleeds
## through; after the takeover it drops to near zero (arena under the 40% overlay).
func _check_end_screen_takeover() -> void:
	print("[End screen takeover — no card-tray bleed-through (P3)]")
	var img := _load_capture(END_CAPTURE)
	if img == null:
		return
	var wood: int = 0
	for y in range(745, 895):
		for x in range(0, img.get_width()):
			var c: Color = img.get_pixel(x, y)
			# Tiny Swords card-tray wood (~139,98,66): warm mid-brown.
			if absf(c.r - 139.0 / 255.0) < 0.16 and absf(c.g - 98.0 / 255.0) < 0.16 and c.b < 90.0 / 255.0:
				wood += 1
	if wood < 2500:
		_assert_pass("card tray hidden behind results (%d wood px, was ~7965)" % wood)
	else:
		_assert_fail("in-match card tray bleeds through the results panel (%d wood px)" % wood,
			"hide HUD/GoldBarBg/CardHand in _on_match_ended (backlog 3.5)")


## VICTORY! ribbon must be full-opacity parchment (audit: 0.85 alpha muddied it to 2.46:1).
## Count BRIGHT parchment pixels in the ribbon band (excludes the dark backdrop AND the
## bright gold text). Baseline muddy parchment (158,145,61) scores ~0; full parchment (187,181,82) many.
func _check_victory_ribbon_bright() -> void:
	print("[VICTORY ribbon at full parchment opacity (P3)]")
	var img := _load_capture(END_CAPTURE)
	if img == null:
		return
	# Band covers the ribbon in both layouts (baseline ~y265, post-wood-backdrop ~y185);
	# excludes the gold PLAY AGAIN button (y500+) so only the ribbon parchment counts.
	var bright: int = 0
	for y in range(150, 320):
		for x in range(40, 445):
			var c: Color = img.get_pixel(x, y)
			# bright parchment yellow: 175<=R<=235, green high, blue low (not dark bg, not R>240 text)
			if c.r >= 0.686 and c.r <= 0.921 and c.g >= 0.627 and c.b <= 0.431:
				bright += 1
	# The full-opacity ribbon fills ~11k px; muddy/low-opacity + gold-label noise stays well
	# under 1500. Threshold sits in that wide gap so it can't false-pass on stat-label gold.
	if bright >= 1500:
		_assert_pass("VICTORY ribbon reads full parchment (%d bright px)" % bright)
	else:
		_assert_fail("VICTORY ribbon still muddy/low-opacity (%d bright parchment px)" % bright,
			"set ribbon.modulate.a = 1.0 in end_screen.gd")


## End-screen buttons meet the >=80px HIG floor (audit: ~43px). Static.
func _check_end_buttons_size() -> void:
	print("[End-screen buttons >=80px (P3)]")
	var tscn := _read_file("res://scenes/game/game_arena.tscn")
	var src := _read_file("res://scripts/ui/end_screen.gd")
	var fails: Array = []
	# RestartButton / MenuButton min-heights in the tscn block.
	var ri: int = tscn.find('name="RestartButton"')
	if ri == -1 or not tscn.substr(ri, 200).contains("Vector2(0, 96)"):
		fails.append("RestartButton != 96")
	var mi: int = tscn.find('name="MenuButton"')
	if mi == -1 or not tscn.substr(mi, 200).contains("Vector2(0, 80)"):
		fails.append("MenuButton != 80")
	if not src.contains("Vector2(260, 80)"):
		fails.append("ShareButton != 260x80")
	# _style_end_button enforces a floor for the code-styled buttons.
	if not src.contains("maxf(btn.custom_minimum_size.y, 80.0)"):
		fails.append("no 80px floor in _style_end_button")
	if fails.is_empty():
		_assert_pass("all end-screen buttons meet the >=80px floor")
	else:
		_assert_fail("%d end-screen button(s) below floor: %s" % [fails.size(), ", ".join(fails)], "raise to >=80/96px")


## P4 (2026-07-15): Army cards must be warm wood/paper, not the cold-navy programmer
## boxes (audit main_menu.gd:1755, measured card bg RGB(29,42,69)). Scans the army-card
## column (menu_army_000.png @504x896, cards at capture x[10,494] y[115,762]) for cold-
## navy pixels: pre-P4 = 264k (RED); warm cards = ~0 (GREEN). Threshold 3000 tolerates a
## few dark-blue Kingdom-armor shadows on the new unit sprites.
func _check_army_cards_not_navy() -> void:
	print("[Army cards warm, not cold-navy (P4 parity)]")
	var img := _load_capture("menu_army_000.png")
	if img == null:
		return
	var navy: int = 0
	for y in range(115, 762, 2):
		for x in range(10, 494, 2):
			var c: Color = img.get_pixel(x, y)
			# NARROW band around the exact card bg (29,42,69)=(0.114,0.165,0.271) so the
			# new unit sprites' varied/brighter armor blues don't false-trip it.
			if absf(c.r - 0.114) < 0.06 and absf(c.g - 0.165) < 0.06 \
					and absf(c.b - 0.271) < 0.07 and c.b > c.r:
				navy += 1
	# sampled every 2px both axes (~1/4 of full). pre-P4 ~61k; warm ~0.
	if navy < 3000:
		_assert_pass("army cards warm, not cold-navy (navy px=%d, sampled)" % navy)
	else:
		_assert_fail("army cards still cold-navy — navy px=%d (need <3000)" % navy,
			"warm UIStyle wood/paper cards per audit main_menu.gd:1755")


## P4 (2026-07-15): the equipped avatar must show a VISIBLE gold ring (audit found ZERO
## gold-border px today — Δ6 RGB bg + a ring that doesn't render at capture scale, HIGH,
## main_menu.gd:533). Window = the top-left selected cell (avatar 1, default), a box
## generous enough to survive the grid-centering shift: menu_shop_000.png @504x896,
## capture x[16,134] y[214,298]. Pre-P4 = 0 gold (RED); strong ring = hundreds (GREEN).
## The daily-pick gold frames sit above (y<205), outside the window.
func _check_avatars_selected_ring() -> void:
	print("[Avatars equipped ring visible (P4 parity)]")
	var img := _load_capture("menu_shop_000.png")
	if img == null:
		return
	var gold: int = 0
	for y in range(214, 298):
		for x in range(16, 134):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.72 and c.g > 0.53 and c.g < 0.83 and c.b < 0.46 and c.r > c.b + 0.28:
				gold += 1
	if gold > 40:
		_assert_pass("equipped avatar shows a visible gold ring (gold px=%d)" % gold)
	else:
		_assert_fail("equipped avatar ring invisible — gold px=%d (need >40)" % gold,
			"strong gold ring on the selected/equipped cell per audit main_menu.gd:533")


## P5 (2026-07-16): Social MATCH RECORD / FRIENDS cards must be warm paper, not the
## cold-navy programmer panels (audit main_menu.gd:1873, _make_style RGB 29,42,69).
## Whole-tab scan (menu_social_000.png @504x896, y[70,800]) so it survives the cards
## moving when the void is filled: pre-P5 = 20,420 navy px (sampled, RED); paper = ~0.
func _check_social_not_navy() -> void:
	print("[Social cards warm paper, not cold-navy (P5 parity)]")
	var img := _load_capture("menu_social_000.png")
	if img == null:
		return
	var navy: int = 0
	for y in range(70, 800, 2):
		for x in range(8, 496, 2):
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - 0.114) < 0.06 and absf(c.g - 0.165) < 0.06 \
					and absf(c.b - 0.271) < 0.07 and c.b > c.r:
				navy += 1
	if navy < 1000:
		_assert_pass("social cards warm paper, not cold-navy (navy px=%d, sampled)" % navy)
	else:
		_assert_fail("social cards still cold-navy — navy px=%d (need <1000)" % navy,
			"warm paper panels per audit main_menu.gd:1873")


## P5: volume sliders must be themed (bar-asset track), not the raw Godot-default neutral-
## gray HSlider (audit main_menu.gd:2062, track RGB 121,118,116). Whole-tab scan for FLAT
## NEUTRAL gray (r≈g≈b, mid value) — the warm bar-asset stone is tinted, not neutral, so it
## won't match. Pre-P5 = 849 gray px (sampled, RED); themed = ~0.
func _check_settings_sliders_themed() -> void:
	print("[Settings sliders themed, not raw gray (P5 parity)]")
	var img := _load_capture("menu_settings_000.png")
	if img == null:
		return
	var gray: int = 0
	for y in range(70, 800, 2):
		for x in range(8, 496, 2):
			var c: Color = img.get_pixel(x, y)
			var avg: float = (c.r + c.g + c.b) / 3.0
			if absf(c.r - c.g) < 0.05 and absf(c.g - c.b) < 0.05 and avg > 0.37 and avg < 0.69:
				gray += 1
	if gray < 250:
		_assert_pass("volume sliders themed (raw neutral-gray px=%d, sampled)" % gray)
	else:
		_assert_fail("volume sliders still raw Godot gray — gray px=%d (need <250)" % gray,
			"UIStyle.theme_slider per audit main_menu.gd:2062")


## P5: "Reset All Progress" must NOT be the brightest/primary — restyled as a low-emphasis
## outline (audit main_menu.gd:2013, currently the sole saturated fill RGB~111,32,20).
## Whole-tab saturated-red-FILL scan (robust to the button moving to the bottom): pre-P5 =
## 9683 filled px (RED); outline-only = a thin border (<2500).
func _check_reset_demoted() -> void:
	print("[Settings Reset demoted, not a filled primary (P5 parity)]")
	var img := _load_capture("menu_settings_000.png")
	if img == null:
		return
	var red: int = 0
	for y in range(70, 800):
		for x in range(8, 496):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.35 and c.r > c.g * 2.0 and c.r > c.b * 2.0 and c.g < 0.32:
				red += 1
	if red < 2500:
		_assert_pass("Reset is a low-emphasis outline (saturated-red-fill px=%d)" % red)
	else:
		_assert_fail("Reset All Progress still a filled primary — red-fill px=%d (need <2500)" % red,
			"restyle as an outline button at the bottom per audit main_menu.gd:2013")


func _print_results() -> void:
	if _quarantine > 0:
		print("\n  (%d quarantined — tracked Phase-3 bugs, reported but not gating)" % _quarantine)
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	if _findings.size() > 0:
		print("\n--- Findings ---")
		for f in _findings:
			print("  [%s] %s:%d  %s" % [f.severity, f.src, f.line, f.msg])
