## Chibi unit visual with animation state machine.
## States: IDLE, WALKING, ATTACKING, CASTING
## Attack animations per role, walk leg cycle, cel shading, team rings.
extends Node2D

enum AnimState { IDLE, WALKING, ATTACKING, CASTING }

var team: int = 0
var role: int = 0
var unit_type: StringName = &""
var hp_ratio: float = 1.0
var facing: float = 1.0

# Animation state
var _anim_state: int = AnimState.IDLE
var _anim_timer: float = 0.0
var _anim_duration: float = 0.0
var _is_moving: bool = false
var _walk_phase: float = 0.0
var _walk_speed_ratio: float = 1.0

# Timing
var _time: float = 0.0
var _hit_flash: float = 0.0
var _blink_timer: float = 3.0
var _is_blinking: bool = false
var _blink_phase: float = 0.0

# Attack offsets (computed in _process, used in _draw)
var _atk_body_x: float = 0.0
var _atk_body_y: float = 0.0
var _atk_weapon_rot: float = 0.0
var _atk_squash: float = 1.0

# T-059: Hit-stop
var _hitstop_timer: float = 0.0
const HITSTOP_DURATION: float = 0.033  # 2 frames at 60fps

# T-059: Smooth direction changes
var _facing_scale: float = 1.0  # 1.0 = full width, 0.0 = squashed mid-turn
var _visual_facing: float = 1.0  # What the draw code uses (lags behind `facing`)
var _turning: bool = false

# Attack durations per role
const ATK_DUR := { 0: 0.35, 1: 0.40, 2: 0.50, 3: 0.40, 4: 0.55 }

# Palettes
const K_SKIN := Color(0.93, 0.78, 0.58)
const K_SKIN_S := Color(0.78, 0.6, 0.42)
const K_PRI := Color(0.25, 0.45, 0.85)
const K_PRI_S := Color(0.15, 0.3, 0.6)
const K_DARK := Color(0.12, 0.22, 0.5)
const K_ACC := Color(0.92, 0.8, 0.3)
const H_SKIN := Color(0.55, 0.75, 0.4)
const H_SKIN_S := Color(0.4, 0.55, 0.28)
const H_PRI := Color(0.82, 0.22, 0.12)
const H_PRI_S := Color(0.58, 0.12, 0.06)
const H_DARK := Color(0.45, 0.1, 0.08)
const H_ACC := Color(0.92, 0.6, 0.2)

const HEAD_R: float = 11.0
const BODY_W: float = 14.0
const BODY_H: float = 10.0
const OL_W: float = 1.8
const OUTLINE := Color(0.1, 0.08, 0.12)


# --- Public API ---

func play_attack(_target_pos: Vector2 = Vector2.ZERO) -> void:
	_anim_state = AnimState.ATTACKING
	_anim_timer = 0.0
	_anim_duration = ATK_DUR.get(role, 0.35)

func play_cast() -> void:
	_anim_state = AnimState.CASTING
	_anim_timer = 0.0
	_anim_duration = 0.50

func set_moving(moving: bool) -> void:
	_is_moving = moving
	if _anim_state == AnimState.IDLE and moving:
		_anim_state = AnimState.WALKING
	elif _anim_state == AnimState.WALKING and not moving:
		_anim_state = AnimState.IDLE

## BUG-40: the sprite path had this; the procedural fallback did not, so
## game_arena's per-frame call errored whenever a unit fell back to procedural
## art. Scales the leg cycle so it matches ground travel like the sprite path.
func set_walk_speed_ratio(ratio: float) -> void:
	_walk_speed_ratio = maxf(ratio, 0.0)

func flash_hit() -> void:
	_hit_flash = 0.12

func trigger_hitstop() -> void:
	_hitstop_timer = HITSTOP_DURATION


# --- Process ---

