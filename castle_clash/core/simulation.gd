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

# T-077 Early game pacing: prep phase + starting gold
var prep_phase: bool = true
var prep_ticks_remaining: int = 0

# Match stats per team [team_0, team_1]
var units_spawned: Array[int] = [0, 0]
var units_killed: Array[int] = [0, 0]  # Enemies killed by this team
var total_damage: Array[int] = [0, 0]

# Grid state -- one 2D array per player
var grid_cells: Array = []

# Flow field pathfinding -- one flat array per player grid (110 ints)
# Each cell stores direction (0-7) toward castle, -2 = goal, -1 = blocked/unreachable
var flow_fields: Array = []

# Combat zone grid: static obstacles (trees) that units path around
# 11 cols × 13 rows covering Y=345-709 (combat zone)
const COMBAT_ROWS: int = 13
const COMBAT_Y: int = 345  # Top of combat zone
var combat_grid: Array = []  # 2D array [row][col], -1=open, 1=tree
var combat_flow_fields: Array = []  # [team_0_field, team_1_field] — flat arrays of 11*13

# Burning Ground fire zones: [{x, y, radius_sq, damage, ticks_remaining, team}]
var fire_zones: Array[Dictionary] = []

# Unit occupancy grid: covers full arena Y=55..Y=985 at 28px/cell (34 rows × 11 cols = 374 cells)
# Each cell stores an Array of unit entity IDs. Capacity = 2 same-team units per cell.
var unit_grid: Array = []  # flat array of 374 Arrays (each Array[int])
const UNIT_GRID_ROWS: int = 34
const UNIT_GRID_Y_OFFSET: int = 55
const CELL_CAPACITY: int = 2

# 8-direction vectors: 0=up, 1=up-right, 2=right, 3=down-right, 4=down, 5=down-left, 6=left, 7=up-left
const DIR_DX: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const DIR_DY: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]
const STUCK_THRESHOLD: int = 15  # 1.5 seconds at 10 tps (was 3s, too slow)

# Unit state machine constants
const UNIT_STATE_MARCH: int = 0   # No target, following flow field toward castle
const UNIT_STATE_CHASE: int = 1   # Has target, moving toward it
const UNIT_STATE_ATTACK: int = 2  # In range, attacking on cooldown

# Building data registry -- maps StringName -> BuildingData
var building_registry: Dictionary = {}

# Damage table -- [attack_type][armor_type] = FP multiplier
var damage_table: Array = []

# Timing constants
const WAVE_INTERVAL_TICKS: int = 250  # 25 seconds at 10 ticks/sec
const INCOME_INTERVAL_TICKS: int = 50 # 5 seconds
const TICKS_PER_SECOND: int = 10
# T-077 Early game pacing
const PREP_PHASE_TICKS: int = 150  # 15 seconds — players settle in, build, no marching
const STARTING_GOLD: int = 100     # Enough for one barracks (50g) + leftover

# Grid constants (portrait 720x1280)
const GRID_COLS: int = 11
const GRID_ROWS: int = 10
const CELL_SIZE_PX: int = 28
const GRID_ORIGIN_X: int = 206   # (720 - 11*28) / 2
const CASTLE_CELL_MARKER: int = -2  # Grid cell marker for castle obstacle (not a building)
const TERRAIN_OBSTACLE_MARKER: int = -3  # T-074: non-entity static obstacle (tree/rock) in grid_cells or combat_grid

# Arena pixel-space constants (portrait vertical march)
# Player (team 0) builds at bottom, marches UP (decreasing Y)
# Enemy (team 1) builds at top, marches DOWN (increasing Y)
# T-096: team Y geometry is mirror-symmetric around FLIP_PIVOT_Y=520 (the T-085
# perspective-flip midpoint). Castle centers and zone tops satisfy
# value_team_0 + value_team_1 = 1040.
const TEAM_0_SPAWN_Y: int = 695   # Top edge of player build zone
const TEAM_1_ZONE_Y: int = 65     # Top edge of enemy build zone (symmetric mirror of team 0)
const TEAM_1_SPAWN_Y: int = 345   # Bottom edge of enemy build zone (65 + 10 * 28)
const CASTLE_0_Y: int = 920       # Player castle center (symmetric: 2*520 - CASTLE_1_Y)
const CASTLE_1_Y: int = 120       # Enemy castle center (T-096: was 70; now 2*520 - CASTLE_0_Y)
const CASTLE_FOOTPRINT_W: int = 5 # 5 cells wide (was full 9 between cols 1-9)
const CASTLE_FOOTPRINT_H: int = 2 # 2 cells tall (was 3 rows with ±1 from center)
const ARENA_LEFT: int = 60
const ARENA_RIGHT: int = 660


## Register all available building types. Call before initialize().
func register_buildings(building_list: Array) -> void:
	for bd in building_list:
		building_registry[bd.id] = bd


## Game mode modifiers (set by GameManager before match)
var mode_income_mult: int = 100    # Percentage: 100 = normal, 200 = 2x
var mode_spawn_mult: int = 100     # Percentage: 100 = normal, 50 = 2x speed

