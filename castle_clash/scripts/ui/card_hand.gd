## Clash Royale-style card hand for building selection.
## Horizontal row of building cards at the bottom of the screen.
extends Control

signal building_selected(building_data: BuildingData)

var _cards: Array[Control] = []
var _current_faction: FactionData = null
var _selected_index: int = -1
var _hand: Array[BuildingData] = []  # All faction buildings visible at once

const CARD_W: float = 88.0
const CARD_H: float = 130.0
const CARD_GAP: float = 6.0
const CARD_CORNER: float = 10.0

const ATTACK_NAMES := ["Phys", "Pierce", "Magic", "Siege"]
const ROLE_NAMES := ["Melee", "Ranged", "Caster", "Flying", "Siege"]


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.gold_changed.connect(_on_gold_changed)


func _on_match_started() -> void:
	_current_faction = GameManager.get_player_faction(GameManager.local_player_id)
	if _current_faction == null:
		push_error("[card_hand] faction is null for local_id=%d — no cards built" % GameManager.local_player_id)
		return
	_build_cards()


func _build_cards() -> void:
	for child in get_children():
		if child.name != "CardBg":
			child.queue_free()
	_cards.clear()
	_selected_index = -1

	# Show ALL faction buildings at once (no deck cycling)
	_hand.clear()
	for bd: BuildingData in _current_faction.buildings:
		_hand.append(bd)

	_rebuild_hand_visuals()


func _rebuild_hand_visuals() -> void:
	# Clear old card visuals
	for child in get_children():
		if child.name != "CardBg":
			child.queue_free()
	_cards.clear()

	var card_count: int = _hand.size()
	if card_count == 0:
		return

	# 2-row layout with padding matching wood table borders
	var pad_x: float = 24.0
	var pad_y: float = 28.0
	var available_w: float = 720.0 - pad_x * 2
	var row_gap: float = 4.0

	if card_count <= 6:
		# Single row
		var actual_card_w: float = minf(CARD_W, (available_w - (card_count - 1) * CARD_GAP) / card_count)
		var total_w: float = card_count * (actual_card_w + CARD_GAP) - CARD_GAP
		var start_x: float = (720.0 - total_w) * 0.5
		var usable_h: float = size.y - pad_y * 2
		var card_h: float = minf(CARD_H, usable_h)
		var card_y: float = pad_y + (usable_h - card_h) * 0.5
		for i in _hand.size():
			_add_card_at(i, start_x + i * (actual_card_w + CARD_GAP), card_y, actual_card_w, card_h)
	else:
		# 2-row layout
		var top_count: int = ceili(card_count / 2.0)
		var bot_count: int = card_count - top_count
		var usable_h: float = size.y - pad_y * 2
		var card_h: float = (usable_h - row_gap) / 2.0

		# Top row
		var tw: float = minf(CARD_W, (available_w - (top_count - 1) * CARD_GAP) / top_count)
		var top_total: float = top_count * (tw + CARD_GAP) - CARD_GAP
		var top_x: float = (720.0 - top_total) * 0.5
		for i in top_count:
			_add_card_at(i, top_x + i * (tw + CARD_GAP), pad_y, tw, card_h)

		# Bottom row
		var bw: float = minf(CARD_W, (available_w - (bot_count - 1) * CARD_GAP) / bot_count)
		var bot_total: float = bot_count * (bw + CARD_GAP) - CARD_GAP
		var bot_x: float = (720.0 - bot_total) * 0.5
		var bot_y: float = pad_y + card_h + row_gap
		for i in bot_count:
			_add_card_at(top_count + i, bot_x + i * (bw + CARD_GAP), bot_y, bw, card_h)

	_update_card_states()


func _add_card_at(index: int, x: float, y: float, w: float, h: float) -> void:
	var bd: BuildingData = _hand[index]
	var card := _CardVisual.new()
	card.bd = bd
	card.index = index
	card.position = Vector2(x, y)
	card.size = Vector2(w, h)
	card.card_pressed.connect(_on_card_pressed)
	add_child(card)
	_cards.append(card)


