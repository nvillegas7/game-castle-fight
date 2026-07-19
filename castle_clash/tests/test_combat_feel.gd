## Combat/movement FEEL regression. Logic-level checks on the visual layer's
## speed/timing math — no rendering, runs headless. Grows with each 1C fix.
## Run: godot --headless -s tests/test_combat_feel.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	print("\n=== COMBAT FEEL ===\n")
	_test_walk_cadence()
	_test_ability_activation()
	_test_fireball_center_payload()
	_test_no_dead_skill_branches()
	_test_wrath_refusal_feedback()
	_test_aoe_swing_dedupe()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


func _test_walk_cadence() -> void:
	print("[Walk cadence ratio (BUG-40)]")
	# Footman reference speed (4.48 px/tick) → legs at 1.0x, matching ground travel.
	var footman: float = CombatTuning.walk_ratio_for_speed(4.48)
	_ok("footman (4.48 px/tick) -> ~1.0x cadence", is_equal_approx(footman, 1.0),
		"got %f" % footman)
	# Guards against the old bug: baseline 44.8 (px/SEC) gave ratio ~0.10 = foot-skate.
	_ok("not the old ~10%% foot-skate cadence", footman > 0.5,
		"ratio %f looks like the px/sec-baseline bug" % footman)
	# Faster unit cycles legs faster; slower slower; stationary safe.
	_ok("2x speed -> ~2x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(8.96), 2.0),
		"got %f" % CombatTuning.walk_ratio_for_speed(8.96))
	_ok("half speed -> ~0.5x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(2.24), 0.5),
		"got %f" % CombatTuning.walk_ratio_for_speed(2.24))
	_ok("stationary -> 1.0 (no divide-by-zero)", CombatTuning.walk_ratio_for_speed(0.0) == 1.0)


## 1D-2: the fireball splash must render from the EVENT payload, not a live
## sim re-lookup (the sim advances before the visual layer handles the event).
func _test_fireball_center_payload() -> void:
	print("[Fireball splash center payload (1D-2)]")
	# (a) construction: game_manager's skill_proc dispatch must forward the
	# center to EventBus (the old arm dropped it).
	var gm_src: String = FileAccess.get_file_as_string("res://autoload/game_manager.gd")
	var arm: int = gm_src.find("\"skill_proc\":")
	var arm_src: String = gm_src.substr(arm, 260) if arm >= 0 else ""
	_ok("skill_proc dispatch forwards center payload",
		arm_src.contains("center_x"), "game_manager skill_proc arm drops center_x/center_y")
	# (b) the visual handler must NOT re-look-up the live sim
	var ga_src: String = FileAccess.get_file_as_string("res://scripts/game/game_arena.gd")
	var handler: int = ga_src.find("func _on_skill_activated")
	var handler_src: String = ga_src.substr(handler, 900) if handler >= 0 else ""
	_ok("skill handler has no live-sim private re-lookup",
		not handler_src.contains("_find_entity_by_id"),
		"fireball splash still re-looks-up the moving target in the live sim")


## 1D-4: every per-skill VFX/SFX branch must correspond to a skill the sim
## actually procs — dead branches imply feedback the player can never see.
func _test_no_dead_skill_branches() -> void:
	print("[No dead skill VFX/SFX branches (1D-4)]")
	var sim_src: String = FileAccess.get_file_as_string("res://core/simulation.gd")
	var proc_re := RegEx.new()
	proc_re.compile("\"skill\": \"([a-z_]+)\"")
	var procd := {}
	for m in proc_re.search_all(sim_src):
		procd[m.get_string(1)] = true
	var branch_re := RegEx.new()
	branch_re.compile("&\"([a-z_]+)\":")
	# Generic effect ids used internally by effects.gd, not skill branches.
	var generic := {"dust": true, "explosion": true, "fire": true, "heal_effect": true}
	var dead: Array = []
	for src_path in ["res://scripts/game/effects.gd", "res://autoload/sfx.gd"]:
		var src: String = FileAccess.get_file_as_string(src_path)
		# Only scan the skill-dispatch match blocks (create_skill_effect / play_skill)
		var start: int = src.find("create_skill_effect") if src_path.contains("effects") else src.find("func play_skill")
		var block: String = src.substr(start, 3600) if start >= 0 else ""
		for m in branch_re.search_all(block):
			var id := m.get_string(1)
			if not procd.has(id) and not generic.has(id):
				dead.append("%s: &\"%s\"" % [src_path.get_file(), id])
	_ok("no dead per-skill branches (sim never procs them)", dead.is_empty(), str(dead))


## 1D-3: a refused Castle Wrath must produce visible feedback — the sim emits
## castle_wrath_refused but nothing listened (silent refusal).
func _test_wrath_refusal_feedback() -> void:
	print("[Castle Wrath refusal feedback (1D-3)]")
	var ga: String = FileAccess.get_file_as_string("res://scripts/game/game_arena.gd")
	_ok("game_arena listens to castle_wrath_refused",
		ga.contains("castle_wrath_refused.connect"),
		"refusals are silent — no shake/toast handler connected")


## 1C-4: an AoE attack emits N unit_attacked events (one per victim) — the
## attacker's swing/SFX/projectile must fire ONCE per attack, not N times.
func _test_aoe_swing_dedupe() -> void:
	print("[AoE attacker-FX dedupe (1C-4)]")
	var ga: String = FileAccess.get_file_as_string("res://scripts/game/game_arena.gd")
	_ok("attacker FX guarded per attacker per tick",
		ga.contains("_attacker_fx_tick"),
		"multi-victim events replay the swing/projectile per victim")


func _test_ability_activation() -> void:
	print("[Ability activation event (1D)]")
	var sim := Simulation.new()
	var buildings: Array = []
	var dir := DirAccess.open("res://data/buildings/")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				var bd = load("res://data/buildings/" + f)
				if bd:
					buildings.append(bd)
			f = dir.get_next()
	sim.register_buildings(buildings)
	sim.initialize(12345, [
		{"id": 0, "team": 0, "faction": &"kingdom", "perk": &""},
		{"id": 1, "team": 1, "faction": &"horde", "perk": &""},
	])
	sim.players[0].gold = FP.from_int(1000)
	# War Horn requires a Barracks; place it first.
	sim.step([Command.place_building(0, &"barracks", 0, 0)])
	sim.step([Command.place_building(0, &"war_horn", 4, 0)])
	var wh = null
	for e in sim.entities:
		if e.get("building_type", &"") == &"war_horn":
			wh = e
			break
	_ok("war_horn placed", wh != null, "not found")
	if wh == null:
		return
	wh.ability_mana = wh.ability_max_mana  # fully charge (skip the timed ramp)
	var result = sim.step([Command.activate_building(0, wh.id)])
	var ev = null
	for e in result.events:
		if e.get("type", "") == "ability_activated":
			ev = e
			break
	# The bug: this event was emitted by the sim but game_manager had no dispatch
	# arm for it, so enemy War Horn/Blood Totem activations were invisible. This
	# asserts the sim contract the new arm reads.
	_ok("activation emits ability_activated", ev != null, "no ability_activated event")
	if ev:
		_ok("event carries building_id/team/ability/duration",
			ev.get("building_id", -1) == wh.id and ev.get("team", -99) == 0
			and ev.get("ability", "") == "rally_cry" and ev.get("duration", 0) == 100,
			"got %s" % str(ev))
