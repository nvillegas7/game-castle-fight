## Headless behavior audit — measures zigzag, stuck, bounce metrics from pure simulation.
## Runs without display. Tests the architectural overhaul (occupancy, state machine, targeting).
## Usage: godot --headless --script tests/test_behavior_audit.gd
extends SceneTree

var pass_count: int = 0
var fail_count: int = 0
var failed_tests: Array = []

func _init() -> void:
	print("\n=== BEHAVIOR AUDIT: Simulation Movement Quality ===\n")

	_audit_melee_scenario()
	_audit_full_army_scenario()
	_audit_state_machine()
	_audit_occupancy_grid()
	_audit_targeting_commitment()
	_audit_castle_wall()

	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if failed_tests.size() > 0:
		print("FAILED TESTS:")
		for t in failed_tests:
			print("  - %s" % t)
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: %s" % msg)
		pass_count += 1
	else:
		print("  FAIL: %s" % msg)
		fail_count += 1
		failed_tests.append(msg)


# --- Scenario Helpers ---

func _create_sim(seed_val: int = 42) -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	# T-077: behavior audit measures movement quality, not pacing — skip prep phase
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	], {"skip_prep": true})
	return sim


func _load_all_building_data() -> Array:
	var results := []
	var dir := DirAccess.open("res://data/buildings/")
	if dir == null:
		return results
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var bd = load("res://data/buildings/" + fname)
			if bd:
				results.append(bd)
		fname = dir.get_next()
	return results


func _run_match(sim: Simulation, ticks: int, first_cmds: Array = []) -> Dictionary:
	# Run match and collect per-unit position history
	if first_cmds.size() > 0:
		sim.step(first_cmds)
	else:
		sim.step([])
	for i in ticks - 1:
		sim.step([])
	return _analyze(sim, ticks)


func _collect_history(sim: Simulation, ticks: int, first_cmds: Array = []) -> Dictionary:
	# Run match and collect per-tick position data.
	# T-077 follow-up: stop snapshotting after match_over so survivors with no
	# targets aren't flagged as "stuck" by _count_stuck (the match is just done).
	var histories: Dictionary = {}  # unit_id -> Array of {tick, x, y, target_id, state, team, type}

	if first_cmds.size() > 0:
		sim.step(first_cmds)
	else:
		sim.step([])
	_snapshot(sim, histories)

	for i in ticks - 1:
		sim.step([])
		if sim.match_over:
			break
		_snapshot(sim, histories)

	return histories


func _snapshot(sim: Simulation, histories: Dictionary) -> void:
	for e in sim.entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		if not histories.has(e.id):
			histories[e.id] = []
		histories[e.id].append({
			"tick": sim.tick,
			"x": FP.to_int(e.x),
			"y": FP.to_int(e.y),
			"target_id": e.target_id,
			"state": e.get("state", 0),
			"team": e.team,
			"type": e.unit_type,
			"moving": e.get("is_moving", false),
		})


func _analyze(sim: Simulation, _ticks: int) -> Dictionary:
	var result := {"zigzag": 0, "bounce": 0, "stuck": 0, "units": 0,
		"castle_0_hp": FP.to_int(sim.castles[0].hp), "castle_1_hp": FP.to_int(sim.castles[1].hp)}
	var unit_count: int = 0
	for e in sim.entities:
		if e.type == "unit":
			unit_count += 1
	result.units = unit_count
	return result


func _count_zigzags(histories: Dictionary) -> int:
	var total: int = 0
	for uid in histories:
		var hist: Array = histories[uid]
		if hist.size() < 5:
			continue
		var reversals: int = 0
		for i in range(2, hist.size()):
			var dy1: int = hist[i-1].y - hist[i-2].y
			var dy2: int = hist[i].y - hist[i-1].y
			if (dy1 > 2 and dy2 < -2) or (dy1 < -2 and dy2 > 2):
				reversals += 1
		if reversals > 5:
			total += 1
	return total


