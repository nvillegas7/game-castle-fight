## Clash Royale-style card hand for building selection.
## Horizontal row of building cards at the bottom of the screen.
extends Control

signal building_selected(building_data: BuildingData)

var _cards: Array[Control] = []
var _current_faction: FactionData = null
var _selected_index: int = -1
var _deck: Array[BuildingData] = []  # Shuffled full deck
var _hand: Array[BuildingData] = []  # 4 visible cards
var _next_card: BuildingData = null   # Next card preview
const HAND_SIZE: int = 4

const CARD_W: float = 130.0
const CARD_H: float = 120.0
const CARD_GAP: float = 8.0
const CARD_CORNER: float = 8.0

const ATTACK_NAMES := ["Phys", "Pierce", "Magic", "Siege"]
const ROLE_NAMES := ["Melee", "Ranged", "Caster", "Flying", "Siege"]


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.gold_changed.connect(_on_gold_changed)


func _on_match_started() -> void:
	_current_faction = GameManager.get_player_faction(GameManager.local_player_id)
	if _current_faction == null:
		return
	_build_cards()


func _build_cards() -> void:
	for child in get_children():
		if child.name != "CardBg":
			child.queue_free()
	_cards.clear()
	_selected_index = -1

	# Build shuffled deck from faction buildings
	_deck.clear()
	for bd: BuildingData in _current_faction.buildings:
		_deck.append(bd)

	# Draw initial hand (first HAND_SIZE cards)
	_hand.clear()
	for i in mini(HAND_SIZE, _deck.size()):
		_hand.append(_deck[i])
	_next_card = _deck[HAND_SIZE] if _deck.size() > HAND_SIZE else null

	_rebuild_hand_visuals()


func _rebuild_hand_visuals() -> void:
	# Clear old card visuals
	for child in get_children():
		if child.name != "CardBg":
			child.queue_free()
	_cards.clear()

	# Main hand: 4 cards
	var total_w: float = _hand.size() * (CARD_W + CARD_GAP) - CARD_GAP
	# Add next-card indicator width
	if _next_card:
		total_w += CARD_GAP + 50  # Small "next" card
	var start_x: float = (720.0 - total_w) * 0.5

	for i in _hand.size():
		var bd: BuildingData = _hand[i]
		var card := _CardVisual.new()
		card.bd = bd
		card.index = i
		card.position = Vector2(start_x + i * (CARD_W + CARD_GAP), 10)
		card.size = Vector2(CARD_W, CARD_H)
		card.card_pressed.connect(_on_card_pressed)
		add_child(card)
		_cards.append(card)

	# Next card indicator
	if _next_card:
		var next_x: float = start_x + _hand.size() * (CARD_W + CARD_GAP)
		var next_label := Label.new()
		next_label.text = "NEXT:\n%s" % _next_card.display_name
		next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_label.add_theme_font_size_override("font_size", 9)
		next_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		next_label.position = Vector2(next_x, 40)
		next_label.size = Vector2(50, 40)
		add_child(next_label)

	_update_card_states()


func _on_card_pressed(index: int) -> void:
	if index == _selected_index:
		_selected_index = -1  # Deselect
	else:
		_selected_index = index
	_update_selection()
	if _selected_index >= 0 and _selected_index < _hand.size():
		building_selected.emit(_hand[_selected_index])


