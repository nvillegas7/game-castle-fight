## Headless multiplayer & building interaction test runner.
## Tests: sync determinism, command round-trip, sell/radial flow, USE_ABILITY gap, grid edge cases.
## Run: godot --headless --path castle_clash -s tests/test_multiplayer.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []


func _init() -> void:
	await process_frame
	_run_tests()
	_print_results()
	quit(1 if _fail > 0 else 0)


func _run_tests() -> void:
	print("\n=== Multiplayer & Building Interaction Tests ===\n")

	_test_command_serialization_roundtrip()
	_test_sell_building_full_flow()
	_test_sell_nonexistent_building()
	_test_sell_opponent_building()
	_test_activate_building_command()
	_test_use_ability_command_gap()
	_test_deterministic_two_player_sync()
	_test_checksum_diverges_on_different_commands()
	_test_grid_special_cells_not_sellable()
	_test_building_lookup_by_entity_id()
	_test_radial_menu_entity_lookup()
	_test_concurrent_commands_both_players()
	_test_command_on_wrong_tick_ignored()
	_test_sell_during_combat()
	_test_place_and_sell_same_tick()
	_test_lockstep_tick_readiness()
	_test_stall_timeout_logic()
	_test_two_sim_json_wire_lockstep()
	_test_same_player_command_order_deterministic()
	_test_match_config_build_id_mismatch_aborts()
	_test_matchmaker_roster_validation()
	_test_match_config_seed_conflict_aborts()
	_test_commands_null_buffer_guard()
	_test_checksum_buffered_comparison()
	_test_match_config_perks_deterministic()
	_test_offline_match_survives_live_socket()
	_test_offline_match_survives_socket_drop()
	_test_offline_command_routing_with_live_socket()


func _assert(condition: bool, name: String) -> void:
	if condition:
		_pass += 1
		_results.append({"test": name, "status": "PASS"})
		print("  PASS: %s" % name)
	else:
		_fail += 1
		_results.append({"test": name, "status": "FAIL"})
		print("  FAIL: %s" % name)


# --- Helpers ---

func _create_test_sim(skip_prep: bool = true) -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": skip_prep} if skip_prep else {})
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


func _place_building(sim: Simulation, player_id: int, btype: StringName, gx: int, gy: int) -> Dictionary:
	"""Place a building and return the result from sim.step()."""
	return sim.step([Command.place_building(player_id, btype, gx, gy)])


func _find_building(sim: Simulation, btype: StringName, player_index: int = -1) -> Dictionary:
	"""Find first building of given type, optionally filtered by player."""
	for e in sim.entities:
		if e.type == "building" and e.building_type == btype:
			if player_index == -1 or e.player_index == player_index:
				return e
	return {}


# --- Command Serialization ---

func _test_command_serialization_roundtrip() -> void:
	print("[Command Serialization Round-Trip]")
	var nm = root.get_node_or_null("NetworkManager")
	_assert(nm != null, "NetworkManager autoload exists")
	if nm == null:
		return

	# Test all 4 command types survive serialize → deserialize
	var commands := [
		Command.place_building(0, &"barracks", 3, 4),
		Command.sell_building(1, 42),
		Command.use_ability(0, &"castle_wrath", 5, 6),
		Command.activate_building(1, 99),
	]

	var serialized: Array = nm._serialize_commands(commands)
	_assert(serialized.size() == 4, "serialized 4 commands")

	var deserialized: Array = nm._deserialize_commands(serialized)
	_assert(deserialized.size() == 4, "deserialized 4 commands")

	# PLACE_BUILDING round-trip
	var place: Dictionary = deserialized[0]
	_assert(place.type == Command.Type.PLACE_BUILDING, "place type preserved")
	_assert(place.player_id == 0, "place player_id preserved")
	_assert(place.building_type == &"barracks", "place building_type preserved")
	_assert(place.grid_x == 3, "place grid_x preserved")
	_assert(place.grid_y == 4, "place grid_y preserved")

	# SELL_BUILDING round-trip
	var sell: Dictionary = deserialized[1]
	_assert(sell.type == Command.Type.SELL_BUILDING, "sell type preserved")
	_assert(sell.player_id == 1, "sell player_id preserved")
	_assert(sell.building_id == 42, "sell building_id preserved")

	# USE_ABILITY round-trip
	var ability: Dictionary = deserialized[2]
	_assert(ability.type == Command.Type.USE_ABILITY, "ability type preserved")
	_assert(ability.player_id == 0, "ability player_id preserved")
	_assert(ability.ability_id == &"castle_wrath", "ability ability_id preserved")
	_assert(ability.target_x == 5, "ability target_x preserved")
	_assert(ability.target_y == 6, "ability target_y preserved")

	# ACTIVATE_BUILDING round-trip
	var activate: Dictionary = deserialized[3]
	_assert(activate.type == Command.Type.ACTIVATE_BUILDING, "activate type preserved")
	_assert(activate.building_id == 99, "activate building_id preserved")


# --- Sell Building Flow ---