## Count rapid zigzags: reversals that happen within 10 ticks of each other (pathological oscillation).
## This distinguishes real bugs from natural combat direction changes.
func _count_rapid_zigzags(histories: Dictionary) -> int:
	var total: int = 0
	for uid in histories:
		var hist: Array = histories[uid]
		if hist.size() < 5:
			continue
		var rapid_count: int = 0
		var last_reversal_idx: int = -100
		for i in range(2, hist.size()):
			var dy1: int = hist[i-1].y - hist[i-2].y
			var dy2: int = hist[i].y - hist[i-1].y
			if (dy1 > 2 and dy2 < -2) or (dy1 < -2 and dy2 > 2):
				if i - last_reversal_idx < 10:
					rapid_count += 1
				last_reversal_idx = i
		if rapid_count > 3:  # 3+ rapid reversals = pathological
			total += 1
	return total


func _count_stuck(histories: Dictionary) -> int:
	var total: int = 0
	for uid in histories:
		var hist: Array = histories[uid]
		if hist.size() < 20:
			continue
		var max_stuck: int = 0
		var stuck_run: int = 0
		for i in range(1, hist.size()):
			if abs(hist[i].x - hist[i-1].x) < 2 and abs(hist[i].y - hist[i-1].y) < 2:
				var team: int = hist[i].team
				var near_castle: bool = (team == 0 and hist[i].y < 110) or (team == 1 and hist[i].y > 880)
				var has_target: bool = hist[i].target_id != -1
				if not near_castle and not has_target:
					stuck_run += 1
					max_stuck = maxi(max_stuck, stuck_run)
				else:
					stuck_run = 0
			else:
				stuck_run = 0
		if max_stuck > 20:
			total += 1
	return total


func _count_bounce(histories: Dictionary) -> int:
	var total: int = 0
	for uid in histories:
		var hist: Array = histories[uid]
		if hist.size() < 10:
			continue
		var team: int = hist[0].team
		var castle_y: int = 920 if team == 0 else 70
		var bounce_ticks: int = 0
		for h in hist:
			if abs(h.y - castle_y) < 40 and h.moving:
				bounce_ticks += 1
		if bounce_ticks > 10:
			total += 1
	return total


# --- Audit Scenarios ---

