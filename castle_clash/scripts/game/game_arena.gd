## Main game scene controller. Manages the arena, building and unit visuals,
## and wires UI to the grid overlay.
extends Node2D

const UnitVisualScript = preload("res://scripts/game/unit_visual.gd")
const BuildingVisualScript = preload("res://scripts/game/building_visual.gd")

# Portrait layout (720x1280)
const CELL_SIZE: int = 28
const GRID_COLS: int = 11
const GRID_ROWS: int = 10

# Vertical zones
const HUD_H: int = 50
const ENEMY_ZONE_Y: int = 55
const ENEMY_ZONE_H: int = 290      # y=55-345
const COMBAT_Y: int = 350
const COMBAT_H: int = 340           # y=350-690
const PLAYER_ZONE_Y: int = 695
const PLAYER_ZONE_H: int = 290      # y=695-985
const GOLD_BAR_Y: int = 990
const CARD_HAND_Y: int = 1040

# Horizontal grid centering
const GRID_W: int = 11 * 28         # 308px
const GRID_MARGIN_X: int = 206      # (720 - 308) / 2

@onready var grid_overlay_0: Node2D = $BuildZone0/GridOverlay
@onready var grid_overlay_1: Node2D = $BuildZone1/GridOverlay
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var units_layer: Node2D = $UnitsLayer
@onready var card_hand: Control = $UILayer/CardHand
@onready var gold_bar_label: Label = $UILayer/GoldBarBg/GoldBarLabel
@onready var gold_bar_fill: ColorRect = $UILayer/GoldBarBg/GoldBarFill

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

	card_hand.building_selected.connect(_on_building_selected)
	_original_position = position

	if wave_label:
		wave_label.visible = false

	GameManager.start_test_match()
	SFX.start_music()


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.simulation == null:
		return
	_sync_unit_positions()
	_update_castle_hp_bars()
	_update_gold_bar()
	_update_wave_announcement(delta)
	_update_screen_shake(delta)
	_update_ai(delta)


func _on_building_selected(bd: BuildingData) -> void:
	var local_index: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	var grid: Node2D = grid_overlay_0 if local_index == 0 else grid_overlay_1
	grid.select_building(bd)


func grid_to_screen(player_index: int, grid_x: int, grid_y: int) -> Vector2:
	var zone_y: int = PLAYER_ZONE_Y if player_index == 0 else ENEMY_ZONE_Y
	return Vector2(
		GRID_MARGIN_X + grid_x * CELL_SIZE,
		zone_y + grid_y * CELL_SIZE
	)


# --- Building Visuals ---

func _on_building_placed(player_id: int, building_data: BuildingData, grid_pos: Vector2i) -> void:
	SFX.play_place()
	# Cycle card hand when player places a building
	if player_id == GameManager.local_player_id:
		card_hand.card_played(building_data.id)
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
	var place_tw: Tween = visual.create_tween()
	place_tw.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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
	SFX.play_gold()
	if _building_visuals.has(building_id):
		var visual = _building_visuals[building_id]
		var pos: Vector2 = visual.position
		# Sell/destroy feedback: poof + gold refund text
		units_layer.add_child(Effects.create_death_poof(pos, Color(0.6, 0.5, 0.3)))
		# Show refund amount if it was a sell (gold went up)
		var refund_node := Effects.create_damage_number(0, pos, true)
		var lbl: Label = refund_node.get_child(0)
		if lbl:
			lbl.text = "SOLD"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		units_layer.add_child(refund_node)
		visual.queue_free()
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
	var spawn_tw: Tween = visual.create_tween()
	spawn_tw.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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
	SFX.play_death()
	if _unit_visuals.has(unit_id):
		var visual = _unit_visuals[unit_id]
		var death_pos: Vector2 = visual.position
		var team_color := Color(0.3, 0.6, 1.0) if visual.team == 0 else Color(1.0, 0.35, 0.3)
		# Death poof
		units_layer.add_child(Effects.create_death_poof(death_pos, team_color))
		# Shrink-out tween instead of instant vanish
		_unit_visuals.erase(unit_id)
		var death_tween: Tween = visual.create_tween()
		death_tween.set_parallel(true)
		death_tween.tween_property(visual, "scale", Vector2(0.0, 0.0), 0.15).set_ease(Tween.EASE_IN)
		death_tween.tween_property(visual, "modulate:a", 0.0, 0.15)
		death_tween.set_parallel(false)
		death_tween.tween_callback(visual.queue_free)


