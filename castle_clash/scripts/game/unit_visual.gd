## Chibi unit visual drawn with _draw(). A-grade polish:
## Team indicator rings, body outlines, facing direction, role-specific details,
## smooth hit flash, bordered HP bars hidden at full HP, grounding shadows.
## Roles: 0=Melee, 1=Ranged, 2=Caster, 3=Flying, 4=Siege
extends Node2D

var team: int = 0
var role: int = 0
var unit_type: StringName = &""
var hp_ratio: float = 1.0
var facing: float = 1.0  # 1.0 = right, -1.0 = left
var _time: float = 0.0
var _hit_flash: float = 0.0

# Kingdom palette
const K_SKIN := Color(0.95, 0.82, 0.7)
const K_PRI := Color(0.25, 0.45, 0.85)
const K_DARK := Color(0.12, 0.22, 0.5)
const K_ACC := Color(0.9, 0.78, 0.3)
# Horde palette
const H_SKIN := Color(0.55, 0.75, 0.45)
const H_PRI := Color(0.78, 0.22, 0.15)
const H_DARK := Color(0.45, 0.1, 0.08)
const H_ACC := Color(0.9, 0.58, 0.2)

const HEAD_R: float = 7.0
const BODY_W: float = 10.0
const BODY_H: float = 7.0
const OUTLINE := Color(0.08, 0.06, 0.12)


func _process(delta: float) -> void:
	_time += delta
	if _hit_flash > 0:
		_hit_flash -= delta
	queue_redraw()


func flash_hit() -> void:
	_hit_flash = 0.12


func _draw() -> void:
	var skin: Color; var pri: Color; var dark: Color; var acc: Color
	if team == 0:
		skin = K_SKIN; pri = K_PRI; dark = K_DARK; acc = K_ACC
	else:
		skin = H_SKIN; pri = H_PRI; dark = H_DARK; acc = H_ACC

	# Hit flash: lerp toward white
	if _hit_flash > 0:
		var ft: float = _hit_flash / 0.12
		skin = skin.lerp(Color.WHITE, ft * 0.65)
		pri = pri.lerp(Color.WHITE, ft * 0.65)
		dark = dark.lerp(Color.WHITE, ft * 0.45)

	# Idle bob (flying units bob more)
	var bob_amp: float = 3.0 if role == 3 else 1.5
	var bob_spd: float = 4.0 if role == 3 else 3.0
	var bob: float = sin(_time * bob_spd) * bob_amp
	var sway: float = sin(_time * 2.0 + 0.5) * 0.6
	var by: float = bob  # base_y

	# --- Team indicator ring ---
	var tc: Color = pri
	_draw_oval(Vector2(0, by + 15), 8.0, 2.5, Color(tc.r, tc.g, tc.b, 0.3))
	draw_arc(Vector2(0, by + 15), 7.0, 0, TAU, 16, Color(tc.r, tc.g, tc.b, 0.7), 1.5)

	# --- Shadow ---
	_draw_oval(Vector2(0, by + 15), 6.0, 2.0, Color(0, 0, 0, 0.22))

	# Siege machines draw differently
	if role == 4:
		_draw_siege(by, pri, dark, acc)
		_draw_hp_bar(by)
		return

	# Mirror drawing based on facing
	var fx: float = facing

	# --- Legs ---
	var ly: float = by + 8.0
	draw_rect(Rect2(-4, ly, 3, 5), dark)
	draw_rect(Rect2(1, ly, 3, 5), dark)
	draw_rect(Rect2(-4, ly, 3, 5), OUTLINE, false, 0.8)
	draw_rect(Rect2(1, ly, 3, 5), OUTLINE, false, 0.8)

	# --- Body ---
	var body_y: float = by + 1.0
	draw_rect(Rect2(-BODY_W * 0.5, body_y, BODY_W, BODY_H), pri)
	draw_rect(Rect2(-BODY_W * 0.5, body_y + BODY_H - 2, BODY_W, 2), dark)  # belt
	draw_rect(Rect2(-BODY_W * 0.5, body_y, BODY_W, BODY_H), OUTLINE, false, 1.0)

	# --- Arms + Weapon ---
	_draw_weapon(by, fx, pri, dark, acc)

	# --- Head ---
	var hy: float = by - 6.0
	draw_circle(Vector2(sway * 0.4, hy), HEAD_R, skin)
	draw_arc(Vector2(sway * 0.4, hy), HEAD_R, 0, TAU, 20, OUTLINE, 1.2)

	# Headgear
	_draw_headgear(hy, sway * 0.4, fx, pri, dark, acc)

	# Eyes (skip for siege)
	var ex: float = sway * 0.4
	_draw_eyes(ex, hy)

	# Mouth
	draw_line(Vector2(ex - 1.5, hy + 4.0), Vector2(ex + 1.5, hy + 4.0), Color(0.35, 0.2, 0.15), 0.8)

	# --- HP Bar ---
	_draw_hp_bar(by)


