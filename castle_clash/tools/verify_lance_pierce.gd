## T-076 smoke test: verify lance_pierce hits multiple enemies in a line.
## Run: godot --headless --path castle_clash -s tools/verify_lance_pierce.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	await process_frame
	_run()
	_print()
	quit(1 if _fail > 0 else 0)


func _assert(cond: bool, desc: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % desc)
	else:
		_fail += 1
		print("  FAIL: %s" % desc)


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


func _make_unit(id: int, team: int, x_px: int, y_px: int, hp: int = 200) -> Dictionary:
	# Approximate the fields _perform_attack reads. Reuse footman defaults.
	return {
		"id": id,
		"type": "unit",
		"team": team,
		"player_index": team,
		"unit_type": &"footman",
		"x": FP.from_int(x_px),
		"y": FP.from_int(y_px),
		"hp": FP.from_int(hp),
		"max_hp": FP.from_int(hp),
		"attack_damage": FP.from_int(10),
		"attack_speed_ticks": 10,
		"attack_cooldown": 0,
		"attack_range": FP.from_int(28),
		"aggro_range": FP.from_int(7 * 28),
		"move_speed": FP.from_int(2 * 28),
		"armor": FP.from_int(0),
		"magic_defense": FP.from_int(0),
		"bounty": 5,
		"role": 0,
		"target_id": -1,
		"state": 0,
		"attack_type": 0,
		"armor_type": 0,
		"skill_id": &"",
		"skill_id_2": &"",
		"skill_param_1": 0,
		"skill_param_2": 0,
		"skill_param_3": 0,
		"skill_param_4": 0,
	}


func _run() -> void:
	print("\n=== T-076 Lance Pierce Smoke Test ===\n")

	var sim := Simulation.new()
	sim.register_buildings(_load_buildings())
	sim.initialize(42, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})

	# Build a Lancer attacker at x=400, y=500 facing UP (decreasing Y)
	var lancer := _make_unit(100, 0, 400, 500, 350)
	lancer.unit_type = &"knight"
	lancer.attack_damage = FP.from_int(22)
	lancer.attack_range = FP.from_int(28)  # 1 cell
	lancer.armor_type = 2  # Heavy
	lancer.skill_id_2 = &"lance_pierce"
	lancer.skill_param_3 = 20  # width px
	lancer.skill_param_4 = 70  # falloff %
	sim.entities.append(lancer)

	# Place 4 enemies in a vertical line, decreasing Y. Lancer→primary distance = 30,
	# attack_range = 28, so the line extends to proj = 58 from lancer = 28 past primary.
	# Secondaries must fit within 28px past primary (y >= 442).
	var primary := _make_unit(101, 1, 400, 470, 200)  # proj=30
	var line2 := _make_unit(102, 1, 400, 460, 200)    # proj=40 (10 past primary)
	var line3 := _make_unit(103, 1, 400, 452, 200)    # proj=48 (18 past primary)
	var line4 := _make_unit(104, 1, 400, 444, 200)    # proj=56 (26 past primary, just inside)
	# Off-line enemy 50px away laterally — should NOT be hit
	var off_line := _make_unit(105, 1, 450, 460, 200)
	for u in [primary, line2, line3, line4, off_line]:
		sim.entities.append(u)

	var pre_hp := []
	for u in [primary, line2, line3, line4, off_line]:
		pre_hp.append(FP.to_int(u.hp))

	# Force the attack via _perform_attack, bypass cooldown / range checks
	var events: Array[Dictionary] = sim._perform_attack(lancer, primary)

	var post_hp := []
	for u in [primary, line2, line3, line4, off_line]:
		post_hp.append(FP.to_int(u.hp))
	print("  HP before: %s" % str(pre_hp))
	print("  HP after:  %s" % str(post_hp))

	# Primary takes full damage (from main attack code, not skill)
	var primary_dmg: int = pre_hp[0] - post_hp[0]
	_assert(primary_dmg > 0, "primary hit (lost %d HP)" % primary_dmg)

	# Secondaries take falloff damage
	var dmg2: int = pre_hp[1] - post_hp[1]
	var dmg3: int = pre_hp[2] - post_hp[2]
	var dmg4: int = pre_hp[3] - post_hp[3]
	_assert(dmg2 > 0, "line2 hit (lost %d HP)" % dmg2)
	_assert(dmg3 > 0, "line3 hit (lost %d HP)" % dmg3)
	_assert(dmg4 > 0, "line4 hit (lost %d HP)" % dmg4)

	# Falloff: each subsequent hit should be ≤ previous (70% of previous, monotonic decreasing)
	_assert(dmg2 <= primary_dmg, "line2 ≤ primary (%d ≤ %d)" % [dmg2, primary_dmg])
	_assert(dmg3 <= dmg2, "line3 ≤ line2 (%d ≤ %d)" % [dmg3, dmg2])
	_assert(dmg4 <= dmg3, "line4 ≤ line3 (%d ≤ %d)" % [dmg4, dmg3])

	# Off-line enemy not hit
	var off_dmg: int = pre_hp[4] - post_hp[4]
	_assert(off_dmg == 0, "off-line enemy NOT hit (lost %d HP, expected 0)" % off_dmg)

	# skill_proc event emitted with targets array
	var found_skill_proc := false
	var target_count := 0
	for ev in events:
		if ev.get("type", "") == "skill_proc" and ev.get("skill", "") == "lance_pierce":
			found_skill_proc = true
			target_count = ev.get("targets", []).size()
			break
	_assert(found_skill_proc, "skill_proc event emitted")
	_assert(target_count >= 4, "skill_proc has >= 4 targets (got %d, primary + 3 secondaries)" % target_count)


func _print() -> void:
	print("\n=== Lance Pierce Smoke Test Results ===")
	print("PASS: %d / FAIL: %d" % [_pass, _fail])
	if _fail == 0:
		print("ALL PASS")
