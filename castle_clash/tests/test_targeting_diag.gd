## Diagnostic test: reproduces exact user-reported bugs.
## Bug 1: Units go straight to castle, ignoring enemies
## Bug 2: Units walk past enemy buildings/castle instead of attacking
extends SceneTree

var pass_count: int = 0
var fail_count: int = 0
var failed_tests: Array = []

func _init() -> void:
	print("\n=== TARGETING DIAGNOSTIC: Reproducing User-Reported Bugs ===\n")

	_test_units_engage_enemies_not_castle()
	_test_units_attack_when_in_range()
	_test_units_dont_walk_past_buildings()
	_test_units_attack_castle_when_in_range()
	_test_castle_always_target_fallback()
	_test_chase_to_attack_transition()

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


func _create_sim(seed_val: int = 42) -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
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


## BUG 1: "Going straight to castle" — units should engage enemy troops when nearby.
## The real bug: a unit targeting the castle WHILE an enemy is within aggro range.
## Targeting castle with no enemies nearby = correct (attack-move toward objective).
func _test_units_engage_enemies_not_castle() -> void:
	print("[BUG1: Units ignore nearby enemies to go to castle]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	# Track: how many ticks does a unit target the castle WHILE an enemy is within aggro range?
	var castle_target_with_enemy_nearby: int = 0
	var total_checks: int = 0

	for i in 800:
		sim.step([])
		for e in sim.entities:
			if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
				continue
			if e.target_id == -1:
				continue
			# Check if targeting castle
			var tgt = null
			for other in sim.entities:
				if other.id == e.target_id:
					tgt = other
					break
			if tgt == null or tgt.type != "castle":
				continue
			# Targeting castle — check if any enemy unit is within aggro range
			var aggro_sq: int = FP.mul(e.aggro_range, e.aggro_range)
			var has_nearby_enemy: bool = false
			for other in sim.entities:
				if other.type != "unit" or other.team == e.team or FP.lte(other.hp, FP.ZERO):
					continue
				var dx: int = e.x - other.x
				var dy: int = e.y - other.y
				var dist_sq: int = FP.mul(dx, dx) + FP.mul(dy, dy)
				if FP.lte(dist_sq, aggro_sq):
					has_nearby_enemy = true
					break
			total_checks += 1
			if has_nearby_enemy:
				castle_target_with_enemy_nearby += 1

	print("  Castle-targeting ticks: %d total, %d with enemy in aggro range" % [total_checks, castle_target_with_enemy_nearby])
	_assert(castle_target_with_enemy_nearby == 0, "no ticks targeting castle with enemy in aggro range (%d)" % castle_target_with_enemy_nearby)


## BUG 2: "Walking instead of attacking when in range"
## Setup: Spawn units, let them reach enemies. Check that units in attack range
## are in ATTACK state, not MARCH or CHASE.
func _test_units_attack_when_in_range() -> void:
	print("\n[BUG2: Units walk past enemies instead of attacking]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	for i in 500:
		sim.step([])

	# Find pairs: unit + its target. Check if in attack range but still moving.
	var in_range_but_moving: int = 0
	var in_range_attacking: int = 0
	var in_range_total: int = 0

	for e in sim.entities:
		if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
			continue
		if e.target_id == -1:
			continue
		var tgt = null
		for other in sim.entities:
			if other.id == e.target_id:
				tgt = other
				break
		if tgt == null or FP.lte(tgt.hp, FP.ZERO):
			continue
		if tgt.type == "castle":
			continue  # Castle range is different

		var dist_sq: int = FP.mul(e.x - tgt.x, e.x - tgt.x) + FP.mul(e.y - tgt.y, e.y - tgt.y)
		var range_sq: int = FP.mul(e.attack_range, e.attack_range)
		if FP.lte(dist_sq, range_sq):
			in_range_total += 1
			var state: int = e.get("state", 0)
			if state == 2:  # ATTACK
				in_range_attacking += 1
			elif e.get("is_moving", false):
				in_range_but_moving += 1
				print("    Walking-in-range: %s #%d (team %d) state=%d, is_moving=%s, dist_sq=%d, range_sq=%d" % [
					e.unit_type, e.id, e.team, state, e.get("is_moving", false), dist_sq, range_sq])

	print("  In range of target: %d — %d attacking, %d still walking" % [in_range_total, in_range_attacking, in_range_but_moving])
	_assert(in_range_but_moving == 0, "no units walking while in attack range (%d are)" % in_range_but_moving)


## Units should not walk past enemy buildings without engaging.
func _test_units_dont_walk_past_buildings() -> void:
	print("\n[Units don't walk past enemy buildings]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	# Place buildings at grid edges so units march through them
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(0, &"barracks", 4, 0),
		Command.place_building(1, &"war_camp", 0, 0),
		Command.place_building(1, &"war_camp", 4, 0),
	])

	for i in 800:
		sim.step([])

	# Check: are any team 0 units past the enemy buildings (deep in enemy build zone)
	# without targeting a building or enemy unit?
	var past_enemy_buildings_no_engage: int = 0
	for e in sim.entities:
		if e.type != "unit" or e.team != 0 or FP.lte(e.hp, FP.ZERO):
			continue
		var py: int = FP.to_int(e.y)
		if py < 200:  # Deep in enemy build zone (past most buildings)
			if e.target_id == -1:
				past_enemy_buildings_no_engage += 1
				print("    No-target deep: %s #%d at Y=%d state=%d" % [e.unit_type, e.id, py, e.get("state", -1)])
			else:
				var tgt = null
				for other in sim.entities:
					if other.id == e.target_id:
						tgt = other
						break
				if tgt != null and tgt.type == "castle":
					# Targeting castle while buildings still alive — check if buildings exist
					var enemy_buildings_alive: int = 0
					for other in sim.entities:
						if other.type == "building" and other.team == 1 and FP.gt(other.hp, FP.ZERO):
							enemy_buildings_alive += 1
					if enemy_buildings_alive > 0:
						past_enemy_buildings_no_engage += 1
						print("    Castle-target with %d buildings alive: %s #%d at Y=%d" % [enemy_buildings_alive, e.unit_type, e.id, py])

	_assert(past_enemy_buildings_no_engage == 0, "no units bypass enemy buildings (%d do)" % past_enemy_buildings_no_engage)


## Units should start attacking the castle when they reach it, not just stand there.
func _test_units_attack_castle_when_in_range() -> void:
	print("\n[Units attack castle when in range]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	# Only player 0 builds — no enemies to distract
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
	])

	# Run long enough for units to reach enemy castle
	for i in 1500:
		sim.step([])

	var castle_hp: int = FP.to_int(sim.castles[1].hp)
	var units_sieging: int = 0
	var units_near_castle_not_sieging: int = 0

	for e in sim.entities:
		if e.type != "unit" or e.team != 0 or FP.lte(e.hp, FP.ZERO):
			continue
		var py: int = FP.to_int(e.y)
		var state: int = e.get("state", 0)
		if py < 130:  # Near enemy castle (Y=70)
			if state == 3:  # SIEGE
				units_sieging += 1
			else:
				units_near_castle_not_sieging += 1
				print("    Near castle not sieging: %s #%d at Y=%d state=%d target=%d is_moving=%s" % [
					e.unit_type, e.id, py, state, e.target_id, e.get("is_moving", false)])

	print("  Castle HP: %d (damaged=%s), sieging=%d, near-but-not-sieging=%d" % [
		castle_hp, castle_hp < 10000, units_sieging, units_near_castle_not_sieging])

	_assert(castle_hp < 10000, "castle takes damage (HP=%d)" % castle_hp)
	_assert(units_near_castle_not_sieging == 0, "all units near castle are sieging (%d not)" % units_near_castle_not_sieging)


