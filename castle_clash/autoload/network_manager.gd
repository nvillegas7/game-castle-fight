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

# --- Build identity ---
## Stamped by build.sh into application/config/version at export time
## ("0.1.0+<git-sha>-<utc-timestamp>"). Editor/dev runs see the plain
## checked-in version string. Included in MATCH_CONFIG so two clients running
## different builds (stale browser cache serving an old index.pck) abort the
## match cleanly instead of checksum-desyncing every match.
var build_id: String = str(ProjectSettings.get_setting("application/config/version", "dev"))

## Emitted when a lobby/match is aborted for a protocol-level reason.
## kind: "version_mismatch" | "matchmaking" | "config_conflict" | "config_timeout"
## LATER WAVE (UI): this signal currently has no dedicated UI surface. Wire it
## in game_arena.gd (reuse _show_error_overlay via the _on_desync_detected path
## at game_arena.gd:2268) and main_menu.gd so the player sees a
## "refresh for the new version" style message instead of a silent abort.
signal match_error(kind: String, message: String)

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
var opponent_perk: StringName = &""
var local_faction: StringName = &"kingdom"

# --- Match config handshake ---
var _pending_config: Dictionary = {}   # player 0: MATCH_CONFIG awaiting CONFIG_ACK
var _config_acked: bool = false        # player 0: opponent confirmed MATCH_CONFIG
var _active_config: Dictionary = {}    # config of the running match (conflict detection)
const CONFIG_RETRY_INTERVAL_SEC: float = 1.0
const CONFIG_ACK_TIMEOUT_SEC: float = 10.0

# --- Desync detection ---
var _remote_checksums: Dictionary = {}  # tick -> remote checksum awaiting local comparison
var _desync_reported: bool = false
const CHECKSUM_BUFFER_MAX_AGE_TICKS: int = 300

# --- Lockstep relay ---
var _local_commands_sent: Dictionary = {}      # tick -> bool
var _remote_commands_received: Dictionary = {}  # tick -> bool
var _local_commands_for_tick: Dictionary = {}   # tick -> Array
var _sent_command_history: Dictionary = {}     # tick -> Array (last N ticks for redundant send)
const REDUNDANT_TICKS: int = 3                # include this many previous ticks in each payload
var _committed_ticks: Dictionary = {}          # tick -> bool (prevents flush from overwriting committed history)

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
	CONFIG_ACK = 13,
}


func _ready() -> void:
	_detect_server()


## Send a command to the relay server (or apply locally in offline mode).
func send_command(command: Dictionary) -> void:
	if offline_mode:
		GameManager.submit_command(command)
		return
	# Buffer 2 ticks ahead in online mode. This guarantees commands are staged
	# at least 1 full frame before their target tick's first flush, preventing
	# the empty-flush race condition where the remote advances with stale data.
	var tick: int = GameManager.current_tick + 2
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
	# Once a tick is committed, its history is definitive. Don't overwrite with
	# potentially stale staging data (staging is erased after commit).
	if _committed_ticks.has(tick):
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


## Called by GameManager BEFORE advancing a tick to commit commands to the local
## buffer and send a definitive re-flush. This ensures commands placed during
## stalling frames are included and the remote has the final version.
func commit_tick_commands(tick: int) -> void:
	var commands: Array = _local_commands_for_tick.get(tick, [])
	_local_commands_for_tick.erase(tick)
	for cmd in commands:
		GameManager.command_buffer.add_command(tick, cmd)

	# Mark tick as committed — flush_commands_for_tick will no longer overwrite history.
	_committed_ticks[tick] = true
	_sent_command_history[tick] = commands

	# Send definitive re-flush so the remote has the final command set.
	_send_definitive_flush(tick)

	# Prune old tracking data
	if tick > REDUNDANT_TICKS + 10:
		_committed_ticks.erase(tick - REDUNDANT_TICKS - 10)


## Send the definitive (post-commit) command payload for a tick.
## Called once after commit_tick_commands to ensure the remote has the final truth.
func _send_definitive_flush(tick: int) -> void:
	if _socket == null:
		return
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
	_socket.send_match_state_async(match_id, OpCode.COMMANDS, payload)


