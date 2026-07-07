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
var _walk_phase: float = 0.0  # T-058: walk bounce phase

# BUG-40 (2026-04-18): walk playback speed relative to the footman baseline
# (2 cells/sec = 1.0). Keeps leg-cycle ÷ ground-travel at ~1.1 body widths
# regardless of unit speed — fast units (knight/gryphon at 3 cells/sec = 1.5)
# get smoother legs, slow units (priest at 1 cells/sec = 0.5) get a deliberate
# gait, and none of them skate or run-in-place.
var _walk_speed_ratio: float = 1.0

var _sprite: AnimatedSprite2D = null
var _pawn_overlay: AnimatedSprite2D = null  # Operator overlay for ballista/scorpion
var _hp_bar: Node2D = null
var _team_ring: Node2D = null
var _has_sprites: bool = false

# T-059: Hit-stop
var _hitstop_timer: float = 0.0
const HITSTOP_DURATION: float = 0.033  # 2 frames at 60fps

# T-059: Smooth direction changes
var _turn_tween: Tween = null
var _base_scale_x: float = 0.30  # Matches _sprite.scale.x from setup

# Per-animation scaling: keeps units at consistent size across animations
# (some sprite packs draw the character at different scales per animation)
var _anim_scales: Dictionary = {}  # StringName -> float

# T-078: Per-unit BODY-height override. For units whose bbox includes a weapon
# or mount silhouette that shouldn't factor into body-size calibration
# (e.g. a lancer's vertical spear doubles the bbox), set this to the
# pure-body pixel height within the source frame. The auto-scale then
# sizes the BODY to target_content instead of the full silhouette.
const BODY_H_OVERRIDE: Dictionary = {
	# Spear-inflated units (bbox includes raised weapon).
	# Tiny Swords lancer: body rows 123-197 = 75 tall, spear above = another 75.
	&"knight": 75.0,
	&"berserker": 75.0,
	# Mounted lancer composites still use the native lancer sprite,
	# so the lancer body within the composite is still 75 native px.
	&"royal_knight": 75.0,
	&"war_rider": 75.0,
	# T-078 ADDENDUM: Short-stocky units (bbox has no raised weapon).
	# Without this, auto-scale fills target_content with the entire body,
	# making monk/pawn bodies ~23% chunkier than footman (whose sword eats
	# 17 px at the top of its bbox). Using 89 (footman's natural bbox) as
	# reference keeps everyone at the same body size.
	&"priest": 89.0,
	&"wardrummer": 89.0,  # red_monk — same source sprite as priest
	&"pawn": 89.0,        # small hammer barely inflates bbox — keep consistent
}

# Animation names expected in SpriteFrames resource
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
const ANIM_CAST := &"cast"
const ANIM_DEATH := &"death"


