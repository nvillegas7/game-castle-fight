## Multi-scenario unit behavior test suite.
## Runs isolated headless scenarios with small unit counts, tracks per-tick detail.
## Each scenario tests a specific aspect: targeting, engagement, castle siege, asymmetry.
##
## Usage:
##   godot --headless --path castle_clash -s tests/test_unit_behavior.gd
##   godot --headless --path castle_clash -s tests/test_unit_behavior.gd -- --scenario melee_3v3
extends SceneTree

const MAX_TICKS: int = 600
const OUT_DIR: String = "/tmp/castle_clash_behavior"

# --- Scenario Definitions ---
# Each scenario: buildings per team, unit cap, what we're testing
var SCENARIOS: Dictionary = {
	# === Category 1: Symmetric combat ===
	"melee_3v3": {
		"desc": "3 footmen vs 3 grunts — basic melee engagement",
		"p0": [["barracks", 5, 3]],
		"p1": [["war_camp", 5, 3]],
		"cap": 3,
		"checks": ["engagement", "targeting", "zigzag"],
	},
	"ranged_3v3": {
		"desc": "3 archers vs 3 axe throwers — ranged standoff",
		"p0": [["archer_range", 5, 3]],
		"p1": [["axe_range", 5, 3]],
		"cap": 3,
		"checks": ["engagement", "positioning"],
	},
	"mixed_2v2": {
		"desc": "1 footman + 1 archer vs 1 grunt + 1 axe — mixed comp",
		"p0": [["barracks", 3, 2], ["archer_range", 7, 2]],
		"p1": [["war_camp", 3, 2], ["axe_range", 7, 2]],
		"cap": 2,
		"checks": ["engagement", "targeting", "role_separation"],
	},

	# === Category 2: One-sided (castle siege) ===
	"player_only_melee": {
		"desc": "3 footmen march to undefended castle — siege test",
		"p0": [["barracks", 5, 3]],
		"p1": [],
		"cap": 3,
		"checks": ["castle_attack", "stuck"],
	},
	"player_only_ranged": {
		"desc": "3 archers march to undefended castle — ranged siege",
		"p0": [["archer_range", 5, 3]],
		"p1": [],
		"cap": 3,
		"checks": ["castle_attack", "stuck"],
	},
	"enemy_only_rush": {
		"desc": "3 grunts attack player castle — defense test",
		"p0": [],
		"p1": [["war_camp", 5, 3]],
		"cap": 3,
		"checks": ["castle_attack", "stuck"],
	},

	# === Category 3: Asymmetric positioning ===
	"left_vs_right": {
		"desc": "Barracks at col 0 vs war_camp at col 9 — cross-field engagement",
		"p0": [["barracks", 0, 3]],
		"p1": [["war_camp", 9, 3]],
		"cap": 3,
		"checks": ["engagement", "pathing"],
	},
	"double_vs_single": {
		"desc": "2 barracks vs 1 war_camp — numerical advantage",
		"p0": [["barracks", 3, 2], ["barracks", 7, 4]],
		"p1": [["war_camp", 5, 3]],
		"cap": 3,
		"checks": ["engagement", "target_spread"],
	},

	# === Category 4: Healing/support ===
	"melee_with_healer": {
		"desc": "2 footmen + 1 priest vs 3 grunts — healing effectiveness",
		"p0": [["barracks", 3, 2], ["priest_temple", 7, 2]],
		"p1": [["war_camp", 5, 3]],
		"cap": 3,
		"checks": ["engagement", "healing"],
	},

	# === Category 5: Siege units ===
	"siege_vs_castle": {
		# siege_workshop has requires_building=&"barracks" (tier-2 gate). Placing it
		# without a barracks first makes Simulation._handle_place_building silently reject
		# the command, so no catapult ever spawns. Place the barracks prerequisite first
		# (same pattern as flying_3v3 placing archer_range before gryphon_roost).
		"desc": "barracks (prereq) + siege_workshop — footmen & catapults siege undefended castle",
		"p0": [["barracks", 8, 3], ["siege_workshop", 5, 3]],
		"p1": [],
		"cap": 4,
		"checks": ["castle_attack", "siege_damage"],
	},

	# === Category 6: Flying units ===
	"flying_3v3": {
		"desc": "3 gryphons vs 3 wyverns — flying combat",
		"p0": [["archer_range", 3, 1], ["gryphon_roost", 6, 1]],
		"p1": [["axe_range", 3, 1], ["wyvern_nest", 6, 1]],
		"cap": 3,
		"checks": ["engagement", "flying"],
	},
}

var _unit_logs: Dictionary = {}
var _events_log: Array = []
var _scenario_results: Array = []


