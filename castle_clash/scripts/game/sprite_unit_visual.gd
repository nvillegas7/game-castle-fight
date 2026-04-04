## Sprite-based unit visual using AnimatedSprite2D.
## Drop-in replacement for unit_visual.gd when real sprite sheets are available.
## Falls back to procedural _draw() if no sprite frames are set.
extends Node2D

var team: int = 0
var role: int = 0
var unit_type: StringName = &""
var hp_ratio: float = 1.0
var facing: float = 1.0
var _is_moving: bool = false
var _hit_flash: float = 0.0
var _anim_state: int = 0  # 0=idle, 1=walk, 2=attack, 3=cast

var _sprite: AnimatedSprite2D = null
var _hp_bar: Node2D = null
var _team_ring: Node2D = null
var _has_sprites: bool = false

# Animation names expected in SpriteFrames resource
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
const ANIM_CAST := &"cast"
const ANIM_DEATH := &"death"


func setup(sprite_frames: SpriteFrames, p_team: int, p_role: int) -> void:
	team = p_team
	role = p_role

	if sprite_frames and sprite_frames.get_animation_names().size() > 0:
		_has_sprites = true
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = sprite_frames
		_sprite.centered = true
		_sprite.flip_h = (team == 1)
		# Scale down 192px sprites to ~48px game size
		_sprite.scale = Vector2(0.25, 0.25)
		add_child(_sprite)

		if sprite_frames.has_animation(ANIM_IDLE):
			_sprite.play(ANIM_IDLE)

	# Team indicator ring (always procedural)
	_team_ring = Node2D.new()
	_team_ring.z_index = -1
	add_child(_team_ring)

	# HP bar (always procedural)
	_hp_bar = Node2D.new()
	_hp_bar.z_index = 10
	add_child(_hp_bar)


func play_attack() -> void:
	_anim_state = 2
	if _has_sprites and _sprite.sprite_frames.has_animation(ANIM_ATTACK):
		_sprite.play(ANIM_ATTACK)
		await _sprite.animation_finished
		_anim_state = 1 if _is_moving else 0
		_play_current_state()


func play_cast() -> void:
	_anim_state = 3
	if _has_sprites and _sprite.sprite_frames.has_animation(ANIM_CAST):
		_sprite.play(ANIM_CAST)
		await _sprite.animation_finished
		_anim_state = 1 if _is_moving else 0
		_play_current_state()


func set_moving(moving: bool) -> void:
	_is_moving = moving
	if _anim_state <= 1:  # Only change if idle or walking
		_anim_state = 1 if moving else 0
		_play_current_state()


func flash_hit() -> void:
	_hit_flash = 0.12
	if _has_sprites:
		_sprite.modulate = Color(2.0, 2.0, 2.0)  # Bright flash
		var tw: Tween = create_tween()
		tw.tween_property(_sprite, "modulate", Color.WHITE, 0.12)


func _play_current_state() -> void:
	if not _has_sprites:
		return
	match _anim_state:
		0:
			if _sprite.sprite_frames.has_animation(ANIM_IDLE):
				_sprite.play(ANIM_IDLE)
		1:
			if _sprite.sprite_frames.has_animation(ANIM_WALK):
				_sprite.play(ANIM_WALK)
			elif _sprite.sprite_frames.has_animation(ANIM_IDLE):
				_sprite.play(ANIM_IDLE)


func _process(delta: float) -> void:
	if _hit_flash > 0:
		_hit_flash -= delta

	# Update facing
	if _has_sprites:
		_sprite.flip_h = (facing < 0)

	_team_ring.queue_redraw()
	_hp_bar.queue_redraw()

	# Connect draw functions
	if not _team_ring.draw.is_connected(_draw_team_ring):
		_team_ring.draw.connect(_draw_team_ring)
	if not _hp_bar.draw.is_connected(_draw_hp_bar):
		_hp_bar.draw.connect(_draw_hp_bar)


func _draw_team_ring() -> void:
	var tc: Color = Color(0.25, 0.45, 0.85) if team == 0 else Color(0.82, 0.22, 0.12)
	# Oval ring under feet
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = i * TAU / 16.0
		pts.append(Vector2(cos(a) * 10, 18 + sin(a) * 3))
	_team_ring.draw_colored_polygon(pts, Color(tc.r, tc.g, tc.b, 0.25))
	_team_ring.draw_arc(Vector2(0, 18), 9.0, 0, TAU, 16, Color(tc.r, tc.g, tc.b, 0.6), 1.5)


func _draw_hp_bar() -> void:
	if hp_ratio >= 0.999:
		return
	var bar_y: float = -22.0
	var bar_w: float = 18.0
	var bar_h: float = 3.0
	_hp_bar.draw_rect(Rect2(-bar_w * 0.5 - 0.5, bar_y - 0.5, bar_w + 1, bar_h + 1), Color(0, 0, 0, 0.85))
	_hp_bar.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.08, 0.08, 0.9))
	var fw: float = bar_w * hp_ratio
	var fc: Color
	if hp_ratio > 0.6:
		fc = Color(0.15, 0.85, 0.15)
	elif hp_ratio > 0.3:
		fc = Color(0.92, 0.8, 0.08)
	else:
		fc = Color(0.92, 0.12, 0.08)
	if fw > 0:
		_hp_bar.draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h), fc)
