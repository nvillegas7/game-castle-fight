## Match end screen with detailed stats, trophy change, and restart.
extends Control

@onready var result_label: Label = %ResultLabel
@onready var detail_label: Label = %DetailLabel
@onready var stats_label: Label = %StatsLabel
@onready var trophy_label: Label = %TrophyLabel
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	visible = false
	EventBus.match_ended.connect(_on_match_ended)
	if restart_button:
		restart_button.pressed.connect(_on_restart)
	if menu_button:
		menu_button.pressed.connect(_on_menu)


func _on_match_ended(winning_team: int) -> void:
	visible = true

	var local_team: int = 0
	var local_faction: StringName = &""
	if GameManager.simulation:
		for player in GameManager.simulation.players:
			if player.id == GameManager.local_player_id:
				local_team = player.team
				local_faction = player.faction
				break

	var won: bool = (winning_team == local_team)

	if won:
		result_label.text = "VICTORY!"
		result_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
		SFX.play_victory()
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		SFX.play_defeat()

	# Match stats
	var buildings_count: int = 0
	if GameManager.simulation:
		for entity in GameManager.simulation.entities:
			if entity.owner == GameManager.local_player_id:
				if entity.type == "building":
					buildings_count += 1

	var match_time: int = GameManager.current_tick / GameManager.TICK_RATE
	var minutes: int = match_time / 60
	var secs: int = match_time % 60

	var spawned: int = GameManager.simulation.units_spawned[local_team] if GameManager.simulation else 0
	var killed: int = GameManager.simulation.units_killed[local_team] if GameManager.simulation else 0

	detail_label.text = "Time: %d:%02d | Buildings: %d\nUnits Spawned: %d | Enemies Killed: %d" % [
		minutes, secs, buildings_count, spawned, killed
	]

	# Record to persistent data
	PlayerData.record_match_result(won, local_faction, waves, buildings_count)

	# Trophy change
	var trophy_change: int = PlayerData.TROPHY_WIN if won else PlayerData.TROPHY_LOSE
	var trophy_sign: String = "+" if trophy_change > 0 else ""
	if trophy_label:
		trophy_label.text = "Trophies: %s%d (Total: %d - %s)" % [
			trophy_sign, trophy_change, PlayerData.trophies, PlayerData.get_rank_name()
		]

	# Overall stats
	if stats_label:
		stats_label.text = "Record: %dW / %dL | Total Games: %d" % [
			PlayerData.games_won, PlayerData.games_played - PlayerData.games_won, PlayerData.games_played
		]


func _on_restart() -> void:
	visible = false
	get_tree().reload_current_scene()


func _on_menu() -> void:
	visible = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
