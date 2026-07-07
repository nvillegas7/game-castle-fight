## Unit visual showcase test. Renders each unit with all animations for QA review.
## Spawns the unit, cycles through idle → walk → attack → death, captures frames.
##
## Usage:
##   godot --path castle_clash -- --showcase                       # All units
##   godot --path castle_clash -- --showcase --unit footman         # Single unit
##   godot --path castle_clash -- --showcase --group composite      # Group filter
##
## Combine with --write-movie for frame capture:
##   /Applications/Godot.app/Contents/MacOS/Godot \
##     --path /Users/paulinecolobong/game/castle_clash \
##     --write-movie "/tmp/castle_clash_showcase/frame.png" \
##     --fixed-fps 10 -- --showcase --unit knight
##
## Groups: all, melee, ranged, caster, siege, composite, flying
extends Node

const OUT_DIR: String = "/tmp/castle_clash_showcase"

# Unit definitions with group tags
const UNITS: Array = [
	# Kingdom
	{"type": &"footman",       "team": 0, "groups": ["melee"],     "display": "Footman"},
	{"type": &"archer",        "team": 0, "groups": ["ranged"],    "display": "Archer"},
	{"type": &"priest",        "team": 0, "groups": ["caster"],    "display": "Priest"},
	{"type": &"knight",        "team": 0, "groups": ["melee", "composite"], "display": "Knight (Lancer)"},
	{"type": &"catapult",      "team": 0, "groups": ["siege", "composite"], "display": "Catapult"},
	{"type": &"champion",      "team": 0, "groups": ["melee"],     "display": "Champion"},
	{"type": &"gryphon_rider", "team": 0, "groups": ["flying", "composite"], "display": "Gryphon Rider"},
	{"type": &"ballista_unit", "team": 0, "groups": ["siege", "composite"],  "display": "Ballista"},
	{"type": &"royal_knight",  "team": 0, "groups": ["melee", "composite"], "display": "Royal Knight (Mounted)"},
	{"type": &"mage",          "team": 0, "groups": ["caster"],    "display": "Mage"},
	# Horde
	{"type": &"grunt",         "team": 1, "groups": ["melee"],     "display": "Grunt"},
	{"type": &"axe_thrower",   "team": 1, "groups": ["ranged"],    "display": "Axe Thrower"},
	{"type": &"wardrummer",    "team": 1, "groups": ["caster"],    "display": "Wardrummer"},
	{"type": &"berserker",     "team": 1, "groups": ["melee", "composite"], "display": "Berserker (Lancer)"},
	{"type": &"demolisher",    "team": 1, "groups": ["siege", "composite"], "display": "Demolisher"},
	{"type": &"warlord",       "team": 1, "groups": ["melee"],     "display": "Warlord"},
	{"type": &"wyvern_rider",  "team": 1, "groups": ["flying", "composite"], "display": "Wyvern Rider"},
	{"type": &"scorpion",      "team": 1, "groups": ["siege", "composite"],  "display": "Scorpion"},
	{"type": &"war_rider",     "team": 1, "groups": ["melee", "composite"], "display": "War Rider (Mounted)"},
]

const ANIM_SEQUENCE: Array = ["idle", "walk", "attack", "death"]
const FRAMES_PER_ANIM: int = 20  # 2 seconds at 10fps per animation
const PAUSE_FRAMES: int = 5      # 0.5s pause between anims

var _active: bool = false
var _filter_unit: String = ""
var _filter_group: String = "all"
var _queue: Array = []
var _current_idx: int = -1
var _current_anim_idx: int = 0
var _frame_timer: int = 0
var _phase: int = 0  # 0=wait, 1=showing, 2=pause, 3=next
var _results: Array = []

# Visual nodes
var _bg: ColorRect
var _title_label: Label
var _anim_label: Label
var _sprite_node: AnimatedSprite2D
var _pawn_overlay: AnimatedSprite2D
var _team_label: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--showcase" not in args:
		return
	_active = true

	# Parse args
	for i in args.size():
		if args[i] == "--unit" and i + 1 < args.size():
			_filter_unit = args[i + 1]
		if args[i] == "--group" and i + 1 < args.size():
			_filter_group = args[i + 1]

	# Build queue
	for u in UNITS:
		if _filter_unit != "" and str(u.type) != _filter_unit:
			continue
		if _filter_group != "all" and _filter_group not in u.groups:
			continue
		_queue.append(u)

	if _queue.size() == 0:
		print("[Showcase] No units match filter: unit='%s' group='%s'" % [_filter_unit, _filter_group])
		print("[Showcase] Available units: %s" % str(UNITS.map(func(u): return str(u.type))))
		print("[Showcase] Available groups: all, melee, ranged, caster, siege, composite, flying")
		get_tree().quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_scene()
	print("\n[Showcase] Testing %d units (filter: unit='%s' group='%s')" % [
		_queue.size(), _filter_unit if _filter_unit != "" else "*", _filter_group])
	_advance_to_next_unit()


