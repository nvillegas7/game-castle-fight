## Sprite registry: auto-loads Tiny Swords sprite strips and creates SpriteFrames.
## Maps unit types to SpriteFrames with animations.
##
## ==============================================================================
## UI ATLAS CAVEAT (READ BEFORE USING ANY `BigBar_*`, `*Paper`, `Ribbon_*` ASSET)
## ==============================================================================
## Most Tiny Swords UI sprites are MULTI-TILE ATLASES with TRANSPARENT GAP
## ROWS/COLS BETWEEN the tiles — they are NOT standard 9-patch textures.
## Using `NinePatchRect` with patch_margin = corner_size will tile/stretch the
## gap regions and produce visible artifacts:
##   - BigBar_Base (3 wood planks with gaps) → 3 floating pieces
##   - RegularPaper / SpecialPaper (3×3 tile atlas) → transparent center, 4
##     edge lines
##
## Correct pattern: extract each opaque tile via `AtlasTexture`, compose with
## CORNERS FIXED + EDGES TILED + CENTER TILED. See `make_tiled_panel_9` helper
## below for a reusable implementation. Matching tile coords per asset:
##
##   BigBar_Base (320×64)    left cap    y=9..59  x=40..63     mid rivet x=128..191   right cap x=256..279
##   BigBar_Fill (64×64)     strip y=20..43 tiles cleanly
##   SpecialPaper (320×320)  top row y=20..63  mid y=128..191  bot y=256..298
##                           left col x=9..63  mid x=128..191  right x=256..310
##   RegularPaper (320×320)  top row y=20..63  mid y=128..191  bot y=256..300
##                           left col x=12..63 mid x=128..191  right x=256..307
##
## See `tasks/asset-usage.md` for the full manifest.
extends Node

var unit_sprites: Dictionary = {}      # unit_type StringName -> SpriteFrames
var building_textures: Dictionary = {} # building_type StringName -> Texture2D
var ui_textures: Dictionary = {}       # name StringName -> Texture2D
var effect_textures: Dictionary = {}   # effect_name StringName -> Texture2D or SpriteFrames
var pawn_sprites: Dictionary = {}      # "blue"/"red" -> SpriteFrames (for overlay operators)
var has_sprite_mode: bool = false

# Animation properties: our_name -> {fps, loop}
# T-088: Bumped FPS for Fort Guardian-level smoothness.
# BUG-40 (2026-04-18): walk reverted 14→10. At 14fps with ~24px/cycle legs and
# ~30px body, sub-body-width displacement per step read as "skating feet" /
# teleporting. Kept T-088's idle (8) and attack/cast (12) — they don't
# interact with march pacing. T-059 speed_scale phases (0.6/2.0/0.8) still
# multiply on top of attack base FPS.
const ANIM_PROPS := {
	"idle": {"fps": 8, "loop": true},
	"walk": {"fps": 10, "loop": true},
	"attack": {"fps": 12, "loop": false},
	"attack_up": {"fps": 12, "loop": false},
	"attack_down": {"fps": 12, "loop": false},
	"cast": {"fps": 12, "loop": false},
	"death": {"fps": 8, "loop": false},
}