func initialize(seed_value: int, player_data: Array, mode_config: Dictionary = {}) -> void:
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
	mode_income_mult = mode_config.get("income_mult", 100)
	mode_spawn_mult = mode_config.get("spawn_mult", 100)
	# T-077: prep phase (mode_config can disable for tests/special modes)
	if mode_config.get("skip_prep", false):
		prep_phase = false
		prep_ticks_remaining = 0
	else:
		prep_phase = true
		prep_ticks_remaining = PREP_PHASE_TICKS

	players.clear()
	for p in player_data:
		var perk: StringName = p.get("perk", &"")
		# War Economy perk: +25% income
		var base_income: int = 20
		if perk == &"war_economy":
			base_income = 25
		# Pillage perk: income buildings cost +40% (handled in placement)
		# Savage Rush perk: -15% income
		if perk == &"savage_rush":
			base_income = 17
		players.append({
			"id": p.id,
			"team": p.team,
			"faction": p.faction,
			"perk": perk,
			# T-077: starting gold = 100 (enough for one barracks + leftover).
			# player_data start_gold key is now ignored — sim is authoritative.
			"gold": FP.from_int(STARTING_GOLD),
			"income": FP.from_int(base_income),
		})

	# T-089: castle HP 10000 → 5000 so a dominant army resolves the match in 1-2 minutes
	# after reaching the castle instead of the previous 3+ minute grind.
	# T-090: castle_wrath_available tracks whether the one-time panic button is still
	# usable. Becomes ready when castle HP < 30%; consumed on first USE_ABILITY.
	castles = [
		{ "team": 0, "hp": FP.from_int(5000), "max_hp": FP.from_int(5000), "castle_wrath_available": true, "castle_wrath_ready_emitted": false },
		{ "team": 1, "hp": FP.from_int(5000), "max_hp": FP.from_int(5000), "castle_wrath_available": true, "castle_wrath_ready_emitted": false },
	]

	# Add castles as targetable entities so units can chase and attack them
	for castle in castles:
		var castle_id := next_entity_id
		next_entity_id += 1
		# Castle center X = arena center, Y = castle position
		var castle_x: int = FP.from_int((ARENA_LEFT + ARENA_RIGHT) / 2)
		var castle_y: int = FP.from_int(CASTLE_0_Y if castle.team == 0 else CASTLE_1_Y)
		var castle_entity := {
			"id": castle_id,
			"type": "castle",
			"team": castle.team,
			"x": castle_x,
			"y": castle_y,
			"hp": castle.hp,
			"max_hp": castle.max_hp,
			"armor": FP.ZERO,
			"armor_type": 3,  # Fortified
			# T-096: grid_size lets _in_attack_range + _check_castle_damage use the same
			# building-style edge-distance formula. Hitbox extends ±hw/±hh from (x, y).
			"grid_size_x": CASTLE_FOOTPRINT_W,
			"grid_size_y": CASTLE_FOOTPRINT_H,
		}
		entities.append(castle_entity)
		castle["entity_id"] = castle_id

	# Initialize unit occupancy grid (covers full arena)
	_init_unit_grid()
	# T-096: Castle occupies its 5×2 build-zone footprint only — flanking cells
	# (cols 0-2, 8-10 on castle rows) are walkable. Attackers can approach from
	# the side unless the defender places blocking buildings there.
	# Convert build-zone footprint cells → unit_grid cells (they may span 2-3
	# unit_grid rows per build-zone row due to zone offsets).
	for castle in castles:
		var fp: Array = _castle_grid_footprint(castle.team)
		var zone_y: int = TEAM_0_SPAWN_Y if castle.team == 0 else TEAM_1_ZONE_Y
		var py_top: int = zone_y + fp[0] * CELL_SIZE_PX
		var py_bot: int = zone_y + (fp[1] + 1) * CELL_SIZE_PX
		var u_row_top: int = (py_top - UNIT_GRID_Y_OFFSET) / CELL_SIZE_PX
		var u_row_bot: int = (py_bot - UNIT_GRID_Y_OFFSET) / CELL_SIZE_PX
		for u_row in range(u_row_top, u_row_bot + 1):
			if u_row < 0 or u_row >= UNIT_GRID_ROWS:
				continue
			for u_col in range(fp[2], fp[3] + 1):
				unit_grid[u_row * GRID_COLS + u_col] = [CASTLE_CELL_MARKER]

	# Initialize grids and flow fields
	grid_cells.clear()
	flow_fields.clear()
	fire_zones.clear()
	for i in players.size():
		var player_grid: Array = []
		for row in GRID_ROWS:
			var grid_row: Array = []
			grid_row.resize(GRID_COLS)
			grid_row.fill(-1)
			player_grid.append(grid_row)
		grid_cells.append(player_grid)
		# Flow field: all open initially
		var field: Array = []
		field.resize(GRID_COLS * GRID_ROWS)
		field.fill(-1)
		flow_fields.append(field)
	# Mark castle cells as grid obstacles so flow field routes around them
	for i in players.size():
		var team: int = players[i].team
		var fp: Array = _castle_grid_footprint(team)
		for row in range(fp[0], fp[1] + 1):
			for col in range(fp[2], fp[3] + 1):
				grid_cells[i][row][col] = CASTLE_CELL_MARKER
	# Build initial flow fields (castle cells now marked as obstacles)
	for i in players.size():
		_rebuild_flow_field(i)

	# Initialize combat zone grid with tree obstacles (symmetric layout)
	combat_grid.clear()
	for row in COMBAT_ROWS:
		var grid_row: Array = []
		grid_row.resize(GRID_COLS)
		grid_row.fill(-1)
		combat_grid.append(grid_row)
	# Place trees: horizontal tree wall at rows 6-7 with 3 gaps (lane system)
	# Row 3/9: minor clusters for variety
	# Row 6-7: main tree wall — gaps at cols 0 (left edge), 4-5 (center), 10 (right edge)
	# No trees on this map — open combat zone
	var tree_positions := []
	# Build combat zone flow fields (one per team march direction)
	combat_flow_fields.clear()
	for team in 2:
		var field: Array = []
		field.resize(GRID_COLS * COMBAT_ROWS)
		field.fill(-1)
		combat_flow_fields.append(field)
	_rebuild_combat_flow_fields()

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

	# T-077: prep phase countdown — fires once when prep ends
	if prep_phase:
		prep_ticks_remaining -= 1
		if prep_ticks_remaining <= 0:
			prep_phase = false
			# Reset all spawn timers so combat begins with a fresh, predictable cycle
			for entity in entities:
				if entity.type == "building":
					var pi_interval: int = entity.get("spawn_interval", 0)
					if pi_interval > 0:
						entity.spawn_timer = pi_interval
			events.append({"type": "prep_phase_ended"})

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

	# 2.5. Tower attacks
	events.append_array(_update_towers())

	# 2.6. Special building mana tick + ability buff application
	for entity in entities:
		if entity.type != "building":
			continue
		var max_mana: int = entity.get("ability_max_mana", 0)
		if max_mana <= 0:
			continue
		# Tick mana if not active
		if entity.get("ability_active_ticks", 0) <= 0:
			if entity.ability_mana < max_mana:
				entity.ability_mana += 1
		else:
			# Tick active buff duration
			entity.ability_active_ticks -= 1

	# 3. Update all units
	events.append_array(_update_units())

	# 4. Remove dead entities
	events.append_array(_cleanup_dead())

	# 4.5. Castle burn damage (from Siege Fire) + sync castle entity HP
	for castle in castles:
		if castle.get("burn_timer", 0) > 0:
			castle.burn_timer -= 1
			var burn_dmg: int = castle.get("burn_damage", FP.ZERO)
			castle.hp = FP.sub(castle.hp, burn_dmg)
			events.append({"type": "castle_damaged", "team": castle.team, "damage": burn_dmg, "remaining_hp": castle.hp, "attacker_id": -1})
		# Sync castle entity HP with castle dict
		var castle_eid: int = castle.get("entity_id", -1)
		if castle_eid != -1:
			var ce = _find_entity_by_id(castle_eid)
			if ce:
				ce.hp = castle.hp
		# T-090: emit castle_wrath_ready once when HP crosses the 30% threshold.
		if castle.get("castle_wrath_available", false) and not castle.get("castle_wrath_ready_emitted", false):
			var wrath_threshold: int = FP.div(FP.mul(castle.max_hp, FP.from_int(CASTLE_WRATH_HP_THRESHOLD_PCT)), FP.from_int(100))
			if FP.lt(castle.hp, wrath_threshold):
				castle["castle_wrath_ready_emitted"] = true
				events.append({"type": "castle_wrath_ready", "team": castle.team, "castle_id": castle_eid})

	# 5. Check win condition (only first castle to fall wins)
	if not match_over:
		for castle in castles:
			if FP.lte(castle.hp, FP.ZERO):
				match_over = true
				winning_team = 1 - castle.team
				events.append({ "type": "match_over", "winner": winning_team })
				break

	# 6. Income tick (immediate first tick at tick 1 so players start with gold)
	if tick % INCOME_INTERVAL_TICKS == 0 or tick == 1:
		# Count income buildings per player for compound bonus
		var income_pct_bonus: Array[int] = []
		for _p in players:
			income_pct_bonus.append(0)
		for entity in entities:
			if entity.type == "building" and FP.gt(entity.hp, FP.ZERO):
				var bd = building_registry.get(entity.building_type)
				if bd and bd.income_bonus > 0:
					income_pct_bonus[entity.player_index] += bd.income_bonus
		for pi in players.size():
			var player: Dictionary = players[pi]
			# Compound income: base_income * (100 + total_pct_bonus) / 100, then apply mode multiplier
			var actual_income: int = FP.div(FP.mul(player.income, FP.from_int(100 + income_pct_bonus[pi])), FP.from_int(100))
			actual_income = FP.div(FP.mul(actual_income, FP.from_int(mode_income_mult)), FP.from_int(100))
			player.gold = FP.add(player.gold, actual_income)
			events.append({
				"type": "income",
				"player_id": player.id,
				"amount": actual_income,
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

	# Castle cells are marked as CASTLE_CELL_MARKER in grid_cells, so the
	# occupancy check above (grid[row][col] != -1) already rejects castle overlap.
	# Explicit overlap check kept as defense in depth.
	var team: int = players[player_index].team
	var cfp: Array = _castle_grid_footprint(team)
	var bld_row_max: int = grid_y + size_y - 1
	var bld_col_max: int = grid_x + size_x - 1
	if grid_x <= cfp[3] and bld_col_max >= cfp[2]:
		if grid_y <= cfp[1] and bld_row_max >= cfp[0]:
			return false

	# Anti-block: reject if placement would seal all paths to castle
	if _would_block_path(player_index, grid_x, grid_y, bd.grid_size.x, bd.grid_size.y):
		return false

	return true


# --- Determinism checksum (see tasks/design-verification-workflow.md) ---
# Order-sensitive FNV-1a-style rolling hash over ALL mutable sim state. Replaces
# the old order-insensitive XOR, which cancelled on swapped values and omitted
# gold, unit state, targets and cooldowns — the silent-desync class Factorio
# documented in FFF-340 ("state outside the checksum").
const _FNV_OFFSET: int = -3750763034362895579   # 14695981039346656037 as signed 64-bit
const _FNV_PRIME: int = 1099511628211


# GDScript int is 64-bit two's-complement; overflow wraps deterministically.
func _mix(h: int, v: int) -> int:
	return (h ^ v) * _FNV_PRIME


func _mix_val(h: int, value) -> int:
	match typeof(value):
		TYPE_INT:
			return _mix(h, value)
		TYPE_BOOL:
			return _mix(h, 1 if value else 0)
		TYPE_STRING, TYPE_STRING_NAME:
			return _mix(h, hash(value))
		TYPE_VECTOR2I:
			return _mix(_mix(h, value.x), value.y)
		TYPE_FLOAT:
			# Sim state must be fixed-point; a float here is itself a determinism
			# bug. Hash it anyway so the checksum notices rather than skipping.
			return _mix(h, hash(value))
		_:
			return _mix(h, hash(value))


# Insertion-order walk. Both lockstep peers construct dicts with identical code,
# so key order is identical; the rolling hash is order-sensitive by design.
func _mix_dict(h: int, d: Dictionary) -> int:
	for key in d:
		h = _mix(h, hash(key))
		h = _mix_val(h, d[key])
	return h


func compute_checksum() -> int:
	var h: int = _FNV_OFFSET
	for v in [tick, next_entity_id, wave_number, wave_timer, prep_ticks_remaining,
			winning_team, (1 if prep_phase else 0), (1 if match_over else 0)]:
		h = _mix(h, v)
	for arr in [units_spawned, units_killed, total_damage]:
		for v in arr:
			h = _mix(h, v)
	for p in players:
		h = _mix_val(h, p.get("gold", 0))
		h = _mix_val(h, p.get("income", 0))
	for c in castles:
		h = _mix_dict(h, c)
	for e in entities:
		h = _mix_dict(h, e)
	for fz in fire_zones:
		h = _mix_dict(h, fz)
	for s in rng.get_state():
		h = _mix(h, s)
	for pi in grid_cells.size():
		for row in grid_cells[pi]:
			for cell in row:
				h = _mix(h, cell)
	return h


## Per-subsystem checksums so a desync report names WHICH system diverged
## (Riot's hierarchical-state pattern), instead of only THAT one did.
func compute_subchecksums() -> Dictionary:
	var units_h: int = _FNV_OFFSET
	var buildings_h: int = _FNV_OFFSET
	for e in entities:
		match e.get("type", ""):
			"unit":
				units_h = _mix_dict(units_h, e)
			"building":
				buildings_h = _mix_dict(buildings_h, e)
	var economy_h: int = _FNV_OFFSET
	for p in players:
		economy_h = _mix_val(economy_h, p.get("gold", 0))
		economy_h = _mix_val(economy_h, p.get("income", 0))
	var castles_h: int = _FNV_OFFSET
	for c in castles:
		castles_h = _mix_dict(castles_h, c)
	var rng_h: int = _FNV_OFFSET
	for s in rng.get_state():
		rng_h = _mix(rng_h, s)
	var grid_h: int = _FNV_OFFSET
	for pi in grid_cells.size():
		for row in grid_cells[pi]:
			for cell in row:
				grid_h = _mix(grid_h, cell)
	return {
		"tick": tick,
		"entity_count": entities.size(),
		"units": units_h,
		"buildings": buildings_h,
		"economy": economy_h,
		"castles": castles_h,
		"rng": rng_h,
		"grid": grid_h,
	}


## Full ordered state dump (raw fixed-point ints, sorted keys) so two peers'
## state at the first divergent tick can be line-diffed (Factorio desync-report
## pattern). Written to disk on first checksum mismatch.
func dump_state_json() -> String:
	var state := {
		"tick": tick,
		"next_entity_id": next_entity_id,
		"wave_number": wave_number,
		"wave_timer": wave_timer,
		"prep_phase": prep_phase,
		"prep_ticks_remaining": prep_ticks_remaining,
		"match_over": match_over,
		"winning_team": winning_team,
		"units_spawned": units_spawned,
		"units_killed": units_killed,
		"total_damage": total_damage,
		"rng_state": rng.get_state(),
		"players": players,
		"castles": castles,
		"entities": entities,
		"fire_zones": fire_zones,
	}
	return JSON.stringify(state, "  ")


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
		Command.Type.ACTIVATE_BUILDING:
			events.append_array(_handle_activate_building(cmd))
		Command.Type.USE_ABILITY:
			events.append_array(_handle_use_ability(cmd))
	return events


# BUG-33: USE_ABILITY commands were silently dropped. Route to per-ability handlers.
# T-090 adds castle_wrath as the first real ability.
func _handle_use_ability(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ability_id: StringName = cmd.get("ability_id", &"")
	match ability_id:
		&"castle_wrath":
			events.append_array(_handle_castle_wrath(cmd))
		_:
			push_warning("Unknown USE_ABILITY id: %s" % str(ability_id))
	return events


# T-090: Castle Wrath — one-time AoE when castle HP drops below 30%. 200 Magic damage to
# all enemies within 5 cells (140px) of the activating team's castle.
const CASTLE_WRATH_RANGE_PX: int = 140  # 5 cells × 28px
const CASTLE_WRATH_DAMAGE: int = 200
const CASTLE_WRATH_HP_THRESHOLD_PCT: int = 30  # triggers availability when HP < 30%

func _handle_castle_wrath(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player_index := get_player_index(cmd.player_id)
	if player_index == -1:
		return events
	var team: int = players[player_index].team
	var castle: Dictionary = castles[team]
	if not castle.get("castle_wrath_available", false):
		events.append({"type": "castle_wrath_refused", "team": team, "reason": "already_used"})
		return events  # already used or never became available
	# Require HP < 30% at activation time (prevents pre-emptive use).
	var hp_threshold: int = FP.div(FP.mul(castle.max_hp, FP.from_int(CASTLE_WRATH_HP_THRESHOLD_PCT)), FP.from_int(100))
	if FP.gte(castle.hp, hp_threshold):
		events.append({"type": "castle_wrath_refused", "team": team, "reason": "hp_above_threshold"})
		return events

	var castle_entity = _find_entity_by_id(castle.entity_id)
	if castle_entity == null:
		events.append({"type": "castle_wrath_refused", "team": team, "reason": "castle_missing"})
		return events
	# Consume only after every guard passed — a refused cast must not burn the charge.
	castle["castle_wrath_available"] = false

	var range_sq: int = FP.mul(FP.from_int(CASTLE_WRATH_RANGE_PX), FP.from_int(CASTLE_WRATH_RANGE_PX))
	var wrath_dmg: int = FP.from_int(CASTLE_WRATH_DAMAGE)
	# Measure to the castle EDGE with the exact formula _in_attack_range uses, so any
	# unit close enough to attack the castle is inside the blast. The castle hitbox is
	# grid_size_x=5 × grid_size_y=2 cells (hw=70px, hh=28px): a catapult legally sieges
	# at 140px from the EDGE (168-210px from center), which the old center-to-center
	# check missed entirely.
	var hw: int = FP.from_int(castle_entity.get("grid_size_x", 2) * CELL_SIZE_PX / 2)
	var hh: int = FP.from_int(castle_entity.get("grid_size_y", 2) * CELL_SIZE_PX / 2)
	var hit_ids: Array = []
	for other in entities:
		if other.type != "unit" or other.team == team:
			continue
		if FP.lte(other.hp, FP.ZERO):
			continue
		var dx: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(other.x, castle_entity.x)), hw), FP.ZERO)
		var dy: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(other.y, castle_entity.y)), hh), FP.ZERO)
		var edge_dist_sq: int = FP.add(FP.mul(dx, dx), FP.mul(dy, dy))
		if FP.gt(edge_dist_sq, range_sq):
			continue
		# Magic damage with per-target magic_defense reduction (WC3 formula).
		var md: int = other.get("magic_defense", FP.ZERO)
		var final: int = FP.div(wrath_dmg, FP.add(FP.ONE, FP.div(FP.mul(md, FP.from_int(6)), FP.from_int(100))))
		final = FP.max_fp(final, FP.ONE)
		other.hp = FP.sub(other.hp, final)
		hit_ids.append(other.id)
		events.append({"type": "unit_attacked", "attacker_id": castle.entity_id, "target_id": other.id, "damage": final, "target_hp": other.hp, "target_x": other.x, "target_y": other.y})

	events.append({
		"type": "castle_wrath_activated",
		"team": team,
		"castle_id": castle.entity_id,
		"target_ids": hit_ids,
		"center_x": castle_entity.x,
		"center_y": castle_entity.y,
		"range_px": CASTLE_WRATH_RANGE_PX,
	})
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
	# Perk cost modifiers
	var player_perk: StringName = player.get("perk", &"")
	if player_perk == &"war_economy":
		# First building costs +50%
		var has_any_building: bool = false
		for e in entities:
			if e.type == "building" and e.player_index == player_index:
				has_any_building = true
				break
		if not has_any_building:
			cost_fp = FP.add(cost_fp, FP.div(cost_fp, FP.TWO))
	if player_perk == &"pillage" and bd.income_bonus > 0:
		# Income buildings cost +40%
		cost_fp = FP.add(cost_fp, FP.div(FP.mul(cost_fp, FP.from_int(40)), FP.from_int(100)))
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

	if _would_block_path(player_index, gx, gy, size_x, size_y):
		return events

	var entity_id := next_entity_id
	next_entity_id += 1

	# Compute building center pixel position for targeting
	var zone_y: int = TEAM_0_SPAWN_Y if player.team == 0 else TEAM_1_ZONE_Y
	var bld_center_x: int = GRID_ORIGIN_X + gx * CELL_SIZE_PX + (size_x * CELL_SIZE_PX) / 2
	var bld_center_y: int = zone_y + gy * CELL_SIZE_PX + (size_y * CELL_SIZE_PX) / 2

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
		"x": FP.from_int(bld_center_x),
		"y": FP.from_int(bld_center_y),
		# T-079: HP from data (or formula fallback), armor from data
		"hp": FP.from_int(bd.max_hp if bd.max_hp > 0 else maxi(300, bd.gold_cost * 5)),
		"max_hp": FP.from_int(bd.max_hp if bd.max_hp > 0 else maxi(300, bd.gold_cost * 5)),
		"armor": FP.from_int(bd.armor),
		"armor_type": 3,  # Fortified
		"spawn_timer": maxi(1, bd.spawn_interval_ticks * mode_spawn_mult / 100) if bd.spawns_unit else 0,
		"spawn_interval": maxi(1, bd.spawn_interval_ticks * mode_spawn_mult / 100) if bd.spawns_unit else 0,
		"is_tower": bd.is_tower,
		"tower_damage": FP.from_int(bd.tower_damage) if bd.is_tower else 0,
		"tower_range": FP.from_int(bd.tower_range * CELL_SIZE_PX) if bd.is_tower else 0,
		"tower_attack_speed": bd.tower_attack_speed if bd.is_tower else 0,
		"tower_attack_type": bd.tower_attack_type if bd.is_tower else 0,
		"tower_cooldown": 0,
		# Special building ability (War Horn / Blood Totem)
		"ability_mana": 0,
		"ability_max_mana": 600 if (bd.id == &"war_horn" or bd.id == &"blood_totem") else 0,
		"ability_active_ticks": 0,
	}
	entities.append(entity)

	for row in range(gy, gy + size_y):
		for col in range(gx, gx + size_x):
			grid[row][col] = entity_id

	player.gold = FP.sub(player.gold, cost_fp)

	# Income is now computed dynamically from mine count (compound %)
	# No flat income modification needed

	# Rebuild flow field for this player's grid
	_rebuild_flow_field(player_index)

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

	# Income is computed dynamically from mine count — no flat tracking to remove

	var grid: Array = grid_cells[player_index]
	for row in range(entity.grid_y, entity.grid_y + entity.grid_size_y):
		for col in range(entity.grid_x, entity.grid_x + entity.grid_size_x):
			grid[row][col] = -1

	entities.remove_at(building_idx)
	_rebuild_flow_field(player_index)

	events.append({ "type": "building_destroyed", "entity_id": entity.id, "reason": "sold" })
	events.append({
		"type": "gold_changed",
		"player_id": cmd.player_id,
		"new_gold": players[player_index].gold,
	})
	return events


