## Chibi unit visual drawn with _draw(). Big head, small body, weapon per role.
## Roles: 0=Melee, 1=Ranged, 2=Caster, 3=Flying, 4=Siege
extends Node2D

var team: int = 0
var role: int = 0
var unit_type: StringName = &""
var hp_ratio: float = 1.0
var _time: float = 0.0
var _hit_flash: float = 0.0

# Color palettes per team
const KINGDOM_SKIN := Color(0.95, 0.82, 0.7)
const KINGDOM_PRIMARY := Color(0.25, 0.45, 0.85)
const KINGDOM_DARK := Color(0.15, 0.3, 0.65)
const KINGDOM_ACCENT := Color(0.85, 0.75, 0.3)

const HORDE_SKIN := Color(0.55, 0.75, 0.45)
const HORDE_PRIMARY := Color(0.75, 0.2, 0.15)
const HORDE_DARK := Color(0.55, 0.12, 0.1)
const HORDE_ACCENT := Color(0.85, 0.55, 0.2)

# Sizes
const HEAD_RADIUS: float = 7.0
const BODY_W: float = 10.0
const BODY_H: float = 7.0
const TOTAL_H: float = 28.0


func _process(delta: float) -> void:
	_time += delta
	if _hit_flash > 0:
		_hit_flash -= delta
	queue_redraw()


func flash_hit() -> void:
	_hit_flash = 0.12


func _draw() -> void:
	var skin: Color
	var primary: Color
	var dark: Color
	var accent: Color

	if team == 0:
		skin = KINGDOM_SKIN
		primary = KINGDOM_PRIMARY
		dark = KINGDOM_DARK
		accent = KINGDOM_ACCENT
	else:
		skin = HORDE_SKIN
		primary = HORDE_PRIMARY
		dark = HORDE_DARK
		accent = HORDE_ACCENT

	# Hit flash override
	if _hit_flash > 0:
		skin = Color.WHITE
		primary = Color(0.95, 0.95, 1.0)

	# Idle bob
	var bob: float = sin(_time * 3.0) * 1.5
	var base_y: float = bob

	# --- Legs ---
	var leg_y: float = base_y + 8.0
	draw_rect(Rect2(-4, leg_y, 3, 5), dark)
	draw_rect(Rect2(1, leg_y, 3, 5), dark)

	# --- Body ---
	var body_y: float = base_y + 1.0
	draw_rect(Rect2(-BODY_W * 0.5, body_y, BODY_W, BODY_H), primary)
	# Belt/detail
	draw_rect(Rect2(-BODY_W * 0.5, body_y + BODY_H - 2, BODY_W, 2), dark)

	# --- Arms + Weapon (behind or in front depending on role) ---
	_draw_arms_and_weapon(base_y, primary, dark, accent)

	# --- Head ---
	var head_y: float = base_y - 6.0
	# Head circle
	draw_circle(Vector2(0, head_y), HEAD_RADIUS, skin)
	# Head outline
	draw_arc(Vector2(0, head_y), HEAD_RADIUS, 0, TAU, 24, dark, 1.2)

	# Hair/helmet
	_draw_headgear(head_y, primary, dark, accent)

	# Eyes (big chibi eyes)
	var eye_y: float = head_y + 1.0
	draw_circle(Vector2(-2.5, eye_y), 1.8, Color.WHITE)
	draw_circle(Vector2(2.5, eye_y), 1.8, Color.WHITE)
	draw_circle(Vector2(-2.5, eye_y), 1.0, Color(0.15, 0.15, 0.2))
	draw_circle(Vector2(2.5, eye_y), 1.0, Color(0.15, 0.15, 0.2))
	# Eye shine
	draw_circle(Vector2(-2.0, eye_y - 0.5), 0.4, Color.WHITE)
	draw_circle(Vector2(3.0, eye_y - 0.5), 0.4, Color.WHITE)

	# Mouth
	draw_line(Vector2(-1.5, head_y + 4.0), Vector2(1.5, head_y + 4.0), Color(0.4, 0.25, 0.2), 0.8)

	# --- HP Bar ---
	_draw_hp_bar(base_y)

	# --- Shadow (oval approximation) ---
	var shadow_pts := PackedVector2Array()
	for i in 12:
		var angle: float = i * TAU / 12.0
		shadow_pts.append(Vector2(cos(angle) * 6, base_y + 15 + sin(angle) * 2))
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.15))


func _draw_headgear(head_y: float, primary: Color, dark: Color, accent: Color) -> void:
	match role:
		0:  # Melee -- helmet
			draw_arc(Vector2(0, head_y), HEAD_RADIUS + 0.5, PI * 0.8, PI * 0.2 + TAU, 12, dark, 2.5)
			# Helmet top
			draw_circle(Vector2(0, head_y - HEAD_RADIUS + 1), 3, dark)
		1:  # Ranged -- hood/bandana
			draw_arc(Vector2(0, head_y), HEAD_RADIUS + 0.5, PI * 0.7, PI * 0.3 + TAU, 12, primary, 2.0)
		2:  # Caster -- pointed hat
			var hat_points := PackedVector2Array([
				Vector2(-6, head_y - 4),
				Vector2(0, head_y - 16),
				Vector2(6, head_y - 4),
			])
			draw_colored_polygon(hat_points, primary)
			draw_circle(Vector2(0, head_y - 16), 1.5, accent)  # Hat tip
		3:  # Flying -- no helmet, spiky hair
			for i in 3:
				var x_off: float = (i - 1) * 3.5
				var spike_pts := PackedVector2Array([
					Vector2(x_off - 2, head_y - 5),
					Vector2(x_off, head_y - 10),
					Vector2(x_off + 2, head_y - 5),
				])
				draw_colored_polygon(spike_pts, dark)
		4:  # Siege -- goggles
			draw_rect(Rect2(-5, head_y - 1, 4, 3), Color(0.5, 0.4, 0.3))
			draw_rect(Rect2(1, head_y - 1, 4, 3), Color(0.5, 0.4, 0.3))
			draw_circle(Vector2(-3, head_y + 0.5), 1.5, Color(0.7, 0.85, 0.95, 0.6))
			draw_circle(Vector2(3, head_y + 0.5), 1.5, Color(0.7, 0.85, 0.95, 0.6))


