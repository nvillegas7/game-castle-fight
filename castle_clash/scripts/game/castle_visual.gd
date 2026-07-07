## Castle visual using Tiny Swords Castle.png sprite with damage states.
extends Node2D

@export var team: int = 0
var hp_ratio: float = 1.0

var _sprite: Sprite2D = null
var _prev_hp: float = 1.0
var _fire_nodes: Array[Node2D] = []
var _glow_color: Color = Color.TRANSPARENT

# T-008: HP bars handled by game_arena.gd (.tscn ColorRects + BigBar overlay)
# castle_visual.gd only handles sprite, damage tint, fire, and glow


func _ready() -> void:
	# Team-colored glow base behind castle
	var glow_color: Color = Color(0.2, 0.4, 0.8, 0.15) if team == 0 else Color(0.8, 0.2, 0.1, 0.15)
	queue_redraw()
	_glow_color = glow_color

	var tex: Texture2D = SpriteRegistry.get_castle_sprite(team)
	if tex:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var s: float = 160.0 / tex.get_height()
		_sprite.scale = Vector2(s, s)
		add_child(_sprite)


func _process(_delta: float) -> void:
	if abs(hp_ratio - _prev_hp) < 0.001:
		return
	_prev_hp = hp_ratio
	queue_redraw()

	# Damage tint on sprite
	if _sprite:
		if hp_ratio < 0.5:
			var dmg: float = (0.5 - hp_ratio) * 1.0
			_sprite.modulate = Color(1.0, 1.0 - dmg, 1.0 - dmg)
		else:
			_sprite.modulate = Color.WHITE

	# Sprite-based fire at low HP
	if hp_ratio < 0.5 and _fire_nodes.is_empty():
		# Add fire sprites
		var fire1 := Effects.create_fire(Vector2(-20, -5), 0.45)
		var fire2 := Effects.create_fire(Vector2(18, -8), 0.4)
		add_child(fire1)
		add_child(fire2)
		_fire_nodes.append(fire1)
		_fire_nodes.append(fire2)
		# Add third fire at very low HP
		if hp_ratio < 0.25:
			var fire3 := Effects.create_fire(Vector2(0, 0), 0.55)
			add_child(fire3)
			_fire_nodes.append(fire3)
	elif hp_ratio < 0.25 and _fire_nodes.size() < 3:
		var fire3 := Effects.create_fire(Vector2(0, 0), 0.55)
		add_child(fire3)
		_fire_nodes.append(fire3)
	elif hp_ratio >= 0.5 and not _fire_nodes.is_empty():
		# Remove fire when healed above threshold
		for f in _fire_nodes:
			f.queue_free()
		_fire_nodes.clear()


func _draw() -> void:
	if _glow_color.a > 0:
		# Soft radial glow behind castle
		for i in range(3, 0, -1):
			var r: float = 50.0 + i * 20.0
			var c := Color(_glow_color.r, _glow_color.g, _glow_color.b, _glow_color.a * (0.4 / i))
			draw_circle(Vector2.ZERO, r, c)

	# HP bar at castle top — same style as building_visual (no gaps)
	var bar_w: float = 120.0
	var bar_h: float = 6.0
	var bar_x: float = -bar_w * 0.5
	var bar_y: float = -56.0 - 4.0  # sprite half-height (56) + 4px gap, same as buildings
	draw_rect(Rect2(bar_x - 1, bar_y - 1, bar_w + 2, bar_h + 2), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.1, 0.05, 0.7))
	var fill_col: Color
	if hp_ratio > 0.6:
		fill_col = Color(0.2, 0.8, 0.25) if team == 0 else Color(0.9, 0.2, 0.1)
	elif hp_ratio > 0.3:
		fill_col = Color(0.9, 0.8, 0.15)
	else:
		fill_col = Color(0.9, 0.2, 0.1)
	draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h), fill_col)
