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

	# Scale punch + float up + fade (deferred until in scene tree)
	node.scale = Vector2(1.5, 1.5)
	var target_y: float = pos.y - 35
	node.tree_entered.connect(func():
		var tween := node.create_tween()
		tween.set_parallel(true)
		tween.tween_property(node, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "position:y", target_y, 0.7).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "modulate:a", 0.0, 0.7).set_delay(0.25)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)
	, CONNECT_ONE_SHOT)

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


## Arrow projectile — use sprite arrow texture if available, else bright procedural.
static func create_arrow_projectile(from_pos: Vector2, to_pos: Vector2, team: int) -> Node2D:
	var arrow_tex: Texture2D = SpriteRegistry.get_arrow_texture(team)
	if arrow_tex:
		var node := _ArrowEffect.new()
		node.position = from_pos
		node.z_index = 80
		node._texture = arrow_tex
		node._target_pos = to_pos
		node._target_px = 22.0   # Small arrow
		node._duration = CombatTuning.flight_time(&"arrow", from_pos, to_pos)
		return node
	# Fallback: bright procedural
	var color := Color(0.2, 0.6, 1.0) if team == 0 else Color(1.0, 0.3, 0.2)
	return create_projectile(from_pos, to_pos, color, CombatTuning.flight_time(&"arrow", from_pos, to_pos))


## Rock projectile — use sprite rock texture if available.
static func create_rock_projectile(from_pos: Vector2, to_pos: Vector2, team: int) -> Node2D:
	var rock_tex: Texture2D = SpriteRegistry.get_rock_texture(team)
	if rock_tex:
		var node := _ArrowEffect.new()
		node.position = from_pos
		node.z_index = 80
		node._texture = rock_tex
		node._target_pos = to_pos
		node._target_px = 18.0   # Medium rock
		node._duration = CombatTuning.flight_time(&"rock", from_pos, to_pos)  # Slower arc feel
		return node
	return create_projectile(from_pos, to_pos, Color(0.7, 0.5, 0.25), CombatTuning.flight_time(&"rock", from_pos, to_pos))


## Fireball projectile for mage — magic projectile with sprite + glow fallback.
static func create_fireball_projectile(from_pos: Vector2, to_pos: Vector2, team: int) -> Node2D:
	var fb_tex: Texture2D = SpriteRegistry.get_fireball_texture(team)
	if fb_tex:
		var node := _ArrowEffect.new()
		node.position = from_pos
		node.z_index = 80
		node._texture = fb_tex
		node._target_pos = to_pos
		node._target_px = 32.0
		node._duration = CombatTuning.flight_time(&"fireball", from_pos, to_pos)
		return node
	# Fallback: glowing magic orb
	var color := Color(0.4, 0.7, 1.0) if team == 0 else Color(1.0, 0.5, 0.2)
	return create_projectile(from_pos, to_pos, color, CombatTuning.flight_time(&"fireball", from_pos, to_pos))


## Bolt projectile for ballista — use sprite bolt texture if available.
static func create_bolt_projectile(from_pos: Vector2, to_pos: Vector2, team: int) -> Node2D:
	var bolt_tex: Texture2D = SpriteRegistry.get_bolt_texture(team)
	if bolt_tex:
		var node := _ArrowEffect.new()
		node.position = from_pos
		node.z_index = 80
		node._texture = bolt_tex
		node._target_pos = to_pos
		# T-082 UPDATE: User now wants 4× archer arrow size. A6 upscaled the
		# source PNG to 256×256. 22 (archer) × 4 = 88.
		node._target_px = 88.0
		node._duration = CombatTuning.flight_time(&"bolt", from_pos, to_pos)  # Very fast
		return node
	var color := Color(0.5, 0.7, 0.9) if team == 0 else Color(0.9, 0.5, 0.3)
	return create_projectile(from_pos, to_pos, color, CombatTuning.flight_time(&"bolt", from_pos, to_pos))


## Sprite-based heal effect (uses Heal_Effect.png from Tiny Swords).
static func create_sprite_heal(pos: Vector2, team: int) -> Node2D:
	var sf: SpriteFrames = SpriteRegistry.get_heal_effect_frames(team)
	if sf == null:
		# Fallback to procedural heal sparkle
		return create_heal_sparkle(pos)
	var node := _SpriteHealEffect.new()
	node.position = pos + Vector2(0, -5)
	node.z_index = 90
	node._sprite_frames = sf
	return node


