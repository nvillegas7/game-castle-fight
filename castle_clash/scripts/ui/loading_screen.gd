## Loading screen with scenic Tiny Swords background.
## T-098: parallax clouds, bird flights, idle logo bob, wooden progress bar,
## rotating tip strip, fade-out to main menu.
extends Control

@onready var progress_fill_legacy: ColorRect = $ProgressBarBg/ProgressFill
@onready var status_label: Label = $StatusLabel

var _bar_base: Control = null
var _bar_fill: Control = null  # TextureRect or NinePatchRect, both Control
var _bar_shine: ColorRect = null
var _bar_width: float = 500.0
var _bar_inner_margin: float = 8.0
var _bar_fill_target: float = 0.0

var _tip_label: Label = null
var _tip_index: int = 0
var _tip_timer: float = 0.0
const _TIP_DISPLAY_SEC: float = 3.5
const _TIP_FADE_SEC: float = 0.25

const _TIPS := [
	"Wall buildings redirect enemy paths — use them to create chokepoints.",
	"Priests heal nearby allies. Keep them behind your front line.",
	"Castle Wrath triggers at 30% HP — a one-time blast wipes nearby enemies.",
	"Place Gold Mines early for compound income (+15% per mine).",
	"Archers shred Footmen (Pierce vs Light = 150% damage).",
	"Siege units (Catapult, Ballista) crush buildings but lose to speed.",
	"Armory and Blood Altar upgrades stack buffs across your army.",
	"Mages cast fireball in a 1.5-cell radius — punish clumped enemies.",
	"Mirror matches use your selected faction only. Blitz mode doubles income.",
	"Flying units ignore terrain — plan anti-air with Archers or Gryphons.",
]


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res and res is Texture2D:
			return res
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
		var img := Image.new()
		var err: int = img.load(abs_path if FileAccess.file_exists(abs_path) else path)
		if err == OK and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _ready() -> void:
	# T-052: Replace old Swords.png with real Castle Fight logo.
	# T-098: shifted up 40px (now y=280-580) to give space for tip strip below.
	var old_logo = get_node_or_null("Logo")
	if old_logo:
		var logo_tex = load("res://assets/sprites/ui/logo.png")
		if logo_tex:
			old_logo.texture = logo_tex
			old_logo.offset_top = 280.0
			old_logo.offset_bottom = 580.0
			old_logo.offset_left = -200.0
			old_logo.offset_right = 200.0
			old_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# Logo bob removed 2026-04-19 (user: "no need to animate the logo").
			# Side-benefit: the prior `_start_logo_bob` tweened `position:y` to
			# absolute -4/+4 instead of applying a delta — that yanked the logo
			# ~280 px above its anchored offset, which was why the castle looked
			# "nowhere near the logo" (castle sat below a phantom logo position).
		else:
			old_logo.visible = false
	# Hide title label — logo already contains "CASTLE FIGHT" text
	var title_lbl = get_node_or_null("Title")
	if title_lbl:
		title_lbl.visible = false

	# Hide the pre-existing StatusLabel from the .tscn — it sat at y=870 right
	# inside the new plateau zone. The bar + rotating tips give enough
	# progress feedback; keeping the label visible just littered the scene.
	if status_label:
		status_label.visible = false

	_build_scenic_background()
	_build_wooden_progress_bar()
	_build_tip_strip()

	SFX.play_music("loading_ambient")

	# Animate the loading bar (unified into the new NinePatchRect).
	# T-098: ease-out-cubic on the first segment for a snappier start.
	var tw := create_tween()
	tw.tween_method(_set_bar_fill, 0.0, 0.30, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(_set_status.bind("Loading assets..."))
	tw.tween_method(_set_bar_fill, 0.30, 0.70, 1.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_set_status.bind("Preparing battle..."))
	tw.tween_method(_set_bar_fill, 0.70, 1.0, 0.8).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.6)
	tw.tween_callback(_go_to_menu)

	# Hide legacy ColorRect progress bar — the NinePatchRect replaces it.
	var legacy_bg = get_node_or_null("ProgressBarBg")
	if legacy_bg:
		legacy_bg.visible = false


