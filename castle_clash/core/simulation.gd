## The authoritative deterministic game simulation.
## Single source of truth for game state. Every client runs an identical copy.
## Contains NO Godot node references. Communicates via return values.
class_name Simulation

var tick: int = 0
var rng: DeterministicRNG
var match_seed: int

# Game state -- all values are fixed-point or plain ints
var entities: Array[Dictionary] = []
var next_entity_id: int = 0
var castles: Array[Dictionary] = []
var players: Array[Dictionary] = []
var wave_number: int = 0
var wave_timer: int = 0
var match_over: bool = false
var winning_team: int = -1

# Grid state -- one 2D array per player
var grid_cells: Array = []

# Building data registry -- maps StringName -> BuildingData
var building_registry: Dictionary = {}

# Damage table -- [attack_type][armor_type] = FP multiplier
var damage_table: Array = []

# Timing constants
const WAVE_INTERVAL_TICKS: int = 250  # 25 seconds at 10 ticks/sec
const INCOME_INTERVAL_TICKS: int = 50 # 5 seconds
const TICKS_PER_SECOND: int = 10

# Grid constants
const GRID_COLS: int = 11
const GRID_ROWS: int = 20
const CELL_SIZE_PX: int = 32
const GRID_ORIGIN_Y: int = 40

# Arena pixel-space constants
const TEAM_0_SPAWN_X: int = 432   # Right edge of build zone 0
const TEAM_1_SPAWN_X: int = 848   # Left edge of build zone 1
const CASTLE_0_X: int = 40        # Center of castle 0 area
const CASTLE_1_X: int = 1240      # Center of castle 1 area


## Register all available building types. Call before initialize().
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

	# Initialize grids
	grid_cells.clear()
	for i in players.size():
		var player_grid: Array = []
		for row in GRID_ROWS:
			var grid_row: Array = []
			grid_row.resize(GRID_COLS)
			grid_row.fill(-1)
			player_grid.append(grid_row)
		grid_cells.append(player_grid)

	# Build damage table as FP values
	# [attack_type][armor_type]: Physical, Pierce, Magic, Siege vs Light, Medium, Heavy, Fortified
	var raw_table := [
		[100, 100, 75, 50],   # Physical
		[150, 75, 100, 50],   # Pierce
		[125, 75, 100, 100],  # Magic
		[50, 50, 50, 150],    # Siege
	]
	damage_table.clear()
	for row in raw_table:
		var fp_row: Array = []
		for val in row:
			fp_row.append(FP.div(FP.from_int(val), FP.from_int(100)))
		damage_table.append(fp_row)


## Advance simulation by one tick.
func step(commands: Array) -> Dictionary:
	tick += 1
	var events: Array[Dictionary] = []

	# 1. Process player commands
	for cmd in commands:
		events.append_array(_process_command(cmd))

	# 2. Wave spawning
	wave_timer -= 1
	if wave_timer <= 0:
		wave_timer = WAVE_INTERVAL_TICKS
		events.append_array(_spawn_wave())

	# 3. Update all units
	events.append_array(_update_units())

	# 4. Remove dead entities
	events.append_array(_cleanup_dead())

	# 5. Check win condition (only first castle to fall wins)
	if not match_over:
		for castle in castles:
			if FP.lte(castle.hp, FP.ZERO):
				match_over = true
				winning_team = 1 - castle.team
				events.append({ "type": "match_over", "winner": winning_team })
				break

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