func _init() -> void:
	await process_frame
	var target_scenario: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario"):
			continue
		if target_scenario == "" and not arg.begins_with("-"):
			target_scenario = arg
	# Also check paired --scenario NAME
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scenario" and i + 1 < args.size():
			target_scenario = args[i + 1]

	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	if target_scenario != "" and SCENARIOS.has(target_scenario):
		_run_scenario(target_scenario)
	else:
		_run_all_scenarios()

	_print_final_report()
	_save_full_report()
	quit(0)


func _run_all_scenarios() -> void:
	print("\n" + "=".repeat(70))
	print("  UNIT BEHAVIOR TEST SUITE — %d SCENARIOS" % SCENARIOS.size())
	print("=".repeat(70))
	for name in SCENARIOS:
		_run_scenario(name)


func _run_scenario(name: String) -> void:
	var scenario: Dictionary = SCENARIOS[name]
	_unit_logs.clear()
	_events_log.clear()

	print("\n" + "-".repeat(70))
	print("  SCENARIO: %s" % name)
	print("  %s" % scenario.desc)
	print("-".repeat(70))

	var sim := Simulation.new()
	sim.register_buildings(_load_all_building_data())
	# T-077: scenario tests measure unit behavior, not pacing — skip prep phase
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	], {"skip_prep": true})
	sim.players[0].gold = FP.from_int(5000)
	sim.players[1].gold = FP.from_int(5000)

	# Place buildings
	var cmds: Array = []
	for bld_spec in scenario.get("p0", []):
		cmds.append(Command.place_building(0, StringName(bld_spec[0]), bld_spec[1], bld_spec[2]))
	for bld_spec in scenario.get("p1", []):
		cmds.append(Command.place_building(1, StringName(bld_spec[0]), bld_spec[1], bld_spec[2]))
	if cmds.size() > 0:
		sim.step(cmds)

	var cap: int = scenario.get("cap", 3)
	var spawn_capped: bool = false
	var castle_0_start: int = FP.to_int(sim.castles[0].hp)
	var castle_1_start: int = FP.to_int(sim.castles[1].hp)
	var first_attack_tick: int = -1
	var first_castle_dmg_tick: int = -1

	for tick_i in MAX_TICKS:
		sim.step([])

		var t0_alive := sim.entities.filter(func(e): return e.type == "unit" and e.team == 0 and FP.gt(e.hp, FP.ZERO))
		var t1_alive := sim.entities.filter(func(e): return e.type == "unit" and e.team == 1 and FP.gt(e.hp, FP.ZERO))

		# Cap spawns
		if not spawn_capped:
			var p0_ok: bool = scenario.get("p0", []).size() == 0 or t0_alive.size() >= cap
			var p1_ok: bool = scenario.get("p1", []).size() == 0 or t1_alive.size() >= cap
			if p0_ok and p1_ok:
				for e in sim.entities:
					if e.type == "building":
						e["spawn_interval"] = 0
				spawn_capped = true
				print("    Tick %d: Capped — T0:%d T1:%d" % [sim.tick, t0_alive.size(), t1_alive.size()])

		# Log units
		for e in sim.entities:
			if e.type != "unit":
				continue
			if not _unit_logs.has(e.id):
				_unit_logs[e.id] = []
				print("    Tick %d: SPAWN #%d %s team%d at (%d,%d)" % [
					sim.tick, e.id, e.unit_type, e.team,
					FP.to_int(e.x), FP.to_int(e.y)])

			var prev: Dictionary = _unit_logs[e.id][-1] if _unit_logs[e.id].size() > 0 else {}
			var cx: int = FP.to_int(e.x)
			var cy: int = FP.to_int(e.y)
			var dx: int = cx - prev.get("x", cx)
			var dy: int = cy - prev.get("y", cy)
			var hp_val: int = FP.to_int(e.hp)
			var curr_tgt: int = e.get("target_id", -1)
			var atk_cd: int = e.get("attack_cooldown", 0)
			var atk_speed: int = e.get("attack_speed_ticks", 10)

			# State inference (Euclidean distance + attack cooldown)
			var state: String = "idle"
			if hp_val <= 0:
				state = "dead"
			elif curr_tgt != -1:
				if atk_cd > 0 and atk_cd < atk_speed:
					state = "attacking"
				else:
					var dist: float = _euclidean_dist(sim, e)
					if dist <= FP.to_int(e.attack_range) + 5:
						state = "attacking"
					else:
						state = "chasing"
			elif abs(dx) > 0 or abs(dy) > 0:
				state = "marching"

			# Track first attack
			if first_attack_tick == -1 and state == "attacking":
				first_attack_tick = sim.tick

			# Events
			var prev_tgt: int = prev.get("target", -1)
			if curr_tgt != prev_tgt and _unit_logs[e.id].size() > 0:
				_events_log.append("    Tick %d: #%d %s TARGET %d → %d (%s)" % [
					sim.tick, e.id, e.unit_type, prev_tgt, curr_tgt,
					_describe_target(sim, curr_tgt)])

			var prev_dy: int = prev.get("dy", 0)
			if prev_dy != 0 and dy != 0 and ((prev_dy > 0 and dy < 0) or (prev_dy < 0 and dy > 0)):
				_events_log.append("    Tick %d: #%d %s Y-REVERSAL dy %d→%d at (%d,%d)" % [
					sim.tick, e.id, e.unit_type, prev_dy, dy, cx, cy])

			if hp_val <= 0 and prev.get("hp", 1) > 0:
				_events_log.append("    Tick %d: #%d %s DIED at (%d,%d)" % [
					sim.tick, e.id, e.unit_type, cx, cy])

			_unit_logs[e.id].append({
				"tick": sim.tick, "x": cx, "y": cy, "dx": dx, "dy": dy,
				"hp": hp_val, "target": curr_tgt, "state": state,
				"atk_cd": atk_cd,
			})

		# Track castle damage
		var c0_hp: int = FP.to_int(sim.castles[0].hp)
		var c1_hp: int = FP.to_int(sim.castles[1].hp)
		if first_castle_dmg_tick == -1 and (c0_hp < castle_0_start or c1_hp < castle_1_start):
			first_castle_dmg_tick = sim.tick

		# End conditions
		if sim.match_over:
			print("    Tick %d: MATCH OVER — winner team %d" % [sim.tick, sim.winning_team])
			break
		if spawn_capped and t0_alive.size() == 0 and t1_alive.size() == 0:
			print("    Tick %d: All units dead" % sim.tick)
			break

	# Analyze results
	var result := _analyze_scenario(name, scenario, sim, first_attack_tick, first_castle_dmg_tick)
	_scenario_results.append(result)

	# Print events
	if _events_log.size() > 0:
		print("\n  Events:")
		for ev in _events_log:
			print(ev)

	# Print summaries
	_print_unit_summaries(sim)
	print("\n  %s → %s" % [name, result.verdict])


