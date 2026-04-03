## Main game scene controller. Manages the arena, building visuals,
## and wires UI to the grid overlay.
extends Node2D

const CELL_SIZE: int = 32
const GRID_COLS: int = 11
const GRID_ROWS: int = 20
const GRID_ORIGIN_Y: int = 40   # Top margin for HUD
const ZONE_0_ORIGIN_X: int = 80
const ZONE_1_ORIGIN_X: int = 848

@onready var grid_overlay_0: Node2D = $BuildZone0/GridOverlay
@onready var grid_overlay_1: Node2D = $BuildZone1/GridOverlay
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var building_menu: PanelContainer = $UILayer/BuildingMenu

var _building_visuals: Dictionary = {}  # entity_id -> Node2D


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_destroyed.connect(_on_building_destroyed)

	# Set grid player indices
	grid_overlay_0.player_index = 0
	grid_overlay_1.player_index = 1

	# Wire building menu to local player's grid
	building_menu.building_selected.connect(_on_building_selected)

	# Start test match
	GameManager.start_test_match()


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


func _on_building_placed(player_id: int, building_data: BuildingData, grid_pos: Vector2i) -> void:
	var player_index: int = GameManager.simulation.get_player_index(player_id)

	# Find entity_id (last placed building at this position for this player)
	var entity_id: int = -1
	for entity in GameManager.simulation.entities:
		if entity.type == "building" and entity.owner == player_id \
		   and entity.grid_x == grid_pos.x and entity.grid_y == grid_pos.y:
			entity_id = entity.id

	var visual := _create_building_visual(building_data, player_index, grid_pos)
	buildings_layer.add_child(visual)
	if entity_id >= 0:
		_building_visuals[entity_id] = visual

	# Redraw grids to show newly occupied cells
	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


func _create_building_visual(bd: BuildingData, player_index: int, grid_pos: Vector2i) -> Node2D:
	var node := Node2D.new()
	var screen_pos := grid_to_screen(player_index, grid_pos.x, grid_pos.y)

	# Position at center of building footprint
	node.position = screen_pos + Vector2(
		bd.grid_size.x * CELL_SIZE * 0.5,
		bd.grid_size.y * CELL_SIZE * 0.5
	)

	# Placeholder colored rectangle
	var rect := ColorRect.new()
	rect.size = Vector2(bd.grid_size.x * CELL_SIZE - 4, bd.grid_size.y * CELL_SIZE - 4)
	rect.position = -rect.size * 0.5
	rect.color = Color(0.2, 0.4, 0.8) if player_index == 0 else Color(0.8, 0.3, 0.3)
	node.add_child(rect)

	# Building name label
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