func _process(delta: float) -> void:
	# T-059: Hit-stop — freeze all animation updates
	if _hitstop_timer > 0:
		_hitstop_timer -= delta
		return  # Skip ALL updates — freeze in place

	_time += delta
	if _hit_flash > 0:
		_hit_flash -= delta

	# T-059: Smooth direction changes — _visual_facing lags behind `facing`
	if facing != _visual_facing and not _turning:
		_turning = true
		_facing_scale = 1.0
	if _turning:
		if _facing_scale > 0.0:
			# Squash phase: shrink to 0 (still showing OLD facing)
			_facing_scale = maxf(0.0, _facing_scale - delta / 0.05)
		else:
			# At midpoint: switch visual facing to match data facing
			_visual_facing = facing
			_turning = false
		queue_redraw()
	elif _facing_scale < 1.0:
		# Expand phase: grow back to 1 (now showing NEW facing)
		_facing_scale = minf(1.0, _facing_scale + delta / 0.05)
		queue_redraw()

	# Blink (only in idle/walking)
	if _anim_state == AnimState.IDLE or _anim_state == AnimState.WALKING:
		_blink_timer -= delta
		if _blink_timer <= 0:
			_is_blinking = true
			_blink_phase = 0.0
			_blink_timer = randf_range(3.0, 5.0)
		if _is_blinking:
			_blink_phase += delta
			if _blink_phase > 0.12:
				_is_blinking = false

	# T-059: Attack timing contrast — variable delta speed for wind-up/strike/recovery
	if _anim_state == AnimState.ATTACKING or _anim_state == AnimState.CASTING:
		var t: float = _anim_timer / maxf(_anim_duration, 0.01)
		var speed_mult: float
		if t < 0.4:
			speed_mult = 0.7  # Slow wind-up
		elif t < 0.6:
			speed_mult = 1.8  # Fast strike
		else:
			speed_mult = 0.9  # Medium recovery
		_anim_timer += delta * speed_mult
		if _anim_timer >= _anim_duration:
			_anim_state = AnimState.WALKING if _is_moving else AnimState.IDLE
			_anim_timer = 0.0

	# Walk phase — scaled by move-speed ratio so legs match ground travel.
	if _anim_state == AnimState.WALKING:
		_walk_phase += delta * 8.0 * _walk_speed_ratio

	# Compute attack offsets
	_compute_attack_offsets()

	# Conditional redraw
	var needs_draw: bool = (
		_anim_state != AnimState.IDLE
		or _hit_flash > 0
		or _is_blinking
		or hp_ratio < 0.999
		or role == 3  # Flying always redraws
		or _facing_scale < 1.0  # T-059: mid-turn
	)
	if needs_draw or fmod(_time, 0.1) < delta:  # Idle redraws at 10fps
		queue_redraw()


func _compute_attack_offsets() -> void:
	_atk_body_x = 0.0
	_atk_body_y = 0.0
	_atk_weapon_rot = 0.0
	_atk_squash = 1.0

	if _anim_state != AnimState.ATTACKING and _anim_state != AnimState.CASTING:
		return

	var t: float = _anim_timer / maxf(_anim_duration, 0.01)

	if _anim_state == AnimState.CASTING:
		# Staff raise
		if t < 0.3:
			_atk_body_y = -2.0 * (t / 0.3)
		elif t < 0.7:
			_atk_body_y = -2.0
		else:
			_atk_body_y = -2.0 * (1.0 - (t - 0.7) / 0.3)
		return

	match role:
		0:  # Melee: lunge + sword swing
			if t < 0.28:
				var p: float = t / 0.28
				_atk_body_x = -3.0 * p * facing
				_atk_weapon_rot = -0.5 * p
			elif t < 0.5:
				var p: float = (t - 0.28) / 0.22
				_atk_body_x = lerpf(-3.0, 6.0, p) * facing
				_atk_weapon_rot = lerpf(-0.5, 1.0, p)
				_atk_squash = 1.0 - 0.08 * (1.0 - p)
			else:
				var p: float = (t - 0.5) / 0.5
				var ep: float = 1.0 - (1.0 - p) * (1.0 - p)
				_atk_body_x = lerpf(6.0, 0.0, ep) * facing
				_atk_weapon_rot = lerpf(1.0, 0.0, ep)
		1:  # Ranged: draw back + release
			if t < 0.5:
				var p: float = t / 0.5
				_atk_body_x = -2.0 * p * p * facing
			elif t < 0.625:
				var p: float = (t - 0.5) / 0.125
				_atk_body_x = lerpf(-2.0, 1.0, p) * facing
			else:
				var p: float = (t - 0.625) / 0.375
				_atk_body_x = lerpf(1.0, 0.0, p) * facing
		3:  # Flying: dive
			if t < 0.25:
				_atk_body_y = -8.0 * (t / 0.25)
			elif t < 0.55:
				var p: float = (t - 0.25) / 0.3
				_atk_body_y = lerpf(-8.0, 4.0, p * p)
				_atk_body_x = 8.0 * p * facing
			else:
				var p: float = (t - 0.55) / 0.45
				var ep: float = 1.0 - (1.0 - p) * (1.0 - p)
				_atk_body_y = lerpf(4.0, 0.0, ep)
				_atk_body_x = lerpf(8.0, 0.0, ep) * facing
		4:  # Siege: arm swing (handled in _draw_siege)
			pass


