## Sprite-based building visual using Tiny Swords building PNGs.
## Drop-in replacement for building_visual.gd when sprites are available.
extends Node2D

var team: int = 0
var building_type: StringName = &""
var tier: int = 1
var display_name: String = ""
var width: float = 60.0
var height: float = 60.0
var hp_ratio: float = 1.0:
	set(value):
		if not is_equal_approx(hp_ratio, value):
			hp_ratio = value
			queue_redraw()

var _sprite: Sprite2D = null
var _roof_icon: Sprite2D = null

# Roof icon overlays: building_type -> {texture_name, icon_size, y_offset_ratio}
const ROOF_ICONS := {
	&"gryphon_roost": &"wing_icon",
	&"wyvern_nest": &"wing_icon",
	&"ballista_workshop": &"bolt_icon",
	&"scorpion_foundry": &"bolt_icon",
	&"royal_stable": &"horse_icon",
	&"beast_pen": &"horse_icon",
}


func setup(p_team: int, p_building_type: StringName, p_tier: int, p_name: String, p_w: float, p_h: float) -> void:
	team = p_team
	building_type = p_building_type
	tier = p_tier
	display_name = p_name
	width = p_w
	height = p_h

	var tex: Texture2D = SpriteRegistry.get_building_sprite(building_type, team)
	if tex == null:
		return

	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Scale sprite to fit building cell size with some padding
	var tex_w: float = tex.get_width()
	var tex_h: float = tex.get_height()
	var scale_x: float = (width + 8) / tex_w
	var scale_y: float = (height + 8) / tex_h
	var s: float = minf(scale_x, scale_y)
	_sprite.scale = Vector2(s, s)

	add_child(_sprite)

	# Add roof icon overlay to distinguish upgraded buildings from their base.
	# BUG-32 (2026-07-17): the old 18-26px targets rendered 3-5px on screen —
	# user-confirmed invisible. Sizes DOUBLED and a dark backing silhouette
	# (same texture, near-black, 1.12x) added behind the icon so it reads
	# against any roof color. Detector: _check_roof_icon_visibility.
	var icon_name: StringName = ROOF_ICONS.get(building_type, &"")
	if icon_name != &"":
		var icon_tex: Texture2D = SpriteRegistry.get_ui_texture(icon_name)
		if icon_tex:
			# Per-icon sizing and positioning on the roof
			var icon_px: float
			var icon_pos: Vector2
			var icon_rot: float = 0.0
			match icon_name:
				&"wing_icon":
					# Angel wings on the roof peak of Archery building
					icon_px = 44.0
					icon_pos = Vector2(0, -height * 0.30)
				&"bolt_icon":
					# Ballista bolt angled across the roof of House1 workshop
					icon_px = 52.0
					icon_pos = Vector2(2, -height * 0.26)
					icon_rot = -30.0
				&"horse_icon":
					# Horse head on the roof of Barracks
					icon_px = 36.0
					icon_pos = Vector2(0, -height * 0.33)
			var icon_s: float = icon_px / icon_tex.get_width()

			# Backing FIRST (behind): dark silhouette for contrast on busy roofs
			var backing := Sprite2D.new()
			backing.texture = icon_tex
			backing.centered = true
			backing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			backing.modulate = Color(0.04, 0.06, 0.09, 0.9)
			backing.scale = Vector2(icon_s, icon_s) * 1.12
			backing.position = icon_pos
			backing.rotation_degrees = icon_rot
			backing.z_index = 1
			add_child(backing)

			_roof_icon = Sprite2D.new()
			_roof_icon.texture = icon_tex
			_roof_icon.centered = true
			_roof_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_roof_icon.z_index = 2
			_roof_icon.scale = Vector2(icon_s, icon_s)
			_roof_icon.position = icon_pos
			_roof_icon.rotation_degrees = icon_rot
			add_child(_roof_icon)

	queue_redraw()


func flash_hit() -> void:
	if _sprite:
		_sprite.modulate = Color(2.0, 2.0, 2.0)
		var tw: Tween = create_tween()
		tw.tween_property(_sprite, "modulate", Color.WHITE, 0.12)


func _draw() -> void:
	var hw: float = width * 0.5

	# Shadow oval under building
	var shadow_pts := PackedVector2Array()
	var sw: float = (width - 4) * 0.5
	for i in 20:
		var angle: float = i * TAU / 20.0
		shadow_pts.append(Vector2(cos(angle) * sw, height * 0.5 + sin(angle) * 3))
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.18))

	# HP bar (always visible above building)
	var bar_w: float = width * 0.8
	var bar_h: float = 4.0
	var bar_x: float = -bar_w * 0.5
	var bar_y: float = -height * 0.5 - 8.0

	# Background frame
	draw_rect(Rect2(bar_x - 1, bar_y - 1, bar_w + 2, bar_h + 2), Color(0, 0, 0, 0.55))
	# Track
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.1, 0.05, 0.7))
	# Fill (green -> yellow -> red)
	var fill_col: Color
	if hp_ratio > 0.6:
		fill_col = Color(0.2, 0.8, 0.25, 1)
	elif hp_ratio > 0.3:
		fill_col = Color(0.9, 0.8, 0.15, 1)
	else:
		fill_col = Color(0.9, 0.2, 0.1, 1)
	draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h), fill_col)

	# Tier stars
	if tier > 1:
		var star_y: float = -height * 0.5 - 14.0
		var accent := Color(0.85, 0.75, 0.3) if team == 0 else Color(0.85, 0.55, 0.2)
		for i in tier:
			var star_x: float = -((tier - 1) * 6.0) * 0.5 + i * 6.0
			draw_circle(Vector2(star_x, star_y + 1), 2.8, Color(0, 0, 0, 0.5))
			draw_circle(Vector2(star_x, star_y), 2.8, accent)
			draw_circle(Vector2(star_x, star_y - 0.5), 1.3, Color(1, 1, 1, 0.35))
