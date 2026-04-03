## Manages match lifecycle and bridges the deterministic simulation
## with the Godot scene tree.
extends Node

enum State { MENU, LOADING, PLAYING, MATCH_OVER }

var state: State = State.MENU
var current_tick: int = 0
var simulation: Simulation = null
var command_buffer: CommandBuffer = null
var local_player_id: int = 0

# Simulation runs at 10 ticks/second (100ms per tick).
const TICK_RATE: int = 10
const TICK_DURATION_MSEC: int = 1000 / TICK_RATE

var _tick_accumulator_msec: int = 0
var _faction_registry: Dictionary = {}  # faction_id -> FactionData


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


## Called by UI to submit a command for the next tick.
func submit_command(command: Dictionary) -> void:
	if state != State.PLAYING:
		return
	command_buffer.add_command(current_tick + 1, command)


## Start a test match for offline single-player development.
func start_test_match() -> void:
	var player_data := [
		{ "id": 0, "team": 0, "faction": &"kingdom" },
		{ "id": 1, "team": 1, "faction": &"kingdom" },
	]
	local_player_id = 0

	simulation = Simulation.new()

	# Register all buildings from all factions
	var all_buildings: Array = []
	for faction_id in _faction_registry:
		var faction: FactionData = _faction_registry[faction_id]
		all_buildings.append_array(faction.buildings)
	simulation.register_buildings(all_buildings)

	simulation.initialize(12345, player_data)
	command_buffer = CommandBuffer.new()

	state = State.PLAYING
	current_tick = 0
	_tick_accumulator_msec = 0
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


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return

	_tick_accumulator_msec += int(delta * 1000.0)

	while _tick_accumulator_msec >= TICK_DURATION_MSEC:
		_tick_accumulator_msec -= TICK_DURATION_MSEC
		_advance_simulation_tick()


func _advance_simulation_tick() -> void:
	current_tick += 1
	var commands := command_buffer.get_commands(current_tick)
	var result := simulation.step(commands)
	command_buffer.clear_through(current_tick)

	for event in result.events:
		match event.type:
			"building_placed":
				EventBus.building_placed.emit(
					event.player_id,
					simulation.building_registry[event.building_type],
					Vector2i(event.grid_x, event.grid_y)
				)
			"gold_changed":
				EventBus.gold_changed.emit(event.player_id, event.new_gold)
			"income":
				EventBus.gold_changed.emit(event.player_id, event.new_gold)
			"building_destroyed":
				EventBus.building_destroyed.emit(event.entity_id)
			"wave_spawned":
				EventBus.wave_started.emit(event.wave_number)
			"match_over":
				state = State.MATCH_OVER
				set_process(false)
				EventBus.match_ended.emit(event.winner)
			"entity_died":
				EventBus.unit_died.emit(event.id, -1)
