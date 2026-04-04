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

	# 2. Per-building spawn timers
	events.append_array(_update_building_spawns())

	# Match timer (for display only)
	wave_timer -= 1
	if wave_timer <= 0:
		wave_timer = WAVE_INTERVAL_TICKS
		wave_number += 1

	# 3. Update all units
	events.append_array(_update_units())

	# 4. Remove dead entities
	events.append_array(_cleanup_dead())

	# 4.5. Castle burn damage (from Siege Fire)
	for castle in castles:
		if castle.get("burn_timer", 0) > 0:
			castle.burn_timer -= 1
			var burn_dmg: int = castle.get("burn_damage", FP.ZERO)
			castle.hp = FP.sub(castle.hp, burn_dmg)
			events.append({"type": "castle_damaged", "team": castle.team, "damage": burn_dmg, "remaining_hp": castle.hp, "attacker_id": -1})

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
		"spawn_timer": bd.spawn_interval_ticks if bd.spawns_unit else 0,
		"spawn_interval": bd.spawn_interval_ticks if bd.spawns_unit else 0,
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

## Per-building spawn timer update. Each building has its own cooldown.
func _update_building_spawns() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for entity in entities:
		if entity.type != "building":
			continue
		var interval: int = entity.get("spawn_interval", 0)
		if interval <= 0:
			continue  # Income building, no spawning

		entity.spawn_timer -= 1
		if entity.spawn_timer <= 0:
			entity.spawn_timer = interval
			events.append_array(_spawn_from_building(entity))
	return events


## Spawn units from a single building.
func _spawn_from_building(building: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var bd = building_registry.get(building.building_type)
	if bd == null or bd.spawns_unit == null:
		return events

	var ud = bd.spawns_unit
	var team: int = building.team

	var spawn_x: int = FP.from_int(TEAM_0_SPAWN_X) if team == 0 else FP.from_int(TEAM_1_SPAWN_X)
	var spawn_y_px: int = GRID_ORIGIN_Y + building.grid_y * CELL_SIZE_PX + (building.grid_size_y * CELL_SIZE_PX) / 2
	var spawn_y: int = FP.from_int(spawn_y_px)

	var move_speed_fp: int = FP.div(
		FP.from_int(ud.move_speed * CELL_SIZE_PX),
		FP.from_int(TICKS_PER_SECOND)
	)
	var attack_range_fp: int = FP.from_int(ud.attack_range * CELL_SIZE_PX)
	var aggro_range_fp: int = FP.from_int(ud.aggro_range * CELL_SIZE_PX)

	for i in bd.units_per_wave:
		var unit_id := next_entity_id
		next_entity_id += 1
		var y_offset: int = FP.from_int(i * 6)

		var unit := {
			"id": unit_id,
			"type": "unit",
			"unit_type": ud.id,
			"owner": building.owner,
			"player_index": building.player_index,
			"team": team,
			"hp": FP.from_int(ud.max_hp),
			"max_hp": FP.from_int(ud.max_hp),
			"attack_damage": FP.from_int(ud.attack_damage),
			"base_attack_damage": FP.from_int(ud.attack_damage),
			"attack_speed_ticks": ud.attack_speed_ticks,
			"attack_range": attack_range_fp,
			"aggro_range": aggro_range_fp,
			"move_speed": move_speed_fp,
			"base_move_speed": move_speed_fp,
			"armor": FP.from_int(ud.armor),
			"magic_defense": FP.from_int(ud.magic_defense),
			"attack_type": ud.attack_type,
			"armor_type": ud.armor_type,
			"role": ud.role,
			"bounty": ud.bounty,
			"skill_id": ud.skill_id,
			"skill_param_1": ud.skill_param_1,
			"skill_param_2": ud.skill_param_2,
			"skill_cooldown": 0,
			"skill_stacks": 0,
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
			"player_index": building.player_index,
			"x": unit.x,
			"y": unit.y,
			"role": ud.role,
		})

	return events


# --- Unit Update Loop ---