# --- Wave Spawning ---

## Per-building spawn timer update. Each building has its own cooldown.
## Tower buildings attack nearest enemy unit in range.
func _update_towers() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for entity in entities:
		if entity.type != "building" or not entity.get("is_tower", false):
			continue

		if entity.get("tower_cooldown", 0) > 0:
			entity.tower_cooldown -= 1
			continue

		# Tower pixel position in portrait (centered in grid footprint)
		var tower_x: int = FP.from_int(GRID_ORIGIN_X + entity.grid_x * CELL_SIZE_PX + (entity.grid_size_x * CELL_SIZE_PX) / 2)
		var zone_y: int = TEAM_0_SPAWN_Y if entity.team == 0 else TEAM_1_ZONE_Y  # Player zone top, enemy zone top
		var tower_y: int = FP.from_int(zone_y + entity.grid_y * CELL_SIZE_PX + (entity.grid_size_y * CELL_SIZE_PX) / 2)

		# Find nearest enemy unit in range
		var range_sq: int = FP.mul(entity.tower_range, entity.tower_range)
		var best_id: int = -1
		var best_dist: int = 0x7FFFFFFFFFFFFFF
		var best_target = null

		for other in entities:
			if other.type != "unit" or other.team == entity.team:
				continue
			if FP.lte(other.hp, FP.ZERO):
				continue
			var dx: int = tower_x - other.x
			var dy: int = tower_y - other.y
			var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
			if FP.lte(dist_sq, range_sq) and dist_sq < best_dist:
				best_dist = dist_sq
				best_id = other.id
				best_target = other

		if best_target != null:
			# Apply damage (WC3-style armor reduction, same formula as unit attacks)
			var multiplier: int = damage_table[entity.tower_attack_type][best_target.armor_type]
			var raw_dmg: int = FP.mul(entity.tower_damage, multiplier)
			var defense: int
			if entity.tower_attack_type == 2:
				defense = best_target.get("magic_defense", FP.ZERO)
			else:
				defense = best_target.armor
			var final_dmg: int
			if defense > 0:
				var armor_bonus: int = FP.div(FP.mul(defense, FP.from_int(6)), FP.from_int(100))
				var armor_factor: int = FP.add(FP.ONE, armor_bonus)
				final_dmg = FP.div(raw_dmg, armor_factor)
			else:
				final_dmg = raw_dmg
			final_dmg = FP.max_fp(final_dmg, FP.ONE)
			best_target.hp = FP.sub(best_target.hp, final_dmg)
			entity.tower_cooldown = entity.tower_attack_speed

			events.append({
				"type": "unit_attacked",
				"attacker_id": entity.id,
				"target_id": best_id,
				"damage": final_dmg,
				"target_hp": best_target.hp,
				"target_x": best_target.x,
				"target_y": best_target.y,
			})

	return events


# --- Terrain Obstacles (T-074) ---
# Static tile occupants (trees, rocks). Block movement, pathfinding, and collision
# like buildings, but are NOT entities — no HP, no team, no ID, not targetable.
# Flying units (role == 3) pass through terrain obstacles but still collide with
# buildings and the castle wall.

## Place a terrain obstacle in a player's build zone at grid (gx, gy).
## Returns true on success, false if the cell is occupied or out of bounds.
## Rebuilds the affected flow field.
func place_terrain_obstacle_build(player_index: int, gx: int, gy: int) -> bool:
	if player_index < 0 or player_index >= grid_cells.size():
		return false
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= GRID_ROWS:
		return false
	var grid: Array = grid_cells[player_index]
	if grid[gy][gx] != -1:
		return false  # Occupied by building, castle, or another obstacle
	grid[gy][gx] = TERRAIN_OBSTACLE_MARKER
	_rebuild_flow_field(player_index)
	return true


## Remove a terrain obstacle from a build zone. Returns true if removed.
## Rebuilds the affected flow field.
func remove_terrain_obstacle_build(player_index: int, gx: int, gy: int) -> bool:
	if player_index < 0 or player_index >= grid_cells.size():
		return false
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= GRID_ROWS:
		return false
	var grid: Array = grid_cells[player_index]
	if grid[gy][gx] != TERRAIN_OBSTACLE_MARKER:
		return false  # Nothing to remove (don't touch buildings or castle cells)
	grid[gy][gx] = -1
	_rebuild_flow_field(player_index)
	return true


