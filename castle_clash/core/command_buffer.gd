## Collects and orders commands for each simulation tick.
## In multiplayer, commands are buffered until all players confirm
## their inputs for a given tick (lockstep).
class_name CommandBuffer

var _buffer: Dictionary = {}  # tick -> Array of commands


## Add a command for a specific tick.
func add_command(tick: int, command: Dictionary) -> void:
	if not _buffer.has(tick):
		_buffer[tick] = []
	_buffer[tick].append(command)


## Get all commands for a tick, sorted by player_id for determinism.
func get_commands(tick: int) -> Array:
	if not _buffer.has(tick):
		return []
	var commands: Array = _buffer[tick]
	commands.sort_custom(func(a, b): return a.player_id < b.player_id)
	return commands


## Replace ALL remote commands for a tick. Used by the multiplayer receiver
## when a later payload for the same tick arrives with more commands than
## an earlier (possibly empty) payload. Local commands are preserved.
func replace_commands(tick: int, remote_commands: Array) -> void:
	if not _buffer.has(tick):
		_buffer[tick] = []
	# Remove existing remote commands (keep local ones)
	# We identify remote commands by player_id != local_player_id
	var local_pid: int = GameManager.local_player_id
	var kept: Array = []
	for cmd in _buffer[tick]:
		if cmd.player_id == local_pid:
			kept.append(cmd)
	# Add all remote commands from the new payload
	kept.append_array(remote_commands)
	_buffer[tick] = kept


## Remove processed ticks to free memory.
func clear_through(tick: int) -> void:
	var to_remove: Array = []
	for t in _buffer:
		if t <= tick:
			to_remove.append(t)
	for t in to_remove:
		_buffer.erase(t)


## Check if all players have confirmed for a tick.
func is_tick_ready(_tick: int, _expected_player_count: int) -> bool:
	# In offline mode, always ready. Network lockstep adds real checks later.
	return true
