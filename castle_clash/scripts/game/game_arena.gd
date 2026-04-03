## Main game scene controller. Manages the arena, building and unit visuals,
## and wires UI to the grid overlay.
extends Node2D

const UnitVisualScript = preload("res://scripts/game/unit_visual.gd")
const BuildingVisualScript = preload("res://scripts/game/building_visual.gd")

const CELL_SIZE: int = 32
const GRID_COLS: int = 11
const GRID_ROWS: int = 20
const GRID_ORIGIN_Y: int = 40
const ZONE_0_ORIGIN_X: int = 80
const ZONE_1_ORIGIN_X: int = 848

@onready var grid_overlay_0: Node2D = $BuildZone0/GridOverlay
@onready var grid_overlay_1: Node2D = $BuildZone1/GridOverlay
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var units_layer: Node2D = $UnitsLayer
@onready var building_menu: PanelContainer = $UILayer/BuildingMenu

var _building_visuals: Dictionary = {}  # entity_id -> Node2D
var _unit_visuals: Dictionary = {}      # entity_id -> Node2D

const ROLE_CHARS := ["M", "R", "C", "F", "S"]  # Melee, Ranged, Caster, Flying, Siege

# --- Simple AI for player 1 ---
const AI_PLAYER_ID: int = 1
const AI_THINK_INTERVAL: float = 3.0  # Seconds between AI decisions
var _ai_timer: float = 2.0  # Start slightly earlier so AI places before first wave


@onready var wave_label: Label = $UILayer/WaveAnnouncement
@onready var castle_hp_bar_0: ColorRect = $CastleHPBar0
@onready var castle_hp_bar_1: ColorRect = $CastleHPBar1

var _wave_announce_timer: float = 0.0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _original_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.wave_started.connect(_on_wave_announced)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_healed.connect(_on_unit_healed)
	EventBus.castle_damaged.connect(_on_castle_hit)

	grid_overlay_0.player_index = 0
	grid_overlay_1.player_index = 1

	building_menu.building_selected.connect(_on_building_selected)
	_original_position = position

	if wave_label:
		wave_label.visible = false

	GameManager.start_test_match()


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.simulation == null:
		return
	_sync_unit_positions()
	_update_castle_hp_bars()
	_update_wave_announcement(delta)
	_update_screen_shake(delta)
	_update_ai(delta)


func _on_building_selected(bd: BuildingData) -> void:
	var local_index: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	var grid: Node2D = grid_overlay_0 if local_index == 0 else grid_overlay_1
	grid.select_building(bd)


func grid_to_screen(player_index: int, grid_x: int, grid_y: int) -> Vector2:
	var origin_x: int = ZONE_0_ORIGIN_X if player_index == 0 else ZONE_1_ORIGIN_X
	return Vector2(
		origin_x + grid_x * CELL_SIZE,
		GRID_ORIGIN_Y + grid_y * CELL_SIZE
	)


# --- Building Visuals ---

func _on_building_placed(player_id: int, building_data: BuildingData, grid_pos: Vector2i) -> void:
	var player_index: int = GameManager.simulation.get_player_index(player_id)

	var entity_id: int = -1
	for entity in GameManager.simulation.entities:
		if entity.type == "building" and entity.owner == player_id \
		   and entity.grid_x == grid_pos.x and entity.grid_y == grid_pos.y:
			entity_id = entity.id

	var visual := _create_building_visual(building_data, player_index, grid_pos)
	buildings_layer.add_child(visual)
	if entity_id >= 0:
		_building_visuals[entity_id] = visual

	# Placement animation: pop in
	visual.scale = Vector2(0.5, 0.5)
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


func _create_building_visual(bd: BuildingData, player_index: int, grid_pos: Vector2i) -> Node2D:
	var screen_pos := grid_to_screen(player_index, grid_pos.x, grid_pos.y)
	var w: float = bd.grid_size.x * CELL_SIZE - 4
	var h: float = bd.grid_size.y * CELL_SIZE - 4

	var bv: Node2D = BuildingVisualScript.new()
	bv.position = screen_pos + Vector2(bd.grid_size.x * CELL_SIZE * 0.5, bd.grid_size.y * CELL_SIZE * 0.5)
	bv.setup(player_index, bd.id, bd.tier, bd.display_name, w, h)
	return bv


