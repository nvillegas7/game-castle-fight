## Clash Royale-style card hand for building selection.
## Horizontal row of building cards at the bottom of the screen.
extends Control

signal building_selected(building_data: BuildingData)

var _cards: Array[Control] = []
var _current_faction: FactionData = null
var _selected_index: int = -1
var _hand: Array[BuildingData] = []  # All faction buildings visible at once

const CARD_W: float = 84.0
const CARD_H: float = 130.0
const CARD_GAP: float = 4.0
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

	var _card_style: StyleBoxFlat = null
	var _card_style_selected: StyleBoxFlat = null
	var _card_style_disabled: StyleBoxFlat = null
	var _badge_style: StyleBoxFlat = null

	func _create_styles() -> void:
		_card_style = StyleBoxFlat.new()
		_card_style.bg_color = Color(0.35, 0.28, 0.18)
		_card_style.border_color = Color(0.55, 0.42, 0.25, 0.7)
		_card_style.set_border_width_all(2)
		_card_style.set_corner_radius_all(10)
		_card_style.shadow_color = Color(0, 0, 0, 0.5)
		_card_style.shadow_size = 4
		_card_style.shadow_offset = Vector2(1, 2)

		_card_style_selected = _card_style.duplicate()
		_card_style_selected.bg_color = Color(0.45, 0.38, 0.22)
		_card_style_selected.border_color = Color(1.0, 0.8, 0.2, 0.95)
		_card_style_selected.set_border_width_all(3)
		_card_style_selected.shadow_color = Color(0.8, 0.6, 0.1, 0.3)
		_card_style_selected.shadow_size = 8

		_card_style_disabled = _card_style.duplicate()
		_card_style_disabled.bg_color = Color(0.2, 0.16, 0.12)
		_card_style_disabled.border_color = Color(0.3, 0.25, 0.18, 0.4)
		_card_style_disabled.shadow_size = 2

		_badge_style = StyleBoxFlat.new()
		_badge_style.bg_color = Color(0.9, 0.75, 0.15)
		_badge_style.border_color = Color(0.65, 0.5, 0.08)
		_badge_style.set_border_width_all(1)
		_badge_style.set_corner_radius_all(6)


	func _draw() -> void:
		if bd == null:
			return
		if _card_style == null:
			_create_styles()

		var w: float = size.x
		var h: float = size.y
		var enabled: bool = _can_afford and _has_prereq
		var compact: bool = h < 60  # Compact mode for 4-row layout

		# Card background (rounded)
		var style: StyleBoxFlat
		if not enabled:
			style = _card_style_disabled
		elif _is_selected:
			style = _card_style_selected
		elif _hover:
			var s := _card_style.duplicate()
			s.bg_color = _card_style.bg_color.lightened(0.08)
			s.border_color = Color(0.65, 0.5, 0.3, 0.8)
			style = s
		else:
			style = _card_style
		draw_style_box(style, Rect2(0, 0, w, h))

		if compact:
			_draw_compact(w, h, enabled, style)
		else:
			_draw_full(w, h, enabled, style)


	func _draw_compact(w: float, h: float, enabled: bool, style: StyleBoxFlat) -> void:
		# Compact card: icon left, name + cost right
		var icon_area: float = h - 6  # Square icon area
		var tint: Color = Color.WHITE if enabled else Color(0.5, 0.5, 0.5)

		# Building icon (left side)
		if _building_icon:
			var tex_w: float = _building_icon.get_width()
			var tex_h: float = _building_icon.get_height()
			var icon_scale: float = (icon_area - 4) / maxf(tex_w, tex_h)
			draw_texture_rect(_building_icon, Rect2(4, 3, tex_w * icon_scale, tex_h * icon_scale), false, tint)

		# Building name (right of icon, top) — 12px floor (mobile QA gate),
		# ellipsized instead of shrunk when the name overflows the text area.
		var text_x: float = icon_area + 4
		var text_w: float = w - text_x - 4
		var name_text: String = _fit_text(bd.display_name, text_w, 12)
		draw_string(ThemeDB.fallback_font, Vector2(text_x, 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, text_w, 12, Color(0.95, 0.9, 0.75) if enabled else Color(0.5, 0.5, 0.5))

		# Cost (right of icon, bottom)
		draw_string(ThemeDB.fallback_font, Vector2(text_x, h - 5), "%dg" % bd.gold_cost, HORIZONTAL_ALIGNMENT_LEFT, text_w, 12, Color(1.0, 0.85, 0.2) if enabled else Color(0.5, 0.45, 0.2))


	func _draw_full(w: float, h: float, enabled: bool, style: StyleBoxFlat) -> void:
		# Inner parchment highlight
		var inner := StyleBoxFlat.new()
		inner.bg_color = style.bg_color.lightened(0.1)
		inner.set_corner_radius_all(7)
		draw_style_box(inner, Rect2(5, 5, w - 10, h - 10))

		# Building icon (proportional to card width). Slightly smaller than the
		# pre-BUG-41 52px so the 12px (possibly two-line) name below has room.
		if _building_icon:
			var icon_size: float = minf(w * 0.6, 48.0)
			var tex_w: float = _building_icon.get_width()
			var tex_h: float = _building_icon.get_height()
			var icon_scale: float = icon_size / maxf(tex_w, tex_h)
			var icon_x: float = (w - tex_w * icon_scale) * 0.5
			var icon_y: float = 6.0
			draw_texture_rect(_building_icon, Rect2(icon_x, icon_y, tex_w * icon_scale, tex_h * icon_scale), false, Color.WHITE if enabled else Color(0.5, 0.5, 0.5))

		# T-073: Gold cost badge — TOP-LEFT corner (Clash Royale style), not bottom
		# This frees up the bottom area for name/type/stats without overlap.
		# Widened for the 12px cost text (mobile QA gate: no sub-12px text).
		var badge_w: float = minf(w * 0.5, 40.0)
		var badge_h: float = 17.0
		var badge_x: float = 3.0
		var badge_y: float = 3.0
		var badge := _badge_style.duplicate()
		if not enabled:
			# Darker bg + bright gold text for legibility (was unreadable
			# dark-on-dark previously). Keep contrast even when disabled.
			badge.bg_color = Color(0.15, 0.1, 0.04, 0.95)
			badge.border_color = Color(0.65, 0.5, 0.1, 0.85)
		draw_style_box(badge, Rect2(badge_x, badge_y, badge_w, badge_h))
		# Cost text: dark on bright when affordable (matches bright gold badge),
		# bright gold on dark when disabled (high contrast for legibility).
		var cost_color: Color
		if enabled:
			cost_color = Color(0.15, 0.1, 0.0)
		else:
			cost_color = Color(1.0, 0.85, 0.25)
		draw_string(ThemeDB.fallback_font, Vector2(badge_x, badge_y + 13), "%dg" % bd.gold_cost, HORIZONTAL_ALIGNMENT_CENTER, badge_w, 12, cost_color)

		# BUG-45 / BUG-41 fix: LOCKED cards render JUST the LOCKED label + the
		# requirements hint. Hiding name/type/stats prevents the 4-way label
		# overlap (name + type + stats + LOCKED + hint all at same y). The
		# icon already draws underneath at reduced tint.
		if not _has_prereq:
			var lock_overlay := StyleBoxFlat.new()
			lock_overlay.bg_color = Color(0, 0, 0, 0.55)
			lock_overlay.set_corner_radius_all(10)
			draw_style_box(lock_overlay, Rect2(0, 0, w, h))
			# BUG-41: "Need: %s" used to draw at 10px on one line and still
			# clipped ("Need: Priest Temple" = 117px vs 76px area at 12px).
			# Now 12px on TWO lines: "Need:" + the building name (ellipsized).
			var lock_y: float = h * 0.5 - 12.0
			draw_string(ThemeDB.fallback_font, Vector2(4, lock_y), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, w - 8, 14, Color(1.0, 0.35, 0.25))
			if bd.requires_building != &"":
				var req_name: String = _prettify_building_id(bd.requires_building)
				draw_string(ThemeDB.fallback_font, Vector2(4, lock_y + 16), "Need:", HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, Color(0.85, 0.7, 0.55))
				draw_string(ThemeDB.fallback_font, Vector2(2, lock_y + 30), _fit_text(req_name, w - 4.0, 12), HORIZONTAL_ALIGNMENT_CENTER, w - 4, 12, Color(0.85, 0.7, 0.55))
			return  # Skip name/type/stats — they'd overlap the LOCKED pair

		# Building name (centered, below icon). BUG-41 mobile readability pass:
		# 12px floor everywhere (project QA gate). Long names wrap to two lines
		# at a word boundary instead of shrinking the font; each line is
		# ellipsized if a single word still overflows.
		var font := ThemeDB.fallback_font
		var name_top_y: float = 66.0 if _building_icon else 16.0
		var name_lines: PackedStringArray = _wrap_two_lines(bd.display_name, w - 8.0, 12)
		for li in name_lines.size():
			draw_string(font, Vector2(4, name_top_y + li * 13.0), name_lines[li], HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, Color(0.95, 0.9, 0.75))
		# Baseline of the row below the name block (name lines + 15px gap).
		var below_name_y: float = name_top_y + (name_lines.size() - 1) * 13.0 + 15.0

		# Type indicator — only when it still fits inside the card (a two-line
		# name on a 2-row-layout card uses up the type row's space).
		var type_text: String = ""
		var type_col: Color = Color(0.7, 0.65, 0.55)
		if bd.is_tower:
			type_text = "Tower"
			type_col = Color(0.8, 0.5, 0.45)
		elif bd.income_bonus > 0:
			type_text = "Income"
			type_col = Color(0.85, 0.75, 0.35)
		elif bd.spawns_unit:
			type_text = "Spawner"
			type_col = Color(0.55, 0.75, 0.5)
		if type_text != "" and below_name_y <= h - 6.0:
			draw_string(font, Vector2(4, below_name_y), type_text, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, type_col)

		# Stats line — only when card is tall enough (single-row layout).
		# 12px floor: a stat string too wide for one line ("HP:620 Dmg:45" =
		# 88px vs 76px) splits at its first space into two stacked lines
		# instead of shrinking below 12px.
		if h >= 110:
			var stat_text: String = ""
			var stat_col: Color = Color(0.75, 0.85, 0.6)
			if bd.spawns_unit:
				var ud = bd.spawns_unit
				stat_text = "HP:%d Dmg:%d" % [ud.max_hp, ud.attack_damage]
			elif bd.is_tower:
				stat_text = "Dmg:%d Rng:%d" % [bd.tower_damage, bd.tower_range]
				stat_col = Color(0.85, 0.6, 0.55)
			elif bd.income_bonus > 0:
				stat_text = "+%d gold/tick" % bd.income_bonus
				stat_col = Color(0.88, 0.75, 0.4)
			if stat_text != "":
				if font.get_string_size(stat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= w - 8.0:
					draw_string(font, Vector2(4, h - 8), stat_text, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, stat_col)
				else:
					var parts: PackedStringArray = stat_text.split(" ", false, 1)
					draw_string(font, Vector2(4, h - 21), _fit_text(parts[0], w - 8.0, 12), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, stat_col)
					if parts.size() > 1:
						draw_string(font, Vector2(4, h - 8), _fit_text(parts[1], w - 8.0, 12), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, stat_col)

		# Tier stars (top-right — opposite corner from cost badge)
		if bd.tier > 1:
			for s in bd.tier:
				draw_circle(Vector2(w - 8 - s * 8, 11), 3, Color(1.0, 0.85, 0.2))


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