func _test_sell_building_full_flow() -> void:
	print("[Sell Building: Full Flow]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Place a barracks
	_place_building(sim, 0, &"barracks", 3, 3)
	var bldg := _find_building(sim, &"barracks", 0)
	_assert(not bldg.is_empty(), "barracks placed for player 0")
	if bldg.is_empty():
		return

	var gold_before := FP.to_int(sim.players[0].gold)
	var bldg_id: int = bldg.id

	# Verify grid cell is occupied
	_assert(sim.grid_cells[0][3][3] == bldg_id, "grid cell stores building id (%d)" % bldg_id)

	# Sell it
	var result := sim.step([Command.sell_building(0, bldg_id)])
	var gold_after := FP.to_int(sim.players[0].gold)

	_assert(gold_after > gold_before, "gold refund received (%d → %d)" % [gold_before, gold_after])
	_assert(_find_building(sim, &"barracks", 0).is_empty(), "building removed from entities")
	_assert(sim.grid_cells[0][3][3] == -1, "grid cell cleared to -1 after sell")

	# Verify events emitted
	var has_destroyed := false
	var has_gold := false
	for ev in result.events:
		if ev.type == "building_destroyed" and ev.entity_id == bldg_id:
			has_destroyed = true
		if ev.type == "gold_changed" and ev.player_id == 0:
			has_gold = true
	_assert(has_destroyed, "building_destroyed event emitted")
	_assert(has_gold, "gold_changed event emitted")


func _test_sell_nonexistent_building() -> void:
	print("[Sell Building: Nonexistent ID]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Run a baseline tick to separate income effects from sell
	sim.step([])
	var gold_before := FP.to_int(sim.players[0].gold)

	# Sell a building ID that doesn't exist — should be a no-op (no refund, no building_destroyed)
	var result := sim.step([Command.sell_building(0, 9999)])

	# Check no building_destroyed event (income may still add gold, so don't check gold directly)
	var has_destroyed: bool = result.events.any(func(e): return e.type == "building_destroyed")
	_assert(not has_destroyed, "no building_destroyed event for nonexistent building")


func _test_sell_opponent_building() -> void:
	print("[Sell Building: Opponent's Building]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)

	# Player 1 places a building
	_place_building(sim, 1, &"barracks", 0, 2)
	var bldg := _find_building(sim, &"barracks", 1)
	_assert(not bldg.is_empty(), "player 1 placed a barracks")
	if bldg.is_empty():
		return

	var p0_gold_before := FP.to_int(sim.players[0].gold)

	# Player 0 tries to sell player 1's building — should fail
	sim.step([Command.sell_building(0, bldg.id)])
	var p0_gold_after := FP.to_int(sim.players[0].gold)

	_assert(p0_gold_before == p0_gold_after, "player 0 can't sell opponent's building")
	_assert(not _find_building(sim, &"barracks", 1).is_empty(), "opponent's building still exists")


# --- Activate Building ---

func _test_activate_building_command() -> void:
	print("[Activate Building Command]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Place a special building (war_drums has active ability)
	_place_building(sim, 0, &"war_drums", 0, 0)
	var bldg := _find_building(sim, &"war_drums", 0)
	_assert(not bldg.is_empty(), "war_drums placed")
	if bldg.is_empty():
		return

	# Activate it — should not crash
	var result := sim.step([Command.activate_building(0, bldg.id)])
	_assert(true, "activate_building command processed without crash")


# --- USE_ABILITY Gap (BUG: not processed in simulation) ---

func _test_use_ability_command_gap() -> void:
	print("[USE_ABILITY Command: Sync Gap]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Send a USE_ABILITY command — simulation should handle it (or at minimum not crash)
	var cmd := Command.use_ability(0, &"war_horn", 5, 5)
	_assert(cmd.type == Command.Type.USE_ABILITY, "USE_ABILITY command created")

	# This tests the CRITICAL sync bug: simulation._process_command() has no
	# match arm for USE_ABILITY. If both clients serialize/send this command
	# but the simulation silently drops it, that's OK for sync (both drop it).
	# But if any side-effect differs, it's a desync.
	var checksum_before := sim.compute_checksum()
	var result := sim.step([cmd])
	var checksum_after := sim.compute_checksum()

	# The command should be silently ignored (no match arm), tick still advances
	_assert(sim.tick == 1, "tick advanced despite unhandled USE_ABILITY")

	# Verify no events were generated from the unhandled command
	var ability_events: Array = result.events.filter(func(e): return e.type == "ability_used" or e.type == "skill_proc")
	_assert(ability_events.size() == 0, "USE_ABILITY silently dropped (no events) — known gap, both clients drop it so no desync")


# --- Determinism & Sync ---

func _test_deterministic_two_player_sync() -> void:
	print("[Determinism: Two-Player Sync]")
	# Simulate both players placing buildings and fighting — verify checksums match
	var commands_per_tick := []
	# Tick 0: both place barracks
	commands_per_tick.append([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"barracks", 0, 2),
	])
	# Tick 1: player 0 places archer range
	commands_per_tick.append([
		Command.place_building(0, &"archer_range", 2, 0),
	])
	# Tick 2: player 1 places archer range
	commands_per_tick.append([
		Command.place_building(1, &"archer_range", 2, 6),
	])

	# Run same scenario twice — must produce identical checksums
	var cs1 := _run_scenario(42, commands_per_tick, 300)
	var cs2 := _run_scenario(42, commands_per_tick, 300)
	_assert(cs1 == cs2, "identical scenarios produce identical checksums (%d)" % cs1)

	# Different player commands → different state
	var alt_commands := [commands_per_tick[0]]  # Only tick 0
	var cs3 := _run_scenario(42, alt_commands, 300)
	_assert(cs1 != cs3, "different commands produce different checksums (%d vs %d)" % [cs1, cs3])


func _test_checksum_diverges_on_different_commands() -> void:
	print("[Checksum: Divergence Detection]")
	# Simulate what happens when one player's command is missed (desync scenario)
	var sim_a := _create_test_sim()
	var sim_b := _create_test_sim()
	sim_a.players[0].gold = FP.from_int(500)
	sim_a.players[1].gold = FP.from_int(500)
	sim_b.players[0].gold = FP.from_int(500)
	sim_b.players[1].gold = FP.from_int(500)

	# Both get the same commands
	var cmd := [Command.place_building(0, &"barracks", 3, 3)]
	sim_a.step(cmd)
	sim_b.step(cmd)
	_assert(sim_a.compute_checksum() == sim_b.compute_checksum(), "same commands → same checksum at tick 1")

	# Sim A gets an extra sell command that Sim B misses (simulated desync)
	var bldg := _find_building(sim_a, &"barracks", 0)
	if not bldg.is_empty():
		sim_a.step([Command.sell_building(0, bldg.id)])
		sim_b.step([])  # B misses the command
		_assert(sim_a.compute_checksum() != sim_b.compute_checksum(), "missed command → checksum divergence (desync detected)")


# --- Grid Edge Cases ---

func _test_grid_special_cells_not_sellable() -> void:
	print("[Grid: Special Cells Not Sellable]")
	var sim := _create_test_sim()

	# T-096: Team 0 castle is at rows 8-9, cols 3-7 in grid_cells[0] (5×2 symmetric footprint)
	var castle_cell: int = sim.grid_cells[0][8][5]  # Center of castle
	_assert(castle_cell == Simulation.CASTLE_CELL_MARKER, "castle cell has marker -2 (got %d)" % castle_cell)

	# Try to sell castle marker (-2) as building_id — no entity has id=-2, so no-op
	var result_castle := sim.step([Command.sell_building(0, Simulation.CASTLE_CELL_MARKER)])
	var castle_destroyed: bool = result_castle.events.any(func(e): return e.type == "building_destroyed")
	_assert(not castle_destroyed, "can't sell castle cell marker — no building_destroyed event")

	# Try to sell terrain obstacle marker (-3) — also no-op
	var result_terrain := sim.step([Command.sell_building(0, Simulation.TERRAIN_OBSTACLE_MARKER)])
	var terrain_destroyed: bool = result_terrain.events.any(func(e): return e.type == "building_destroyed")
	_assert(not terrain_destroyed, "can't sell terrain obstacle marker — no building_destroyed event")


func _test_building_lookup_by_entity_id() -> void:
	print("[Building Lookup: Entity ID in Grid]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(1000)

	# Place multiple buildings
	_place_building(sim, 0, &"barracks", 0, 3)
	_place_building(sim, 0, &"archer_range", 2, 3)
	_place_building(sim, 0, &"gold_mine", 4, 3)

	var buildings := sim.entities.filter(func(e): return e.type == "building" and e.player_index == 0)
	_assert(buildings.size() >= 3, "3 buildings placed (%d found)" % buildings.size())

	# Each building's grid cells should store the correct entity ID
	for bldg in buildings:
		var grid_id: int = sim.grid_cells[0][bldg.grid_y][bldg.grid_x]
		_assert(grid_id == bldg.id, "grid[%d][%d] stores entity id %d (got %d) for %s" % [bldg.grid_y, bldg.grid_x, bldg.id, grid_id, bldg.building_type])

	# Verify empty cells are -1
	_assert(sim.grid_cells[0][5][5] == -1, "empty cell is -1")


func _test_radial_menu_entity_lookup() -> void:
	print("[Radial Menu: Entity Lookup from Grid]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	_place_building(sim, 0, &"barracks", 3, 3)
	var bldg := _find_building(sim, &"barracks", 0)
	_assert(not bldg.is_empty(), "building placed at (3,3)")
	if bldg.is_empty():
		return

	# Simulate what _try_show_radial does: read grid → find entity
	var grid: Array = sim.grid_cells[0]
	var entity_id: int = grid[3][3]
	_assert(entity_id != -1, "grid cell not empty (id=%d)" % entity_id)
	_assert(entity_id == bldg.id, "grid cell has correct entity id")

	# Entity lookup by ID (same as building_grid.gd lines 253-256)
	var found := {}
	for e in sim.entities:
		if e.id == entity_id:
			found = e
			break
	_assert(not found.is_empty(), "entity found by grid ID lookup")
	_assert(found.get("building_type", &"") == &"barracks", "found entity is barracks")

	# Verify castle cells don't resolve to real entities
	# Team 0 castle is at rows 7-9, cols 1-9
	var castle_id: int = grid[8][5]  # Castle marker at center
	_assert(castle_id == Simulation.CASTLE_CELL_MARKER, "castle cell is -2 (got %d)" % castle_id)
	var castle_entity := {}
	for e in sim.entities:
		if e.id == castle_id:
			castle_entity = e
			break
	_assert(castle_entity.is_empty(), "no entity found for castle cell marker — radial menu won't show")


# --- Concurrent & Edge Case Commands ---

func _test_concurrent_commands_both_players() -> void:
	print("[Sync: Both Players Command Same Tick]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)

	# Both players place buildings on the same tick
	var result := sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"barracks", 0, 2),
	])

	var p0_bldgs := sim.entities.filter(func(e): return e.type == "building" and e.player_index == 0)
	var p1_bldgs := sim.entities.filter(func(e): return e.type == "building" and e.player_index == 1)
	_assert(p0_bldgs.size() == 1, "player 0 has 1 building")
	_assert(p1_bldgs.size() == 1, "player 1 has 1 building")

	# Both sell on the same tick
	if p0_bldgs.size() > 0 and p1_bldgs.size() > 0:
		sim.step([
			Command.sell_building(0, p0_bldgs[0].id),
			Command.sell_building(1, p1_bldgs[0].id),
		])
		var remaining := sim.entities.filter(func(e): return e.type == "building")
		_assert(remaining.size() == 0, "both buildings sold simultaneously")


func _test_command_on_wrong_tick_ignored() -> void:
	print("[Sync: Command Buffer Isolation]")
	# Commands for a tick should only be processed on that tick
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Tick 0: place building
	sim.step([Command.place_building(0, &"barracks", 0, 0)])
	_assert(sim.tick == 1, "tick 1 after first step")

	# Tick 1: empty — building from tick 0 shouldn't replay
	sim.step([])
	var buildings := sim.entities.filter(func(e): return e.type == "building" and e.player_index == 0)
	_assert(buildings.size() == 1, "still only 1 building after empty tick (no replay)")


func _test_sell_during_combat() -> void:
	print("[Sell: During Active Combat]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)

	# Both place barracks → units will spawn and fight
	sim.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"barracks", 0, 2),
	])

	# Run until units exist (spawn interval is ~130-140 ticks)
	for i in 160:
		sim.step([])

	var units := sim.entities.filter(func(e): return e.type == "unit")
	_assert(units.size() > 0, "units spawned during combat (%d)" % units.size())

	# Sell player 0's barracks mid-combat
	var bldg := _find_building(sim, &"barracks", 0)
	if not bldg.is_empty():
		sim.step([Command.sell_building(0, bldg.id)])
		_assert(_find_building(sim, &"barracks", 0).is_empty(), "barracks sold during combat")

		# Simulation should continue without crash
		for i in 50:
			sim.step([])
		_assert(sim.tick > 70, "simulation continues after mid-combat sell (tick %d)" % sim.tick)


func _test_place_and_sell_same_tick() -> void:
	print("[Edge Case: Place + Sell Same Tick]")
	var sim := _create_test_sim()
	sim.players[0].gold = FP.from_int(500)

	# Place a building first so we have an entity to reference
	_place_building(sim, 0, &"barracks", 0, 0)
	var bldg := _find_building(sim, &"barracks", 0)
	_assert(not bldg.is_empty(), "building placed")
	if bldg.is_empty():
		return

	# Now try place + sell of DIFFERENT building in same tick
	# (the sell targets the already-placed barracks)
	var gold_before := FP.to_int(sim.players[0].gold)
	sim.step([
		Command.place_building(0, &"archer_range", 2, 0),
		Command.sell_building(0, bldg.id),
	])

	_assert(_find_building(sim, &"barracks", 0).is_empty(), "barracks sold in same tick as new placement")
	_assert(not _find_building(sim, &"archer_range", 0).is_empty(), "archer_range placed in same tick as sell")


# --- Lockstep Logic ---

func _test_lockstep_tick_readiness() -> void:
	print("[Lockstep: Tick Readiness]")
	var nm = root.get_node_or_null("NetworkManager")
	_assert(nm != null, "NetworkManager exists")
	if nm == null:
		return

	# In offline mode, every tick is ready
	nm.offline_mode = true
	_assert(nm.is_tick_ready(1), "offline: tick 1 always ready")
	_assert(nm.is_tick_ready(999), "offline: tick 999 always ready")

	# In online mode, tick needs both local sent + remote received
	nm.offline_mode = false
	nm._local_commands_sent.clear()
	nm._remote_commands_received.clear()

	_assert(not nm.is_tick_ready(5), "online: tick 5 not ready (nothing sent/received)")

	nm._local_commands_sent[5] = true
	_assert(not nm.is_tick_ready(5), "online: tick 5 not ready (only local sent)")

	nm._remote_commands_received[5] = true
	_assert(nm.is_tick_ready(5), "online: tick 5 ready (both local + remote)")

	# Cleanup — reset to offline
	nm.offline_mode = true
	nm._local_commands_sent.clear()
	nm._remote_commands_received.clear()


func _test_stall_timeout_logic() -> void:
	print("[Lockstep: Stall Timeout]")
	var gm = root.get_node_or_null("GameManager")
	_assert(gm != null, "GameManager exists")
	if gm == null:
		return

	# Verify MAX_STALL_MSEC constant exists and is reasonable
	var has_max_stall: bool = "MAX_STALL_MSEC" in gm
	_assert(has_max_stall, "MAX_STALL_MSEC constant exists")
	if has_max_stall:
		_assert(gm.MAX_STALL_MSEC >= 3000, "stall timeout >= 3s (%d ms)" % gm.MAX_STALL_MSEC)
		_assert(gm.MAX_STALL_MSEC <= 10000, "stall timeout <= 10s (%d ms)" % gm.MAX_STALL_MSEC)

	# Verify TICK_DURATION_MSEC is 100ms (10 ticks/sec)
	var has_tick_dur: bool = "TICK_DURATION_MSEC" in gm
	_assert(has_tick_dur, "TICK_DURATION_MSEC constant exists")
	if has_tick_dur:
		_assert(gm.TICK_DURATION_MSEC == 100, "tick duration is 100ms (10 ticks/sec)")


# --- Wire-Format Lockstep (JSON round-trip like _on_match_state) ---

## Minimal stand-in for NakamaRTAPI.MatchData — just what _on_match_state reads.
class FakeMatchState:
	var op_code: int
	var data: String
	func _init(p_op_code: int, p_data: String) -> void:
		op_code = p_op_code
		data = p_data


func _create_wire_sim() -> Simulation:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(777, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"kingdom", "perk": &""},
	], {"skip_prep": true})
	sim.players[0].gold = FP.from_int(2000)
	sim.players[1].gold = FP.from_int(2000)
	return sim


