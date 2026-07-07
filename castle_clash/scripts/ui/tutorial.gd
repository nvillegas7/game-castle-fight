## Tutorial overlay system — dark overlay with spotlights, arrows, text bubbles.
## Added as CanvasLayer (layer 10) to game_arena at runtime.
## 3-step flow: place building → earn gold → destroy castle.
extends CanvasLayer

enum Step { CARD_SELECT, CARD_PLACE, EARN_GOLD, DESTROY_CASTLE, COMPLETE }

var _step: int = Step.CARD_SELECT
var _overlay: Control = null
var _dark: Control = null
var _spotlight: Control = null
var _arrow_label: Label = null
var _text_panel: PanelContainer = null
var _text_label: Label = null
var _got_it_btn: Button = null
var _skip_btn: Button = null
var _arrow_tween: Tween = null
var _step2_timer: float = 0.0

# Spotlight regions for each step (in game coordinates)
const CARD_HAND_RECT := Rect2(0, 1040, 720, 240)
const BUILD_ZONE_RECT := Rect2(206, 700, 308, 280)
const GOLD_BAR_RECT := Rect2(0, 1000, 720, 40)
const ENEMY_CASTLE_RECT := Rect2(255, 40, 210, 90)


func _ready() -> void:
	layer = 10
	_build_ui()
	_show_step(Step.CARD_SELECT)

	EventBus.building_placed.connect(_on_building_placed)
	EventBus.unit_attacked.connect(_on_first_combat)


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Dark overlay — custom drawn with spotlight cutout
	_dark = Control.new()
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_dark)

	# Spotlight rect (invisible — position data only, drawing done by _dark)
	_spotlight = Control.new()
	_spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spotlight.visible = false
	_overlay.add_child(_spotlight)

	# Arrow/instruction label (bobbing)
	_arrow_label = Label.new()
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_label.add_theme_font_size_override("font_size", 22)
	_arrow_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
	_arrow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_arrow_label.add_theme_constant_override("outline_size", 5)
	_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_arrow_label)

	# Text bubble
	_text_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.92)
	style.border_color = Color(0.9, 0.75, 0.2, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	_text_panel.add_theme_stylebox_override("panel", style)
	_text_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_text_panel)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 18)
	_text_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(350, 0)
	_text_panel.add_child(_text_label)

	# "Got it!" button
	_got_it_btn = Button.new()
	_got_it_btn.text = "Got it!"
	_got_it_btn.custom_minimum_size = Vector2(160, 48)
	_got_it_btn.add_theme_font_size_override("font_size", 18)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.5, 0.85)
	btn_style.border_color = Color(0.4, 0.7, 1.0)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(10)
	btn_style.set_content_margin_all(8)
	_got_it_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0.25, 0.55, 0.9)
	_got_it_btn.add_theme_stylebox_override("hover", btn_hover)
	var btn_press := btn_style.duplicate()
	btn_press.bg_color = Color(0.15, 0.4, 0.75)
	_got_it_btn.add_theme_stylebox_override("pressed", btn_press)
	_got_it_btn.pressed.connect(_on_got_it)
	_got_it_btn.visible = false
	_overlay.add_child(_got_it_btn)

	# "Skip Tutorial" button
	_skip_btn = Button.new()
	_skip_btn.text = "Skip"
	_skip_btn.custom_minimum_size = Vector2(80, 32)
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.15, 0.12, 0.1, 0.7)
	skip_style.border_color = Color(0.4, 0.35, 0.3, 0.5)
	skip_style.set_border_width_all(1)
	skip_style.set_corner_radius_all(6)
	skip_style.set_content_margin_all(4)
	_skip_btn.add_theme_stylebox_override("normal", skip_style)
	_skip_btn.position = Vector2(620, 12)
	_skip_btn.pressed.connect(_on_skip)
	_overlay.add_child(_skip_btn)


func _show_step(step: int) -> void:
	_step = step

	if _arrow_tween and _arrow_tween.is_valid():
		_arrow_tween.kill()

	match step:
		Step.CARD_SELECT:
			_set_spotlight(CARD_HAND_RECT)
			_arrow_label.text = "▼  TAP A CARD  ▼"
			_arrow_label.position = Vector2(160, 990)
			_arrow_label.size = Vector2(400, 30)
			_text_label.text = "Tap a building card to select it!"
			_text_panel.position = Vector2(120, 900)
			_text_panel.size = Vector2(480, 60)
			_got_it_btn.visible = false
			_start_arrow_bob(990, 8)
			_overlay.mouse_filter = Control.MOUSE_FILTER_PASS

		Step.CARD_PLACE:
			_set_spotlight(BUILD_ZONE_RECT)
			_arrow_label.text = "▼  TAP THE GRID  ▼"
			_arrow_label.position = Vector2(210, 670)
			_arrow_label.size = Vector2(300, 30)
			_text_label.text = "Tap the grid to place your building!"
			_text_panel.position = Vector2(150, 580)
			_text_panel.size = Vector2(420, 60)
			_got_it_btn.visible = false
			_start_arrow_bob(670, 8)

		Step.EARN_GOLD:
			_set_spotlight(GOLD_BAR_RECT)
			_arrow_label.text = "▲  GOLD  ▲"
			_arrow_label.position = Vector2(200, 1045)
			_arrow_label.size = Vector2(320, 30)
			_text_label.text = "Nice! You earn gold every 5 seconds.\nBuild more to overwhelm your enemy!"
			_text_panel.position = Vector2(100, 830)
			_text_panel.size = Vector2(520, 80)
			_got_it_btn.visible = true
			_got_it_btn.position = Vector2(280, 920)
			_start_arrow_bob(1045, -6)
			_step2_timer = 10.0  # Auto-advance after 10s

		Step.DESTROY_CASTLE:
			_set_spotlight(ENEMY_CASTLE_RECT)
			_arrow_label.text = "▼  DESTROY IT!  ▼"
			_arrow_label.position = Vector2(220, 15)
			_arrow_label.size = Vector2(280, 30)
			_text_label.text = "Your units fight automatically.\nDestroy the enemy castle to win!"
			_text_panel.position = Vector2(120, 150)
			_text_panel.size = Vector2(480, 80)
			_got_it_btn.visible = false
			_skip_btn.visible = false
			_start_arrow_bob(15, 8)
			# Auto-dismiss after 5 seconds
			var tw := create_tween()
			tw.tween_interval(5.0)
			tw.tween_callback(_complete_tutorial)

		Step.COMPLETE:
			_complete_tutorial()


