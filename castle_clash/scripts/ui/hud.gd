## Top HUD bar showing gold, wave timer, and castle HP.
extends Control

@onready var gold_label: Label = %GoldLabel
@onready var wave_label: Label = %WaveLabel
@onready var castle_label: Label = %CastleLabel


func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.castle_damaged.connect(_on_castle_damaged)


func _process(_delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_update_wave_timer()
	_update_gold()
	_update_castle_hp()


func _update_gold() -> void:
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	gold_label.text = "Gold: %d" % gold


func _update_wave_timer() -> void:
	if GameManager.simulation == null:
		return
	var ticks_remaining: int = GameManager.simulation.wave_timer
	var seconds: int = ticks_remaining / GameManager.TICK_RATE
	wave_label.text = "Wave %d | Next: %ds" % [GameManager.simulation.wave_number, seconds]


func _update_castle_hp() -> void:
	if GameManager.simulation == null:
		return
	var local_team: int = 0
	for player in GameManager.simulation.players:
		if player.id == GameManager.local_player_id:
			local_team = player.team
			break

	var castle: Dictionary = GameManager.simulation.castles[local_team]
	var hp: int = FP.to_int(castle.hp)
	var max_hp: int = FP.to_int(castle.max_hp)
	castle_label.text = "Castle: %d / %d" % [hp, max_hp]


func _on_gold_changed(player_id: int, _new_gold: int) -> void:
	if player_id == GameManager.local_player_id:
		_update_gold()


func _on_castle_damaged(_team: int, _damage: int, _remaining_hp: int) -> void:
	_update_castle_hp()
