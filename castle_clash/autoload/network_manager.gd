## Manages connection to Nakama relay server for multiplayer.
## In offline mode, commands go directly to GameManager (no network).
extends Node

# --- Configuration ---
# Auto-detect: localhost uses local Nakama directly (fast),
# deployed uses Cloudflare tunnel (internet play).
const SERVER_KEY: String = "castleclash_dev"
var server_host: String = "nakama.castlefight.net"
var server_port: int = 443
var server_scheme: String = "https"

func _detect_server() -> void:
	if OS.has_feature("web"):
		var js_host: String = JavaScriptBridge.eval("window.location.hostname")
		if js_host == "localhost" or js_host == "127.0.0.1":
			server_host = "localhost"
			server_port = 7350
			server_scheme = "http"
			print("[NET] Local mode: Nakama at localhost:7350")
			return
	print("[NET] Remote mode: Nakama at %s:%d" % [server_host, server_port])

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
var local_user_id: String = ""      # stable user_id from device auth
var local_player_id: int = -1       # deterministic 0/1 from sorted user_ids
var opponent_user_id: String = ""   # opponent's stable user_id
var opponent_username: String = ""  # opponent display name (for lobby UI)
var opponent_faction: StringName = &""
var local_faction: StringName = &"kingdom"

# --- Lockstep relay ---
var _local_commands_sent: Dictionary = {}      # tick -> bool
var _remote_commands_received: Dictionary = {}  # tick -> bool
var _local_commands_for_tick: Dictionary = {}   # tick -> Array
var _sent_command_history: Dictionary = {}     # tick -> Array (last N ticks for redundant send)
const REDUNDANT_TICKS: int = 3                # include this many previous ticks in each payload

# --- Lobby state ---
var _opponent_ready: bool = false
var _local_ready: bool = false
var _matchmaker_ticket: String = ""  # for cancel matchmaking

# --- Op codes ---
enum OpCode {
	COMMANDS = 1,
	CHECKSUM = 2,
	FACTION_SELECT = 10,
	READY = 11,
	MATCH_CONFIG = 12,
}


func _ready() -> void:
	_detect_server()


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
## May be called multiple times for the same tick (while stalling for remote).
## Commands accumulate in _local_commands_for_tick until the tick advances;
## each flush re-sends the FULL accumulated set so the remote always gets
## the latest version. The receiver uses the latest payload for each tick,
## replacing any earlier (possibly empty) version.
func flush_commands_for_tick(tick: int) -> void:
	if offline_mode:
		return
	# DON'T erase — commands may be added between flush calls while stalling.
	# Read the current accumulated commands for this tick.
	var commands: Array = _local_commands_for_tick.get(tick, [])

	# Build payload with current + previous ticks (redundant send for reliability)
	_sent_command_history[tick] = commands
	if tick > REDUNDANT_TICKS + 10:
		_sent_command_history.erase(tick - REDUNDANT_TICKS - 10)

	var all_ticks: Array = []
	for t in range(maxi(1, tick - REDUNDANT_TICKS), tick + 1):
		var cmds: Array = _sent_command_history.get(t, [])
		all_ticks.append({
			"tick": t,
			"commands": _serialize_commands(cmds),
		})

	var payload := JSON.stringify({
		"tick": tick,
		"ticks": all_ticks,
	})

	if _socket:
		_socket.send_match_state_async(match_id, OpCode.COMMANDS, payload)
	_local_commands_sent[tick] = true