func setup(sprite_frames: SpriteFrames, p_team: int, p_role: int, p_unit_type: StringName = &"") -> void:
	team = p_team
	role = p_role
	unit_type = p_unit_type

	if sprite_frames and sprite_frames.get_animation_names().size() > 0:
		_has_sprites = true
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = sprite_frames
		_sprite.centered = true
		_sprite.flip_h = (team == 1)
		# Auto-scale based on idle animation's first frame content height.
		# This matches the original Tiny Swords character proportions.
		var ref_anim: StringName = &"idle" if sprite_frames.has_animation(&"idle") else sprite_frames.get_animation_names()[0]
		var frame_tex: Texture2D = sprite_frames.get_frame_texture(ref_anim, 0)
		var content_h: float = frame_tex.get_height() if frame_tex else 192.0
		if frame_tex:
			var img: Image = frame_tex.get_image()
			if img and not img.is_empty():
				var used: Rect2i = img.get_used_rect()
				if used.size.y > 0:
					content_h = float(used.size.y)
		# T-078: Body-height override — skip the full-bbox measurement for units
		# with weapons that inflate the silhouette (lancer spear doubles bbox).
		var body_override: float = BODY_H_OVERRIDE.get(p_unit_type, -1.0)
		if body_override > 0.0:
			content_h = body_override
		# Scale so content fills target height.
		# Composite units (mounts, vehicles) need larger targets so the
		# character portion stays the same size as standalone units.
		# Each composite's target is calibrated so the RIDER renders at ~30px,
		# matching standalone footman/archer size.
		var target_content: float = 30.0
		match p_unit_type:
			&"gryphon_rider", &"wyvern_rider":
				target_content = 54.0   # archer is ~55% of 159px composite
			# T-078: REMOVED royal_knight/war_rider — now use body_h override
			#        + default target_content=30 for body-size parity.
			&"catapult", &"demolisher":
				# T-084: User wants catapult 1.2× smaller. 49/1.2 = 40.8 ≈ 41.
				# Pawn portion of composite (71 px) now renders at 71×0.345 = 24.5 px,
				# matching standalone pawn size after T-078 addendum.
				target_content = 41.0
			&"ballista_unit", &"scorpion":
				target_content = 36.0   # pawn is ~82% of 85px composite
		var auto_scale: float = target_content / maxf(content_h, 1.0)
		_sprite.scale = Vector2(auto_scale, auto_scale)
		_base_scale_x = auto_scale
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Pixel art crisp
		add_child(_sprite)

		# BUG-SPRITE2/5 FIX: Lock scale to idle animation's content height for ALL
		# animations. Previously each animation got its own scale based on its
		# content height, causing body size to pop when weapons change orientation
		# (e.g. Lancer idle=tall vertical spear vs attack=short horizontal thrust).
		# Now all animations use the same scale derived from the idle reference.
		for anim_name in sprite_frames.get_animation_names():
			_anim_scales[anim_name] = auto_scale

		if sprite_frames.has_animation(ANIM_IDLE):
			_sprite.play(ANIM_IDLE)

		# Ballista/Scorpion: add a clean Pawn overlay on top to cover erasure artifacts.
		# The composite sprite has the peon poorly erased behind the machine.
		# Rendering a clean pawn ON TOP naturally hides those artifacts.
		if p_unit_type in [&"ballista_unit", &"scorpion"]:
			var pawn_sf: SpriteFrames = SpriteRegistry.get_pawn_sprites(p_team)
			if pawn_sf:
				_pawn_overlay = AnimatedSprite2D.new()
				_pawn_overlay.sprite_frames = pawn_sf
				_pawn_overlay.centered = true
				_pawn_overlay.flip_h = (team == 1)
				_pawn_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# T-084: Compute pawn-specific scale instead of inheriting the
				# ballista's auto_scale. The ballista has a wider machine bbox so
				# its auto_scale produces a fat pawn overlay (~32 px) — bigger
				# than a standalone pawn. Use the pawn body height directly so
				# the overlay matches standalone pawn rendering.
				# With BODY_H_OVERRIDE[&"pawn"] = 89 (T-078 addendum), this gives
				# 30/89 ≈ 0.337, matching standalone pawn render size.
				var pawn_body_h: float = BODY_H_OVERRIDE.get(&"pawn", 71.0)
				var pawn_scale: float = 30.0 / pawn_body_h
				_pawn_overlay.scale = Vector2(pawn_scale, pawn_scale)
				# Position pawn slightly behind and on the machine
				_pawn_overlay.position = Vector2(-4.0 if team == 0 else 4.0, 3.0)
				_pawn_overlay.z_index = 1  # On top of machine sprite (z=0)
				add_child(_pawn_overlay)
				if pawn_sf.has_animation(&"idle"):
					_pawn_overlay.play(&"idle")

	# Team indicator ring (always procedural)
	_team_ring = Node2D.new()
	_team_ring.z_index = -1
	add_child(_team_ring)

	# HP bar (always procedural)
	_hp_bar = Node2D.new()
	_hp_bar.z_index = 10
	add_child(_hp_bar)


func trigger_hitstop() -> void:
	_hitstop_timer = HITSTOP_DURATION
	# T-059 fix: actually freeze the animation frame. Previously the timer was
	# set but nothing paused the sprite, so hit-stop was a no-op. Position is
	# frozen in parallel by game_arena._sync_unit_positions (is_in_hitstop guard).
	if _has_sprites and _sprite:
		_sprite.speed_scale = 0.0


func is_in_hitstop() -> bool:
	return _hitstop_timer > 0.0


