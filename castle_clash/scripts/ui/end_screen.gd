## Match end screen. Shows victory/defeat with a restart button.
extends Control

@onready var result_label: Label = %ResultLabel
@onready var detail_label: Label = %DetailLabel
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	visible = false
	EventBus.match_ended.connect(_on_match_ended)
	restart_button.pressed.connect(_on_restart)


func _on_match_ended(winning_team: int) -> void:
	visible = true

	var local_team: int = 0
	if GameManager.simulation:
		for player in GameManager.simulation.players:
			if player.id == GameManager.local_player_id:
				local_team = player.team
				break

	if winning_team == local_team:
		result_label.text = "VICTORY"
		result_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

	var waves: int = GameManager.simulation.wave_number if GameManager.simulation else 0
	detail_label.text = "Waves survived: %d" % waves


func _on_restart() -> void:
	visible = false
	get_tree().reload_current_scene()