## Read-only query for ghost preview.
func can_place_building(player_id: int, building_type: StringName, grid_x: int, grid_y: int) -> bool:
	var player_index := get_player_index(player_id)
	if player_index == -1:
		return false

	var bd = building_registry.get(building_type)
	if bd == null:
		return false

	if FP.lt(players[player_index].gold, FP.from_int(bd.gold_cost)):
		return false

	var size_x: int = bd.grid_size.x
	var size_y: int = bd.grid_size.y
	if grid_x < 0 or grid_y < 0 or grid_x + size_x > GRID_COLS or grid_y + size_y > GRID_ROWS:
		return false

	var grid: Array = grid_cells[player_index]
	for row in range(grid_y, grid_y + size_y):
		for col in range(grid_x, grid_x + size_x):
			if grid[row][col] != -1:
				return false

	if bd.requires_building != &"":
		if not player_has_building(player_index, bd.requires_building):
			return false

	return true


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
	for pi in grid_cells.size():
		for row in grid_cells[pi]:
			for cell in row:
				checksum = checksum ^ (cell * 61)
	return checksum


# --- Helpers ---

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


func _find_entity_by_id(id: int):
	for entity in entities:
		if entity.id == id:
			return entity
	return null


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

	for row in range(gy, gy + size_y):
		for col in range(gx, gx + size_x):
			grid[row][col] = entity_id

	player.gold = FP.sub(player.gold, cost_fp)

	# Income building bonus
	if bd.income_bonus > 0:
		player.income = FP.add(player.income, FP.from_int(bd.income_bonus))

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

	var refund := FP.from_int(bd.gold_cost * bd.sell_refund_percent / 100)
	players[player_index].gold = FP.add(players[player_index].gold, refund)

	var grid: Array = grid_cells[player_index]
	for row in range(entity.grid_y, entity.grid_y + entity.grid_size_y):
		for col in range(entity.grid_x, entity.grid_x + entity.grid_size_x):
			grid[row][col] = -1

	entities.remove_at(building_idx)

	events.append({ "type": "building_destroyed", "entity_id": entity.id })
	events.append({
		"type": "gold_changed",
		"player_id": cmd.player_id,
		"new_gold": players[player_index].gold,
	})
	return events


# --- Wave Spawning ---

func _spawn_wave() -> Array[Dictionary]:
	wave_number += 1
	var events: Array[Dictionary] = []
	events.append({ "type": "wave_spawned", "wave_number": wave_number })

	# Iterate building entities and spawn their units
	for entity in entities:
		if entity.type != "building":
			continue
		var bd = building_registry.get(entity.building_type)
		if bd == null or bd.spawns_unit == null:
			continue

		var ud = bd.spawns_unit
		var team: int = entity.team

		# Spawn X: at build zone edge facing combat lane
		var spawn_x: int = FP.from_int(TEAM_0_SPAWN_X) if team == 0 else FP.from_int(TEAM_1_SPAWN_X)

		# Spawn Y: center of the building's grid footprint in pixels
		var spawn_y_px: int = GRID_ORIGIN_Y + entity.grid_y * CELL_SIZE_PX + (entity.grid_size_y * CELL_SIZE_PX) / 2
		var spawn_y: int = FP.from_int(spawn_y_px)

		# Convert unit data to simulation FP values
		var move_speed_fp: int = FP.div(
			FP.from_int(ud.move_speed * CELL_SIZE_PX),
			FP.from_int(TICKS_PER_SECOND)
		)
		var attack_range_fp: int = FP.from_int(ud.attack_range * CELL_SIZE_PX)

		for i in bd.units_per_wave:
			var unit_id := next_entity_id
			next_entity_id += 1

			# Small Y offset to prevent perfect stacking from same building
			var y_offset: int = FP.from_int(i * 6)

			var unit := {
				"id": unit_id,
				"type": "unit",
				"unit_type": ud.id,
				"owner": entity.owner,
				"player_index": entity.player_index,
				"team": team,
				"hp": FP.from_int(ud.max_hp),
				"max_hp": FP.from_int(ud.max_hp),
				"attack_damage": FP.from_int(ud.attack_damage),
				"attack_speed_ticks": ud.attack_speed_ticks,
				"attack_range": attack_range_fp,
				"move_speed": move_speed_fp,
				"armor": FP.from_int(ud.armor),
				"attack_type": ud.attack_type,
				"armor_type": ud.armor_type,
				"role": ud.role,
				"bounty": ud.bounty,
				"x": spawn_x,
				"y": FP.add(spawn_y, y_offset),
				"attack_cooldown": 0,
				"target_id": -1,
			}
			entities.append(unit)

			events.append({
				"type": "unit_spawned",
				"entity_id": unit_id,
				"unit_type": ud.id,
				"team": team,
				"player_index": entity.player_index,
				"x": unit.x,
				"y": unit.y,
				"role": ud.role,
			})

	return events


