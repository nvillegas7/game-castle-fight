## Main menu with faction selection and play button.
extends Control

@onready var kingdom_btn: Button = %KingdomBtn
@onready var horde_btn: Button = %HordeBtn
@onready var faction_desc: Label = %FactionDesc
@onready var play_btn: Button = %PlayBtn

var _selected_faction: StringName = &"kingdom"

const FACTION_DESCRIPTIONS := {
	&"kingdom": "The Kingdom - Balanced faction with healing priests and heavy knights. Sustain-oriented, wins long fights.",
	&"horde": "The Horde - Aggressive faction with high burst damage and zero healing. Cheap units, fast attacks, snowball or die.",
}


func _ready() -> void:
	kingdom_btn.pressed.connect(_select_kingdom)
	horde_btn.pressed.connect(_select_horde)
	play_btn.pressed.connect(_on_play)
	_update_selection()


func _select_kingdom() -> void:
	_selected_faction = &"kingdom"
	_update_selection()


func _select_horde() -> void:
	_selected_faction = &"horde"
	_update_selection()


func _update_selection() -> void:
	kingdom_btn.disabled = (_selected_faction == &"kingdom")
	horde_btn.disabled = (_selected_faction == &"horde")
	faction_desc.text = FACTION_DESCRIPTIONS.get(_selected_faction, "")


func _on_play() -> void:
	GameManager.selected_faction = _selected_faction
	get_tree().change_scene_to_file("res://scenes/game/game_arena.tscn")