func _setup_scene() -> void:
	# Use CanvasLayer to render ABOVE all game scenes
	var canvas := CanvasLayer.new()
	canvas.layer = 100  # Above everything
	add_child(canvas)

	# Dark background — covers entire screen
	_bg = ColorRect.new()
	_bg.color = Color(0.15, 0.18, 0.12, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_bg)

	# Title label
	_title_label = Label.new()
	_title_label.position = Vector2(20, 20)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	canvas.add_child(_title_label)

	# Team label
	_team_label = Label.new()
	_team_label.position = Vector2(20, 55)
	_team_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_team_label)

	# Animation label
	_anim_label = Label.new()
	_anim_label.position = Vector2(20, 80)
	_anim_label.add_theme_font_size_override("font_size", 18)
	_anim_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	canvas.add_child(_anim_label)

	# Sprite needs to be in main scene tree (not CanvasLayer) for AnimatedSprite2D
	# But we put it on a Node2D with high z_index
	var sprite_layer := CanvasLayer.new()
	sprite_layer.layer = 101
	add_child(sprite_layer)
	var sprite_container := Node2D.new()
	sprite_layer.add_child(sprite_container)

	_sprite_node = AnimatedSprite2D.new()
	_sprite_node.position = Vector2(360, 640)
	_sprite_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite_node.centered = true
	_sprite_node.scale = Vector2(3.0, 3.0)
	sprite_container.add_child(_sprite_node)

	# Pawn overlay for ballista/scorpion composites
	_pawn_overlay = AnimatedSprite2D.new()
	_pawn_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pawn_overlay.centered = true
	_pawn_overlay.z_index = 1
	_pawn_overlay.visible = false
	_sprite_node.add_child(_pawn_overlay)


func _advance_to_next_unit() -> void:
	_current_idx += 1
	if _current_idx >= _queue.size():
		_finish()
		return

	var unit: Dictionary = _queue[_current_idx]
	_current_anim_idx = 0
	_frame_timer = 0
	_phase = 0

	# Load sprites
	var sr: Node = get_node_or_null("/root/SpriteRegistry")
	if sr == null:
		print("[Showcase] ERROR: SpriteRegistry not found")
		_results.append({"unit": str(unit.type), "verdict": "FAIL", "reason": "no SpriteRegistry"})
		_advance_to_next_unit()
		return

	var frames: SpriteFrames = sr.get_unit_sprites(unit.type)
	if frames == null:
		print("[Showcase] FAIL: No sprites for %s" % unit.type)
		_results.append({"unit": str(unit.type), "verdict": "FAIL", "reason": "no sprites loaded"})
		_advance_to_next_unit()
		return

	_sprite_node.sprite_frames = frames
	_sprite_node.flip_h = (unit.team == 1)

	# Check for pawn overlay (ballista/scorpion)
	_pawn_overlay.visible = false
	var composite_types: Array = [&"ballista_unit", &"scorpion"]
	if unit.type in composite_types:
		var pawn_key: String = "blue" if unit.team == 0 else "red"
		if sr.has_method("get_pawn_sprites"):
			var pawn_frames: SpriteFrames = sr.get_pawn_sprites(unit.team)
			if pawn_frames:
				_pawn_overlay.sprite_frames = pawn_frames
				_pawn_overlay.scale = Vector2(0.45, 0.45)
				_pawn_overlay.position = Vector2(-4.0 if unit.team == 0 else 4.0, 3.0)
				_pawn_overlay.flip_h = (unit.team == 1)
				_pawn_overlay.visible = true
				if pawn_frames.has_animation(&"idle"):
					_pawn_overlay.play(&"idle")

	# Update labels
	var team_name: String = "Kingdom (Blue)" if unit.team == 0 else "Horde (Red)"
	var team_color: Color = Color(0.3, 0.5, 1.0) if unit.team == 0 else Color(1.0, 0.3, 0.2)
	_title_label.text = "%s" % unit.display
	_team_label.text = team_name
	_team_label.add_theme_color_override("font_color", team_color)

	# List available animations
	var available: Array = []
	for anim_name in ANIM_SEQUENCE:
		if frames.has_animation(StringName(anim_name)):
			available.append(anim_name)
	print("[Showcase] %s (%s) — anims: %s, composite: %s" % [
		unit.display, team_name,
		str(available),
		"pawn overlay" if _pawn_overlay.visible else ("yes" if "composite" in unit.groups else "no")])

	# Verify and record
	var check: Dictionary = {
		"unit": str(unit.type),
		"display": unit.display,
		"team": unit.team,
		"groups": unit.groups,
		"has_idle": frames.has_animation(&"idle"),
		"has_walk": frames.has_animation(&"walk"),
		"has_attack": frames.has_animation(&"attack"),
		"has_death": frames.has_animation(&"death"),
		"available_anims": available,
		"frame_counts": {},
		"pawn_overlay": _pawn_overlay.visible,
	}
	for anim_name in available:
		check.frame_counts[anim_name] = frames.get_frame_count(StringName(anim_name))

	var missing: Array = []
	if not check.has_idle:
		missing.append("idle")
	if not check.has_walk:
		missing.append("walk")
	if not check.has_attack:
		missing.append("attack")

	check["verdict"] = "PASS" if missing.size() == 0 else "FAIL"
	check["missing"] = missing
	_results.append(check)

	_play_current_anim()