# --- Unit Update Loop ---

func _update_units() -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	for entity in entities:
		if entity.type != "unit":
			continue
		if FP.lte(entity.hp, FP.ZERO):
			continue

		# Casters (role=2) heal allies instead of attacking
		if entity.role == 2:
			if entity.attack_cooldown > 0:
				entity.attack_cooldown -= 1
			if entity.attack_cooldown <= 0:
				var healed := _try_heal(entity)
				if healed:
					events.append_array(healed)
					entity.attack_cooldown = entity.attack_speed_ticks
			# Casters still move with the army
			_move_unit(entity)
			continue

		# Phase 1: Acquire target
		_acquire_target(entity)

		# Phase 2: Attack or move
		if entity.attack_cooldown > 0:
			entity.attack_cooldown -= 1

		var attacked: bool = false
		if entity.target_id != -1:
			var target = _find_entity_by_id(entity.target_id)
			if target != null and FP.gt(target.hp, FP.ZERO):
				var dist_sq := _distance_squared(entity, target)
				var range_sq := FP.mul(entity.attack_range, entity.attack_range)
				if FP.lte(dist_sq, range_sq):
					if entity.attack_cooldown <= 0:
						events.append_array(_perform_attack(entity, target))
						entity.attack_cooldown = entity.attack_speed_ticks
					attacked = true

		if not attacked:
			# Phase 3: Move toward enemy
			_move_unit(entity)

			# Phase 4: Check if reached castle zone
			events.append_array(_check_castle_damage(entity))

	return events


func _acquire_target(unit: Dictionary) -> void:
	# Check if current target is still valid
	if unit.target_id != -1:
		var current = _find_entity_by_id(unit.target_id)
		if current != null and FP.gt(current.hp, FP.ZERO) and current.team != unit.team:
			return  # Keep current target

	# Find nearest living enemy unit
	var best_id: int = -1
	var best_dist_sq: int = 0x7FFFFFFFFFFFFFF  # Large number

	for other in entities:
		if other.type != "unit":
			continue
		if other.team == unit.team:
			continue
		if FP.lte(other.hp, FP.ZERO):
			continue
		var dist_sq := _distance_squared(unit, other)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = other.id

	unit.target_id = best_id