## Check if both players have submitted commands for the given tick.
func is_tick_ready(tick: int) -> bool:
	if offline_mode:
		return true
	return _local_commands_sent.get(tick, false) and _remote_commands_received.has(tick)


## Send checksum for desync detection. Called every tick by GameManager, so it
## also drives comparison of buffered remote checksums once the local sim
## catches up to the tick they were computed at.
func send_checksum(tick: int, checksum: int) -> void:
	if offline_mode or _socket == null:
		return
	_compare_buffered_checksums()
	if tick % 50 != 0:
		return
	var payload := JSON.stringify({ "tick": tick, "checksum": checksum })
	_socket.send_match_state_async(match_id, OpCode.CHECKSUM, payload)


## Compare buffered remote checksums against local history once the local sim
## reaches the corresponding tick. Previously a remote checksum arriving before
## the local sim reached that tick was silently dropped (get_checksum_for_tick
## returned -1) — the behind client never compared, so desync detection was
## one-directional and 50-100 ticks late. On mismatch, reports the EARLIEST
## mismatching tick (closest to the root cause).
func _compare_buffered_checksums() -> void:
	if _remote_checksums.is_empty():
		return
	var current_tick: int = GameManager.current_tick
	var earliest_mismatch: int = -1
	var ticks: Array = _remote_checksums.keys()
	ticks.sort()
	for t in ticks:
		if t > current_tick:
			continue  # local sim hasn't reached this tick yet — keep buffered
		var local_checksum: int = GameManager.get_checksum_for_tick(t)
		if local_checksum != -1 and local_checksum != _remote_checksums[t]:
			push_error("DESYNC at tick %d! local=%d remote=%d" % [t, local_checksum, _remote_checksums[t]])
			if earliest_mismatch == -1:
				earliest_mismatch = t
		# Compared (or pruned from local history — nothing left to compare
		# against). Either way, drop the buffered entry.
		_remote_checksums.erase(t)
	# Prune entries that can never be compared (e.g. stale after a reset).
	for t in _remote_checksums.keys():
		if t < current_tick - CHECKSUM_BUFFER_MAX_AGE_TICKS:
			_remote_checksums.erase(t)
	if earliest_mismatch != -1 and not _desync_reported:
		_desync_reported = true
		EventBus.desync_detected.emit(earliest_mismatch)


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
	var raw_ids: Array = []
	if matched.self_user != null and matched.self_user.presence != null:
		raw_ids.append(matched.self_user.presence.user_id)
	for u in matched.users:
		if u.presence != null:
			raw_ids.append(u.presence.user_id)
	if not _assign_player_ids(raw_ids):
		return

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

	# Send our faction + perk selection (perk must travel with the lobby data
	# so player 0 can include BOTH perks in MATCH_CONFIG — perks alter sim
	# state, so both clients need identical perk assignments).
	_send_match_message(OpCode.FACTION_SELECT, {
		"faction": str(local_faction),
		"perk": str(GameManager.selected_perk),
	})


## Deterministic player assignment from the matchmaker roster. Returns false
## (and aborts) unless exactly 2 distinct users are present. Never guess here:
## the old fallback appended only local_user_id when presences were missing,
## making BOTH clients player 0 — each then generated its own seed and played
## a different match (guaranteed desync).
func _assign_player_ids(raw_user_ids: Array) -> bool:
	var user_ids: Array = []
	for uid in raw_user_ids:
		if str(uid) != "" and not user_ids.has(uid):
			user_ids.append(uid)
	if local_user_id != "" and not user_ids.has(local_user_id):
		user_ids.append(local_user_id)
	if user_ids.size() != 2:
		_abort_match("matchmaking",
			"Matchmaking failed (%d/2 players found) — please search again" % user_ids.size())
		return false
	user_ids.sort()
	local_player_id = user_ids.find(local_user_id)
	print("[MATCH] matchmaker_ids=%s local=%s player_id=%d" % [str(user_ids), local_user_id, local_player_id])
	return true


# --- Lobby ---

func set_faction(faction: StringName) -> void:
	local_faction = faction
	if net_state == NetState.IN_LOBBY:
		_send_match_message(OpCode.FACTION_SELECT, {
			"faction": str(local_faction),
			"perk": str(GameManager.selected_perk),
		})