## Build a COMMANDS payload exactly like flush_commands_for_tick /
## _send_definitive_flush: current tick + REDUNDANT_TICKS previous ticks.
## partial=true emulates a pre-commit flush where tick's own commands are
## still empty (the stall race the redundant format exists to survive).
func _build_wire_payload(nm, hist: Dictionary, tick: int, partial: bool) -> String:
	var all_ticks: Array = []
	for u in range(maxi(1, tick - 3), tick + 1):
		var cmds: Array = hist.get(u, [])
		if partial and u == tick:
			cmds = []
		all_ticks.append({"tick": u, "commands": nm._serialize_commands(cmds)})
	return JSON.stringify({"tick": tick, "ticks": all_ticks})


## Apply a JSON payload to a CommandBuffer exactly like the COMMANDS arm of
## _on_match_state (parse_string floats → int casts → replace_commands).
## NOTE: buffer is untyped — command_buffer.gd references the GameManager
## autoload, so the CommandBuffer class_name cannot be resolved at this test
## script's compile time (before autoloads register). Use load() at runtime.
func _apply_wire_payload(nm, buffer, payload_json: String, local_pid: int) -> void:
	var data = JSON.parse_string(payload_json)
	var ticks_array: Array = data.get("ticks", [])
	for tick_data in ticks_array:
		var t: int = int(tick_data.tick)
		var commands: Array = nm._deserialize_commands(tick_data.get("commands", []))
		buffer.replace_commands(t, commands, local_pid)


