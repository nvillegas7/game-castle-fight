## Manages connection to Nakama relay server for multiplayer.
## In offline mode, commands go directly to GameManager (no network).
extends Node

# --- Configuration ---
const SERVER_HOST: String = "localhost"
const SERVER_PORT: int = 7350
const SERVER_KEY: String = "castleclash_dev"
const SERVER_SCHEME: String = "http"

# --- Connection state ---
enum NetState { OFFLINE, CONNECTING, AUTHENTICATED, MATCHMAKING, IN_LOBBY, IN_MATCH }
var net_state: NetState = NetState.OFFLINE
var offline_mode: bool = true

# --- Nakama objects ---
var _client = null  # NakamaClient
var _session = null  # NakamaSession
var _socket = null   # NakamaSocket

# --- Match state ---
var match_id: String = ""
var local_session_id: String = ""
var local_player_id: int = -1
var opponent_session_id: String = ""
var opponent_faction: StringName = &""
var local_faction: StringName = &"kingdom"

# --- Lockstep relay ---
var _local_commands_sent: Dictionary = {}      # tick -> bool
var _remote_commands_received: Dictionary = {}  # tick -> bool
var _local_commands_for_tick: Dictionary = {}   # tick -> Array

# --- Lobby state ---
var _opponent_ready: bool = false
var _local_ready: bool = false

# --- Op codes ---
enum OpCode {
	COMMANDS = 1,
	CHECKSUM = 2,
	FACTION_SELECT = 10,
	READY = 11,
	MATCH_CONFIG = 12,
}


func _ready() -> void:
	pass


## Send a command to the relay server (or apply locally in offline mode).
func send_command(command: Dictionary) -> void:
	if offline_mode:
		GameManager.submit_command(command)
		return
	# Buffer for the next tick
	var tick: int = GameManager.current_tick + 1
	if not _local_commands_for_tick.has(tick):
		_local_commands_for_tick[tick] = []
	_local_commands_for_tick[tick].append(command)


## Called by GameManager each tick to flush and send commands for that tick.
func flush_commands_for_tick(tick: int) -> void:
	if offline_mode:
		return
	var commands: Array = _local_commands_for_tick.get(tick, [])
	_local_commands_for_tick.erase(tick)

	var payload := JSON.stringify({
		"tick": tick,
		"commands": _serialize_commands(commands),
	})

	if _socket:
		_socket.send_match_state_async(match_id, OpCode.COMMANDS, payload)
	_local_commands_sent[tick] = true

	# Also add our commands to GameManager's buffer
	for cmd in commands:
		GameManager.command_buffer.add_command(tick, cmd)


## Check if both players have submitted commands for the given tick.
func is_tick_ready(tick: int) -> bool:
	if offline_mode:
		return true
	return _local_commands_sent.get(tick, false) and _remote_commands_received.has(tick)


## Send checksum for desync detection.
func send_checksum(tick: int, checksum: int) -> void:
	if offline_mode or _socket == null:
		return
	if tick % 50 != 0:
		return
	var payload := JSON.stringify({ "tick": tick, "checksum": checksum })
	_socket.send_match_state_async(match_id, OpCode.CHECKSUM, payload)


# --- Connection and Auth ---

func connect_to_server() -> void:
	net_state = NetState.CONNECTING

	# Load Nakama singleton
	var Nakama = Engine.get_singleton("Nakama") if Engine.has_singleton("Nakama") else null
	if Nakama == null:
		# Try loading via the addon autoload
		Nakama = get_node_or_null("/root/Nakama")
	if Nakama == null:
		push_error("Nakama addon not found. Enable the plugin in Project Settings.")
		net_state = NetState.OFFLINE
		return

	_client = Nakama.create_client(SERVER_KEY, SERVER_HOST, SERVER_PORT, SERVER_SCHEME)

	# Device ID auth
	var device_id: String = _get_or_create_device_id()
	_session = await _client.authenticate_device_async(device_id, null, true)
	if _session.is_exception():
		push_error("Auth failed: %s" % _session.get_exception().message)
		net_state = NetState.OFFLINE
		return

	local_session_id = _session.user_id

	# Open WebSocket
	_socket = Nakama.create_socket_from(_client)
	var connected = await _socket.connect_async(_session)
	if connected.is_exception():
		push_error("Socket connect failed")
		net_state = NetState.OFFLINE
		return

	offline_mode = false
	net_state = NetState.AUTHENTICATED
	_socket.received_match_state.connect(_on_match_state)
	_socket.received_matchmaker_matched.connect(_on_matchmaker_matched)
	_socket.closed.connect(_on_socket_closed)
	EventBus.connected_to_server.emit()


func _get_or_create_device_id() -> String:
	var config := ConfigFile.new()
	var path := "user://device_id.cfg"
	if config.load(path) == OK:
		var id = config.get_value("auth", "device_id", "")
		if id != "":
			return id
	var id := "%x%x%x%x" % [randi(), randi(), randi(), randi()]
	config.set_value("auth", "device_id", id)
	config.save(path)
	return id


# --- Matchmaking ---

func start_matchmaking(faction: StringName) -> void:
	if net_state != NetState.AUTHENTICATED:
		return
	local_faction = faction
	net_state = NetState.MATCHMAKING

	var ticket = await _socket.add_matchmaker_async("*", 2, 2)
	if ticket.is_exception():
		push_error("Matchmaking failed")
		net_state = NetState.AUTHENTICATED