func _on_unit_attacked(attacker_id: int, target_id: int, damage: int, target_x: float, target_y: float) -> void:
	var target_pos := Vector2(target_x, target_y)
	# Sound
	if _unit_visuals.has(attacker_id):
		var av = _unit_visuals[attacker_id]
		if av.position.distance_to(target_pos) > 40:
			SFX.play_shoot()
		else:
			SFX.play_hit()
	# Damage number
	units_layer.add_child(Effects.create_damage_number(damage, target_pos))
	# Hit flash on target
	if _unit_visuals.has(target_id):
		_unit_visuals[target_id].flash_hit()
	# Attack animation on attacker
	if _unit_visuals.has(attacker_id):
		var attacker_visual = _unit_visuals[attacker_id]
		attacker_visual.play_attack()
		# Projectile for ranged attacks
		var dist: float = attacker_visual.position.distance_to(target_pos)
		if dist > 40:
			var proj_color := Color(0.8, 0.8, 0.4) if attacker_visual.team == 0 else Color(1.0, 0.5, 0.2)
			units_layer.add_child(Effects.create_projectile(attacker_visual.position, target_pos, proj_color, 0.12))


func _on_unit_healed(healer_id: int, _target_id: int, amount: int, target_x: float, target_y: float) -> void:
	SFX.play_heal()
	var target_pos := Vector2(target_x, target_y)
	units_layer.add_child(Effects.create_heal_sparkle(target_pos))
	units_layer.add_child(Effects.create_damage_number(amount, target_pos, true))
	# Cast animation on healer
	if _unit_visuals.has(healer_id):
		_unit_visuals[healer_id].play_cast()


func _on_castle_hit(_team: int, _damage: int, _remaining_hp: int) -> void:
	SFX.play_castle_hit()
	_shake_intensity = 4.0
	_shake_timer = 0.2


# --- Position Sync ---

func _sync_unit_positions() -> void:
	for entity in GameManager.simulation.entities:
		if entity.type != "unit":
			continue
		if _unit_visuals.has(entity.id):
			var visual = _unit_visuals[entity.id]
			var new_pos := Vector2(FP.to_float(entity.x), FP.to_float(entity.y))

			var is_moving: bool = new_pos.distance_squared_to(visual.position) > 0.5
			visual.set_moving(is_moving)

			# Facing: face toward target X position
			if entity.target_id != -1:
				var target = GameManager.simulation._find_entity_by_id(entity.target_id)
				if target:
					visual.facing = 1.0 if FP.to_float(target.x) > new_pos.x else -1.0

			visual.position = new_pos

			var max_hp: float = FP.to_float(entity.max_hp)
			if max_hp > 0:
				visual.hp_ratio = clampf(FP.to_float(entity.hp) / max_hp, 0.0, 1.0)


# --- Gold Bar ---