func _process(delta: float) -> void:
	_tip_timer += delta
	if _tip_timer >= _TIP_DISPLAY_SEC:
		_tip_timer = 0.0
		_rotate_tip()


func _start_logo_bob(logo_node: Control) -> void:
	# ±4 px vertical ease-in-out-sine on a 3 s loop. Uses `position.y` offset
	# (via pivot-less translate) instead of `offset_top/bottom`, so layout
	# engine can't reset the bob back to 0 on a re-layout pass.
	var tw := logo_node.create_tween().set_loops()
	tw.tween_property(logo_node, "position:y", -4.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(logo_node, "position:y", 4.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_wooden_progress_bar() -> void:
	# BUG-43 round 4: user direction was "replicate the middle portion until
	# all the bar is covered". Tiny Swords `BigBar_Base` (320×64) has 3 OPAQUE
	# pieces (left cap 40..63, middle rivet 128..191, right cap 256..279) with
	# transparent gaps between them at native scale — the asset is designed for
	# ONE fixed width. Stretching OR naïvely placing it shows visible gaps.
	# Architecture: LEFT CAP fixed + MIDDLE RIVET tiled to fill the full span +
	# RIGHT CAP fixed — yields a continuous wooden frame. `BigBar_Fill` (red
	# strip at native y=20..43) is drawn ON TOP at the frame's trough height
	# so it looks like a filling HP bar.
	var base_tex := _load_texture("res://assets/sprites/ui/BigBar_Base.png")
	var fill_tex := _load_texture("res://assets/sprites/ui/BigBar_Fill.png")
	if base_tex == null or fill_tex == null:
		return

	# User direction (2026-04-19 round 2): shrink another 20% (total 44% smaller
	# than original). New display 269×72. Scale factor 1.125 keeps all native
	# geometry in sync so the red fill stays inside the wooden trough.
	var scale_factor: float = 1.125
	var native_cap_w: float = 24.0
	var native_h: float = 64.0
	var cap_w: float = native_cap_w * scale_factor  # 27
	var bar_h: float = native_h * scale_factor      # 72
	var bar_w: float = 269.0                        # 20% smaller than 336
	var middle_w: float = bar_w - cap_w * 2.0       # 215
	var bar_x: float = (720.0 - bar_w) * 0.5
	var bar_y: float = 990.0

	var container := Control.new()
	container.position = Vector2(bar_x, bar_y)
	container.size = Vector2(bar_w, bar_h)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_bar_base = container

	# Left cap — AtlasTexture crop from source x=40..63 (24px wide, full 64 tall)
	var left_atlas := AtlasTexture.new()
	left_atlas.atlas = base_tex
	left_atlas.region = Rect2(40, 0, 24, 64)
	var left_cap := TextureRect.new()
	left_cap.texture = left_atlas
	left_cap.size = Vector2(cap_w, bar_h)
	left_cap.position = Vector2.ZERO
	left_cap.stretch_mode = TextureRect.STRETCH_SCALE
	left_cap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	left_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(left_cap)

	# Middle rivet — TILED horizontally across the span between the caps.
	# STRETCH_TILE repeats the atlas region every native-width (24 display
	# px per tile at 2× scale) instead of stretching it, so the rivet texture
	# reads as a continuous wooden bar with no gaps or distortion.
	var mid_atlas := AtlasTexture.new()
	mid_atlas.atlas = base_tex
	mid_atlas.region = Rect2(128, 0, 64, 64)
	var mid := TextureRect.new()
	mid.texture = mid_atlas
	mid.size = Vector2(middle_w, bar_h)
	mid.position = Vector2(cap_w, 0)
	mid.stretch_mode = TextureRect.STRETCH_TILE
	mid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(mid)

	# Right cap — AtlasTexture crop from source x=256..279
	var right_atlas := AtlasTexture.new()
	right_atlas.atlas = base_tex
	right_atlas.region = Rect2(256, 0, 24, 64)
	var right_cap := TextureRect.new()
	right_cap.texture = right_atlas
	right_cap.size = Vector2(cap_w, bar_h)
	right_cap.position = Vector2(bar_w - cap_w, 0)
	right_cap.stretch_mode = TextureRect.STRETCH_SCALE
	right_cap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(right_cap)

	# Fill ON TOP — AtlasTexture crop of the opaque red strip (native y=20..43)
	# so the fill renders INSIDE the wooden trough regardless of element size.
	# Previous STRETCH_TILE tiled the 64×64 source in a 27-tall element, which
	# clipped the opaque band because only native y=0..27 fit (most of 20..43
	# got cut off, and the visible strip shifted to the bar's bottom edge).
	var fill_src_y: int = 20
	var fill_src_h: int = 23                   # opaque content 20..42
	var fill_y: float = fill_src_y * scale_factor
	var fill_h: float = fill_src_h * scale_factor
	var fill_inner_x: float = cap_w * 0.95     # start fill just past the cap's outer rim
	var fill_atlas := AtlasTexture.new()
	fill_atlas.atlas = fill_tex
	fill_atlas.region = Rect2(0, fill_src_y, 64, fill_src_h)
	_bar_fill = TextureRect.new()
	_bar_fill.texture = fill_atlas
	_bar_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_bar_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bar_fill.position = Vector2(fill_inner_x, fill_y)
	_bar_fill.size = Vector2(0.0, fill_h)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_bar_fill)
	_bar_width = bar_w - fill_inner_x * 2.0  # Max fill width (inset both sides)

	# Shine sweep — bright white strip clipped to fill.
	_bar_shine = ColorRect.new()
	_bar_shine.color = Color(1.0, 1.0, 1.0, 0.35)
	_bar_shine.size = Vector2(32.0, fill_h)
	_bar_shine.position = Vector2(-50.0, 0.0)
	_bar_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.add_child(_bar_shine)
	_bar_fill.clip_contents = true
	_start_shine_loop()


func _set_bar_fill(ratio: float) -> void:
	_bar_fill_target = clampf(ratio, 0.0, 1.0)
	if _bar_fill:
		# _bar_width now IS the fill's max width (pre-computed to match the
		# BigBar_Base inner channel), no extra margin subtraction needed.
		_bar_fill.size.x = _bar_width * _bar_fill_target
	# Mirror into the legacy ColorRect too in case assets are missing and the
	# fallback bar is still visible during tests.
	if progress_fill_legacy:
		progress_fill_legacy.size.x = 354.0 * _bar_fill_target


func _start_shine_loop() -> void:
	if _bar_shine == null or _bar_fill == null:
		return
	var tw := _bar_shine.create_tween().set_loops()
	tw.tween_property(_bar_shine, "position:x", _bar_width + 40.0, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_shine, "position:x", -60.0, 0.0)
	tw.tween_interval(1.3)


func _build_tip_strip() -> void:
	# Restyled 2026-07-02: the SpecialPaper 3×3 atlas composite read as a
	# default-gray panel with thin gold corners, clashing with the wood/pixel
	# theme. Replaced with a themed StyleBoxFlat — dark wood body, warm brass
	# border — matching the card hand / end screen palette.
	var tip_w: float = 540.0
	var tip_h: float = 84.0
	var tip_x: float = (720.0 - tip_w) * 0.5
	var tip_y: float = 1090.0  # sits below the bar (bar ends y=1070 after shift)

	var strip := Panel.new()
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = Color(0.18, 0.12, 0.07, 0.96)      # dark wood
	strip_style.border_color = Color(0.58, 0.43, 0.20, 0.95)  # warm brass-brown
	strip_style.set_border_width_all(3)
	strip_style.set_corner_radius_all(12)
	strip_style.shadow_color = Color(0, 0, 0, 0.35)
	strip_style.shadow_size = 6
	strip_style.shadow_offset = Vector2(0, 3)
	strip.add_theme_stylebox_override("panel", strip_style)
	strip.size = Vector2(tip_w, tip_h)
	strip.position = Vector2(tip_x, tip_y)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 18)
	# Cream text on the dark wood panel for legibility (>=14px QA floor).
	_tip_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.68))
	_tip_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03))
	_tip_label.add_theme_constant_override("outline_size", 2)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.position = Vector2(16, 8)
	_tip_label.size = Vector2(tip_w - 32, tip_h - 16)
	_tip_label.text = _TIPS[0]
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_tip_label)


