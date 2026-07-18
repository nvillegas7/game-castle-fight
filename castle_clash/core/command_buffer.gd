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


## Get all commands for a tick, sorted by (player_id, seq) for determinism.
## 1B-3: player_id alone left same-player order INSERTION-dependent — peers
## receiving the same commands out of order applied them differently (and
## sort_custom is not stability-guaranteed). seq is stamped by the SENDER
## (GameManager.submit_command); legacy commands without seq sort as 0.
func get_commands(tick: int) -> Array:
	if not _buffer.has(tick):
		return []
	var commands: Array = _buffer[tick]
	commands.sort_custom(func(a, b):
		if a.player_id != b.player_id:
			return a.player_id < b.player_id
		return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	return commands


## Replace ALL remote commands for a tick. Used by the multiplayer receiver
## when a later payload for the same tick arrives with more commands than
## an earlier (possibly empty) payload. Local commands are preserved.
func replace_commands(tick: int, remote_commands: Array, local_pid: int) -> void:
	if not _buffer.has(tick):
		_buffer[tick] = []
	# Remove existing remote commands (keep local ones)
	# We identify remote commands by player_id != local_pid (injected — this
	# class must stay autoload-free so headless suites can instance it; 1B-3).
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