func _update_units() -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# Pre-pass: clear temp buffs, tick debuffs
	for entity in entities:
		if entity.type != "unit":
			continue
		entity["drums_buffed"] = false
		if entity.get("rend_timer", 0) > 0:
			entity.rend_timer -= 1

	# Pre-pass: apply War Drums aura
	for entity in entities:
		if entity.type != "unit" or FP.lte(entity.hp, FP.ZERO):
			continue
		if entity.get("skill_id", &"") == &"war_drums":
			var aura_range_sq: int = FP.mul(FP.from_int(entity.skill_param_2), FP.from_int(entity.skill_param_2))
			for other in entities:
				if other.type != "unit" or other.team != entity.team or other.id == entity.id:
					continue
				if FP.lte(other.hp, FP.ZERO):
					continue
				if FP.lte(_distance_squared_2d(entity, other), aura_range_sq):
					other["drums_buffed"] = true

	# Main unit loop
	for entity in entities:
		if entity.type != "unit":
			continue
		if FP.lte(entity.hp, FP.ZERO):
			continue

		# Tick skill cooldown
		if entity.get("skill_cooldown", 0) > 0:
			entity.skill_cooldown -= 1

		# Passive threshold skills
		events.append_array(_check_passive_skills(entity))

		# Casters (role=2) heal allies instead of attacking
		if entity.role == 2:
			if entity.attack_cooldown > 0:
				entity.attack_cooldown -= 1
			if entity.attack_cooldown <= 0:
				var healed := _try_heal(entity)
				if healed:
					events.append_array(healed)
					entity.attack_cooldown = entity.attack_speed_ticks
				# Holy Light AoE heal skill
				if entity.get("skill_id", &"") == &"holy_light" and entity.skill_cooldown <= 0:
					events.append_array(_skill_holy_light(entity))
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
				var dist_sq := _distance_squared_x(entity, target)
				var range_sq := FP.mul(entity.attack_range, entity.attack_range)
				if FP.lte(dist_sq, range_sq):
					if entity.attack_cooldown <= 0:
						events.append_array(_perform_attack(entity, target))
						# Drums buff: reduce cooldown by 15%
						var cd: int = entity.attack_speed_ticks
						if entity.get("drums_buffed", false):
							cd = maxi(1, int(cd * 0.85))
						entity.attack_cooldown = cd
						# Active skills that trigger after attack
						events.append_array(_check_attack_skills(entity))
					attacked = true

		if not attacked:
			_move_unit(entity)
			events.append_array(_check_castle_damage(entity))

	return events


func _acquire_target(unit: Dictionary) -> void:
	var aggro_sq: int = FP.mul(unit.aggro_range, unit.aggro_range)

	# Check if current target is still valid and in aggro range
	if unit.target_id != -1:
		var current = _find_entity_by_id(unit.target_id)
		if current != null and FP.gt(current.hp, FP.ZERO) and current.team != unit.team:
			if FP.lte(_distance_squared_2d(unit, current), aggro_sq):
				return  # Keep current target

	# Find nearest living enemy within aggro range (full 2D)
	var best_id: int = -1
	var best_dist_sq: int = 0x7FFFFFFFFFFFFFF

	for other in entities:
		if other.type != "unit":
			continue
		if other.team == unit.team:
			continue
		if FP.lte(other.hp, FP.ZERO):
			continue
		var dist_sq := _distance_squared_2d(unit, other)
		if FP.gt(dist_sq, aggro_sq):
			continue  # Outside aggro range
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = other.id

	unit.target_id = best_id