func _on_building_destroyed(building_id: int) -> void:
	if _building_visuals.has(building_id):
		_building_visuals[building_id].queue_free()
		_building_visuals.erase(building_id)
	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


# --- Unit Visuals ---

func _on_unit_spawned(unit_id: int, _unit_type: StringName) -> void:
	var entity: Dictionary = {}
	for e in GameManager.simulation.entities:
		if e.id == unit_id:
			entity = e
			break
	if entity.is_empty():
		return

	var visual := _create_unit_visual(entity)
	units_layer.add_child(visual)
	_unit_visuals[unit_id] = visual

	# Spawn animation: scale from 0 to 1 + burst ring
	visual.scale = Vector2(0.1, 0.1)
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var spawn_color := Color(0.3, 0.6, 1.0) if entity.team == 0 else Color(1.0, 0.35, 0.3)
	units_layer.add_child(Effects.create_spawn_burst(visual.position, spawn_color))


func _create_unit_visual(entity: Dictionary) -> Node2D:
	var uv: Node2D = UnitVisualScript.new()
	uv.position = Vector2(FP.to_float(entity.x), FP.to_float(entity.y))
	uv.team = entity.team
	uv.role = entity.get("role", 0)
	uv.unit_type = entity.get("unit_type", &"")
	uv.hp_ratio = 1.0
	uv.facing = 1.0 if entity.team == 0 else -1.0
	return uv


func _on_unit_died(unit_id: int, _killer_id: int) -> void:
	if _unit_visuals.has(unit_id):
		var visual = _unit_visuals[unit_id]
		var death_pos: Vector2 = visual.position
		var team_color := Color(0.3, 0.6, 1.0) if visual.team == 0 else Color(1.0, 0.35, 0.3)
		# Death poof
		units_layer.add_child(Effects.create_death_poof(death_pos, team_color))
		# Shrink-out tween instead of instant vanish
		_unit_visuals.erase(unit_id)
		var tween := visual.create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector2(0.0, 0.0), 0.15).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "modulate:a", 0.0, 0.15)
		tween.set_parallel(false)
		tween.tween_callback(visual.queue_free)


func _on_unit_attacked(_attacker_id: int, target_id: int, damage: int, target_x: float, target_y: float) -> void:
	var target_pos := Vector2(target_x, target_y)
	# Damage number
	units_layer.add_child(Effects.create_damage_number(damage, target_pos))
	# Hit flash on target visual
	if _unit_visuals.has(target_id):
		_unit_visuals[target_id].flash_hit()
	# Projectile from attacker to target (for ranged units)
	if _unit_visuals.has(_attacker_id):
		var attacker_visual = _unit_visuals[_attacker_id]
		var dist: float = attacker_visual.position.distance_to(target_pos)
		if dist > 40:  # Only show projectile for ranged attacks
			var proj_color := Color(0.8, 0.8, 0.4) if attacker_visual.team == 0 else Color(1.0, 0.5, 0.2)
			units_layer.add_child(Effects.create_projectile(attacker_visual.position, target_pos, proj_color, 0.12))


func _on_unit_healed(_healer_id: int, _target_id: int, amount: int, target_x: float, target_y: float) -> void:
	var target_pos := Vector2(target_x, target_y)
	units_layer.add_child(Effects.create_heal_sparkle(target_pos))
	units_layer.add_child(Effects.create_damage_number(amount, target_pos, true))


func _on_castle_hit(_team: int, _damage: int, _remaining_hp: int) -> void:
	_shake_intensity = 4.0
	_shake_timer = 0.2


# --- Position Sync ---

func _sync_unit_positions() -> void:
	for entity in GameManager.simulation.entities:
		if entity.type != "unit":
			continue
		if _unit_visuals.has(entity.id):
			var visual = _unit_visuals[entity.id]
			visual.position = Vector2(FP.to_float(entity.x), FP.to_float(entity.y))
			# Update HP ratio on the chibi visual
			var max_hp: float = FP.to_float(entity.max_hp)
			if max_hp > 0:
				visual.hp_ratio = clampf(FP.to_float(entity.hp) / max_hp, 0.0, 1.0)


# --- Screen Shake ---