## Play attack animation with timing contrast (slow wind-up, fast strike, medium recovery).
func play_attack(target_pos: Vector2 = Vector2.ZERO) -> void:
	if not _has_sprites:
		return
	# Pick directional attack animation if available
	var anim_name: StringName = ANIM_ATTACK
	if target_pos != Vector2.ZERO:
		var dy: float = target_pos.y - global_position.y
		if dy < -20 and _sprite.sprite_frames.has_animation(&"attack_up"):
			anim_name = &"attack_up"
		elif dy > 20 and _sprite.sprite_frames.has_animation(&"attack_down"):
			anim_name = &"attack_down"
	if _sprite.sprite_frames.has_animation(anim_name):
		_anim_state = 2
		_apply_anim_scale(anim_name)
		var frame_count: int = _sprite.sprite_frames.get_frame_count(anim_name)
		# T-059: Attack timing contrast — wind-up slow, strike fast, recovery medium
		if frame_count >= 3:
			var windup_frames: int = ceili(frame_count * 0.4)
			var strike_frames: int = maxi(1, ceili(frame_count * 0.2))
			# Wind-up: slow (0.6x speed)
			_sprite.speed_scale = 0.6
			_sprite.play(anim_name)
			# Wait for wind-up frames
			for i in windup_frames:
				await _sprite.frame_changed
				if not is_inside_tree():
					return
			# Strike: fast (2.0x speed)
			_sprite.speed_scale = 2.0
			for i in strike_frames:
				await _sprite.frame_changed
				if not is_inside_tree():
					return
			# Recovery: medium (0.8x speed)
			_sprite.speed_scale = 0.8
			await _sprite.animation_finished
		else:
			_sprite.speed_scale = 1.0
			_sprite.play(anim_name)
			await _sprite.animation_finished
		if not is_inside_tree():
			return
		_sprite.speed_scale = 1.0
		_anim_state = 1 if _is_moving else 0
		_play_current_state()


func play_cast() -> void:
	if _has_sprites and _sprite.sprite_frames.has_animation(ANIM_CAST):
		_anim_state = 3
		_sprite.play(ANIM_CAST)
		await _sprite.animation_finished
		if not is_inside_tree():
			return  # Visual was freed during animation
		_anim_state = 1 if _is_moving else 0
		_play_current_state()
	# If no cast animation, don't change _anim_state — let walk/idle continue


func set_moving(moving: bool) -> void:
	if _is_moving == moving:
		return  # No change — don't restart animation
	_is_moving = moving
	if _anim_state <= 1:  # Only change if idle or walking
		_anim_state = 1 if moving else 0
		_play_current_state()


## BUG-40: call per-frame with the unit's cells/sec speed relative to the
## footman baseline (2 cells/sec = 1.0). Only affects walk playback; idle
## and attack keep their own timing.
func set_walk_speed_ratio(ratio: float) -> void:
	if is_equal_approx(_walk_speed_ratio, ratio):
		return
	_walk_speed_ratio = ratio
	# Don't touch speed_scale during hit-stop — it's frozen at 0 and resumes to
	# the stored ratio when the stop ends (else game_arena's per-frame call here
	# would immediately un-freeze the sprite).
	if _hitstop_timer > 0.0:
		return
	if _anim_state == 1 and _has_sprites and _sprite:
		_sprite.speed_scale = _walk_speed_ratio


func flash_hit() -> void:
	_hit_flash = 0.12
	if _has_sprites:
		_sprite.modulate = Color(2.0, 2.0, 2.0)  # Bright flash
		var tw: Tween = create_tween()
		tw.tween_property(_sprite, "modulate", Color.WHITE, 0.12)


func _apply_anim_scale(anim_name: StringName) -> void:
	if _anim_scales.has(anim_name):
		var s: float = _anim_scales[anim_name]
		_sprite.scale = Vector2(s, s)
		_base_scale_x = s


func _play_current_state() -> void:
	if not _has_sprites:
		return
	match _anim_state:
		0:
			if _sprite.sprite_frames.has_animation(ANIM_IDLE):
				_sprite.play(ANIM_IDLE)
				_apply_anim_scale(ANIM_IDLE)
				_sprite.speed_scale = 1.0  # Idle plays at data fps
			if _pawn_overlay and _pawn_overlay.sprite_frames.has_animation(&"idle"):
				_pawn_overlay.play(&"idle")
				_pawn_overlay.speed_scale = 1.0
		1:
			if _sprite.sprite_frames.has_animation(ANIM_WALK):
				_sprite.play(ANIM_WALK)
				_apply_anim_scale(ANIM_WALK)
				# BUG-40: scale walk playback by unit speed to match ground travel
				_sprite.speed_scale = _walk_speed_ratio
			elif _sprite.sprite_frames.has_animation(ANIM_IDLE):
				_sprite.play(ANIM_IDLE)
				_apply_anim_scale(ANIM_IDLE)
				_sprite.speed_scale = 1.0
			if _pawn_overlay and _pawn_overlay.sprite_frames.has_animation(&"walk"):
				_pawn_overlay.play(&"walk")
				_pawn_overlay.speed_scale = _walk_speed_ratio


