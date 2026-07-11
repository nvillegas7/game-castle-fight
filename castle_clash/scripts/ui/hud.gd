## Top HUD bar showing match time and both castle HP bars.
extends Control

@onready var gold_label: Label = %GoldLabel
@onready var wave_label: Label = %WaveLabel
@onready var castle_label: Label = %CastleLabel

# Compact castle HP bars (own = green fill, enemy = red fill) replacing the
# old plain-text "HP %d | Foe %d" label. Built in code and parented to this
# Control directly — NOT to the HBox: a Container discards manual
# position/size on sort (project container rule). Panel children keep manual
# rects because Panel is a plain Control, not a Container.
# Reference (design/references/hud_target.png): YOU bar left, TIME banner center, FOE bar
# right — wood-framed glossy bars floating over the arena (no HUD strip).
const BAR_W: float = 200.0
const BAR_H: float = 34.0
const FILL_INSET_X: float = 14.0  # leave the bar_bg wood frame visible around the fill
const FILL_INSET_Y: float = 7.0
const HUD_W: float = 720.0  # Portrait viewport width (project-wide constant)
const HUD_H: float = 48.0   # Top strip height (HUD offset_bottom in the scene)

var _my_fill: Panel = null
var _en_fill: Panel = null
var _my_hp_label: Label = null
var _en_hp_label: Label = null
var _my_fill_tween: Tween = null
var _en_fill_tween: Tween = null
var _last_my_hp: int = -1
var _last_en_hp: int = -1
var _time_label: Label = null  # value line of the centered TIME banner


func _ready() -> void:
	EventBus.castle_damaged.connect(_on_castle_damaged)
	# Ensure HUD text is readable at 720x1280 (16px = native pixel-font size)
	gold_label.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
	wave_label.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
	# Plain-text castle HP is replaced by the graphical bars below; the HBox time text
	# is replaced by the centered TIME banner (reference).
	castle_label.visible = false
	wave_label.visible = false
	gold_label.visible = false
	_build_hp_bars()
	_build_time_banner()