## Full 2D distance squared (for aggro detection and combat range).
func _distance_squared_2d(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return FP.mul(dx, dx) + FP.mul(dy, dy)


## X-only distance squared (for attack range checks -- units attack across lanes).
func _distance_squared_x(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	return FP.mul(dx, dx)


func _move_unit(unit: Dictionary) -> void:
	# If we have a target, chase it (role-dependent)
	if unit.target_id != -1:
		var target = _find_entity_by_id(unit.target_id)
		if target != null and FP.gt(target.hp, FP.ZERO):
			var dx: int = target.x - unit.x
			var dy: int = target.y - unit.y

			# Check if already in attack range (X-distance for combat)
			var attack_range_sq: int = FP.mul(unit.attack_range, unit.attack_range)
			if FP.lte(_distance_squared_x(unit, target), attack_range_sq):
				return  # In attack range, don't move

			match unit.role:
				0, 3:  # Melee, Flying: full 2D chase
					var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
					var dist: int = FP.sqrt_fp(dist_sq)
					if dist > 0:
						unit.x = FP.add(unit.x, FP.div(FP.mul(dx, unit.move_speed), dist))
						unit.y = FP.add(unit.y, FP.div(FP.mul(dy, unit.move_speed), dist))
						# Clamp Y to arena bounds
						unit.y = FP.clamp_fp(unit.y, FP.from_int(GRID_ORIGIN_Y), FP.from_int(GRID_ORIGIN_Y + GRID_ROWS * CELL_SIZE_PX))
					return
				1, 2:  # Ranged, Caster: X-only chase (stay in lane)
					var sign_x: int = 1 if dx > 0 else -1
					unit.x = FP.add(unit.x, FP.mul(FP.from_int(sign_x), unit.move_speed))
					return
				4:  # Siege: no chasing, march straight
					pass  # Fall through to default march

	# Default: march toward enemy castle
	if unit.team == 0:
		unit.x = FP.add(unit.x, unit.move_speed)
		unit.x = FP.min_fp(unit.x, FP.from_int(CASTLE_1_X))
	else:
		unit.x = FP.sub(unit.x, unit.move_speed)
		unit.x = FP.max_fp(unit.x, FP.from_int(CASTLE_0_X))


func _perform_attack(attacker: Dictionary, target: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var multiplier: int = damage_table[attacker.attack_type][target.armor_type]
	var raw_damage: int = FP.mul(attacker.attack_damage, multiplier)

	# Magic attacks reduced by magic_defense, others by armor
	var defense: int
	if attacker.attack_type == 2:  # Magic
		defense = target.get("magic_defense", FP.ZERO)
	else:
		defense = target.armor

	var final_damage: int = FP.sub(raw_damage, defense)
	final_damage = FP.max_fp(final_damage, FP.ONE)

	# --- On-hit skill: Shield Wall (target) ---
	# Footman: -15% Pierce damage when HP > 50%
	if target.get("skill_id", &"") == &"shield_wall" and attacker.attack_type == 1:
		var hp_threshold: int = FP.div(target.max_hp, FP.TWO)  # 50%
		if FP.gt(target.hp, hp_threshold):
			final_damage = FP.div(FP.mul(final_damage, FP.from_int(target.skill_param_1)), FP.from_int(1000))

	# --- On-hit skill: Rending Throw (attacker) ---
	# Axe Thrower: 25% chance to apply +20% damage taken debuff
	if attacker.get("skill_id", &"") == &"rending_throw":
		if rng.range_int(1, 100) <= attacker.skill_param_1:
			target["rend_timer"] = attacker.skill_param_2
			events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "rending_throw"})

	# --- Rend debuff on target: +20% damage taken ---
	if target.get("rend_timer", 0) > 0:
		final_damage = FP.div(FP.mul(final_damage, FP.from_int(1200)), FP.from_int(1000))

	target.hp = FP.sub(target.hp, final_damage)

	events.append({
		"type": "unit_attacked",
		"attacker_id": attacker.id,
		"target_id": target.id,
		"damage": final_damage,
		"target_hp": target.hp,
	})

	# --- On-kill skill: Blood Frenzy (attacker) ---
	# Berserker: +10% base damage per kill, max 5 stacks
	if FP.lte(target.hp, FP.ZERO) and attacker.get("skill_id", &"") == &"blood_frenzy":
		if attacker.skill_stacks < attacker.skill_param_2:
			attacker.skill_stacks += 1
			var bonus: int = FP.div(attacker.base_attack_damage, FP.from_int(10))
			attacker.attack_damage = FP.add(attacker.attack_damage, bonus)
			events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "blood_frenzy", "stacks": attacker.skill_stacks})

	# --- On-hit skill: Boulder Splash (attacker) ---
	# Catapult: 40% splash to enemies within param_2 pixels of target
	if attacker.get("skill_id", &"") == &"boulder_splash":
		var splash_range_sq: int = FP.mul(FP.from_int(attacker.skill_param_2), FP.from_int(attacker.skill_param_2))
		var splash_dmg: int = FP.div(FP.mul(final_damage, FP.from_int(attacker.skill_param_1)), FP.from_int(1000))
		splash_dmg = FP.max_fp(splash_dmg, FP.ONE)
		for other in entities:
			if other.type != "unit" or other.team == attacker.team or other.id == target.id:
				continue
			if FP.lte(other.hp, FP.ZERO):
				continue
			if FP.lte(_distance_squared_2d(target, other), splash_range_sq):
				other.hp = FP.sub(other.hp, splash_dmg)
				events.append({"type": "unit_attacked", "attacker_id": attacker.id, "target_id": other.id, "damage": splash_dmg, "target_hp": other.hp})

	return events


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
		var dist_sq := _distance_squared_2d(healer, other)
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


# --- Skill Helpers ---

