## Per-matchup duel viewer.
## Runs a real Simulation with two scripted units and (optionally) cluster of
## dummies, renders sprites + range rings + skill VFX, and overlays stats.
##
## Usage:
##   godot --path castle_clash -s tests/test_unit_duel.gd -- --p0 knight --p1 archer
##   godot --path castle_clash -s tests/test_unit_duel.gd -- --p0 mage --p1 footman --dummies 3
##   godot --path castle_clash -s tests/test_unit_duel.gd -- --p0 catapult --p1 grunt --dummies 4
##
## Options (after `--`):
##   --p0 <unit_id>        Team-0 unit (default: footman)
##   --p1 <unit_id>        Team-1 unit (default: grunt)
##   --dummies N           Extra stationary team-1 targets clustered near p1 (default: 0)
##   --spacing PX          Vertical distance between p0 and p1 spawns (default: 220)
##   --duration SEC        Auto-quit after N seconds (default: 30)
##   --headless            Run without visuals (smoke mode)
##
## Controls:
##   SPACE — pause / resume
##   S     — single-step while paused
##   R     — restart match
##   ESC   — quit
extends SceneTree

const TICKS_PER_SECOND: int = 10
const TICK_DURATION: float = 1.0 / TICKS_PER_SECOND
const ARENA_CENTER_X: int = 360
const P0_SPAWN_Y: int = 860
const P1_SPAWN_Y: int = 420
const CELL_SIZE_PX: int = 28

var _sim: Simulation
var _rng_seed: int = 42
var _paused: bool = false
var _tick_accumulator: float = 0.0
var _ticks_elapsed: int = 0
var _max_ticks: int = 300  # 30s
var _step_request: bool = false

# CLI args
var _p0_unit: StringName = &"footman"
var _p1_unit: StringName = &"grunt"
var _dummy_count: int = 0
var _spacing_px: int = 220
var _headless: bool = false

# Visual nodes
var _world: Node2D
var _ui: CanvasLayer
var _rings_node: _RangeRings
var _stats_label: Label
var _tick_label: Label
var _status_label: Label
var _visuals: Dictionary = {}  # entity_id -> {sprite, hp_bar_fill, hp_bar_bg}

# Skill VFX bookkeeping
var _skill_overlays: Array = []

# Effects class_name does not resolve reliably in `-s` mode (Godot autoload/
# class-cache timing), so we provide small inline VFX helpers instead.


func _init() -> void:
	_parse_args()
	# SceneTree scripts: process_frame comes before _process; do setup after first frame.
	await process_frame
	_setup_sim()
	if not _headless:
		_setup_scene()
	print("\n=== DUEL: %s (team 0) vs %s (team 1) ===" % [_p0_unit, _p1_unit])
	if _dummy_count > 0:
		print("  +%d team-1 dummies near %s" % [_dummy_count, _p1_unit])
	print("  spacing=%dpx  duration=%ds  headless=%s" % [_spacing_px, _max_ticks / TICKS_PER_SECOND, str(_headless)])
	print("  SPACE=pause  S=step  R=restart  ESC=quit\n")


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		match a:
			"--p0":
				if i + 1 < args.size():
					_p0_unit = StringName(args[i + 1])
					i += 1
			"--p1":
				if i + 1 < args.size():
					_p1_unit = StringName(args[i + 1])
					i += 1
			"--dummies":
				if i + 1 < args.size():
					_dummy_count = int(args[i + 1])
					i += 1
			"--spacing":
				if i + 1 < args.size():
					_spacing_px = int(args[i + 1])
					i += 1
			"--duration":
				if i + 1 < args.size():
					_max_ticks = int(args[i + 1]) * TICKS_PER_SECOND
					i += 1
			"--headless":
				_headless = true
		i += 1


func _setup_sim() -> void:
	_sim = Simulation.new()
	_sim.register_buildings(_load_all_building_data())
	_sim.initialize(_rng_seed, [
		{"id": 0, "team": 0, "faction": &"kingdom"},
		{"id": 1, "team": 1, "faction": &"kingdom"},
	], {"skip_prep": true})
	# Spawn the duelists at the configured spacing.
	var half: int = _spacing_px / 2
	var p0_y: int = 640 + half
	var p1_y: int = 640 - half
	_spawn_unit(_p0_unit, 0, ARENA_CENTER_X, p0_y)
	_spawn_unit(_p1_unit, 1, ARENA_CENTER_X, p1_y)
	# Add dummies clustered around p1.
	for d in _dummy_count:
		var dx: int = ARENA_CENTER_X - 40 + (d % 3) * 40
		var dy: int = p1_y - 30 + int(d / 3) * 30
		_spawn_unit(_p1_unit, 1, dx, dy)


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