## Sprite-based explosion (uses Explosion_01/02.png).
static func create_explosion(pos: Vector2, scale_factor: float = 0.5) -> Node2D:
	var sf: SpriteFrames = SpriteRegistry.get_explosion_frames()
	if sf == null:
		return create_death_poof(pos, Color(1, 0.6, 0.1))
	var node := Node2D.new()
	node.position = pos
	node.z_index = 95
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.centered = true
	node.add_child(anim)
	anim.play(&"explosion")
	anim.animation_finished.connect(node.queue_free)
	return node


## Sprite-based dust puff (uses Dust_01/02.png).
static func create_dust(pos: Vector2, scale_factor: float = 0.4) -> Node2D:
	var sf: SpriteFrames = SpriteRegistry.get_dust_frames()
	if sf == null:
		return create_spawn_burst(pos, Color(0.6, 0.5, 0.3))
	var node := Node2D.new()
	node.position = pos
	node.z_index = 35
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.centered = true
	node.add_child(anim)
	anim.play(&"dust")
	anim.animation_finished.connect(node.queue_free)
	return node


## Sprite-based fire loop (uses Fire_01/02/03.png). Returns node to manage lifecycle.
static func create_fire(pos: Vector2, scale_factor: float = 0.5) -> Node2D:
	var sf: SpriteFrames = SpriteRegistry.get_fire_frames()
	if sf == null:
		# Fallback: no fire
		return Node2D.new()
	var node := Node2D.new()
	node.position = pos
	node.z_index = 85
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.centered = true
	node.add_child(anim)
	anim.play(&"fire")
	return node


static func create_spawn_burst(pos: Vector2, color: Color) -> Node2D:
	var node := _SpawnEffect.new()
	node.position = pos
	node.z_index = 40
	node.color = color
	return node


## T-022: Skill visual effects

static func create_skill_effect(skill: StringName, pos: Vector2, team: int = 0) -> Node2D:
	var tc := Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
	match skill:
		&"critical_strike":
			return _create_crit_effect(pos)
		&"evasion":
			return _create_dodge_blur(pos)
		&"battle_cry":
			return _create_ring_pulse(pos, tc, 60.0)
		&"mana_shield", &"mana_shield_break":
			return _create_shield_flash(pos)
		&"piercing_shot":
			return _create_piercing_trail(pos)
		&"enrage", &"blood_frenzy":
			return _create_glow_flash(pos, Color(1.0, 0.2, 0.1, 0.7), 12.0)
		&"burning_ground":
			return create_fire(pos, 0.3)
		# 1D-4 (2026-07-19): devotion_aura / cleave / siege_momentum branches
		# DELETED — the sim never emits skill_proc for them (passives/no such
		# skill), so the arms were unreachable. Re-add together with a sim proc.
		&"charge", &"charge_hit":
			return _create_glow_flash(pos, Color(0.9, 0.6, 0.15, 0.7), 10.0)
		&"volley":
			return _create_ring_pulse(pos, Color(0.8, 0.6, 0.3), 35.0)
		&"holy_light":
			return _create_glow_flash(pos, Color(1.0, 1.0, 0.6, 0.6), 15.0)
		&"toughness":
			return _create_shield_flash(pos)
		&"rending_throw":
			return _create_glow_flash(pos, Color(0.7, 0.2, 0.15, 0.7), 8.0)
		&"lance_pierce":
			return _create_lance_thrust(pos, tc)
		&"fireball":
			return _create_fireball_burst(pos)
		_:
			return _create_glow_flash(pos, tc, 6.0)


static func _create_crit_effect(pos: Vector2) -> Node2D:
	var node := _SkillFlash.new()
	node.position = pos
	node.z_index = 45
	node._color = Color(1.0, 0.9, 0.2)
	node._text = "CRIT!"
	node._radius = 10.0
	return node


static func _create_dodge_effect(pos: Vector2) -> Node2D:
	var node := _SkillFlash.new()
	node.position = pos
	node.z_index = 45
	node._color = Color(0.7, 0.8, 1.0, 0.6)
	node._text = "DODGE"
	node._radius = 6.0
	node._duration = 0.3
	return node


static func _create_shield_flash(pos: Vector2) -> Node2D:
	var node := _SkillFlash.new()
	node.position = pos
	node.z_index = 44
	node._color = Color(0.3, 0.5, 1.0, 0.7)
	node._text = ""
	node._radius = 14.0
	node._is_hex = true
	return node