var _prev_facing: float = 1.0
var _prev_hp: float = 1.0
var _signals_connected: bool = false

# BUG-40 round 2: distance-driven walk bounce. Track last position so we can
# advance _walk_phase by pixels traveled instead of wall-clock time. Makes the
# body bob pulse at footfall rhythm even under hit-stop / accel / decel.
var _last_bounce_pos: Vector2 = Vector2.ZERO
var _bounce_pos_initialized: bool = false
const _GROUND_STRIDE_PX: float = 35.0  # pixels traveled per sin cycle (~1 body width)
const _FLYING_STRIDE_PX: float = 60.0  # longer "glide" for flying bob

func _process(delta: float) -> void:
	# T-059: Hit-stop — freeze all animation updates + the sprite frame.
	if _hitstop_timer > 0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0 and _has_sprites and _sprite:
			# Resume: walk cadence if walking, else normal speed.
			_sprite.speed_scale = _walk_speed_ratio if _anim_state == 1 else 1.0
		return  # Skip ALL animation updates — freeze in place

	if _hit_flash > 0:
		_hit_flash -= delta

	# T-058 + BUG-40 round 2: walk bounce driven by distance traveled, not
	# wall-clock time. Each sin cycle = one _GROUND_STRIDE_PX of ground travel,
	# so feet pulse at real footfall rhythm even across accel/decel/hit-stop.
	if _anim_state == 1 and _sprite:  # Walking
		var moved: float = 0.0
		if _bounce_pos_initialized:
			moved = (position - _last_bounce_pos).length()
			# Clamp to prevent teleport spikes (respawn, zone clamp) from
			# producing a giant phase jump.
			moved = minf(moved, 3.0)
		_last_bounce_pos = position
		_bounce_pos_initialized = true

		if role == 3:  # Flying — longer glide stride + wing flap
			_walk_phase += moved / _FLYING_STRIDE_PX
			_sprite.offset.y = sin(_walk_phase * TAU) * 5.0
			# Subtle scale.y oscillation to simulate wing flap (2× bounce freq)
			var flap: float = 1.0 + sin(_walk_phase * TAU * 2.0) * 0.06
			_sprite.scale.y = _base_scale_x * flap
		else:
			_walk_phase += moved / _GROUND_STRIDE_PX
			_sprite.offset.y = sin(_walk_phase * TAU) * 2.0
	elif _sprite:
		_sprite.offset.y = 0.0
		if role == 3:
			_sprite.scale.y = _base_scale_x

	# T-059: Smooth direction changes — squash-turn instead of instant flip
	if _has_sprites and facing != _prev_facing:
		_prev_facing = facing
		if _turn_tween and _turn_tween.is_valid():
			_turn_tween.kill()
		_turn_tween = create_tween()
		# Squash to 0 width, flip, expand back
		_turn_tween.tween_property(_sprite, "scale:x", 0.0, 0.05)
		_turn_tween.tween_callback(func():
			_sprite.flip_h = (facing < 0)
			if _pawn_overlay:
				_pawn_overlay.flip_h = (facing < 0)
				_pawn_overlay.position.x = -4.0 if facing > 0 else 4.0
		)
		_turn_tween.tween_property(_sprite, "scale:x", _base_scale_x, 0.05)

	# Connect draw signals once
	if not _signals_connected:
		_team_ring.draw.connect(_draw_team_ring)
		_hp_bar.draw.connect(_draw_hp_bar)
		_signals_connected = true
		_team_ring.queue_redraw()

	# Only redraw HP bar when HP changes
	if hp_ratio != _prev_hp:
		_prev_hp = hp_ratio
		_hp_bar.queue_redraw()


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
	var bar_h: float = 5.0
	# T-007: Use sprite HP bar if available
	var bar_base: Texture2D = SpriteRegistry.get_ui_texture(&"SmallBar_Base")
	var bar_fill: Texture2D = SpriteRegistry.get_ui_texture(&"SmallBar_Fill")
	if bar_base:
		_hp_bar.draw_texture_rect(bar_base, Rect2(-bar_w * 0.5 - 1, bar_y - 1, bar_w + 2, bar_h + 2), false)
	else:
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
		if bar_fill:
			_hp_bar.draw_texture_rect(bar_fill, Rect2(-bar_w * 0.5, bar_y, fw, bar_h), false, fc)
		else:
			_hp_bar.draw_rect(Rect2(-bar_w * 0.5, bar_y, fw, bar_h), fc)