## Passive skills that trigger on thresholds (checked every tick).
func _check_passive_skills(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sid: StringName = unit.get("skill_id", &"")

	# Toughness (Grunt): +3 armor when HP < 30%, one-time
	if sid == &"toughness" and unit.skill_stacks == 0:
		var threshold: int = FP.div(FP.mul(unit.max_hp, FP.from_int(unit.skill_param_1)), FP.from_int(1000))
		if FP.lt(unit.hp, threshold):
			unit.armor = FP.add(unit.armor, FP.from_int(unit.skill_param_2))
			unit.magic_defense = FP.add(unit.get("magic_defense", FP.ZERO), FP.ONE)
			unit.skill_stacks = 1
			events.append({"type": "skill_proc", "unit_id": unit.id, "skill": "toughness"})

	# Charge (Knight): double speed on first target acquisition, one-time
	if sid == &"charge" and unit.get("charge_available", true) and unit.target_id != -1:
		unit["charge_available"] = false
		unit.move_speed = FP.mul(unit.move_speed, FP.TWO)
		unit["charge_timer"] = unit.skill_param_2  # 15 ticks
		unit["charge_damage_ready"] = true
		events.append({"type": "skill_proc", "unit_id": unit.id, "skill": "charge"})

	# Charge timer countdown
	if unit.get("charge_timer", 0) > 0:
		unit.charge_timer -= 1
		if unit.charge_timer <= 0:
			unit.move_speed = unit.base_move_speed

	return events


## Active skills that trigger after a normal attack.
func _check_attack_skills(entity: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sid: StringName = entity.get("skill_id", &"")

	# Volley (Archer): every 50 ticks, fire 3 arrows at 60% damage
	if sid == &"volley" and entity.skill_cooldown <= 0:
		entity.skill_cooldown = entity.skill_param_2  # 50 ticks
		var volley_dmg: int = FP.div(FP.mul(entity.attack_damage, FP.from_int(entity.skill_param_1)), FP.from_int(1000))
		volley_dmg = FP.max_fp(volley_dmg, FP.ONE)
		var targets_hit: int = 0
		var range_sq: int = FP.mul(entity.attack_range, entity.attack_range)
		for other in entities:
			if targets_hit >= 3:
				break
			if other.type != "unit" or other.team == entity.team:
				continue
			if FP.lte(other.hp, FP.ZERO):
				continue
			if FP.lte(_distance_squared_x(entity, other), range_sq):
				other.hp = FP.sub(other.hp, volley_dmg)
				events.append({"type": "unit_attacked", "attacker_id": entity.id, "target_id": other.id, "damage": volley_dmg, "target_hp": other.hp})
				targets_hit += 1
		if targets_hit > 0:
			events.append({"type": "skill_proc", "unit_id": entity.id, "skill": "volley"})

	# Charge first-hit bonus (Knight): 200% damage on first attack
	if entity.get("charge_damage_ready", false):
		entity.charge_damage_ready = false
		# The attack already happened in _perform_attack, so apply bonus damage to last target
		if entity.target_id != -1:
			var target = _find_entity_by_id(entity.target_id)
			if target and FP.gt(target.hp, FP.ZERO):
				var bonus: int = entity.attack_damage  # +100% = double total
				target.hp = FP.sub(target.hp, bonus)
				events.append({"type": "unit_attacked", "attacker_id": entity.id, "target_id": target.id, "damage": bonus, "target_hp": target.hp})
				events.append({"type": "skill_proc", "unit_id": entity.id, "skill": "charge_hit"})

	return events


## Holy Light (Priest): AoE heal allies within 2 cells.
func _skill_holy_light(healer: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	healer.skill_cooldown = healer.skill_param_2  # 30 ticks
	var heal_amount: int = FP.div(healer.attack_damage, FP.TWO)  # 50% of heal power
	var range_px: int = FP.from_int(2 * CELL_SIZE_PX)
	var range_sq: int = FP.mul(range_px, range_px)
	var healed_count: int = 0

	for other in entities:
		if other.type != "unit" or other.team != healer.team or other.id == healer.id:
			continue
		if FP.lte(other.hp, FP.ZERO) or FP.gte(other.hp, other.max_hp):
			continue
		if FP.lte(_distance_squared_2d(healer, other), range_sq):
			other.hp = FP.min_fp(FP.add(other.hp, heal_amount), other.max_hp)
			healed_count += 1

	if healed_count > 0:
		events.append({"type": "skill_proc", "unit_id": healer.id, "skill": "holy_light", "count": healed_count})
	return events


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
			var multiplier: int = damage_table[unit.attack_type][3]  # Fortified
			var raw_damage: int = FP.mul(unit.attack_damage, multiplier)
			var final_damage: int = FP.max_fp(raw_damage, FP.ONE)

			# Siege Fire (Demolisher): +25% castle damage + burn
			if unit.get("skill_id", &"") == &"siege_fire":
				final_damage = FP.div(FP.mul(final_damage, FP.from_int(unit.skill_param_1)), FP.from_int(1000))
				castle["burn_timer"] = unit.skill_param_2
				castle["burn_damage"] = FP.from_int(5)

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
