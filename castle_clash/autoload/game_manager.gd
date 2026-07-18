## Manages match lifecycle and bridges the deterministic simulation
## with the Godot scene tree. Supports both offline and online (lockstep) modes.
extends Node

enum State { MENU, LOADING, COUNTDOWN, PLAYING, MATCH_OVER }
enum GameMode { STANDARD, BLITZ, MIRROR }

var state: State = State.MENU
var current_tick: int = 0
var simulation: Simulation = null
var command_buffer: CommandBuffer = null
var local_player_id: int = 0

## True when this match was started via NetworkManager (not offline AI).
var is_online_match: bool = false


## The lockstep wait/stall machinery applies ONLY to a networked match.
## BUG 2026-07-10 ("opponent left" in single player): gating on the GLOBAL
## socket flag (NetworkManager.offline_mode) alone poisoned solo matches when
## a Nakama socket was still alive from an earlier PLAY ONLINE attempt (cancel/
## abort keeps the socket open by design) — the solo match waited for remote
## ticks that never come, hit the stall timeout, and aborted with "Opponent
## disconnected". Match TYPE and socket STATE are independent; lockstep needs both.
func is_lockstep_match() -> bool:
	return is_online_match and not NetworkManager.offline_mode

## Selected faction for the local player (set by main menu).
var selected_faction: StringName = &"kingdom"

## Selected perk for the local player (set by perk selection screen).
var selected_perk: StringName = &""

## Selected game mode (set by mode selection UI).
var selected_game_mode: GameMode = GameMode.STANDARD

## Tutorial state (managed by GameManager, consumed by UI)
var tutorial_mode: bool = false
var tutorial_step: int = 0  # 0=not started, 1=place building, 2=earn gold, 3=destroy castle, 4=complete

# Simulation runs at 10 ticks/second (100ms per tick).
const TICK_RATE: int = 10
const TICK_DURATION_MSEC: int = 1000 / TICK_RATE
const MAX_STALL_MSEC: int = 5000  # Disconnect timeout
const COUNTDOWN_SECONDS: int = 3  # Pre-match countdown (CR-standard)

var _tick_accumulator_msec: int = 0
var _stall_msec: int = 0
var _faction_registry: Dictionary = {}
var _checksum_history: Dictionary = {}  # tick -> checksum

## How far between simulation ticks (0.0 = just ticked, 1.0 = about to tick).
## Visual layer uses this for smooth position interpolation.
var tick_interpolation: float = 0.0


func _ready() -> void:
	set_process(false)
	_load_faction_data()
	EventBus.disconnected_from_server.connect(_on_disconnected)
	EventBus.desync_detected.connect(_on_desync_detected)


## 1B-4: once checksums diverge the two clients are simulating different games.
## Halt the sim immediately (mirroring the disconnect path) so we stop advancing
## a divergent match behind the error overlay instead of running two realities.
func _on_desync_detected(_tick: int) -> void:
	# Desync is meaningless offline (no remote checksums) — guard anyway (2026-07-10).
	if not is_online_match:
		return
	if state == State.PLAYING or state == State.COUNTDOWN:
		state = State.MATCH_OVER
		set_process(false)
		Engine.time_scale = 1.0


func _load_faction_data() -> void:
	# Load faction data by explicit path. DirAccess directory listing does NOT
	# work in Godot web exports (PCK virtual filesystem doesn't support
	# list_dir_begin/get_next). load() and ResourceLoader.exists() work fine.
	var faction_paths := [
		"res://data/factions/kingdom.tres",
		"res://data/factions/horde.tres",
	]
	for path in faction_paths:
		if ResourceLoader.exists(path):
			var faction: FactionData = load(path)
			if faction:
				_faction_registry[faction.id] = faction
	if _faction_registry.is_empty():
		push_warning("GameManager: No faction data loaded! Check res://data/factions/")


var _cmd_seq: int = 0  # 1B-3: per-session sender-authoritative command sequence

## Called by UI to submit a command for the next tick (offline mode).
func submit_command(command: Dictionary) -> void:
	if state != State.PLAYING:
		return
	# 1B-3: stamp a monotonic per-sender seq so both peers apply same-player
	# same-tick commands in ONE order (CommandBuffer sorts (player_id, seq)).
	_cmd_seq += 1
	command["seq"] = _cmd_seq
	command_buffer.add_command(current_tick + 1, command)


## Start an offline test match with AI opponent.
func start_test_match() -> void:
	is_online_match = false
	# Mirror Match: both players use the same faction
	var ai_faction: StringName
	if selected_game_mode == GameMode.MIRROR:
		ai_faction = selected_faction
	else:
		ai_faction = &"horde" if selected_faction == &"kingdom" else &"kingdom"

	# 3.1 (2026-07-18): tutorial re-enabled for the FIRST offline game only.
	# (2026-04-14 disable reason — overlay ate all input — fixed in tutorial.gd:
	# root overlay is MOUSE_FILTER_IGNORE.) Online matches still skip it.
	tutorial_mode = PlayerData.games_played == 0
	tutorial_step = 1 if tutorial_mode else 4

	var player_data := [
		{ "id": 0, "team": 0, "faction": selected_faction, "perk": selected_perk },
		{ "id": 1, "team": 1, "faction": ai_faction, "perk": &"" },
	]
	local_player_id = 0
	_init_simulation(12345, player_data)

	if tutorial_mode:
		EventBus.tutorial_step_changed.emit(1)