func _draw_eyes(ex: float, hy: float) -> void:
	var ey: float = hy + 1.0
	# Eye whites
	draw_circle(Vector2(ex - 2.5, ey), 2.0, Color.WHITE)
	draw_circle(Vector2(ex + 2.5, ey), 2.0, Color.WHITE)
	# Pupils
	draw_circle(Vector2(ex - 2.5, ey), 1.1, Color(0.12, 0.1, 0.18))
	draw_circle(Vector2(ex + 2.5, ey), 1.1, Color(0.12, 0.1, 0.18))
	# Shine
	draw_circle(Vector2(ex - 2.0, ey - 0.6), 0.5, Color(1, 1, 1, 0.9))
	draw_circle(Vector2(ex + 3.0, ey - 0.6), 0.5, Color(1, 1, 1, 0.9))


func _draw_headgear(hy: float, hx: float, fx: float, pri: Color, dark: Color, acc: Color) -> void:
	match role:
		0:  # Melee -- helmet
			draw_arc(Vector2(hx, hy), HEAD_R + 1, PI * 0.75, PI * 0.25 + TAU, 12, dark, 2.8)
			draw_circle(Vector2(hx, hy - HEAD_R + 1), 3.5, dark)
			draw_circle(Vector2(hx, hy - HEAD_R + 1), 2.0, acc)  # helmet gem
		1:  # Ranged -- hood
			draw_arc(Vector2(hx, hy), HEAD_R + 1, PI * 0.65, PI * 0.35 + TAU, 12, pri, 2.2)
		2:  # Caster -- pointed hat
			var pts := PackedVector2Array([
				Vector2(hx - 6, hy - 4), Vector2(hx, hy - 17), Vector2(hx + 6, hy - 4),
			])
			draw_colored_polygon(pts, pri)
			draw_polyline(pts, OUTLINE, 1.0)
			draw_circle(Vector2(hx, hy - 17), 1.8, acc)
		3:  # Flying -- spiky hair
			for i in 3:
				var xo: float = hx + (i - 1) * 3.5
				var sp := PackedVector2Array([
					Vector2(xo - 2, hy - 5), Vector2(xo, hy - 11), Vector2(xo + 2, hy - 5),
				])
				draw_colored_polygon(sp, dark)


