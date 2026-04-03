## Draws a chibi castle for each team. Fits within 80x640px area.
extends Node2D

@export var team: int = 0

const KINGDOM_WALL := Color(0.5, 0.55, 0.7)
const KINGDOM_ROOF := Color(0.2, 0.35, 0.65)
const KINGDOM_ACCENT := Color(0.85, 0.75, 0.3)

const HORDE_WALL := Color(0.55, 0.45, 0.35)
const HORDE_ROOF := Color(0.65, 0.15, 0.1)
const HORDE_ACCENT := Color(0.85, 0.55, 0.2)


func _draw() -> void:
	var wall: Color
	var roof: Color
	var accent: Color

	if team == 0:
		wall = KINGDOM_WALL
		roof = KINGDOM_ROOF
		accent = KINGDOM_ACCENT
	else:
		wall = HORDE_WALL
		roof = HORDE_ROOF
		accent = HORDE_ACCENT

	# Castle fits within ~70x120px centered at origin
	var w: float = 60.0
	var h: float = 100.0

	# Main keep wall
	draw_rect(Rect2(-w * 0.4, -h * 0.2, w * 0.8, h * 0.55), wall)

	# Left tower
	draw_rect(Rect2(-w * 0.5, -h * 0.3, w * 0.25, h * 0.65), wall.lightened(0.1))
	# Left tower roof
	var lt := PackedVector2Array([
		Vector2(-w * 0.52, -h * 0.3),
		Vector2(-w * 0.375, -h * 0.42),
		Vector2(-w * 0.23, -h * 0.3),
	])
	draw_colored_polygon(lt, roof)

	# Right tower
	draw_rect(Rect2(w * 0.25, -h * 0.3, w * 0.25, h * 0.65), wall.lightened(0.1))
	# Right tower roof
	var rt := PackedVector2Array([
		Vector2(w * 0.23, -h * 0.3),
		Vector2(w * 0.375, -h * 0.42),
		Vector2(w * 0.52, -h * 0.3),
	])
	draw_colored_polygon(rt, roof)

	# Center battlement
	for i in 3:
		var bx: float = -8 + i * 8
		draw_rect(Rect2(bx, -h * 0.22, 5, 6), wall)

	# Gate arch
	draw_rect(Rect2(-6, h * 0.15, 12, 16), Color(0.2, 0.15, 0.1))
	draw_arc(Vector2(0, h * 0.15), 6, PI, 0, 8, Color(0.25, 0.18, 0.12), 6)

	# Windows on main keep
	draw_rect(Rect2(-5, -h * 0.1, 4, 5), Color(0.9, 0.85, 0.5, 0.5))
	draw_rect(Rect2(1, -h * 0.1, 4, 5), Color(0.9, 0.85, 0.5, 0.5))
	draw_rect(Rect2(-5, h * 0.02, 4, 5), Color(0.9, 0.85, 0.5, 0.5))
	draw_rect(Rect2(1, h * 0.02, 4, 5), Color(0.9, 0.85, 0.5, 0.5))

	# Tower windows
	draw_rect(Rect2(-w * 0.45, -h * 0.12, 3, 4), Color(0.9, 0.85, 0.5, 0.4))
	draw_rect(Rect2(-w * 0.45, h * 0.05, 3, 4), Color(0.9, 0.85, 0.5, 0.4))
	draw_rect(Rect2(w * 0.35, -h * 0.12, 3, 4), Color(0.9, 0.85, 0.5, 0.4))
	draw_rect(Rect2(w * 0.35, h * 0.05, 3, 4), Color(0.9, 0.85, 0.5, 0.4))

	# Banner on top
	var flag_pts := PackedVector2Array([
		Vector2(0, -h * 0.4),
		Vector2(10, -h * 0.37),
		Vector2(0, -h * 0.34),
	])
	draw_colored_polygon(flag_pts, accent)
	draw_rect(Rect2(-1, -h * 0.43, 2, h * 0.1), Color(0.4, 0.3, 0.2))
