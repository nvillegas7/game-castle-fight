## Contract test for the shared UIStyle kit (P0 foundation).
## Run: godot --headless --path castle_clash -s tests/test_ui_style.gd
##
## Guards the two audit root causes at the source: font sizes stay quantized to 16/32,
## and every panel factory resolves its ninepatch texture (so screens can't silently fall
## back to programmer-box StyleBoxFlat when a path breaks).
extends SceneTree

var _pass := 0
var _fail := 0


func _init() -> void:
	await process_frame
	print("\n=== UIStyle Kit Tests ===\n")
	_test_font_constants()
	_test_panel_factories_load_textures()
	_test_chip_and_widgets()
	_test_generated_assets_exist()
	print("\nTOTAL: %d PASS, %d FAIL" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: " + msg)


func _test_font_constants() -> void:
	# Pixel Operator Bold is 16px-native; non-16/32 sizes render mushy (lessons).
	_ok(UIStyle.FONT_BODY == 16, "FONT_BODY must be 16, got %d" % UIStyle.FONT_BODY)
	_ok(UIStyle.FONT_TITLE == 32, "FONT_TITLE must be 32, got %d" % UIStyle.FONT_TITLE)


func _test_panel_factories_load_textures() -> void:
	# Each factory must return a StyleBox whose ninepatch texture actually resolved —
	# a StyleBoxFlat means it fell back (broken path), which is a failure here.
	var boxes := {
		"paper_panel": UIStyle.paper_panel(),
		"wood_panel": UIStyle.wood_panel(),
		"slot_panel": UIStyle.slot_panel(),
		"ribbon_yellow": UIStyle.ribbon_style("yellow"),
		"ribbon_blue": UIStyle.ribbon_style("blue"),
		"ribbon_dark": UIStyle.ribbon_style("dark"),
		"bar_bg": UIStyle.bar_bg(),
		"bar_fill": UIStyle.bar_fill(),
	}
	for name in boxes:
		var sb = boxes[name]
		_ok(sb is StyleBoxTexture, "%s must be a StyleBoxTexture (path resolved), not a fallback" % name)
		if sb is StyleBoxTexture:
			_ok((sb as StyleBoxTexture).texture != null, "%s texture is null" % name)


func _test_chip_and_widgets() -> void:
	_ok(UIStyle.stat_chip() is StyleBoxFlat, "stat_chip must be a StyleBoxFlat")
	# Widgets must apply without error on fresh nodes.
	var lbl := Label.new()
	UIStyle.apply_tab_title(lbl, "SETTINGS")
	_ok(lbl.text == "SETTINGS", "apply_tab_title did not set text")
	_ok(lbl.get_theme_font_size("font_size") == 32, "tab title font size must be 32")
	var slider := HSlider.new()
	UIStyle.theme_slider(slider)
	_ok(slider.has_theme_stylebox_override("slider"), "theme_slider did not skin the track")
	_ok(slider.has_theme_icon_override("grabber"), "theme_slider did not set a grabber icon")
	var btn := Button.new()
	UIStyle.style_texture_button(btn)
	_ok(btn.has_theme_stylebox_override("normal"), "style_texture_button did not set normal box")
	lbl.free()
	slider.free()
	btn.free()


func _test_generated_assets_exist() -> void:
	for f in ["star_gold.png", "star_empty.png", "padlock.png"]:
		var t := UIStyle.load_tex(UIStyle.UI + f)
		_ok(t != null, "generated asset failed to load: %s" % f)