static func _create_glow_flash(pos: Vector2, color: Color, radius: float) -> Node2D:
	var node := _SkillFlash.new()
	node.position = pos
	node.z_index = 42
	node._color = color
	node._text = ""
	node._radius = radius
	return node


static func _create_ring_pulse(pos: Vector2, color: Color, max_radius: float) -> Node2D:
	var node := _RingPulse.new()
	node.position = pos
	node.z_index = 43
	node._color = color
	node._max_radius = max_radius
	return node

static func _create_piercing_trail(pos: Vector2) -> Node2D:
	var node := _PiercingTrail.new()
	node.position = pos
	node.z_index = 45
	return node


## T-022: Evasion — brief afterimage/dodge blur
static func _create_dodge_blur(pos: Vector2) -> Node2D:
	var node := _DodgeBlur.new()
	node.position = pos
	node.z_index = 45
	return node


## T-076: Lance Pierce — thrust line from attacker through targets.
## The line extends 60px downward (march direction) and fades.
static func _create_lance_thrust(pos: Vector2, team_color: Color) -> Node2D:
	var node := _LanceThrust.new()
	node.position = pos
	node.z_index = 46
	node._color = team_color
	return node


## T-084 Mage fireball splash — radial magic burst.
## Orange/yellow expanding ring + core flash + 10-particle spark spray.
## Mirror of the boulder_splash VFX pattern.
static func _create_fireball_burst(pos: Vector2) -> Node2D:
	var node := _FireballBurst.new()
	node.position = pos
	node.z_index = 46
	return node


class _SkillFlash extends Node2D:
	var _color := Color.WHITE
	var _text: String = ""
	var _radius: float = 8.0
	var _is_hex: bool = false
	var _duration: float = 0.4
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= _duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / _duration
		var alpha: float = 1.0 - t
		var r: float = _radius * (0.5 + t * 0.5)

		if _is_hex:
			# Hexagonal barrier
			var pts := PackedVector2Array()
			for i in 6:
				var a: float = i * TAU / 6.0 - PI / 6.0
				pts.append(Vector2(cos(a) * r, sin(a) * r))
			draw_colored_polygon(pts, Color(_color.r, _color.g, _color.b, alpha * 0.3))
			for i in 6:
				var a1: float = i * TAU / 6.0 - PI / 6.0
				var a2: float = (i + 1) * TAU / 6.0 - PI / 6.0
				draw_line(Vector2(cos(a1) * r, sin(a1) * r), Vector2(cos(a2) * r, sin(a2) * r),
					Color(_color.r, _color.g, _color.b, alpha * 0.8), 2.0)
		else:
			# Circular flash
			draw_circle(Vector2.ZERO, r, Color(_color.r, _color.g, _color.b, alpha * 0.4))
			if t < 0.2:
				draw_circle(Vector2.ZERO, r * 0.5, Color(1, 1, 1, (1.0 - t / 0.2) * 0.5))

		# Text (floats up)
		if _text != "":
			var ty: float = -15.0 - t * 20.0
			draw_string(ThemeDB.fallback_font, Vector2(-16, ty), _text,
				HORIZONTAL_ALIGNMENT_CENTER, 32, 12, Color(_color.r, _color.g, _color.b, alpha))


class _RingPulse extends Node2D:
	var _color := Color.WHITE
	var _max_radius: float = 50.0
	var _time: float = 0.0
	const DURATION: float = 0.5

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var r: float = _max_radius * t
		var alpha: float = 0.7 * (1.0 - t)
		draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(_color.r, _color.g, _color.b, alpha), 2.5)
		if t < 0.3:
			draw_arc(Vector2.ZERO, r * 0.7, 0, TAU, 16, Color(1, 1, 1, alpha * 0.3), 1.5)


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
		draw_circle(Vector2.ZERO, 6.0, Color(color.r, color.g, color.b, 0.35))
		# Core
		draw_circle(Vector2.ZERO, 3.5, color)
		# Trail
		var dir: Vector2 = (_start_pos - _target_pos).normalized()
		draw_line(Vector2.ZERO, dir * 10, Color(color.r, color.g, color.b, 0.5), 2.5)


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