func _rotate_tip() -> void:
	if _tip_label == null:
		return
	var next_idx: int = (_tip_index + 1) % _TIPS.size()
	var tw := create_tween()
	tw.tween_property(_tip_label, "modulate:a", 0.0, _TIP_FADE_SEC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_tip_index = next_idx
		_tip_label.text = _TIPS[_tip_index]
	)
	tw.tween_property(_tip_label, "modulate:a", 1.0, _TIP_FADE_SEC).set_ease(Tween.EASE_OUT)


func _build_scenic_background() -> void:
	# Overhaul 2026-04-19 per user direction. Composition, top to bottom:
	#   y=0–260    sky with 3 drifting clouds (different sizes)
	#   y=280–580  logo (kept from prior, anchors handled in _ready)
	#   y=600–820  castle centerpiece flanked by tree clumps
	#   y=820–1020 multi-elevation plateau + mini water pond (Tilemap_color1)
	#   y=1020+    tip strip + fade transition area
	# Deletions from prior build: decorative Barracks/Tower/Archery/Monastery,
	# edge-aligned trees, the 2 gryphon birds, 4 mid-field grass patches.
	var scene_layer := Control.new()
	scene_layer.name = "SceneLayer"
	scene_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scene_layer)
	move_child(scene_layer, 0)

	# Vertical sky gradient: light blue at the zenith feathering to a pale
	# horizon haze just above the castle/grove line (~y=510-600), then meadow
	# green behind the scene down past the plateau/water. Replaces the flat
	# green plane that made the sky read as a green wall with dark cloud blobs.
	# Sizing contract: TextureRect anchored FULL_RECT inside scene_layer (a
	# fixed-size Control), so the rect is anchor-driven and honored.
	# z_index=-10 keeps plateau tiles (which use negative z to stack under
	# trees/castle) above the sky plane.
	var sky_grad := Gradient.new()
	sky_grad.offsets = PackedFloat32Array([0.0, 0.40, 0.47, 0.53, 1.0])
	sky_grad.colors = PackedColorArray([
		Color(0.45, 0.66, 0.90),   # zenith blue (y=0)
		Color(0.71, 0.84, 0.94),   # pale horizon haze (~y=512, above grove)
		Color(0.60, 0.76, 0.58),   # haze-to-meadow feather (~y=602)
		Color(0.40, 0.60, 0.31),   # sunlit meadow (~y=678)
		Color(0.25, 0.44, 0.20),   # deep field green at the bottom
	])
	var sky_tex := GradientTexture2D.new()
	sky_tex.gradient = sky_grad
	sky_tex.fill_from = Vector2(0, 0)
	sky_tex.fill_to = Vector2(0, 1)   # Vertical
	sky_tex.width = 64
	sky_tex.height = 1280
	var sky := TextureRect.new()
	sky.texture = sky_tex
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.z_index = -10
	scene_layer.add_child(sky)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	# --- 3 clouds above the logo (y=40..240) ---
	# Sizes scale: small(90), medium(140), large(200). Phase-offset horizontal
	# starts. Uniform rightward parallax advanced in _physics_process.
	_clouds = []
	var cloud_specs := [
		{"idx": 1, "size": 90.0,  "x": 80.0,  "y": 60.0,  "speed": 5.0,  "alpha": 0.55},
		{"idx": 3, "size": 200.0, "x": 320.0, "y": 100.0, "speed": 7.0,  "alpha": 0.70},
		{"idx": 5, "size": 140.0, "x": 540.0, "y": 180.0, "speed": 6.0,  "alpha": 0.50},
	]
	for spec in cloud_specs:
		var tex = load("res://assets/sprites/terrain/Decorations/Clouds_%02d.png" % spec.idx)
		if tex == null:
			continue
		# STRETCH_SCALE (not KEEP_ASPECT_CENTERED) so the explicit size wins
		# without needing a container wrapper. Slight aspect distortion is
		# imperceptible on a soft-edged cloud.
		var cloud := TextureRect.new()
		cloud.texture = tex
		cloud.size = Vector2(spec.size, spec.size * 0.55)
		cloud.position = Vector2(spec.x, spec.y)
		cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cloud.stretch_mode = TextureRect.STRETCH_SCALE
		cloud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cloud.modulate = Color(1, 1, 1, spec.alpha)
		cloud.set_meta("drift_speed", spec.speed)
		scene_layer.add_child(cloud)
		_clouds.append(cloud)

	# --- Castle centerpiece: anchored to the logo's bottom edge ---
	# Per user ask: "reuse the logo location, apply to castle, adjust downward".
	# Reading `old_logo.position.y + old_logo.size.y` gives the logo element's
	# BOTTOM (y=580 with current offsets). Castle top is pulled UP by 50 px so
	# it slips into the logo's transparent-padding zone (logo is aspect-fit
	# inside a 400×300 box so the actual artwork ends ~25 px above element
	# bottom). Castle's own top padding (native y=0..40 transparent) then lands
	# in the gap so the visible castle wall reads ~20 px below the logo.
	var castle_tex = load("res://assets/sprites/buildings/blue/Castle.png")
	if castle_tex:
		var castle_w: float = 240.0
		var castle_h: float = castle_w * (256.0 / 320.0)   # 192 (preserve 1.25 aspect)
		var logo_bottom: float = 580.0   # falls back to default
		var logo_x_center: float = 360.0
		var logo_ref := get_node_or_null("Logo")
		if logo_ref and logo_ref is Control:
			logo_bottom = (logo_ref as Control).position.y + (logo_ref as Control).size.y
			logo_x_center = (logo_ref as Control).position.x + (logo_ref as Control).size.x * 0.5
		# See tree-clump comment below: wrap in a fixed-size Control so size is
		# honored (EXPAND_IGNORE_SIZE only works inside a Container).
		var castle_box := Control.new()
		castle_box.position = Vector2(logo_x_center - castle_w * 0.5, logo_bottom - 50.0)
		castle_box.size = Vector2(castle_w, castle_h)
		castle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		castle_box.z_index = 5
		var castle := TextureRect.new()
		castle.texture = castle_tex
		castle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		castle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		castle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		castle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		castle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		castle_box.add_child(castle)
		scene_layer.add_child(castle_box)

	# --- Tree clumps on either side of the castle ---
	# Staggered depth: 3 trees per side, slightly different sizes, offset y
	# so they read as a grove not a line. z=-5 so they sit behind the castle
	# shoulder but in front of the plateau composite.
	# Only Tree3/Tree4: their bbox has symmetric ~50 px padding on left+right,
	# so when the texture is scaled into a container the tree reads as centered.
	# Tree1/Tree2 content goes to the texture's right edge (asymmetric padding)
	# which makes those trees look hard-cropped on the right side of their box.
	var tree_sheets: Array = []
	for i in [3, 4]:
		var tex = load("res://assets/sprites/terrain/Resources/Tree%d.png" % i)
		if tex:
			tree_sheets.append(tex)
	# 6 trees per side (12 total) at castle's y-range (530..720), clustered
	# BESIDE the castle as a clump. Sizes 130–150 match the prior visual scale
	# that was an accident of the EXPAND_IGNORE_SIZE bug. Back row (z=2,
	# slightly behind castle walls) + front row (z=4, in front of castle
	# shoulder). Left x-range 5..230 / right 490..715 keep a 5–10 px edge
	# buffer and 10 px gap to castle at x=240..480.
	# Positions with 30 px viewport buffer. Tree sheets have asymmetric bbox
	# padding (Tree1/2 content often spans to the right edge of the frame with
	# heavy left padding), so even with a container we end up with the tree
	# visually hugging the right side of its box. Only using Tree3/Tree4 below
	# (those have symmetric bbox ≈ 50 px padding on both sides) plus extra
	# viewport margin addresses user-reported "cropped trees".
	# Tight clusters: each side packs 6 trees into a ~160×210 zone so they
	# overlap and read as a grove, not a row. Back row (z=2) behind front row
	# (z=4). Horizontal spread ~15..175 (left) / ~545..705 (right) — a single
	# cohesive clump on each side of the castle at x=240..480.
	var tree_clumps := [
		# --- LEFT clump (6, packed within x=15..175, y=490..700) ---
		{"pos": Vector2(15, 495), "size": 130.0, "z": 2},
		{"pos": Vector2(75, 485), "size": 125.0, "z": 2},
		{"pos": Vector2(120, 505), "size": 115.0, "z": 2},
		{"pos": Vector2(5, 585), "size": 140.0, "z": 4},
		{"pos": Vector2(70, 595), "size": 130.0, "z": 4},
		{"pos": Vector2(125, 580), "size": 120.0, "z": 4},
		# --- RIGHT clump (6 — mirror around viewport center x=360) ---
		{"pos": Vector2(575, 495), "size": 130.0, "z": 2},
		{"pos": Vector2(520, 485), "size": 125.0, "z": 2},
		{"pos": Vector2(480, 505), "size": 115.0, "z": 2},
		{"pos": Vector2(575, 585), "size": 140.0, "z": 4},
		{"pos": Vector2(520, 595), "size": 130.0, "z": 4},
		{"pos": Vector2(475, 580), "size": 120.0, "z": 4},
	]
	# IMPORTANT: `TextureRect.EXPAND_IGNORE_SIZE` is only respected inside a
	# Container. Added to a bare Control, TextureRect falls back to the
	# texture's natural size (256×256 for Tree1/2, 192×192 for Tree3/4) — which
	# made the rightmost tree's element spill 150+ px past its intended right
	# edge and pulled the whole composition rightward. Wrap each sprite in a
	# fixed-size Control and anchor the TextureRect full-rect so the
	# container's size wins.
	for clump in tree_clumps:
		if tree_sheets.is_empty():
			break
		var sheet = tree_sheets[rng.randi() % tree_sheets.size()]
		var frame_size: int = sheet.get_height()
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(rng.randi_range(0, 3) * frame_size, 0, frame_size, frame_size)
		var box := Control.new()
		box.position = clump.pos
		box.size = Vector2(clump.size, clump.size)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.z_index = clump.z
		var spr := TextureRect.new()
		spr.texture = atlas
		spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(spr)
		scene_layer.add_child(box)

	# --- Multi-elevation plateau + water pond BELOW the castle (y=820..1020) ---
	_build_plateau(scene_layer)