func _on_card_pressed(index: int) -> void:
	SFX.play_ui("card_select")
	if index == _selected_index:
		_selected_index = -1  # Deselect
		_update_selection()
		building_selected.emit(null)
	else:
		_selected_index = index
		_update_selection()
		if _selected_index >= 0 and _selected_index < _hand.size():
			building_selected.emit(_hand[_selected_index])


## Called by external signal when grid deselects (e.g. right-click)
func force_deselect() -> void:
	if _selected_index != -1:
		_selected_index = -1
		_update_selection()


## T-050: Return cheapest building cost from hand (for gold bar marker)
func get_cheapest_cost() -> int:
	var cheapest: int = 999999
	for bd: BuildingData in _hand:
		if bd.gold_cost < cheapest:
			cheapest = bd.gold_cost
	return cheapest if cheapest < 999999 else 0


## Called after a building is successfully placed. Card stays (can build multiples).
func card_played(_building_type: StringName) -> void:
	_selected_index = -1
	_update_selection()
	_update_card_states()


func _on_gold_changed(player_id: int, _new_gold: int) -> void:
	if player_id == GameManager.local_player_id:
		_update_card_states()


func _update_card_states() -> void:
	if _current_faction == null or GameManager.simulation == null:
		return
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)

	for i in _cards.size():
		if i >= _hand.size():
			break
		var bd: BuildingData = _hand[i]  # Use hand, not faction.buildings
		var can_afford: bool = gold >= bd.gold_cost
		var has_prereq: bool = bd.requires_building == &"" or \
			GameManager.simulation.player_has_building(pi, bd.requires_building)
		_cards[i].set_state(can_afford, has_prereq)


func _update_selection() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _selected_index)


# --- Inner Card Visual ---