func _process(_delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_update_wave_timer()
	_update_castle_hp()


func _update_wave_timer() -> void:
	if GameManager.simulation == null:
		return
	var total_seconds: int = GameManager.current_tick / GameManager.TICK_RATE
	var minutes: int = total_seconds / 60
	var secs: int = total_seconds % 60
	if _time_label:
		_time_label.text = "%d:%02d" % [minutes, secs]


func _build_hp_bars() -> void:
	var bar_y: float = (HUD_H - BAR_H) * 0.5
	var my_x: float = 8.0                       # YOU on the left (reference)
	var en_x: float = HUD_W - 8.0 - BAR_W        # FOE on the right
	var mine: Dictionary = _make_hp_bar(Vector2(my_x, bar_y),
		Color(0.30, 0.72, 0.32), Color(0.16, 0.42, 0.18))
	_my_fill = mine.fill
	_my_hp_label = mine.label
	var foe: Dictionary = _make_hp_bar(Vector2(en_x, bar_y),
		Color(0.82, 0.28, 0.22), Color(0.48, 0.14, 0.10))
	_en_fill = foe.fill
	_en_hp_label = foe.label


## Centered blue-gray stone banner (ribbon_dark): "TIME" over the m:ss value.
func _build_time_banner() -> void:
	var banner_w: float = 150.0
	var banner := Control.new()
	banner.name = "TimeBanner"
	banner.position = Vector2((HUD_W - banner_w) * 0.5, -4.0)
	banner.size = Vector2(banner_w, 56.0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := NinePatchRect.new()
	bg.texture = UIStyle.load_tex(UIStyle.NP + "ribbon_dark.png")
	bg.patch_margin_left = 90
	bg.patch_margin_right = 90
	bg.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	bg.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)
	var title := Label.new()
	title.text = "TIME"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 8.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
	title.add_theme_color_override("font_color", UIStyle.TEXT_CREAM)
	title.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
	title.add_theme_constant_override("outline_size", 2)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(title)
	var value := Label.new()
	value.text = "0:00"
	value.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	value.offset_top = 26.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
	value.add_theme_color_override("font_color", Color(1, 1, 1))
	value.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
	value.add_theme_constant_override("outline_size", 2)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(value)
	add_child(banner)
	_time_label = value


## One bar = trough Panel (dark, warm border) + fill Panel + centered numeric
## overlay Label (FULL_RECT preset inside the fixed-size trough).
func _make_hp_bar(pos: Vector2, fill_color: Color, fill_border: Color) -> Dictionary:
	var trough := Panel.new()
	# Tiny Swords wood-bar trough (StyleBoxTexture) replaces the flat vector capsule
	# that clashed with the hand-painted ribbon (audit: two rendering languages).
	trough.add_theme_stylebox_override("panel", UIStyle.bar_bg())
	trough.position = pos
	trough.size = Vector2(BAR_W, BAR_H)
	trough.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(trough)

	var fill := Panel.new()
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.border_color = fill_border
	fill_style.set_border_width_all(1)
	fill_style.set_corner_radius_all(2)
	fill.add_theme_stylebox_override("panel", fill_style)
	fill.position = Vector2(FILL_INSET_X, FILL_INSET_Y)
	fill.size = Vector2(BAR_W - FILL_INSET_X * 2.0, BAR_H - FILL_INSET_Y * 2.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trough.add_child(fill)

	# Glossy top highlight — lighter band on the top ~45% of the fill (follows the
	# fill width via anchors as HP drains).
	var gloss := Panel.new()
	var gloss_style := StyleBoxFlat.new()
	gloss_style.bg_color = fill_color.lightened(0.35)
	gloss_style.bg_color.a = 0.55
	gloss_style.set_corner_radius_all(2)
	gloss.add_theme_stylebox_override("panel", gloss_style)
	gloss.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	gloss.anchor_bottom = 0.45
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(gloss)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
	label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trough.add_child(label)

	return {"fill": fill, "label": label}


func _update_castle_hp() -> void:
	if GameManager.simulation == null or _my_fill == null:
		return
	var local_team: int = 0
	for player in GameManager.simulation.players:
		if player.id == GameManager.local_player_id:
			local_team = player.team
			break

	var enemy_team: int = 1 - local_team
	var my_castle: Dictionary = GameManager.simulation.castles[local_team]
	var enemy_castle: Dictionary = GameManager.simulation.castles[enemy_team]
	var my_hp: int = FP.to_int(my_castle.hp)
	var my_max: int = FP.to_int(my_castle.max_hp)
	var en_hp: int = FP.to_int(enemy_castle.hp)
	var en_max: int = FP.to_int(enemy_castle.max_hp)

	# Called every frame from _process — only touch nodes/tweens on change.
	if my_hp == _last_my_hp and en_hp == _last_en_hp:
		return
	var instant: bool = _last_my_hp < 0  # First update snaps, no tween
	_last_my_hp = my_hp
	_last_en_hp = en_hp

	_my_hp_label.text = "YOU %d" % my_hp
	_en_hp_label.text = "FOE %d" % en_hp
	_my_fill_tween = _tween_bar_fill(_my_fill, _my_fill_tween, my_hp, my_max, instant)
	_en_fill_tween = _tween_bar_fill(_en_fill, _en_fill_tween, en_hp, en_max, instant)


## Smooth the fill width toward the new HP ratio with a short ease-out tween.
func _tween_bar_fill(fill: Panel, tween: Tween, hp: int, max_hp: int, instant: bool) -> Tween:
	var ratio: float = clampf(float(hp) / maxf(float(max_hp), 1.0), 0.0, 1.0)
	var target_w: float = (BAR_W - FILL_INSET_X * 2.0) * ratio
	if instant:
		fill.size.x = target_w
		return null
	if tween and tween.is_valid():
		tween.kill()
	var tw := fill.create_tween()
	tw.tween_property(fill, "size:x", target_w, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


func _on_castle_damaged(_team: int, _damage: int, _remaining_hp: int, _attacker_id: int = -1) -> void:
	_update_castle_hp()