# --- Draw ---

func _draw() -> void:
	# T-059: Apply squash scale for smooth direction changes
	if _facing_scale < 1.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(_facing_scale, 1.0))

	var skin: Color; var skin_s: Color; var pri: Color; var pri_s: Color
	var dark: Color; var acc: Color
	if team == 0:
		skin = K_SKIN; skin_s = K_SKIN_S; pri = K_PRI; pri_s = K_PRI_S
		dark = K_DARK; acc = K_ACC
	else:
		skin = H_SKIN; skin_s = H_SKIN_S; pri = H_PRI; pri_s = H_PRI_S
		dark = H_DARK; acc = H_ACC

	if _hit_flash > 0:
		var ft: float = _hit_flash / 0.12
		skin = skin.lerp(Color.WHITE, ft * 0.65)
		skin_s = skin_s.lerp(Color.WHITE, ft * 0.5)
		pri = pri.lerp(Color.WHITE, ft * 0.65)
		pri_s = pri_s.lerp(Color.WHITE, ft * 0.5)
		dark = dark.lerp(Color.WHITE, ft * 0.45)

	# Bob (skip during attack)
	var bob: float = 0.0
	if _anim_state != AnimState.ATTACKING:
		var ba: float = 3.0 if role == 3 else 1.5
		var bs: float = 4.0 if role == 3 else 3.0
		bob = sin(_time * bs) * ba
	var sway: float = sin(_time * 2.0 + 0.5) * 0.6
	var by: float = bob + _atk_body_y
	var bx: float = _atk_body_x

	# Team ring
	var tc: Color = pri
	_draw_oval(Vector2(bx, by + 15), 8.0, 2.5, Color(tc.r, tc.g, tc.b, 0.3))
	draw_arc(Vector2(bx, by + 15), 7.0, 0, TAU, 16, Color(tc.r, tc.g, tc.b, 0.7), 1.5)

	# Shadow
	_draw_oval(Vector2(bx, by + 15), 6.0, 2.0, Color(0, 0, 0, 0.22))

	# Siege special path
	if role == 4:
		_draw_siege(by, pri, dark, acc)
		_draw_hp_bar(by)
		if _facing_scale < 1.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	var fx: float = _visual_facing  # T-059: Use visual facing (lags during turn)
	var lean: float = 1.5 * fx if _anim_state == AnimState.WALKING else 0.0

	# --- Legs (with walk animation) ---
	var ly: float = by + 9.0
	if _anim_state == AnimState.WALKING:
		var l1: float = sin(_walk_phase) * 2.5
		var l2: float = sin(_walk_phase + PI) * 2.5
		draw_rect(Rect2(bx - 5, ly + l1, 4, 6), dark)
		draw_rect(Rect2(bx + 1, ly + l2, 4, 6), dark)
		draw_rect(Rect2(bx - 5, ly + l1, 4, 6), OUTLINE, false, OL_W)
		draw_rect(Rect2(bx + 1, ly + l2, 4, 6), OUTLINE, false, OL_W)
	else:
		draw_rect(Rect2(bx - 5, ly, 4, 6), dark)
		draw_rect(Rect2(bx + 1, ly, 4, 6), dark)
		draw_rect(Rect2(bx - 5, ly, 4, 6), OUTLINE, false, OL_W)
		draw_rect(Rect2(bx + 1, ly, 4, 6), OUTLINE, false, OL_W)

	# --- Body ---
	var body_y: float = by + 1.0
	draw_rect(Rect2(bx - BODY_W * 0.5 + lean, body_y, BODY_W, BODY_H), pri)
	draw_rect(Rect2(bx - BODY_W * 0.5 + lean, body_y + BODY_H * 0.5, BODY_W, BODY_H * 0.5), pri_s)
	draw_rect(Rect2(bx - BODY_W * 0.5 + lean, body_y + BODY_H - 2.5, BODY_W, 2.5), dark)
	draw_rect(Rect2(bx - BODY_W * 0.5 + lean, body_y, BODY_W, BODY_H), OUTLINE, false, OL_W)

	# --- Arms + Weapon ---
	_draw_weapon(by, bx, fx, pri, dark, acc)

	# --- Head ---
	var hy: float = by - 7.0
	var hx: float = bx + sway * 0.4
	draw_circle(Vector2(hx, hy), HEAD_R, skin)
	draw_arc(Vector2(hx, hy), HEAD_R * 0.6, 0.1, PI - 0.1, 8, Color(skin_s.r, skin_s.g, skin_s.b, 0.4), HEAD_R * 0.5)
	draw_arc(Vector2(hx, hy), HEAD_R, 0, TAU, 20, OUTLINE, OL_W)

	_draw_headgear(hy, hx, fx, pri, dark, acc)

	if not _is_blinking:
		_draw_eyes(hx, hy)
	else:
		draw_line(Vector2(hx - 4, hy + 1), Vector2(hx - 1, hy + 1), OUTLINE, 1.5)
		draw_line(Vector2(hx + 1, hy + 1), Vector2(hx + 4, hy + 1), OUTLINE, 1.5)

	draw_line(Vector2(hx - 1.5, hy + 4.5), Vector2(hx + 1.5, hy + 4.5), Color(0.35, 0.2, 0.15), 0.8)

	_draw_hp_bar(by)

	# T-059: Reset transform after squash-turn
	if _facing_scale < 1.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_eyes(ex: float, hy: float) -> void:
	var ey: float = hy + 0.5
	draw_circle(Vector2(ex - 3, ey), 2.8, Color.WHITE)
	draw_circle(Vector2(ex + 3, ey), 2.8, Color.WHITE)
	draw_circle(Vector2(ex - 3, ey + 0.3), 1.6, Color(0.08, 0.06, 0.14))
	draw_circle(Vector2(ex + 3, ey + 0.3), 1.6, Color(0.08, 0.06, 0.14))
	draw_circle(Vector2(ex - 2.2, ey - 0.5), 0.7, Color(1, 1, 1, 0.95))
	draw_circle(Vector2(ex + 3.8, ey - 0.5), 0.7, Color(1, 1, 1, 0.95))