func _analyze_scenario(name: String, scenario: Dictionary, sim: Simulation,
		first_atk: int, first_castle_dmg: int) -> Dictionary:
	var checks: Array = scenario.get("checks", [])
	var issues: Array = []
	var c0: int = FP.to_int(sim.castles[0].hp)
	var c1: int = FP.to_int(sim.castles[1].hp)

	# Aggregate unit stats
	var total_zigzag: int = 0
	var total_stuck: int = 0  # idle with no target for 30+ ticks
	var total_units: int = _unit_logs.size()
	var engaged_units: int = 0  # had at least one "attacking" state

	for uid in _unit_logs:
		var log: Array = _unit_logs[uid]
		# Zigzag count
		var rev: int = 0; var ldy: int = 0
		for entry in log:
			if entry.dy != 0:
				if ldy != 0 and ((entry.dy > 0 and ldy < 0) or (entry.dy < 0 and ldy > 0)):
					rev += 1
				ldy = entry.dy
		if rev > 5:
			total_zigzag += 1

		# Stuck: idle (no target, not moving) for 30+ consecutive ticks
		var idle_run: int = 0; var max_idle: int = 0
		for entry in log:
			if entry.state == "idle" and entry.target == -1:
				idle_run += 1
				max_idle = maxi(max_idle, idle_run)
			else:
				idle_run = 0
		if max_idle >= 30:
			total_stuck += 1

		# Engaged?
		var atk_count: int = 0
		for entry in log:
			if entry.state == "attacking":
				atk_count += 1
		if atk_count > 0:
			engaged_units += 1

	# Check: engagement
	if "engagement" in checks and total_units > 0:
		var engage_pct: float = float(engaged_units) / total_units
		if engage_pct < 0.5:
			issues.append("LOW ENGAGEMENT: only %d/%d (%.0f%%) units attacked" % [engaged_units, total_units, engage_pct * 100])

	# Check: zigzag
	if "zigzag" in checks and total_zigzag > 0:
		issues.append("ZIGZAG: %d units with 6+ Y-reversals" % total_zigzag)

	# Check: stuck
	if "stuck" in checks and total_stuck > 0:
		issues.append("STUCK: %d units idle 30+ ticks with no target" % total_stuck)

	# Check: castle_attack
	if "castle_attack" in checks:
		if first_castle_dmg == -1:
			issues.append("NO CASTLE DAMAGE: units never hit the castle")
		elif first_castle_dmg > 300:
			issues.append("SLOW SIEGE: castle first hit at tick %d (>30s)" % first_castle_dmg)

	# Check: targeting
	if "targeting" in checks:
		# Verify units don't swap targets excessively
		for uid in _unit_logs:
			var tgt_changes: int = 0; var pt: int = -2
			for entry in _unit_logs[uid]:
				if entry.target != pt:
					tgt_changes += 1; pt = entry.target
			if tgt_changes > 10:
				issues.append("THRASHING: unit #%d changed target %d times" % [uid, tgt_changes])
				break  # Only report once

	# Check: healing
	if "healing" in checks:
		# Check if any unit was healed (HP went up between ticks)
		var healed: bool = false
		for uid in _unit_logs:
			var log: Array = _unit_logs[uid]
			for i in range(1, log.size()):
				if log[i].hp > log[i-1].hp and log[i-1].hp > 0:
					healed = true; break
			if healed:
				break
		if not healed:
			issues.append("NO HEALING: priest never healed any unit")

	var verdict: String = "PASS" if issues.size() == 0 else "FAIL"
	return {
		"scenario": name,
		"desc": scenario.desc,
		"verdict": verdict,
		"issues": issues,
		"units": total_units,
		"engaged": engaged_units,
		"zigzag": total_zigzag,
		"stuck": total_stuck,
		"castle_0_hp": c0,
		"castle_1_hp": c1,
		"first_attack_tick": first_atk,
		"first_castle_dmg_tick": first_castle_dmg,
		"ticks": sim.tick,
	}


