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
var _findings: Array = []  # list of {severity, file, line, msg}

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
	_check_progress_bar_pixel_continuity()  # BUG-43 RE-OPEN: pixel-level check
	_check_tip_strip_construction()
	# Phase-1 detector suite (BUG-46/47/48/49) — pixel-level, run on
	# /tmp/castle_clash_test/menu_battle_000.png from latest --autotest run.
	_check_chimney_smoke_vertical()       # BUG-46
	_check_tree_spire_zindex()            # BUG-47
	_check_fence_row_repetition()         # BUG-48
	_check_ribbon_edge_clipping()         # BUG-49
	# Phase-2 detector suite (BUG-51/52) — user-reported 2026-04-21.
	_check_battle_tab_always_lifted()     # BUG-51
	_check_non_battle_tab_scenic_bleed()  # BUG-52
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
	print("[Locked card overlapping labels (BUG-45)]")
	var path: String = "res://scripts/ui/card_hand.gd"
	var content := _read_file(path)
	if content.is_empty():
		_assert_pass("card_hand.gd not present (skipped)")
		return
	# Heuristic: search for "LOCKED" and check if there's a `visible = false` /
	# `if locked` guard nearby that hides the building-name label.
	var lines := content.split("\n")
	var locked_line: int = -1
	for i in lines.size():
		if lines[i].contains("LOCKED"):
			locked_line = i + 1
			break
	if locked_line == -1:
		_assert_pass("no LOCKED label found in card_hand")
		return
	# Look for `if not enabled` / `if locked` / `visible = false` within ±20 lines
	var has_guard: bool = false
	var lo: int = maxi(0, locked_line - 20)
	var hi: int = mini(lines.size(), locked_line + 20)
	for j in range(lo, hi):
		var ln: String = lines[j].strip_edges()
		if ln.contains("if not enabled") or ln.contains("if enabled") or ln.contains("if locked") or ln.contains("if not locked") or ln.contains("name_lbl.visible") or ln.contains("name_lbl.hide") or ln.contains("type_lbl.visible") or ln.contains("type_lbl.hide"):
			has_guard = true
			break
	if has_guard:
		_assert_pass("LOCKED card has visibility guard nearby")
	else:
		_assert_fail("LOCKED card likely overlaps building-name + role + LOCKED labels at same position",
			"add `if locked: name_lbl.visible = false` (or similar) per BUG-45")
		_record("HIGH", path, locked_line, "BUG-45 — no visibility guard near LOCKED render")


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
## desktop window override). Scans the bar centerline and counts horizontal
## "wood" runs separated by "green background" gaps. A continuous trough = exactly
## 1 wood run. 3 detached planks = 3+ runs. Coordinates calibrated 2026-04-18:
## bar Y-band y≈624-688, centerline ~y=648, bar interior x≈90..414.
func _check_progress_bar_pixel_continuity() -> void:
	print("[Progress bar pixel continuity (BUG-43 pixel-level)]")
	var img := _load_capture("loading_000.png")
	if img == null:
		return
	# Bar centerline ~y=648 in 504×896 capture.
	var y_sample: int = 648
	var x_start: int = 90
	var x_end: int = 414
	var runs: Array = []  # list of {start, end}
	var in_wood: bool = false
	var run_start: int = -1
	for x in range(x_start, x_end):
		var c: Color = img.get_pixel(x, y_sample)
		# Wood = brown-ish (R > G, dark to medium). Green bg = G > R.
		var is_wood: bool = c.r > c.g and c.r > 0.25 and c.r < 0.75 and c.b < 0.5
		if is_wood and not in_wood:
			in_wood = true
			run_start = x
		elif not is_wood and in_wood:
			in_wood = false
			runs.append({"start": run_start, "end": x - 1})
	if in_wood:
		runs.append({"start": run_start, "end": x_end - 1})
	# Coalesce runs separated by < 8px (anti-alias artifacts only)
	var merged: Array = []
	for r in runs:
		if merged.size() > 0 and r.start - merged[-1].end < 8:
			merged[-1].end = r.end
		else:
			merged.append({"start": r.start, "end": r.end})
	if merged.size() <= 1:
		_assert_pass("loading bar trough is one continuous wood run (%d run found)" % merged.size())
	else:
		_assert_fail("loading bar has %d detached wood segments at y=%d (should be 1)" % [merged.size(), y_sample],
			"BUG-43 RE-OPEN — middle plank floats between end caps")
		for i in merged.size():
			_record("HIGH", "loading_000.png", y_sample, "wood run #%d: x=%d..%d (width %d)" % [i + 1, merged[i].start, merged[i].end, merged[i].end - merged[i].start])


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
func _check_tree_spire_zindex() -> void:
	print("[Tree z-clip through spire (BUG-47 pixel)]")
	var img := _load_capture(MENU_CAPTURE)
	if img == null:
		return
	var mixing_rows: Array = []
	for y in range(140, 340, 4):
		var greens: int = 0
		var grays: int = 0
		for x in range(0, 250):
			var c: Color = img.get_pixel(x, y)
			if c.g > c.r + 0.04 and c.g > 0.4:
				greens += 1
			if absf(c.r - c.g) < 0.05 and c.r > 0.4 and c.r < 0.78 and c.b < c.r + 0.12:
				grays += 1
		if greens > 30 and grays > 30:
			mixing_rows.append({"y": y, "green": greens, "gray": grays})
	if mixing_rows.size() <= 1:
		_assert_pass("left scenic strip has clean tree/building z-order (%d mixed rows)" % mixing_rows.size())
	else:
		_assert_fail("BUG-47 — %d Y-rows show green/gray sandwich in left scenic strip" % mixing_rows.size(),
			"trees lack consistent z_index vs cottage spire")
		for mr in mixing_rows.slice(0, 5):
			_record("MEDIUM", MENU_CAPTURE, mr.y,
				"BUG-47 — y=%d green=%d gray=%d" % [mr.y, mr.green, mr.gray])


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


