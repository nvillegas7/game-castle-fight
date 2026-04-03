## Main game scene controller. Manages the arena, building and unit visuals,
## and wires UI to the grid overlay.
extends Node2D

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


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died)

	grid_overlay_0.player_index = 0
	grid_overlay_1.player_index = 1

	building_menu.building_selected.connect(_on_building_selected)

	GameManager.start_test_match()


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.simulation == null:
		return
	_sync_unit_positions()
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

	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


func _create_building_visual(bd: BuildingData, player_index: int, grid_pos: Vector2i) -> Node2D:
	var node := Node2D.new()
	var screen_pos := grid_to_screen(player_index, grid_pos.x, grid_pos.y)

	node.position = screen_pos + Vector2(
		bd.grid_size.x * CELL_SIZE * 0.5,
		bd.grid_size.y * CELL_SIZE * 0.5
	)

	var rect := ColorRect.new()
	rect.size = Vector2(bd.grid_size.x * CELL_SIZE - 4, bd.grid_size.y * CELL_SIZE - 4)
	rect.position = -rect.size * 0.5
	rect.color = Color(0.2, 0.4, 0.8) if player_index == 0 else Color(0.8, 0.3, 0.3)
	node.add_child(rect)

	var label := Label.new()
	label.text = bd.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.position = Vector2(-bd.grid_size.x * CELL_SIZE * 0.5, -8)
	label.size = Vector2(bd.grid_size.x * CELL_SIZE, 16)
	node.add_child(label)

	return node


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


func _create_unit_visual(entity: Dictionary) -> Node2D:
	var node := Node2D.new()
	node.position = Vector2(FP.to_float(entity.x), FP.to_float(entity.y))

	var size: float = 8.0
	var color: Color
	if entity.team == 0:
		color = Color(0.3, 0.6, 1.0)
	else:
		color = Color(1.0, 0.35, 0.3)

	# Unit body
	var rect := ColorRect.new()
	rect.size = Vector2(size * 2, size * 2)
	rect.position = Vector2(-size, -size)
	rect.color = color
	node.add_child(rect)

	# Role label
	var role_idx: int = entity.get("role", 0)
	if role_idx >= 0 and role_idx < ROLE_CHARS.size():
		var label := Label.new()
		label.text = ROLE_CHARS[role_idx]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		label.position = Vector2(-size, -size)
		label.size = Vector2(size * 2, size * 2)
		node.add_child(label)

	# HP bar background (dark)
	var hp_bg := ColorRect.new()
	hp_bg.name = "HPBg"
	hp_bg.size = Vector2(size * 2, 3)
	hp_bg.position = Vector2(-size, -size - 5)
	hp_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	node.add_child(hp_bg)

	# HP bar fill (green -> yellow -> red as HP drops)
	var hp_fill := ColorRect.new()
	hp_fill.name = "HPFill"
	hp_fill.size = Vector2(size * 2, 3)
	hp_fill.position = Vector2(-size, -size - 5)
	hp_fill.color = Color(0.2, 0.9, 0.2)
	node.add_child(hp_fill)

	return node


func _on_unit_died(unit_id: int, _killer_id: int) -> void:
	if _unit_visuals.has(unit_id):
		_unit_visuals[unit_id].queue_free()
		_unit_visuals.erase(unit_id)


# --- Position Sync ---

func _sync_unit_positions() -> void:
	for entity in GameManager.simulation.entities:
		if entity.type != "unit":
			continue
		if _unit_visuals.has(entity.id):
			var visual: Node2D = _unit_visuals[entity.id]
			visual.position = Vector2(FP.to_float(entity.x), FP.to_float(entity.y))

			# Update HP bar
			var hp_fill: ColorRect = visual.get_node_or_null("HPFill")
			if hp_fill:
				var hp_ratio: float = FP.to_float(entity.hp) / FP.to_float(entity.max_hp)
				hp_ratio = clampf(hp_ratio, 0.0, 1.0)
				hp_fill.size.x = 16.0 * hp_ratio  # 16 = size * 2

				# Color: green > yellow > red
				if hp_ratio > 0.6:
					hp_fill.color = Color(0.2, 0.9, 0.2)
				elif hp_ratio > 0.3:
					hp_fill.color = Color(0.9, 0.8, 0.1)
				else:
					hp_fill.color = Color(0.9, 0.2, 0.1)


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
