## Visual effects: damage numbers, death poof, heal sparkle, projectiles, spawn burst.
## All effects are self-contained Node2D scripts that auto-free after their animation.
class_name Effects


## Floating damage number that rises and fades.
static func create_damage_number(value: int, pos: Vector2, is_heal: bool = false) -> Node2D:
	var node := Node2D.new()
	node.position = pos + Vector2(randf_range(-6, 6), -10)
	node.z_index = 100

	var label := Label.new()
	label.text = ("+%d" if is_heal else "-%d") % value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11 if value < 20 else 14)
	label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if is_heal else Color(1.0, 0.9, 0.2))
	label.position = Vector2(-20, -8)
	label.size = Vector2(40, 16)
	node.add_child(label)

	# Animate: float up + fade
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", pos.y - 30, 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)

	return node


## Death poof: shrinking circle + small particles flying out.
static func create_death_poof(pos: Vector2, team_color: Color) -> Node2D:
	var node := _PoofEffect.new()
	node.position = pos
	node.z_index = 50
	node.color = team_color
	return node


## Projectile: colored dot traveling from source to target.
static func create_projectile(from_pos: Vector2, to_pos: Vector2, color: Color, duration: float = 0.15) -> Node2D:
	var node := _ProjectileEffect.new()
	node.position = from_pos
	node.z_index = 80
	node.color = color
	node._target_pos = to_pos
	node._duration = duration
	return node


## Heal sparkle: green plus sign that pops and fades.
static func create_heal_sparkle(pos: Vector2) -> Node2D:
	var node := _HealEffect.new()
	node.position = pos + Vector2(0, -5)
	node.z_index = 90
	return node


## Spawn burst: expanding ring.
static func create_spawn_burst(pos: Vector2, color: Color) -> Node2D:
	var node := _SpawnEffect.new()
	node.position = pos
	node.z_index = 40
	node.color = color
	return node


# --- Internal effect classes ---

class _PoofEffect extends Node2D:
	var color: Color = Color.WHITE
	var _time: float = 0.0
	var _particles: Array = []
	const DURATION: float = 0.35

	func _ready() -> void:
		for i in 6:
			var angle: float = i * TAU / 6.0 + randf() * 0.5
			var speed: float = randf_range(30, 60)
			_particles.append({
				"angle": angle, "speed": speed,
				"size": randf_range(2, 4),
			})

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		# Central circle shrinking
		var radius: float = 8.0 * (1.0 - t)
		if radius > 0:
			draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 1.0 - t))
		# Particles flying outward
		for p in _particles:
			var dist: float = p.speed * _time
			var px: float = cos(p.angle) * dist
			var py: float = sin(p.angle) * dist
			var size: float = p.size * (1.0 - t)
			if size > 0:
				draw_rect(
					Rect2(px - size * 0.5, py - size * 0.5, size, size),
					Color(color.r, color.g, color.b, 0.8 * (1.0 - t))
				)


class _ProjectileEffect extends Node2D:
	var color: Color = Color.WHITE
	var _target_pos: Vector2 = Vector2.ZERO
	var _duration: float = 0.15
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
		draw_circle(Vector2.ZERO, 2.5, color)
		# Trail
		var dir: Vector2 = (_start_pos - _target_pos).normalized()
		draw_line(Vector2.ZERO, dir * 6, Color(color.r, color.g, color.b, 0.4), 1.5)


class _HealEffect extends Node2D:
	var _time: float = 0.0
	const DURATION: float = 0.4

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 1.0 - t
		var s: float = 3.0 + t * 4.0
		var color := Color(0.2, 1.0, 0.3, alpha)
		# Plus sign
		draw_rect(Rect2(-s * 0.3, -s, s * 0.6, s * 2), color)
		draw_rect(Rect2(-s, -s * 0.3, s * 2, s * 0.6), color)
		# Ring
		draw_arc(Vector2.ZERO, s * 1.5, 0, TAU, 12, Color(0.2, 1.0, 0.3, alpha * 0.5), 1.5)


class _SpawnEffect extends Node2D:
	var color: Color = Color.WHITE
	var _time: float = 0.0
	const DURATION: float = 0.25

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var radius: float = 5.0 + t * 15.0
		var alpha: float = 0.6 * (1.0 - t)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 16, Color(color.r, color.g, color.b, alpha), 2.0)
