## Manages match lifecycle and bridges the deterministic simulation
## with the Godot scene tree.
extends Node

enum State { MENU, LOADING, PLAYING, MATCH_OVER }

var state: State = State.MENU
var current_tick: int = 0
var simulation: Simulation = null
var command_buffer: CommandBuffer = null

# Simulation runs at 10 ticks/second (100ms per tick).
const TICK_RATE: int = 10
const TICK_DURATION_MSEC: int = 1000 / TICK_RATE

var _tick_accumulator_msec: int = 0


func _ready() -> void:
	set_process(false)


func start_match(seed_value: int, player_data: Array) -> void:
	simulation = Simulation.new()
	simulation.initialize(seed_value, player_data)
	command_buffer = CommandBuffer.new()

	state = State.PLAYING
	current_tick = 0
	_tick_accumulator_msec = 0
	set_process(true)
	EventBus.match_started.emit()


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

	# Translate simulation events to EventBus signals
	for event in result.events:
		match event.type:
			"income":
				EventBus.gold_changed.emit(event.player_id, event.new_gold)
			"match_over":
				state = State.MATCH_OVER
				set_process(false)
				EventBus.match_ended.emit(event.winner)
			"entity_died":
				EventBus.unit_died.emit(event.id, -1)