## 1B-3: two peers receiving the SAME same-player commands in OPPOSITE
## insertion orders (out-of-order delivery) must apply them in ONE order.
## Sort key must be (player_id, seq) — player_id alone leaves same-player
## order insertion-dependent (and sort_custom is not stability-guaranteed).
func _test_same_player_command_order_deterministic() -> void:
	var c1 := Command.place_building(0, &"barracks", 0, 0)
	c1["seq"] = 1
	var c2 := Command.place_building(0, &"archer_range", 4, 0)
	c2["seq"] = 2
	var c3 := Command.place_building(1, &"war_camp", 0, 8)
	c3["seq"] = 1
	var buf_a := CommandBuffer.new()
	for c in [c1, c2, c3]:
		buf_a.add_command(7, c)
	var buf_b := CommandBuffer.new()
	for c in [c3, c2, c1]:  # reversed arrival
		buf_b.add_command(7, c)
	var a := buf_a.get_commands(7)
	var b := buf_b.get_commands(7)
	_assert(a.size() == 3 and b.size() == 3, "order test: both buffers hold 3 commands")
	var same := true
	for i in a.size():
		if a[i] != b[i]:
			same = false
	_assert(same, "same-player same-tick commands apply in identical order on both peers")
	_assert(a[0].get("seq", -1) == 1 and a[1].get("seq", -1) == 2,
		"player 0 commands honor sender seq order (1 then 2)")