func _update_gold_bar() -> void:
	if not gold_bar_label or not gold_bar_fill:
		return
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var income: int = 10  # Default
	if GameManager.simulation:
		var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
		if pi >= 0 and pi < GameManager.simulation.players.size():
			income = FP.to_int(GameManager.simulation.players[pi].income)
	gold_bar_label.text = "Gold: %d (+%d/5s)" % [gold, income]
	# Fill bar proportionally (max display = 300 gold)
	var ratio: float = clampf(float(gold) / 300.0, 0.0, 1.0)
	var max_w: float = 488.0  # 708 - 220
	gold_bar_fill.offset_right = 220.0 + max_w * ratio


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
	var max_w: float = 398.0  # 559 - 161

	var ratio_0: float = clampf(FP.to_float(c0.hp) / FP.to_float(c0.max_hp), 0.0, 1.0)
	var ratio_1: float = clampf(FP.to_float(c1.hp) / FP.to_float(c1.max_hp), 0.0, 1.0)

	# Horizontal bars: resize width from left
	castle_hp_bar_0.offset_right = 161.0 + max_w * ratio_0
	castle_hp_bar_1.offset_right = 161.0 + max_w * ratio_1

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
		var wave_tw: Tween = wave_label.create_tween()
		wave_tw.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
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
	var match_time: int = GameManager.current_tick

	# Count AI's current buildings by type
	var ai_building_count: int = 0
	var has_income: bool = false
	var has_t1_combat: bool = false
	for entity in sim.entities:
		if entity.type == "building" and entity.player_index == ai_index:
			ai_building_count += 1
			var bd_check = sim.building_registry.get(entity.building_type)
			if bd_check and bd_check.income_bonus > 0:
				has_income = true
			if bd_check and bd_check.spawns_unit and bd_check.tier == 1:
				has_t1_combat = true

	# Build affordable list
	var affordable: Array[BuildingData] = []
	for bd: BuildingData in faction.buildings:
		if bd.gold_cost <= gold:
			if bd.requires_building == &"" or sim.player_has_building(ai_index, bd.requires_building):
				affordable.append(bd)

	if affordable.is_empty():
		return

	# Scout player's unit composition
	var player_melee: int = 0
	var player_ranged: int = 0
	var player_siege: int = 0
	for entity in sim.entities:
		if entity.type == "unit" and entity.team != AI_PLAYER_ID:
			match entity.role:
				0: player_melee += 1
				1: player_ranged += 1
				4: player_siege += 1

	var chosen: BuildingData = null

	# Phase 1 (early): income building
	if not has_income and ai_building_count < 3:
		for bd: BuildingData in affordable:
			if bd.income_bonus > 0:
				chosen = bd
				break

	# Phase 2: ensure base combat
	if chosen == null and ai_building_count < 4:
		for bd: BuildingData in affordable:
			if bd.spawns_unit and bd.tier == 1:
				chosen = bd
				break

	# Phase 3: reactive counter-building
	if chosen == null and match_time > 200:
		# Counter heavy melee -> build ranged/towers
		if player_melee > player_ranged + 2:
			for bd: BuildingData in affordable:
				if bd.spawns_unit and bd.spawns_unit.role == 1:  # Ranged counter
					chosen = bd
					break
			if chosen == null:
				for bd: BuildingData in affordable:
					if bd.is_tower:
						chosen = bd
						break
		# Counter heavy ranged -> build melee/T2
		elif player_ranged > player_melee + 2:
			for bd: BuildingData in affordable:
				if bd.tier == 2 and bd.spawns_unit and bd.spawns_unit.role == 0:
					chosen = bd
					break
		# Counter siege -> build anything fast
		elif player_siege > 1:
			for bd: BuildingData in affordable:
				if bd.spawns_unit and bd.tier == 1 and bd.spawns_unit.role == 0:
					chosen = bd
					break

	# Phase 4 (late): T2 and towers
	if chosen == null and match_time > 400:
		var roll: int = randi() % 100
		if roll < 45:
			for bd: BuildingData in affordable:
				if bd.tier == 2:
					chosen = bd
					break
		elif roll < 65:
			for bd: BuildingData in affordable:
				if bd.is_tower:
					chosen = bd
					break

	# Fallback: weighted random (prefer spawners over income)
	if chosen == null:
		var combat: Array[BuildingData] = []
		for bd: BuildingData in affordable:
			if bd.spawns_unit or bd.is_tower:
				combat.append(bd)
		if not combat.is_empty():
			chosen = combat[randi() % combat.size()]
		else:
			chosen = affordable[randi() % affordable.size()]

	# Smart grid placement: towers near front (high X), income in back (low X)
	var prefer_front: bool = chosen.is_tower or (chosen.spawns_unit != null)
	var prefer_back: bool = chosen.income_bonus > 0

	for _attempt in 25:
		var gx: int
		if prefer_front:
			# Front half of grid (closer to combat lane)
			gx = (GRID_COLS - chosen.grid_size.x) / 2 + randi() % ((GRID_COLS - chosen.grid_size.x + 2) / 2)
		elif prefer_back:
			# Back half of grid (farther from combat lane)
			gx = randi() % ((GRID_COLS - chosen.grid_size.x + 2) / 2)
		else:
			gx = randi() % (GRID_COLS - chosen.grid_size.x + 1)
		var gy: int = randi() % (GRID_ROWS - chosen.grid_size.y + 1)
		if sim.can_place_building(AI_PLAYER_ID, chosen.id, gx, gy):
			var cmd := Command.place_building(AI_PLAYER_ID, chosen.id, gx, gy)
			GameManager.submit_command(cmd)
			return
