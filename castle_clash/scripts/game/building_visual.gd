## Chibi building visual drawn with _draw(). Different shapes per building type.
extends Node2D

var team: int = 0
var building_type: StringName = &""
var tier: int = 1
var display_name: String = ""
var width: float = 60.0
var height: float = 60.0

# Building shape types
const SHAPE_FORT := 0      # Barracks / War Camp
const SHAPE_TOWER := 1     # Archer Range / Axe Range
const SHAPE_TEMPLE := 2    # Priest Temple / War Drums
const SHAPE_CASTLE := 3    # Knight Hall / Berserker Pit
const SHAPE_WORKSHOP := 4  # Siege Workshop / Demolisher Works

var _shape: int = SHAPE_FORT

# Team palettes
const PALETTE := {
	0: {  # Kingdom
		"wall": Color(0.55, 0.6, 0.75),
		"wall_light": Color(0.65, 0.7, 0.82),
		"roof": Color(0.2, 0.35, 0.7),
		"roof_dark": Color(0.15, 0.25, 0.55),
		"wood": Color(0.5, 0.35, 0.2),
		"accent": Color(0.85, 0.75, 0.3),
		"window": Color(0.9, 0.85, 0.5, 0.7),
		"door": Color(0.4, 0.28, 0.15),
	},
	1: {  # Horde
		"wall": Color(0.6, 0.5, 0.4),
		"wall_light": Color(0.7, 0.6, 0.48),
		"roof": Color(0.7, 0.18, 0.12),
		"roof_dark": Color(0.5, 0.12, 0.08),
		"wood": Color(0.45, 0.3, 0.18),
		"accent": Color(0.85, 0.55, 0.2),
		"window": Color(0.9, 0.5, 0.2, 0.6),
		"door": Color(0.35, 0.22, 0.12),
	}
}

# Map building types to shapes
const TYPE_TO_SHAPE := {
	&"barracks": SHAPE_FORT,
	&"war_camp": SHAPE_FORT,
	&"archer_range": SHAPE_TOWER,
	&"axe_range": SHAPE_TOWER,
	&"priest_temple": SHAPE_TEMPLE,
	&"war_drums": SHAPE_TEMPLE,
	&"knight_hall": SHAPE_CASTLE,
	&"berserker_pit": SHAPE_CASTLE,
	&"siege_workshop": SHAPE_WORKSHOP,
	&"demolisher_works": SHAPE_WORKSHOP,
}


func setup(p_team: int, p_building_type: StringName, p_tier: int, p_name: String, p_w: float, p_h: float) -> void:
	team = p_team
	building_type = p_building_type
	tier = p_tier
	display_name = p_name
	width = p_w
	height = p_h
	_shape = TYPE_TO_SHAPE.get(building_type, SHAPE_FORT)
	queue_redraw()


func _draw() -> void:
	var p: Dictionary = PALETTE.get(team, PALETTE[0])
	var hw: float = width * 0.5
	var hh: float = height * 0.5

	# Shadow
	draw_ellipse(Rect2(-hw + 2, hh - 4, width - 4, 8), Color(0, 0, 0, 0.12))

	match _shape:
		SHAPE_FORT:
			_draw_fort(p, hw, hh)
		SHAPE_TOWER:
			_draw_tower(p, hw, hh)
		SHAPE_TEMPLE:
			_draw_temple(p, hw, hh)
		SHAPE_CASTLE:
			_draw_castle(p, hw, hh)
		SHAPE_WORKSHOP:
			_draw_workshop(p, hw, hh)

	# Tier stars
	if tier > 1:
		for i in tier:
			var star_x: float = -((tier - 1) * 5.0) * 0.5 + i * 5.0
			draw_circle(Vector2(star_x, -hh + 3), 2.0, p.accent)

	# Name label below
	# (Drawn by game_arena as a Label node for text rendering)