## Called after a building is successfully placed. Cycles the card.
func card_played(building_type: StringName) -> void:
	# Find which hand slot was played
	var played_idx: int = -1
	for i in _hand.size():
		if _hand[i].id == building_type:
			played_idx = i
			break
	if played_idx == -1:
		return

	var played_bd: BuildingData = _hand[played_idx]

	# Replace with next card, cycle played to back of deck
	if _next_card:
		_hand[played_idx] = _next_card
		# Find next in deck after current next
		var deck_idx: int = _deck.find(_next_card)
		var next_idx: int = (deck_idx + 1) % _deck.size()
		# Skip cards already in hand
		var attempts: int = 0
		while _deck[next_idx] in _hand and attempts < _deck.size():
			next_idx = (next_idx + 1) % _deck.size()
			attempts += 1
		_next_card = _deck[next_idx] if attempts < _deck.size() else null
	else:
		# No next card, just keep the hand
		pass

	_selected_index = -1
	_rebuild_hand_visuals()


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

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _can_afford and _has_prereq:
				card_pressed.emit(index)
				accept_event()

	func set_state(can_afford: bool, has_prereq: bool) -> void:
		_can_afford = can_afford
		_has_prereq = has_prereq
		queue_redraw()

	func set_selected(selected: bool) -> void:
		_is_selected = selected
		queue_redraw()

	func _draw() -> void:
		if bd == null:
			return
		var w: float = size.x
		var h: float = size.y
		var enabled: bool = _can_afford and _has_prereq

		# Card background
		var bg_top: Color
		var bg_bot: Color
		var border_col: Color

		if not enabled:
			bg_top = Color(0.12, 0.12, 0.15)
			bg_bot = Color(0.08, 0.08, 0.1)
			border_col = Color(0.25, 0.25, 0.3, 0.4)
		elif _is_selected:
			bg_top = Color(0.25, 0.28, 0.4)
			bg_bot = Color(0.18, 0.2, 0.3)
			border_col = Color(1.0, 0.85, 0.2, 0.9)
		elif _hover:
			bg_top = Color(0.22, 0.24, 0.35)
			bg_bot = Color(0.16, 0.18, 0.26)
			border_col = Color(0.5, 0.55, 0.65, 0.6)
		else:
			bg_top = Color(0.18, 0.2, 0.28)
			bg_bot = Color(0.12, 0.13, 0.2)
			border_col = Color(0.35, 0.38, 0.48, 0.5)

		# Shadow
		draw_rect(Rect2(2, 2, w, h), Color(0, 0, 0, 0.3))
		# Background (top half lighter, bottom half darker for gradient effect)
		draw_rect(Rect2(0, 0, w, h * 0.5), bg_top)
		draw_rect(Rect2(0, h * 0.5, w, h * 0.5), bg_bot)
		# Border
		var bw: float = 2.0 if _is_selected else 1.0
		draw_rect(Rect2(0, 0, w, h), border_col, false, bw)

		# Building name
		var name_text: String = bd.display_name
		if name_text.length() > 10:
			name_text = name_text.substr(0, 9) + "."
		draw_string(ThemeDB.fallback_font, Vector2(4, 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 10, Color(0.85, 0.85, 0.9) if enabled else Color(0.45, 0.45, 0.5))

		# Type indicator
		var type_text: String = ""
		if bd.is_tower:
			type_text = "Tower"
		elif bd.income_bonus > 0:
			type_text = "Income"
		elif bd.spawns_unit:
			type_text = "Spawner"
		draw_string(ThemeDB.fallback_font, Vector2(4, 28), type_text, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, Color(0.6, 0.6, 0.65))

		# Unit info (if spawner)
		if bd.spawns_unit:
			var ud = bd.spawns_unit
			var info: String = "HP:%d Dmg:%d" % [ud.max_hp, ud.attack_damage]
			draw_string(ThemeDB.fallback_font, Vector2(4, 50), info, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, Color(0.55, 0.7, 0.55) if enabled else Color(0.35, 0.4, 0.35))
			var info2: String = "x%d / %ds" % [bd.units_per_wave, bd.spawn_interval_ticks / 10]
			draw_string(ThemeDB.fallback_font, Vector2(4, 62), info2, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, Color(0.55, 0.6, 0.7))
		elif bd.is_tower:
			var info: String = "Dmg:%d Rng:%d" % [bd.tower_damage, bd.tower_range]
			draw_string(ThemeDB.fallback_font, Vector2(4, 50), info, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, Color(0.7, 0.55, 0.55) if enabled else Color(0.4, 0.35, 0.35))
		elif bd.income_bonus > 0:
			draw_string(ThemeDB.fallback_font, Vector2(4, 50), "+%d gold/tick" % bd.income_bonus, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, Color(0.7, 0.65, 0.4))

		# Tier stars
		if bd.tier > 1:
			for s in bd.tier:
				draw_circle(Vector2(w - 8 - s * 8, 10), 3, Color(0.9, 0.8, 0.2) if enabled else Color(0.4, 0.35, 0.15))

		# Gold cost badge at bottom
		var badge_w: float = 40.0
		var badge_x: float = (w - badge_w) * 0.5
		draw_rect(Rect2(badge_x, h - 22, badge_w, 18), Color(0.8, 0.65, 0.1) if enabled else Color(0.4, 0.33, 0.08))
		draw_rect(Rect2(badge_x, h - 22, badge_w, 18), Color(0.6, 0.5, 0.08), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(badge_x + 4, h - 8), "%dg" % bd.gold_cost, HORIZONTAL_ALIGNMENT_CENTER, badge_w - 8, 11, Color(0.15, 0.1, 0.0) if enabled else Color(0.3, 0.25, 0.1))

		# Lock overlay for missing prereq
		if not _has_prereq:
			draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.4))
			draw_string(ThemeDB.fallback_font, Vector2(4, h * 0.5 + 4), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, w - 8, 10, Color(0.8, 0.3, 0.2))
			if bd.requires_building != &"":
				draw_string(ThemeDB.fallback_font, Vector2(4, h * 0.5 + 16), "Need: %s" % bd.requires_building, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 7, Color(0.6, 0.4, 0.35))

		# Selected lift indicator
		if _is_selected:
			draw_rect(Rect2(0, 0, w, 3), Color(1.0, 0.85, 0.2))