func _play_current_anim() -> void:
	if _current_anim_idx >= ANIM_SEQUENCE.size():
		_advance_to_next_unit()
		return

	var anim_name: String = ANIM_SEQUENCE[_current_anim_idx]
	var frames: SpriteFrames = _sprite_node.sprite_frames
	if frames == null or not frames.has_animation(StringName(anim_name)):
		# Skip missing animation
		_anim_label.text = "Animation: %s (MISSING)" % anim_name
		_current_anim_idx += 1
		_frame_timer = 0
		_phase = 2  # Short pause then next
		return

	_sprite_node.play(StringName(anim_name))
	_anim_label.text = "Animation: %s (%d frames)" % [
		anim_name, frames.get_frame_count(StringName(anim_name))]
	_phase = 1
	_frame_timer = 0

	# Sync pawn overlay if visible
	if _pawn_overlay.visible and _pawn_overlay.sprite_frames:
		var pawn_anim: StringName = &"idle" if anim_name != "walk" else &"walk"
		if _pawn_overlay.sprite_frames.has_animation(pawn_anim):
			_pawn_overlay.play(pawn_anim)


func _process(_delta: float) -> void:
	if not _active:
		return
	_frame_timer += 1

	match _phase:
		1:  # Showing animation
			if _frame_timer >= FRAMES_PER_ANIM:
				_phase = 2
				_frame_timer = 0
		2:  # Pause between anims
			if _frame_timer >= PAUSE_FRAMES:
				_current_anim_idx += 1
				_play_current_anim()
		_:
			pass


func _finish() -> void:
	print("\n[Showcase] === RESULTS ===")
	var pass_count: int = 0
	var fail_count: int = 0
	for r in _results:
		var v: String = r.verdict
		if v == "PASS":
			pass_count += 1
		else:
			fail_count += 1
		var fc_str: String = ""
		if r.has("frame_counts"):
			var parts: Array = []
			for k in r.frame_counts:
				parts.append("%s:%d" % [k, r.frame_counts[k]])
			fc_str = " [%s]" % ", ".join(parts)
		var extra: String = ""
		if r.get("pawn_overlay", false):
			extra += " +pawn"
		if r.get("missing", []).size() > 0:
			extra += " MISSING:%s" % str(r.missing)
		print("  %s %-22s %s%s%s" % [v, r.get("display", r.unit), fc_str, extra,
			" (%s)" % ",".join(r.groups) if r.has("groups") else ""])

	print("\n  %d PASS, %d FAIL / %d total" % [pass_count, fail_count, _results.size()])

	# Save JSON
	var json := JSON.stringify({"results": _results}, "  ")
	var f := FileAccess.open("%s/showcase_report.json" % OUT_DIR, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	print("  Output: %s/showcase_report.json" % OUT_DIR)

	_active = false
	get_tree().quit(0 if fail_count == 0 else 1)