func _draw_headgear(hy: float, hx: float, fx: float, pri: Color, dark: Color, acc: Color) -> void:
	match role:
		0:
			draw_arc(Vector2(hx, hy), HEAD_R + 1, PI * 0.75, PI * 0.25 + TAU, 12, dark, 2.8)
			draw_circle(Vector2(hx, hy - HEAD_R + 1), 3.5, dark)
			draw_circle(Vector2(hx, hy - HEAD_R + 1), 2.0, acc)
		1:
			draw_arc(Vector2(hx, hy), HEAD_R + 1, PI * 0.65, PI * 0.35 + TAU, 12, pri, 2.2)
		2:
			var pts := PackedVector2Array([
				Vector2(hx - 6, hy - 4), Vector2(hx, hy - 17), Vector2(hx + 6, hy - 4),
			])
			draw_colored_polygon(pts, pri)
			draw_polyline(pts, OUTLINE, 1.0)
			draw_circle(Vector2(hx, hy - 17), 1.8, acc)
		3:
			for i in 3:
				var xo: float = hx + (i - 1) * 3.5
				var sp := PackedVector2Array([
					Vector2(xo - 2, hy - 5), Vector2(xo, hy - 11), Vector2(xo + 2, hy - 5),
				])
				draw_colored_polygon(sp, dark)


