## Balance test: 2x100 headless AI-vs-AI matches, two modes.
##   Mode A (mirror): both teams play the same scripted build order — a pure
##     SIM-SYMMETRY test (T-067/T-079); any drift from ~50% is a sim bug.
##   Mode B (real AI, Phase 2.1): two ArenaAI instances (the SHIPPING opponent
##     AI, seeded per match) play kingdom vs horde — a FACTION-BALANCE probe.
##     Its win rate is design signal; only crashes gate the exit code.
## Run: godot --headless --path castle_clash -s tests/test_balance.gd
extends SceneTree

const NUM_MATCHES: int = 100
const MAX_TICKS: int = 6000  # 10 min at 10 tps — timeout
const BUILD_INTERVAL: int = 30  # Build every 3 seconds
const BASE_SEED: int = 12345

# Build orders (prioritized — build cheapest affordable in order)
# T-079 fix: per T-067 "Horde mirrors Kingdom", both teams use the SAME army for a
# true mirror balance test. The old HORDE_ORDER spawned legacy Horde units (grunt,
# axe_thrower, wardrummer) whose armor types weren't updated in T-079, creating
# a false 2x Pierce-vs-Light damage imbalance favoring Horde.
const KINGDOM_ORDER: Array[StringName] = [
	&"barracks", &"archer_range", &"gold_mine", &"barracks",
	&"priest_temple", &"guard_tower", &"knight_hall", &"siege_workshop",
	&"armory", &"war_horn",
]
const HORDE_ORDER: Array[StringName] = KINGDOM_ORDER  # Mirror Kingdom (T-067)

var _all_buildings: Array = []
var _building_costs: Dictionary = {}


func _init() -> void:
	await process_frame
	_load_buildings()
	var results := _run_all_matches(false)
	_print_report(results, "Mode A — scripted mirror (sim symmetry)")
	var results_ai := _run_all_matches(true)
	_print_report(results_ai, "Mode B — real ArenaAI, kingdom vs horde (faction balance)")
	_save_json({"mirror": results, "real_ai": results_ai})
	var win_rate: float = results.kingdom_wins * 100.0 / NUM_MATCHES
	# Gate: mirror symmetry band + zero crashes in either mode. Mode B's win
	# rate is REPORTED (faction-balance signal for A0/A5), not gated here.
	var pass_val: bool = win_rate >= 40.0 and win_rate <= 60.0 \
		and results.crashes == 0 and results_ai.crashes == 0
	quit(0 if pass_val else 1)


