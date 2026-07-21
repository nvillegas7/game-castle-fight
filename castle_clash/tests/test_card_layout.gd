## BUG-30: card-face layout contract — the building name renders BELOW the
## icon and INSIDE the card. Root cause of the shipped artifact: draw_string's
## y is a BASELINE, but card_hand anchored it at icon_bottom+4, so the ascent
## rendered ACROSS the icon; two-line names also overflowed the 90px 2-row
## card ("Gryphon Roost" clipped mid-glyph). The math lives in CardLayout
## (pure, autoload-free); this suite pins the contract headless.
## Usage: godot --headless --path castle_clash -s tests/test_card_layout.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	print("\n=== CARD LAYOUT (BUG-30) ===\n")
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/card_layout.gd")
	var has_cls: bool = src.contains("static func layout(")
	_ok("CardLayout.layout exists (pure, headless-testable)", has_cls,
		"card layout math still inlined in card_hand._draw_full")
	if has_cls:
		var cl: GDScript = load("res://scripts/ui/card_layout.gd")
		var font := ThemeDB.fallback_font
		var asc: float = font.get_ascent(16)
		var desc: float = font.get_descent(16)
		# Case matrix: {2-row 90px, 1-row 130px} x {tall icon, wide icon,
		# no icon} x {1, 2 name lines}. Contract per case:
		#   first baseline - ascent >= icon bottom + 2   (below the icon)
		#   last baseline + descent <= h - 2.5           (inside the card)
		for case in [
			[88.0, 90.0, 100.0, 140.0, 2], [88.0, 90.0, 140.0, 100.0, 2],
			[88.0, 90.0, 100.0, 140.0, 1], [88.0, 90.0, 0.0, 0.0, 2],
			[88.0, 130.0, 100.0, 140.0, 2], [88.0, 130.0, 140.0, 100.0, 1],
		]:
			var lay: Dictionary = cl.call("layout", case[0], case[1], case[2], case[3], int(case[4]), asc, desc)
			var icon: Rect2 = lay.icon
			var icon_bottom: float = icon.position.y + icon.size.y if icon.size.y > 0.0 else 24.0
			var bl: Array = lay.baselines
			var name_top: float = float(bl[0]) - asc
			var name_bottom: float = float(bl[bl.size() - 1]) + desc
			var tag: String = "w%d h%d tex%dx%d lines%d" % [case[0], case[1], case[2], case[3], case[4]]
			_ok("%s: name below icon (top %.1f >= icon_bottom %.1f + 2)" % [tag, name_top, icon_bottom],
				name_top >= icon_bottom + 2.0 - 0.01)
			# 5.0: BOTTOM_MARGIN(6) minus float slack — descenders + AA must
			# clear the pixel detector's bottom-3-capture-rows zone.
			_ok("%s: name inside card (bottom %.1f <= h - 5)" % [tag, name_bottom],
				name_bottom <= float(case[1]) - 5.0)
			_ok("%s: icon inside card" % tag,
				icon.size.y == 0.0 or (icon.position.y >= 20.0 and icon_bottom < float(case[1])))
			if lay.type_y > 0.0:
				var tmax: float = (float(case[1]) - 24.0) if float(case[1]) >= 110.0 else float(case[1]) - 3.0
				_ok("%s: type fits when drawn" % tag, float(lay.type_y) + desc <= tmax + 0.01)
			else:
				_ok("%s: type omitted (no room)" % tag, true)
		# The 90px card must degrade a 2-line name to 1 line, never overflow.
		var tight: Dictionary = cl.call("layout", 88.0, 90.0, 100.0, 140.0, 2, asc, desc)
		_ok("2-row card degrades 2-line name to 1 line", int(tight.lines) == 1,
			"got %d lines — 22+44+4+2x18 = 106 > 90 cannot fit" % int(tight.lines))
	# Drift guard: card_hand must consume CardLayout, not re-inline the math.
	var ch: String = FileAccess.get_file_as_string("res://scripts/ui/card_hand.gd")
	var full: int = ch.find("func _draw_full")
	var full_src: String = ch.substr(full, 2600) if full >= 0 else ""
	_ok("_draw_full consumes CardLayout.layout", full_src.contains("CardLayout.layout("),
		"card_hand re-inlines the layout math (baseline bug class can return)")
	_ok("_draw_full has no baseline-anchored name_top_y", not full_src.contains("name_top_y"),
		"name_top_y used as a draw_string y IS the BUG-30 baseline confusion")
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])