func _draw_weapon(by: float, fx: float, pri: Color, dark: Color, acc: Color) -> void:
	var ay: float = by + 3.0
	var weapon_side: float = fx * (BODY_W * 0.5)

	match role:
		0:  # Sword
			draw_rect(Rect2(-BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(BODY_W * 0.5, ay, 3, 5), pri)
			# Sword on facing side
			var sx: float = weapon_side + fx * 1
			draw_rect(Rect2(sx, ay - 9, 2 * fx, 11), Color(0.82, 0.82, 0.88))
			draw_rect(Rect2(sx, ay - 9, 2 * fx, 11), OUTLINE, false, 0.7)
			draw_rect(Rect2(sx - fx * 2, ay + 1, 5 * fx, 2), acc)
		1:  # Bow
			draw_rect(Rect2(-BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(BODY_W * 0.5, ay, 3, 5), pri)
			var bx: float = weapon_side + fx * 5
			draw_arc(Vector2(bx, ay + 2), 6, -PI * 0.4 * fx, PI * 0.4 * fx, 8, Color(0.55, 0.35, 0.2), 1.8)
		2:  # Staff
			draw_rect(Rect2(-BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(BODY_W * 0.5, ay, 3, 5), pri)
			var stx: float = -weapon_side - fx * 1
			draw_rect(Rect2(stx, ay - 11, 2, 17), Color(0.55, 0.35, 0.2))
			draw_rect(Rect2(stx, ay - 11, 2, 17), OUTLINE, false, 0.6)
			# Orb glow (pulsing)
			var glow: float = 0.35 + sin(_time * 4.0) * 0.15
			draw_circle(Vector2(stx + 1, ay - 12), 3.5, Color(acc.r, acc.g, acc.b, glow))
			draw_circle(Vector2(stx + 1, ay - 12), 2.2, acc)
		3:  # Wings
			draw_rect(Rect2(-BODY_W * 0.5 - 2, ay, 3, 4), pri)
			draw_rect(Rect2(BODY_W * 0.5, ay, 3, 4), pri)
			var flap: float = sin(_time * 8.0) * 4.0
			var lw := PackedVector2Array([
				Vector2(-BODY_W * 0.5 - 2, ay),
				Vector2(-BODY_W * 0.5 - 14, ay - 7 + flap),
				Vector2(-BODY_W * 0.5 - 8, ay + 4),
			])
			draw_colored_polygon(lw, Color(1, 1, 1, 0.55))
			draw_polyline(lw, Color(0.7, 0.7, 0.8, 0.4), 1.0)
			var rw := PackedVector2Array([
				Vector2(BODY_W * 0.5 + 2, ay),
				Vector2(BODY_W * 0.5 + 14, ay - 7 + flap),
				Vector2(BODY_W * 0.5 + 8, ay + 4),
			])
			draw_colored_polygon(rw, Color(1, 1, 1, 0.55))
			draw_polyline(rw, Color(0.7, 0.7, 0.8, 0.4), 1.0)


func _draw_siege(by: float, pri: Color, dark: Color, acc: Color) -> void:
	# Catapult/demolisher machine (no human face)
	# Platform
	draw_rect(Rect2(-10, by + 2, 20, 8), Color(0.5, 0.35, 0.22))
	draw_rect(Rect2(-10, by + 2, 20, 8), OUTLINE, false, 1.0)
	# Wheels
	for wx in [-6, 6]:
		draw_circle(Vector2(wx, by + 11), 4.0, Color(0.4, 0.3, 0.2))
		draw_arc(Vector2(wx, by + 11), 4.0, 0, TAU, 12, OUTLINE, 1.0)
		draw_circle(Vector2(wx, by + 11), 1.5, Color(0.3, 0.2, 0.12))
	# Catapult arm
	var arm_ang: float = sin(_time * 2.5) * 0.12 - 0.3
	var arm_end := Vector2(sin(arm_ang) * 13, -cos(arm_ang) * 13) + Vector2(0, by + 2)
	draw_line(Vector2(0, by + 2), arm_end, Color(0.55, 0.35, 0.2), 2.8)
	draw_line(Vector2(0, by + 2), arm_end, OUTLINE, 0.8)
	# Boulder
	draw_circle(arm_end, 3.0, Color(0.55, 0.55, 0.5))
	draw_arc(arm_end, 3.0, 0, TAU, 8, OUTLINE, 0.8)
	# Team flag on arm
	draw_rect(Rect2(arm_end.x - 1, arm_end.y - 6, 6, 4), pri)


func _draw_hp_bar(by: float) -> void:
	if hp_ratio >= 0.999:
		return  # Hide at full HP -- reduces clutter
	var bar_y: float = by - 17.0
	var bar_w: float = 16.0
	var bar_h: float = 3.0

	# Black border
	draw_rect(Rect2(-bar_w * 0.5 - 0.5, bar_y - 0.5, bar_w + 1, bar_h + 1), Color(0, 0, 0, 0.85))
	# Background
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.08, 0.08, 0.9))
	# Fill
	var fw: float = bar_w * hp_ratio
	var fc: Color
	if hp_ratio > 0.6:
		fc = Color(0.15, 0.85, 0.15)
	elif hp_ratio > 0.3:
		fc = Color(0.92, 0.8, 0.08)
	else:
		fc = Color(0.92, 0.12, 0.08)
	if fw > 0:
		draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h), fc)
		# Gloss highlight
		draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h * 0.4), Color(1, 1, 1, 0.2))


func _draw_oval(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = i * TAU / 16.0
		pts.append(Vector2(center.x + cos(a) * rx, center.y + sin(a) * ry))
	draw_colored_polygon(pts, color)