func _load_buildings() -> void:
	var dir := DirAccess.open("res://data/buildings/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var bd = load("res://data/buildings/" + fname)
			if bd:
				_all_buildings.append(bd)
				_building_costs[bd.id] = bd.gold_cost
		fname = dir.get_next()


func _run_all_matches(real_ai: bool) -> Dictionary:
	var kingdom_wins: int = 0
	var horde_wins: int = 0
	var draws: int = 0
	var crashes: int = 0
	var total_ticks: int = 0
	var match_lengths: Array[int] = []
	var match_details: Array = []

	print("\n=== Castle Fight Balance Test: %d Matches (%s) ===" % [
		NUM_MATCHES, "real ArenaAI" if real_ai else "scripted mirror"])
	print("Kingdom (team 0) vs Horde (team 1)\n")

	for i in NUM_MATCHES:
		var seed_val: int = BASE_SEED + i
		var result := _run_match_ai(seed_val, i) if real_ai else _run_match(seed_val, i)
		match_details.append(result)
		match_lengths.append(result.ticks)
		total_ticks += result.ticks

		if result.winner == 0:
			kingdom_wins += 1
		elif result.winner == 1:
			horde_wins += 1
		elif result.winner == -2:
			crashes += 1
		else:
			draws += 1

		# Progress every 10 matches
		if (i + 1) % 10 == 0:
			var wr: float = kingdom_wins * 100.0 / (i + 1)
			print("  Match %d/%d — Kingdom %d, Horde %d, Draw %d (KR %.1f%%)" % [
				i + 1, NUM_MATCHES, kingdom_wins, horde_wins, draws, wr])

	match_lengths.sort()
	var avg_ticks: int = total_ticks / NUM_MATCHES if NUM_MATCHES > 0 else 0
	var median_ticks: int = match_lengths[NUM_MATCHES / 2] if NUM_MATCHES > 0 else 0

	return {
		"kingdom_wins": kingdom_wins,
		"horde_wins": horde_wins,
		"draws": draws,
		"crashes": crashes,
		"avg_ticks": avg_ticks,
		"median_ticks": median_ticks,
		"min_ticks": match_lengths[0] if match_lengths.size() > 0 else 0,
		"max_ticks": match_lengths[-1] if match_lengths.size() > 0 else 0,
		"matches": match_details,
	}


## Mode B (Phase 2.1): the REAL opponent AI on both sides. Seeded RNG per AI →
## reproducible; sim-default starting gold (real match conditions, unlike the
## zeroed-gold scripted mode); think() every BUILD_INTERVAL ticks = the game's
## 3s cadence at 10tps.
func _run_match_ai(seed_val: int, match_idx: int) -> Dictionary:
	var sim := Simulation.new()
	sim.register_buildings(_all_buildings)
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	var factions: Array = [
		load("res://data/factions/kingdom.tres"),
		load("res://data/factions/horde.tres"),
	]
	var ais: Array = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val * 2 + i
		ais.append(ArenaAI.new(i, rng))

	for tick_i in MAX_TICKS:
		var cmds: Array = []
		if tick_i > 0 and tick_i % BUILD_INTERVAL == 0:
			for i in 2:
				var gold: int = FP.to_int(sim.players[i].gold)
				cmds.append_array(ais[i].think(sim, factions[i], gold, sim.tick))
		sim.step(cmds)

		if sim.match_over:
			return {
				"match": match_idx,
				"seed": seed_val,
				"winner": sim.winning_team,
				"ticks": sim.tick,
				"castle0_hp": FP.to_int(sim.castles[0].hp),
				"castle1_hp": FP.to_int(sim.castles[1].hp),
				"strategies": [ais[0].strategy, ais[1].strategy],
			}

	var hp0_ai: int = FP.to_int(sim.castles[0].hp)
	var hp1_ai: int = FP.to_int(sim.castles[1].hp)
	var winner_ai: int = -1
	if hp0_ai > hp1_ai:
		winner_ai = 0
	elif hp1_ai > hp0_ai:
		winner_ai = 1
	return {
		"match": match_idx,
		"seed": seed_val,
		"winner": winner_ai,
		"ticks": MAX_TICKS,
		"castle0_hp": hp0_ai,
		"castle1_hp": hp1_ai,
		"timeout": true,
		"strategies": [ais[0].strategy, ais[1].strategy],
	}


func _run_match(seed_val: int, match_idx: int) -> Dictionary:
	var sim := Simulation.new()
	sim.register_buildings(_all_buildings)
	sim.initialize(seed_val, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(0)
	sim.players[1].gold = FP.from_int(0)

	var p0_build_idx: int = 0
	var p1_build_idx: int = 0
	var p0_pos: int = 0  # Linearized grid position
	var p1_pos: int = 0

	for tick_i in MAX_TICKS:
		var cmds: Array = []

		# Build for both players every BUILD_INTERVAL ticks
		if tick_i > 0 and tick_i % BUILD_INTERVAL == 0:
			# Player 0 (Kingdom)
			if p0_build_idx < KINGDOM_ORDER.size():
				var btype: StringName = KINGDOM_ORDER[p0_build_idx]
				var cost: int = _building_costs.get(btype, 999)
				if FP.to_int(sim.players[0].gold) >= cost:
					var gx: int = (p0_pos % 5) * 2
					var gy: int = (p0_pos / 5) * 2
					if sim.can_place_building(0, btype, gx, gy):
						cmds.append(Command.place_building(0, btype, gx, gy))
						p0_build_idx += 1
					p0_pos = (p0_pos + 1) % 20

			# Player 1 (Horde) — mirror team 0's gy across the build zone.
			# T-079 fix: gy=0 means OPPOSITE things for team 0 and team 1 because the
			# grid is oriented differently. Team 0 row 0 = front (near combat). Team 1
			# row 0 = back (near own castle). Without mirroring, team 1 places spawners
			# deep in its own territory (safe but slow), while team 0 places spawners
			# near combat (vulnerable but fast). Team 1 wins by attrition every time.
			# Mirror: team_1_gy = (GRID_ROWS - 2 - team_0_gy) so both teams place at
			# symmetric positions relative to the combat zone.
			if p1_build_idx < HORDE_ORDER.size():
				var btype: StringName = HORDE_ORDER[p1_build_idx]
				var cost: int = _building_costs.get(btype, 999)
				if FP.to_int(sim.players[1].gold) >= cost:
					var gx: int = (p1_pos % 5) * 2
					var raw_gy: int = (p1_pos / 5) * 2
					var gy: int = 8 - raw_gy  # Mirror: 0→8, 2→6, 4→4, 6→2
					if sim.can_place_building(1, btype, gx, gy):
						cmds.append(Command.place_building(1, btype, gx, gy))
						p1_build_idx += 1
					p1_pos = (p1_pos + 1) % 20

		sim.step(cmds)

		if sim.match_over:
			return {
				"match": match_idx,
				"seed": seed_val,
				"winner": sim.winning_team,
				"ticks": sim.tick,
				"castle0_hp": FP.to_int(sim.castles[0].hp),
				"castle1_hp": FP.to_int(sim.castles[1].hp),
			}

	# Timeout — whoever has more castle HP wins, or draw
	var hp0: int = FP.to_int(sim.castles[0].hp)
	var hp1: int = FP.to_int(sim.castles[1].hp)
	var winner: int = -1
	if hp0 > hp1:
		winner = 0
	elif hp1 > hp0:
		winner = 1
	return {
		"match": match_idx,
		"seed": seed_val,
		"winner": winner,
		"ticks": MAX_TICKS,
		"castle0_hp": hp0,
		"castle1_hp": hp1,
		"timeout": true,
	}


func _print_report(results: Dictionary, label: String) -> void:
	var wr: float = results.kingdom_wins * 100.0 / NUM_MATCHES
	print("\n=== Balance Test Results — %s ===" % label)
	print("Kingdom wins: %d (%.1f%%)" % [results.kingdom_wins, wr])
	print("Horde wins:   %d (%.1f%%)" % [results.horde_wins, 100.0 - wr - results.draws * 100.0 / NUM_MATCHES])
	print("Draws:        %d" % results.draws)
	print("Crashes:      %d" % results.crashes)
	print("Avg ticks:    %d (%.1fs)" % [results.avg_ticks, results.avg_ticks / 10.0])
	print("Median ticks: %d (%.1fs)" % [results.median_ticks, results.median_ticks / 10.0])
	print("Range:        %d - %d ticks" % [results.min_ticks, results.max_ticks])

	var verdict: String = "PASS" if wr >= 45.0 and wr <= 55.0 else ("WARN" if wr >= 40.0 and wr <= 60.0 else "FAIL")
	print("\nBalance verdict: %s (target 45-55%%)" % verdict)
	if results.crashes > 0:
		print("FAIL: %d matches crashed!" % results.crashes)


func _save_json(results: Dictionary) -> void:
	var json := JSON.stringify(results, "  ")
	var f := FileAccess.open("res://tests/balance_results.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
		print("Results saved to tests/balance_results.json")
