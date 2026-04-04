## Sprite registry: auto-loads Tiny Swords sprite strips and creates SpriteFrames.
## Maps unit types to SpriteFrames with animations.
extends Node

var unit_sprites: Dictionary = {}      # unit_type StringName -> SpriteFrames
var building_textures: Dictionary = {} # building_type StringName -> Texture2D
var has_sprite_mode: bool = false

# Map our unit types to Tiny Swords folder/file names
const UNIT_MAP := {
	# Kingdom (Blue)
	&"footman": {"folder": "blue_warrior", "prefix": "Warrior"},
	&"archer": {"folder": "blue_archer", "prefix": "Archer"},
	&"priest": {"folder": "blue_monk", "prefix": "Monk"},
	&"knight": {"folder": "blue_lancer", "prefix": "Lancer"},
	&"catapult": {"folder": "blue_pawn", "prefix": "Pawn"},
	# Horde (Red)
	&"grunt": {"folder": "red_warrior", "prefix": "Warrior"},
	&"axe_thrower": {"folder": "red_archer", "prefix": "Archer"},
	&"wardrummer": {"folder": "red_monk", "prefix": "Monk"},
	&"berserker": {"folder": "red_lancer", "prefix": "Lancer"},
	&"demolisher": {"folder": "red_pawn", "prefix": "Pawn"},
}

# Map Tiny Swords animation files to our animation names
# Format: TS_suffix -> {our_name, fps, loop}
const ANIM_MAP := {
	"_Idle": {"name": "idle", "fps": 6, "loop": true},
	"_Run": {"name": "walk", "fps": 8, "loop": true},
	"_Attack1": {"name": "attack", "fps": 10, "loop": false},
	"_Attack2": {"name": "cast", "fps": 10, "loop": false},
	"_Guard": {"name": "death", "fps": 6, "loop": false},
}


func _ready() -> void:
	_load_unit_sprites()
	_load_building_textures()


func _load_unit_sprites() -> void:
	var base_path := "res://assets/sprites/units/"

	for unit_type in UNIT_MAP:
		var info: Dictionary = UNIT_MAP[unit_type]
		var folder: String = info.folder
		var prefix: String = info.prefix
		var folder_path: String = base_path + folder + "/"

		var dir := DirAccess.open(folder_path)
		if dir == null:
			continue

		var sf := SpriteFrames.new()
		# Remove default animation
		if sf.has_animation(&"default"):
			sf.remove_animation(&"default")

		var found_any: bool = false

		for ts_suffix in ANIM_MAP:
			var anim_info: Dictionary = ANIM_MAP[ts_suffix]
			var file_name: String = prefix + ts_suffix + ".png"
			var file_path: String = folder_path + file_name

			if not FileAccess.file_exists(file_path):
				continue

			var tex = load(file_path) if ResourceLoader.exists(file_path) else null
			if tex == null or not (tex is Texture2D):
				continue

			var anim_name: StringName = StringName(anim_info.name)
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, anim_info.fps)
			sf.set_animation_loop(anim_name, anim_info.loop)

			# Sprite strip: split into frames (each frame is height x height square)
			var frame_size: int = tex.get_height()  # 192px
			var frame_count: int = tex.get_width() / frame_size

			for i in frame_count:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(i * frame_size, 0, frame_size, frame_size)
				sf.add_frame(anim_name, atlas)

			found_any = true

		if found_any:
			unit_sprites[unit_type] = sf
			has_sprite_mode = true


func _load_building_textures() -> void:
	# Load building textures for both teams
	for team_folder in ["blue", "red"]:
		var path: String = "res://assets/sprites/buildings/" + team_folder + "/"
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png"):
				var full_path: String = path + file_name
				if not ResourceLoader.exists(full_path):
					continue
				var tex = load(full_path)
				if tex and tex is Texture2D:
					var key := StringName(team_folder + "_" + file_name.get_basename())
					building_textures[key] = tex
			file_name = dir.get_next()


func get_unit_sprites(unit_type: StringName) -> SpriteFrames:
	return unit_sprites.get(unit_type)


func get_building_sprite(building_type: StringName) -> Texture2D:
	return building_textures.get(building_type)
