## Manages connection to Nakama relay server.
## Stub -- real Nakama integration comes in the multiplayer phase.
## In offline mode, commands are applied locally with no relay.
extends Node

var is_connected: bool = false
var local_player_id: int = 0
var offline_mode: bool = true


func _ready() -> void:
	pass


## Send a command to the relay server (or apply locally in offline mode).
func send_command(command: Dictionary) -> void:
	if offline_mode:
		# Directly enqueue for the next tick
		pass
	else:
		# Serialize and send via WebSocket to Nakama
		pass


## Called when receiving commands relayed from the server.
func _on_commands_received(_tick: int, _commands: Array) -> void:
	pass
