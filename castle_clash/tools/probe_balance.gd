## T-079 balance investigation: probe positional asymmetry between teams.
## Spawns identical buildings at symmetric positions and reports who hits the castle first.
## Run: godot --headless --path castle_clash -s tools/probe_balance.gd
extends SceneTree


func _init() -> void:
	await process_frame
	_run()
	quit(0)


func _load_buildings() -> Array:
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


func _run() -> void:
	print("\n=== T-079 Balance Probe ===\n")

	# --- Probe 1: spawn locations for symmetric placements ---
	print("[Probe 1: spawn coordinates for placement at gy=4]")
	var sim := Simulation.new()
	sim.register_buildings(_load_buildings())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)

	sim.step([
		Command.place_building(0, &"barracks", 4, 4),
		Command.place_building(1, &"barracks", 4, 4),
	])
	for e in sim.entities:
		if e.type == "building":
			print("  team %d barracks at grid (4,4) → pixel (%d, %d)" % [e.team, FP.to_int(e.x), FP.to_int(e.y)])

	# Step until both spawn at least one unit
	for i in 200:
		sim.step([])
	for e in sim.entities:
		if e.type == "unit":
			var dist_to_enemy_castle: int
			if e.team == 0:
				dist_to_enemy_castle = FP.to_int(e.y) - 70
			else:
				dist_to_enemy_castle = 920 - FP.to_int(e.y)
			print("  team %d %s at (%d, %d) — distance to enemy castle = %d px" % [
				e.team, e.unit_type, FP.to_int(e.x), FP.to_int(e.y), dist_to_enemy_castle])

	# --- Probe 2: castle wall asymmetry ---
	print("\n[Probe 2: castle wall blocked rows]")
	for row_offset in [-2, -1, 0, 1, 2]:
		var r0: int = 30 + row_offset  # castle 0 row
		var r1: int = 0 + row_offset   # castle 1 row
		var r0_blocked := "?"
		var r1_blocked := "?"
		if r0 >= 0 and r0 < 34:
			var idx := r0 * 11
			r0_blocked = "BLOCKED" if (sim.unit_grid[idx].size() == 1 and sim.unit_grid[idx][0] == -2) else "free"
		else:
			r0_blocked = "(off-grid)"
		if r1 >= 0 and r1 < 34:
			var idx := r1 * 11
			r1_blocked = "BLOCKED" if (sim.unit_grid[idx].size() == 1 and sim.unit_grid[idx][0] == -2) else "free"
		else:
			r1_blocked = "(off-grid)"
		print("  offset %+d: castle_0 row %d %s | castle_1 row %d %s" % [row_offset, r0, r0_blocked, r1, r1_blocked])

	# --- Probe 3: solo siege race — only player 0 has a barracks, then only player 1.
	# Compare who reaches the enemy castle faster from symmetric grid positions.
	print("\n[Probe 3a: Team 0 solo at gy=0 (front), no team 1, time to first castle hit]")
	var sim_a := Simulation.new()
	sim_a.register_buildings(_load_buildings())
	sim_a.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})
	sim_a.players[0].gold = FP.from_int(500)
	sim_a.step([Command.place_building(0, &"barracks", 4, 0)])  # gy=0 = front for team 0
	var c1_start_a := FP.to_int(sim_a.castles[1].hp)
	var c1_hit_tick := -1
	for i in 1000:
		sim_a.step([])
		if c1_hit_tick == -1 and FP.to_int(sim_a.castles[1].hp) < c1_start_a:
			c1_hit_tick = sim_a.tick
			break
	print("  team 0 barracks at gy=0 → first hit on castle 1 at tick %d (%.1fs)" % [c1_hit_tick, c1_hit_tick / 10.0])

	print("\n[Probe 3b: Team 1 solo at gy=8 (front), no team 0, time to first castle hit]")
	var sim_b := Simulation.new()
	sim_b.register_buildings(_load_buildings())
	sim_b.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})
	sim_b.players[1].gold = FP.from_int(500)
	sim_b.step([Command.place_building(1, &"barracks", 4, 8)])  # gy=8 = front for team 1
	var c0_start_b := FP.to_int(sim_b.castles[0].hp)
	var c0_hit_tick := -1
	for i in 1000:
		sim_b.step([])
		if c0_hit_tick == -1 and FP.to_int(sim_b.castles[0].hp) < c0_start_b:
			c0_hit_tick = sim_b.tick
			break
	print("  team 1 barracks at gy=8 → first hit on castle 0 at tick %d (%.1fs)" % [c0_hit_tick, c0_hit_tick / 10.0])

	# --- Probe 4: replicate test_balance progression with mirror army ---
	print("\n[Probe 4: Replicate test_balance.gd mirror progression — observe building placements]")
	var sim4 := Simulation.new()
	sim4.register_buildings(_load_buildings())
	sim4.initialize(12345, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {})  # NO skip_prep — match the real balance test
	sim4.players[0].gold = FP.from_int(0)
	sim4.players[1].gold = FP.from_int(0)
	var KINGDOM_ORDER: Array = [&"barracks", &"archer_range", &"gold_mine", &"barracks",
		&"priest_temple", &"guard_tower", &"knight_hall", &"siege_workshop", &"armory", &"war_horn"]
	var p0_idx := 0; var p1_idx := 0; var p0_pos := 0; var p1_pos := 0
	var building_costs := {}
	for bd in _load_buildings():
		building_costs[bd.id] = bd.gold_cost

	for tick_i in 6000:
		var cmds: Array = []
		if tick_i > 0 and tick_i % 30 == 0:
			if p0_idx < KINGDOM_ORDER.size():
				var btype: StringName = KINGDOM_ORDER[p0_idx]
				if FP.to_int(sim4.players[0].gold) >= building_costs.get(btype, 999):
					var gx: int = (p0_pos % 5) * 2
					var gy: int = (p0_pos / 5) * 2
					if sim4.can_place_building(0, btype, gx, gy):
						cmds.append(Command.place_building(0, btype, gx, gy))
						p0_idx += 1
					p0_pos = (p0_pos + 1) % 20
			if p1_idx < KINGDOM_ORDER.size():
				var btype: StringName = KINGDOM_ORDER[p1_idx]
				if FP.to_int(sim4.players[1].gold) >= building_costs.get(btype, 999):
					var gx: int = (p1_pos % 5) * 2
					var gy: int = (p1_pos / 5) * 2
					if sim4.can_place_building(1, btype, gx, gy):
						cmds.append(Command.place_building(1, btype, gx, gy))
						p1_idx += 1
					p1_pos = (p1_pos + 1) % 20
		sim4.step(cmds)
		# Periodic snapshot
		if tick_i % 200 == 0:
			var t0_units := 0; var t1_units := 0
			var t0_blds_alive := 0; var t1_blds_alive := 0
			for e in sim4.entities:
				if FP.lte(e.hp, FP.ZERO):
					continue
				if e.type == "unit":
					if e.team == 0: t0_units += 1
					else: t1_units += 1
				elif e.type == "building":
					if e.team == 0: t0_blds_alive += 1
					else: t1_blds_alive += 1
			print("  tick %4d: T0 units=%2d blds=%2d C0=%5d | T1 units=%2d blds=%2d C1=%5d" % [
				tick_i, t0_units, t0_blds_alive, FP.to_int(sim4.castles[0].hp),
				t1_units, t1_blds_alive, FP.to_int(sim4.castles[1].hp)])
		if sim4.match_over:
			break

	# Report building counts and positions per team
	var t0_blds := []
	var t1_blds := []
	for e in sim4.entities:
		if e.type == "building":
			var info := "%s gy=%d (y=%d)" % [str(e.building_type), e.grid_y, FP.to_int(e.y)]
			if e.team == 0:
				t0_blds.append(info)
			else:
				t1_blds.append(info)
	print("  Match over: %s, winner team %d, ticks %d" % [sim4.match_over, sim4.winning_team, sim4.tick])
	print("  Castle HP: P0=%d, P1=%d" % [FP.to_int(sim4.castles[0].hp), FP.to_int(sim4.castles[1].hp)])
	print("  Team 0 buildings (%d): %s" % [t0_blds.size(), str(t0_blds)])
	print("  Team 1 buildings (%d): %s" % [t1_blds.size(), str(t1_blds)])