func _test_two_sim_json_wire_lockstep() -> void:
	print("[Two-Sim JSON Wire Lockstep: 520 ticks, dup + out-of-order delivery]")
	var nm = root.get_node_or_null("NetworkManager")
	var gm = root.get_node_or_null("GameManager")
	_assert(nm != null and gm != null, "autoloads exist")
	if nm == null or gm == null:
		return

	# Probe run: discover the deterministic entity ids used by SELL/ACTIVATE.
	# Ids depend only on prior commands, so the probe's ids match the wire run.
	var probe := _create_wire_sim()
	probe.step([
		Command.place_building(0, &"barracks", 0, 0),
		Command.place_building(1, &"barracks", 0, 2),
	])
	probe.step([Command.place_building(0, &"war_drums", 4, 0)])
	var barracks_id: int = -1
	var drums_id: int = -1
	for e in probe.entities:
		if e.type == "building" and e.building_type == &"barracks" and e.player_index == 0:
			barracks_id = e.id
		if e.type == "building" and e.building_type == &"war_drums":
			drums_id = e.id
	_assert(barracks_id != -1 and drums_id != -1, "probe found deterministic building ids")

	# Scripted commands per tick (includes every command type + USE_ABILITY).
	var script_p0: Dictionary = {
		1: [Command.place_building(0, &"barracks", 0, 0)],
		2: [Command.place_building(0, &"war_drums", 4, 0)],
		30: [Command.place_building(0, &"archer_range", 2, 0)],
		150: [Command.use_ability(0, &"war_horn", 5, 5)],
		200: [Command.sell_building(0, barracks_id)],
		260: [Command.activate_building(0, drums_id)],
	}
	var script_p1: Dictionary = {
		1: [Command.place_building(1, &"barracks", 0, 2)],
		40: [Command.place_building(1, &"archer_range", 2, 6)],
		210: [Command.place_building(1, &"gold_mine", 4, 6)],
	}

	var sim_a := _create_wire_sim()
	var sim_b := _create_wire_sim()
	# load() at runtime — see _apply_wire_payload note re: autoload references.
	var command_buffer_script: GDScript = load("res://core/command_buffer.gd")
	var buf_a = command_buffer_script.new()
	var buf_b = command_buffer_script.new()
	var hist_a: Dictionary = {}
	var hist_b: Dictionary = {}
	var finals_a: Array = []  # committed payloads, chronological
	var finals_b: Array = []
	var saved_local_pid: int = gm.local_player_id
	var num_ticks: int = 520
	var all_equal: bool = true
	var first_diverged_tick: int = -1

	for t in range(1, num_ticks + 1):
		var cmds0: Array = script_p0.get(t, [])
		var cmds1: Array = script_p1.get(t, [])
		# Local commit (commit_tick_commands equivalent)
		for c in cmds0:
			buf_a.add_command(t, c)
		for c in cmds1:
			buf_b.add_command(t, c)
		hist_a[t] = cmds0
		hist_b[t] = cmds1

		# Delivery to the opposite side. WebSocket order guarantees a tick's
		# partial (pre-commit) flush precedes its definitive flush, but the
		# redundant multi-tick format must survive DUPLICATED payloads and
		# older committed payloads re-arriving AFTER newer ones.
		var final_a := _build_wire_payload(nm, hist_a, t, false)
		var final_b := _build_wire_payload(nm, hist_b, t, false)
		finals_a.append(final_a)
		finals_b.append(final_b)
		var deliver_to_b: Array = [_build_wire_payload(nm, hist_a, t, true)]
		var deliver_to_a: Array = [_build_wire_payload(nm, hist_b, t, true)]
		if t % 3 == 0 and finals_a.size() >= 2:
			# Out-of-order: previous committed payload re-delivered after current
			deliver_to_b.append(finals_a[-1])
			deliver_to_b.append(finals_a[-2])
			deliver_to_a.append(finals_b[-1])
			deliver_to_a.append(finals_b[-2])
		else:
			deliver_to_b.append(final_a)
			deliver_to_a.append(final_b)
		if t % 5 == 0:
			deliver_to_b.append(final_a)  # duplicate delivery
			deliver_to_a.append(final_b)

		# replace_commands keys off GameManager.local_player_id to preserve
		# local commands — set it per receiving side, like each real client.
		gm.local_player_id = 1
		for pj in deliver_to_b:
			_apply_wire_payload(nm, buf_b, pj, 1)
		gm.local_player_id = 0
		for pj in deliver_to_a:
			_apply_wire_payload(nm, buf_a, pj, 0)

		sim_a.step(buf_a.get_commands(t))
		sim_b.step(buf_b.get_commands(t))
		buf_a.clear_through(t)
		buf_b.clear_through(t)

		if t == 2:
			var bldgs_a: int = sim_a.entities.filter(func(e): return e.type == "building").size()
			var bldgs_b: int = sim_b.entities.filter(func(e): return e.type == "building").size()
			_assert(bldgs_a == 3 and bldgs_b == 3, "both sims placed 3 buildings through the wire (a=%d b=%d)" % [bldgs_a, bldgs_b])

		if sim_a.compute_checksum() != sim_b.compute_checksum():
			all_equal = false
			first_diverged_tick = t
			break

	gm.local_player_id = saved_local_pid
	_assert(all_equal, "checksums equal every tick for %d ticks%s" % [num_ticks,
		"" if all_equal else " (diverged at tick %d)" % first_diverged_tick])
	if all_equal:
		_assert(sim_a.tick == num_ticks and sim_b.tick == num_ticks, "both sims advanced %d ticks" % num_ticks)
		_assert(sim_a.entities.size() == sim_b.entities.size(), "entity counts match (%d)" % sim_a.entities.size())