func _draw_fort(p: Dictionary, hw: float, hh: float) -> void:
	# Main walls
	draw_rect(Rect2(-hw + 4, -hh + 16, width - 8, hh + hh - 20), p.wall)

	# Battlements (top crenellations)
	for i in 4:
		var bx: float = -hw + 6 + i * (width - 12) / 4.0
		draw_rect(Rect2(bx, -hh + 10, 8, 8), p.wall)
	draw_rect(Rect2(-hw + 4, -hh + 14, width - 8, 4), p.wall_light)

	# Door
	draw_rect(Rect2(-5, hh - 18, 10, 14), p.door)
	draw_rect(Rect2(-4, hh - 17, 8, 13), p.door.lightened(0.15))
	draw_circle(Vector2(2, hh - 10), 1.2, p.accent)  # Door handle

	# Windows
	draw_rect(Rect2(-hw + 8, -hh + 22, 6, 6), p.window)
	draw_rect(Rect2(hw - 14, -hh + 22, 6, 6), p.window)

	# Banner
	var banner_pts := PackedVector2Array([
		Vector2(hw - 8, -hh + 2),
		Vector2(hw - 2, -hh + 2),
		Vector2(hw - 5, -hh + 12),
	])
	draw_colored_polygon(banner_pts, p.roof)
	draw_rect(Rect2(hw - 6, -hh - 2, 2, 16), p.wood)


func _draw_tower(p: Dictionary, hw: float, hh: float) -> void:
	# Narrow tower body
	var tw: float = width * 0.55
	draw_rect(Rect2(-tw * 0.5, -hh + 18, tw, hh + hh - 22), p.wall)

	# Wider base
	draw_rect(Rect2(-hw + 6, hh - 10, width - 12, 10), p.wall_light)

	# Pointed roof
	var roof_pts := PackedVector2Array([
		Vector2(-tw * 0.5 - 3, -hh + 18),
		Vector2(0, -hh + 2),
		Vector2(tw * 0.5 + 3, -hh + 18),
	])
	draw_colored_polygon(roof_pts, p.roof)

	# Roof edge
	draw_line(Vector2(-tw * 0.5 - 3, -hh + 18), Vector2(0, -hh + 2), p.roof_dark, 1.5)
	draw_line(Vector2(tw * 0.5 + 3, -hh + 18), Vector2(0, -hh + 2), p.roof_dark, 1.5)

	# Window (arched)
	draw_rect(Rect2(-3, -hh + 22, 6, 8), p.window)
	draw_arc(Vector2(0, -hh + 22), 3, PI, 0, 6, p.window, 3)

	# Arrow slits
	draw_rect(Rect2(-tw * 0.5 + 3, -hh + 26, 2, 6), p.door)
	draw_rect(Rect2(tw * 0.5 - 5, -hh + 26, 2, 6), p.door)


func _draw_temple(p: Dictionary, hw: float, hh: float) -> void:
	# Temple body
	draw_rect(Rect2(-hw + 6, -hh + 20, width - 12, hh + hh - 24), p.wall)

	# Dome roof
	draw_arc(Vector2(0, -hh + 20), hw - 6, PI, 0, 16, p.roof, (hw - 6))
	draw_arc(Vector2(0, -hh + 20), hw - 6, PI, 0, 16, p.roof_dark, 1.5)

	# Cross / totem on top
	draw_rect(Rect2(-1.5, -hh + 2, 3, 12), p.accent)
	draw_rect(Rect2(-4, -hh + 6, 8, 3), p.accent)

	# Columns
	draw_rect(Rect2(-hw + 8, -hh + 20, 4, hh + hh - 24), p.wall_light)
	draw_rect(Rect2(hw - 12, -hh + 20, 4, hh + hh - 24), p.wall_light)

	# Door (arched)
	draw_rect(Rect2(-5, hh - 16, 10, 12), p.door)
	draw_arc(Vector2(0, hh - 16), 5, PI, 0, 8, p.door.lightened(0.1), 5)

	# Glowing window
	draw_circle(Vector2(0, -hh + 28), 4, p.window)