class _ArrowEffect extends Node2D:
	var _texture: Texture2D = null
	var _target_pos: Vector2 = Vector2.ZERO
	var _start_pos: Vector2 = Vector2.ZERO
	var _time: float = 0.0
	var _sprite: Sprite2D = null
	var _target_px: float = 24.0  # Target display size in pixels
	# 1C-3: duration comes from CombatTuning.flight_time, set by the creator —
	# game_arena defers impact FX by the same number, so arrival must not be
	# recomputed here from a separate speed.
	var _duration: float = 0.2

	func _ready() -> void:
		_start_pos = position
		_sprite = Sprite2D.new()
		_sprite.texture = _texture
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var s: float = _target_px / maxf(_texture.get_height(), 1.0)
		_sprite.scale = Vector2(s, s)
		var dir: Vector2 = (_target_pos - _start_pos).normalized()
		_sprite.rotation = dir.angle()
		add_child(_sprite)

	func _process(delta: float) -> void:
		_time += delta
		var t: float = minf(_time / maxf(_duration, 0.05), 1.0)
		position = _start_pos.lerp(_target_pos, t)
		if t >= 1.0:
			queue_free()


## T-022: Pulsing gold ring for Devotion Aura — lingers 0.8s with 2 pulse cycles.
class _AuraRing extends Node2D:
	var _color := Color(1.0, 0.85, 0.2)
	var _time: float = 0.0
	const DURATION: float = 0.8
	const RADIUS: float = 20.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var fade: float = 1.0 - t
		# Pulsing radius via sine wave (2 pulses over lifetime)
		var pulse: float = 1.0 + 0.15 * sin(_time * TAU * 2.5)
		var r: float = RADIUS * pulse
		# Outer ring
		draw_arc(Vector2.ZERO, r, 0, TAU, 24,
			Color(_color.r, _color.g, _color.b, fade * 0.6), 2.0)
		# Inner glow
		draw_arc(Vector2.ZERO, r * 0.7, 0, TAU, 16,
			Color(_color.r, _color.g, _color.b, fade * 0.2), 4.0)


## T-022: Arc slash for Cleave — sweeping arc that fades.
class _CleaveArc extends Node2D:
	var _color := Color.WHITE
	var _time: float = 0.0
	const DURATION: float = 0.3
	const ARC_RADIUS: float = 18.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 0.8 * (1.0 - t)
		# Sweep arc from -60° to +60° (120° slash)
		var sweep: float = PI * 0.67 * minf(t * 3.0, 1.0)  # Fast sweep
		var start_angle: float = -PI * 0.33
		var r: float = ARC_RADIUS * (0.8 + t * 0.4)
		# Main slash arc
		draw_arc(Vector2.ZERO, r, start_angle, start_angle + sweep, 12,
			Color(_color.r, _color.g, _color.b, alpha), 3.0)
		# White leading edge
		if t < 0.5:
			var edge_angle: float = start_angle + sweep
			var edge_pos := Vector2(cos(edge_angle) * r, sin(edge_angle) * r)
			draw_circle(edge_pos, 3.0 * (1.0 - t * 2.0), Color(1, 1, 1, alpha))


## T-022: Piercing Shot trail — bright white streak with glow.
class _PiercingTrail extends Node2D:
	var _time: float = 0.0
	const DURATION: float = 0.35

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 0.9 * (1.0 - t)
		# Bright white core flash
		var r: float = 4.0 + t * 6.0
		draw_circle(Vector2.ZERO, r, Color(1.0, 1.0, 0.9, alpha * 0.5))
		draw_circle(Vector2.ZERO, r * 0.4, Color(1.0, 1.0, 1.0, alpha))
		# Trail streak downward (arrow direction)
		var trail_len: float = 12.0 + t * 8.0
		draw_line(Vector2.ZERO, Vector2(0, trail_len),
			Color(1.0, 1.0, 0.8, alpha * 0.6), 2.5)
		draw_line(Vector2(-2, 0), Vector2(-2, trail_len * 0.7),
			Color(1.0, 1.0, 0.8, alpha * 0.3), 1.5)
		draw_line(Vector2(2, 0), Vector2(2, trail_len * 0.7),
			Color(1.0, 1.0, 0.8, alpha * 0.3), 1.5)