# --- MATCH_CONFIG Handshake & Abort Paths ---

func _test_match_config_build_id_mismatch_aborts() -> void:
	print("[MATCH_CONFIG: Build ID Mismatch Aborts]")
	var nm = root.get_node_or_null("NetworkManager")
	var gm = root.get_node_or_null("GameManager")
	_assert(nm != null and gm != null, "autoloads exist")
	if nm == null or gm == null:
		return
	var captured: Array = []
	var handler := func(kind: String, _message: String): captured.append(kind)
	nm.match_error.connect(handler)

	# build.sh stamps application/config/version at export time; NetworkManager
	# must read exactly that setting for the stamp to reach MATCH_CONFIG.
	_assert(nm.build_id == str(ProjectSettings.get_setting("application/config/version", "dev")) and nm.build_id != "",
		"build_id reads application/config/version (%s)" % nm.build_id)

	nm.offline_mode = false
	nm.net_state = nm.NetState.IN_LOBBY
	nm.match_id = "test-match"
	var payload := JSON.stringify({
		"build_id": "stale-cached-build",
		"seed": 123,
		"game_mode": 0,
		"players": [
			{"id": 0, "team": 0, "faction": "kingdom", "perk": ""},
			{"id": 1, "team": 1, "faction": "horde", "perk": ""},
		],
	})
	nm._on_match_state(FakeMatchState.new(nm.OpCode.MATCH_CONFIG, payload))

	_assert(captured == ["version_mismatch"], "match_error(version_mismatch) emitted (%s)" % str(captured))
	_assert(nm.net_state == nm.NetState.AUTHENTICATED, "net_state back to AUTHENTICATED (can re-queue)")
	_assert(nm.match_id == "", "match_id cleared")
	_assert(gm.state == gm.State.MENU, "GameManager never started the match")

	nm.match_error.disconnect(handler)
	nm.offline_mode = true
	nm.net_state = nm.NetState.OFFLINE


func _test_matchmaker_roster_validation() -> void:
	print("[Matchmaker: Roster Must Have Exactly 2 Users]")
	var nm = root.get_node_or_null("NetworkManager")
	_assert(nm != null, "NetworkManager exists")
	if nm == null:
		return
	var captured: Array = []
	var handler := func(kind: String, _message: String): captured.append(kind)
	nm.match_error.connect(handler)

	nm.offline_mode = false
	nm.local_user_id = "user_a"
	nm.match_id = ""

	# Presences missing (old dual-player-0 bug): only self in roster → abort
	nm.net_state = nm.NetState.MATCHMAKING
	var ok: bool = nm._assign_player_ids([])
	_assert(not ok, "empty roster rejected (self-only fallback no longer guesses player 0)")
	_assert(captured == ["matchmaking"], "matchmaking abort emitted")
	_assert(nm.net_state == nm.NetState.AUTHENTICATED, "net_state back to AUTHENTICATED")

	# Single explicit user (self) → abort
	nm.net_state = nm.NetState.MATCHMAKING
	ok = nm._assign_player_ids(["user_a", "user_a", ""])
	_assert(not ok, "deduped single-user roster rejected")

	# Valid 2-user roster (with duplicates + empty entries) → deterministic assignment
	ok = nm._assign_player_ids(["user_b", "user_a", "user_b", ""])
	_assert(ok, "two-user roster accepted")
	_assert(nm.local_player_id == 0, "sorted assignment: user_a is player 0")
	nm.local_user_id = "user_b"
	ok = nm._assign_player_ids(["user_b", "user_a"])
	_assert(ok and nm.local_player_id == 1, "sorted assignment: user_b is player 1")

	nm.match_error.disconnect(handler)
	nm.local_user_id = ""
	nm.local_player_id = -1
	nm.offline_mode = true
	nm.net_state = nm.NetState.OFFLINE


func _test_match_config_seed_conflict_aborts() -> void:
	print("[MATCH_CONFIG: Conflicting Seed While IN_MATCH Aborts]")
	var nm = root.get_node_or_null("NetworkManager")
	_assert(nm != null, "NetworkManager exists")
	if nm == null:
		return
	var captured: Array = []
	var handler := func(kind: String, _message: String): captured.append(kind)
	nm.match_error.connect(handler)

	# Duplicate config with the SAME seed while IN_MATCH → re-ack, no abort
	nm.offline_mode = false
	nm.net_state = nm.NetState.IN_MATCH
	nm._active_config = {"seed": 111}
	nm._on_match_state(FakeMatchState.new(nm.OpCode.MATCH_CONFIG, JSON.stringify({"seed": 111, "build_id": nm.build_id})))
	_assert(nm.net_state == nm.NetState.IN_MATCH, "duplicate config (same seed) does not abort")
	_assert(captured.is_empty(), "no match_error for duplicate config")

	# Config with a DIFFERENT seed while IN_MATCH → abort (was silently dropped)
	nm._on_match_state(FakeMatchState.new(nm.OpCode.MATCH_CONFIG, JSON.stringify({"seed": 222, "build_id": nm.build_id})))
	_assert(captured == ["config_conflict"], "match_error(config_conflict) emitted (%s)" % str(captured))
	_assert(nm.net_state == nm.NetState.AUTHENTICATED, "net_state back to AUTHENTICATED after conflict")

	# CONFIG_ACK while IN_MATCH sets the acked flag (stops player 0's retries)
	nm.net_state = nm.NetState.IN_MATCH
	nm._config_acked = false
	nm._on_match_state(FakeMatchState.new(nm.OpCode.CONFIG_ACK, "{}"))
	_assert(nm._config_acked, "CONFIG_ACK sets _config_acked")

	nm.match_error.disconnect(handler)
	nm._active_config.clear()
	nm.offline_mode = true
	nm.net_state = nm.NetState.OFFLINE


