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

# Grid state -- one 2D array per player
# grid_cells[player_index][row][col] = entity_id or -1 (empty)
var grid_cells: Array = []

# Building data registry -- maps building_type StringName -> BuildingData
var building_registry: Dictionary = {}

const WAVE_INTERVAL_TICKS: int = 250  # 25 seconds at 10 ticks/sec
const INCOME_INTERVAL_TICKS: int = 50 # 5 seconds
const GRID_COLS: int = 11
const GRID_ROWS: int = 20


## Register all available building types. Must be called before initialize().
func register_buildings(building_list: Array) -> void:
	for bd in building_list:
		building_registry[bd.id] = bd


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

	players.clear()
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

	# Initialize grids -- one per player
	grid_cells.clear()
	for i in players.size():
		var player_grid: Array = []
		for row in GRID_ROWS:
			var grid_row: Array = []
			grid_row.resize(GRID_COLS)
			grid_row.fill(-1)
			player_grid.append(grid_row)
		grid_cells.append(player_grid)


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


## Read-only query: can this building be placed? Used by visual layer for ghost.
func can_place_building(player_id: int, building_type: StringName, grid_x: int, grid_y: int) -> bool:
	var player_index := get_player_index(player_id)
	if player_index == -1:
		return false

	var bd = building_registry.get(building_type)
	if bd == null:
		return false

	# Check gold
	if FP.lt(players[player_index].gold, FP.from_int(bd.gold_cost)):
		return false

	# Check bounds
	var size_x: int = bd.grid_size.x
	var size_y: int = bd.grid_size.y
	if grid_x < 0 or grid_y < 0 or grid_x + size_x > GRID_COLS or grid_y + size_y > GRID_ROWS:
		return false

	# Check all cells empty
	var grid: Array = grid_cells[player_index]
	for row in range(grid_y, grid_y + size_y):
		for col in range(grid_x, grid_x + size_x):
			if grid[row][col] != -1:
				return false

	# Check tech requirements
	if bd.requires_building != &"":
		if not player_has_building(player_index, bd.requires_building):
			return false

	return true


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
	# Include grid state
	for pi in grid_cells.size():
		for row in grid_cells[pi]:
			for cell in row:
				checksum = checksum ^ (cell * 61)
	return checksum


# --- Helper Methods ---

func get_player_index(player_id: int) -> int:
	for i in players.size():
		if players[i].id == player_id:
			return i
	return -1


func player_has_building(player_index: int, building_type: StringName) -> bool:
	for entity in entities:
		if entity.type == "building" and entity.player_index == player_index \
		   and entity.building_type == building_type:
			return true
	return false


# --- Command Processing ---

func _process_command(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match cmd.type:
		Command.Type.PLACE_BUILDING:
			events.append_array(_handle_place_building(cmd))
		Command.Type.SELL_BUILDING:
			events.append_array(_handle_sell_building(cmd))
	return events


func _handle_place_building(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player_index := get_player_index(cmd.player_id)
	if player_index == -1:
		return events

	var player: Dictionary = players[player_index]
	var bd = building_registry.get(cmd.building_type)
	if bd == null:
		return events

	var cost_fp := FP.from_int(bd.gold_cost)
	if FP.lt(player.gold, cost_fp):
		return events

	var gx: int = cmd.grid_x
	var gy: int = cmd.grid_y
	var size_x: int = bd.grid_size.x
	var size_y: int = bd.grid_size.y

	if gx < 0 or gy < 0 or gx + size_x > GRID_COLS or gy + size_y > GRID_ROWS:
		return events

	var grid: Array = grid_cells[player_index]
	for row in range(gy, gy + size_y):
		for col in range(gx, gx + size_x):
			if grid[row][col] != -1:
				return events

	if bd.requires_building != &"":
		if not player_has_building(player_index, bd.requires_building):
			return events

	# All checks passed -- place the building
	var entity_id := next_entity_id
	next_entity_id += 1

	var entity := {
		"id": entity_id,
		"type": "building",
		"building_type": bd.id,
		"owner": cmd.player_id,
		"player_index": player_index,
		"team": player.team,
		"grid_x": gx,
		"grid_y": gy,
		"grid_size_x": size_x,
		"grid_size_y": size_y,
		"hp": FP.from_int(500),
		"max_hp": FP.from_int(500),
	}
	entities.append(entity)

	# Mark grid cells
	for row in range(gy, gy + size_y):
		for col in range(gx, gx + size_x):
			grid[row][col] = entity_id

	# Deduct gold
	player.gold = FP.sub(player.gold, cost_fp)

	events.append({
		"type": "building_placed",
		"entity_id": entity_id,
		"player_id": cmd.player_id,
		"player_index": player_index,
		"building_type": bd.id,
		"grid_x": gx,
		"grid_y": gy,
		"grid_size_x": size_x,
		"grid_size_y": size_y,
	})
	events.append({
		"type": "gold_changed",
		"player_id": cmd.player_id,
		"new_gold": player.gold,
	})

	return events


func _handle_sell_building(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player_index := get_player_index(cmd.player_id)
	if player_index == -1:
		return events

	# Find the building entity
	var building_idx: int = -1
	for i in entities.size():
		if entities[i].id == cmd.building_id and entities[i].type == "building" \
		   and entities[i].player_index == player_index:
			building_idx = i
			break

	if building_idx == -1:
		return events

	var entity: Dictionary = entities[building_idx]
	var bd = building_registry.get(entity.building_type)
	if bd == null:
		return events

	# Refund gold
	var refund := FP.from_int(bd.gold_cost * bd.sell_refund_percent / 100)
	players[player_index].gold = FP.add(players[player_index].gold, refund)

	# Clear grid cells
	var grid: Array = grid_cells[player_index]
	for row in range(entity.grid_y, entity.grid_y + entity.grid_size_y):
		for col in range(entity.grid_x, entity.grid_x + entity.grid_size_x):
			grid[row][col] = -1

	# Remove entity
	entities.remove_at(building_idx)

	events.append({ "type": "building_destroyed", "entity_id": entity.id })
	events.append({
		"type": "gold_changed",
		"player_id": cmd.player_id,
		"new_gold": players[player_index].gold,
	})

	return events


# --- Wave Spawning (stub -- units not visual yet) ---

func _spawn_wave() -> Array[Dictionary]:
	wave_number += 1
	var events: Array[Dictionary] = []
	events.append({ "type": "wave_spawned", "wave_number": wave_number })
	# TODO: iterate building entities, spawn their units
	return events


func _update_units() -> Array[Dictionary]:
	return []


func _cleanup_dead() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in range(entities.size() - 1, -1, -1):
		if FP.lte(entities[i].get("hp", FP.ONE), FP.ZERO):
			events.append({ "type": "entity_died", "id": entities[i].id })
			entities.remove_at(i)
	return events