## Advance the tutorial to the next step.
func advance_tutorial(to_step: int) -> void:
	tutorial_step = to_step
	EventBus.tutorial_step_changed.emit(to_step)
	if to_step >= 4:
		tutorial_mode = false
		PlayerData.set_value("tutorial_complete", true)


## Start a networked match (called by NetworkManager after lobby).
func start_online_match(seed_value: int, player_data: Array, my_player_id: int) -> void:
	is_online_match = true
	local_player_id = my_player_id
	# Online matches skip the tutorial — fresh browser (incognito) always has
	# games_played=0 and tutorial_complete=false, which would trigger the
	# tutorial overlay and block building card interaction.
	tutorial_mode = false
	tutorial_step = 4  # mark as completed so game_arena doesn't show it
	_init_simulation(seed_value, player_data)


func _init_simulation(seed_value: int, player_data: Array) -> void:
	_cmd_seq = 0  # 1B-3: fresh sequence per match
	simulation = Simulation.new()

	var all_buildings: Array = []
	for faction_id in _faction_registry:
		var faction: FactionData = _faction_registry[faction_id]
		all_buildings.append_array(faction.buildings)
	simulation.register_buildings(all_buildings)

	# Apply game mode modifiers
	var mode_config := {"income_mult": 100, "spawn_mult": 100}
	if selected_game_mode == GameMode.BLITZ:
		mode_config.income_mult = 200   # 2x income
		mode_config.spawn_mult = 50     # Half spawn intervals (2x speed)

	simulation.initialize(seed_value, player_data, mode_config)
	command_buffer = CommandBuffer.new()

	state = State.PLAYING
	current_tick = 0
	_tick_accumulator_msec = 0
	_stall_msec = 0
	_checksum_history.clear()
	set_process(true)
	EventBus.match_started.emit()


## Get the faction data for a given player.
func get_player_faction(player_id: int) -> FactionData:
	if simulation == null:
		return null
	for player in simulation.players:
		if player.id == player_id:
			return _faction_registry.get(player.faction)
	return null


## Get the player's current gold as a display integer.
func get_player_gold(player_id: int) -> int:
	if simulation == null:
		return 0
	for player in simulation.players:
		if player.id == player_id:
			return FP.to_int(player.gold)
	return 0


## Get a stored checksum for desync comparison.
func get_checksum_for_tick(tick: int) -> int:
	return _checksum_history.get(tick, -1)


## Reset all match state. Called after match ends or on disconnect.
func reset_match() -> void:
	# Leave the relay match FIRST — otherwise trailing opponent payloads keep
	# arriving for the command_buffer nulled below (null-deref on COMMANDS).
	if is_online_match and not NetworkManager.offline_mode:
		NetworkManager.leave_current_match()
	state = State.MENU
	is_online_match = false
	current_tick = 0
	simulation = null
	command_buffer = null
	_tick_accumulator_msec = 0
	_stall_msec = 0
	_checksum_history.clear()
	set_process(false)
	Engine.time_scale = 1.0  # safety reset


## Handle mid-match disconnection.
func _on_disconnected() -> void:
	# A Nakama socket drop must never terminate an OFFLINE match (2026-07-10).
	if not is_online_match:
		return
	if state == State.PLAYING or state == State.COUNTDOWN:
		state = State.MATCH_OVER
		set_process(false)
		Engine.time_scale = 1.0
		EventBus.match_aborted.emit("Connection lost")


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return

	var delta_msec: int = int(delta * 1000.0)
	_tick_accumulator_msec += delta_msec

	while _tick_accumulator_msec >= TICK_DURATION_MSEC:
		var next_tick: int = current_tick + 1

		# Online lockstep: flush local commands and wait for remote
		if is_lockstep_match():
			NetworkManager.flush_commands_for_tick(next_tick)
			if not NetworkManager.is_tick_ready(next_tick):
				# Accumulate REAL elapsed time, not tick duration.
				# At 60fps _process runs every ~16ms. Using TICK_DURATION_MSEC (100ms)
				# per frame made the 5s timeout fire in under 1 real second.
				_stall_msec += delta_msec
				if _stall_msec >= MAX_STALL_MSEC:
					push_error("Tick stall timeout at tick %d" % next_tick)
					state = State.MATCH_OVER
					set_process(false)
					EventBus.match_aborted.emit("Opponent disconnected")
				# T-101: update interp during stalls so visual layer keeps lerping
				# smoothly toward end-of-tick instead of freezing (brick walk).
				# Pure visual float — no lockstep effect, cannot cause desync.
				tick_interpolation = clampf(float(_tick_accumulator_msec) / float(TICK_DURATION_MSEC), 0.0, 1.0)
				return  # Don't consume accumulator -- retry next frame

		_stall_msec = 0
		_tick_accumulator_msec -= TICK_DURATION_MSEC
		# Commit local commands to buffer right before advancing — ensures
		# commands placed during stalling frames are included (BUG-DESYNC1).
		if is_lockstep_match():
			NetworkManager.commit_tick_commands(current_tick + 1)
		_advance_simulation_tick()

	# Update interpolation factor for visual layer (0.0 = just ticked, 1.0 = about to tick)
	tick_interpolation = clampf(float(_tick_accumulator_msec) / float(TICK_DURATION_MSEC), 0.0, 1.0)