func _test_commands_null_buffer_guard() -> void:
	print("[Teardown: COMMANDS With Null command_buffer Does Not Crash]")
	var nm = root.get_node_or_null("NetworkManager")
	var gm = root.get_node_or_null("GameManager")
	_assert(nm != null and gm != null, "autoloads exist")
	if nm == null or gm == null:
		return

	var saved_buffer = gm.command_buffer
	gm.command_buffer = null
	nm.offline_mode = false
	nm.net_state = nm.NetState.IN_MATCH
	nm._remote_commands_received.clear()

	var payload := JSON.stringify({"tick": 5, "ticks": [
		{"tick": 5, "commands": [{"type": Command.Type.PLACE_BUILDING, "player_id": 1, "building_type": "barracks", "grid_x": 0, "grid_y": 0}]},
	]})
	nm._on_match_state(FakeMatchState.new(nm.OpCode.COMMANDS, payload))
	_assert(true, "trailing COMMANDS payload with null command_buffer did not crash")
	_assert(not nm._remote_commands_received.has(5), "payload dropped before marking tick received")

	# Trailing message AFTER leaving the match entirely (net_state no longer IN_MATCH)
	nm.net_state = nm.NetState.AUTHENTICATED
	nm._on_match_state(FakeMatchState.new(nm.OpCode.COMMANDS, payload))
	_assert(true, "COMMANDS after leaving match dropped without crash")

	gm.command_buffer = saved_buffer
	nm.offline_mode = true
	nm.net_state = nm.NetState.OFFLINE


func _test_checksum_buffered_comparison() -> void:
	print("[Checksum: Buffered Comparison When Local Sim Is Behind]")
	var nm = root.get_node_or_null("NetworkManager")
	var gm = root.get_node_or_null("GameManager")
	var eb = root.get_node_or_null("EventBus")
	_assert(nm != null and gm != null and eb != null, "autoloads exist")
	if nm == null or gm == null or eb == null:
		return
	var desync_ticks: Array = []
	var handler := func(t: int): desync_ticks.append(t)
	eb.desync_detected.connect(handler)

	nm.offline_mode = false
	nm.net_state = nm.NetState.IN_MATCH
	nm._desync_reported = false
	nm._remote_checksums.clear()
	gm.current_tick = 40
	gm._checksum_history.clear()

	# Remote checksum for tick 50 arrives while local sim is at tick 40 —
	# previously silently dropped (get_checksum_for_tick returned -1).
	nm._on_match_state(FakeMatchState.new(nm.OpCode.CHECKSUM, JSON.stringify({"tick": 50, "checksum": 999})))
	_assert(desync_ticks.is_empty(), "no comparison while local sim is behind")
	_assert(nm._remote_checksums.has(50), "remote checksum buffered for later comparison")

	# Local sim catches up with a different checksum → mismatch detected
	gm.current_tick = 50
	gm._checksum_history[50] = 123
	nm._compare_buffered_checksums()
	_assert(desync_ticks == [50], "desync detected once local catches up (got %s)" % str(desync_ticks))
	_assert(not nm._remote_checksums.has(50), "compared entry pruned from buffer")

	# Matching checksum does not fire the signal
	nm._desync_reported = false
	gm.current_tick = 100
	gm._checksum_history[100] = 555
	nm._on_match_state(FakeMatchState.new(nm.OpCode.CHECKSUM, JSON.stringify({"tick": 100, "checksum": 555})))
	_assert(desync_ticks == [50], "matching checksum does not fire desync")
	_assert(not nm._remote_checksums.has(100), "matching entry pruned from buffer")

	# Multiple buffered mismatches → EARLIEST mismatching tick reported
	nm._desync_reported = false
	gm.current_tick = 120
	nm._on_match_state(FakeMatchState.new(nm.OpCode.CHECKSUM, JSON.stringify({"tick": 200, "checksum": 1})))
	nm._on_match_state(FakeMatchState.new(nm.OpCode.CHECKSUM, JSON.stringify({"tick": 150, "checksum": 2})))
	gm._checksum_history[150] = 7777
	gm._checksum_history[200] = 8888
	gm.current_tick = 200
	nm._compare_buffered_checksums()
	_assert(desync_ticks == [50, 150], "earliest mismatching tick reported (got %s)" % str(desync_ticks))

	eb.desync_detected.disconnect(handler)
	gm.current_tick = 0
	gm._checksum_history.clear()
	nm._remote_checksums.clear()
	nm._desync_reported = false
	nm.offline_mode = true
	nm.net_state = nm.NetState.OFFLINE