## T-022: Dodge blur — brief afterimage (3 fading copies offset sideways).
class _DodgeBlur extends Node2D:
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
		# 3 afterimage silhouettes offset to the side (dodge direction)
		for i in 3:
			var offset_x: float = -(i + 1) * 5.0
			var ghost_alpha: float = alpha * (0.7 - i * 0.2)
			# Simple oval silhouette
			var c := Color(0.7, 0.8, 1.0, ghost_alpha)
			draw_circle(Vector2(offset_x, -5), 4.0 - i * 0.5, c)
			draw_circle(Vector2(offset_x, 2), 3.0 - i * 0.3, c)
		# "DODGE" text above
		var ty: float = -18.0 - t * 15.0
		draw_string(ThemeDB.fallback_font, Vector2(-20, ty), "DODGE",
			HORIZONTAL_ALIGNMENT_CENTER, 40, 11,
			Color(0.7, 0.8, 1.0, alpha))


## T-076: Lance Pierce thrust line — fading line downward through targets.
class _LanceThrust extends Node2D:
	var _color := Color.WHITE
	var _time: float = 0.0
	const DURATION: float = 0.35
	const THRUST_LEN: float = 60.0  # Line extends this far from attacker

	func _process(delta: float) -> void:
		_time += delta
		if _time >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _time / DURATION
		var alpha: float = 0.85 * (1.0 - t)
		var len_t: float = THRUST_LEN * minf(t * 4.0, 1.0)  # Fast extend
		# Main thrust line (vertical, downward in march direction)
		draw_line(Vector2.ZERO, Vector2(0, len_t),
			Color(_color.r, _color.g, _color.b, alpha), 3.0)
		# Bright leading tip
		if t < 0.5:
			var tip_y: float = len_t
			draw_circle(Vector2(0, tip_y), 4.0 * (1.0 - t * 2.0),
				Color(1, 1, 1, alpha * 0.8))
		# Impact flashes along the line (3 evenly spaced)
		for i in 3:
			var flash_y: float = len_t * (0.3 + i * 0.25)
			var flash_alpha: float = alpha * maxf(0.0, 1.0 - t * 3.0 + i * 0.3)
			if flash_alpha > 0:
				draw_circle(Vector2(0, flash_y), 3.0,
					Color(_color.r, _color.g, _color.b, flash_alpha * 0.5))


class _SpriteHealEffect extends Node2D:
	var _sprite_frames: SpriteFrames = null
	var _anim: AnimatedSprite2D = null

	func _ready() -> void:
		_anim = AnimatedSprite2D.new()
		_anim.sprite_frames = _sprite_frames
		_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_anim.scale = Vector2(0.25, 0.25)  # 192px * 0.25 ≈ 48px
		_anim.centered = true
		add_child(_anim)
		_anim.play(&"heal_effect")
		_anim.animation_finished.connect(queue_free)


## T-084 Mage fireball splash burst.
## Orange/yellow ring expands outward + bright core + 10 spark particles.
class _FireballBurst extends Node2D:
	var _elapsed: float = 0.0
	const _DURATION: float = 0.55
	const _MAX_RADIUS: float = 56.0  # matches sim splash radius (1.5 cells ≈ 42px) + overshoot
	var _sparks: Array[Vector2] = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in 10:
			var angle: float = rng.randf_range(0, TAU)
			var dist: float = rng.randf_range(18.0, _MAX_RADIUS)
			_sparks.append(Vector2(cos(angle) * dist, sin(angle) * dist))
		set_process(true)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= _DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_elapsed / _DURATION, 0.0, 1.0)
		var ease_out: float = 1.0 - pow(1.0 - t, 3.0)
		var fade: float = 1.0 - t

		# Bright core flash — shrinks as it fades.
		var core_r: float = lerpf(18.0, 6.0, t)
		draw_circle(Vector2.ZERO, core_r, Color(1.0, 0.95, 0.5, 0.7 * fade))

		# Expanding outer ring (magic shock).
		var ring_r: float = _MAX_RADIUS * ease_out
		draw_arc(Vector2.ZERO, ring_r, 0, TAU, 42, Color(1.0, 0.55, 0.15, 0.9 * fade), 3.5)

		# Secondary thinner ring, trailing.
		var ring2_r: float = _MAX_RADIUS * (ease_out * 0.75)
		draw_arc(Vector2.ZERO, ring2_r, 0, TAU, 36, Color(1.0, 0.8, 0.3, 0.55 * fade), 2.0)

		# Sparks flying outward — each lerps from 0 → final position, shrinks.
		var spark_r: float = lerpf(4.0, 1.5, t) * (1.0 - t * 0.5)
		for offset in _sparks:
			var p: Vector2 = offset * ease_out
			draw_circle(p, spark_r, Color(1.0, 0.85, 0.35, 0.8 * fade))