func _spawn_unit(unit_id: StringName, team: int, x_px: int, y_px: int) -> Dictionary:
	var ud: UnitData = load("res://data/units/%s.tres" % String(unit_id))
	if ud == null:
		push_error("[duel] unknown unit: %s" % unit_id)
		return {}
	var eid: int = _sim.next_entity_id
	_sim.next_entity_id += 1
	var entity := {
		"id": eid,
		"type": "unit",
		"team": team,
		"player_index": team,
		"unit_type": unit_id,
		"owner": team,
		"x": FP.from_int(x_px),
		"y": FP.from_int(y_px),
		"prev_x": FP.from_int(x_px),
		"prev_y": FP.from_int(y_px),
		"hp": FP.from_int(ud.max_hp),
		"max_hp": FP.from_int(ud.max_hp),
		"base_attack_damage": FP.from_int(ud.attack_damage),
		"attack_damage": FP.from_int(ud.attack_damage),
		"attack_speed_ticks": ud.attack_speed_ticks,
		"attack_cooldown": 0,
		"attack_range": FP.from_int(ud.attack_range * CELL_SIZE_PX),
		"aggro_range": FP.from_int(ud.aggro_range * CELL_SIZE_PX),
		"move_speed": FP.div(FP.from_int(ud.move_speed * CELL_SIZE_PX * 80), FP.from_int(TICKS_PER_SECOND * 100)),
		"base_move_speed": FP.div(FP.from_int(ud.move_speed * CELL_SIZE_PX * 80), FP.from_int(TICKS_PER_SECOND * 100)),
		"armor": FP.from_int(ud.armor),
		"magic_defense": FP.from_int(ud.magic_defense),
		"bounty": ud.bounty,
		"skill_id": ud.skill_id,
		"skill_id_2": ud.skill_id_2,
		"skill_param_1": ud.skill_param_1,
		"skill_param_2": ud.skill_param_2,
		"skill_param_3": ud.skill_param_3,
		"skill_param_4": ud.skill_param_4,
		"skill_cooldown": 0,
		"skill_stacks": 0,
		"skill_2_cooldown": 0,
		"skill_2_stacks": 0,
		"skill_2_active": false,
		"attack_type": ud.attack_type,
		"armor_type": ud.armor_type,
		"role": ud.role,
		"can_hit_air": ud.can_hit_air,
		"target_id": -1,
		"state": 0,
		"grid_row": -1,
		"grid_col": -1,
		"last_progress_y": FP.from_int(y_px),
		"mana_shield_hp": FP.from_int(ud.skill_param_3) if ud.skill_id_2 == &"mana_shield" else FP.ZERO,
		"arcane_shield_hp": FP.from_int(ud.skill_param_3) if ud.skill_id_2 == &"arcane_shield" else FP.ZERO,
	}
	_sim.entities.append(entity)
	return entity