func set_ready() -> void:
	_local_ready = true
	_send_match_message(OpCode.READY, {})
	_try_start_match()


func _try_start_match() -> void:
	if net_state != NetState.IN_LOBBY:
		return
	if not _local_ready or not _opponent_ready or opponent_faction == &"":
		return
	# Player 0 sends match config — includes ALL simulation parameters so both
	# clients initialize identically. Previously only seed+players were sent;
	# mode_config was built locally from each client's selected_game_mode,
	# causing desync when they differed (BUG-DESYNC1). Now also carries
	# build_id (stale-cache detection) and both perks (perks alter sim state).
	if local_player_id == 0:
		var config := {
			"build_id": build_id,
			"seed": randi(),
			"game_mode": GameManager.selected_game_mode,
			"players": [
				{ "id": 0, "team": 0, "faction": str(local_faction), "perk": str(GameManager.selected_perk) },
				{ "id": 1, "team": 1, "faction": str(opponent_faction), "perk": str(opponent_perk) },
			]
		}
		_pending_config = config.duplicate(true)
		_config_acked = false
		_send_match_message(OpCode.MATCH_CONFIG, config)
		_begin_match(config)
		_retry_config_until_acked()


## MATCH_CONFIG is no longer single-shot: player 0 re-sends it every second
## until player 1 answers with CONFIG_ACK (or the timeout aborts). A lost
## config previously left player 1 in the lobby forever while player 0 played.
## Fire-and-forget coroutine started right after the first MATCH_CONFIG send.
func _retry_config_until_acked() -> void:
	var waited: float = 0.0
	while not _config_acked and net_state == NetState.IN_MATCH and not _pending_config.is_empty():
		await get_tree().create_timer(CONFIG_RETRY_INTERVAL_SEC).timeout
		if _config_acked or net_state != NetState.IN_MATCH or _pending_config.is_empty():
			return
		waited += CONFIG_RETRY_INTERVAL_SEC
		if waited >= CONFIG_ACK_TIMEOUT_SEC:
			_abort_match("config_timeout", "Opponent never confirmed match settings — match aborted")
			return
		_send_match_message(OpCode.MATCH_CONFIG, _pending_config)


## Build the deterministic player_data array from a MATCH_CONFIG dictionary.
## Both clients MUST produce identical arrays — ordered by player id, with
## identical perk/faction values — because simulation.initialize folds this
## into sim state. Survives the JSON wire (ids arrive as floats).
func _config_to_player_data(config: Dictionary) -> Array:
	var config_players: Array = []
	for p in config.get("players", []):
		config_players.append(p)
	config_players.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var player_data: Array = []
	for p in config_players:
		player_data.append({
			"id": int(p.id),
			"team": int(p.team),
			"faction": StringName(str(p.faction)),
			"perk": StringName(str(p.get("perk", ""))),
		})
	return player_data


func _begin_match(config: Dictionary) -> void:
	net_state = NetState.IN_MATCH
	_active_config = config.duplicate(true)
	_local_commands_sent.clear()
	_remote_commands_received.clear()
	_local_commands_for_tick.clear()
	_sent_command_history.clear()
	_committed_ticks.clear()
	_remote_checksums.clear()
	_desync_reported = false

	var player_data: Array = _config_to_player_data(config)

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
	if net_state != NetState.IN_MATCH:
		# Trailing relay messages after leaving/aborting a match — drop them.
		return

	match op_code:
		OpCode.COMMANDS:
			# Guard: a trailing opponent payload can arrive after local teardown
			# (GameManager.reset_match nulls command_buffer before the relay
			# quiesces) — previously a null-deref crash.
			if GameManager.command_buffer == null:
				return
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
			# Buffer instead of compare-or-drop: the local sim may not have
			# reached this tick yet. _compare_buffered_checksums (driven every
			# tick from send_checksum) compares once we catch up.
			var remote_tick: int = int(data.tick)
			_remote_checksums[remote_tick] = int(data.checksum)
			_compare_buffered_checksums()

		OpCode.MATCH_CONFIG:
			# Late/duplicate config (player 0's retry raced our ACK): re-ack if
			# it matches the match we're simulating; abort if it conflicts —
			# a different seed means the two clients started different matches.
			if int(data.get("seed", -1)) == int(_active_config.get("seed", -2)):
				_send_match_message(OpCode.CONFIG_ACK, { "seed": int(data.get("seed", 0)) })
			else:
				_abort_match("config_conflict", "Match settings conflict detected — match aborted")

		OpCode.CONFIG_ACK:
			_config_acked = true


