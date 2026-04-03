## Main menu with faction selection and play button.
extends Control

@onready var kingdom_btn: Button = %KingdomBtn
@onready var horde_btn: Button = %HordeBtn
@onready var faction_desc: Label = %FactionDesc
@onready var play_btn: Button = %PlayBtn
@onready var online_btn: Button = %OnlineBtn
@onready var status_label: Label = %StatusLabel

var _selected_faction: StringName = &"kingdom"

const FACTION_DESCRIPTIONS := {
	&"kingdom": "The Kingdom - Balanced faction with healing priests and heavy knights. Sustain-oriented, wins long fights.",
	&"horde": "The Horde - Aggressive faction with high burst damage and zero healing. Cheap units, fast attacks, snowball or die.",
}


func _ready() -> void:
	kingdom_btn.pressed.connect(_select_kingdom)
	horde_btn.pressed.connect(_select_horde)
	play_btn.pressed.connect(_on_play)
	online_btn.pressed.connect(_on_play_online)
	EventBus.connected_to_server.connect(_on_connected)
	EventBus.match_found.connect(_on_match_found)
	if status_label:
		status_label.text = ""
	_update_selection()
	_update_player_stats()


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


func _on_play_online() -> void:
	if status_label:
		status_label.text = "Connecting to server..."
	online_btn.disabled = true
	play_btn.disabled = true
	NetworkManager.local_faction = _selected_faction
	NetworkManager.connect_to_server()


func _on_connected() -> void:
	if status_label:
		status_label.text = "Connected! Finding match..."
	NetworkManager.start_matchmaking(_selected_faction)


func _on_match_found(_match_id: String) -> void:
	if status_label:
		status_label.text = "Match found! Starting..."
	# Auto-ready for MVP (skip lobby screen)
	NetworkManager.set_ready()


func _update_player_stats() -> void:
	if status_label:
		var rank: String = PlayerData.get_rank_name()
		var record: String = "%dW / %dL" % [PlayerData.games_won, PlayerData.games_played - PlayerData.games_won]
		var bonus: String = " | First Win Bonus!" if PlayerData.first_win_bonus_available else ""
		if PlayerData.games_played > 0:
			status_label.text = "%d Trophies (%s) | %s%s" % [PlayerData.trophies, rank, record, bonus]
		else:
			status_label.text = "Welcome, Commander! Pick a faction and fight."
