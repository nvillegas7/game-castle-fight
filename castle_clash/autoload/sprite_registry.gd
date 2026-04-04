## Sprite registry: maps unit/building types to SpriteFrames resources.
## When real sprite sheets are available, place them in assets/sprites/
## and register them here. Falls back to procedural _draw() visuals.
##
## To add sprites for a unit:
## 1. Create a SpriteFrames resource (.tres) with animations: idle, walk, attack, cast, death
## 2. Place sprite sheet PNGs in assets/sprites/units/
## 3. Register in _load_sprites() below
##
## Expected sprite sheet format:
##   - 48x48px per frame (or 32x32 for small units)
##   - Horizontal strip: all frames in a row
##   - Animations: idle (3-4 frames), walk (4-6), attack (3-5), death (3-4)
##   - Facing RIGHT by default (flip_h for left)
extends Node

var unit_sprites: Dictionary = {}      # unit_type StringName -> SpriteFrames
var building_sprites: Dictionary = {}  # building_type StringName -> Texture2D
var has_sprite_mode: bool = false      # True if any sprites are loaded


func _ready() -> void:
	_load_sprites()


func _load_sprites() -> void:
	# Check if sprite assets directory exists
	var dir := DirAccess.open("res://assets/sprites/units/")
	if dir == null:
		return

	# Auto-scan for .tres SpriteFrames resources
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load("res://assets/sprites/units/" + file_name)
			if res is SpriteFrames:
				var unit_name := StringName(file_name.get_basename())
				unit_sprites[unit_name] = res
				has_sprite_mode = true
		file_name = dir.get_next()

	# Auto-scan building sprites
	var bdir := DirAccess.open("res://assets/sprites/buildings/")
	if bdir:
		bdir.list_dir_begin()
		file_name = bdir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") or file_name.ends_with(".svg"):
				var tex = load("res://assets/sprites/buildings/" + file_name)
				if tex is Texture2D:
					var bld_name := StringName(file_name.get_basename())
					building_sprites[bld_name] = tex
			file_name = bdir.get_next()


## Get SpriteFrames for a unit type, or null if not available.
func get_unit_sprites(unit_type: StringName) -> SpriteFrames:
	return unit_sprites.get(unit_type)


## Get building texture, or null if not available.
func get_building_sprite(building_type: StringName) -> Texture2D:
	return building_sprites.get(building_type)