## Called by GameManager AFTER advancing a tick to commit commands to the local
## buffer and clean up. This ensures commands placed during stalling frames are
## included before the tick is processed.
func commit_tick_commands(tick: int) -> void:
	var commands: Array = _local_commands_for_tick.get(tick, [])
	_local_commands_for_tick.erase(tick)
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
	EventBus.connection_status_changed.emit("Connecting to server...")

	# Load Nakama singleton
	var Nakama = Engine.get_singleton("Nakama") if Engine.has_singleton("Nakama") else null
	if Nakama == null:
		# Try loading via the addon autoload
		Nakama = get_node_or_null("/root/Nakama")
	if Nakama == null:
		push_error("Nakama addon not found. Enable the plugin in Project Settings.")
		_reset_to_offline()
		EventBus.connection_status_changed.emit("Server not available")
		return

	# Nakama.create_client(key, host, port, scheme, timeout, log_level)
	# Log level WARNING (2) suppresses the per-message DEBUG/INFO spam in console.
	# Only errors and warnings are shown. NakamaLogger.LOG_LEVEL: 0=NONE,1=ERROR,2=WARNING,3=INFO,4=VERBOSE,5=DEBUG
	_client = Nakama.create_client(SERVER_KEY, server_host, server_port, server_scheme, 3, 2)

	# Device ID auth
	var device_id: String = _get_or_create_device_id()
	_session = await _client.authenticate_device_async(device_id, null, true)
	if _session.is_exception():
		push_error("Auth failed: %s" % _session.get_exception().message)
		_reset_to_offline()
		EventBus.connection_status_changed.emit("Authentication failed")
		return

	local_user_id = _session.user_id

	# Open WebSocket
	_socket = Nakama.create_socket_from(_client)
	var connected = await _socket.connect_async(_session)
	if connected.is_exception():
		push_error("Socket connect failed")
		_reset_to_offline()
		EventBus.connection_status_changed.emit("Connection failed")
		return

	offline_mode = false
	net_state = NetState.AUTHENTICATED
	_socket.received_match_state.connect(_on_match_state)
	_socket.received_matchmaker_matched.connect(_on_matchmaker_matched)
	_socket.closed.connect(_on_socket_closed)
	EventBus.connected_to_server.emit()
	EventBus.connection_status_changed.emit("Connected!")


func _get_or_create_device_id() -> String:
	# Web exports: all tabs on the same origin share IndexedDB, so a persistent
	# device ID makes every tab authenticate as the same Nakama user. Generate a
	# unique ID per session so each tab is a distinct player for testing.
	if OS.has_feature("web"):
		return "%x%x%x%x" % [randi(), randi(), randi(), randi()]
	# Native: persist device ID across sessions for stable identity.
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
	EventBus.connection_status_changed.emit("Finding opponent...")

	var ticket = await _socket.add_matchmaker_async("*", 2, 2)
	if ticket.is_exception():
		push_error("Matchmaking failed")
		net_state = NetState.AUTHENTICATED
		EventBus.connection_status_changed.emit("Matchmaking failed. Try again.")
		return
	_matchmaker_ticket = ticket.ticket


## Cancel an in-progress matchmaking search.
func cancel_matchmaking() -> void:
	if net_state != NetState.MATCHMAKING or _matchmaker_ticket == "":
		return
	if _socket:
		await _socket.remove_matchmaker_async(_matchmaker_ticket)
	_matchmaker_ticket = ""
	net_state = NetState.AUTHENTICATED
	EventBus.connection_status_changed.emit("Search cancelled")


