class_name ArenaAI
extends RefCounted

## Offline opponent AI — Phase 2.1: extracted VERBATIM from game_arena.gd's
## "Smart AI Opponent" block (behavior-preserving refactor; ends the A2/A5
## SHARED-file contention on game_arena.gd, mirrors what 2.2 did for terrain).
##
## Pure decision logic: think() reads a Simulation + snapshot params and RETURNS
## an Array of Command dictionaries (same order the original submitted them:
## activate → place → wall). No GameManager, no scene access, no global randi()
## — the RNG is injected, so headless suites (test_arena_ai.gd, test_balance.gd
## Mode B) can seed it and replay identical command streams.
##
## game_arena.gd keeps the scene-side concerns: the think timer, ai_disabled,
## is_online_match and tutorial pacing gates, and submitting the returned
## commands through GameManager (which queues them for current_tick + 1 — hence
## a single gold snapshot per think() is exact, not approximate).
##
## Known oddity preserved on purpose (behavior-neutral extraction): _place's
## "front/back" preference varies gx (the COLUMN), not gy (the row toward
## combat) — flagged for a future A5 balance task, not changed here.

var player_id: int
var strategy: int = -1  # 0=balanced, 1=rush, 2=tech — rolled on first think()
var _rng: RandomNumberGenerator


func _init(p_player_id: int, rng: RandomNumberGenerator) -> void:
	player_id = p_player_id
	_rng = rng


## One decision pass (the original _update_ai body after its scene gates).
## gold/match_time are snapshots; commands are returned, not submitted.
func think(sim: Simulation, faction: FactionData, gold: int, match_time: int) -> Array:
	var out: Array = []
	if sim == null or faction == null:
		return out
	var ai_index: int = sim.get_player_index(player_id)
	if ai_index == -1:
		return out

	# Pick strategy once per match
	if strategy == -1:
		strategy = _rng.randi() % 3

	# 1D-5: fire Castle Wrath (one-time panic ability) once own castle is at
	# or below the sim's 30-percent readiness threshold. Sim-side guards refuse
	# early fires; castle_wrath_available prevents re-emits after use.
	for castle in sim.castles:
		if castle.team == player_id and castle.get("castle_wrath_available", false):
			if FP.to_int(castle.hp) * 10 <= FP.to_int(castle.max_hp) * 3:
				out.append(Command.use_ability(player_id, &"castle_wrath", 0, 0))

	# Activate special building abilities when ready
	_try_activate(sim, ai_index, out)

	# Scan AI's buildings
	var ai_bld_count: int = 0
	var has_income: bool = false
	var has_t1: bool = false
	var has_upgrade: bool = false
	var has_special: bool = false
	var wall_count: int = 0
	for entity in sim.entities:
		if entity.type == "building" and entity.player_index == ai_index:
			ai_bld_count += 1
			var bt: StringName = entity.building_type
			var bd_c = sim.building_registry.get(bt)
			if bd_c and bd_c.income_bonus > 0: has_income = true
			if bd_c and bd_c.spawns_unit and bd_c.tier == 1: has_t1 = true
			if bt in [&"armory", &"blood_altar"]: has_upgrade = true
			if bt in [&"war_horn", &"blood_totem"]: has_special = true
			if bt in [&"wall", &"palisade"]: wall_count += 1

	# Affordable buildings (exclude walls from main selection)
	var affordable: Array[BuildingData] = []
	for bd: BuildingData in faction.buildings:
		if bd.gold_cost > gold:
			continue
		if bd.grid_size == Vector2i(1, 1) and not bd.spawns_unit and not bd.is_tower and bd.income_bonus == 0:
			continue  # Skip walls
		if bd.requires_building != &"" and not sim.player_has_building(ai_index, bd.requires_building):
			continue
		affordable.append(bd)

	# Scout player composition
	var p_melee: int = 0
	var p_ranged: int = 0
	var p_siege: int = 0
	for entity in sim.entities:
		if entity.type == "unit" and entity.team != player_id:
			match entity.role:
				0: p_melee += 1
				1: p_ranged += 1
				4: p_siege += 1

	var chosen: BuildingData = null

	# Strategy-based build order
	match strategy:
		0:  # Balanced
			if not has_income and ai_bld_count < 2:
				chosen = _pick(affordable, &"income")
			if chosen == null and ai_bld_count < 5:
				chosen = _pick(affordable, &"t1")
			if chosen == null and match_time > 350 and not has_upgrade:
				chosen = _pick(affordable, &"upgrade")
		1:  # Rush — spam T1 combat, no economy
			if ai_bld_count < 6:
				chosen = _pick(affordable, &"t1")
			if chosen == null and match_time > 400:
				chosen = _pick(affordable, &"t2")
		2:  # Tech — double income then T2
			if ai_bld_count < 2:
				chosen = _pick(affordable, &"income")
			if chosen == null and ai_bld_count < 4:
				chosen = _pick(affordable, &"t1")
			if chosen == null and match_time > 250:
				chosen = _pick(affordable, &"t2")
			if chosen == null and match_time > 400 and not has_special:
				chosen = _pick(affordable, &"special")

	# Counter-play (all strategies)
	if chosen == null and match_time > 200:
		if p_melee > p_ranged + 3:
			chosen = _pick(affordable, &"ranged")
			if chosen == null:
				chosen = _pick(affordable, &"tower")
		elif p_ranged > p_melee + 3:
			chosen = _pick(affordable, &"t2")
		elif p_siege > 1:
			chosen = _pick(affordable, &"t1")

	# Upgrade buildings when ahead on economy
	if chosen == null and match_time > 500 and gold > 150:
		if not has_upgrade:
			chosen = _pick(affordable, &"upgrade")
		elif not has_special:
			chosen = _pick(affordable, &"special")

	# Fallback: random combat building
	if chosen == null:
		var combat: Array[BuildingData] = []
		for bd: BuildingData in affordable:
			if bd.spawns_unit or bd.is_tower:
				combat.append(bd)
		if not combat.is_empty():
			chosen = combat[_rng.randi() % combat.size()]
		elif not affordable.is_empty():
			chosen = affordable[_rng.randi() % affordable.size()]
		else:
			return out

	var cmds_before_place: int = out.size()
	_place(sim, chosen, out)

	# Place maze walls periodically — but NEVER in the same think as a building
	# placement (T-AI1, 2026-07-18): both commands were validated against the
	# same pre-tick state and apply sequentially at tick+1, so the wall silently
	# no-oped whenever the building spent the gold or took the cells first
	# (measured 25% wasted commands for player 1 at seed 777). Deferring the
	# wall one think (~3s) re-validates it against fresh state and removes the
	# race entirely. Deliberate behavior change from the pre-extraction code.
	if out.size() == cmds_before_place \
			and wall_count < 4 and ai_bld_count > 3 and match_time > 300 and gold > 30:
		_place_wall(sim, ai_index, faction, gold, out)

	return out


