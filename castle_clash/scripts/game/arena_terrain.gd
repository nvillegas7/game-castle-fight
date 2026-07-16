class_name ArenaTerrain
extends RefCounted

# --- Terrain Decorations ---
# Extracted verbatim from game_arena.gd (pure refactor). All functions are static;
# the `arena` param is the GameArena node (untyped — game_arena.gd has no class_name).

## Extract a single frame from a horizontal sprite sheet.
## Detects frame width automatically — handles both square and non-square frames.
static func _extract_sprite_frame(sheet: Texture2D, frame: int) -> AtlasTexture:
	var w: int = sheet.get_width()
	var h: int = sheet.get_height()
	# Find the actual frame width: try common frame counts and pick the one
	# where frame_width <= height and divides width evenly.
	var frame_w: int = h  # Default: square frames
	if w > h:
		# Try frame counts 8, 6, 4, 16, 12 — pick first where frame_w <= h
		for try_count in [8, 6, 16, 4, 12]:
			if w % try_count == 0:
				var fw: int = w / try_count
				if fw <= h:
					frame_w = fw
					break
	var frame_count: int = maxi(1, w / frame_w)
	var actual_frame: int = clampi(frame, 0, frame_count - 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(actual_frame * frame_w, 0, frame_w, h)
	return atlas


## Load texture with fallback to raw PNG for un-imported files.
static func _load_texture_safe(path: String) -> Texture2D:
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


## Polish arena visuals: fix symmetry, darken water, add grass texture variation.
## These overrides run at startup and survive scene file edits by other agents.
static func polish(arena) -> void:
	# Fix castle symmetry: both castles 55px from their grass edge
	# Enemy: y=55-120 (55px from top at y=0). Player must match: y=890-955 (55px from bottom at y=1010)
	var castle0 = arena.get_node_or_null("CastleArea0")
	if castle0 and castle0 is ColorRect:
		castle0.offset_top = 890
		castle0.offset_bottom = 955
	var hp_bg0 = arena.get_node_or_null("CastleHPBarBg0")
	if hp_bg0:
		hp_bg0.offset_top = 880
		hp_bg0.offset_bottom = 890
	var hp_bar0 = arena.get_node_or_null("CastleHPBar0")
	if hp_bar0:
		hp_bar0.offset_top = 882
		hp_bar0.offset_bottom = 888

	# Gold bar — YELLOW Tiny Swords ribbon (reference). The top HUD strip is now
	# transparent (bars + TIME banner float over the arena), so there is no HUD ribbon.
	var ribbon_tex: Texture2D = _load_texture_safe("res://assets/sprites/ui/ninepatch/ribbon_yellow.png")

	if ribbon_tex:
		var gold_bg = arena.get_node_or_null("UILayer/GoldBarBg")
		if gold_bg and gold_bg is ColorRect:
			(gold_bg as ColorRect).color = Color(0, 0, 0, 0)  # ribbon carries the strip
			var gold_ribbon := NinePatchRect.new()
			gold_ribbon.texture = ribbon_tex
			gold_ribbon.patch_margin_left = 98
			gold_ribbon.patch_margin_right = 97
			gold_ribbon.patch_margin_top = 0
			gold_ribbon.patch_margin_bottom = 0
			gold_ribbon.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
			gold_ribbon.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
			gold_ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			gold_ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
			gold_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gold_bg.add_child(gold_ribbon)
			gold_bg.move_child(gold_ribbon, 0)

	# Hide the old flat ColorRect fill/track/lines — replaced by the textured elixir bar below.
	for old_name in ["GoldBarFill", "GoldBarTrack", "GoldBarTopLine", "GoldBarBottomLine"]:
		var old_node = arena.get_node_or_null("UILayer/GoldBarBg/" + old_name)
		if old_node:
			old_node.visible = false

	# Coin + amount centered as a group on the ribbon (reference — no fill meter).
	var gold_bg = arena.get_node_or_null("UILayer/GoldBarBg")
	var gold_label = arena.get_node_or_null("UILayer/GoldBarBg/GoldBarLabel")
	if gold_label and gold_label is Label:
		var l := gold_label as Label
		l.offset_left = 300.0   # centered group: coin sits just left of the text
		l.offset_right = 680.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var coin_icon: Texture2D = SpriteRegistry.get_ui_texture(&"Icon_03")
	if coin_icon and gold_bg:
		var coin := Sprite2D.new()
		coin.texture = coin_icon
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.centered = true
		coin.scale = Vector2(24.0 / coin_icon.get_height(), 24.0 / coin_icon.get_height())
		coin.position = Vector2(285.0, 25.0)  # left of the amount text; tuned vs reference
		coin.z_index = 3
		gold_bg.add_child(coin)

	# Tiny Swords wood table on card hand — NinePatchRect
	var wood_tex: Texture2D = _load_texture_safe("res://assets/sprites/ui/ninepatch/woodtable.png")
	if wood_tex:
		var card_bg = arena.get_node_or_null("UILayer/CardHand/CardBg")
		if card_bg and card_bg is ColorRect:
			card_bg.color = Color(0.35, 0.25, 0.15, 1)
			var wood := NinePatchRect.new()
			wood.texture = wood_tex
			wood.patch_margin_left = 84
			wood.patch_margin_right = 84
			wood.patch_margin_top = 85
			wood.patch_margin_bottom = 103
			wood.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
			wood.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
			wood.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wood.set_anchors_preset(Control.PRESET_FULL_RECT)
			card_bg.add_child(wood)
	# Top HUD strip is transparent (reference): no ribbon here — hud.gd's wood-framed
	# HP bars + the centered TIME banner float directly over the arena. HUDBg is set
	# transparent in the scene; the hidden HBox text is left in place (inert).

	# CombatLane hidden entirely — terrain tiles (T-060) handle the combat zone visual.
	var combat_lane = arena.get_node_or_null("CombatLane")
	if combat_lane:
		combat_lane.visible = false

	# Design-flow port (design/arena_target.png is the spec): water is the NATIVE
	# Tiny Swords teal — the old modulate tints turned (71,171,169) into a murky
	# (28,86,93) gutter, the single largest palette divergence from the mockups.
	# WaterBase now paints the full screen in the native texel color (the water
	# tile is perfectly flat, std=0, so a ColorRect is pixel-identical to tiling
	# it); the old 45px straight TextureRect strips are hidden.
	var water_base = arena.get_node_or_null("WaterBase")
	if water_base:
		water_base.color = Color8(71, 171, 169)
	var water_left = arena.get_node_or_null("WaterLeft")
	if water_left:
		water_left.visible = false
	var water_right = arena.get_node_or_null("WaterRight")
	if water_right:
		water_right.visible = false
	# GrassMain shrinks to sit exactly under the tiled platform (fallback fill);
	# its dark edge children belonged to the old full-bleed rectangle.
	var grass_main = arena.get_node_or_null("GrassMain")
	if grass_main:
		grass_main.position = Vector2(72, 56)
		grass_main.size = Vector2(576, 896)
		for child in grass_main.get_children():
			child.visible = false


# --- T-060: Kingdom Rush 3-Layer Terrain ---

static func build_textures(arena) -> void:
	# Design-flow port of design/arena_target.png (the approved pixel spec, built
	# by tools/compose_arena.py from these same assets — see tasks/design-flow.md).
	# Values below mirror the compositor's LAYOUT table verbatim; change the look
	# THERE first (0.1s/render), re-approve, then port the numbers here.
	var tm1 = load("res://assets/sprites/terrain/Tilemap_color1.png")  # sunny green
	if tm1 == null:
		return

	var terrain_layer := Node2D.new()
	terrain_layer.z_index = 0
	terrain_layer.name = "TilemapTerrain"
	arena.add_child(terrain_layer)
	# Move after GrassMain+CombatLane so tiles render on top of base colors
	var grass_node = arena.get_node_or_null("GrassMain")
	if grass_node:
		arena.move_child(terrain_layer, grass_node.get_index() + 1)

	var ts: float = 64.0

	# Grass ISLAND PLATFORM on native-teal water: x=[72,648] y=[72,968] (9x14
	# tiles) with proper 3x3 edge/corner tiles. The y-span mirrors EXACTLY about
	# FLIP_PIVOT_Y=520 (72+968=1040) so the multiplayer perspective flip shows
	# both players an identical island. Uniform center tile (per-tile hue mixing
	# betrays the 64px grid — lessons.md 2026-07-07); variation = decoration.
	_build_tiled_zone(terrain_layer, tm1, Rect2(72, 72, 576, 896), 1.0, ts, Color.WHITE)

	_add_fortress_dressing(terrain_layer, tm1, ts)

	_add_water_foam(arena)


## Integrated castle cliff base (design/arena_target.png; CASTLE-CLIFF 2026-07-14).
## PORT of compose_arena.py cliff_base: a continuous castle-width stone cliff band
## directly under each castle's SOUTH foot — a grass rim lip (tile col6,row3) caps
## the top, a stone FACE (tile col6,row4) drops one tile below. The castle (drawn on
## a higher layer) sits ON the band so its own stone foot merges into the cliff and
## the two read as one raised mound (replaces the old waist-height full-width fence).
## PERSPECTIVE-LOCKED (user feedback 2026-07-08): the face points SOUTH on BOTH halves
## and is NEVER flipped. LAYOUT: cx=360; 3 tiles wide (x0 = cx - 96); stone top edge
## red=132 / blue=958 (see the castle_visual-offset note on the loop below); blue is a
## short sea-cliff, mostly under the card-hand HUD.
static func _add_fortress_dressing(parent: Node2D, tm: Texture2D, ts: float) -> void:
	if tm == null:
		return
	var lip := AtlasTexture.new()
	lip.atlas = tm
	lip.region = Rect2(6 * 64, 3 * 64, 64, 64)   # grass-edge rim tile (col6,row3)
	var stone := AtlasTexture.new()
	stone.atlas = tm
	stone.region = Rect2(6 * 64, 4 * 64, 64, 64)  # stone cliff face tile (col6,row4)
	var n: int = 3
	# Game edges differ from the compositor's (red 163 / blue 967) by the castle_visual
	# offset: castle_visual.gd renders the castle ~20px HIGHER than compose_arena.py's
	# CASTLE_CENTERS assume (measured game red content-foot = design ~147 vs compositor
	# 167). The cliff top must sit ABOVE the foot so the castle hides the tile's grass
	# fringe and the stone emerges merged with the castle's own stone foundation — hence
	# red edge=132 (stone body ~140 overlaps the ~147 foot); blue=958 (its south face is
	# under the card-hand HUD, perspective-locked, so mostly occluded).
	for edge in [132.0, 958.0]:
		var x0: float = 360.0 - n * ts / 2.0
		for i in n:
			var x: float = x0 + i * ts
			for pair in [[lip, edge - ts], [stone, edge]]:
				var spr := Sprite2D.new()
				spr.texture = pair[0]
				spr.centered = false
				spr.position = Vector2(x, pair[1])
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				parent.add_child(spr)


## Build a tiled zone using flat ground tiles (cols 0-3) with proper edges
static func _build_tiled_zone(parent: Node2D, atlas: Texture2D, rect: Rect2, tile_s: float, ts: float, tint: Color) -> void:
	var cols: int = ceili(rect.size.x / ts)
	var rows: int = ceili(rect.size.y / ts)

	for row in rows:
		for col in cols:
			var gx: int  # Grid col in tilemap (0-3)
			var gy: int  # Grid row in tilemap (0-3)

			# Determine which tile to use based on position (edge detection)
			var is_top: bool = (row == 0)
			var is_bot: bool = (row == rows - 1)
			var is_left: bool = (col == 0)
			var is_right: bool = (col == cols - 1)

			if is_top and is_left:
				gx = 0; gy = 0  # TL corner
			elif is_top and is_right:
				gx = 2; gy = 0  # TR corner
			elif is_bot and is_left:
				gx = 0; gy = 2  # BL corner
			elif is_bot and is_right:
				gx = 2; gy = 2  # BR corner
			elif is_top:
				gx = 1; gy = 0  # Top edge
			elif is_bot:
				gx = 1; gy = 2  # Bottom edge
			elif is_left:
				gx = 0; gy = 1  # Left edge
			elif is_right:
				gx = 2; gy = 1  # Right edge
			else:
				gx = 1; gy = 1  # Center fill

			var tile := AtlasTexture.new()
			tile.atlas = atlas
			tile.region = Rect2(gx * 64, gy * 64, 64, 64)

			var spr := Sprite2D.new()
			spr.texture = tile
			spr.centered = false
			spr.position = Vector2(rect.position.x + col * ts, rect.position.y + row * ts)
			spr.scale = Vector2(tile_s, tile_s)
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.modulate = tint
			parent.add_child(spr)


static func _add_water_foam(arena) -> void:
	var foam_tex = load("res://assets/sprites/terrain/Water Foam.png")
	if foam_tex == null:
		return
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"foam")
	sf.set_animation_speed(&"foam", 6)
	sf.set_animation_loop(&"foam", true)
	var fs: int = foam_tex.get_height()
	var fc: int = foam_tex.get_width() / fs
	for i in fc:
		var atlas := AtlasTexture.new()
		atlas.atlas = foam_tex
		atlas.region = Rect2(i * fs, 0, fs, fs)
		sf.add_frame(&"foam", atlas)

	# Foam dashes hugging the island coastline on ALL FOUR edges (design/
	# arena_target.png): staggered small dashes, near-opaque, animated. Each foam
	# sprite keeps a small alpha-phase offset so the shoreline "breathes"
	# (±0.15 around a 0.85 base in physics_process).
	arena._ambient_foams.clear()
	var dash_specs: Array = []
	var idx: int = 0
	for x_pos in range(72, 600, 60):  # top + bottom coasts
		var jig: float = 8.0 if idx % 2 == 0 else -5.0
		dash_specs.append([Vector2(x_pos + 30 + jig, 86), false, false])
		dash_specs.append([Vector2(x_pos + 30 - jig, 972), false, true])
		idx += 1
	idx = 0
	for y_pos in range(72, 920, 60):  # left + right coasts
		var jig: float = 9.0 if idx % 2 == 0 else -6.0
		dash_specs.append([Vector2(70, y_pos + 30 + jig), false, false])
		dash_specs.append([Vector2(650, y_pos + 30 - jig), true, false])
		idx += 1
	for spec in dash_specs:
		var foam := AnimatedSprite2D.new()
		foam.sprite_frames = sf
		foam.position = spec[0]
		foam.scale = Vector2(0.32, 0.32)
		foam.flip_h = spec[1]
		foam.flip_v = spec[2]
		foam.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		foam.modulate = Color(1.0, 1.0, 1.0, 0.85)
		foam.z_index = -1
		foam.play(&"foam")
		foam.frame = randi() % fc
		arena.add_child(foam)
		foam.set_meta("breath_phase", randf() * TAU)
		arena._ambient_foams.append(foam)