func _test_match_config_perks_deterministic() -> void:
	print("[MATCH_CONFIG: Perks Travel The Wire Deterministically]")
	var nm = root.get_node_or_null("NetworkManager")
	_assert(nm != null, "NetworkManager exists")
	if nm == null:
		return

	# Deliberately unordered players — _config_to_player_data must sort by id
	# so both clients hand simulation.initialize the identical array.
	var config := {
		"build_id": "test",
		"seed": 999,
		"game_mode": 0,
		"players": [
			{"id": 1, "team": 1, "faction": "kingdom", "perk": "savage_rush"},
			{"id": 0, "team": 0, "faction": "kingdom", "perk": "iron_discipline"},
		],
	}
	var pd_local: Array = nm._config_to_player_data(config)
	var pd_wire: Array = nm._config_to_player_data(JSON.parse_string(JSON.stringify(config)))

	_assert(pd_local.size() == 2 and pd_wire.size() == 2, "player_data has 2 entries")
	_assert(pd_local[0].id == 0 and pd_local[1].id == 1, "player_data ordered by id")
	_assert(pd_local[0].perk == &"iron_discipline", "player 0 perk carried through config")
	_assert(pd_local[1].perk == &"savage_rush", "player 1 perk carried through config")
	_assert(str(pd_local) == str(pd_wire), "player_data identical after JSON wire round-trip")
	_assert(pd_wire[0].id is int and pd_wire[0].perk is StringName, "wire floats/strings normalized to int/StringName")

	# Same perks on both clients → identical sims
	var cmds := [Command.place_building(0, &"barracks", 0, 0)]
	var sim_p := Simulation.new()
	sim_p.register_buildings(_load_all_building_data())
	sim_p.initialize(999, pd_local, {"skip_prep": true})
	sim_p.players[0].gold = FP.from_int(500)
	var sim_q := Simulation.new()
	sim_q.register_buildings(_load_all_building_data())
	sim_q.initialize(999, pd_wire, {"skip_prep": true})
	sim_q.players[0].gold = FP.from_int(500)
	for t in 250:
		sim_p.step(cmds if t == 0 else [])
		sim_q.step(cmds if t == 0 else [])
	_assert(sim_p.compute_checksum() == sim_q.compute_checksum(), "identical perks → identical checksums after 250 ticks")

	# Perk stripped on one side (the old MATCH_CONFIG behavior) → desync.
	# iron_discipline gives +10% unit HP, which is checksum-visible once units spawn.
	var pd_stripped: Array = []
	for p in pd_local:
		pd_stripped.append({"id": p.id, "team": p.team, "faction": p.faction})
	var sim_r := Simulation.new()
	sim_r.register_buildings(_load_all_building_data())
	sim_r.initialize(999, pd_stripped, {"skip_prep": true})
	sim_r.players[0].gold = FP.from_int(500)
	for t in 250:
		sim_r.step(cmds if t == 0 else [])
	_assert(sim_p.compute_checksum() != sim_r.compute_checksum(), "perk lost in transit → checksum desync (the trap this fix closes)")


# --- Scenario Runner ---

func _run_scenario(seed_val: int, commands_per_tick: Array, num_ticks: int) -> int:
	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"kingdom", "perk": &""},
	], {"skip_prep": true})
	sim.players[0].gold = FP.from_int(500)
	sim.players[1].gold = FP.from_int(500)
	for i in num_ticks:
		var cmds: Array = commands_per_tick[i] if i < commands_per_tick.size() else []
		sim.step(cmds)
	return sim.compute_checksum()


func _print_results() -> void:
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	if _fail > 0:
		print("FAILED TESTS:")
		for r in _results:
			if r.status == "FAIL":
				print("  - %s" % r.test)
	var json := JSON.stringify({"pass": _pass, "fail": _fail, "tests": _results}, "  ")
	var f := FileAccess.open("res://tests/multiplayer_test_results.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()

# --- BUG "opponent left" in single player (2026-07-10) ---
# Root cause: lockstep wait + command routing keyed on the GLOBAL socket flag
# (NetworkManager.offline_mode) instead of the per-match GameManager
# .is_online_match. A live socket left over from PLAY ONLINE (cancel/abort
# keeps it open by design) poisons the next SOLO match: it waits for remote
# ticks that never come -> stall timeout -> "Opponent disconnected".

func _test_offline_match_survives_live_socket() -> void:
	print("[Offline match survives live socket (opponent-left bug)]")
	var gm = root.get_node_or_null("GameManager")
	var nm = root.get_node_or_null("NetworkManager")
	if gm == null or nm == null:
		_assert(false, "autoloads exist")
		return
	var saved_offline: bool = nm.offline_mode
	# Poisoned state: socket "alive" (offline_mode=false), match is SOLO
	nm.offline_mode = false
	gm.is_online_match = false
	# The lockstep gate must NOT engage for a solo match
	var lockstep: bool = gm.is_lockstep_match() if gm.has_method("is_lockstep_match") else (not nm.offline_mode)
	_assert(not lockstep, "solo match does not enter lockstep wait with live socket")
	# And the stall-abort path must be unreachable: simulate the _process gate
	nm.offline_mode = saved_offline
	gm.is_online_match = false


func _test_offline_match_survives_socket_drop() -> void:
	print("[Offline match survives socket drop (Connection lost guard)]")
	var gm = root.get_node_or_null("GameManager")
	if gm == null:
		_assert(false, "GameManager exists")
		return
	var eb = root.get_node_or_null("EventBus")
	if eb == null:
		_assert(false, "EventBus exists")
		return
	var saved_state = gm.state
	var aborted: Array = []
	var handler := func(reason: String) -> void: aborted.append(reason)
	eb.match_aborted.connect(handler)
	# Solo match in PLAYING state; a socket drop fires _on_disconnected
	gm.is_online_match = false
	gm.state = gm.State.PLAYING
	gm._on_disconnected()
	eb.match_aborted.disconnect(handler)
	_assert(aborted.is_empty(), "socket drop does not abort a solo match (got %s)" % str(aborted))
	_assert(gm.state == gm.State.PLAYING, "solo match still PLAYING after socket drop")
	gm.state = saved_state
	gm.set_process(false)


func _test_offline_command_routing_with_live_socket() -> void:
	print("[Offline command routing with live socket]")
	var gm = root.get_node_or_null("GameManager")
	var nm = root.get_node_or_null("NetworkManager")
	if gm == null or nm == null:
		_assert(false, "autoloads exist")
		return
	var saved_offline: bool = nm.offline_mode
	var saved_state = gm.state
	nm.offline_mode = false          # live socket
	gm.is_online_match = false       # solo match
	nm._local_commands_for_tick.clear()
	# A solo-match command must be applied locally, NOT staged for the relay
	nm.send_command({"type": "noop_test"})
	_assert(nm._local_commands_for_tick.is_empty(),
		"solo command not staged into the online buffer (staged: %s)" % str(nm._local_commands_for_tick))
	nm._local_commands_for_tick.clear()
	nm.offline_mode = saved_offline
	gm.state = saved_state