## BUG-49: Decoration sprites clipped at screen edges (originally filed as
## "partial ribbons"; user actually meant any edge-clipped scenery — towers,
## cottages, ribbons all qualify). Calibrated 2026-04-18 on 504×896 capture:
## the rightmost edge clips a tower, the bottom-right clips a cottage, etc.
##
## PASS rule: the leftmost 16-px column AND the rightmost 16-px column may not
## contain >180 non-grass pixels within any 80-px Y window. (16 px = inside the
## safe area; any sprite reaching that depth is being clipped by the viewport.)
func _check_ribbon_edge_clipping() -> void:
	print("[Edge-clipped scenery (BUG-49 pixel)]")
	var img := _load_capture(MENU_CAPTURE)
	if img == null:
		return
	var h: int = img.get_height()
	var w: int = img.get_width()
	var hits: Array = []
	for y0 in range(0, h - 80, 40):
		var y1: int = y0 + 80
		var left: int = 0
		var right: int = 0
		for y in range(y0, y1):
			for x in range(0, 16):
				if _is_decoration_pixel(img.get_pixel(x, y)):
					left += 1
			for x in range(w - 16, w):
				if _is_decoration_pixel(img.get_pixel(x, y)):
					right += 1
		if left > 180:
			hits.append({"side": "LEFT", "y0": y0, "y1": y1, "px": left})
		if right > 180:
			hits.append({"side": "RIGHT", "y0": y0, "y1": y1, "px": right})
	if hits.is_empty():
		_assert_pass("no ribbon-like clipping at screen edges")
	else:
		_assert_fail("BUG-49 — %d edge-clipped ribbon zones" % hits.size(),
			"flags/ribbons sit outside the visible viewport")
		for h_entry in hits.slice(0, 4):
			_record("LOW", MENU_CAPTURE, h_entry.y0,
				"BUG-49 — %s edge y=%d-%d ribbon_px=%d" %
				[h_entry.side, h_entry.y0, h_entry.y1, h_entry.px])


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


func _is_ribbon_pixel(c: Color) -> bool:
	var brightness: float = (c.r + c.g + c.b) / 3.0
	var sat: float = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))
	# Saturated, bright, not grass-green
	var is_grass: bool = c.g > c.r + 0.04 and c.g > c.b + 0.04
	return brightness > 0.39 and sat > 0.20 and not is_grass


## True when pixel belongs to any non-grass scenery (towers, cottages, ribbons,
## stone, wood, etc.). Used by BUG-49 edge-clipping detector.
func _is_decoration_pixel(c: Color) -> bool:
	var is_grass: bool = c.g > c.r + 0.05 and c.g > c.b + 0.04 and c.g > 0.30
	# Skip very dark transparent-edge / shadow pixels
	var brightness: float = (c.r + c.g + c.b) / 3.0
	if brightness < 0.18:
		return false
	return not is_grass


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


func _print_results() -> void:
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	if _findings.size() > 0:
		print("\n--- Findings ---")
		for f in _findings:
			print("  [%s] %s:%d  %s" % [f.severity, f.src, f.line, f.msg])
