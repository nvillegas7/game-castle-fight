## Manages audio playback with a pooled AudioStreamPlayer system.
extends Node

const SFX_POOL_SIZE: int = 16

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx_index: int = 0


func _ready() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	var player := _sfx_pool[_next_sfx_index]
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	_next_sfx_index = (_next_sfx_index + 1) % SFX_POOL_SIZE