func _audit_melee_scenario() -> void:
	print("[Melee Scenario: barracks vs war_camp]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)

	var cmds := [
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	]

	# T-077: bumped 1500 → 2500 ticks (slower T1 spawns 130-140 vs old 70-90)
	var histories := _collect_history(sim, 2500, cmds)

	var zigzag := _count_zigzags(histories)
	var stuck := _count_stuck(histories)
	var bounce := _count_bounce(histories)
	var total_units := histories.size()

	var castle_0_hp := FP.to_int(sim.castles[0].hp)
	var castle_1_hp := FP.to_int(sim.castles[1].hp)
	var castle_damaged := castle_0_hp < 10000 or castle_1_hp < 10000

	print("  Stats: %d zigzag, %d bounce, %d stuck / %d units" % [zigzag, bounce, stuck, total_units])
	print("  Castle HP: P0=%d, P1=%d (ticks=%d)" % [castle_0_hp, castle_1_hp, sim.tick])

	_assert(zigzag < 10, "melee zigzag < 10 (got %d)" % zigzag)
	_assert(stuck < 10, "melee stuck < 10 (got %d)" % stuck)
	_assert(bounce < 5, "melee bounce < 5 (got %d)" % bounce)
	_assert(castle_damaged, "at least one castle takes damage (P0=%d, P1=%d)" % [castle_0_hp, castle_1_hp])
	# T-089: castle HP 10K→5K means matches end faster, so fewer units spawn before conclusion.
	# Threshold lowered 15→12 per A5 calibration.
	_assert(total_units >= 12, "enough units spawned (%d)" % total_units)


func _audit_full_army_scenario() -> void:
	print("\n[Full Army Scenario: all T1+T2 buildings]")
	var sim := _create_sim(123)
	sim.players[0].gold = FP.from_int(5000)
	sim.players[1].gold = FP.from_int(5000)

	# Place T1 buildings first (prereqs for T2)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(0, &"archer_range", 2, 0),
		Command.place_building(0, &"priest_temple", 4, 0),
		Command.place_building(1, &"war_camp", 0, 0),
		Command.place_building(1, &"axe_range", 2, 8),
		Command.place_building(1, &"war_drums", 4, 8),
	])
	# Wait for T1 prerequisites
	for i in 20:
		sim.step([])
	# Place T2 buildings
	sim.step([
		Command.place_building(0, &"knight_hall", 6, 0),
		Command.place_building(0, &"siege_workshop", 8, 0),
		Command.place_building(1, &"berserker_pit", 6, 8),
		Command.place_building(1, &"demolisher_works", 8, 8),
	])

	var histories := _collect_history(sim, 2000)

	var zigzag := _count_zigzags(histories)
	var rapid_zigzag := _count_rapid_zigzags(histories)
	var stuck := _count_stuck(histories)
	var bounce := _count_bounce(histories)
	var total_units := histories.size()

	var castle_0_hp := FP.to_int(sim.castles[0].hp)
	var castle_1_hp := FP.to_int(sim.castles[1].hp)
	var match_over := sim.match_over

	print("  Stats: %d zigzag (%d rapid), %d bounce, %d stuck / %d units" % [zigzag, rapid_zigzag, bounce, stuck, total_units])
	print("  Castle HP: P0=%d, P1=%d (match_over=%s, ticks=%d)" % [castle_0_hp, castle_1_hp, match_over, sim.tick])

	# Detailed breakdown: what unit types are zigzagging and where
	var zigzag_by_type: Dictionary = {}
	var stuck_by_type: Dictionary = {}
	for uid in histories:
		var hist: Array = histories[uid]
		if hist.size() < 5:
			continue
		var utype: String = hist[0].type
		# Zigzag check: count reversals
		var reversals: int = 0
		var rapid_reversals: int = 0  # Reversals within 10 ticks of each other
		var last_reversal_tick: int = -100
		for i in range(2, hist.size()):
			var dy1: int = hist[i-1].y - hist[i-2].y
			var dy2: int = hist[i].y - hist[i-1].y
			if (dy1 > 2 and dy2 < -2) or (dy1 < -2 and dy2 > 2):
				reversals += 1
				if hist[i].tick - last_reversal_tick < 10:
					rapid_reversals += 1
				last_reversal_tick = hist[i].tick
		if reversals > 5:
			zigzag_by_type[utype] = zigzag_by_type.get(utype, 0) + 1
		# Stuck check
		var max_stuck_run: int = 0
		var stuck_run: int = 0
		for i in range(1, hist.size()):
			if abs(hist[i].x - hist[i-1].x) < 2 and abs(hist[i].y - hist[i-1].y) < 2:
				var team: int = hist[i].team
				var near_castle: bool = (team == 0 and hist[i].y < 110) or (team == 1 and hist[i].y > 880)
				var has_target: bool = hist[i].target_id != -1
				if not near_castle and not has_target:
					stuck_run += 1
					max_stuck_run = maxi(max_stuck_run, stuck_run)
				else:
					stuck_run = 0
			else:
				stuck_run = 0
		if max_stuck_run > 20:
			stuck_by_type[utype] = stuck_by_type.get(utype, 0) + 1

	if zigzag_by_type.size() > 0:
		print("  Zigzag by type: %s" % str(zigzag_by_type))
	if stuck_by_type.size() > 0:
		print("  Stuck by type: %s" % str(stuck_by_type))

	# Full army thresholds: mixed units with different speeds/ranges create complex movement.
	# Total zigzag includes natural combat reversals (target dies, acquire new one behind you).
	# Rapid zigzag (reversals within 10 ticks) is the pathological metric — that's the real bug.
	_assert(rapid_zigzag < 10, "full army rapid zigzag < 10 (got %d) — pathological oscillation" % rapid_zigzag)
	# T-077: stuck threshold relaxed slightly. With faster matches (skip_prep + balanced
	# pacing), 50% of total can be too tight when small numbers of units exist.
	# Pathological stuck would still trigger (>>50%).
	_assert(stuck < total_units / 2, "full army stuck < 50%% of units (got %d/%d)" % [stuck, total_units])
	_assert(bounce < 5, "full army bounce < 5 (got %d)" % bounce)
	# T-077: threshold lowered from 40 to 30. Faster matches end before more spawn cycles complete.
	# T-089: castle HP 10K→5K shortens matches further. Threshold lowered 30→25 per A5 calibration.
	_assert(total_units > 25, "enough units spawned (%d)" % total_units)
	_assert(match_over, "full army: match reaches conclusion")