func _on_lobby_message(op_code: int, data: Dictionary) -> void:
	match op_code:
		OpCode.FACTION_SELECT:
			opponent_faction = StringName(str(data.get("faction", "")))
			opponent_perk = StringName(str(data.get("perk", "")))
			# READY may have arrived before FACTION_SELECT; retry start check
			_try_start_match()
		OpCode.READY:
			_opponent_ready = true
			_try_start_match()
		OpCode.MATCH_CONFIG:
			# Reject mismatched builds BEFORE starting the sim — different sim
			# code produces a checksum desync every match. A stale cached
			# index.pck is the top suspect for user-visible "Sync error" reports.
			var remote_build: String = str(data.get("build_id", ""))
			if remote_build != build_id:
				_abort_match("version_mismatch",
					"Version mismatch — refresh your browser to get the new version, then search again")
				return
			_send_match_message(OpCode.CONFIG_ACK, { "seed": int(data.get("seed", 0)) })
			_begin_match(data)
		OpCode.CONFIG_ACK:
			_config_acked = true


func _send_match_message(op_code: int, data: Dictionary) -> void:
	if _socket and match_id != "":
		_socket.send_match_state_async(match_id, op_code, JSON.stringify(data))


## Leave the current Nakama match and clear per-match relay state, keeping the
## socket/session alive so the player can re-queue. Called by
## GameManager.reset_match() — without this, nobody left the relay match and a
## trailing opponent COMMANDS payload hit the nulled command_buffer.
func leave_current_match() -> void:
	if _socket != null and match_id != "":
		_socket.leave_match_async(match_id)
	match_id = ""
	_clear_match_state()
	if net_state == NetState.IN_MATCH or net_state == NetState.IN_LOBBY:
		net_state = NetState.AUTHENTICATED


## Abort the current lobby/match for a protocol-level reason (version
## mismatch, incomplete matchmaking roster, conflicting MATCH_CONFIG).
## Leaves the relay match, returns to AUTHENTICATED so the player can
## re-queue, and surfaces the reason via match_error (see signal docs for the
## UI wiring a later wave must add).
func _abort_match(kind: String, message: String) -> void:
	push_error("[NET] Match aborted (%s): %s" % [kind, message])
	var was_playing: bool = GameManager.state == GameManager.State.PLAYING \
		or GameManager.state == GameManager.State.COUNTDOWN
	if _socket != null and match_id != "":
		_socket.leave_match_async(match_id)
	match_id = ""
	_clear_match_state()
	if net_state != NetState.OFFLINE:
		net_state = NetState.AUTHENTICATED
	if was_playing and GameManager.is_online_match:
		# Mirror GameManager._on_disconnected: freeze the sim and let the
		# arena error overlay (game_arena.gd _on_match_aborted) take over.
		GameManager.state = GameManager.State.MATCH_OVER
		GameManager.set_process(false)
		Engine.time_scale = 1.0
		EventBus.match_aborted.emit(message)
	match_error.emit(kind, message)
	EventBus.connection_status_changed.emit(message)


## Clear all per-match state (lobby selections, lockstep buffers, config
## handshake, checksum buffer). Shared by leave/abort/offline-reset paths.
func _clear_match_state() -> void:
	opponent_user_id = ""
	opponent_username = ""
	opponent_faction = &""
	opponent_perk = &""
	_opponent_ready = false
	_local_ready = false
	_local_commands_sent.clear()
	_remote_commands_received.clear()
	_local_commands_for_tick.clear()
	_sent_command_history.clear()
	_committed_ticks.clear()
	_remote_checksums.clear()
	_pending_config.clear()
	_active_config.clear()
	_config_acked = true  # stops any in-flight _retry_config_until_acked loop
	_desync_reported = false


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
	_matchmaker_ticket = ""
	_clear_match_state()
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