func _on_matchmaker_matched(matched) -> void:
	var joined = await _socket.join_matched_async(matched)
	if joined.is_exception():
		push_error("Failed to join match")
		return

	match_id = joined.match_id

	# Assign player IDs by sorting session IDs lexicographically
	var session_ids: Array = []
	for p in joined.presences:
		session_ids.append(p.session_id)
	session_ids.sort()

	local_player_id = session_ids.find(local_session_id)
	for p in joined.presences:
		if p.session_id != local_session_id:
			opponent_session_id = p.session_id

	net_state = NetState.IN_LOBBY
	_opponent_ready = false
	_local_ready = false
	EventBus.match_found.emit(match_id)

	# Send our faction selection
	_send_match_message(OpCode.FACTION_SELECT, { "faction": str(local_faction) })


# --- Lobby ---

func set_faction(faction: StringName) -> void:
	local_faction = faction
	if net_state == NetState.IN_LOBBY:
		_send_match_message(OpCode.FACTION_SELECT, { "faction": str(local_faction) })


func set_ready() -> void:
	_local_ready = true
	_send_match_message(OpCode.READY, {})
	_try_start_match()


func _try_start_match() -> void:
	if not _local_ready or not _opponent_ready or opponent_faction == &"":
		return
	# Player 0 sends match config
	if local_player_id == 0:
		var config := {
			"seed": randi(),
			"players": [
				{ "id": 0, "team": 0, "faction": str(local_faction) },
				{ "id": 1, "team": 1, "faction": str(opponent_faction) },
			]
		}
		_send_match_message(OpCode.MATCH_CONFIG, config)
		_begin_match(config)


func _begin_match(config: Dictionary) -> void:
	net_state = NetState.IN_MATCH
	_local_commands_sent.clear()
	_remote_commands_received.clear()
	_local_commands_for_tick.clear()

	var player_data: Array = []
	for p in config.players:
		player_data.append({
			"id": int(p.id),
			"team": int(p.team),
			"faction": StringName(str(p.faction)),
		})

	GameManager.start_online_match(int(config.seed), player_data, local_player_id)


# --- Relay ---

func _on_match_state(match_state) -> void:
	var op_code: int = match_state.op_code
	var raw_data: String = match_state.data if match_state.data is String else str(match_state.data)
	if raw_data == "":
		raw_data = "{}"
	var data = JSON.parse_string(raw_data)
	if data == null:
		data = {}

	if net_state == NetState.IN_LOBBY:
		_on_lobby_message(op_code, data)
		return

	match op_code:
		OpCode.COMMANDS:
			var tick: int = int(data.tick)
			var commands: Array = _deserialize_commands(data.get("commands", []))
			_remote_commands_received[tick] = true
			for cmd in commands:
				GameManager.command_buffer.add_command(tick, cmd)

		OpCode.CHECKSUM:
			var remote_tick: int = int(data.tick)
			var remote_checksum: int = int(data.checksum)
			var local_checksum: int = GameManager.get_checksum_for_tick(remote_tick)
			if local_checksum != -1 and local_checksum != remote_checksum:
				push_error("DESYNC at tick %d! local=%d remote=%d" % [remote_tick, local_checksum, remote_checksum])
				EventBus.desync_detected.emit(remote_tick)


func _on_lobby_message(op_code: int, data: Dictionary) -> void:
	match op_code:
		OpCode.FACTION_SELECT:
			opponent_faction = StringName(str(data.get("faction", "")))
		OpCode.READY:
			_opponent_ready = true
			_try_start_match()
		OpCode.MATCH_CONFIG:
			_begin_match(data)


func _send_match_message(op_code: int, data: Dictionary) -> void:
	if _socket and match_id != "":
		_socket.send_match_state_async(match_id, op_code, JSON.stringify(data))


func _on_socket_closed() -> void:
	EventBus.disconnected_from_server.emit()


# --- Serialization ---

func _serialize_commands(commands: Array) -> Array:
	var result: Array = []
	for cmd in commands:
		var s := { "type": cmd.type, "player_id": cmd.player_id }
		match int(cmd.type):
			Command.Type.PLACE_BUILDING:
				s["building_type"] = str(cmd.building_type)
				s["grid_x"] = cmd.grid_x
				s["grid_y"] = cmd.grid_y
			Command.Type.SELL_BUILDING:
				s["building_id"] = cmd.building_id
			Command.Type.USE_ABILITY:
				s["ability_id"] = str(cmd.ability_id)
				s["target_x"] = cmd.target_x
				s["target_y"] = cmd.target_y
		result.append(s)
	return result


func _deserialize_commands(data: Array) -> Array:
	var result: Array = []
	for item in data:
		var cmd: Dictionary = { "type": int(item.type), "player_id": int(item.player_id) }
		match cmd.type:
			Command.Type.PLACE_BUILDING:
				cmd["building_type"] = StringName(str(item.building_type))
				cmd["grid_x"] = int(item.grid_x)
				cmd["grid_y"] = int(item.grid_y)
			Command.Type.SELL_BUILDING:
				cmd["building_id"] = int(item.building_id)
			Command.Type.USE_ABILITY:
				cmd["ability_id"] = StringName(str(item.ability_id))
				cmd["target_x"] = int(item.target_x)
				cmd["target_y"] = int(item.target_y)
		result.append(cmd)
	return result