func _setup_scene() -> void:
	var root: Window = get_root()
	# Background
	_ui = CanvasLayer.new()
	_ui.layer = 0
	root.add_child(_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.18, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(bg)
	# World container for sprites + rings. In SceneTree (`-s`) mode, Node2D
	# under the Window root doesn't render into the main viewport — wrap in a
	# CanvasLayer so it composites like the HUD.
	var world_layer := CanvasLayer.new()
	world_layer.layer = 1
	root.add_child(world_layer)
	_world = Node2D.new()
	_world.name = "DuelWorld"
	world_layer.add_child(_world)
	# Range rings drawn beneath sprites (z_index 0 vs 10)
	_rings_node = _RangeRings.new()
	_rings_node.z_index = 1
	_rings_node.set_sim(_sim)
	_world.add_child(_rings_node)
	# Stats HUD
	var hud := CanvasLayer.new()
	hud.layer = 10
	root.add_child(hud)
	_stats_label = Label.new()
	_stats_label.position = Vector2(12, 12)
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_stats_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_stats_label.add_theme_constant_override("outline_size", 3)
	hud.add_child(_stats_label)
	_tick_label = Label.new()
	_tick_label.position = Vector2(12, 1230)
	_tick_label.add_theme_font_size_override("font_size", 12)
	_tick_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(_tick_label)
	_status_label = Label.new()
	_status_label.position = Vector2(500, 1230)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	hud.add_child(_status_label)
	# Spawn sprite visuals for existing entities
	for e in _sim.entities:
		if e.type == "unit":
			_attach_visual(e)


func _attach_visual(entity: Dictionary) -> void:
	# Keep the duel viewer independent of SpriteRegistry/sprite_unit_visual — those
	# paths have autoload-timing surprises in `-s` mode. The duel viewer's purpose
	# is tactical combat visualization (ranges, skill VFX, HP), not sprite QA
	# (which test_unit_showcase.gd covers).
	var container := _UnitMarker.new()
	container.position = Vector2(FP.to_float(entity.x), FP.to_float(entity.y))
	container.z_index = 10
	container.team = entity.team
	container.role = int(entity.get("role", 0))
	container.unit_name = String(entity.unit_type)
	_world.add_child(container)
	_visuals[entity.id] = {"container": container}


func _process(delta: float) -> bool:
	# Guard against _process firing before async _init() finishes (await process_frame).
	if _sim == null:
		return false
	if not _headless:
		_handle_input()
	if not _paused or _step_request:
		_tick_accumulator += delta
		while _tick_accumulator >= TICK_DURATION:
			_tick_accumulator -= TICK_DURATION
			_run_one_tick()
			if _step_request:
				_step_request = false
				_tick_accumulator = 0.0
				_paused = true
				break
	if not _headless:
		_sync_visuals()
		_update_hud()
	# Auto-quit on timeout or both sides eliminated
	if _ticks_elapsed >= _max_ticks or _all_one_side_dead():
		if not _headless:
			# Hold on screen for a moment then quit
			if _ticks_elapsed >= _max_ticks + 30:
				quit()
		else:
			_print_summary()
			quit()
	return false


func _handle_input() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		quit()
	if Input.is_key_pressed(KEY_SPACE) and not _space_held:
		_paused = not _paused
		_space_held = true
	elif not Input.is_key_pressed(KEY_SPACE):
		_space_held = false
	if Input.is_key_pressed(KEY_S) and not _s_held:
		if _paused:
			_step_request = true
		_s_held = true
	elif not Input.is_key_pressed(KEY_S):
		_s_held = false
	if Input.is_key_pressed(KEY_R) and not _r_held:
		_restart()
		_r_held = true
	elif not Input.is_key_pressed(KEY_R):
		_r_held = false


var _space_held: bool = false
var _s_held: bool = false
var _r_held: bool = false


func _run_one_tick() -> void:
	var result: Dictionary = _sim.step([])
	_ticks_elapsed += 1
	var events: Array = result.get("events", [])
	for ev in events:
		_handle_event(ev)


func _handle_event(ev: Dictionary) -> void:
	if _headless:
		# Only log noteworthy events in headless mode
		var t: String = ev.get("type", "")
		if t == "unit_died" or t == "skill_proc":
			print("  tick %d: %s" % [_ticks_elapsed, str(ev)])
		return
	match ev.get("type", ""):
		"unit_attacked":
			var target = _find_entity(ev.target_id)
			if target.is_empty():
				return
			var damage: int = FP.to_int(ev.damage)
			var pos := Vector2(FP.to_float(target.x), FP.to_float(target.y))
			_spawn_damage_number(damage, pos, false)
			# Draw a quick projectile from attacker to target for ranged units
			var attacker = _find_entity(ev.attacker_id)
			if not attacker.is_empty() and attacker.get("type", "") == "unit":
				var from_pos := Vector2(FP.to_float(attacker.x), FP.to_float(attacker.y))
				var atk_type: int = attacker.get("attack_type", 0)
				var role: int = attacker.get("role", 0)
				var color := Color(0.3, 0.7, 1.0) if attacker.team == 0 else Color(1.0, 0.4, 0.3)
				if role == 1 or atk_type == 1 or atk_type == 2 or role == 4:
					_spawn_projectile(from_pos, pos, color)
		"unit_healed":
			var target = _find_entity(ev.target_id)
			if target.is_empty():
				return
			var pos := Vector2(FP.to_float(target.x), FP.to_float(target.y))
			_spawn_damage_number(FP.to_int(ev.amount), pos, true)
		"skill_proc":
			_handle_skill_proc(ev)
		"unit_died":
			var v = _visuals.get(ev.unit_id, {})
			if v.has("container") and v.container:
				_spawn_skill_ring(v.container.position, 28.0, Color(1.0, 0.6, 0.15))
				v.container.queue_free()
				_visuals.erase(ev.unit_id)


func _handle_skill_proc(ev: Dictionary) -> void:
	var skill: String = ev.get("skill", "")
	var unit_id: int = ev.get("unit_id", -1)
	var attacker = _find_entity(unit_id)
	if attacker == null:
		return
	var attacker_pos := Vector2(FP.to_float(attacker.x), FP.to_float(attacker.y))
	match skill:
		"fireball":
			# Draw a splash ring at center
			var center := Vector2(float(ev.get("center_x", attacker.x)), float(ev.get("center_y", attacker.y)))
			if ev.has("center_x"):
				center = Vector2(FP.to_float(ev.center_x), FP.to_float(ev.center_y))
			_spawn_skill_ring(center, 42.0, Color(1.0, 0.5, 0.15))
		"boulder_splash":
			# Catapult: splash around the primary target; approximate center from attacker target
			var center := attacker_pos
			_spawn_skill_ring(center, float(attacker.get("skill_param_2", 40)), Color(0.85, 0.65, 0.3))
		"lance_pierce":
			var targets: Array = ev.get("targets", [])
			if targets.size() > 0:
				var last_id: int = targets[-1]
				var last = _find_entity(last_id)
				if last != null:
					var end_pos := Vector2(FP.to_float(last.x), FP.to_float(last.y))
					_spawn_pierce_line(attacker_pos, end_pos)
		"arcane_shield", "mana_shield":
			_spawn_skill_ring(attacker_pos, 30.0, Color(0.4, 0.8, 1.0))
		"arcane_shield_break", "mana_shield_break":
			_spawn_skill_ring(attacker_pos, 35.0, Color(1.0, 1.0, 0.4))
		_:
			pass


func _spawn_skill_ring(center: Vector2, radius: float, color: Color) -> void:
	var ring := _SkillRing.new()
	ring.position = center
	ring.z_index = 95
	ring.radius = radius
	ring.color = color
	_world.add_child(ring)


func _spawn_pierce_line(from_pos: Vector2, to_pos: Vector2) -> void:
	var line := _PierceLine.new()
	line.from_pos = from_pos
	line.to_pos = to_pos
	line.z_index = 94
	_world.add_child(line)


func _spawn_damage_number(value: int, pos: Vector2, is_heal: bool) -> void:
	var node := _DamageNumber.new()
	node.position = pos
	node.value = value
	node.is_heal = is_heal
	node.z_index = 100
	_world.add_child(node)


func _spawn_projectile(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	var node := _DuelProjectile.new()
	node.position = from_pos
	node.target_pos = to_pos
	node.color = color
	node.z_index = 80
	_world.add_child(node)


func _sync_visuals() -> void:
	for e in _sim.entities:
		if e.type != "unit":
			continue
		var v = _visuals.get(e.id, null)
		if v == null:
			continue
		v.container.position = Vector2(FP.to_float(e.x), FP.to_float(e.y))
		var hp_ratio: float = FP.to_float(e.hp) / FP.to_float(e.max_hp)
		v.container.hp_ratio = clampf(hp_ratio, 0.0, 1.0)
		v.container.queue_redraw()
	if _rings_node:
		_rings_node.queue_redraw()


func _update_hud() -> void:
	var t0: Dictionary = _find_duelist(0)
	var t1: Dictionary = _find_duelist(1)
	var lines: Array[String] = []
	lines.append("[TEAM 0] %s" % _format_unit_stats(t0))
	lines.append("")
	lines.append("[TEAM 1] %s" % _format_unit_stats(t1))
	_stats_label.text = "\n".join(lines)
	_tick_label.text = "tick %d / %d   (%.1fs / %.1fs)" % [
		_ticks_elapsed, _max_ticks,
		float(_ticks_elapsed) / TICKS_PER_SECOND, float(_max_ticks) / TICKS_PER_SECOND,
	]
	var status := ""
	if _paused:
		status = "[PAUSED — SPACE to resume, S to step]"
	elif _all_one_side_dead():
		status = "[MATCH OVER]"
	_status_label.text = status


func _find_duelist(team: int) -> Dictionary:
	for e in _sim.entities:
		if e.type == "unit" and e.team == team:
			return e
	return {}


func _format_unit_stats(e: Dictionary) -> String:
	if e.is_empty():
		return "(defeated)"
	var hp: int = FP.to_int(e.hp)
	var max_hp: int = FP.to_int(e.max_hp)
	var dmg: int = FP.to_int(e.attack_damage)
	var dps: float = float(dmg) * TICKS_PER_SECOND / float(max(e.attack_speed_ticks, 1))
	var atk_range: int = FP.to_int(e.attack_range)
	var armor: int = FP.to_int(e.armor)
	var mdef: int = FP.to_int(e.magic_defense)
	var atk_type_names := ["Physical", "Pierce", "Magic", "Siege"]
	var armor_type_names := ["Light", "Medium", "Heavy", "Fortified"]
	var skill_line := ""
	if e.skill_id != &"":
		skill_line += "  skill=%s" % String(e.skill_id)
	if e.skill_id_2 != &"":
		skill_line += "  skill2=%s" % String(e.skill_id_2)
	return "%s  HP %d/%d  DMG %d (%.1f DPS)  RNG %dpx  %s→%s armor=%d mdef=%d%s" % [
		String(e.unit_type), hp, max_hp, dmg, dps, atk_range,
		atk_type_names[clampi(e.attack_type, 0, 3)],
		armor_type_names[clampi(e.armor_type, 0, 3)],
		armor, mdef, skill_line,
	]


func _find_entity(eid: int) -> Dictionary:
	for e in _sim.entities:
		if e.id == eid:
			return e
	return {}


func _all_one_side_dead() -> bool:
	var alive_0 := 0
	var alive_1 := 0
	for e in _sim.entities:
		if e.type == "unit" and FP.gt(e.hp, FP.ZERO):
			if e.team == 0:
				alive_0 += 1
			else:
				alive_1 += 1
	return alive_0 == 0 or alive_1 == 0


func _restart() -> void:
	for eid in _visuals.keys():
		var v = _visuals[eid]
		if v.container:
			v.container.queue_free()
	_visuals.clear()
	_ticks_elapsed = 0
	_tick_accumulator = 0.0
	_paused = false
	_setup_sim()
	if not _headless:
		for e in _sim.entities:
			if e.type == "unit":
				_attach_visual(e)


func _print_summary() -> void:
	print("\n=== DUEL RESULT (tick %d) ===" % _ticks_elapsed)
	for e in _sim.entities:
		if e.type != "unit":
			continue
		var hp: int = FP.to_int(e.hp)
		var status := "ALIVE" if hp > 0 else "DEAD"
		print("  team %d %s  HP=%d/%d  %s" % [e.team, String(e.unit_type), hp, FP.to_int(e.max_hp), status])


# --------------------------------------------------------------------------------------
# Inline visual classes
# --------------------------------------------------------------------------------------

## Draws aggro + attack range circles for each live unit.
class _RangeRings extends Node2D:
	var _sim_ref: Simulation

	func set_sim(s: Simulation) -> void:
		_sim_ref = s

	func _draw() -> void:
		if _sim_ref == null:
			return
		for e in _sim_ref.entities:
			if e.type != "unit":
				continue
			if FP.lte(e.hp, FP.ZERO):
				continue
			var pos := Vector2(FP.to_float(e.x), FP.to_float(e.y))
			var atk_r: float = FP.to_float(e.attack_range)
			var agg_r: float = FP.to_float(e.aggro_range)
			var atk_color := Color(0.4, 0.9, 0.4, 0.55) if e.team == 0 else Color(0.9, 0.4, 0.4, 0.55)
			var agg_color := Color(0.3, 0.6, 1.0, 0.25) if e.team == 0 else Color(1.0, 0.6, 0.3, 0.25)
			# Aggro ring (dashed-ish via many short arcs)
			draw_arc(pos, agg_r, 0.0, TAU, 48, agg_color, 1.0, false)
			# Attack ring (solid)
			draw_arc(pos, atk_r, 0.0, TAU, 48, atk_color, 2.0, false)


## Expanding fading ring for splash/shield VFX.
class _SkillRing extends Node2D:
	var radius: float = 40.0
	var color: Color = Color(1, 1, 1, 0.8)
	var _age: float = 0.0
	const LIFETIME: float = 0.5

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
		var cur_radius: float = radius * (0.4 + 0.8 * t)
		var a: float = (1.0 - t) * color.a
		draw_arc(Vector2.ZERO, cur_radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, a), 3.0, false)
		draw_arc(Vector2.ZERO, cur_radius - 4.0, 0.0, TAU, 48, Color(color.r, color.g, color.b, a * 0.4), 2.0, false)


## Fading straight line for lance_pierce VFX.
class _PierceLine extends Node2D:
	var from_pos: Vector2
	var to_pos: Vector2
	var _age: float = 0.0
	const LIFETIME: float = 0.35

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
		var a: float = 1.0 - t
		var col := Color(1.0, 0.9, 0.4, a)
		draw_line(from_pos, to_pos, col, 3.0, true)
		draw_line(from_pos, to_pos, Color(1.0, 1.0, 1.0, a * 0.8), 1.5, true)


## Floating damage/heal number (inline to avoid Effects class_name coupling).
class _DamageNumber extends Node2D:
	var value: int = 0
	var is_heal: bool = false
	var _age: float = 0.0
	const LIFETIME: float = 0.7
	var _start_y: float = 0.0

	func _ready() -> void:
		_start_y = position.y
		var label := Label.new()
		label.text = ("+%d" if is_heal else "%d") % value
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14 if value < 15 else 18)
		label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.35) if is_heal else Color(1.0, 0.95, 0.3))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override("outline_size", 3)
		label.position = Vector2(-24, -18)
		label.size = Vector2(48, 20)
		add_child(label)

	func _process(delta: float) -> void:
		_age += delta
		var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
		position.y = _start_y - 30.0 * t
		modulate.a = 1.0 - t
		if _age >= LIFETIME:
			queue_free()