## Distance squared between two entities.
## Uses X-distance only for combat (lane-based game -- units march horizontally).
## Full 2D distance would prevent units on different Y-lanes from ever fighting.
func _distance_squared(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	return FP.mul(dx, dx)


func _move_unit(unit: Dictionary) -> void:
	if unit.team == 0:
		unit.x = FP.add(unit.x, unit.move_speed)
		unit.x = FP.min_fp(unit.x, FP.from_int(CASTLE_1_X))
	else:
		unit.x = FP.sub(unit.x, unit.move_speed)
		unit.x = FP.max_fp(unit.x, FP.from_int(CASTLE_0_X))


func _perform_attack(attacker: Dictionary, target: Dictionary) -> Array[Dictionary]:
	var multiplier: int = damage_table[attacker.attack_type][target.armor_type]
	var raw_damage: int = FP.mul(attacker.attack_damage, multiplier)
	var final_damage: int = FP.sub(raw_damage, target.armor)
	final_damage = FP.max_fp(final_damage, FP.ONE)  # Minimum 1 damage

	target.hp = FP.sub(target.hp, final_damage)

	return [{
		"type": "unit_attacked",
		"attacker_id": attacker.id,
		"target_id": target.id,
		"damage": final_damage,
		"target_hp": target.hp,
	}]


## Caster heals the nearest damaged ally in range.
func _try_heal(healer: Dictionary) -> Array[Dictionary]:
	var heal_amount: int = healer.attack_damage  # Reuse attack_damage as heal power
	var range_sq: int = FP.mul(healer.attack_range, healer.attack_range)

	# Find nearest damaged ally in range
	var best_id: int = -1
	var best_dist_sq: int = 0x7FFFFFFFFFFFFFF
	var best_entity = null

	for other in entities:
		if other.type != "unit":
			continue
		if other.team != healer.team:
			continue
		if other.id == healer.id:
			continue
		if FP.lte(other.hp, FP.ZERO):
			continue
		# Only heal damaged units
		if FP.gte(other.hp, other.max_hp):
			continue
		var dist_sq := _distance_squared(healer, other)
		if FP.lte(dist_sq, range_sq) and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = other.id
			best_entity = other

	if best_entity == null:
		return []

	# Heal, capped at max HP
	best_entity.hp = FP.min_fp(
		FP.add(best_entity.hp, heal_amount),
		best_entity.max_hp
	)

	return [{
		"type": "unit_healed",
		"healer_id": healer.id,
		"target_id": best_id,
		"amount": heal_amount,
		"target_hp": best_entity.hp,
	}]


func _check_castle_damage(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var enemy_team: int = 1 - unit.team
	var in_castle_zone: bool = false

	if unit.team == 0 and FP.gte(unit.x, FP.from_int(CASTLE_1_X)):
		in_castle_zone = true
	elif unit.team == 1 and FP.lte(unit.x, FP.from_int(CASTLE_0_X)):
		in_castle_zone = true

	if in_castle_zone and unit.attack_cooldown <= 0:
		var castle: Dictionary = castles[enemy_team]
		if FP.gt(castle.hp, FP.ZERO):
			# Castle armor type = Fortified (3)
			var multiplier: int = damage_table[unit.attack_type][3]
			var raw_damage: int = FP.mul(unit.attack_damage, multiplier)
			var final_damage: int = FP.max_fp(raw_damage, FP.ONE)
			castle.hp = FP.sub(castle.hp, final_damage)
			unit.attack_cooldown = unit.attack_speed_ticks

			events.append({
				"type": "castle_damaged",
				"team": enemy_team,
				"damage": final_damage,
				"remaining_hp": castle.hp,
				"attacker_id": unit.id,
			})

	return events


# --- Cleanup ---

func _cleanup_dead() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in range(entities.size() - 1, -1, -1):
		var entity: Dictionary = entities[i]
		if FP.lte(entity.get("hp", FP.ONE), FP.ZERO):
			events.append({
				"type": "entity_died",
				"id": entity.id,
				"entity_type": entity.type,
				"team": entity.get("team", -1),
				"x": entity.get("x", 0),
				"y": entity.get("y", 0),
			})
			# Kill bounty: award gold to the opposing team's players
			if entity.type == "unit":
				var bounty: int = entity.get("bounty", 0)
				if bounty > 0:
					var bounty_fp := FP.from_int(bounty)
					var enemy_team: int = 1 - entity.team
					for player in players:
						if player.team == enemy_team:
							player.gold = FP.add(player.gold, bounty_fp)
							events.append({
								"type": "gold_changed",
								"player_id": player.id,
								"new_gold": player.gold,
							})
			# If building, clear grid cells and remove income bonus
			if entity.type == "building":
				var bd = building_registry.get(entity.building_type)
				if bd and bd.income_bonus > 0:
					var pi: int = entity.player_index
					players[pi].income = FP.sub(players[pi].income, FP.from_int(bd.income_bonus))
				var grid: Array = grid_cells[entity.player_index]
				for row in range(entity.grid_y, entity.grid_y + entity.grid_size_y):
					for col in range(entity.grid_x, entity.grid_x + entity.grid_size_x):
						grid[row][col] = -1
			entities.remove_at(i)
	return events