static func setup_decorations(arena) -> void:
	# Design-flow port of design/arena_target.png — mirrors the compositor's
	# LAYOUT tables VERBATIM (tools/compose_arena.py). Change the look there
	# first (0.1s/render), re-approve, then port the numbers here.
	#
	# SYMMETRY BY CONSTRUCTION (user feedback 2026-07-08): decorations are
	# authored for the LEFT side of the ENEMY half only; right side = x-mirror
	# (720-x, same y), player half = y-mirror about FLIP_PIVOT_Y. The multiplayer
	# perspective flip therefore shows both players an identical arena.
	#
	# Y-SORTED: every decoration is ground-anchored (position = ground point,
	# sprite offset lifts the art) and the layer y-sorts, so sheep never float
	# on tree canopies and units interleave correctly.
	var deco_base := "res://assets/sprites/terrain/"

	var deco_layer := Node2D.new()
	deco_layer.z_index = 0
	deco_layer.y_sort_enabled = true
	deco_layer.name = "DecorationLayer"
	arena.add_child(deco_layer)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Deterministic phase staggering for animations

	# 4-way symmetric expansion helper: [L, R, L-mirrored, R-mirrored]
	var all4 := func(cx: float, gy: float) -> Array:
		return [Vector2(cx, gy), Vector2(720.0 - cx, gy),
			Vector2(cx, 2.0 * arena.FLIP_PIVOT_Y - gy), Vector2(720.0 - cx, 2.0 * arena.FLIP_PIVOT_Y - gy)]

	# --- Fortress towers + corner houses (y-sorted vs sheep/trees) ---
	# Enemy half red, player half blue; LAYOUT: Tower @(140,268) s=0.72,
	# House1 @(122,148) s=0.62 (all four corners via mirroring).
	for spec in [[false, "red"], [true, "blue"]]:
		var flip: bool = spec[0]
		var team_dir: String = spec[1]
		for d in [["Tower.png", 140.0, 268.0, 0.72], ["Tower.png", 580.0, 268.0, 0.72],
				["House1.png", 122.0, 148.0, 0.62], ["House1.png", 598.0, 148.0, 0.62]]:
			var tex: Texture2D = load("res://assets/sprites/buildings/%s/%s" % [team_dir, d[0]])
			if tex == null:
				continue
			var gy: float = d[2] if not flip else 2.0 * arena.FLIP_PIVOT_Y - d[2]
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.position = Vector2(d[1], gy)
			spr.offset = Vector2(0, -tex.get_height() * 0.5)  # bottom-anchored
			spr.scale = Vector2(d[3], d[3])
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			deco_layer.add_child(spr)

	# --- Trees: LAYOUT TREES_L = [(110,428,3),(110,580,2)], 4-way mirrored ---
	var tree_sheets: Array[Texture2D] = []
	for i in range(1, 5):
		var path: String = deco_base + "Resources/Tree%d.png" % i
		if ResourceLoader.exists(path):
			tree_sheets.append(load(path))
	if not tree_sheets.is_empty():
		for cl in [[128.0, 428.0, 3], [128.0, 580.0, 2]]:
			for k in int(cl[2]):
				var sheet: Texture2D = tree_sheets[k % tree_sheets.size()]
				var fh: int = int(sheet.get_height())
				# Tree strips are 8 frames of 192px WIDTH (Tree1/2 are 192x256,
				# NON-square) — the old square fh-wide crop bled a sliver of the
				# next frame in: the "floating fir fragments" bug (2026-07-10).
				var fw: int = sheet.get_width() / 8
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(0, 0, fw, fh)
				var dx: float = (k - cl[2] / 2.0) * 26.0 + 13.0
				var dy: float = (k % 2) * 26.0
				for pos in all4.call(cl[0] + dx, cl[1] + dy):
					var spr := Sprite2D.new()
					spr.texture = at
					spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					spr.scale = Vector2(0.52, 0.52)
					spr.position = pos
					spr.offset = Vector2(0, -fh * 0.5)  # ground-anchored, sways from base
					deco_layer.add_child(spr)
					var sway := spr.create_tween().set_loops()
					var sdur: float = rng.randf_range(2.6, 3.8)
					var samp: float = deg_to_rad(rng.randf_range(1.5, 3.0))
					sway.tween_interval(rng.randf_range(0.0, sdur))
					sway.tween_property(spr, "rotation", samp, sdur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
					sway.tween_property(spr, "rotation", -samp, sdur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# --- Bushes: LAYOUT BUSH_L = [(170,250)], 4-way ---
	var bush_path: String = deco_base + "Decorations/Bushe1.png"
	if ResourceLoader.exists(bush_path):
		var bsheet: Texture2D = load(bush_path)
		for pos in all4.call(170.0, 250.0):
			var spr := Sprite2D.new()
			spr.texture = _extract_sprite_frame(bsheet, 0)
			spr.position = pos
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(0.5, 0.5)
			var tex_size: Vector2 = spr.texture.get_size() if spr.texture else Vector2(32, 32)
			spr.offset = Vector2(0, -tex_size.y * 0.5)
			deco_layer.add_child(spr)
			var sway_tw := spr.create_tween().set_loops()
			var sway_dur: float = rng.randf_range(1.8, 2.8)
			var sway_amp: float = deg_to_rad(rng.randf_range(3.0, 5.0))
			sway_tw.tween_interval(rng.randf_range(0.0, sway_dur))
			sway_tw.tween_property(spr, "rotation", sway_amp, sway_dur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			sway_tw.tween_property(spr, "rotation", -sway_amp, sway_dur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# --- Midfield rock accents: POINT-mirrored pair (340,508)/(380,532) ---
	var rock_path: String = deco_base + "Decorations/Rock1.png"
	if ResourceLoader.exists(rock_path):
		for pos in [Vector2(340, 508), Vector2(380, 532)]:
			var spr := Sprite2D.new()
			spr.texture = load(rock_path)
			spr.position = pos
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(0.4, 0.4)
			deco_layer.add_child(spr)

	# --- Water rocks: LAYOUT WROCK_L = [(40,300,1),(34,470,3)], 4-way, bob ---
	for wr in [[40.0, 300.0, 1], [34.0, 470.0, 3]]:
		var path: String = deco_base + "Decorations/Water Rocks_%02d.png" % int(wr[2])
		if not ResourceLoader.exists(path):
			continue
		var sheet: Texture2D = load(path)
		var frame_count: int = maxi(1, sheet.get_width() / sheet.get_height())
		for pos in all4.call(wr[0], wr[1]):
			var spr := Sprite2D.new()
			spr.texture = _extract_sprite_frame(sheet, int(wr[2]) % frame_count)
			spr.position = pos
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(0.5, 0.5)
			deco_layer.add_child(spr)
			var bob_dur: float = rng.randf_range(3.0, 5.0)
			var bob_amp: float = rng.randf_range(2.0, 3.0)
			var bob_tw := spr.create_tween().set_loops()
			bob_tw.tween_interval(rng.randf_range(0.0, bob_dur))
			bob_tw.tween_property(spr, "position:y", pos.y + bob_amp, bob_dur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bob_tw.tween_property(spr, "position:y", pos.y - bob_amp, bob_dur * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# --- Gold: LAYOUT GOLD_L = [(188,505)], 3 nuggets, 4-way ---
	for k in 3:
		var gold_path: String = deco_base + "Resources/Gold Stone %d.png" % ((k % 6) + 1)
		if not ResourceLoader.exists(gold_path):
			continue
		var gtex: Texture2D = load(gold_path)
		for pos in all4.call(188.0 + (k - 1) * 30.0, 505.0 + (k % 2) * 14.0):
			var spr := Sprite2D.new()
			spr.texture = gtex
			spr.position = pos
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(0.55, 0.55)
			deco_layer.add_child(spr)

	# --- Sheep: LAYOUT SHEEP_L = [(190,350),(190,620)], 4-way, ground-anchored ---
	var sheep_tex = load(deco_base + "Resources/Sheep_Grass.png")
	if sheep_tex:
		var sheep_sf := SpriteFrames.new()
		if sheep_sf.has_animation(&"default"):
			sheep_sf.remove_animation(&"default")
		sheep_sf.add_animation(&"graze")
		sheep_sf.set_animation_speed(&"graze", 6)
		sheep_sf.set_animation_loop(&"graze", true)
		var sh_fh: int = sheep_tex.get_height()
		var sh_fc: int = sheep_tex.get_width() / sh_fh
		for si in sh_fc:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheep_tex
			atlas.region = Rect2(si * sh_fh, 0, sh_fh, sh_fh)
			sheep_sf.add_frame(&"graze", atlas)
		for sl in [[190.0, 350.0], [190.0, 620.0]]:
			for pos in all4.call(sl[0], sl[1]):
				var sheep := AnimatedSprite2D.new()
				sheep.sprite_frames = sheep_sf
				sheep.position = pos
				# Ground-anchor: sheep art sits ~75% down its frame; lift so the
				# wool base lands on position.y (correct y-sort vs trees/towers).
				sheep.offset = Vector2(0, -sh_fh * 0.25)
				sheep.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sheep.scale = Vector2(0.55, 0.55)
				sheep.flip_h = pos.x > 360.0  # face inward
				sheep.play(&"graze")
				sheep.frame = rng.randi() % sh_fc
				deco_layer.add_child(sheep)
				var sb := sheep.create_tween().set_loops()
				var sbd: float = rng.randf_range(2.2, 3.4)
				sb.tween_interval(rng.randf_range(0.0, sbd))
				sb.tween_property(sheep, "position:y", pos.y + 2.0, sbd * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				sb.tween_property(sheep, "position:y", pos.y - 2.0, sbd * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# --- Rubber duck easter egg (kept; drifts in the left channel) ---
	var duck_tex = load(deco_base + "Decorations/Rubber duck.png")
	if duck_tex:
		var duck_sf := SpriteFrames.new()
		if duck_sf.has_animation(&"default"):
			duck_sf.remove_animation(&"default")
		duck_sf.add_animation(&"swim")
		duck_sf.set_animation_speed(&"swim", 3)
		duck_sf.set_animation_loop(&"swim", true)
		var duck_frame_w: int = duck_tex.get_height()
		var duck_fc: int = duck_tex.get_width() / duck_frame_w
		for di in duck_fc:
			var atlas := AtlasTexture.new()
			atlas.atlas = duck_tex
			atlas.region = Rect2(di * duck_frame_w, 0, duck_frame_w, duck_frame_w)
			duck_sf.add_frame(&"swim", atlas)
		var duck := AnimatedSprite2D.new()
		duck.sprite_frames = duck_sf
		duck.position = Vector2(36, rng.randf_range(430, 560))
		duck.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		duck.scale = Vector2(0.6, 0.6)
		duck.play(&"swim")
		deco_layer.add_child(duck)
		var duck_tw := duck.create_tween().set_loops()
		duck_tw.tween_property(duck, "position:y", duck.position.y + 4, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		duck_tw.tween_property(duck, "position:y", duck.position.y - 4, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var drift_tw := duck.create_tween().set_loops()
		drift_tw.tween_property(duck, "position:x", duck.position.x + 8, 6.0)
		drift_tw.tween_property(duck, "position:x", duck.position.x - 2, 6.0)