func _draw_arms_and_weapon(base_y: float, primary: Color, dark: Color, accent: Color) -> void:
	var arm_y: float = base_y + 3.0

	match role:
		0:  # Melee -- sword
			# Left arm
			draw_rect(Rect2(-BODY_W * 0.5 - 3, arm_y, 3, 5), primary)
			# Right arm holding sword
			draw_rect(Rect2(BODY_W * 0.5, arm_y, 3, 5), primary)
			# Sword blade
			draw_rect(Rect2(BODY_W * 0.5 + 1, arm_y - 8, 2, 10), Color(0.8, 0.8, 0.85))
			# Sword hilt
			draw_rect(Rect2(BODY_W * 0.5 - 1, arm_y + 1, 5, 2), accent)

		1:  # Ranged -- bow or thrown weapon
			# Arms
			draw_rect(Rect2(-BODY_W * 0.5 - 3, arm_y, 3, 5), primary)
			draw_rect(Rect2(BODY_W * 0.5, arm_y, 3, 5), primary)
			# Bow
			draw_arc(Vector2(BODY_W * 0.5 + 4, arm_y + 2), 6, -PI * 0.4, PI * 0.4, 8, Color(0.55, 0.35, 0.2), 1.5)
			# Bowstring
			draw_line(
				Vector2(BODY_W * 0.5 + 4 + 6 * cos(-PI * 0.4), arm_y + 2 + 6 * sin(-PI * 0.4)),
				Vector2(BODY_W * 0.5 + 4 + 6 * cos(PI * 0.4), arm_y + 2 + 6 * sin(PI * 0.4)),
				Color(0.7, 0.65, 0.5), 0.8
			)

		2:  # Caster -- staff with glow
			draw_rect(Rect2(-BODY_W * 0.5 - 3, arm_y, 3, 5), primary)
			draw_rect(Rect2(BODY_W * 0.5, arm_y, 3, 5), primary)
			# Staff
			draw_rect(Rect2(-BODY_W * 0.5 - 2, arm_y - 10, 2, 16), Color(0.55, 0.35, 0.2))
			# Orb glow
			draw_circle(Vector2(-BODY_W * 0.5 - 1, arm_y - 11), 3, Color(accent.r, accent.g, accent.b, 0.4))
			draw_circle(Vector2(-BODY_W * 0.5 - 1, arm_y - 11), 2, accent)

		3:  # Flying -- wings
			draw_rect(Rect2(-BODY_W * 0.5 - 2, arm_y, 3, 4), primary)
			draw_rect(Rect2(BODY_W * 0.5, arm_y, 3, 4), primary)
			# Wings
			var wing_flap: float = sin(_time * 8.0) * 3.0
			# Left wing
			var lw := PackedVector2Array([
				Vector2(-BODY_W * 0.5 - 2, arm_y),
				Vector2(-BODY_W * 0.5 - 14, arm_y - 6 + wing_flap),
				Vector2(-BODY_W * 0.5 - 8, arm_y + 4),
			])
			draw_colored_polygon(lw, Color(1, 1, 1, 0.6))
			# Right wing
			var rw := PackedVector2Array([
				Vector2(BODY_W * 0.5 + 2, arm_y),
				Vector2(BODY_W * 0.5 + 14, arm_y - 6 + wing_flap),
				Vector2(BODY_W * 0.5 + 8, arm_y + 4),
			])
			draw_colored_polygon(rw, Color(1, 1, 1, 0.6))

		4:  # Siege -- catapult/wheels
			# No visible arms, it's a machine
			# Wheels
			draw_circle(Vector2(-5, base_y + 11), 3.5, Color(0.4, 0.3, 0.2))
			draw_circle(Vector2(5, base_y + 11), 3.5, Color(0.4, 0.3, 0.2))
			draw_circle(Vector2(-5, base_y + 11), 1.5, Color(0.3, 0.2, 0.15))
			draw_circle(Vector2(5, base_y + 11), 1.5, Color(0.3, 0.2, 0.15))
			# Catapult arm
			var arm_angle: float = sin(_time * 2.0) * 0.1 - 0.3
			var arm_end := Vector2(sin(arm_angle) * 12, -cos(arm_angle) * 12) + Vector2(0, base_y + 2)
			draw_line(Vector2(0, base_y + 2), arm_end, Color(0.55, 0.35, 0.2), 2.5)
			# Boulder
			draw_circle(arm_end, 2.5, Color(0.5, 0.5, 0.5))


func _draw_hp_bar(base_y: float) -> void:
	var bar_y: float = base_y - 16.0
	var bar_w: float = 16.0
	var bar_h: float = 2.5

	# Background
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.7))
	# Fill
	var fill_w: float = bar_w * hp_ratio
	var fill_color: Color
	if hp_ratio > 0.6:
		fill_color = Color(0.2, 0.85, 0.2)
	elif hp_ratio > 0.3:
		fill_color = Color(0.9, 0.8, 0.1)
	else:
		fill_color = Color(0.9, 0.15, 0.1)
	if fill_w > 0:
		draw_rect(Rect2(-bar_w * 0.5, bar_y, fill_w, bar_h), fill_color)