## Simple circle-with-label unit marker for the duel viewer.
class _UnitMarker extends Node2D:
	var team: int = 0
	var role: int = 0
	var unit_name: String = ""
	var hp_ratio: float = 1.0
	const BODY_R: float = 14.0

	func _draw() -> void:
		var body_col := Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
		# Role-coded outline (melee=gray, ranged=yellow, caster=purple, flying=cyan, siege=orange)
		var outline_col := Color(0.2, 0.2, 0.2)
		match role:
			1: outline_col = Color(1.0, 0.85, 0.2)
			2: outline_col = Color(0.8, 0.5, 1.0)
			3: outline_col = Color(0.4, 1.0, 1.0)
			4: outline_col = Color(1.0, 0.6, 0.2)
		draw_circle(Vector2.ZERO, BODY_R + 2.0, outline_col)
		draw_circle(Vector2.ZERO, BODY_R, body_col)
		# Facing tick (team 0 up-arrow, team 1 down-arrow)
		var tip: Vector2 = Vector2(0, -BODY_R - 6) if team == 0 else Vector2(0, BODY_R + 6)
		draw_line(Vector2.ZERO, tip, Color(1, 1, 1, 0.8), 2.0)
		# HP bar
		var bar_w: float = 30.0
		var bar_y: float = -BODY_R - 14.0
		draw_rect(Rect2(Vector2(-bar_w * 0.5 - 1, bar_y - 1), Vector2(bar_w + 2, 5)), Color(0, 0, 0, 0.85))
		var fill_col := Color(0.3, 1.0, 0.3)
		if hp_ratio <= 0.25:
			fill_col = Color(1.0, 0.3, 0.3)
		elif hp_ratio <= 0.5:
			fill_col = Color(1.0, 0.85, 0.2)
		draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_ratio, 3)), fill_col)

	func _ready() -> void:
		var lbl := Label.new()
		lbl.text = unit_name
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0) if team == 0 else Color(1.0, 0.6, 0.55))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.position = Vector2(-35, BODY_R + 4)
		lbl.size = Vector2(70, 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lbl)


## Fading projectile dot for duel viewer (team-colored).
class _DuelProjectile extends Node2D:
	var target_pos: Vector2
	var color: Color = Color(1, 1, 1)
	var _age: float = 0.0
	const LIFETIME: float = 0.18
	var _start: Vector2

	func _ready() -> void:
		_start = position

	func _process(delta: float) -> void:
		_age += delta
		var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
		position = _start.lerp(target_pos, t)
		queue_redraw()
		if _age >= LIFETIME:
			queue_free()

	func _draw() -> void:
		var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
		var a: float = 1.0 - t * 0.3
		draw_circle(Vector2.ZERO, 5.0, Color(color.r, color.g, color.b, a))
		draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, a * 0.9))
