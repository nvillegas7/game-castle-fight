class_name UIStyle
extends RefCounted
## Shared Tiny-Swords UI kit (P0 foundation for the screen-parity sweep).
##
## Single source of themed StyleBoxes, fonts, and palette so P1-P5 stop hand-rolling
## cold-navy/flat-gray StyleBoxFlat "programmer boxes" per screen. All members are static:
##   var sb := UIStyle.paper_panel()
##   UIStyle.apply_tab_title(label, "SETTINGS")
##
## Nine-patch kit lives in assets/sprites/ui/ninepatch/ (NOT assembled/, which is empty).
## Patch margins are measured (see tools/generate_ui_bits.py recon + plan-screen-parity.md).

const UI := "res://assets/sprites/ui/"
const NP := "res://assets/sprites/ui/ninepatch/"

# --- Fonts: Pixel Operator Bold is 16px-native; ONLY these render crisp. ---------------
const FONT_BODY := 16   # body / labels / card text
const FONT_TITLE := 32  # tab & screen titles (integer 2x of the pixel font)

# --- Palette (warm Tiny Swords wood/parchment; no cold navy, no raw grays) -------------
const TEXT_CREAM := Color(0.93, 0.87, 0.72)   # light text on wood/dark
const TEXT_DARK := Color(0.25, 0.16, 0.08)    # dark text on cream paper / tan ribbon
const TEXT_GOLD := Color(1.0, 0.85, 0.3)      # gold accent labels
const OUTLINE_DARK := Color(0.1, 0.07, 0.03)  # standard dark text outline
const PANEL_WOOD := Color(0.22, 0.16, 0.10)   # warm dark wood card fill
const PANEL_BORDER := Color(0.55, 0.42, 0.22) # warm wood border


# ============================ texture loading =========================================

## Robust loader: ResourceLoader first, raw-PNG filesystem fallback for un-imported art.
## Mirrors main_menu.gd:_load_texture so any script can theme without depending on MainMenu.
static func load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res and res is Texture2D:
			return res
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
		var img := Image.new()
		var err: int = img.load(abs_path if FileAccess.file_exists(abs_path) else path)
		if err == OK and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# ============================ panel factories =========================================

## Internal: build a StyleBoxTexture from a ninepatch asset with the given margins.
## Returns a warm StyleBoxFlat fallback (never null) if the texture fails to load.
static func _tex_box(path: String, ml: int, mr: int, mt: int, mb: int,
		cm := 12) -> StyleBox:
	var tex := load_tex(path)
	if tex == null:
		return _flat_fallback(cm)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = ml
	sb.texture_margin_right = mr
	sb.texture_margin_top = mt
	sb.texture_margin_bottom = mb
	sb.content_margin_left = maxi(cm, ml)
	sb.content_margin_right = maxi(cm, mr)
	sb.content_margin_top = maxi(cm, mt)
	sb.content_margin_bottom = maxi(cm, mb)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb


static func _flat_fallback(cm := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_WOOD
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(cm)
	return sb


## Cream parchment panel (regularpaper 168x153, near-uniform fill).
static func paper_panel(margin := 20) -> StyleBox:
	return _tex_box(NP + "regularpaper.png", margin, margin, margin, margin, 16)


## Warm wood-table panel (woodtable 232x252, thick bottom ledge → asymmetric margins).
static func wood_panel() -> StyleBox:
	return _tex_box(NP + "woodtable.png", 20, 20, 24, 40, 18)


## Inset slot cell (slots 109x167) — for shop/grid cells.
static func slot_panel() -> StyleBox:
	return _tex_box(NP + "slots.png", 20, 20, 20, 20, 10)


## Pointed ribbon strip (ribbon_yellow/blue/red/dark/purple 259x103, ~97px pointed ends).
static func ribbon_style(name := "yellow") -> StyleBox:
	return _tex_box(NP + "ribbon_%s.png" % name, 97, 97, 30, 30, 20)


## Bar trough (bigbar_base 112x64) — gold bar + HP pill backing.
static func bar_bg() -> StyleBox:
	return _tex_box(NP + "bigbar_base.png", 16, 16, 10, 10, 6)


## Bar fill (bigbar_fill 64x24) — elixir-style fill; modulate the host node to recolor.
static func bar_fill() -> StyleBox:
	return _tex_box(NP + "bigbar_fill.png", 8, 8, 4, 4, 0)


## Warm rounded chip (stat / role / gold-balance). Flat by design — small, crisp at any size.
static func stat_chip(bg := PANEL_WOOD, border := PANEL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


# ============================ text + widgets ==========================================

## Unify every tab/screen heading: gold FONT_TITLE, dark outline, centered.
## Replaces the inconsistent SOCIAL-24 / SETTINGS-28 hand-styling.
static func apply_tab_title(label: Label, text: String) -> void:
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_TITLE)
	label.add_theme_color_override("font_color", TEXT_GOLD)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 4)


## Theme an HSlider with the bar assets + a round grabber sized for a >=80px hit row.
## Grabber is resized to grabber_px so the effective hit area meets HIG regardless of source.
static func theme_slider(slider: HSlider, grabber_px := 40) -> void:
	var bg := bar_bg()
	if bg is StyleBoxTexture:
		(bg as StyleBoxTexture).content_margin_top = 0
		(bg as StyleBoxTexture).content_margin_bottom = 0
	slider.add_theme_stylebox_override("slider", bg)
	slider.add_theme_stylebox_override("grabber_area", bar_fill())
	slider.add_theme_stylebox_override("grabber_area_highlight", bar_fill())
	var grab := _scaled_tex(UI + "TinyRoundBlueButton.png", grabber_px)
	if grab:
		slider.add_theme_icon_override("grabber", grab)
		slider.add_theme_icon_override("grabber_highlight", grab)


## Skin a Button with the Tiny Swords plate (normal/pressed/hover) StyleBoxTexture set.
static func style_texture_button(btn: Button, base := "bigbluebutton_regular",
		pressed := "bigbluebutton_pressed") -> void:
	var normal := _tex_box(NP + base + ".png", 40, 40, 40, 48, 12)
	var down := _tex_box(NP + pressed + ".png", 40, 40, 40, 48, 12)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", down)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_stylebox_override("disabled", normal)


## Load a texture and resize it to a square target (crisp NEAREST) — for slider grabbers etc.
static func _scaled_tex(path: String, px: int) -> Texture2D:
	var tex := load_tex(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