func _draw_weapon(by: float, bx: float, fx: float, pri: Color, dark: Color, acc: Color) -> void:
	var ay: float = by + 3.0

	match role:
		0:  # Sword with attack rotation
			draw_rect(Rect2(bx - BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(bx + BODY_W * 0.5, ay, 3, 5), pri)
			# Sword with rotation during attack
			var sx: float = bx + fx * (BODY_W * 0.5 + 1)
			var pivot := Vector2(sx, ay + 2)
			if _anim_state == AnimState.ATTACKING and _atk_weapon_rot != 0:
				draw_set_transform(pivot, _atk_weapon_rot * fx, Vector2.ONE)
				draw_rect(Rect2(-1, -11, 2, 12), Color(0.82, 0.82, 0.88))
				draw_rect(Rect2(-1, -11, 2, 12), OUTLINE, false, OL_W * 0.5)
				draw_rect(Rect2(-2.5, 0, 5, 2), acc)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			else:
				draw_rect(Rect2(sx - 1, ay - 9, 2, 11), Color(0.82, 0.82, 0.88))
				draw_rect(Rect2(sx - 1, ay - 9, 2, 11), OUTLINE, false, OL_W * 0.5)
				draw_rect(Rect2(sx - 2.5, ay + 1, 5, 2), acc)
		1:  # Bow
			draw_rect(Rect2(bx - BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(bx + BODY_W * 0.5, ay, 3, 5), pri)
			var bow_x: float = bx + fx * (BODY_W * 0.5 + 5)
			draw_arc(Vector2(bow_x, ay + 2), 6, -PI * 0.4 * fx, PI * 0.4 * fx, 8, Color(0.55, 0.35, 0.2), 1.8)
		2:  # Staff
			draw_rect(Rect2(bx - BODY_W * 0.5 - 3, ay, 3, 5), pri)
			draw_rect(Rect2(bx + BODY_W * 0.5, ay, 3, 5), pri)
			var stx: float = bx - fx * (BODY_W * 0.5 + 1)
			var staff_y_off: float = _atk_body_y if _anim_state == AnimState.CASTING else 0.0
			draw_rect(Rect2(stx, ay - 11 + staff_y_off, 2, 17), Color(0.55, 0.35, 0.2))
			draw_rect(Rect2(stx, ay - 11 + staff_y_off, 2, 17), OUTLINE, false, OL_W * 0.5)
			var orb_glow: float = 0.35 + sin(_time * 4.0) * 0.15
			if _anim_state == AnimState.CASTING:
				orb_glow = 0.7 + sin(_time * 12.0) * 0.2
			draw_circle(Vector2(stx + 1, ay - 12 + staff_y_off), 3.5, Color(acc.r, acc.g, acc.b, orb_glow))
			draw_circle(Vector2(stx + 1, ay - 12 + staff_y_off), 2.2, acc)
		3:  # Wings
			draw_rect(Rect2(bx - BODY_W * 0.5 - 2, ay, 3, 4), pri)
			draw_rect(Rect2(bx + BODY_W * 0.5, ay, 3, 4), pri)
			var flap_spd: float = 12.0 if _anim_state == AnimState.WALKING else 8.0
			var flap: float = sin(_time * flap_spd) * 4.0
			var lw := PackedVector2Array([
				Vector2(bx - BODY_W * 0.5 - 2, ay),
				Vector2(bx - BODY_W * 0.5 - 14, ay - 7 + flap),
				Vector2(bx - BODY_W * 0.5 - 8, ay + 4),
			])
			draw_colored_polygon(lw, Color(1, 1, 1, 0.55))
			draw_polyline(lw, Color(0.7, 0.7, 0.8, 0.4), 1.0)
			var rw := PackedVector2Array([
				Vector2(bx + BODY_W * 0.5 + 2, ay),
				Vector2(bx + BODY_W * 0.5 + 14, ay - 7 + flap),
				Vector2(bx + BODY_W * 0.5 + 8, ay + 4),
			])
			draw_colored_polygon(rw, Color(1, 1, 1, 0.55))
			draw_polyline(rw, Color(0.7, 0.7, 0.8, 0.4), 1.0)


func _draw_siege(by: float, pri: Color, dark: Color, acc: Color) -> void:
	var bx: float = _atk_body_x
	draw_rect(Rect2(bx - 10, by + 2, 20, 8), Color(0.5, 0.35, 0.22))
	draw_rect(Rect2(bx - 10, by + 2, 20, 8), OUTLINE, false, 1.0)
	# Wheels (rotate when walking)
	var wheel_rot: float = _walk_phase * 0.5 if _anim_state == AnimState.WALKING else 0.0
	for wx in [-6, 6]:
		draw_circle(Vector2(bx + wx, by + 11), 4.0, Color(0.4, 0.3, 0.2))
		draw_arc(Vector2(bx + wx, by + 11), 4.0, 0, TAU, 12, OUTLINE, 1.0)
		# Spokes that rotate
		draw_line(
			Vector2(bx + wx + cos(wheel_rot) * 2.5, by + 11 + sin(wheel_rot) * 2.5),
			Vector2(bx + wx - cos(wheel_rot) * 2.5, by + 11 - sin(wheel_rot) * 2.5),
			Color(0.3, 0.2, 0.12), 1.0
		)
	# Catapult arm
	var arm_ang: float
	var show_boulder: bool = true
	if _anim_state == AnimState.ATTACKING:
		var t: float = _anim_timer / maxf(_anim_duration, 0.01)
		if t < 0.45:
			arm_ang = lerpf(-0.3, -1.2, t / 0.45)
		elif t < 0.64:
			var p: float = (t - 0.45) / 0.19
			arm_ang = lerpf(-1.2, 0.6, p * p * (3.0 - 2.0 * p))
			if p > 0.7:
				show_boulder = false
		else:
			var p: float = (t - 0.64) / 0.36
			arm_ang = -0.3 + exp(-p * 4.0) * sin(p * 12.0) * 0.15
			show_boulder = false
	else:
		arm_ang = sin(_time * 2.5) * 0.12 - 0.3

	var arm_end := Vector2(sin(arm_ang) * 13, -cos(arm_ang) * 13) + Vector2(bx, by + 2)
	draw_line(Vector2(bx, by + 2), arm_end, Color(0.55, 0.35, 0.2), 2.8)
	draw_line(Vector2(bx, by + 2), arm_end, OUTLINE, 0.8)
	if show_boulder:
		draw_circle(arm_end, 3.0, Color(0.55, 0.55, 0.5))
		draw_arc(arm_end, 3.0, 0, TAU, 8, OUTLINE, 0.8)
	draw_rect(Rect2(arm_end.x - 1, arm_end.y - 6, 6, 4), pri)


func _draw_hp_bar(by: float) -> void:
	if hp_ratio >= 0.999:
		return
	var bar_y: float = by - 17.0
	var bar_w: float = 16.0
	var bar_h: float = 4.0
	# T-007: Sprite HP bar with fallback
	var bar_base: Texture2D = SpriteRegistry.get_ui_texture(&"SmallBar_Base")
	var bar_fill: Texture2D = SpriteRegistry.get_ui_texture(&"SmallBar_Fill")
	if bar_base:
		draw_texture_rect(bar_base, Rect2(-bar_w * 0.5 - 1, bar_y - 1, bar_w + 2, bar_h + 2), false)
	else:
		draw_rect(Rect2(-bar_w * 0.5 - 0.5, bar_y - 0.5, bar_w + 1, bar_h + 1), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.08, 0.08, 0.9))
	var fw: float = bar_w * hp_ratio
	var fc: Color
	if hp_ratio > 0.6:
		fc = Color(0.15, 0.85, 0.15)
	elif hp_ratio > 0.3:
		fc = Color(0.92, 0.8, 0.08)
	else:
		fc = Color(0.92, 0.12, 0.08)
	if fw > 0:
		if bar_fill:
			draw_texture_rect(bar_fill, Rect2(-bar_w * 0.5, bar_y, fw, bar_h), false, fc)
		else:
			draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h), fc)
			draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h * 0.4), Color(1, 1, 1, 0.2))


func _draw_oval(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = i * TAU / 16.0
		pts.append(Vector2(center.x + cos(a) * rx, center.y + sin(a) * ry))
	draw_colored_polygon(pts, color)