# Multi-elevation plateau using Tilemap_color1.png (64×64 grid).
# Tile atlas layout (reference, x,y in atlas pixels):
#   Grass corners/edges (no cliff):  left half, rows 0..3 (x=0..255, y=0..255)
#   Grass with cliff bottom:         right half (x=320..575, y=0..319)
#   Cliff faces:                     right half row 4 (y=256..319)
# We pick a mixed composition to read like the reference reference map.
func _build_plateau(parent: Control) -> void:
	var atlas_tex = load("res://assets/sprites/terrain/Tilemap_color1.png")
	if atlas_tex == null:
		return
	# Tile display size: 48 px per tile (Tiny Swords 64 native × 0.75 scale).
	var ts: float = 48.0
	# Plateau composition: grass-top + grass-mid + stone-cliff, three rows.
	var top_y: float = 790.0
	var mid_y: float = 838.0
	var cliff_y: float = 886.0
	# Plateau is an ISLAND in a surrounding water plane. 11 cols (528 px)
	# centered in 720 viewport → 96 px of water visible on each side.
	var cols: int = 11
	var island_x: float = (720.0 - cols * ts) / 2.0   # 96
	# Water plane underneath plateau spans full width, aligned with plateau's
	# top..cliff vertical range so the cliff cleanly meets water edge.
	var water_tex = load("res://assets/sprites/terrain/Water Background color.png")
	if water_tex:
		var water := TextureRect.new()
		water.texture = water_tex
		water.position = Vector2(0, top_y + ts * 0.5)   # water "horizon" sits halfway up plateau top
		water.size = Vector2(720, 200)                   # to y≈1014, below bar
		water.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		water.stretch_mode = TextureRect.STRETCH_TILE
		water.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		water.modulate = Color(0.50, 0.78, 0.90, 1)  # bright cyan-blue
		water.z_index = -5   # above sky (-10), below plateau (-3)
		parent.add_child(water)

	# Helper closure writes a single tile.
	var add_tile := func(cx: int, py: float, atlas_x: int, atlas_y: int, z: int) -> void:
		var at := AtlasTexture.new()
		at.atlas = atlas_tex
		at.region = Rect2(atlas_x, atlas_y, 64, 64)
		var r := TextureRect.new()
		r.texture = at
		r.size = Vector2(ts, ts)
		r.position = Vector2(cx * ts + island_x, py)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.z_index = z
		parent.add_child(r)
	# Atlas tile coordinates (from right-half of Tilemap_color1):
	#   Top row (y=0)    — grass-top with cliff sides:  dark TOP edge, clean BOTTOM
	#   Mid row (y=128)  — grass-bottom with cliff sides: clean TOP, dark BOTTOM edge
	#   Cliff row (y=256) — pure cliff face
	#
	# User flagged prior composition showed a visible dark DIVISION mid-plateau.
	# Root cause: prior mid row used (_, 192) which has dark edges on BOTH top
	# AND bottom — its dark top stacked against the top row's (clean) bottom
	# created a double-line seam in the middle of the grass. Swapping to
	# (_, 128) gives clean top + dark bottom, so the two grass rows composite
	# as ONE rectangle with outlines only at the outer edges.
	#
	# Use x=384 (interior) for every column — x=320/x=512 variants bake a side
	# cliff column into the edge tile, which shows as an "extra border" on the
	# outer columns (user feedback 2026-04-22: "separate column far right /
	# extra left border"). Interior tiles give a clean straight grass block.
	for col in range(cols):
		# Top row — dark top edge (grass outline), clean bottom
		add_tile.call(col, top_y, 384, 0, -3)
		# Mid row — clean top (merges seamlessly with top row), dark bottom edge
		add_tile.call(col, mid_y, 384, 128, -3)
		# Cliff face
		add_tile.call(col, cliff_y, 384, 256, -2)

	# Water Foam is a LOCALIZED wave-blob sprite (frame 0 opaque content at y=58..141
	# in the 192×192 tile — everything else is transparent). Stretching it into a
	# thin strip renders the transparent top rows and nothing visible; tiling it
	# distorts the wave shape. Correct use is to place individual foam blobs along
	# the shoreline. All blobs share one AtlasTexture so they animate in sync.
	# Content-safe region margin: content drifts y=58..148 across the 16 frames,
	# so we crop to y=56..150 (h=94) with a small safety buffer.
	var foam_tex = load("res://assets/sprites/terrain/Water Foam.png")
	if foam_tex:
		var foam_region_y: int = 56
		var foam_region_h: int = 94
		var foam_atlas := AtlasTexture.new()
		foam_atlas.atlas = foam_tex
		foam_atlas.region = Rect2(0, foam_region_y, 192, foam_region_h)
		# CONTINUOUS foam shoreline per Tiny Swords reference — the foam hugs
		# the cliff outline as an unbroken line, not discrete splashes.
		# Math: content in source is ~86 px wide inside each 192-px frame (45%
		# of blob width). To make adjacent blobs' content touch at cliff-tile
		# spacing (48 px), each blob display must satisfy content_w ≥ 48, i.e.
		# blob_w × (86/192) ≥ 48 → blob_w ≥ 107. Using 120 gives ~54 px content
		# → 6 px overlap between adjacent blobs → truly continuous. One blob
		# per cliff tile (11 total) centered on its tile with an additional
		# LEFT shift so the foam line aligns to the cliff-stone seams rather
		# than mid-tile gaps. Y: blob center 16 px up into the cliff rect so
		# only the thin bottom edge peeks below as shoreline trim.
		var foam_display: float = 120.0
		var foam_center_y: float = cliff_y + ts - 16.0  # 918 design — 16 px up into cliff
		# Shift LEFT so foam row aligns with cliff span: at shift=10, left gap was
		# 14 px (foam started inside the cliff) and right overshoot was 21 px
		# (foam extended into open water past the cliff right edge). Shifting
		# left by another ~17 px centers the foam span over the cliff span.
		var foam_left_shift: float = 27.0
		for tile_i in range(cols):
			var tile_center_x: float = island_x + tile_i * ts + ts * 0.5
			var fx: float = tile_center_x - foam_display * 0.5 - foam_left_shift
			var fy: float = foam_center_y - foam_display * 0.5
			_add_foam_blob(parent, foam_atlas, Vector2(fx, fy), Vector2(foam_display, foam_display))
		_animate_foam_atlas(foam_atlas, foam_region_y, foam_region_h)