var _spotlight_rect := Rect2(0, 1040, 720, 240)

func _set_spotlight(rect: Rect2) -> void:
	_spotlight_rect = rect
	if not _dark.draw.is_connected(_draw_dark_overlay):
		_dark.draw.connect(_draw_dark_overlay)
	_dark.queue_redraw()


func _draw_dark_overlay() -> void:
	var screen := Vector2(720, 1280)
	var margin: float = 8.0
	var expanded := Rect2(
		_spotlight_rect.position - Vector2(margin, margin),
		_spotlight_rect.size + Vector2(margin * 2, margin * 2)
	)

	var dark_color := Color(0, 0, 0, 0.55)
	# Top strip
	if expanded.position.y > 0:
		_dark.draw_rect(Rect2(0, 0, screen.x, expanded.position.y), dark_color)
	# Bottom strip
	var bot_y: float = expanded.end.y
	if bot_y < screen.y:
		_dark.draw_rect(Rect2(0, bot_y, screen.x, screen.y - bot_y), dark_color)
	# Left strip
	if expanded.position.x > 0:
		_dark.draw_rect(Rect2(0, expanded.position.y, expanded.position.x, expanded.size.y), dark_color)
	# Right strip
	var right_x: float = expanded.end.x
	if right_x < screen.x:
		_dark.draw_rect(Rect2(right_x, expanded.position.y, screen.x - right_x, expanded.size.y), dark_color)

	# Gold glow border around spotlight
	_dark.draw_rect(expanded, Color(1.0, 0.85, 0.3, 0.5), false, 3.0)


func _start_arrow_bob(base_y: float, amplitude: float) -> void:
	_arrow_label.position.y = base_y
	_arrow_tween = _arrow_label.create_tween().set_loops()
	_arrow_tween.tween_property(_arrow_label, "position:y", base_y + amplitude, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_arrow_tween.tween_property(_arrow_label, "position:y", base_y, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	# Auto-advance step 2 after timer
	if _step == Step.EARN_GOLD:
		_step2_timer -= delta
		if _step2_timer <= 0:
			_show_step(Step.DESTROY_CASTLE)


func _on_building_placed(_pid: int, _bd: Resource, _gp: Vector2i) -> void:
	if _step == Step.CARD_SELECT or _step == Step.CARD_PLACE:
		# Building placed — show celebration, then advance
		_text_label.text = "Nice! Buildings spawn units that fight!"
		_got_it_btn.visible = true
		_got_it_btn.position = Vector2(280, 920 if _step == Step.CARD_SELECT else 650)
		_text_panel.position = Vector2(120, 830 if _step == Step.CARD_SELECT else 500)
		_arrow_label.visible = false
		_step = Step.EARN_GOLD  # Will show on "Got it!"
	elif _step == Step.EARN_GOLD:
		# Second building placed — advance to step 3
		_show_step(Step.DESTROY_CASTLE)


func _on_first_combat(_attacker_id: int, _target_id: int, _damage: int, _tx: float, _ty: float) -> void:
	if _step == Step.DESTROY_CASTLE or _step == Step.EARN_GOLD:
		# First combat happened — show step 3 if not already
		if _step != Step.DESTROY_CASTLE:
			_show_step(Step.DESTROY_CASTLE)
		EventBus.unit_attacked.disconnect(_on_first_combat)


func _on_got_it() -> void:
	if _step == Step.EARN_GOLD:
		_arrow_label.visible = true
		_show_step(Step.EARN_GOLD)
	elif _step == Step.DESTROY_CASTLE:
		_complete_tutorial()
	else:
		# After first building placed, show step 2
		_arrow_label.visible = true
		_show_step(Step.EARN_GOLD)


func _on_skip() -> void:
	_complete_tutorial()


func _complete_tutorial() -> void:
	if _step == Step.COMPLETE:
		return  # Already completing
	_step = Step.COMPLETE
	GameManager.advance_tutorial(4)  # Marks tutorial complete
	# Disconnect signals
	if EventBus.building_placed.is_connected(_on_building_placed):
		EventBus.building_placed.disconnect(_on_building_placed)
	if EventBus.unit_attacked.is_connected(_on_first_combat):
		EventBus.unit_attacked.disconnect(_on_first_combat)
	# Fade out overlay
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)


func _on_card_selected() -> void:
	# Called when a card is tapped — advance from CARD_SELECT to CARD_PLACE
	if _step == Step.CARD_SELECT:
		_show_step(Step.CARD_PLACE)