func _update_screen_shake(delta: float) -> void:
	if _shake_timer > 0:
		_shake_timer -= delta
		var offset := Vector2(randf_range(-_shake_intensity, _shake_intensity), randf_range(-_shake_intensity, _shake_intensity))
		position = _original_position + offset
	else:
		position = _original_position


# --- Castle HP Bars ---

func _update_castle_hp_bars() -> void:
	if not castle_hp_bar_0 or not castle_hp_bar_1:
		return
	var c0: Dictionary = GameManager.simulation.castles[0]
	var c1: Dictionary = GameManager.simulation.castles[1]
	var max_h: float = 640.0

	var ratio_0: float = clampf(FP.to_float(c0.hp) / FP.to_float(c0.max_hp), 0.0, 1.0)
	var ratio_1: float = clampf(FP.to_float(c1.hp) / FP.to_float(c1.max_hp), 0.0, 1.0)

	var h0: float = max_h * ratio_0
	var h1: float = max_h * ratio_1
	castle_hp_bar_0.offset_top = 40.0 + (max_h - h0)
	castle_hp_bar_0.offset_bottom = 680.0
	castle_hp_bar_1.offset_top = 40.0 + (max_h - h1)
	castle_hp_bar_1.offset_bottom = 680.0

	# Smooth color gradient from green to red
	castle_hp_bar_0.color = Color(0.15, 0.85, 0.25).lerp(Color(0.9, 0.15, 0.08), 1.0 - ratio_0)
	castle_hp_bar_1.color = Color(0.15, 0.85, 0.25).lerp(Color(0.9, 0.15, 0.08), 1.0 - ratio_1)

	# Sync castle visual damage state
	var cv0 = get_node_or_null("CastleArea0/CastleVisual0")
	var cv1 = get_node_or_null("CastleArea1/CastleVisual1")
	if cv0:
		cv0.hp_ratio = ratio_0
	if cv1:
		cv1.hp_ratio = ratio_1


# --- Wave Announcement ---

func _on_wave_announced(wave_number: int) -> void:
	if wave_label:
		wave_label.text = "WAVE %d" % wave_number
		wave_label.visible = true
		wave_label.modulate.a = 1.0
		wave_label.add_theme_font_size_override("font_size", 36)
		wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		wave_label.add_theme_constant_override("outline_size", 4)
		# Scale punch
		wave_label.scale = Vector2(1.4, 1.4)
		var tween := wave_label.create_tween()
		tween.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_wave_announce_timer = 2.5


func _update_wave_announcement(delta: float) -> void:
	if _wave_announce_timer <= 0:
		return
	_wave_announce_timer -= delta
	if _wave_announce_timer <= 0:
		if wave_label:
			wave_label.visible = false
	elif _wave_announce_timer < 1.0 and wave_label:
		wave_label.modulate.a = _wave_announce_timer


# --- Simple AI Opponent ---

func _update_ai(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0:
		return
	_ai_timer = AI_THINK_INTERVAL

	var sim: Simulation = GameManager.simulation
	var ai_index: int = sim.get_player_index(AI_PLAYER_ID)
	if ai_index == -1:
		return

	var faction: FactionData = GameManager.get_player_faction(AI_PLAYER_ID)
	if faction == null:
		return

	var gold: int = GameManager.get_player_gold(AI_PLAYER_ID)

	# Pick a random affordable building (prefer T1 early, T2 later)
	var affordable: Array[BuildingData] = []
	for bd: BuildingData in faction.buildings:
		if bd.gold_cost <= gold:
			# Check tech prereq
			if bd.requires_building == &"" or sim.player_has_building(ai_index, bd.requires_building):
				affordable.append(bd)

	if affordable.is_empty():
		return

	# Pick randomly
	var bd: BuildingData = affordable[randi() % affordable.size()]

	# Find a valid grid position (try random spots)
	for _attempt in 20:
		var gx: int = randi() % (GRID_COLS - bd.grid_size.x + 1)
		var gy: int = randi() % (GRID_ROWS - bd.grid_size.y + 1)
		if sim.can_place_building(AI_PLAYER_ID, bd.id, gx, gy):
			var cmd := Command.place_building(AI_PLAYER_ID, bd.id, gx, gy)
			GameManager.submit_command(cmd)
			return