func _advance_simulation_tick() -> void:
	current_tick += 1
	var commands := command_buffer.get_commands(current_tick)
	var result := simulation.step(commands)
	command_buffer.clear_through(current_tick)

	# Track checksums for desync detection
	var checksum: int = simulation.compute_checksum()
	_checksum_history[current_tick] = checksum
	if current_tick > 100:
		_checksum_history.erase(current_tick - 100)
	NetworkManager.send_checksum(current_tick, checksum)

	# Dispatch events to visual layer via EventBus
	for event in result.events:
		match event.type:
			"building_placed":
				EventBus.building_placed.emit(
					event.player_id,
					simulation.building_registry[event.building_type],
					Vector2i(event.grid_x, event.grid_y)
				)
			"gold_changed":
				EventBus.gold_changed.emit(event.player_id, FP.to_int(event.new_gold))
			"income":
				EventBus.gold_changed.emit(event.player_id, FP.to_int(event.new_gold))
			"building_destroyed":
				# Sim-emitted only for sells; combat kills arrive as entity_died.
				EventBus.building_destroyed.emit(event.entity_id, event.get("reason", "sold"))
			"wave_spawned":
				EventBus.wave_started.emit(event.wave_number)
			"unit_spawned":
				EventBus.unit_spawned.emit(event.entity_id, event.unit_type)
			"unit_attacked":
				# Read the position from the event payload — NEVER re-look-up the
				# target: _cleanup_dead removes hp<=0 entities within the same step,
				# so every killing blow used to be silently swallowed here (no swing,
				# no projectile, no damage number on lethal hits).
				EventBus.unit_attacked.emit(
					event.attacker_id, event.target_id,
					FP.to_int(event.damage),
					FP.to_float(event.get("target_x", 0)), FP.to_float(event.get("target_y", 0))
				)
			"unit_healed":
				EventBus.unit_healed.emit(
					event.healer_id, event.target_id,
					FP.to_int(event.amount),
					FP.to_float(event.get("target_x", 0)), FP.to_float(event.get("target_y", 0))
				)
			"castle_damaged":
				EventBus.castle_damaged.emit(event.team, FP.to_int(event.damage), FP.to_int(event.remaining_hp), event.get("attacker_id", -1))
			"castle_wrath_ready":
				EventBus.castle_wrath_ready.emit(event.team, event.castle_id)
			"castle_wrath_activated":
				EventBus.castle_wrath_activated.emit(
					event.team,
					event.target_ids,
					FP.to_float(event.center_x),
					FP.to_float(event.center_y),
					float(event.range_px)
				)
			"castle_wrath_refused":
				EventBus.castle_wrath_refused.emit(event.team, event.reason)
			"prep_phase_ended":
				EventBus.prep_phase_ended.emit()
			"skill_proc":
				# 1D-2: forward the sim's splash center so the visual layer
				# never re-looks-up a moving/dead target in the live sim.
				var skill_center := Vector2.INF
				if event.has("center_x"):
					skill_center = Vector2(FP.to_float(event.center_x), FP.to_float(event.center_y))
				EventBus.skill_activated.emit(event.unit_id, StringName(event.skill), skill_center)
			"ability_activated":
				# Was silently dropped — no arm here — so War Horn / Blood Totem
				# activations were invisible + inaudible (esp. the enemy's).
				EventBus.ability_activated.emit(
					event.building_id, event.team, event.ability, event.duration)
			"match_over":
				state = State.MATCH_OVER
				set_process(false)
				_dramatic_match_end(event.winner)
			"entity_died":
				if event.get("entity_type", "unit") == "building":
					EventBus.building_destroyed.emit(event.id, event.get("reason", "killed"))
				else:
					# Bounty + position come from the payload — the entity is
					# already removed from the sim when this dispatches.
					EventBus.unit_died.emit(
						event.id, -1,
						event.get("bounty", 0),
						FP.to_float(event.get("x", 0)), FP.to_float(event.get("y", 0))
					)


func _dramatic_match_end(winner: int) -> void:
	# Slow-mo for 1.5 seconds, then show end screen
	Engine.time_scale = 0.3
	SFX.stop_music(0.3)
	await get_tree().create_timer(1.5 * 0.3).timeout  # 1.5s perceived
	Engine.time_scale = 1.0
	EventBus.match_ended.emit(winner)