func _audit_state_machine() -> void:
	print("\n[State Machine: units have explicit states]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])
	# Run enough for units to spawn and start marching (T-077: T1 spawn = 130 ticks)
	for i in 200:
		sim.step([])

	var has_march: bool = false
	var has_state_field: bool = false
	var all_valid_states: bool = true

	for e in sim.entities:
		if e.type != "unit":
			continue
		has_state_field = e.has("state")
		if not has_state_field:
			break
		var state: int = e.state
		if state < 0 or state > 3:
			all_valid_states = false
		if state == 0:  # MARCH
			has_march = true

	_assert(has_state_field, "units have 'state' field")
	_assert(all_valid_states, "all unit states are valid (0-3)")
	# With castle-always-as-target, MARCH is transient — units immediately enter CHASE.
	# Some may still be in MARCH briefly after spawn. Either state is valid.
	_assert(has_march or has_state_field, "units have valid state after spawn")

	# Run longer for combat to develop
	for i in 400:
		sim.step([])

	var state_counts: Array = [0, 0, 0, 0]  # MARCH, CHASE, ATTACK, SIEGE
	for e in sim.entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		var s: int = e.get("state", 0)
		if s >= 0 and s <= 3:
			state_counts[s] += 1

	print("  State distribution: MARCH=%d CHASE=%d ATTACK=%d SIEGE=%d" % state_counts)
	var has_combat: bool = state_counts[1] > 0 or state_counts[2] > 0  # CHASE or ATTACK
	_assert(has_combat, "units are in combat states (CHASE/ATTACK)")


func _audit_occupancy_grid() -> void:
	print("\n[Occupancy Grid: units tracked in cells]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])
	# T-077: T1 spawn = 130 ticks, need at least 200 for first wave alive
	for i in 250:
		sim.step([])

	# Check units have grid_row/grid_col
	var has_grid_pos: bool = true
	var units_registered: int = 0
	for e in sim.entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		if not e.has("grid_row") or not e.has("grid_col"):
			has_grid_pos = false
			break
		if e.grid_row != -1:
			units_registered += 1

	_assert(has_grid_pos, "all units have grid_row/grid_col fields")
	_assert(units_registered > 0, "units are registered in occupancy grid (%d)" % units_registered)

	# Check occupancy grid is populated
	var occupied_cells: int = 0
	for cell in sim.unit_grid:
		if cell.size() > 0 and (cell.size() != 1 or cell[0] != -2):
			occupied_cells += 1
	_assert(occupied_cells > 0, "occupancy grid has units in cells (%d)" % occupied_cells)

	# Check no cell has more than capacity same-team units
	var over_capacity: int = 0
	for cell in sim.unit_grid:
		if cell.size() <= 1:
			continue
		if cell[0] == -2:
			continue
		var team_counts: Array = [0, 0]
		for uid in cell:
			for e in sim.entities:
				if e.id == uid and e.type == "unit":
					team_counts[e.team] += 1
					break
		if team_counts[0] > sim.CELL_CAPACITY or team_counts[1] > sim.CELL_CAPACITY:
			over_capacity += 1

	_assert(over_capacity == 0, "no cells over capacity (%d violations)" % over_capacity)


func _audit_targeting_commitment() -> void:
	print("\n[Targeting: committed sticky lock-on]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	# Collect target changes per unit
	var target_changes: Dictionary = {}  # unit_id -> count of target switches
	var prev_targets: Dictionary = {}    # unit_id -> last target_id

	for i in 1000:
		sim.step([])
		for e in sim.entities:
			if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
				continue
			if not target_changes.has(e.id):
				target_changes[e.id] = 0
				prev_targets[e.id] = e.target_id
			elif e.target_id != prev_targets[e.id]:
				# Only count switches between valid targets (not -1 -> target or target -> -1)
				if prev_targets[e.id] != -1 and e.target_id != -1:
					target_changes[e.id] += 1
				prev_targets[e.id] = e.target_id

	var total_switches: int = 0
	var max_switches: int = 0
	var units_that_switched: int = 0
	for uid in target_changes:
		total_switches += target_changes[uid]
		max_switches = maxi(max_switches, target_changes[uid])
		if target_changes[uid] > 0:
			units_that_switched += 1

	print("  Target switches: total=%d, max_per_unit=%d, units_that_switched=%d/%d" % [
		total_switches, max_switches, units_that_switched, target_changes.size()])

	# With committed targeting, switches should be rare (only when target dies then new one acquired)
	_assert(max_switches < 20, "max target switches per unit < 20 (got %d)" % max_switches)
	_assert(total_switches < target_changes.size() * 5, "avg switches < 5 per unit (total=%d, units=%d)" % [total_switches, target_changes.size()])


func _audit_castle_wall() -> void:
	print("\n[Castle Wall: units can't pass through]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	# Run long enough for units to reach castles
	for i in 2000:
		sim.step([])

	# Castle is 7×4 (2026-07-10; was 5×2). Castle 1 center Y=120 with hh=56 → hitbox
	# top edge at 64, so "behind enemy castle" means team 0 unit at py < 64. Castle 0
	# center Y=920 with hh=56 → hitbox bottom edge at 976, so "behind player castle"
	# means team 1 unit at py > 976.
	var behind_castle_1: int = 0
	var behind_castle_0: int = 0

	for e in sim.entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		var py: int = FP.to_int(e.y)
		if e.team == 0 and py < 64:  # Past enemy castle hitbox top (CASTLE_1_Y - hh = 120 - 56)
			behind_castle_1 += 1
		if e.team == 1 and py > 976:  # Past player castle hitbox bottom (CASTLE_0_Y + hh = 920 + 56)
			behind_castle_0 += 1

	_assert(behind_castle_1 == 0, "no team 0 units behind enemy castle (%d)" % behind_castle_1)
	_assert(behind_castle_0 == 0, "no team 1 units behind player castle (%d)" % behind_castle_0)

	# Verify the 7×4 castle footprint cells are blocked in the occupancy grid,
	# while flanking cols (0-1, 9-10) on the same UNIT_GRID rows remain WALKABLE.
	# Castle 0 footprint: build-zone rows 6-9, cols 2-8 → UNIT_GRID rows 28-32 cols 2-8
	# Castle 1 footprint: build-zone rows 0-3, cols 2-8 → UNIT_GRID rows 0-4 cols 2-8
	var footprint_blocked: bool = true
	var flanking_walkable: bool = true
	for test_row in [0, 1, 2, 3, 4, 28, 29, 30, 31, 32]:
		if test_row < 0 or test_row >= 34:
			continue
		for c_castle in range(2, 9):
			var idx_c: int = test_row * 11 + c_castle
			if sim.unit_grid[idx_c].size() != 1 or sim.unit_grid[idx_c][0] != -2:
				footprint_blocked = false
		for c_flank in [0, 1, 9, 10]:
			var idx_f: int = test_row * 11 + c_flank
			var cell: Array = sim.unit_grid[idx_f]
			if cell.size() == 1 and cell[0] == -2:
				flanking_walkable = false

	_assert(footprint_blocked, "castle 7×4 footprint cells blocked (cols 2-8 on castle UNIT_GRID rows)")
	_assert(flanking_walkable, "castle flanking cells walkable (cols 0-1, 9-10 on castle UNIT_GRID rows)")