class _CardVisual extends Control:
	signal card_pressed(index: int)

	var bd: BuildingData = null
	var index: int = 0
	var _can_afford: bool = true
	var _has_prereq: bool = true
	var _is_selected: bool = false
	var _hover: bool = false
	var _building_icon: Texture2D = null
	var _select_pulse_tween: Tween = null  # T-039: gold border pulse
	var _star_tex: Texture2D = null        # pixel tier star (P0 asset)
	var _padlock_tex: Texture2D = null     # locked-card padlock (P0 asset)

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_hover = true; queue_redraw()
			SFX.play_ui("card_hover")
		)
		mouse_exited.connect(func(): _hover = false; queue_redraw())
		# Load building icon for this card
		if bd:
			_building_icon = SpriteRegistry.get_building_sprite(bd.id, 0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _can_afford and _has_prereq:
				card_pressed.emit(index)
				accept_event()
			else:
				SFX.play_ui("card_denied")
				accept_event()

	func set_state(can_afford: bool, has_prereq: bool) -> void:
		_can_afford = can_afford
		_has_prereq = has_prereq
		queue_redraw()

	func set_selected(selected: bool) -> void:
		_is_selected = selected
		# T-039: Pulse gold border on selected card
		if _select_pulse_tween and _select_pulse_tween.is_valid():
			_select_pulse_tween.kill()
			_select_pulse_tween = null
		if selected:
			_select_pulse_tween = create_tween().set_loops()
			_select_pulse_tween.tween_property(self, "modulate", Color(1.15, 1.1, 0.95), 0.4)
			_select_pulse_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.4)
		else:
			modulate = Color.WHITE
		queue_redraw()

	var _card_style: StyleBox = null      # Tiny Swords wood slot (StyleBoxTexture from UIStyle)
	var _badge_style: StyleBoxFlat = null

	func _create_styles() -> void:
		# Warm wood-slot card box (matches the tray) — replaces the flat programmer StyleBoxFlat.
		# State (selected/hover/disabled) is drawn as overlays in _draw, since a StyleBoxTexture
		# has no bg_color to recolor.
		_card_style = UIStyle.slot_panel()

		_badge_style = StyleBoxFlat.new()
		_badge_style.bg_color = Color(0.9, 0.75, 0.15)
		_badge_style.border_color = Color(0.65, 0.5, 0.08)
		_badge_style.set_border_width_all(1)
		_badge_style.set_corner_radius_all(6)

		_star_tex = UIStyle.load_tex(UIStyle.UI + "star_gold.png")
		_padlock_tex = UIStyle.load_tex(UIStyle.UI + "padlock.png")


	func _draw() -> void:
		if bd == null:
			return
		if _card_style == null:
			_create_styles()

		var w: float = size.x
		var h: float = size.y
		var enabled: bool = _can_afford and _has_prereq
		var compact: bool = h < 60  # Compact mode for 4-row layout

		# Base wood-slot box, then a state overlay on top (StyleBoxTexture can't recolor).
		draw_style_box(_card_style, Rect2(0, 0, w, h))
		if not enabled:
			var dim := StyleBoxFlat.new()
			dim.bg_color = Color(0.0, 0.0, 0.0, 0.28)
			dim.set_corner_radius_all(8)
			draw_style_box(dim, Rect2(0, 0, w, h))
		elif _is_selected:
			draw_rect(Rect2(1.5, 1.5, w - 3, h - 3), Color(1.0, 0.8, 0.2, 0.95), false, 3.0)
		elif _hover:
			var hl := StyleBoxFlat.new()
			hl.bg_color = Color(1.0, 1.0, 1.0, 0.07)
			hl.set_corner_radius_all(8)
			draw_style_box(hl, Rect2(0, 0, w, h))

		if compact:
			_draw_compact(w, h, enabled)
		else:
			_draw_full(w, h, enabled)


	func _draw_compact(w: float, h: float, enabled: bool) -> void:
		# Compact card: icon left, name + cost right
		var icon_area: float = h - 6  # Square icon area
		var tint: Color = Color.WHITE if enabled else Color(0.5, 0.5, 0.5)

		# Building icon (left side)
		if _building_icon:
			var tex_w: float = _building_icon.get_width()
			var tex_h: float = _building_icon.get_height()
			var icon_scale: float = (icon_area - 4) / maxf(tex_w, tex_h)
			draw_texture_rect(_building_icon, Rect2(4, 3, tex_w * icon_scale, tex_h * icon_scale), false, tint)

		# Building name (right of icon, top) — 16px (native pixel-font), ellipsized on overflow.
		var text_x: float = icon_area + 4
		var text_w: float = w - text_x - 4
		var name_text: String = _fit_text(bd.display_name, text_w, UIStyle.FONT_BODY)
		draw_string(ThemeDB.fallback_font, Vector2(text_x, 18), name_text, HORIZONTAL_ALIGNMENT_LEFT, text_w, UIStyle.FONT_BODY, Color(0.95, 0.9, 0.75) if enabled else Color(0.5, 0.5, 0.5))

		# Cost (right of icon, bottom)
		draw_string(ThemeDB.fallback_font, Vector2(text_x, h - 5), "%dg" % bd.gold_cost, HORIZONTAL_ALIGNMENT_LEFT, text_w, UIStyle.FONT_BODY, Color(1.0, 0.85, 0.2) if enabled else Color(0.5, 0.45, 0.2))


	func _draw_full(w: float, h: float, enabled: bool) -> void:
		var font := ThemeDB.fallback_font
		var fs: int = UIStyle.FONT_BODY  # 16 — native pixel-font size

		# Building icon — centered, slightly smaller so the 16px name has vertical room.
		var icon_bottom: float = 6.0
		if _building_icon:
			var icon_size: float = minf(w * 0.52, 44.0)
			var tex_w: float = _building_icon.get_width()
			var tex_h: float = _building_icon.get_height()
			var icon_scale: float = icon_size / maxf(tex_w, tex_h)
			var iw: float = tex_w * icon_scale
			var ih: float = tex_h * icon_scale
			var icon_x: float = (w - iw) * 0.5
			var icon_y: float = 6.0
			# Locked/unaffordable icons desaturate toward gray.
			var icon_tint: Color = Color.WHITE if enabled else Color(0.6, 0.6, 0.6)
			draw_texture_rect(_building_icon, Rect2(icon_x, icon_y, iw, ih), false, icon_tint)
			icon_bottom = icon_y + ih

		# Gold cost badge — TOP-LEFT corner (Clash Royale style), 16px.
		var badge_w: float = minf(w * 0.52, 46.0)
		var badge_h: float = 20.0
		var badge_x: float = 3.0
		var badge_y: float = 3.0
		var badge := _badge_style.duplicate()
		if not enabled:
			badge.bg_color = Color(0.15, 0.1, 0.04, 0.95)
			badge.border_color = Color(0.65, 0.5, 0.1, 0.85)
		draw_style_box(badge, Rect2(badge_x, badge_y, badge_w, badge_h))
		var cost_color: Color = Color(0.15, 0.1, 0.0) if enabled else Color(1.0, 0.85, 0.25)
		draw_string(font, Vector2(badge_x, badge_y + 15), "%dg" % bd.gold_cost, HORIZONTAL_ALIGNMENT_CENTER, badge_w, fs, cost_color)

		# LOCKED cards: grayscale icon (drawn above) under a light overlay + a padlock
		# glyph + "Need: <building>" — no red "LOCKED" text (backlog 3.3).
		if not _has_prereq:
			var lock_overlay := StyleBoxFlat.new()
			lock_overlay.bg_color = Color(0, 0, 0, 0.35)
			lock_overlay.set_corner_radius_all(10)
			draw_style_box(lock_overlay, Rect2(0, 0, w, h))
			if _padlock_tex:
				var pw: float = 22.0
				var ph: float = pw * float(_padlock_tex.get_height()) / float(_padlock_tex.get_width())
				draw_texture_rect(_padlock_tex, Rect2((w - pw) * 0.5, h * 0.40 - ph, pw, ph), false, Color(1, 1, 1, 0.95))
			if bd.requires_building != &"":
				var req_name: String = _prettify_building_id(bd.requires_building)
				var need_y: float = h * 0.40 + 8.0
				draw_string(font, Vector2(4, need_y), "Need:", HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, Color(0.88, 0.74, 0.58))
				draw_string(font, Vector2(2, need_y + 18.0), _fit_text(req_name, w - 4.0, fs), HORIZONTAL_ALIGNMENT_CENTER, w - 4, fs, Color(0.88, 0.74, 0.58))
			return  # Skip name/type/stats — the padlock pair owns the space

		# Building name (centered below the icon), 16px, up to two wrapped lines.
		var name_top_y: float = (icon_bottom + 4.0) if _building_icon else 18.0
		var name_lines: PackedStringArray = _wrap_two_lines(bd.display_name, w - 8.0, fs)
		for li in name_lines.size():
			draw_string(font, Vector2(4, name_top_y + li * 18.0), name_lines[li], HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, Color(0.96, 0.91, 0.76))
		var below_name_y: float = name_top_y + (name_lines.size() - 1) * 18.0 + 20.0

		# Type indicator — only when it still fits (a two-line name eats the row).
		var type_text: String = ""
		var type_col: Color = Color(0.75, 0.7, 0.6)
		if bd.is_tower:
			type_text = "Tower"
			type_col = Color(1.0, 0.72, 0.62)   # audit: >=4.5:1 on inner panel
		elif bd.income_bonus > 0:
			type_text = "Income"
			type_col = Color(0.9, 0.78, 0.4)
		elif bd.spawns_unit:
			type_text = "Spawner"
			type_col = Color(0.65, 0.85, 0.58)  # audit: raise from 4.17:1
		if type_text != "" and below_name_y <= h - 6.0:
			draw_string(font, Vector2(4, below_name_y), type_text, HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, type_col)

		# Stats line — only on the tall single-row layout.
		if h >= 110:
			var stat_text: String = ""
			var stat_col: Color = Color(0.78, 0.88, 0.62)
			if bd.spawns_unit:
				var ud = bd.spawns_unit
				stat_text = "HP %d  Dmg %d" % [ud.max_hp, ud.attack_damage]
			elif bd.is_tower:
				stat_text = "Dmg %d  Rng %d" % [bd.tower_damage, bd.tower_range]
				stat_col = Color(0.88, 0.62, 0.56)
			elif bd.income_bonus > 0:
				stat_text = "+%d gold" % bd.income_bonus
				stat_col = Color(0.9, 0.78, 0.42)
			if stat_text != "":
				if font.get_string_size(stat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w - 8.0:
					draw_string(font, Vector2(4, h - 8), stat_text, HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, stat_col)
				else:
					var parts: PackedStringArray = stat_text.split(" ", false, 1)
					draw_string(font, Vector2(4, h - 26), _fit_text(parts[0], w - 8.0, fs), HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, stat_col)
					if parts.size() > 1:
						draw_string(font, Vector2(4, h - 8), _fit_text(parts[1], w - 8.0, fs), HORIZONTAL_ALIGNMENT_CENTER, w - 8, fs, stat_col)

		# Tier stars (top-right — opposite corner from the cost badge), pixel-art star.
		if bd.tier > 1:
			if _star_tex:
				var sp: float = 12.0
				for s in bd.tier:
					draw_texture_rect(_star_tex, Rect2(w - 6.0 - (s + 1) * (sp + 2.0), 4.0, sp, sp), false, Color.WHITE)
			else:
				for s in bd.tier:
					draw_circle(Vector2(w - 8 - s * 8, 11), 4, Color(1.0, 0.85, 0.2))


	## Ellipsize text so it fits max_w at font_size ("Demolisher Wo…").
	## Used instead of shrinking below the 12px mobile floor (BUG-41).
	static func _fit_text(text: String, max_w: float, font_size: int) -> String:
		var font := ThemeDB.fallback_font
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return text
		var t: String = text
		while t.length() > 1:
			t = t.substr(0, t.length() - 1)
			var cand: String = t.strip_edges() + "…"
			if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
				return cand
		return "…"

	## Split text into at most two lines at a word boundary (greedy fill),
	## ellipsizing whatever still overflows. Returns 1 or 2 lines.
	static func _wrap_two_lines(text: String, max_w: float, font_size: int) -> PackedStringArray:
		var font := ThemeDB.fallback_font
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return PackedStringArray([text])
		var words: PackedStringArray = text.split(" ")
		if words.size() == 1:
			return PackedStringArray([_fit_text(text, max_w, font_size)])
		var line1: String = words[0]
		var idx: int = 1
		while idx < words.size():
			var cand: String = line1 + " " + words[idx]
			if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
				line1 = cand
				idx += 1
			else:
				break
		var line2: String = " ".join(words.slice(idx))
		return PackedStringArray([
			_fit_text(line1, max_w, font_size),
			_fit_text(line2, max_w, font_size),
		])

	## Turn a snake_case building id (priest_temple) into a readable
	## "Priest Temple" for the LOCKED Need hint. Keeps it self-contained so
	## we don't need to look up the requires_building's BuildingData.
	func _prettify_building_id(id: StringName) -> String:
		var raw: String = String(id).replace("_", " ")
		var words: PackedStringArray = raw.split(" ")
		for i in words.size():
			if words[i].length() > 0:
				words[i] = words[i][0].to_upper() + words[i].substr(1)
		return " ".join(words)