# Map our unit types to Tiny Swords folder/file names + animation file suffixes.
# "anims" maps our animation name -> file suffix (prefix + suffix + ".png" = filename).
# Empty prefix means files have no prefix (e.g. Monk: "Idle.png" not "Monk_Idle.png").
const UNIT_MAP := {
	# Kingdom (Blue)
	&"footman": {"folder": "blue_warrior", "prefix": "Warrior", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "cast": "_Attack2", "death": "_Guard",
	}},
	&"archer": {"folder": "blue_archer", "prefix": "Archer", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Shoot",
	}},
	&"priest": {"folder": "blue_monk", "prefix": "", "anims": {
		"idle": "Idle", "walk": "Run", "attack": "Heal", "cast": "Heal",
	}},
	&"knight": {"folder": "blue_lancer", "prefix": "Lancer", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Right_Attack", "death": "_Right_Defence",
	}},
	&"catapult": {"folder": "blue_catapult", "prefix": "Catapult", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	# Horde (Red)
	&"grunt": {"folder": "red_warrior", "prefix": "Warrior", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "cast": "_Attack2", "death": "_Guard",
	}},
	&"axe_thrower": {"folder": "red_archer", "prefix": "Archer", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Shoot",
	}},
	&"wardrummer": {"folder": "red_monk", "prefix": "", "anims": {
		"idle": "Idle", "walk": "Run", "attack": "Heal", "cast": "Heal",
	}},
	&"berserker": {"folder": "red_lancer", "prefix": "Lancer", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Right_Attack", "death": "_Right_Defence",
	}},
	&"demolisher": {"folder": "red_catapult", "prefix": "Catapult", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	# T3 units — use Tiny Swords warrior with Attack2 to distinguish from T1 footman/grunt
	&"champion": {"folder": "blue_warrior", "prefix": "Warrior", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack2", "death": "_Guard",
	}},
	&"warlord": {"folder": "red_warrior", "prefix": "Warrior", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack2", "death": "_Guard",
	}},
	# Flying units — custom gryphon sprites
	&"gryphon_rider": {"folder": "blue_gryphon", "prefix": "Gryphon", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	&"wyvern_rider": {"folder": "red_gryphon", "prefix": "Gryphon", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	# Siege units — ballista sprites
	&"ballista_unit": {"folder": "blue_ballista", "prefix": "Ballista", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	&"scorpion": {"folder": "red_ballista", "prefix": "Ballista", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	# Mage — Tiny RPG Wizard sprites (T-083)
	&"mage": {"folder": "blue_mage", "prefix": "Mage", "anims": {
		"idle": "_Idle", "walk": "_Walk", "attack": "_Attack", "death": "_Death",
	}},
	# Red mage — visual-only entry for team 1 (mirror mode). Same anims, red folder.
	&"red_mage": {"folder": "red_mage", "prefix": "Mage", "anims": {
		"idle": "_Idle", "walk": "_Walk", "attack": "_Attack", "death": "_Death",
	}},
	# Cavalry units — mounted knight sprites
	&"royal_knight": {"folder": "blue_knight", "prefix": "Knight", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
	&"war_rider": {"folder": "red_knight", "prefix": "Knight", "anims": {
		"idle": "_Idle", "walk": "_Run", "attack": "_Attack1", "death": "_Guard",
	}},
}

# Map game building types to Tiny Swords building sprite filenames
const BUILDING_MAP := {
	&"barracks": "Barracks",
	&"war_camp": "Barracks",
	&"archer_range": "Archery",
	&"axe_range": "Archery",
	&"priest_temple": "Monastery",
	&"war_drums": "Monastery",
	&"knight_hall": "House2",
	&"berserker_pit": "House2",
	&"siege_workshop": "House1",
	&"demolisher_works": "House1",
	&"gold_mine": "House3",
	&"plunder_camp": "House3",
	&"guard_tower": "Tower",
	&"flame_tower": "Tower",
	&"wall": "House3",
	&"palisade": "House3",
	&"armory": "House2",
	&"blood_altar": "House2",
	&"war_horn": "Tower",
	&"blood_totem": "Tower",
	&"champions_hall": "Castle",
	&"warlords_den": "Castle",
	&"gryphon_roost": "Archery",
	&"wyvern_nest": "Archery",
	&"ballista_workshop": "House1",
	&"scorpion_foundry": "House1",
	&"royal_stable": "Barracks",
	&"beast_pen": "Barracks",
	# T-086: Mage tower — Tiny Swords Tower with palette-swapped wizard hat on top.
	# Sprite at assets/sprites/buildings/{blue,red}/MageTower.png. T-084 (A5) will
	# create the mage_tower.tres data file that triggers this sprite.
	&"mage_tower": "MageTower",
}


func _ready() -> void:
	_load_unit_sprites()
	_load_building_textures()
	_load_ui_textures()
	_load_effect_textures()
	_load_pawn_sprites()


func _load_unit_sprites() -> void:
	var base_path := "res://assets/sprites/units/"

	for unit_type in UNIT_MAP:
		var info: Dictionary = UNIT_MAP[unit_type]
		var folder: String = info.folder
		var prefix: String = info.prefix
		var anims: Dictionary = info.anims
		var folder_path: String = base_path + folder + "/"

		# Don't use DirAccess.open to check folder existence — it fails in web
		# exports (PCK virtual filesystem). Just try loading files directly.
		var sf := SpriteFrames.new()
		if sf.has_animation(&"default"):
			sf.remove_animation(&"default")

		var found_any: bool = false

		for anim_name_str in anims:
			var file_suffix: String = anims[anim_name_str]
			var file_name: String = prefix + file_suffix + ".png"
			var file_path: String = folder_path + file_name

			# Use ResourceLoader.exists — FileAccess.file_exists fails for packed
			# resources in Godot web exports (PCK virtual filesystem).
			if not ResourceLoader.exists(file_path):
				continue

			var tex = load(file_path)
			if tex == null or not (tex is Texture2D):
				continue

			var props: Dictionary = ANIM_PROPS.get(anim_name_str, {"fps": 8, "loop": false})
			var anim_name: StringName = StringName(anim_name_str)
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, props.fps)
			sf.set_animation_loop(anim_name, props.loop)

			# Sprite strip: split into frames (each frame is height x height square)
			var frame_size: int = tex.get_height()
			var frame_count: int = maxi(1, tex.get_width() / frame_size)

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
	# Explicit file list — DirAccess directory scanning fails in web exports.
	var building_files := [
		"Archery", "Barracks", "Castle", "House1", "House2", "House3",
		"MageTower", "Monastery", "Tower",
	]
	for team_folder in ["blue", "red"]:
		for base_name in building_files:
			var full_path: String = "res://assets/sprites/buildings/" + team_folder + "/" + base_name + ".png"
			if not ResourceLoader.exists(full_path):
				continue
			var tex = load(full_path)
			if tex and tex is Texture2D:
				var key := StringName(team_folder + "_" + base_name)
				building_textures[key] = tex


# T-066 fix: Kingdom units on team 1 need red sprite variants.
# Maps each Kingdom unit_type to its red-sprite equivalent (same animations, red folder).
const RED_EQUIVALENT := {
	&"footman": &"grunt",
	&"archer": &"axe_thrower",
	&"priest": &"wardrummer",
	&"knight": &"berserker",
	&"catapult": &"demolisher",
	&"champion": &"warlord",
	&"gryphon_rider": &"wyvern_rider",
	&"ballista_unit": &"scorpion",
	&"royal_knight": &"war_rider",
	# T-083: Mage is Kingdom-only but red sprite still needed for mirror mode.
	&"mage": &"red_mage",
}


func get_unit_sprites(unit_type: StringName, team: int = 0) -> SpriteFrames:
	if team == 1:
		var red_type: StringName = RED_EQUIVALENT.get(unit_type, unit_type)
		var red_sprites: SpriteFrames = unit_sprites.get(red_type)
		if red_sprites:
			return red_sprites
	return unit_sprites.get(unit_type)


func get_building_sprite(building_type: StringName, team: int = 0) -> Texture2D:
	var sprite_name: String = BUILDING_MAP.get(building_type, "")
	if sprite_name == "":
		return null
	var team_folder: String = "blue" if team == 0 else "red"
	var key := StringName(team_folder + "_" + sprite_name)
	return building_textures.get(key)


func get_castle_sprite(team: int) -> Texture2D:
	var team_folder: String = "blue" if team == 0 else "red"
	var key := StringName(team_folder + "_Castle")
	return building_textures.get(key)


func _load_ui_textures() -> void:
	# Explicit file list — DirAccess directory scanning fails in web exports.
	var ui_path := "res://assets/sprites/ui/"
	var ui_files := [
		"Banner", "Banner_Slots", "BigBar_Base", "BigBar_Fill",
		"BigBlueButton_Pressed", "BigBlueButton_Regular",
		"BigRedButton_Pressed", "BigRedButton_Regular", "BigRibbons",
		"bolt_icon", "horse_icon", "wing_icon",
		"Icon_01", "Icon_02", "Icon_03", "Icon_04", "Icon_05", "Icon_06",
		"Icon_07", "Icon_08", "Icon_09", "Icon_10", "Icon_11", "Icon_12",
		"logo", "logo_128", "logo_32", "logo_512",
		"RegularPaper", "Ribbon_Black", "Ribbon_Blue", "Ribbon_Purple",
		"Ribbon_Red", "Ribbon_Yellow", "Slots",
		"SmallBar_Base", "SmallBar_Fill", "SpecialPaper", "Swords",
		"WoodTable", "WoodTable_Slots",
	]
	# Avatars
	for i in range(1, 26):
		ui_files.append("Avatars_%02d" % i)
	# Small/Tiny buttons
	for prefix in ["SmallBlueRound", "SmallBlueSquare", "SmallRedRound", "SmallRedSquare"]:
		ui_files.append(prefix + "Button_Pressed")
		ui_files.append(prefix + "Button_Regular")
	for prefix in ["TinyRoundBlue", "TinyRoundRed", "TinySquareBlue", "TinySquareRed"]:
		ui_files.append(prefix + "Button")
	# Cursors
	for i in range(1, 5):
		ui_files.append("Cursor_%02d" % i)
	ui_files.append("SmallRibbons")

	for base_name in ui_files:
		var full_path: String = ui_path + base_name + ".png"
		if ResourceLoader.exists(full_path):
			var tex = load(full_path)
			if tex and tex is Texture2D:
				ui_textures[StringName(base_name)] = tex


func get_ui_texture(name: StringName) -> Texture2D:
	return ui_textures.get(name)


func _load_effect_textures() -> void:
	# Arrow projectile — Tiny Swords per-team arrows (64x64, detailed pixel art)
	for entry in [["blue_archer", &"blue_arrow"], ["red_archer", &"red_arrow"]]:
		var path: String = "res://assets/sprites/units/" + entry[0] + "/Arrow.png"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				effect_textures[entry[1]] = tex

	# Ballista bolt projectile
	for entry in [["blue_ballista", &"blue_bolt"], ["red_ballista", &"red_bolt"]]:
		var path: String = "res://assets/sprites/units/" + entry[0] + "/Bolt.png"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				effect_textures[entry[1]] = tex

	# Catapult rock projectile
	for entry in [["blue_catapult", &"blue_rock"], ["red_catapult", &"red_rock"]]:
		var path: String = "res://assets/sprites/units/" + entry[0] + "/Rock.png"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				effect_textures[entry[1]] = tex

	# T-083: Mage fireball projectile
	for entry in [["blue_mage", &"blue_fireball"], ["red_mage", &"red_fireball"]]:
		var path: String = "res://assets/sprites/units/" + entry[0] + "/Fireball.png"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				effect_textures[entry[1]] = tex

	# Heal effect (11-frame sprite strip, 2112x192 -> 192x192 frames)
	for team_folder in ["blue_monk", "red_monk"]:
		var path: String = "res://assets/sprites/units/" + team_folder + "/Heal_Effect.png"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				var sf := SpriteFrames.new()
				if sf.has_animation(&"default"):
					sf.remove_animation(&"default")
				sf.add_animation(&"heal_effect")
				sf.set_animation_speed(&"heal_effect", 15)
				sf.set_animation_loop(&"heal_effect", false)
				var frame_size: int = tex.get_height()
				var frame_count: int = maxi(1, tex.get_width() / frame_size)
				for i in frame_count:
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(i * frame_size, 0, frame_size, frame_size)
					sf.add_frame(&"heal_effect", atlas)
				var key := StringName(team_folder.split("_")[0] + "_heal_effect")
				effect_textures[key] = sf


	# Explosion effects (Explosion_01.png, Explosion_02.png)
	for i in range(1, 3):
		var path: String = "res://assets/sprites/effects/Explosion_%02d.png" % i
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				var sf := SpriteFrames.new()
				if sf.has_animation(&"default"):
					sf.remove_animation(&"default")
				sf.add_animation(&"explosion")
				sf.set_animation_speed(&"explosion", 14)
				sf.set_animation_loop(&"explosion", false)
				var h: int = tex.get_height()
				var frame_count: int = maxi(1, tex.get_width() / h)
				for f in frame_count:
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(f * h, 0, h, h)
					sf.add_frame(&"explosion", atlas)
				effect_textures[StringName("explosion_%d" % i)] = sf

	# Dust effects (Dust_01.png, Dust_02.png)
	for i in range(1, 3):
		var path: String = "res://assets/sprites/effects/Dust_%02d.png" % i
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				var sf := SpriteFrames.new()
				if sf.has_animation(&"default"):
					sf.remove_animation(&"default")
				sf.add_animation(&"dust")
				sf.set_animation_speed(&"dust", 12)
				sf.set_animation_loop(&"dust", false)
				var h: int = tex.get_height()
				var frame_count: int = maxi(1, tex.get_width() / h)
				for f in frame_count:
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(f * h, 0, h, h)
					sf.add_frame(&"dust", atlas)
				effect_textures[StringName("dust_%d" % i)] = sf

	# Fire effects (Fire_01.png, Fire_02.png, Fire_03.png)
	for i in range(1, 4):
		var path: String = "res://assets/sprites/effects/Fire_%02d.png" % i
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex and tex is Texture2D:
				var sf := SpriteFrames.new()
				if sf.has_animation(&"default"):
					sf.remove_animation(&"default")
				sf.add_animation(&"fire")
				sf.set_animation_speed(&"fire", 10)
				sf.set_animation_loop(&"fire", true)
				var h: int = tex.get_height()
				var frame_count: int = maxi(1, tex.get_width() / h)
				for f in frame_count:
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(f * h, 0, h, h)
					sf.add_frame(&"fire", atlas)
				effect_textures[StringName("fire_%d" % i)] = sf


func get_explosion_frames() -> SpriteFrames:
	# Return random explosion variant
	var key := StringName("explosion_%d" % randi_range(1, 2))
	return effect_textures.get(key)


func get_dust_frames() -> SpriteFrames:
	var key := StringName("dust_%d" % randi_range(1, 2))
	return effect_textures.get(key)


func get_fire_frames() -> SpriteFrames:
	var key := StringName("fire_%d" % randi_range(1, 3))
	return effect_textures.get(key)


func get_arrow_texture(team: int) -> Texture2D:
	var key := StringName("blue_arrow" if team == 0 else "red_arrow")
	return effect_textures.get(key)


func get_rock_texture(team: int) -> Texture2D:
	var key := StringName("blue_rock" if team == 0 else "red_rock")
	return effect_textures.get(key)


func get_bolt_texture(team: int) -> Texture2D:
	var key := StringName("blue_bolt" if team == 0 else "red_bolt")
	return effect_textures.get(key)


func get_fireball_texture(team: int) -> Texture2D:
	var key := StringName("blue_fireball" if team == 0 else "red_fireball")
	return effect_textures.get(key)


func get_heal_effect_frames(team: int) -> SpriteFrames:
	var key := StringName("blue_heal_effect" if team == 0 else "red_heal_effect")
	return effect_textures.get(key)


func get_pawn_sprites(team: int) -> SpriteFrames:
	var key: String = "blue" if team == 0 else "red"
	return pawn_sprites.get(key)


func _load_pawn_sprites() -> void:
	# Load raw Pawn idle/run for siege unit overlays (ballista operator on top)
	for team_folder in ["blue_pawn", "red_pawn"]:
		var base_path: String = "res://assets/sprites/units/" + team_folder + "/"
		var sf := SpriteFrames.new()
		if sf.has_animation(&"default"):
			sf.remove_animation(&"default")
		var found_any: bool = false
		# Map: our anim name -> file name
		var pawn_anims := {"idle": "Pawn_Idle.png", "walk": "Pawn_Run.png"}
		for anim_name_str in pawn_anims:
			var file_path: String = base_path + pawn_anims[anim_name_str]
			if not ResourceLoader.exists(file_path):
				continue
			var tex = load(file_path)
			if tex == null or not (tex is Texture2D):
				continue
			var props: Dictionary = ANIM_PROPS.get(anim_name_str, {"fps": 8, "loop": true})
			var anim_name: StringName = StringName(anim_name_str)
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, props.fps)
			sf.set_animation_loop(anim_name, props.loop)
			var frame_size: int = tex.get_height()
			var frame_count: int = maxi(1, tex.get_width() / frame_size)
			for i in frame_count:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(i * frame_size, 0, frame_size, frame_size)
				sf.add_frame(anim_name, atlas)
			found_any = true
		if found_any:
			var key: String = team_folder.split("_")[0]  # "blue" or "red"
			pawn_sprites[key] = sf


## Compose a 9-patch panel from a multi-tile atlas texture by stitching 4
## fixed corners + 4 tiled edges + 1 tiled center. Use this instead of
## `NinePatchRect` when the source texture has TRANSPARENT GAPS between
## its tiles (BigBar_Base, SpecialPaper, RegularPaper all do).
##
## `regions` is a Dictionary keyed by tile position with Rect2 values:
##   tl, tm, tr  — top-left, top-middle (tiled), top-right
##   ml, mm, mr  — middle-left (tiled), center (tiled), middle-right (tiled)
##   bl, bm, br  — bottom-left, bottom-middle (tiled), bottom-right
## Assumes all three rows share a height and all three columns share a width
## (derived from the tl region). Uniform corners simplify layout math.
## Optional `corner_scale` shrinks corner tiles so all 4 remain visible when the
## target is too shallow or narrow for native-size corners to coexist with a
## center row. Default 1.0 = native atlas size. For a 600×90 panel with native
## 55×44 corners, scale 0.55 gives ~30×24 corners leaving ~42 px of center row
## visible — all 4 corners + middle tiles render cleanly.
static func make_tiled_panel_9(tex: Texture2D, regions: Dictionary, target_size: Vector2, corner_scale: float = 1.0) -> Control:
	var container := Control.new()
	container.size = target_size
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var corner_w: float = regions.tl.size.x * corner_scale
	var corner_h: float = regions.tl.size.y * corner_scale
	# Guard: if corner is bigger than half the target dimension, the center
	# collapses — auto-shrink corners to target_dim/3 so a 3×3 grid always fits.
	if corner_w * 2.0 >= target_size.x:
		corner_w = target_size.x / 3.0
	if corner_h * 2.0 >= target_size.y:
		corner_h = target_size.y / 3.0
	var mid_w: float = maxf(target_size.x - corner_w * 2.0, 1.0)
	var mid_h: float = maxf(target_size.y - corner_h * 2.0, 1.0)

	# 4 corners — fixed size from source atlas, no stretching.
	_add_tile(container, tex, regions.tl, Vector2(0, 0), Vector2(corner_w, corner_h), TextureRect.STRETCH_SCALE)
	_add_tile(container, tex, regions.tr, Vector2(target_size.x - corner_w, 0), Vector2(corner_w, corner_h), TextureRect.STRETCH_SCALE)
	_add_tile(container, tex, regions.bl, Vector2(0, target_size.y - corner_h), Vector2(corner_w, corner_h), TextureRect.STRETCH_SCALE)
	_add_tile(container, tex, regions.br, Vector2(target_size.x - corner_w, target_size.y - corner_h), Vector2(corner_w, corner_h), TextureRect.STRETCH_SCALE)

	# 4 edges — tiled across the inter-corner span.
	_add_tile(container, tex, regions.tm, Vector2(corner_w, 0), Vector2(mid_w, corner_h), TextureRect.STRETCH_TILE)
	_add_tile(container, tex, regions.bm, Vector2(corner_w, target_size.y - corner_h), Vector2(mid_w, corner_h), TextureRect.STRETCH_TILE)
	_add_tile(container, tex, regions.ml, Vector2(0, corner_h), Vector2(corner_w, mid_h), TextureRect.STRETCH_TILE)
	_add_tile(container, tex, regions.mr, Vector2(target_size.x - corner_w, corner_h), Vector2(corner_w, mid_h), TextureRect.STRETCH_TILE)

	# Center — tiled across the full inter-corner rect.
	_add_tile(container, tex, regions.mm, Vector2(corner_w, corner_h), Vector2(mid_w, mid_h), TextureRect.STRETCH_TILE)

	return container


static func _add_tile(parent: Control, tex: Texture2D, region: Rect2, pos: Vector2, size: Vector2, stretch_mode: int) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	var rect := TextureRect.new()
	rect.texture = atlas
	rect.position = pos
	rect.size = size
	rect.stretch_mode = stretch_mode
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


## Pre-built tile region dictionaries for the two parchment assets.
## Use with `make_tiled_panel_9(tex, SPECIAL_PAPER_REGIONS, size)`.
const SPECIAL_PAPER_REGIONS := {
	"tl": Rect2(9, 20, 55, 44),
	"tm": Rect2(128, 20, 64, 44),
	"tr": Rect2(256, 20, 55, 44),
	"ml": Rect2(9, 128, 55, 64),
	"mm": Rect2(128, 128, 64, 64),
	"mr": Rect2(256, 128, 55, 64),
	"bl": Rect2(9, 256, 55, 43),
	"bm": Rect2(128, 256, 64, 43),
	"br": Rect2(256, 256, 55, 43),
}

const REGULAR_PAPER_REGIONS := {
	"tl": Rect2(12, 20, 52, 44),
	"tm": Rect2(128, 20, 64, 44),
	"tr": Rect2(256, 20, 52, 44),
	"ml": Rect2(12, 128, 52, 64),
	"mm": Rect2(128, 128, 64, 64),
	"mr": Rect2(256, 128, 52, 64),
	"bl": Rect2(12, 256, 52, 45),
	"bm": Rect2(128, 256, 64, 45),
	"br": Rect2(256, 256, 52, 45),
}
