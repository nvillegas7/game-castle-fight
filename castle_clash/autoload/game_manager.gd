## Manages match lifecycle and bridges the deterministic simulation
## with the Godot scene tree. Supports both offline and online (lockstep) modes.
extends Node

enum State { MENU, LOADING, PLAYING, MATCH_OVER }

var state: State = State.MENU
var current_tick: int = 0
var simulation: Simulation = null
var command_buffer: CommandBuffer = null
var local_player_id: int = 0

## Selected faction for the local player (set by main menu).
var selected_faction: StringName = &"kingdom"

# Simulation runs at 10 ticks/second (100ms per tick).
const TICK_RATE: int = 10
const TICK_DURATION_MSEC: int = 1000 / TICK_RATE
const MAX_STALL_MSEC: int = 5000  # Disconnect timeout

var _tick_accumulator_msec: int = 0
var _stall_msec: int = 0
var _faction_registry: Dictionary = {}
var _checksum_history: Dictionary = {}  # tick -> checksum


func _ready() -> void:
	set_process(false)
	_load_faction_data()


func _load_faction_data() -> void:
	var dir := DirAccess.open("res://data/factions/")
	if dir == null:
		push_warning("GameManager: No factions directory found")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var faction: FactionData = load("res://data/factions/" + file_name)
			if faction:
				_faction_registry[faction.id] = faction
		file_name = dir.get_next()


## Called by UI to submit a command for the next tick (offline mode).
func submit_command(command: Dictionary) -> void:
	if state != State.PLAYING:
		return
	command_buffer.add_command(current_tick + 1, command)


## Start an offline test match with AI opponent.
func start_test_match() -> void:
	var ai_faction: StringName = &"horde" if selected_faction == &"kingdom" else &"kingdom"
	var player_data := [
		{ "id": 0, "team": 0, "faction": selected_faction },
		{ "id": 1, "team": 1, "faction": ai_faction },
	]
	local_player_id = 0
	_init_simulation(12345, player_data)


## Start a networked match (called by NetworkManager after lobby).
func start_online_match(seed_value: int, player_data: Array, my_player_id: int) -> void:
	local_player_id = my_player_id
	_init_simulation(seed_value, player_data)


func _init_simulation(seed_value: int, player_data: Array) -> void:
	simulation = Simulation.new()

	var all_buildings: Array = []
	for faction_id in _faction_registry:
		var faction: FactionData = _faction_registry[faction_id]
		all_buildings.append_array(faction.buildings)
	simulation.register_buildings(all_buildings)

	simulation.initialize(seed_value, player_data)
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


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return

	_tick_accumulator_msec += int(delta * 1000.0)

	while _tick_accumulator_msec >= TICK_DURATION_MSEC:
		var next_tick: int = current_tick + 1

		# Online lockstep: flush local commands and wait for remote
		if not NetworkManager.offline_mode:
			NetworkManager.flush_commands_for_tick(next_tick)
			if not NetworkManager.is_tick_ready(next_tick):
				_stall_msec += TICK_DURATION_MSEC
				if _stall_msec >= MAX_STALL_MSEC:
					push_error("Tick stall timeout at tick %d" % next_tick)
				return  # Don't consume accumulator -- retry next frame

		_stall_msec = 0
		_tick_accumulator_msec -= TICK_DURATION_MSEC
		_advance_simulation_tick()


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
				EventBus.building_destroyed.emit(event.entity_id)
			"wave_spawned":
				EventBus.wave_started.emit(event.wave_number)
			"unit_spawned":
				EventBus.unit_spawned.emit(event.entity_id, event.unit_type)
			"unit_attacked":
				var target = simulation._find_entity_by_id(event.target_id)
				if target:
					EventBus.unit_attacked.emit(
						event.attacker_id, event.target_id,
						FP.to_int(event.damage),
						FP.to_float(target.x), FP.to_float(target.y)
					)
			"unit_healed":
				var healed = simulation._find_entity_by_id(event.target_id)
				if healed:
					EventBus.unit_healed.emit(
						event.healer_id, event.target_id,
						FP.to_int(event.amount),
						FP.to_float(healed.x), FP.to_float(healed.y)
					)
			"castle_damaged":
				EventBus.castle_damaged.emit(event.team, FP.to_int(event.damage), FP.to_int(event.remaining_hp))
			"match_over":
				state = State.MATCH_OVER
				set_process(false)
				EventBus.match_ended.emit(event.winner)
			"entity_died":
				if event.get("entity_type", "unit") == "building":
					EventBus.building_destroyed.emit(event.id)
				else:
					EventBus.unit_died.emit(event.id, -1)
