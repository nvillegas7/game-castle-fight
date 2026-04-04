## Building selection panel with info tooltips showing unit stats.
extends PanelContainer

signal building_selected(building_data: BuildingData)

var _buttons: Array[Button] = []
var _current_faction: FactionData = null
var _selected_bd: BuildingData = null

@onready var building_list: VBoxContainer = %BuildingList
@onready var info_panel: VBoxContainer = %InfoPanel
@onready var info_name: Label = %InfoName
@onready var info_stats: Label = %InfoStats
@onready var info_desc: Label = %InfoDesc

const ATTACK_NAMES := ["Physical", "Pierce", "Magic", "Siege"]
const ARMOR_NAMES := ["Light", "Medium", "Heavy", "Fortified"]
const ROLE_NAMES := ["Melee", "Ranged", "Caster", "Flying", "Siege"]


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.gold_changed.connect(_on_gold_changed)
	if info_panel:
		info_panel.visible = false


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
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(_on_building_button_pressed.bind(bd))
		btn.mouse_entered.connect(_show_info.bind(bd))
		btn.mouse_exited.connect(_hide_info)
		building_list.add_child(btn)
		_buttons.append(btn)

	_update_button_states()


func _on_building_button_pressed(bd: BuildingData) -> void:
	_selected_bd = bd
	building_selected.emit(bd)


func _show_info(bd: BuildingData) -> void:
	if not info_panel:
		return
	info_panel.visible = true

	var tier_str := "T%d" % bd.tier
	var req_str := ""
	if bd.requires_building != &"":
		req_str = " (needs %s)" % bd.requires_building

	info_name.text = "%s [%s]%s" % [bd.display_name, tier_str, req_str]

	if bd.spawns_unit:
		var ud = bd.spawns_unit
		var atk_name: String = ATTACK_NAMES[ud.attack_type] if ud.attack_type < ATTACK_NAMES.size() else "?"
		var arm_name: String = ARMOR_NAMES[ud.armor_type] if ud.armor_type < ARMOR_NAMES.size() else "?"
		var role_name: String = ROLE_NAMES[ud.role] if ud.role < ROLE_NAMES.size() else "?"

		info_stats.text = "Spawns: %s x%d\nHP: %d  Dmg: %d  Spd: %d\nAtk: %s  Arm: %s\nRole: %s  Range: %d" % [
			ud.display_name, bd.units_per_wave,
			ud.max_hp, ud.attack_damage, ud.attack_speed_ticks,
			atk_name, arm_name,
			role_name, ud.attack_range,
		]
	else:
		info_stats.text = "Utility building"

	info_desc.text = "Cost: %dg  Sell: %d%%" % [bd.gold_cost, bd.sell_refund_percent]


func _hide_info() -> void:
	if info_panel:
		info_panel.visible = false


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

		# Update button text with status indicators
		var status: String = ""
		if not has_prereq:
			status = " [LOCKED: build %s]" % bd.requires_building
		elif not can_afford:
			status = " [need %dg]" % bd.gold_cost
		var tier_str: String = " **" if bd.tier >= 2 else ""
		var tower_str: String = " [Tower]" if bd.is_tower else ""
		_buttons[i].text = "%s (%dg)%s%s%s" % [bd.display_name, bd.gold_cost, tier_str, tower_str, status]
