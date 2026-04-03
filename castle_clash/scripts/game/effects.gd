## A-grade visual effects: punchy damage numbers, satisfying death poofs,
## glowing projectiles, sparkle heals, burst spawns.
class_name Effects
extends RefCounted


static func create_damage_number(value: int, pos: Vector2, is_heal: bool = false) -> Node2D:
	var node := Node2D.new()
	node.position = pos + Vector2(randf_range(-8, 8), -12)
	node.z_index = 100

	var label := Label.new()
	label.text = ("+%d" if is_heal else "%d") % value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13 if value < 15 else 17)
	label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if is_heal else Color(1.0, 0.95, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-24, -10)
	label.size = Vector2(48, 20)
	node.add_child(label)

	# Scale punch + float up + fade
	node.scale = Vector2(1.5, 1.5)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", pos.y - 35, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)

	return node


static func create_death_poof(pos: Vector2, team_color: Color) -> Node2D:
	var node := _PoofEffect.new()
	node.position = pos
	node.z_index = 50
	node.color = team_color
	return node


static func create_projectile(from_pos: Vector2, to_pos: Vector2, color: Color, duration: float = 0.14) -> Node2D:
	var node := _ProjectileEffect.new()
	node.position = from_pos
	node.z_index = 80
	node.color = color
	node._target_pos = to_pos
	node._duration = duration
	return node


static func create_heal_sparkle(pos: Vector2) -> Node2D:
	var node := _HealEffect.new()
	node.position = pos + Vector2(0, -5)
	node.z_index = 90
	return node


static func create_spawn_burst(pos: Vector2, color: Color) -> Node2D:
	var node := _SpawnEffect.new()
	node.position = pos
	node.z_index = 40
	node.color = color
	return node


class _PoofEffect extends Node2D:
	var color: Color = Color.WHITE
	var _time: float = 0.0
	var _particles: Array = []
	const DURATION: float = 0.5

	func _ready() -> void:
		for i in 8:
			var angle: float = i * TAU / 8.0 + randf() * 0.5
			_particles.append({
				"angle": angle,
				"speed": randf_range(40, 80),
				"size": randf_range(2.5, 5.0),
			})

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		# Central burst circle
		var r: float = 12.0 * (1.0 - t)
		if r > 0:
			draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.7 * (1.0 - t)))
			# White core flash
			if t < 0.2:
				draw_circle(Vector2.ZERO, r * 0.6, Color(1, 1, 1, 0.5 * (1.0 - t / 0.2)))
		# Particles
		for p in _particles:
			var dist: float = p.speed * _time
			var px: float = cos(p.angle) * dist
			var py: float = sin(p.angle) * dist
			var sz: float = p.size * (1.0 - t)
			if sz > 0.5:
				draw_rect(
					Rect2(px - sz * 0.5, py - sz * 0.5, sz, sz),
					Color(color.r, color.g, color.b, 0.8 * (1.0 - t))
				)


class _ProjectileEffect extends Node2D:
	var color: Color = Color.WHITE
	var _target_pos: Vector2 = Vector2.ZERO
	var _duration: float = 0.14
	var _time: float = 0.0
	var _start_pos: Vector2 = Vector2.ZERO

	func _ready() -> void:
		_start_pos = position

	func _process(delta: float) -> void:
		_time += delta
		var t: float = minf(_time / _duration, 1.0)
		position = _start_pos.lerp(_target_pos, t)
		if t >= 1.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		# Glow
		draw_circle(Vector2.ZERO, 5.0, Color(color.r, color.g, color.b, 0.3))
		# Core
		draw_circle(Vector2.ZERO, 3.0, color)
		# Trail
		var dir: Vector2 = (_start_pos - _target_pos).normalized()
		draw_line(Vector2.ZERO, dir * 8, Color(color.r, color.g, color.b, 0.5), 2.0)


class _HealEffect extends Node2D:
	var _time: float = 0.0
	const DURATION: float = 0.45

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 1.0 - t
		var s: float = 3.0 + t * 5.0
		var gc := Color(0.2, 1.0, 0.3, alpha)
		# Plus sign
		draw_rect(Rect2(-s * 0.3, -s, s * 0.6, s * 2), gc)
		draw_rect(Rect2(-s, -s * 0.3, s * 2, s * 0.6), gc)
		# Ring
		draw_arc(Vector2.ZERO, s * 1.5, 0, TAU, 14, Color(0.2, 1.0, 0.3, alpha * 0.4), 1.5)
		# Sparkle particles
		for i in 4:
			var px: float = sin(_time * 10.0 + i * 1.5) * s * 0.8
			var py: float = -t * 10.0 - i * 3.0
			draw_circle(Vector2(px, py), 1.2, Color(0.4, 1.0, 0.5, alpha * 0.6))


class _SpawnEffect extends Node2D:
	var color: Color = Color.WHITE
	var _time: float = 0.0
	const DURATION: float = 0.3

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 0.6 * (1.0 - t)
		# Central flash
		if t < 0.25:
			draw_circle(Vector2.ZERO, 5.0 * (1.0 - t / 0.25), Color(color.r, color.g, color.b, 0.5))
		# Outer ring
		var r1: float = 5.0 + t * 18.0
		draw_arc(Vector2.ZERO, r1, 0, TAU, 16, Color(color.r, color.g, color.b, alpha), 2.0)
		# Inner ring (delayed)
		if t > 0.08:
			var t2: float = (t - 0.08) / 0.92
			var r2: float = 3.0 + t2 * 12.0
			draw_arc(Vector2.ZERO, r2, 0, TAU, 12, Color(1, 1, 1, alpha * 0.35), 1.5)