func _print_unit_summaries(sim: Simulation) -> void:
	for uid in _unit_logs:
		var log: Array = _unit_logs[uid]
		if log.size() == 0:
			continue
		var first: Dictionary = log[0]
		var last: Dictionary = log[-1]
		var states: Dictionary = {}
		for entry in log:
			states[entry.state] = states.get(entry.state, 0) + 1
		var rev: int = 0; var ldy: int = 0
		for entry in log:
			if entry.dy != 0:
				if ldy != 0 and ((entry.dy > 0 and ldy < 0) or (entry.dy < 0 and ldy > 0)):
					rev += 1
				ldy = entry.dy
		var tgt_ch: int = 0; var pt: int = -2
		for entry in log:
			if entry.target != pt:
				tgt_ch += 1; pt = entry.target

		var utype: String = "?"
		var team: int = -1
		for e in sim.entities:
			if e.id == uid:
				utype = str(e.unit_type); team = e.team; break

		print("    #%d %s t%d | (%d,%d)→(%d,%d) | HP %d→%d | %s | tgt×%d rev×%d" % [
			uid, utype, team, first.x, first.y, last.x, last.y,
			first.hp, last.hp, str(states), tgt_ch, rev])


func _print_final_report() -> void:
	print("\n" + "=".repeat(70))
	print("  BEHAVIOR TEST SUITE — FINAL REPORT")
	print("=".repeat(70))
	print("\n  %-25s %6s %5s %5s %5s %5s  %s" % ["Scenario", "Units", "Engd", "ZZ", "Stk", "Ticks", "Verdict"])
	print("  " + "-".repeat(68))
	var pass_count: int = 0
	var fail_count: int = 0
	for r in _scenario_results:
		var v: String = r.verdict
		if v == "PASS":
			pass_count += 1
		else:
			fail_count += 1
		print("  %-25s %6d %5d %5d %5d %5d  %s" % [
			r.scenario, r.units, r.engaged, r.zigzag, r.stuck, r.ticks, v])
		if r.issues.size() > 0:
			for issue in r.issues:
				print("    → %s" % issue)
	print("  " + "-".repeat(68))
	print("  TOTAL: %d PASS, %d FAIL" % [pass_count, fail_count])


func _save_full_report() -> void:
	var report: Dictionary = {"scenarios": _scenario_results}
	var json := JSON.stringify(report, "  ")
	var f := FileAccess.open("%s/suite_report.json" % OUT_DIR, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	print("  Output: %s/suite_report.json" % OUT_DIR)


# --- Helpers ---

func _euclidean_dist(sim: Simulation, unit: Dictionary) -> float:
	var tgt_id: int = unit.get("target_id", -1)
	if tgt_id == -1:
		return 9999.0
	for e in sim.entities:
		if e.id == tgt_id:
			var dx: float = float(FP.to_int(unit.x) - FP.to_int(e.x))
			var dy: float = float(FP.to_int(unit.y) - FP.to_int(e.y))
			return sqrt(dx * dx + dy * dy)
	return 9999.0


func _describe_target(sim: Simulation, tgt_id: int) -> String:
	if tgt_id == -1:
		return "none"
	for e in sim.entities:
		if e.id == tgt_id:
			if e.type == "castle":
				return "castle t%d" % e.team
			elif e.type == "building":
				return "%s t%d" % [e.building_type, e.team]
			else:
				return "%s#%d t%d hp%d @(%d,%d)" % [
					e.unit_type, e.id, e.team,
					FP.to_int(e.hp), FP.to_int(e.x), FP.to_int(e.y)]
	return "dead"


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