## Castle should always be the fallback target — no unit should ever have target_id=-1.
func _test_castle_always_target_fallback() -> void:
	print("\n[Castle always fallback: no unit without target]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	var no_target_ticks: int = 0
	var total_checks: int = 0

	for i in 500:
		sim.step([])
		for e in sim.entities:
			if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
				continue
			total_checks += 1
			if e.target_id == -1:
				no_target_ticks += 1

	print("  Checked %d unit-ticks, %d had no target (%.1f%%)" % [
		total_checks, no_target_ticks, 100.0 * no_target_ticks / maxi(total_checks, 1)])
	# Some no-target ticks are OK right at spawn before first _acquire_target runs
	_assert(no_target_ticks < total_checks * 0.02, "< 2%% of unit-ticks without target (%d/%d)" % [no_target_ticks, total_checks])


## Units should transition through combat states (CHASE→ATTACK for units, CHASE→SIEGE for castle).
func _test_chase_to_attack_transition() -> void:
	print("\n[Units enter combat states (ATTACK or SIEGE)]")
	var sim := _create_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"war_camp", 0, 0),
	])

	# Track state transitions
	var ever_attacked: Dictionary = {}  # unit_id -> bool (ATTACK state = fighting unit/building)
	var ever_sieged: Dictionary = {}    # unit_id -> bool (SIEGE state = fighting castle)
	var ever_chased: Dictionary = {}

	for i in 800:
		sim.step([])
		for e in sim.entities:
			if e.type != "unit" or FP.lte(e.hp, FP.ZERO):
				continue
			var state: int = e.get("state", 0)
			if state == 1:  # CHASE
				ever_chased[e.id] = true
			if state == 2:  # ATTACK
				ever_attacked[e.id] = true
			if state == 3:  # SIEGE
				ever_sieged[e.id] = true

	var chased_count: int = ever_chased.size()
	var attacked_count: int = ever_attacked.size()
	var sieged_count: int = ever_sieged.size()
	var combat_count: int = 0
	for uid in ever_chased:
		if ever_attacked.has(uid) or ever_sieged.has(uid):
			combat_count += 1

	print("  %d chased, %d attacked units, %d sieged castle, %d reached combat" % [
		chased_count, attacked_count, sieged_count, combat_count])
	_assert(combat_count > 0, "units reached combat (ATTACK or SIEGE) from CHASE (%d)" % combat_count)
	_assert(sieged_count > 0, "some units entered SIEGE state (%d)" % sieged_count)