## Place a terrain obstacle in the shared combat zone at combat-grid (gx, gy).
## Combat grid is 11 cols × 13 rows, spanning Y=345..709.
## Returns true on success, false if the cell is occupied or out of bounds.
## Rebuilds the combat flow fields for both teams.
func place_terrain_obstacle_combat(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= COMBAT_ROWS:
		return false
	if combat_grid[gy][gx] != -1:
		return false
	combat_grid[gy][gx] = TERRAIN_OBSTACLE_MARKER
	_rebuild_combat_flow_fields()
	return true


## Remove a terrain obstacle from the combat zone. Returns true if removed.
func remove_terrain_obstacle_combat(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= COMBAT_ROWS:
		return false
	if combat_grid[gy][gx] != TERRAIN_OBSTACLE_MARKER:
		return false
	combat_grid[gy][gx] = -1
	_rebuild_combat_flow_fields()
	return true


## Test if a build-zone grid cell is marked as a terrain obstacle.
func is_terrain_obstacle_build(player_index: int, gx: int, gy: int) -> bool:
	if player_index < 0 or player_index >= grid_cells.size():
		return false
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= GRID_ROWS:
		return false
	return grid_cells[player_index][gy][gx] == TERRAIN_OBSTACLE_MARKER


## Test if a combat-zone grid cell is marked as a terrain obstacle.
func is_terrain_obstacle_combat(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= COMBAT_ROWS:
		return false
	return combat_grid[gy][gx] == TERRAIN_OBSTACLE_MARKER


func _handle_activate_building(cmd: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player_index := get_player_index(cmd.player_id)
	if player_index == -1:
		return events

	# Find the building
	var building = null
	for entity in entities:
		if entity.id == cmd.building_id and entity.type == "building" \
		   and entity.player_index == player_index:
			building = entity
			break
	if building == null:
		return events

	# Check mana is full and ability not already active
	var max_mana: int = building.get("ability_max_mana", 0)
	if max_mana <= 0 or building.ability_mana < max_mana:
		return events
	if building.get("ability_active_ticks", 0) > 0:
		return events

	# Activate!
	building.ability_mana = 0
	var team: int = building.team

	if building.building_type == &"war_horn":
		# Rally Cry: +30% move speed for 100 ticks (10 seconds)
		building["ability_active_ticks"] = 100
		events.append({"type": "ability_activated", "building_id": building.id, "team": team, "ability": "rally_cry", "duration": 100})
	elif building.building_type == &"blood_totem":
		# Blood Rage: +25% damage, +10% damage taken for 80 ticks (8 seconds)
		building["ability_active_ticks"] = 80
		events.append({"type": "ability_activated", "building_id": building.id, "team": team, "ability": "blood_rage", "duration": 80})

	return events


## Per-building spawn timer update. Each building has its own cooldown.
func _update_building_spawns() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# T-077: no spawning during prep phase. Spawn timers do not tick — they
	# get reset to spawn_interval when prep ends, so the combat phase starts
	# with a predictable, synchronized first wave.
	if prep_phase:
		return events
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

	# Spawn at building position, offset to the march-direction edge
	var spawn_x: int = building.x  # Building center X (already FP)
	var bld_half_h: int = FP.from_int(building.grid_size_y * CELL_SIZE_PX / 2)
	var spawn_y: int
	if team == 0:
		# Team 0 marches UP: spawn just above building (lower Y)
		spawn_y = FP.sub(building.y, FP.add(bld_half_h, FP.from_int(4)))
	else:
		# Team 1 marches DOWN: spawn just below building (higher Y)
		spawn_y = FP.add(building.y, FP.add(bld_half_h, FP.from_int(4)))

	# T-077 Fix 4: 20% speed reduction (gives defenders time to react).
	# Measured baseline: footman ~12.3s march to castle. Target: 25-35s.
	# 20% reduction → ~15.4s (still below target but matches task author's prescription).
	var move_speed_fp: int = FP.div(
		FP.from_int(ud.move_speed * CELL_SIZE_PX * 80),
		FP.from_int(TICKS_PER_SECOND * 100)
	)
	var attack_range_fp: int = FP.from_int(ud.attack_range * CELL_SIZE_PX)
	var aggro_range_fp: int = FP.from_int(ud.aggro_range * CELL_SIZE_PX)

	for i in bd.units_per_wave:
		var unit_id := next_entity_id
		next_entity_id += 1
		# Spawn jitter: random X offset ±1 cell for organic spread
		var jitter_x: int = rng.range_int(-CELL_SIZE_PX, CELL_SIZE_PX)
		var x_offset: int = FP.from_int(i * 6 + jitter_x)

		var unit := {
			"id": unit_id,
			"type": "unit",
			"unit_type": ud.id,
			"owner": building.owner,
			"player_index": building.player_index,
			"team": team,
			"hp": _perk_hp(FP.from_int(ud.max_hp), building.player_index),
			"max_hp": _perk_hp(FP.from_int(ud.max_hp), building.player_index),
			"attack_damage": _perk_dmg(FP.from_int(ud.attack_damage), building.player_index),
			"base_attack_damage": _perk_dmg(FP.from_int(ud.attack_damage), building.player_index),
			"attack_speed_ticks": ud.attack_speed_ticks,
			"attack_range": attack_range_fp,
			"aggro_range": aggro_range_fp,
			# ±5% random speed variation + perk speed bonus
			"move_speed": _perk_speed(FP.div(FP.mul(move_speed_fp, FP.from_int(rng.range_int(95, 105))), FP.from_int(100)), building.player_index),
			"base_move_speed": _perk_speed(move_speed_fp, building.player_index),
			"armor": _perk_armor(FP.from_int(ud.armor), building.player_index),
			"magic_defense": FP.from_int(ud.magic_defense),
			"attack_type": ud.attack_type,
			"armor_type": ud.armor_type,
			"role": ud.role,
			"can_hit_air": ud.can_hit_air,
			"bounty": ud.bounty,
			"skill_id": ud.skill_id,
			"skill_param_1": ud.skill_param_1,
			"skill_param_2": ud.skill_param_2,
			"skill_cooldown": 0,
			"skill_stacks": 0,
			"skill_id_2": ud.skill_id_2,
			"skill_param_3": ud.skill_param_3,
			"skill_param_4": ud.skill_param_4,
			"skill_2_cooldown": 0,
			"skill_2_stacks": 0,
			"skill_2_active": false,
			"mana_shield_hp": FP.from_int(ud.skill_param_3) if ud.skill_id_2 == &"mana_shield" else FP.ZERO,
			"arcane_shield_hp": FP.from_int(ud.skill_param_3) if ud.skill_id_2 == &"arcane_shield" else FP.ZERO,
			"x": FP.clamp_fp(FP.add(spawn_x, x_offset), FP.from_int(ARENA_LEFT), FP.from_int(ARENA_RIGHT)),
			"y": spawn_y,
			"prev_x": FP.clamp_fp(FP.add(spawn_x, x_offset), FP.from_int(ARENA_LEFT), FP.from_int(ARENA_RIGHT)),
			"prev_y": spawn_y,
			"attack_cooldown": 0,
			"target_id": -1,
			"state": UNIT_STATE_MARCH,
			"last_progress_y": spawn_y,
			"stuck_ticks": 0,
		}
		entities.append(unit)
		_register_unit_cell(unit)

		units_spawned[team] += 1
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

	# Pre-pass: count global buff buildings and active abilities per team
	var armory_count: Array[int] = [0, 0]
	var blood_altar_count: Array[int] = [0, 0]
	var rally_cry_active: Array[bool] = [false, false]   # War Horn
	var blood_rage_active: Array[bool] = [false, false]   # Blood Totem
	for entity in entities:
		if entity.type != "building" or FP.lte(entity.hp, FP.ZERO):
			continue
		if entity.building_type == &"armory":
			armory_count[entity.team] = mini(armory_count[entity.team] + 1, 3)
		elif entity.building_type == &"blood_altar":
			blood_altar_count[entity.team] = mini(blood_altar_count[entity.team] + 1, 3)
		elif entity.building_type == &"war_horn" and entity.get("ability_active_ticks", 0) > 0:
			rally_cry_active[entity.team] = true
		elif entity.building_type == &"blood_totem" and entity.get("ability_active_ticks", 0) > 0:
			blood_rage_active[entity.team] = true

	# Pre-pass: clear temp buffs, tick debuffs, apply global buffs
	for entity in entities:
		if entity.type != "unit":
			continue
		entity["drums_buffed"] = false
		entity["devotion_armor"] = FP.ZERO  # Reset per-tick aura buff
		entity["battle_cry_bonus"] = false
		if entity.get("rend_timer", 0) > 0:
			entity.rend_timer -= 1
		# Bloodthirst perk: 5% max HP bleed per 10 ticks (0.5% per tick)
		var unit_perk: StringName = players[entity.player_index].get("perk", &"")
		if unit_perk == &"bloodthirst" and tick % 10 == 0:
			var bleed: int = FP.div(FP.mul(entity.max_hp, FP.from_int(5)), FP.from_int(100))
			entity.hp = FP.max_fp(FP.sub(entity.hp, bleed), FP.ONE)  # Don't kill from bleed
		# Tick Battle Cry buff duration
		if entity.get("battle_cry_timer", 0) > 0:
			entity.battle_cry_timer -= 1
			if entity.battle_cry_timer > 0:
				entity["battle_cry_bonus"] = true

		# Armory buff: +1 armor per armory (max 3)
		var armory_bonus: int = armory_count[entity.team]
		entity["armory_armor"] = FP.from_int(armory_bonus)

		# Blood Altar buff: +10% attack damage per altar (max 3 = +30%)
		var altar_count: int = blood_altar_count[entity.team]
		if altar_count > 0:
			entity["altar_damage_bonus"] = FP.div(FP.from_int(altar_count * 10), FP.from_int(100))
		else:
			entity["altar_damage_bonus"] = FP.ZERO

		# Rally Cry (War Horn): +30% move speed
		if rally_cry_active[entity.team]:
			entity["rally_cry_speed"] = true
		else:
			entity["rally_cry_speed"] = false

		# Blood Rage (Blood Totem): +25% damage, +10% damage taken
		entity["blood_rage_active"] = blood_rage_active[entity.team]

	# Pre-pass: apply War Drums + Devotion Aura + Battle Cry
	for entity in entities:
		if entity.type != "unit" or FP.lte(entity.hp, FP.ZERO):
			continue
		# War Drums aura (primary skill)
		if entity.get("skill_id", &"") == &"war_drums":
			var aura_range_sq: int = FP.mul(FP.from_int(entity.skill_param_2), FP.from_int(entity.skill_param_2))
			for other in entities:
				if other.type != "unit" or other.team != entity.team or other.id == entity.id:
					continue
				if FP.lte(other.hp, FP.ZERO):
					continue
				if FP.lte(_distance_squared_2d(entity, other), aura_range_sq):
					other["drums_buffed"] = true
		# Devotion Aura (Footman second skill): +armor to nearby allies
		if entity.get("skill_id_2", &"") == &"devotion_aura":
			var aura_range: int = FP.from_int(entity.skill_param_4)
			var aura_range_sq: int = FP.mul(aura_range, aura_range)
			var armor_bonus: int = FP.from_int(entity.skill_param_3)
			for other in entities:
				if other.type != "unit" or other.team != entity.team:
					continue
				if FP.lte(other.hp, FP.ZERO):
					continue
				if FP.lte(_distance_squared_2d(entity, other), aura_range_sq):
					other["devotion_armor"] = FP.add(other.get("devotion_armor", FP.ZERO), armor_bonus)
		# Battle Cry (Wardrummer second skill): periodic +15% damage to nearby allies
		if entity.get("skill_id_2", &"") == &"battle_cry":
			entity["skill_2_cooldown"] = entity.get("skill_2_cooldown", 0) - 1
			if entity.skill_2_cooldown <= 0:
				entity.skill_2_cooldown = entity.skill_param_3  # 40 ticks
				# Apply buff to allies in War Drums aura range
				var aura_range_sq: int = FP.mul(FP.from_int(entity.skill_param_2), FP.from_int(entity.skill_param_2))
				for other in entities:
					if other.type != "unit" or other.team != entity.team:
						continue
					if FP.lte(other.hp, FP.ZERO):
						continue
					if FP.lte(_distance_squared_2d(entity, other), aura_range_sq):
						other["battle_cry_timer"] = entity.skill_param_4  # 15 ticks
						other["battle_cry_bonus"] = true
				events.append({"type": "skill_proc", "unit_id": entity.id, "skill": "battle_cry"})

	# Pre-pass: tick fire zones (Burning Ground)
	for i in range(fire_zones.size() - 1, -1, -1):
		var fz: Dictionary = fire_zones[i]
		fz.ticks_remaining -= 1
		if fz.ticks_remaining <= 0:
			fire_zones.remove_at(i)
			continue
		# Damage enemies in fire zone
		for entity in entities:
			if entity.type != "unit" or entity.team == fz.team:
				continue
			if FP.lte(entity.hp, FP.ZERO):
				continue
			var dx: int = entity.x - fz.x
			var dy: int = entity.y - fz.y
			var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
			if FP.lte(dist_sq, fz.radius_sq):
				entity.hp = FP.sub(entity.hp, fz.damage)
				events.append({"type": "unit_attacked", "attacker_id": -1, "target_id": entity.id, "damage": fz.damage, "target_hp": entity.hp, "target_x": entity.x, "target_y": entity.y})

	# Snapshot positions before movement (for visual interpolation)
	for entity in entities:
		if entity.type == "unit" and FP.gt(entity.get("hp", FP.ZERO), FP.ZERO):
			entity["prev_x"] = entity.x
			entity["prev_y"] = entity.y

	# Unit separation removed — caused micro-jitter (1px Y-reversals).
	# Occupancy grid handles overcrowding. Visual spread handled by spawn jitter.

	# Main unit loop — state machine dispatch
	for entity in entities:
		if entity.type != "unit":
			continue
		if FP.lte(entity.hp, FP.ZERO):
			continue

		# Tick skill cooldown
		if entity.get("skill_cooldown", 0) > 0:
			entity.skill_cooldown -= 1
		if entity.attack_cooldown > 0:
			entity.attack_cooldown -= 1

		# Passive threshold skills
		events.append_array(_check_passive_skills(entity))

		# Casters (role=2) get special handling for healing
		if entity.role == 2:
			events.append_array(_update_caster(entity))
			continue

		# State machine dispatch
		match entity.get("state", UNIT_STATE_MARCH):
			UNIT_STATE_MARCH:
				events.append_array(_state_march(entity))
			UNIT_STATE_CHASE:
				events.append_array(_state_chase(entity))
			UNIT_STATE_ATTACK:
				events.append_array(_state_attack(entity))

		# Stuck recovery (only for MARCH and CHASE states)
		_update_stuck_detection(entity)

	# Post-pass: push units out of building/tree bounding boxes
	# Needed because flow field can slightly overshoot cell boundaries.
	# Castle collision removed (handled by occupancy grid full-width wall).
	_resolve_building_collisions()

	# Post-pass: sync unit occupancy grid after all movement + collision resolution
	for entity in entities:
		if entity.type == "unit" and FP.gt(entity.hp, FP.ZERO):
			var new_pos: Array = _pos_to_unit_grid(entity.x, entity.y)
			if new_pos[0] != entity.get("grid_row", -1) or new_pos[1] != entity.get("grid_col", -1):
				_unregister_unit_cell(entity)
				_register_unit_cell(entity)

	return events


# --- Unit State Machine ---

## MARCH state: No target. Follow flow field toward enemy castle.
func _state_march(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	unit["is_moving"] = true

	# Try to acquire a target (castle is always the fallback)
	_acquire_target(unit)

	if unit.target_id != -1:
		# Target acquired — transition to CHASE
		unit["state"] = UNIT_STATE_CHASE
		unit["stuck_ticks"] = 0
		return _state_chase(unit)

	# No target at all (shouldn't happen — castle is always available)
	_move_unit(unit)
	return events


## CHASE state: Has target, moving toward it.
func _state_chase(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	unit["is_moving"] = true

	# Validate target is still alive
	var target = _find_entity_by_id(unit.target_id)
	if target == null or FP.lte(target.hp, FP.ZERO):
		unit.target_id = -1
		unit["state"] = UNIT_STATE_MARCH
		return _state_march(unit)

	# Re-evaluate target — but if already close to current target, stay committed
	# to avoid micro-oscillation between two enemies at similar distance.
	var close_range: int = FP.mul(unit.attack_range, FP.from_int(3))  # 3x attack range
	var close_sq: int = FP.mul(close_range, close_range)
	var target_dist_sq: int = _distance_squared_2d(unit, target)
	if not FP.lte(target_dist_sq, close_sq):
		# Far from target — re-evaluate, a nearer enemy might have appeared
		_acquire_target(unit)
		target = _find_entity_by_id(unit.target_id)
		if target == null or FP.lte(target.hp, FP.ZERO):
			unit.target_id = -1
			unit["state"] = UNIT_STATE_MARCH
			return _state_march(unit)

	# Check if in attack range of current target
	if _in_attack_range(unit, target):
		unit["state"] = UNIT_STATE_ATTACK
		unit["is_moving"] = false
		unit["stuck_ticks"] = 0
		return _state_attack(unit)

	# Nothing in attack range — move toward target
	_move_unit(unit)
	return events


## ATTACK state: In range, attacking on cooldown.
func _state_attack(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	unit["is_moving"] = false

	# Validate target
	var target = _find_entity_by_id(unit.target_id)
	if target == null or FP.lte(target.hp, FP.ZERO):
		unit.target_id = -1
		unit["state"] = UNIT_STATE_MARCH
		unit["stuck_ticks"] = 0
		return _state_march(unit)

	# Check if target moved out of attack range
	# Castle: Y-only distance (it's a full-width wall)
	var in_range: bool = _in_attack_range(unit, target)

	if not in_range:
		unit["state"] = UNIT_STATE_CHASE
		return _state_chase(unit)

	# In range — attack if off cooldown (same for units, buildings, AND castle)
	if unit.attack_cooldown <= 0:
		if target.type == "castle":
			events.append_array(_check_castle_damage(unit))
		else:
			events.append_array(_perform_attack(unit, target))
			events.append_array(_check_attack_skills(unit))
		var cd: int = unit.attack_speed_ticks
		if unit.get("drums_buffed", false):
			cd = maxi(1, int(cd * 0.85))
		unit.attack_cooldown = cd

	return events


## Caster update: heal-priority behavior with state transitions.
func _update_caster(unit: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	if unit.attack_cooldown <= 0:
		var healed := _try_heal(unit)
		if healed:
			events.append_array(healed)
			unit.attack_cooldown = unit.attack_speed_ticks
			unit["last_action_heal"] = true
		# Holy Light AoE heal skill
		if unit.get("skill_id", &"") == &"holy_light" and unit.skill_cooldown <= 0:
			events.append_array(_skill_holy_light(unit))
		if healed:
			unit["is_moving"] = false
			unit["state"] = UNIT_STATE_ATTACK
			return events
		# No allies need healing — fall through to normal state machine
		unit["last_action_heal"] = false

	# Use same state machine as regular units when not healing
	match unit.get("state", UNIT_STATE_MARCH):
		UNIT_STATE_MARCH:
			events.append_array(_state_march(unit))
		UNIT_STATE_CHASE:
			events.append_array(_state_chase(unit))
		UNIT_STATE_ATTACK:
			events.append_array(_state_attack(unit))

	_update_stuck_detection(unit)
	return events


## Stuck detection: track Y-progress, nudge if stuck too long.
func _update_stuck_detection(unit: Dictionary) -> void:
	var state: int = unit.get("state", UNIT_STATE_MARCH)
	# Only MARCH and CHASE can be stuck
	if state == UNIT_STATE_ATTACK:
		unit["stuck_ticks"] = 0
		return

	var progressed: bool = false
	if unit.team == 0:
		if FP.lt(unit.y, unit.get("last_progress_y", unit.y)):
			unit["last_progress_y"] = unit.y
			unit["stuck_ticks"] = 0
			progressed = true
	else:
		if FP.gt(unit.y, unit.get("last_progress_y", unit.y)):
			unit["last_progress_y"] = unit.y
			unit["stuck_ticks"] = 0
			progressed = true

	if not progressed:
		unit["stuck_ticks"] = unit.get("stuck_ticks", 0) + 1
		# Short threshold if near target (blocked by allies), longer if far away
		var threshold: int = STUCK_THRESHOLD  # 1.5 seconds default
		if state == UNIT_STATE_CHASE and unit.target_id != -1:
			var tgt = _find_entity_by_id(unit.target_id)
			if tgt != null:
				var dist_sq: int = _distance_squared_2d(unit, tgt)
				var close_sq: int = FP.mul(FP.from_int(3 * CELL_SIZE_PX), FP.from_int(3 * CELL_SIZE_PX))
				if FP.lte(dist_sq, close_sq):
					threshold = 5  # 0.5 seconds — near target, just need a nudge
		if unit.get("stuck_ticks", 0) >= threshold:
			# Only unstick if we haven't already tried recently (prevent jitter loops)
			var unstick_count: int = unit.get("unstick_count", 0) + 1
			unit["unstick_count"] = unstick_count
			if unstick_count <= 3:
				_unstick_unit(unit)
			# else: give up nudging — unit stays put until target changes
			unit["stuck_ticks"] = 0
	else:
		unit["stuck_ticks"] = 0
		unit["unstick_count"] = 0  # Reset on real progress


## Push overlapping same-team units apart so they spread visually.
## All units participate (including attackers) but with gentle force
## so melee units fan out around targets instead of stacking into blobs.
func _separate_units() -> void:
	var sep_dist: int = FP.from_int(16)  # Minimum pixels between same-team units
	var sep_dist_sq: int = FP.mul(sep_dist, sep_dist)
	var push_force: int = FP.ONE  # 1 pixel per tick (gentle, won't shove out of attack range)

	# Only check nearby MOVING units — attacking units plant their feet (Clash Royale model)
	var units: Array = []
	for e in entities:
		if e.type == "unit" and FP.gt(e.hp, FP.ZERO) and e.get("is_moving", true):
			units.append(e)

	for i in units.size():
		var a: Dictionary = units[i]
		for j in range(i + 1, units.size()):
			var b: Dictionary = units[j]
			if a.team != b.team:
				continue
			var dx: int = a.x - b.x
			var dy: int = a.y - b.y
			var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
			if dist_sq > 0 and FP.lt(dist_sq, sep_dist_sq):
				# Push apart along the delta vector
				var dist: int = FP.sqrt_fp(dist_sq)
				if dist > 0:
					var push_x: int = FP.div(FP.mul(dx, push_force), dist)
					var push_y: int = FP.div(FP.mul(dy, push_force), dist)
					a.x = FP.add(a.x, push_x)
					a.y = FP.add(a.y, push_y)
					b.x = FP.sub(b.x, push_x)
					b.y = FP.sub(b.y, push_y)


## Push units out of building bounding boxes so they path around buildings.
func _resolve_building_collisions() -> void:
	# Collect all living buildings with their bounding rects
	var buildings: Array = []
	for e in entities:
		if e.type == "building" and FP.gt(e.hp, FP.ZERO):
			var half_w: int = FP.from_int(e.grid_size_x * CELL_SIZE_PX / 2)
			var half_h: int = FP.from_int(e.grid_size_y * CELL_SIZE_PX / 2)
			buildings.append({"x": e.x, "y": e.y, "hw": half_w, "hh": half_h})

	# Collect combat-zone terrain obstacle rects (trees/rocks)
	var tree_rects: Array = get_combat_tree_rects()

	# Collect build-zone terrain obstacle rects (per player)
	var build_terrain_rects: Array = []
	for pi in grid_cells.size():
		var team: int = players[pi].team
		var zone_y: int = TEAM_0_SPAWN_Y if team == 0 else TEAM_1_ZONE_Y
		for gy in GRID_ROWS:
			for gx in GRID_COLS:
				if grid_cells[pi][gy][gx] != TERRAIN_OBSTACLE_MARKER:
					continue
				build_terrain_rects.append({
					"x": FP.from_int(GRID_ORIGIN_X + gx * CELL_SIZE_PX + CELL_SIZE_PX / 2),
					"y": FP.from_int(zone_y + gy * CELL_SIZE_PX + CELL_SIZE_PX / 2),
					"hw": FP.from_int(CELL_SIZE_PX / 2),
					"hh": FP.from_int(CELL_SIZE_PX / 2),
				})

	if buildings.is_empty() and tree_rects.is_empty() and build_terrain_rects.is_empty():
		return

	for e in entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		var is_flying: bool = e.get("role", 0) == 3
		# Buildings push out ground units only — flying units soar over
		if is_flying:
			continue
		for bld in buildings:
			var dx: int = FP.sub(e.x, bld.x)
			var dy: int = FP.sub(e.y, bld.y)
			var abs_dx: int = FP.abs_fp(dx)
			var abs_dy: int = FP.abs_fp(dy)
			if FP.lt(abs_dx, bld.hw) and FP.lt(abs_dy, bld.hh):
				var push_x: int = FP.sub(bld.hw, abs_dx)
				var push_y: int = FP.sub(bld.hh, abs_dy)
				if FP.lt(push_x, push_y):
					if dx >= 0:
						e.x = FP.add(bld.x, bld.hw)
					else:
						e.x = FP.sub(bld.x, bld.hw)
				else:
					if dy >= 0:
						e.y = FP.add(bld.y, bld.hh)
					else:
						e.y = FP.sub(bld.y, bld.hh)

		# Terrain obstacles (combat zone + build zone)
		for tr in tree_rects:
			var tdx: int = FP.sub(e.x, tr.x)
			var tdy: int = FP.sub(e.y, tr.y)
			var abs_tdx: int = FP.abs_fp(tdx)
			var abs_tdy: int = FP.abs_fp(tdy)
			if FP.lt(abs_tdx, tr.hw) and FP.lt(abs_tdy, tr.hh):
				var push_x: int = FP.sub(tr.hw, abs_tdx)
				var push_y: int = FP.sub(tr.hh, abs_tdy)
				if FP.lt(push_x, push_y):
					if tdx >= 0:
						e.x = FP.add(tr.x, tr.hw)
					else:
						e.x = FP.sub(tr.x, tr.hw)
				else:
					if tdy >= 0:
						e.y = FP.add(tr.y, tr.hh)
					else:
						e.y = FP.sub(tr.y, tr.hh)
		for br in build_terrain_rects:
			var bdx: int = FP.sub(e.x, br.x)
			var bdy: int = FP.sub(e.y, br.y)
			var abs_bdx: int = FP.abs_fp(bdx)
			var abs_bdy: int = FP.abs_fp(bdy)
			if FP.lt(abs_bdx, br.hw) and FP.lt(abs_bdy, br.hh):
				var push_x: int = FP.sub(br.hw, abs_bdx)
				var push_y: int = FP.sub(br.hh, abs_bdy)
				if FP.lt(push_x, push_y):
					if bdx >= 0:
						e.x = FP.add(br.x, br.hw)
					else:
						e.x = FP.sub(br.x, br.hw)
				else:
					if bdy >= 0:
						e.y = FP.add(br.y, br.hh)
					else:
						e.y = FP.sub(br.y, br.hh)

	# Castle collision handled by occupancy grid (full-width impassable wall rows)
	# + hard Y-clamp in _move_unit() as defense-in-depth


# --- Perk Helpers ---

## Apply Iron Discipline (+10% HP) or Bloodthirst (+10% DMG via _perk_dmg)
func _perk_hp(base_hp: int, player_index: int) -> int:
	var perk: StringName = players[player_index].get("perk", &"")
	if perk == &"iron_discipline":
		return FP.add(base_hp, FP.div(FP.mul(base_hp, FP.from_int(10)), FP.from_int(100)))
	return base_hp

func _perk_dmg(base_dmg: int, player_index: int) -> int:
	var perk: StringName = players[player_index].get("perk", &"")
	if perk == &"iron_discipline":
		return FP.sub(base_dmg, FP.div(FP.mul(base_dmg, FP.from_int(10)), FP.from_int(100)))
	if perk == &"bloodthirst":
		return FP.add(base_dmg, FP.div(FP.mul(base_dmg, FP.from_int(10)), FP.from_int(100)))
	return base_dmg

func _perk_speed(base_speed: int, player_index: int) -> int:
	var perk: StringName = players[player_index].get("perk", &"")
	if perk == &"swift_march":
		return FP.add(base_speed, FP.div(FP.mul(base_speed, FP.from_int(15)), FP.from_int(100)))
	return base_speed

func _perk_armor(base_armor: int, player_index: int) -> int:
	var perk: StringName = players[player_index].get("perk", &"")
	if perk == &"swift_march":
		return FP.sub(base_armor, FP.ONE)  # -1 armor (min 0 handled by combat)
	return base_armor

## Get perk-modified bounty for kill rewards
func _perk_bounty(base_bounty: int, killer_player_index: int) -> int:
	var perk: StringName = players[killer_player_index].get("perk", &"")
	if perk == &"pillage":
		return FP.add(base_bounty, FP.div(FP.mul(base_bounty, FP.from_int(50)), FP.from_int(100)))
	return base_bounty


# --- Castle Grid Helpers ---

## Returns [row_min, row_max, col_min, col_max] for a team's castle grid footprint.
## T-096: symmetric 5-wide × 2-tall footprint at the back of each team's build zone.
## Team 0 castle occupies the last 2 rows (8-9); team 1 castle occupies the first 2 rows (0-1).
## Both use the middle 5 columns (3-7), leaving cols 0-2 and 8-10 buildable on castle rows
## for "flanking" defensive placement — per the "castle is a regular building" design.
func _castle_grid_footprint(team: int) -> Array:
	var col_min: int = (GRID_COLS - CASTLE_FOOTPRINT_W) / 2   # (11-5)/2 = 3
	var col_max: int = col_min + CASTLE_FOOTPRINT_W - 1        # 3+4 = 7
	if team == 0:
		return [GRID_ROWS - CASTLE_FOOTPRINT_H, GRID_ROWS - 1, col_min, col_max]  # rows 8-9
	return [0, CASTLE_FOOTPRINT_H - 1, col_min, col_max]                          # rows 0-1

## Returns the BFS goal row (row immediately in front of the castle).
func _castle_front_row(team: int) -> int:
	var fp: Array = _castle_grid_footprint(team)
	if team == 0:
		return maxi(0, fp[0] - 1)  # Row above castle top (team 0: row 6)
	else:
		return mini(GRID_ROWS - 1, fp[1] + 1)  # Row below castle bottom (team 1: row 2)


# --- Flow Field Pathfinding ---

## Rebuild the flow field for a player's grid via BFS from castle front row.
func _rebuild_flow_field(player_index: int) -> void:
	var team: int = players[player_index].team
	var grid: Array = grid_cells[player_index]
	var field: Array = flow_fields[player_index]

	for i in field.size():
		field[i] = -1

	# Goal row: the row in front of the castle (castle cells are grid obstacles)
	var goal_row: int = _castle_front_row(team)

	var queue: Array = []
	# Seed BFS with all walkable cells in goal row
	for col in GRID_COLS:
		if grid[goal_row][col] == -1:
			var idx: int = goal_row * GRID_COLS + col
			field[idx] = -2  # Goal marker
			queue.append(idx)

	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var cur_row: int = current / GRID_COLS
		var cur_col: int = current % GRID_COLS

		for dir in 8:
			var nr: int = cur_row + DIR_DY[dir]
			var nc: int = cur_col + DIR_DX[dir]
			if nr < 0 or nr >= GRID_ROWS or nc < 0 or nc >= GRID_COLS:
				continue
			var n_idx: int = nr * GRID_COLS + nc
			if field[n_idx] != -1:
				continue
			if grid[nr][nc] != -1:
				continue
			# Prevent diagonal corner-cutting through buildings
			if DIR_DX[dir] != 0 and DIR_DY[dir] != 0:
				if grid[cur_row + DIR_DY[dir]][cur_col] != -1:
					continue
				if grid[cur_row][cur_col + DIR_DX[dir]] != -1:
					continue
			# Direction FROM neighbor TOWARD goal = opposite of expansion direction
			field[n_idx] = (dir + 4) % 8
			queue.append(n_idx)

	flow_fields[player_index] = field


## Convert pixel-space FP position to grid [row, col] in a team's build zone. Returns [-1,-1] if outside.
func _pixel_to_grid(x_fp: int, y_fp: int, target_team: int) -> Array:
	var px: int = FP.to_int(x_fp)
	var py: int = FP.to_int(y_fp)
	var zone_y: int = TEAM_0_SPAWN_Y if target_team == 0 else TEAM_1_ZONE_Y
	var local_x: int = px - GRID_ORIGIN_X
	var local_y: int = py - zone_y
	if local_x < 0 or local_x >= GRID_COLS * CELL_SIZE_PX:
		return [-1, -1]
	if local_y < 0 or local_y >= GRID_ROWS * CELL_SIZE_PX:
		return [-1, -1]
	return [local_y / CELL_SIZE_PX, local_x / CELL_SIZE_PX]


## Get player_index that owns a given team's grid.
func _get_player_index_for_team(team: int) -> int:
	for i in players.size():
		if players[i].team == team:
			return i
	return 0


## Convert pixel position to combat zone grid [row, col]. Returns [-1,-1] if outside.
func _pixel_to_combat_grid(x_fp: int, y_fp: int) -> Array:
	var px: int = FP.to_int(x_fp)
	var py: int = FP.to_int(y_fp)
	var local_x: int = px - GRID_ORIGIN_X
	var local_y: int = py - COMBAT_Y
	if local_x < 0 or local_x >= GRID_COLS * CELL_SIZE_PX:
		return [-1, -1]
	if local_y < 0 or local_y >= COMBAT_ROWS * CELL_SIZE_PX:
		return [-1, -1]
	return [local_y / CELL_SIZE_PX, local_x / CELL_SIZE_PX]


## Combat grid with 1-cell hysteresis at boundaries to prevent oscillation.
## Units within 1 cell of the combat zone edge are treated as inside the zone.
func _pixel_to_combat_grid_hysteresis(x_fp: int, y_fp: int) -> Array:
	var px: int = FP.to_int(x_fp)
	var py: int = FP.to_int(y_fp)
	var local_x: int = px - GRID_ORIGIN_X
	var local_y: int = py - COMBAT_Y
	if local_x < 0 or local_x >= GRID_COLS * CELL_SIZE_PX:
		return [-1, -1]
	# Extend combat zone by 1 cell on each side for movement checks
	if local_y < -CELL_SIZE_PX or local_y >= COMBAT_ROWS * CELL_SIZE_PX + CELL_SIZE_PX:
		return [-1, -1]
	var row: int = clampi(local_y / CELL_SIZE_PX, 0, COMBAT_ROWS - 1)
	var col: int = local_x / CELL_SIZE_PX
	return [row, col]


# --- Unit Occupancy Grid ---

## Convert FP pixel position to unit grid [row, col]. Returns [-1, -1] if outside arena.
func _pos_to_unit_grid(x_fp: int, y_fp: int) -> Array:
	var px: int = FP.to_int(x_fp)
	var py: int = FP.to_int(y_fp)
	var local_x: int = px - GRID_ORIGIN_X
	var local_y: int = py - UNIT_GRID_Y_OFFSET
	if local_x < 0 or local_x >= GRID_COLS * CELL_SIZE_PX:
		return [-1, -1]
	if local_y < 0 or local_y >= UNIT_GRID_ROWS * CELL_SIZE_PX:
		return [-1, -1]
	return [local_y / CELL_SIZE_PX, local_x / CELL_SIZE_PX]


## Register a unit in the occupancy grid. Stores its grid position on the unit dict.
func _register_unit_cell(unit: Dictionary) -> void:
	var pos: Array = _pos_to_unit_grid(unit.x, unit.y)
	unit["grid_row"] = pos[0]
	unit["grid_col"] = pos[1]
	if pos[0] == -1:
		return
	var idx: int = pos[0] * GRID_COLS + pos[1]
	if idx >= 0 and idx < unit_grid.size():
		var cell: Array = unit_grid[idx]
		# Don't register in impassable cells (castle wall sentinel)
		if cell.size() == 1 and cell[0] == -2:
			return
		cell.append(unit.id)


## Unregister a unit from the occupancy grid.
func _unregister_unit_cell(unit: Dictionary) -> void:
	var row: int = unit.get("grid_row", -1)
	var col: int = unit.get("grid_col", -1)
	if row == -1:
		return
	var idx: int = row * GRID_COLS + col
	if idx >= 0 and idx < unit_grid.size():
		var cell: Array = unit_grid[idx]
		var pos_in_cell: int = cell.find(unit.id)
		if pos_in_cell != -1:
			cell.remove_at(pos_in_cell)
	unit["grid_row"] = -1
	unit["grid_col"] = -1


## Check if a unit of the given team can enter the cell (capacity not exceeded, not blocked).
func _can_enter_cell(col: int, row: int, team: int) -> bool:
	if row < 0 or row >= UNIT_GRID_ROWS or col < 0 or col >= GRID_COLS:
		return false
	var idx: int = row * GRID_COLS + col
	var cell: Array = unit_grid[idx]
	# Check for impassable sentinel (castle wall, etc.)
	if cell.size() == 1 and cell[0] == -2:
		return false
	# Count same-team units in the cell
	var same_team_count: int = 0
	for uid in cell:
		var u = _find_entity_by_id(uid)
		if u != null and u.team == team:
			same_team_count += 1
	return same_team_count < CELL_CAPACITY


## Count same-team units in a cell (for flow field weighting).
func _cell_team_count(col: int, row: int, team: int) -> int:
	if row < 0 or row >= UNIT_GRID_ROWS or col < 0 or col >= GRID_COLS:
		return 0
	var idx: int = row * GRID_COLS + col
	var count: int = 0
	for uid in unit_grid[idx]:
		var u = _find_entity_by_id(uid)
		if u != null and u.team == team:
			count += 1
	return count


## Initialize the unit occupancy grid. Call during initialize().
func _init_unit_grid() -> void:
	unit_grid.clear()
	unit_grid.resize(GRID_COLS * UNIT_GRID_ROWS)
	for i in unit_grid.size():
		unit_grid[i] = []


## Build flow fields for combat zone (one per team march direction).
## Team 0 marches UP (goal = row 0 = top of combat zone)
## Team 1 marches DOWN (goal = row COMBAT_ROWS-1 = bottom of combat zone)
func _rebuild_combat_flow_fields() -> void:
	for team in 2:
		var field: Array = combat_flow_fields[team]
		for i in field.size():
			field[i] = -1
		var goal_row: int = 0 if team == 0 else COMBAT_ROWS - 1
		var queue: Array = []
		for col in GRID_COLS:
			if combat_grid[goal_row][col] == -1:
				var idx: int = goal_row * GRID_COLS + col
				field[idx] = -2
				queue.append(idx)
		var head: int = 0
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			var cur_row: int = current / GRID_COLS
			var cur_col: int = current % GRID_COLS
			for dir in 8:
				var nr: int = cur_row + DIR_DY[dir]
				var nc: int = cur_col + DIR_DX[dir]
				if nr < 0 or nr >= COMBAT_ROWS or nc < 0 or nc >= GRID_COLS:
					continue
				var n_idx: int = nr * GRID_COLS + nc
				if field[n_idx] != -1:
					continue
				if combat_grid[nr][nc] != -1:
					continue
				if DIR_DX[dir] != 0 and DIR_DY[dir] != 0:
					if combat_grid[cur_row + DIR_DY[dir]][cur_col] != -1:
						continue
					if combat_grid[cur_row][cur_col + DIR_DX[dir]] != -1:
						continue
				field[n_idx] = (dir + 4) % 8
				queue.append(n_idx)
		combat_flow_fields[team] = field


## Occupancy-weighted combat flow field rebuild (Dijkstra-style multi-pass BFS).
## Cells with more units cost more, causing units to naturally distribute across gaps.
## Get list of tree obstacle positions as pixel-space rects (for collision).
func get_combat_tree_rects() -> Array:
	var rects: Array = []
	for row in COMBAT_ROWS:
		for col in GRID_COLS:
			if combat_grid[row][col] != -1:
				rects.append({
					"x": FP.from_int(GRID_ORIGIN_X + col * CELL_SIZE_PX + CELL_SIZE_PX / 2),
					"y": FP.from_int(COMBAT_Y + row * CELL_SIZE_PX + CELL_SIZE_PX / 2),
					"hw": FP.from_int(CELL_SIZE_PX / 2),
					"hh": FP.from_int(CELL_SIZE_PX / 2),
				})
	return rects


## Check if placing a building would block all paths from entry to castle.
## Uses conservative 4-directional BFS.
func _would_block_path(player_index: int, gx: int, gy: int, sx: int, sy: int) -> bool:
	var team: int = players[player_index].team
	var grid: Array = grid_cells[player_index]

	# Create flat blocked array
	var blocked: Array = []
	blocked.resize(GRID_COLS * GRID_ROWS)
	for row in GRID_ROWS:
		for col in GRID_COLS:
			blocked[row * GRID_COLS + col] = (grid[row][col] != -1)

	# Mark proposed building cells
	for row in range(gy, gy + sy):
		for col in range(gx, gx + sx):
			blocked[row * GRID_COLS + col] = true

	# BFS from castle front row to entry row (4-directional)
	var goal_row: int = _castle_front_row(team)
	var entry_row: int = 0 if team == 0 else GRID_ROWS - 1

	var queue: Array = []
	var visited: Array = []
	visited.resize(GRID_COLS * GRID_ROWS)
	visited.fill(false)

	for col in GRID_COLS:
		var idx: int = goal_row * GRID_COLS + col
		if not blocked[idx]:
			visited[idx] = true
			queue.append(idx)

	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var cur_row: int = current / GRID_COLS
		if cur_row == entry_row:
			return false  # Path exists — does NOT block

		# 4-directional: up(0), right(2), down(4), left(6)
		for dir_i in [0, 2, 4, 6]:
			var nr: int = cur_row + DIR_DY[dir_i]
			var nc: int = (current % GRID_COLS) + DIR_DX[dir_i]
			if nr < 0 or nr >= GRID_ROWS or nc < 0 or nc >= GRID_COLS:
				continue
			var n_idx: int = nr * GRID_COLS + nc
			if visited[n_idx] or blocked[n_idx]:
				continue
			visited[n_idx] = true
			queue.append(n_idx)

	return true  # No path — would block


## Teleport a stuck unit to the nearest reachable flow field cell.
## Wall-safe unstick: scan 8 neighbor cells, pick the passable one closest to enemy castle.
## Guaranteed not to teleport through walls (only moves 1 cell).
func _unstick_unit(unit: Dictionary) -> void:
	var cur_pos: Array = _pos_to_unit_grid(unit.x, unit.y)
	if cur_pos[0] == -1:
		# Outside grid — nudge toward center
		unit.x = FP.clamp_fp(unit.x, FP.from_int(ARENA_LEFT + CELL_SIZE_PX), FP.from_int(ARENA_RIGHT - CELL_SIZE_PX))
		return

	var best_row: int = -1
	var best_col: int = -1
	var best_score: int = 0x7FFFFFFF

	# Nudge toward current target if we have one, otherwise toward enemy castle
	var goal_row: int
	var goal_col: int
	var target = _find_entity_by_id(unit.target_id) if unit.target_id != -1 else null
	if target != null:
		var tpos: Array = _pos_to_unit_grid(target.x, target.y)
		goal_row = tpos[0] if tpos[0] != -1 else ((CASTLE_1_Y if unit.team == 0 else CASTLE_0_Y) - UNIT_GRID_Y_OFFSET) / CELL_SIZE_PX
		goal_col = tpos[1] if tpos[1] != -1 else cur_pos[1]
	else:
		goal_row = ((CASTLE_1_Y if unit.team == 0 else CASTLE_0_Y) - UNIT_GRID_Y_OFFSET) / CELL_SIZE_PX
		goal_col = cur_pos[1]

	for dir in 8:
		var nr: int = cur_pos[0] + DIR_DY[dir]
		var nc: int = cur_pos[1] + DIR_DX[dir]
		if _can_enter_cell(nc, nr, unit.team):
			# Score = distance to goal (lower = closer = better)
			var score: int = absi(nr - goal_row) + absi(nc - goal_col)
			if score < best_score:
				best_score = score
				best_row = nr
				best_col = nc

	if best_row != -1:
		# Move to center of the best neighbor cell
		unit.x = FP.from_int(GRID_ORIGIN_X + best_col * CELL_SIZE_PX + CELL_SIZE_PX / 2)
		unit.y = FP.from_int(UNIT_GRID_Y_OFFSET + best_row * CELL_SIZE_PX + CELL_SIZE_PX / 2)
		unit["last_progress_y"] = unit.y
	# Keep current target — don't clear. The unit will re-evaluate naturally.


## Target acquisition: scan nearby, fight what's close, march to castle otherwise.
## Units don't chase across the map. They march toward the castle and engage
## enemies/buildings they encounter along the way — then resume marching.
## Re-evaluates every tick so units respond to new threats immediately.
func _acquire_target(unit: Dictionary) -> void:
	# Nearest enemy entity. Castle, buildings, units — all treated equally.
	# BUG-28: ground units without can_hit_air skip flying (role==3) enemies.
	var can_hit_air: bool = unit.get("can_hit_air", false)
	var best_id: int = -1
	var best_dist: int = 0x7FFFFFFFFFFFFFF

	for other in entities:
		if other.team == unit.team:
			continue
		if FP.lte(other.hp, FP.ZERO):
			continue
		if other.type != "unit" and other.type != "building" and other.type != "castle":
			continue
		if other.type == "unit" and other.get("role", 0) == 3 and not can_hit_air:
			continue
		var dist_sq: int = _distance_squared_2d(unit, other)
		if dist_sq < best_dist:
			best_dist = dist_sq
			best_id = other.id

	if best_id != -1:
		unit.target_id = best_id


## Check if a building blocks line of sight between two entities.
## Simple check: if both are in/near the same build zone, check if any building
## occupies a grid cell between them on the Y axis.
func _is_blocked_by_building(from_entity: Dictionary, to_entity: Dictionary) -> bool:
	# Only check in build zones where buildings exist
	var check_team: int = to_entity.team  # Check the target's team's build zone
	var from_grid: Array = _pixel_to_grid(from_entity.x, from_entity.y, check_team)
	var to_grid: Array = _pixel_to_grid(to_entity.x, to_entity.y, check_team)
	# If neither is in the build zone, no buildings to block
	if from_grid[0] == -1 and to_grid[0] == -1:
		return false
	# If attacker is outside and target is inside build zone, check the column
	var grid: Array = grid_cells[_get_player_index_for_team(check_team)]
	# Simple vertical check: scan grid rows between from and to
	var zone_y: int = TEAM_0_SPAWN_Y if check_team == 0 else TEAM_1_ZONE_Y
	var from_row: int = clampi((FP.to_int(from_entity.y) - zone_y) / CELL_SIZE_PX, 0, GRID_ROWS - 1)
	var to_row: int = clampi((FP.to_int(to_entity.y) - zone_y) / CELL_SIZE_PX, 0, GRID_ROWS - 1)
	var col: int = clampi((FP.to_int(to_entity.x) - GRID_ORIGIN_X) / CELL_SIZE_PX, 0, GRID_COLS - 1)
	var min_row: int = mini(from_row, to_row)
	var max_row: int = maxi(from_row, to_row)
	for row in range(min_row, max_row + 1):
		if grid[row][col] != -1:
			return true  # Building blocks the path
	return false


## Check if combat zone trees block LOS between two entities.
func _is_blocked_by_tree(from_entity: Dictionary, to_entity: Dictionary) -> bool:
	var from_cg: Array = _pixel_to_combat_grid(from_entity.x, from_entity.y)
	var to_cg: Array = _pixel_to_combat_grid(to_entity.x, to_entity.y)
	# Both must be in or near combat zone
	if from_cg[0] == -1 and to_cg[0] == -1:
		return false
	# Scan combat grid rows between from and to for tree obstacles in both columns
	var from_row: int = clampi((FP.to_int(from_entity.y) - COMBAT_Y) / CELL_SIZE_PX, 0, COMBAT_ROWS - 1)
	var to_row: int = clampi((FP.to_int(to_entity.y) - COMBAT_Y) / CELL_SIZE_PX, 0, COMBAT_ROWS - 1)
	var from_col: int = clampi((FP.to_int(from_entity.x) - GRID_ORIGIN_X) / CELL_SIZE_PX, 0, GRID_COLS - 1)
	var to_col: int = clampi((FP.to_int(to_entity.x) - GRID_ORIGIN_X) / CELL_SIZE_PX, 0, GRID_COLS - 1)
	var min_row: int = mini(from_row, to_row)
	var max_row: int = maxi(from_row, to_row)
	for row in range(min_row, max_row + 1):
		if row >= 0 and row < COMBAT_ROWS:
			if combat_grid[row][from_col] != -1:
				return true
			if from_col != to_col and combat_grid[row][to_col] != -1:
				return true
	return false


## Full 2D distance squared (for aggro detection and combat range).
func _distance_squared_2d(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return FP.mul(dx, dx) + FP.mul(dy, dy)



func _move_unit(unit: Dictionary) -> void:
	var old_x: int = unit.x
	var old_y: int = unit.y
	_move_unit_inner(unit)  # Obstacle check is inside — unit won't enter trees/buildings
	# T-096: Y-clamp removed. Castle is now a regular 5×2 building obstacle in the
	# occupancy grid; units path around it via flow field and the occupancy check
	# below (_can_enter_cell) prevents entering castle cells. Flanking cells (cols
	# 0-2, 8-10 on castle rows) are walkable — intended defensive design.

	# Occupancy grid capacity check
	var new_x: int = unit.x
	var new_y: int = unit.y
	var new_cell: Array = _pos_to_unit_grid(new_x, new_y)
	var old_cell: Array = _pos_to_unit_grid(old_x, old_y)
	# Only check if we actually changed cells
	if new_cell[0] != old_cell[0] or new_cell[1] != old_cell[1]:
		if new_cell[0] != -1 and not _can_enter_cell(new_cell[1], new_cell[0], unit.team):
			# Full destination — try Y-only (keep march direction, slide on X)
			var y_only_cell: Array = _pos_to_unit_grid(old_x, new_y)
			if y_only_cell[0] != -1 and (y_only_cell[0] != old_cell[0] or y_only_cell[1] != old_cell[1]) and _can_enter_cell(y_only_cell[1], y_only_cell[0], unit.team):
				unit.x = old_x  # Keep old X, use new Y
			else:
				# Try X-only
				var x_only_cell: Array = _pos_to_unit_grid(new_x, old_y)
				if x_only_cell[0] != -1 and (x_only_cell[0] != old_cell[0] or x_only_cell[1] != old_cell[1]) and _can_enter_cell(x_only_cell[1], x_only_cell[0], unit.team):
					unit.y = old_y  # Keep old Y, use new X
				else:
					# All blocked — stay put (stuck detection will handle)
					unit.x = old_x
					unit.y = old_y


## Check if a unit is within attack range of a target.
## Units: center-to-center 2D distance.
## Buildings + Castles: center-to-EDGE distance via grid_size_x/y (T-096 unified).
func _in_attack_range(unit: Dictionary, target: Dictionary) -> bool:
	var range_sq: int = FP.mul(unit.attack_range, unit.attack_range)
	if target.type == "building" or target.type == "castle":
		# T-096: castle now carries grid_size_x=5, grid_size_y=2 so the same edge
		# formula applies. This replaces the old Y-only 40px magic number that
		# caused BUG-PATH1 asymmetries.
		var hw: int = FP.from_int(target.get("grid_size_x", 2) * CELL_SIZE_PX / 2)
		var hh: int = FP.from_int(target.get("grid_size_y", 2) * CELL_SIZE_PX / 2)
		var dx: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(unit.x, target.x)), hw), FP.ZERO)
		var dy: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(unit.y, target.y)), hh), FP.ZERO)
		var edge_dist_sq: int = FP.add(FP.mul(dx, dx), FP.mul(dy, dy))
		return FP.lte(edge_dist_sq, range_sq)
	# Unit: center-to-center
	var dist_sq: int = _distance_squared_2d(unit, target)
	return FP.lte(dist_sq, range_sq)


## Check if a pixel position is inside any obstacle (tree, building, or castle wall).
## Check if a pixel position is inside any obstacle (building, castle wall, terrain).
## If `unit` is provided and unit.role == 3 (FLYING), terrain obstacles AND buildings
## are ignored — flying units soar over everything except the castle wall.
func _is_inside_obstacle(x_fp: int, y_fp: int, unit: Dictionary = {}) -> bool:
	var is_flying: bool = unit.get("role", 0) == 3
	# Check combat zone terrain obstacles (trees/rocks)
	var cpos: Array = _pixel_to_combat_grid(x_fp, y_fp)
	if cpos[0] != -1 and combat_grid[cpos[0]][cpos[1]] != -1:
		if not is_flying:
			return true
	# Check occupancy grid for castle wall sentinels (-2) — flying units still collide
	var upos: Array = _pos_to_unit_grid(x_fp, y_fp)
	if upos[0] != -1:
		var uidx: int = upos[0] * GRID_COLS + upos[1]
		if uidx >= 0 and uidx < unit_grid.size():
			var cell: Array = unit_grid[uidx]
			if cell.size() == 1 and cell[0] == -2:
				return true
	# Check per-player build-zone terrain obstacles — skipped by flying units
	if not is_flying:
		for pi in grid_cells.size():
			var team: int = players[pi].team
			var bpos: Array = _pixel_to_grid(x_fp, y_fp, team)
			if bpos[0] == -1:
				continue
			if grid_cells[pi][bpos[0]][bpos[1]] == TERRAIN_OBSTACLE_MARKER:
				return true
	# Check buildings (both teams) — flying units skip these (soar over)
	if is_flying:
		return false
	for e in entities:
		if e.type != "building" or FP.lte(e.hp, FP.ZERO):
			continue
		var hw: int = FP.from_int(e.grid_size_x * CELL_SIZE_PX / 2)
		var hh: int = FP.from_int(e.grid_size_y * CELL_SIZE_PX / 2)
		if FP.lt(FP.abs_fp(FP.sub(x_fp, e.x)), hw) and FP.lt(FP.abs_fp(FP.sub(y_fp, e.y)), hh):
			return true
	return false


func _move_unit_inner(unit: Dictionary) -> void:
	var speed: int = unit.move_speed
	if unit.get("rally_cry_speed", false):
		speed = FP.add(speed, FP.div(FP.mul(speed, FP.from_int(30)), FP.from_int(100)))

	# Calculate desired movement direction
	var move_dx: int = FP.ZERO
	var move_dy: int = FP.ZERO

	if unit.target_id != -1:
		var target = _find_entity_by_id(unit.target_id)
		if target == null or FP.lte(target.hp, FP.ZERO):
			unit.target_id = -1
		elif _in_attack_range(unit, target):
			return  # In range, don't move
		else:
			# T-096: castles use the same chase logic as buildings — move X+Y toward
			# the target. The edge-distance _in_attack_range with castle grid_size handles
			# stopping when at the hitbox. Flanking attackers converge on the castle X.
			var dx: int = target.x - unit.x
			var dy: int = target.y - unit.y
			var dist_sq: int = FP.add(FP.mul(dx, dx), FP.mul(dy, dy))
			var dist: int = FP.sqrt_fp(dist_sq)
			if dist > 0:
				var ms: int = FP.min_fp(speed, dist)
				move_dx = FP.div(FP.mul(dx, ms), dist)
				move_dy = FP.div(FP.mul(dy, ms), dist)

	if unit.target_id == -1:
		# No target — march toward enemy castle on Y-axis
		move_dy = -speed if unit.team == 0 else speed

	# Apply movement with preventive obstacle check (Clash Royale model):
	# Check destination BEFORE moving. If blocked, try alternatives.
	var new_x: int = FP.add(unit.x, move_dx)
	var new_y: int = FP.add(unit.y, move_dy)
	new_x = FP.clamp_fp(new_x, FP.from_int(ARENA_LEFT), FP.from_int(ARENA_RIGHT))

	if not _is_inside_obstacle(new_x, new_y, unit):
		# Clear path — move
		unit.x = new_x
		unit.y = new_y
	elif not _is_inside_obstacle(unit.x, new_y, unit):
		# X blocked, Y clear — slide vertically
		unit.y = new_y
	elif not _is_inside_obstacle(new_x, unit.y, unit):
		# Y blocked, X clear — slide horizontally
		unit.x = new_x
	# else: fully blocked — stay put (stuck detection will handle)


func _perform_attack(attacker: Dictionary, target: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# --- Evasion (Berserker second skill): chance to dodge entirely ---
	if target.get("skill_id_2", &"") == &"evasion":
		if rng.range_int(1, 100) <= target.skill_param_3:
			events.append({"type": "skill_proc", "unit_id": target.id, "skill": "evasion"})
			return events  # Attack missed — no damage

	var multiplier: int = damage_table[attacker.attack_type][target.armor_type]
	var raw_damage: int = FP.mul(attacker.attack_damage, multiplier)

	# Blood Altar buff: +10% damage per altar on attacker's team
	var altar_bonus: int = attacker.get("altar_damage_bonus", FP.ZERO)
	if altar_bonus > 0:
		raw_damage = FP.add(raw_damage, FP.mul(raw_damage, altar_bonus))

	# Blood Rage (Blood Totem active): +25% damage for attacker
	if attacker.get("blood_rage_active", false):
		raw_damage = FP.add(raw_damage, FP.div(FP.mul(raw_damage, FP.from_int(25)), FP.from_int(100)))

	# Battle Cry buff: +15% damage
	if attacker.get("battle_cry_bonus", false):
		raw_damage = FP.add(raw_damage, FP.div(FP.mul(raw_damage, FP.from_int(15)), FP.from_int(100)))

	# Critical Strike (Axe Thrower second skill): chance for multiplied damage
	if attacker.get("skill_id_2", &"") == &"critical_strike":
		if rng.range_int(1, 100) <= attacker.skill_param_3:
			raw_damage = FP.div(FP.mul(raw_damage, FP.from_int(attacker.skill_param_4)), FP.from_int(100))
			events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "critical_strike"})

	# Siege Momentum (Catapult second skill): +5% damage per 2 cells of distance
	if attacker.get("skill_id_2", &"") == &"siege_momentum":
		var dist: int = FP.sqrt_fp(_distance_squared_2d(attacker, target))
		var cells_away: int = FP.to_int(FP.div(dist, FP.from_int(CELL_SIZE_PX)))
		var bonus_pct: int = mini((cells_away / 2) * attacker.skill_param_3, attacker.skill_param_4)
		if bonus_pct > 0:
			raw_damage = FP.add(raw_damage, FP.div(FP.mul(raw_damage, FP.from_int(bonus_pct)), FP.from_int(100)))

	# WC3-style percentage armor reduction: damage / (1 + armor * 0.06)
	var defense: int
	if attacker.attack_type == 2:  # Magic
		defense = target.get("magic_defense", FP.ZERO)
	else:
		defense = target.armor
	# Armory + Devotion Aura armor bonuses
	defense = FP.add(defense, target.get("armory_armor", FP.ZERO))
	defense = FP.add(defense, target.get("devotion_armor", FP.ZERO))

	# Piercing Shot (Archer second skill): chance to ignore armor entirely
	if attacker.get("skill_id_2", &"") == &"piercing_shot":
		if rng.range_int(1, 100) <= attacker.skill_param_3:
			defense = FP.ZERO
			events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "piercing_shot"})

	var final_damage: int
	if defense > 0:
		var armor_bonus: int = FP.div(FP.mul(defense, FP.from_int(6)), FP.from_int(100))
		var armor_factor: int = FP.add(FP.ONE, armor_bonus)
		final_damage = FP.div(raw_damage, armor_factor)
	else:
		final_damage = raw_damage
	final_damage = FP.max_fp(final_damage, FP.ONE)

	# --- On-hit skill: Shield Wall (target) ---
	# Footman: -15% Pierce damage when HP > threshold% (param_2/1000)
	if target.get("skill_id", &"") == &"shield_wall" and attacker.attack_type == 1:
		var hp_threshold: int = FP.div(FP.mul(target.max_hp, FP.from_int(target.skill_param_2)), FP.from_int(1000))
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

	# --- Blood Rage vulnerability: target takes +10% damage ---
	if target.get("blood_rage_active", false):
		final_damage = FP.add(final_damage, FP.div(FP.mul(final_damage, FP.from_int(10)), FP.from_int(100)))

	# --- Mana Shield (Priest second skill): absorb damage ---
	var shield_hp: int = target.get("mana_shield_hp", FP.ZERO)
	if FP.gt(shield_hp, FP.ZERO):
		if FP.gte(shield_hp, final_damage):
			target["mana_shield_hp"] = FP.sub(shield_hp, final_damage)
			final_damage = FP.ZERO
			events.append({"type": "skill_proc", "unit_id": target.id, "skill": "mana_shield"})
		else:
			final_damage = FP.sub(final_damage, shield_hp)
			target["mana_shield_hp"] = FP.ZERO
			events.append({"type": "skill_proc", "unit_id": target.id, "skill": "mana_shield_break"})

	# --- Arcane Shield (Mage second skill): absorb first N points of MAGIC damage, one-time ---
	if attacker.attack_type == 2:
		var arcane_hp: int = target.get("arcane_shield_hp", FP.ZERO)
		if FP.gt(arcane_hp, FP.ZERO):
			if FP.gte(arcane_hp, final_damage):
				target["arcane_shield_hp"] = FP.sub(arcane_hp, final_damage)
				final_damage = FP.ZERO
				events.append({"type": "skill_proc", "unit_id": target.id, "skill": "arcane_shield"})
			else:
				final_damage = FP.sub(final_damage, arcane_hp)
				target["arcane_shield_hp"] = FP.ZERO
				events.append({"type": "skill_proc", "unit_id": target.id, "skill": "arcane_shield_break"})

	target.hp = FP.sub(target.hp, final_damage)

	events.append({
		"type": "unit_attacked",
		"attacker_id": attacker.id,
		"target_id": target.id,
		"damage": final_damage,
		"target_hp": target.hp,
		# Position rides in the payload so the dispatcher never re-looks-up the
		# target — a lethal hit removes the entity in _cleanup_dead the same step.
		"target_x": target.x,
		"target_y": target.y,
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
				events.append({"type": "unit_attacked", "attacker_id": attacker.id, "target_id": other.id, "damage": splash_dmg, "target_hp": other.hp, "target_x": other.x, "target_y": other.y})

	# --- On-hit skill: Fireball (attacker) ---
	# Mage (T-084): param_1‰ splash to enemies within param_2 pixels of target. Magic-typed.
	if attacker.get("skill_id", &"") == &"fireball":
		var fb_range_sq: int = FP.mul(FP.from_int(attacker.skill_param_2), FP.from_int(attacker.skill_param_2))
		var fb_dmg: int = FP.div(FP.mul(final_damage, FP.from_int(attacker.skill_param_1)), FP.from_int(1000))
		fb_dmg = FP.max_fp(fb_dmg, FP.ONE)
		var fb_hit_ids: Array = []
		for other in entities:
			if other.type != "unit" or other.team == attacker.team or other.id == target.id:
				continue
			if FP.lte(other.hp, FP.ZERO):
				continue
			if FP.lte(_distance_squared_2d(target, other), fb_range_sq):
				other.hp = FP.sub(other.hp, fb_dmg)
				fb_hit_ids.append(other.id)
				events.append({"type": "unit_attacked", "attacker_id": attacker.id, "target_id": other.id, "damage": fb_dmg, "target_hp": other.hp, "target_x": other.x, "target_y": other.y})
		if fb_hit_ids.size() > 0:
			events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "fireball", "targets": fb_hit_ids, "center_x": target.x, "center_y": target.y})

	# --- Cleave (legacy second skill): 30% splash to enemies near target ---
	if attacker.get("skill_id_2", &"") == &"cleave":
		var cleave_range: int = FP.from_int(attacker.skill_param_4)
		var cleave_range_sq: int = FP.mul(cleave_range, cleave_range)
		var cleave_dmg: int = FP.div(FP.mul(final_damage, FP.from_int(attacker.skill_param_3)), FP.from_int(100))
		cleave_dmg = FP.max_fp(cleave_dmg, FP.ONE)
		for other in entities:
			if other.type != "unit" or other.team == attacker.team or other.id == target.id:
				continue
			if FP.lte(other.hp, FP.ZERO):
				continue
			if FP.lte(_distance_squared_2d(target, other), cleave_range_sq):
				other.hp = FP.sub(other.hp, cleave_dmg)
				events.append({"type": "unit_attacked", "attacker_id": attacker.id, "target_id": other.id, "damage": cleave_dmg, "target_hp": other.hp, "target_x": other.x, "target_y": other.y})

	# --- Lance Pierce (T-076): line attack from lancer through target. Damages every
	# enemy in a narrow rectangle along the attacker→target direction, extending up to
	# attack_range past the target. Damage falloff: primary=100% (already applied above),
	# 1st secondary = falloff%, 2nd = falloff%², ... in distance order from attacker.
	# skill_param_3 = pierce width in px (20). skill_param_4 = falloff % per target (70).
	if attacker.get("skill_id_2", &"") == &"lance_pierce":
		var dx_fp: int = FP.sub(target.x, attacker.x)
		var dy_fp: int = FP.sub(target.y, attacker.y)
		var dir_len_sq: int = FP.add(FP.mul(dx_fp, dx_fp), FP.mul(dy_fp, dy_fp))
		if dir_len_sq > 0:
			var dir_len: int = FP.sqrt_fp(dir_len_sq)
			var max_proj: int = FP.add(dir_len, attacker.attack_range)
			var half_w: int = FP.from_int(attacker.skill_param_3) / 2  # half-width in FP
			var half_w_sq: int = FP.mul(half_w, half_w)
			var falloff_pct: int = attacker.skill_param_4
			# Collect candidate hits with their projection along the line
			var lp_hits: Array = []
			for other in entities:
				if other.type != "unit" or other.team == attacker.team or other.id == target.id:
					continue
				if FP.lte(other.hp, FP.ZERO):
					continue
				var rel_x: int = FP.sub(other.x, attacker.x)
				var rel_y: int = FP.sub(other.y, attacker.y)
				# Unnormalized projection: dot product of rel and dir vectors
				var dot_fp: int = FP.add(FP.mul(rel_x, dx_fp), FP.mul(rel_y, dy_fp))
				if dot_fp <= 0:
					continue  # behind the attacker
				# Normalized signed distance along the line
				var proj_fp: int = FP.div(dot_fp, dir_len)
				if proj_fp >= max_proj:
					continue  # past the line's far end
				# Perpendicular distance² = |rel|² - proj²
				var rel_sq: int = FP.add(FP.mul(rel_x, rel_x), FP.mul(rel_y, rel_y))
				var proj_sq: int = FP.mul(proj_fp, proj_fp)
				var perp_sq: int = FP.sub(rel_sq, proj_sq)
				if perp_sq < 0:
					perp_sq = 0  # numerical safety
				if perp_sq >= half_w_sq:
					continue  # outside the line rectangle
				lp_hits.append({"id": other.id, "proj": proj_fp, "entity": other})
			# Sort hits by distance from attacker (closest first)
			lp_hits.sort_custom(func(a, b): return a.proj < b.proj)
			# Apply damage with geometric falloff
			var lp_dmg: int = final_damage
			var lp_target_ids: Array = [target.id]  # primary first, secondaries follow
			for hit in lp_hits:
				lp_dmg = FP.div(FP.mul(lp_dmg, FP.from_int(falloff_pct)), FP.from_int(100))
				lp_dmg = FP.max_fp(lp_dmg, FP.ONE)
				var hit_other: Dictionary = hit.entity
				hit_other.hp = FP.sub(hit_other.hp, lp_dmg)
				lp_target_ids.append(hit.id)
				events.append({"type": "unit_attacked", "attacker_id": attacker.id, "target_id": hit.id, "damage": lp_dmg, "target_hp": hit_other.hp, "target_x": hit_other.x, "target_y": hit_other.y})
			if lp_hits.size() > 0:
				events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "lance_pierce", "targets": lp_target_ids})

	# --- Burning Ground (Demolisher second skill): leave fire zone at impact ---
	if attacker.get("skill_id_2", &"") == &"burning_ground":
		var fire_radius: int = FP.from_int(CELL_SIZE_PX)
		fire_zones.append({
			"x": target.x,
			"y": target.y,
			"radius_sq": FP.mul(fire_radius, fire_radius),
			"damage": FP.from_int(attacker.skill_param_4),
			"ticks_remaining": attacker.skill_param_3,
			"team": attacker.team,
		})
		events.append({"type": "skill_proc", "unit_id": attacker.id, "skill": "burning_ground"})

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
		"target_x": best_entity.x,
		"target_y": best_entity.y,
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

	# --- Second skills (check both slots for T3 units that reuse skills) ---
	var sid2: StringName = unit.get("skill_id_2", &"")

	# Enrage: +attack speed when HP < threshold% (can be on either slot)
	var has_enrage: bool = (sid == &"enrage" or sid2 == &"enrage") and not unit.get("skill_2_active", false)
	if has_enrage:
		var on_s1: bool = sid == &"enrage"
		var e_pct: int = unit.skill_param_1 if on_s1 else unit.skill_param_3
		var e_spd: int = unit.skill_param_2 if on_s1 else unit.skill_param_4
		var threshold: int = FP.div(FP.mul(unit.max_hp, FP.from_int(e_pct)), FP.from_int(100))
		if FP.lt(unit.hp, threshold) and e_spd > 0:
			unit["skill_2_active"] = true
			var reduction: int = maxi(1, unit.attack_speed_ticks * e_spd / 100)
			unit.attack_speed_ticks = maxi(1, unit.attack_speed_ticks - reduction)
			events.append({"type": "skill_proc", "unit_id": unit.id, "skill": "enrage"})

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
			if FP.lte(_distance_squared_2d(entity, other), range_sq):
				other.hp = FP.sub(other.hp, volley_dmg)
				events.append({"type": "unit_attacked", "attacker_id": entity.id, "target_id": other.id, "damage": volley_dmg, "target_hp": other.hp, "target_x": other.x, "target_y": other.y})
				targets_hit += 1
		if targets_hit > 0:
			events.append({"type": "skill_proc", "unit_id": entity.id, "skill": "volley"})

	# Charge first-hit bonus (Knight): param_1% damage on first attack
	if entity.get("charge_damage_ready", false):
		entity.charge_damage_ready = false
		# The attack already happened in _perform_attack, so apply bonus damage to last target
		if entity.target_id != -1:
			var target = _find_entity_by_id(entity.target_id)
			if target and FP.gt(target.hp, FP.ZERO):
				var bonus: int = FP.div(FP.mul(entity.attack_damage, FP.from_int(entity.skill_param_1)), FP.from_int(100))
				target.hp = FP.sub(target.hp, bonus)
				events.append({"type": "unit_attacked", "attacker_id": entity.id, "target_id": target.id, "damage": bonus, "target_hp": target.hp, "target_x": target.x, "target_y": target.y})
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

	# Any unit within castle attack range damages the castle — independent of target_id
	# Range = max(attack_range, 84px) + 1-cell buffer (matches stop check in _update_units)
	var enemy_team: int = 1 - unit.team
	# Castle uses same attack_range as buildings — no special inflation
	var range_sq: int = FP.mul(unit.attack_range, unit.attack_range)

	# Find the enemy castle entity
	var target = null
	for ce in entities:
		if ce.type == "castle" and ce.team == enemy_team:
			target = ce
			break
	if target == null:
		return events

	# T-096: castle uses the SAME edge-distance formula as buildings + _in_attack_range.
	# grid_size_x=5, grid_size_y=2 → hw=70, hh=28. Range check now includes X too
	# so flanking attackers hit the castle from the side when unblocked.
	var hw: int = FP.from_int(target.get("grid_size_x", 2) * CELL_SIZE_PX / 2)
	var hh: int = FP.from_int(target.get("grid_size_y", 2) * CELL_SIZE_PX / 2)
	var dx: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(unit.x, target.x)), hw), FP.ZERO)
	var dy: int = FP.max_fp(FP.sub(FP.abs_fp(FP.sub(unit.y, target.y)), hh), FP.ZERO)
	var edge_dist_sq: int = FP.add(FP.mul(dx, dx), FP.mul(dy, dy))
	if not FP.lte(edge_dist_sq, range_sq):
		return events
	if unit.attack_cooldown > 0:
		return events

	var castle: Dictionary = castles[enemy_team]
	if FP.lte(castle.hp, FP.ZERO):
		return events

	var multiplier: int = damage_table[unit.attack_type][3]  # Fortified
	var raw_damage: int = FP.mul(unit.attack_damage, multiplier)
	var final_damage: int = FP.max_fp(raw_damage, FP.ONE)

	# Siege Fire (Demolisher): +25% castle damage + burn
	if unit.get("skill_id", &"") == &"siege_fire":
		final_damage = FP.div(FP.mul(final_damage, FP.from_int(unit.skill_param_1)), FP.from_int(1000))
		castle["burn_timer"] = unit.skill_param_2
		castle["burn_damage"] = FP.from_int(5)

	castle.hp = FP.sub(castle.hp, final_damage)
	target.hp = castle.hp  # Sync entity HP with castle dict
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
	var dirty_flow: Array = [false, false]
	for i in range(entities.size() - 1, -1, -1):
		var entity: Dictionary = entities[i]
		if entity.type == "castle":
			continue  # Castles don't get removed — win condition handles them
		if FP.lte(entity.get("hp", FP.ONE), FP.ZERO):
			# Track kill stat
			if entity.type == "unit":
				var enemy_team: int = 1 - entity.get("team", 0)
				if enemy_team >= 0 and enemy_team < 2:
					units_killed[enemy_team] += 1
			events.append({
				"type": "entity_died",
				"id": entity.id,
				"entity_type": entity.type,
				"team": entity.get("team", -1),
				"x": entity.get("x", 0),
				"y": entity.get("y", 0),
				# Payload must be self-contained: the entity is removed below,
				# BEFORE the dispatcher runs, so re-lookups always miss.
				"bounty": entity.get("bounty", 0),
				"reason": "killed",
			})
			# Kill bounty: award gold to the opposing team's players (Pillage perk: +50%)
			if entity.type == "unit":
				var bounty: int = entity.get("bounty", 0)
				if bounty > 0:
					var enemy_team: int = 1 - entity.team
					for player in players:
						if player.team == enemy_team:
							var pi: int = players.find(player)
							var bounty_fp: int = _perk_bounty(FP.from_int(bounty), pi)
							player.gold = FP.add(player.gold, bounty_fp)
							events.append({
								"type": "gold_changed",
								"player_id": player.id,
								"new_gold": player.gold,
							})
			# Unregister unit from occupancy grid before removal
			if entity.type == "unit":
				_unregister_unit_cell(entity)
			# If building, clear grid cells and remove income bonus
			if entity.type == "building":
				# Income computed dynamically — no flat tracking to remove
				var grid: Array = grid_cells[entity.player_index]
				for row in range(entity.grid_y, entity.grid_y + entity.grid_size_y):
					for col in range(entity.grid_x, entity.grid_x + entity.grid_size_x):
						grid[row][col] = -1
				if entity.player_index < dirty_flow.size():
					dirty_flow[entity.player_index] = true
			entities.remove_at(i)
	# Batch rebuild flow fields for grids that changed
	for pi in dirty_flow.size():
		if dirty_flow[pi]:
			_rebuild_flow_field(pi)
	return events
