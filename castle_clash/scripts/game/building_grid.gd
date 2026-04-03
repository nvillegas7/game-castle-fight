## Grid overlay that draws grid lines, ghost preview, and handles placement input.
## Attached to a Node2D inside each team's build zone.
extends Node2D

const CELL_SIZE: int = 32
const GRID_COLS: int = 11
const GRID_ROWS: int = 20

## Which player this grid belongs to (set by parent).
var player_index: int = 0

# Placement state
var selected_building: BuildingData = null
var ghost_grid_pos: Vector2i = Vector2i(-1, -1)
var ghost_valid: bool = false
var _is_hovering: bool = false


func _draw() -> void:
	_draw_grid_lines()
	_draw_occupied_cells()
	if selected_building and _is_hovering:
		_draw_ghost()


func _draw_grid_lines() -> void:
	var grid_color := Color(1.0, 1.0, 1.0, 0.1)
	var width: int = GRID_COLS * CELL_SIZE
	var height: int = GRID_ROWS * CELL_SIZE

	for row in GRID_ROWS + 1:
		var y: float = row * CELL_SIZE
		draw_line(Vector2(0, y), Vector2(width, y), grid_color, 1.0)

	for col in GRID_COLS + 1:
		var x: float = col * CELL_SIZE
		draw_line(Vector2(x, 0), Vector2(x, height), grid_color, 1.0)

	# Border
	draw_rect(Rect2(0, 0, width, height), Color(1.0, 1.0, 1.0, 0.25), false, 2.0)


func _draw_occupied_cells() -> void:
	if GameManager.simulation == null:
		return
	if player_index >= GameManager.simulation.grid_cells.size():
		return
	var grid: Array = GameManager.simulation.grid_cells[player_index]
	var occupied_color := Color(0.5, 0.5, 0.5, 0.15)
	for row in GRID_ROWS:
		for col in GRID_COLS:
			if grid[row][col] != -1:
				draw_rect(
					Rect2(col * CELL_SIZE + 1, row * CELL_SIZE + 1, CELL_SIZE - 2, CELL_SIZE - 2),
					occupied_color
				)


func _draw_ghost() -> void:
	if ghost_grid_pos.x < 0:
		return
	var color := Color(0.0, 0.8, 0.0, 0.4) if ghost_valid else Color(0.8, 0.0, 0.0, 0.4)
	var rect := Rect2(
		ghost_grid_pos.x * CELL_SIZE,
		ghost_grid_pos.y * CELL_SIZE,
		selected_building.grid_size.x * CELL_SIZE,
		selected_building.grid_size.y * CELL_SIZE
	)
	draw_rect(rect, color)
	var border_color := Color(0.0, 1.0, 0.0, 0.8) if ghost_valid else Color(1.0, 0.0, 0.0, 0.8)
	draw_rect(rect, border_color, false, 2.0)


func _input(event: InputEvent) -> void:
	# Only the local player's grid processes input
	if player_index != GameManager.simulation.get_player_index(GameManager.local_player_id):
		return
	if selected_building == null:
		return

	if event is InputEventMouseMotion:
		_update_ghost_position(event.position)
		queue_redraw()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_ghost_position(event.position)
		if ghost_valid:
			_place_building()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		deselect_building()


func _update_ghost_position(screen_pos: Vector2) -> void:
	var local_pos: Vector2 = screen_pos - global_position
	var gx: int = int(local_pos.x) / CELL_SIZE
	var gy: int = int(local_pos.y) / CELL_SIZE

	# Check if mouse is within this grid area
	if local_pos.x < 0 or local_pos.x > GRID_COLS * CELL_SIZE \
	   or local_pos.y < 0 or local_pos.y > GRID_ROWS * CELL_SIZE:
		_is_hovering = false
		ghost_valid = false
		return

	_is_hovering = true

	# Clamp so building footprint stays in bounds
	gx = clampi(gx, 0, GRID_COLS - selected_building.grid_size.x)
	gy = clampi(gy, 0, GRID_ROWS - selected_building.grid_size.y)
	ghost_grid_pos = Vector2i(gx, gy)

	ghost_valid = GameManager.simulation.can_place_building(
		GameManager.local_player_id,
		selected_building.id,
		gx, gy
	)


func _place_building() -> void:
	var cmd := Command.place_building(
		GameManager.local_player_id,
		selected_building.id,
		ghost_grid_pos.x,
		ghost_grid_pos.y
	)
	NetworkManager.send_command(cmd)
	queue_redraw()


func select_building(building_data: BuildingData) -> void:
	selected_building = building_data
	ghost_grid_pos = Vector2i(-1, -1)
	ghost_valid = false
	queue_redraw()


func deselect_building() -> void:
	selected_building = null
	ghost_grid_pos = Vector2i(-1, -1)
	ghost_valid = false
	_is_hovering = false
	queue_redraw()