func _add_foam_blob(parent: Control, shared_atlas: AtlasTexture,
		pos: Vector2, size: Vector2) -> void:
	var blob := TextureRect.new()
	blob.texture = shared_atlas
	blob.position = pos
	blob.size = size
	blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blob.stretch_mode = TextureRect.STRETCH_SCALE
	blob.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.modulate = Color(1, 1, 1, 0.9)
	# z=-4 sits the foam between water (-5) and plateau tiles (grass=-3, cliff=-2)
	# so the cliff face renders ON TOP of the foam. Only the lower half of each
	# blob (the half below the cliff base) stays visible in the water — reads as
	# wave lapping at the base of the cliff, not on top of it.
	blob.z_index = -4
	parent.add_child(blob)


# Cycles a shared AtlasTexture through its 16 frames at 20 fps. Preserves the
# content-crop Y offset so we don't rerender the transparent outer margins.
func _animate_foam_atlas(shared_atlas: AtlasTexture, region_y: int, region_h: int) -> void:
	var tw := create_tween().set_loops()
	for i in range(16):
		tw.tween_callback(func():
			if shared_atlas != null:
				shared_atlas.region = Rect2(i * 192, region_y, 192, region_h)
		)
		tw.tween_interval(0.05)


var _clouds: Array = []


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _go_to_menu() -> void:
	SceneTransition.change_scene("res://scenes/ui/main_menu.tscn")


# Parallax cloud drift: advances each cloud's X by drift_speed * delta,
# wrapping from right edge back to left. Uniform rightward 8 px/s per spec.
func _physics_process(delta: float) -> void:
	for c in _clouds:
		if not is_instance_valid(c):
			continue
		var speed: float = c.get_meta("drift_speed", 8.0)
		c.position.x += speed * delta
		if c.position.x > 720.0 + 20.0:
			c.position.x = -c.size.x - 20.0
