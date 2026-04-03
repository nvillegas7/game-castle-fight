## Building selection panel. Shows available buildings for the player's faction.
extends PanelContainer

signal building_selected(building_data: BuildingData)

var _buttons: Array[Button] = []
var _current_faction: FactionData = null

@onready var building_list: VBoxContainer = %BuildingList


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.gold_changed.connect(_on_gold_changed)


func _on_match_started() -> void:
	_current_faction = GameManager.get_player_faction(GameManager.local_player_id)
	if _current_faction == null:
		return
	_rebuild_button_list()


func _rebuild_button_list() -> void:
	for child in building_list.get_children():
		child.queue_free()
	_buttons.clear()

	for bd: BuildingData in _current_faction.buildings:
		var btn := Button.new()
		btn.text = "%s (%dg)" % [bd.display_name, bd.gold_cost]
		btn.custom_minimum_size = Vector2(0, 48)
		btn.pressed.connect(_on_building_button_pressed.bind(bd))
		building_list.add_child(btn)
		_buttons.append(btn)

	_update_button_states()


func _on_building_button_pressed(bd: BuildingData) -> void:
	building_selected.emit(bd)


func _on_gold_changed(player_id: int, _new_gold: int) -> void:
	if player_id == GameManager.local_player_id:
		_update_button_states()


func _update_button_states() -> void:
	if _current_faction == null or GameManager.simulation == null:
		return

	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var player_index: int = GameManager.simulation.get_player_index(GameManager.local_player_id)

	for i in _current_faction.buildings.size():
		if i >= _buttons.size():
			break
		var bd: BuildingData = _current_faction.buildings[i]
		var can_afford: bool = gold >= bd.gold_cost
		var has_prereq: bool = bd.requires_building == &"" or \
			GameManager.simulation.player_has_building(player_index, bd.requires_building)
		_buttons[i].disabled = not (can_afford and has_prereq)
