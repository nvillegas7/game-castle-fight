## The authoritative deterministic game simulation.
## Single source of truth for game state. Every client runs an identical copy.
## Contains NO Godot node references. Communicates via return values.
class_name Simulation

var tick: int = 0
var rng: DeterministicRNG
var match_seed: int

# Game state -- all values are fixed-point or plain ints
var entities: Array[Dictionary] = []  # All units and buildings, sorted by ID
var next_entity_id: int = 0
var castles: Array[Dictionary] = []   # [team_0, team_1]
var players: Array[Dictionary] = []
var wave_number: int = 0
var wave_timer: int = 0               # Ticks until next wave
var match_over: bool = false
var winning_team: int = -1

const WAVE_INTERVAL_TICKS: int = 250  # 25 seconds at 10 ticks/sec
const INCOME_INTERVAL_TICKS: int = 50 # 5 seconds


func initialize(seed_value: int, player_data: Array) -> void:
	match_seed = seed_value
	rng = DeterministicRNG.new()
	rng.seed_from(seed_value)
	tick = 0
	next_entity_id = 0
	entities.clear()
	wave_number = 0
	wave_timer = WAVE_INTERVAL_TICKS
	match_over = false
	winning_team = -1

	for p in player_data:
		players.append({
			"id": p.id,
			"team": p.team,
			"faction": p.faction,
			"gold": FP.from_int(100),
			"income": FP.from_int(10),
		})

	castles = [
		{ "team": 0, "hp": FP.from_int(10000), "max_hp": FP.from_int(10000) },
		{ "team": 1, "hp": FP.from_int(10000), "max_hp": FP.from_int(10000) },
	]


## Advance simulation by one tick. Returns events for the visual layer.
func step(commands: Array) -> Dictionary:
	tick += 1
	var events: Array[Dictionary] = []

	# 1. Process player commands
	for cmd in commands:
		var cmd_events := _process_command(cmd)
		events.append_array(cmd_events)

	# 2. Wave spawning
	wave_timer -= 1
	if wave_timer <= 0:
		wave_timer = WAVE_INTERVAL_TICKS
		var spawn_events := _spawn_wave()
		events.append_array(spawn_events)

	# 3. Update all units (movement, targeting, combat)
	var combat_events := _update_units()
	events.append_array(combat_events)

	# 4. Remove dead entities
	var death_events := _cleanup_dead()
	events.append_array(death_events)

	# 5. Check win condition
	for castle in castles:
		if FP.lte(castle.hp, FP.ZERO):
			match_over = true
			winning_team = 1 - castle.team
			events.append({ "type": "match_over", "winner": winning_team })

	# 6. Income tick
	if tick % INCOME_INTERVAL_TICKS == 0:
		for player in players:
			player.gold = FP.add(player.gold, player.income)
			events.append({
				"type": "income",
				"player_id": player.id,
				"amount": player.income,
				"new_gold": player.gold,
			})

	return { "tick": tick, "events": events }


## Compute checksum for desync detection.
func compute_checksum() -> int:
	var checksum: int = tick
	checksum = checksum ^ (castles[0].hp * 31)
	checksum = checksum ^ (castles[1].hp * 37)
	for entity in entities:
		checksum = checksum ^ (entity.id * 41)
		checksum = checksum ^ (entity.get("x", 0) * 43)
		checksum = checksum ^ (entity.get("y", 0) * 47)
		checksum = checksum ^ (entity.get("hp", 0) * 53)
	for s in rng.get_state():
		checksum = checksum ^ (s * 59)
	return checksum


# --- Stubs (to be implemented as we build the game) ---

func _process_command(_cmd: Dictionary) -> Array[Dictionary]:
	return []


func _spawn_wave() -> Array[Dictionary]:
	wave_number += 1
	return []


func _update_units() -> Array[Dictionary]:
	return []


func _cleanup_dead() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in range(entities.size() - 1, -1, -1):
		if FP.lte(entities[i].get("hp", FP.ONE), FP.ZERO):
			events.append({ "type": "entity_died", "id": entities[i].id })
			entities.remove_at(i)
	return events