func _pick(list: Array[BuildingData], cat: StringName) -> BuildingData:
	for bd: BuildingData in list:
		match cat:
			&"income":
				if bd.income_bonus > 0: return bd
			&"t1":
				if bd.spawns_unit and bd.tier == 1: return bd
			&"t2":
				if bd.spawns_unit and bd.tier == 2: return bd
			&"ranged":
				if bd.spawns_unit and bd.spawns_unit.role == 1: return bd
			&"tower":
				if bd.is_tower: return bd
			&"upgrade":
				if bd.id in [&"armory", &"blood_altar"]: return bd
			&"special":
				if bd.id in [&"war_horn", &"blood_totem"]: return bd
	return null


func _try_activate(sim: Simulation, ai_index: int, out: Array) -> void:
	for entity in sim.entities:
		if entity.type != "building" or entity.player_index != ai_index:
			continue
		var max_mana: int = entity.get("ability_max_mana", 0)
		if max_mana > 0 and entity.get("ability_mana", 0) >= max_mana:
			if entity.get("ability_active_ticks", 0) <= 0:
				out.append(Command.activate_building(player_id, entity.id))
				return


func _place_wall(sim: Simulation, ai_index: int, faction: FactionData, gold: int, out: Array) -> void:
	var wall_bd: BuildingData = null
	for bd: BuildingData in faction.buildings:
		if bd.grid_size == Vector2i(1, 1) and not bd.spawns_unit and not bd.is_tower and bd.income_bonus == 0:
			wall_bd = bd
			break
	# gold is the think() snapshot — identical to the live read the original did,
	# because submitted commands only apply at current_tick + 1.
	if wall_bd == null or gold < wall_bd.gold_cost:
		return
	# Zigzag walls: rows 2 and 5, alternating columns
	var positions := [[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[2,7],[2,8],
		[5,2],[5,3],[5,4],[5,5],[5,6],[5,7],[5,8],[5,9],[5,10]]
	for pos in positions:
		if sim.can_place_building(player_id, wall_bd.id, pos[1], pos[0]):
			out.append(Command.place_building(player_id, wall_bd.id, pos[1], pos[0]))
			return


func _place(sim: Simulation, chosen: BuildingData, out: Array) -> void:
	var prefer_front: bool = chosen.is_tower or chosen.spawns_unit != null
	var prefer_back: bool = chosen.income_bonus > 0
	for _attempt in 25:
		var gx: int
		if prefer_front:
			gx = (Simulation.GRID_COLS - chosen.grid_size.x) / 2 + _rng.randi() % maxi(1, (Simulation.GRID_COLS - chosen.grid_size.x + 2) / 2)
		elif prefer_back:
			gx = _rng.randi() % maxi(1, (Simulation.GRID_COLS - chosen.grid_size.x + 2) / 2)
		else:
			gx = _rng.randi() % maxi(1, Simulation.GRID_COLS - chosen.grid_size.x + 1)
		var gy: int = _rng.randi() % maxi(1, Simulation.GRID_ROWS - chosen.grid_size.y + 1)
		if sim.can_place_building(player_id, chosen.id, gx, gy):
			out.append(Command.place_building(player_id, chosen.id, gx, gy))
			return
