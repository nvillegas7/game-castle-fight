## Animated chibi castle with banner wave, window glow, damage states.
extends Node2D

@export var team: int = 0
var hp_ratio: float = 1.0

var _time: float = 0.0

const K_WALL := Color(0.5, 0.55, 0.7)
const K_ROOF := Color(0.2, 0.35, 0.65)
const K_ACC := Color(0.85, 0.75, 0.3)

const H_WALL := Color(0.55, 0.45, 0.35)
const H_ROOF := Color(0.65, 0.15, 0.1)
const H_ACC := Color(0.85, 0.55, 0.2)

const OL := Color(0.05, 0.04, 0.08, 0.6)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var wall: Color; var roof: Color; var acc: Color
	if team == 0:
		wall = K_WALL; roof = K_ROOF; acc = K_ACC
	else:
		wall = H_WALL; roof = H_ROOF; acc = H_ACC

	# Damage darkening
	if hp_ratio < 0.5:
		var dmg: float = (0.5 - hp_ratio) * 0.5
		wall = wall.darkened(dmg)
		roof = roof.darkened(dmg * 0.7)

	var w: float = 70.0
	var h: float = 140.0

	# Main keep
	draw_rect(Rect2(-w * 0.35, -h * 0.2, w * 0.7, h * 0.5), wall)
	draw_rect(Rect2(-w * 0.35, -h * 0.2, w * 0.7, h * 0.5), OL, false, 1.0)

	# Left tower
	draw_rect(Rect2(-w * 0.5, -h * 0.28, w * 0.22, h * 0.58), wall.lightened(0.08))
	draw_rect(Rect2(-w * 0.5, -h * 0.28, w * 0.22, h * 0.58), OL, false, 0.8)
	var lt := PackedVector2Array([
		Vector2(-w * 0.52, -h * 0.28),
		Vector2(-w * 0.39, -h * 0.4),
		Vector2(-w * 0.26, -h * 0.28),
	])
	draw_colored_polygon(lt, roof)
	draw_polyline(PackedVector2Array([lt[0], lt[1], lt[2]]), OL, 1.0)

	# Right tower
	draw_rect(Rect2(w * 0.28, -h * 0.28, w * 0.22, h * 0.58), wall.lightened(0.08))
	draw_rect(Rect2(w * 0.28, -h * 0.28, w * 0.22, h * 0.58), OL, false, 0.8)
	var rt := PackedVector2Array([
		Vector2(w * 0.26, -h * 0.28),
		Vector2(w * 0.39, -h * 0.4),
		Vector2(w * 0.52, -h * 0.28),
	])
	draw_colored_polygon(rt, roof)
	draw_polyline(PackedVector2Array([rt[0], rt[1], rt[2]]), OL, 1.0)

	# Battlements
	for i in 3:
		var bx: float = -9 + i * 9
		draw_rect(Rect2(bx, -h * 0.22, 6, 7), wall)

	# Gate
	draw_rect(Rect2(-7, h * 0.12, 14, 18), Color(0.18, 0.12, 0.08))
	# Gate arch (polygon semicircle)
	var gate_pts := PackedVector2Array()
	for i in 9:
		var a: float = PI + float(i) / 8.0 * PI
		gate_pts.append(Vector2(cos(a) * 7, h * 0.12 + sin(a) * 7))
	draw_colored_polygon(gate_pts, Color(0.22, 0.15, 0.1))

	# Windows with animated glow
	var glow: float = 0.4 + sin(_time * 2.0) * 0.15
	var win_col := Color(0.95, 0.85, 0.45, glow)
	for row_i in 3:
		var wy: float = -h * 0.12 + row_i * h * 0.1
		draw_rect(Rect2(-5, wy, 4, 5), win_col)
		draw_rect(Rect2(1, wy, 4, 5), win_col)

	# Tower windows
	for row_i in 2:
		var twy: float = -h * 0.1 + row_i * h * 0.12
		draw_rect(Rect2(-w * 0.45, twy, 3, 4), Color(0.9, 0.8, 0.45, glow * 0.8))
		draw_rect(Rect2(w * 0.35, twy, 3, 4), Color(0.9, 0.8, 0.45, glow * 0.8))

	# Animated banner
	var wind: float = sin(_time * 3.0) * 2.5
	var flag := PackedVector2Array([
		Vector2(0, -h * 0.38),
		Vector2(11 + wind, -h * 0.35),
		Vector2(wind * 0.4, -h * 0.32),
	])
	draw_colored_polygon(flag, acc)
	draw_rect(Rect2(-1, -h * 0.42, 2, h * 0.1), Color(0.35, 0.25, 0.15))

	# Fire at low HP
	if hp_ratio < 0.3:
		var fh: float = 8.0 + sin(_time * 7.0) * 3.0
		draw_circle(Vector2(-9, h * 0.05), fh * 0.35, Color(1.0, 0.6, 0.1, 0.55))
		draw_circle(Vector2(-9, h * 0.05), fh * 0.2, Color(1.0, 0.9, 0.3, 0.4))
		draw_circle(Vector2(10, -h * 0.05), fh * 0.3, Color(1.0, 0.5, 0.05, 0.45))
		# Smoke
		var sy: float = -h * 0.15 + sin(_time * 3.0) * 5.0
		draw_circle(Vector2(-8, sy), 4, Color(0.3, 0.3, 0.3, 0.25))
		draw_circle(Vector2(9, sy - 3), 3, Color(0.3, 0.3, 0.3, 0.2))
