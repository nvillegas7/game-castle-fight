## Draws a chibi castle for each team.
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

	var w: float = 60.0
	var h: float = 500.0
	var cx: float = 0.0

	# Main keep wall
	draw_rect(Rect2(cx - w * 0.4, -h * 0.3, w * 0.8, h * 0.6), wall)

	# Left tower
	draw_rect(Rect2(cx - w * 0.5, -h * 0.35, w * 0.25, h * 0.7), wall.lightened(0.1))
	var lt := PackedVector2Array([
		Vector2(cx - w * 0.52, -h * 0.35),
		Vector2(cx - w * 0.375, -h * 0.45),
		Vector2(cx - w * 0.23, -h * 0.35),
	])
	draw_colored_polygon(lt, roof)

	# Right tower
	draw_rect(Rect2(cx + w * 0.25, -h * 0.35, w * 0.25, h * 0.7), wall.lightened(0.1))
	var rt := PackedVector2Array([
		Vector2(cx + w * 0.23, -h * 0.35),
		Vector2(cx + w * 0.375, -h * 0.45),
		Vector2(cx + w * 0.52, -h * 0.35),
	])
	draw_colored_polygon(rt, roof)

	# Center battlement
	for i in 3:
		var bx: float = cx - 10 + i * 10
		draw_rect(Rect2(bx, -h * 0.32, 7, 10), wall)

	# Gate arch
	draw_rect(Rect2(cx - 8, h * 0.15, 16, 20), Color(0.2, 0.15, 0.1))
	draw_arc(Vector2(cx, h * 0.15), 8, PI, 0, 8, Color(0.25, 0.18, 0.12), 8)

	# Windows
	for row_i in 4:
		var wy: float = -h * 0.25 + row_i * h * 0.12
		draw_rect(Rect2(cx - 6, wy, 4, 5), Color(0.9, 0.85, 0.5, 0.5))
		draw_rect(Rect2(cx + 2, wy, 4, 5), Color(0.9, 0.85, 0.5, 0.5))

	# Tower windows
	for row_i in 3:
		var twy: float = -h * 0.2 + row_i * h * 0.15
		draw_rect(Rect2(cx - w * 0.45, twy, 3, 4), Color(0.9, 0.85, 0.5, 0.4))
		draw_rect(Rect2(cx + w * 0.35, twy, 3, 4), Color(0.9, 0.85, 0.5, 0.4))

	# Banner on top
	var flag_pts := PackedVector2Array([
		Vector2(cx, -h * 0.42),
		Vector2(cx + 12, -h * 0.39),
		Vector2(cx, -h * 0.36),
	])
	draw_colored_polygon(flag_pts, accent)
	draw_rect(Rect2(cx - 1, -h * 0.45, 2, h * 0.12), Color(0.4, 0.3, 0.2))