func _on_matchmaker_matched(matched) -> void:
	EventBus.connection_status_changed.emit("Opponent found! Joining...")

	var joined = await _socket.join_matched_async(matched)
	if joined.is_exception():
		push_error("Failed to join match")
		EventBus.connection_status_changed.emit("Failed to join match")
		return

	match_id = joined.match_id

	# Deterministic player assignment from matchmaker result (available BEFORE join).
	# joined.presences has a race condition — first joiner doesn't see the second.
	# The matchmaker result contains ALL matched users: self_user + users[].
	var user_ids: Array = []
	if matched.self_user != null and matched.self_user.presence != null:
		var uid: String = matched.self_user.presence.user_id
		if uid != "" and not user_ids.has(uid):
			user_ids.append(uid)
	for u in matched.users:
		if u.presence != null:
			var uid: String = u.presence.user_id
			if uid != "" and not user_ids.has(uid):
				user_ids.append(uid)
	# Fallback: ensure self is always in the list
	if not user_ids.has(local_user_id):
		user_ids.append(local_user_id)
	user_ids.sort()
	local_player_id = user_ids.find(local_user_id)
	print("[MATCH] matchmaker_ids=%s local=%s player_id=%d" % [str(user_ids), local_user_id, local_player_id])

	# Track opponent info
	for u in matched.users:
		if u.presence != null and u.presence.user_id != local_user_id:
			opponent_user_id = u.presence.user_id
			opponent_username = u.presence.username if u.presence.username != "" else "Opponent"
			break
	# Fallback: check joined presences for opponent info
	if opponent_user_id == "":
		for p in joined.presences:
			if p.user_id != local_user_id:
				opponent_user_id = p.user_id
				opponent_username = p.username if p.username != "" else "Opponent"
				break

	net_state = NetState.IN_LOBBY
	_opponent_ready = false
	_local_ready = false
	EventBus.match_found.emit(match_id)
	EventBus.connection_status_changed.emit("Match found! Starting...")

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
	# Player 0 sends match config — includes ALL simulation parameters so both
	# clients initialize identically. Previously only seed+players were sent;
	# mode_config was built locally from each client's selected_game_mode,
	# causing desync when they differed (BUG-DESYNC1).
	if local_player_id == 0:
		var config := {
			"seed": randi(),
			"game_mode": GameManager.selected_game_mode,
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

	# Use game_mode from match config — NOT from local selected_game_mode.
	# Both clients must use the same mode for deterministic sync (BUG-DESYNC1).
	var game_mode: int = int(config.get("game_mode", 0))  # 0 = STANDARD
	GameManager.selected_game_mode = game_mode as GameManager.GameMode
	GameManager.start_online_match(int(config.seed), player_data, local_player_id)
	# Transition to the game arena scene. The simulation is already initialized
	# and ticking; game_arena._ready() will re-emit match_started so children
	# (card_hand, building_menu) can initialize from the running simulation.
	SceneTransition.change_scene("res://scenes/game/game_arena.tscn")


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
			# Each payload contains multiple ticks (current + redundant previous).
			# REPLACE (not skip) commands for each tick — later messages may have
			# commands that earlier (empty) messages didn't, because the sender
			# accumulates commands while stalling.
			var ticks_array: Array = data.get("ticks", [])
			if ticks_array.is_empty():
				# Legacy single-tick format fallback
				var tick: int = int(data.tick)
				var commands: Array = _deserialize_commands(data.get("commands", []))
				_remote_commands_received[tick] = true
				GameManager.command_buffer.replace_commands(tick, commands)
			else:
				for tick_data in ticks_array:
					var t: int = int(tick_data.tick)
					var commands: Array = _deserialize_commands(tick_data.get("commands", []))
					_remote_commands_received[t] = true
					# Replace — later payload for same tick may have more commands
					GameManager.command_buffer.replace_commands(t, commands)

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
			# READY may have arrived before FACTION_SELECT; retry start check
			_try_start_match()
		OpCode.READY:
			_opponent_ready = true
			_try_start_match()
		OpCode.MATCH_CONFIG:
			_begin_match(data)


func _send_match_message(op_code: int, data: Dictionary) -> void:
	if _socket and match_id != "":
		_socket.send_match_state_async(match_id, op_code, JSON.stringify(data))


## Handle socket disconnection. Reset all network state so the game can
## reconnect cleanly from the main menu.
func _on_socket_closed() -> void:
	_reset_to_offline()
	EventBus.disconnected_from_server.emit()
	EventBus.connection_status_changed.emit("Connection lost")


## Reset all network state to clean offline mode.
func _reset_to_offline() -> void:
	net_state = NetState.OFFLINE
	offline_mode = true
	match_id = ""
	local_player_id = -1
	opponent_user_id = ""
	opponent_username = ""
	opponent_faction = &""
	_opponent_ready = false
	_local_ready = false
	_matchmaker_ticket = ""
	_local_commands_sent.clear()
	_remote_commands_received.clear()
	_local_commands_for_tick.clear()
	_client = null
	_session = null
	_socket = null


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
			Command.Type.ACTIVATE_BUILDING:
				s["building_id"] = cmd.building_id
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
			Command.Type.ACTIVATE_BUILDING:
				cmd["building_id"] = int(item.building_id)
		result.append(cmd)
	return result