func _draw_castle(p: Dictionary, hw: float, hh: float) -> void:
	# Main keep
	draw_rect(Rect2(-hw + 4, -hh + 14, width - 8, hh + hh - 18), p.wall)

	# Two towers on sides
	draw_rect(Rect2(-hw + 2, -hh + 6, 12, hh + hh - 10), p.wall_light)
	draw_rect(Rect2(hw - 14, -hh + 6, 12, hh + hh - 10), p.wall_light)

	# Tower roofs
	var lt_pts := PackedVector2Array([
		Vector2(-hw + 1, -hh + 6),
		Vector2(-hw + 8, -hh - 4),
		Vector2(-hw + 15, -hh + 6),
	])
	draw_colored_polygon(lt_pts, p.roof)
	var rt_pts := PackedVector2Array([
		Vector2(hw - 15, -hh + 6),
		Vector2(hw - 8, -hh - 4),
		Vector2(hw - 1, -hh + 6),
	])
	draw_colored_polygon(rt_pts, p.roof)

	# Center battlement
	for i in 3:
		var bx: float = -8 + i * 8
		draw_rect(Rect2(bx, -hh + 10, 5, 6), p.wall)

	# Gate
	draw_rect(Rect2(-6, hh - 18, 12, 14), p.door)
	draw_arc(Vector2(0, hh - 18), 6, PI, 0, 8, p.door.lightened(0.1), 6)
	# Portcullis lines
	for i in 3:
		var lx: float = -4 + i * 4
		draw_line(Vector2(lx, hh - 18), Vector2(lx, hh - 4), Color(0.3, 0.3, 0.3, 0.5), 0.8)

	# Windows
	draw_rect(Rect2(-hw + 5, -hh + 14, 4, 5), p.window)
	draw_rect(Rect2(hw - 9, -hh + 14, 4, 5), p.window)

	# Banner
	var banner := PackedVector2Array([
		Vector2(0, -hh + 14), Vector2(6, -hh + 18), Vector2(0, -hh + 22),
	])
	draw_colored_polygon(banner, p.accent)


func _draw_workshop(p: Dictionary, hw: float, hh: float) -> void:
	# Open shed structure
	draw_rect(Rect2(-hw + 4, -hh + 20, width - 8, hh + hh - 24), p.wall)

	# Slanted roof
	var roof_pts := PackedVector2Array([
		Vector2(-hw + 2, -hh + 20),
		Vector2(-hw + 10, -hh + 8),
		Vector2(hw - 2, -hh + 8),
		Vector2(hw - 2, -hh + 20),
	])
	draw_colored_polygon(roof_pts, p.roof)
	draw_line(Vector2(-hw + 2, -hh + 20), Vector2(-hw + 10, -hh + 8), p.roof_dark, 1.5)

	# Support beams
	draw_rect(Rect2(-hw + 6, -hh + 20, 3, hh + hh - 24), p.wood)
	draw_rect(Rect2(hw - 9, -hh + 20, 3, hh + hh - 24), p.wood)

	# Anvil / workbench
	draw_rect(Rect2(-6, hh - 14, 12, 5), Color(0.4, 0.4, 0.4))
	draw_rect(Rect2(-8, hh - 10, 16, 3), Color(0.35, 0.35, 0.35))

	# Wheel leaning on wall
	draw_arc(Vector2(hw - 14, hh - 12), 5, 0, TAU, 12, p.wood, 2.0)
	draw_line(Vector2(hw - 14, hh - 17), Vector2(hw - 14, hh - 7), p.wood, 1.0)
	draw_line(Vector2(hw - 19, hh - 12), Vector2(hw - 9, hh - 12), p.wood, 1.0)

	# Chimney / smoke
	draw_rect(Rect2(hw - 10, -hh + 4, 5, 6), p.wall_light)
