## Main game scene controller. Manages the arena, building and unit visuals,
## and wires UI to the grid overlay.
extends Node2D

const UnitVisualScript = preload("res://scripts/game/unit_visual.gd")
const SpriteUnitVisualScript = preload("res://scripts/game/sprite_unit_visual.gd")
const BuildingVisualScript = preload("res://scripts/game/building_visual.gd")
const SpriteBuildingVisualScript = preload("res://scripts/game/sprite_building_visual.gd")

# Portrait layout (720x1280)
const CELL_SIZE: int = 28
const GRID_COLS: int = 11
const GRID_ROWS: int = 10

# Vertical zones
const HUD_H: int = 50
const ENEMY_ZONE_Y: int = 55
const ENEMY_ZONE_H: int = 290      # y=55-345
const COMBAT_Y: int = 350
const COMBAT_H: int = 340           # y=350-690
const PLAYER_ZONE_Y: int = 695
const PLAYER_ZONE_H: int = 290      # y=695-985
const GOLD_BAR_Y: int = 990
const CARD_HAND_Y: int = 1040

# Horizontal grid centering
const GRID_W: int = 11 * 28         # 308px
const GRID_MARGIN_X: int = 206      # (720 - 308) / 2

@onready var grid_overlay_0: Node2D = $BuildZone0/GridOverlay
@onready var grid_overlay_1: Node2D = $BuildZone1/GridOverlay
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var units_layer: Node2D = $UnitsLayer
@onready var card_hand: Control = $UILayer/CardHand
@onready var gold_bar_label: Label = $UILayer/GoldBarBg/GoldBarLabel
@onready var camera: Camera2D = $Camera2D

# 1.0 = arena exactly fills the 720x1280 viewport. Below 1.0 would reveal void
# beyond the arena, so zoom only goes IN from the default.
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 2.0
const ZOOM_SPEED: float = 0.1
const PAN_SPEED_KEYS: float = 600.0  # Pixels per second when panning with keys
var _zoom_level: float = 1.0

# Camera pan state (middle-click drag)
var _camera_pan_dragging: bool = false
var _camera_pan_last_pos: Vector2 = Vector2.ZERO
const CAMERA_HOME: Vector2 = Vector2(360, 640)

# T-085: CR-standard perspective flip. Player 2 sees the arena Y-reflected
# so they build at the bottom of their screen (same as Player 1's view).
# Simulation coordinates are unchanged — only the visual layer transforms.
var view_flipped: bool = false
const FLIP_PIVOT_Y: float = 520.0  # (55 + 985) / 2 = midpoint of play area


## Transform simulation coordinates → screen coordinates.
## When view_flipped, reflects Y around FLIP_PIVOT_Y.
func sim_to_screen(pos: Vector2) -> Vector2:
	if not view_flipped:
		return pos
	return Vector2(pos.x, FLIP_PIVOT_Y * 2.0 - pos.y)


## Transform screen coordinates → simulation coordinates.
## Reflection is its own inverse — same math as sim_to_screen.
func screen_to_sim(pos: Vector2) -> Vector2:
	return sim_to_screen(pos)

var _building_visuals: Dictionary = {}  # entity_id -> Node2D
var _unit_visuals: Dictionary = {}      # entity_id -> Node2D
var _unit_dust_timers: Dictionary = {}  # entity_id -> float (countdown)

# Ambient background elements driven in _physics_process — uniform cloud
# parallax + water-foam alpha breathing. Pure visual, no mechanics impact.
var _ambient_clouds: Array = []
var _ambient_foams: Array = []
var _ambient_time: float = 0.0

# T-043: Ability buttons
var _ability_buttons: Dictionary = {}   # building_id -> Control
var _ability_container: HBoxContainer = null

const ROLE_CHARS := ["M", "R", "C", "F", "S"]  # Melee, Ranged, Caster, Flying, Siege

# --- Simple AI for player 1 ---
const AI_PLAYER_ID: int = 1
const AI_THINK_INTERVAL: float = 3.0  # Seconds between AI decisions
var _ai_timer: float = 2.0  # Start slightly earlier so AI places before first wave
var ai_disabled: bool = false  # Set by video test to suppress AI building
# view_flipped declared above with T-085 transform helpers (line 52)


@onready var wave_label: Label = $UILayer/WaveAnnouncement

var _wave_announce_timer: float = 0.0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _original_position: Vector2 = Vector2.ZERO
var _prev_gold: int = 0


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.wave_started.connect(_on_wave_announced)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_healed.connect(_on_unit_healed)
	EventBus.castle_damaged.connect(_on_castle_hit)
	EventBus.skill_activated.connect(_on_skill_activated)
	# T-090 Castle Wrath — HUD button + shockwave VFX
	EventBus.castle_wrath_ready.connect(_on_castle_wrath_ready)
	EventBus.castle_wrath_activated.connect(_on_castle_wrath_activated)
	# 1D-1: special-building ability activations (both teams) → ring + SFX
	EventBus.ability_activated.connect(_on_ability_activated)
	# CR-standard: handle mid-match disconnect and desync
	EventBus.match_aborted.connect(_on_match_aborted)
	EventBus.desync_detected.connect(_on_desync_detected)

	grid_overlay_0.player_index = 0
	grid_overlay_1.player_index = 1

	card_hand.building_selected.connect(_on_building_selected)
	grid_overlay_0.building_deselected.connect(card_hand.force_deselect)
	grid_overlay_1.building_deselected.connect(card_hand.force_deselect)
	_original_position = position

	# Default camera: full arena view, both castles visible
	_zoom_level = 1.0
	view_flipped = false
	if camera:
		camera.zoom = Vector2.ONE
		camera.position = Vector2(360, 640)

	if wave_label:
		wave_label.visible = false

	_build_terrain_textures()
	_setup_terrain_decorations()
	_polish_arena_visuals()

	# T-080: Only start a test match if we arrived here offline. Online matches
	# are initialized by NetworkManager._begin_match before the scene change;
	# calling start_test_match again would overwrite the networked simulation.
	if GameManager.state != GameManager.State.PLAYING:
		GameManager.start_test_match()
	else:
		# Online match: simulation was initialized before this scene loaded, so
		# match_started was emitted before card_hand/building_menu connected
		# their handlers. Re-emit now (children _ready fires before parent).
		EventBus.match_started.emit()

	# T-085: Set perspective flip based on player index. Player 1 (index 1) sees
	# the arena Y-reflected so they build at bottom (same view as Player 0).
	if GameManager.simulation:
		var local_idx: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
		view_flipped = (local_idx == 1)
	if view_flipped:
		_apply_perspective_flip()

	SFX.play_music("battle_theme")
	SFX.start_ambient()  # T-030: Ambient battlefield sounds

	# T-054: Show selected perk on battle screen
	_show_perk_indicator()

	# Tutorial disabled 2026-04-14 — was blocking interaction for new players.
	# The tutorial overlay covers the screen and prevents building card usage.
	# Re-enable when tutorial flow is polished and tested.
	# if PlayerData.games_played == 0 and GameManager.tutorial_mode:
	#	_show_tutorial()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom. Guard on event.pressed: a wheel notch emits BOTH a
	# pressed and a released event, so without this the step applied twice
	# (effective 2x ZOOM_SPEED).
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_level = clampf(_zoom_level + ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			if camera:
				camera.zoom = Vector2(_zoom_level, _zoom_level)
				_clamp_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_level = clampf(_zoom_level - ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			if camera:
				camera.zoom = Vector2(_zoom_level, _zoom_level)
				_clamp_camera_position()
		# Middle-click drag to pan camera
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_camera_pan_dragging = true
				_camera_pan_last_pos = event.position
			else:
				_camera_pan_dragging = false
	# Mouse drag while middle button held
	elif event is InputEventMouseMotion and _camera_pan_dragging:
		if camera:
			# Drag direction inverted from cursor movement (natural pan feel).
			# Divide by zoom so 1px screen = 1px world at any zoom level.
			var delta: Vector2 = (_camera_pan_last_pos - event.position) / _zoom_level
			camera.position += delta
			_camera_pan_last_pos = event.position
			_clamp_camera_position()
	# Pinch zoom (touch)
	elif event is InputEventMagnifyGesture:
		_zoom_level = clampf(_zoom_level * event.factor, ZOOM_MIN, ZOOM_MAX)
		if camera:
			camera.zoom = Vector2(_zoom_level, _zoom_level)
			_clamp_camera_position()
	# Two-finger pan gesture (touch)
	elif event is InputEventPanGesture:
		if camera:
			camera.position += event.delta / _zoom_level
			_clamp_camera_position()


## T-085: Apply visual perspective flip for Player 2.
## Swaps castle areas and grid overlay routing so the local player always
## sees their build zone at the bottom.
##
## Terrain tint note: terrain in `_build_terrain_textures()` paints the
## bottom-half zone (y=695–1010) green and the top-half zone (y=0–345)
## darker. These are SCREEN-POSITIONAL, not team-positional. Because
## `sim_to_screen()` Y-reflects sim positions around FLIP_PIVOT_Y=520,
## the flipped (local=player 1) player's buildings render on the visual
## bottom half (green) and the opponent's render on the visual top half
## (darker) — the acceptance criterion "local player zone = green,
## opponent zone = darker" is satisfied by construction without a tint
## swap. Decorations (bushes, stumps, stones) are ambient and not
## team-colored, so they also need no swap.
func _apply_perspective_flip() -> void:
	# Swap castle area positions (scene nodes at fixed Y coordinates)
	var ca0 = get_node_or_null("CastleArea0")
	var ca1 = get_node_or_null("CastleArea1")
	if ca0 and ca1:
		var ca0_top: float = ca0.offset_top
		var ca0_bottom: float = ca0.offset_bottom
		var ca1_top: float = ca1.offset_top
		var ca1_bottom: float = ca1.offset_bottom
		ca0.offset_top = ca1_top
		ca0.offset_bottom = ca1_bottom
		ca1.offset_top = ca0_top
		ca1.offset_bottom = ca0_bottom

	# Swap grid overlays so the local player's grid is at the bottom
	# grid_overlay_0 normally = player (bottom), grid_overlay_1 = enemy (top)
	# When flipped, swap their player_index assignments
	if grid_overlay_0 and grid_overlay_1:
		var tmp: int = grid_overlay_0.player_index
		grid_overlay_0.player_index = grid_overlay_1.player_index
		grid_overlay_1.player_index = tmp


## Clamp camera position so the visible area stays within the arena bounds.
## Arena is 720x1280; visible area scales with zoom.
func _clamp_camera_position() -> void:
	if camera == null:
		return
	var visible_w: float = 720.0 / _zoom_level
	var visible_h: float = 1280.0 / _zoom_level
	var min_x: float = visible_w * 0.5
	var max_x: float = 720.0 - visible_w * 0.5
	var min_y: float = visible_h * 0.5
	var max_y: float = 1280.0 - visible_h * 0.5
	# When fully zoomed out, bounds collapse — recenter to home.
	if min_x > max_x:
		camera.position.x = CAMERA_HOME.x
	else:
		camera.position.x = clampf(camera.position.x, min_x, max_x)
	if min_y > max_y:
		camera.position.y = CAMERA_HOME.y
	else:
		camera.position.y = clampf(camera.position.y, min_y, max_y)


## Keyboard pan: WASD or arrow keys move the camera. Speed scales with delta.
func _handle_camera_keyboard_pan(delta: float) -> void:
	if camera == null:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir == Vector2.ZERO:
		return
	camera.position += dir.normalized() * PAN_SPEED_KEYS * delta / _zoom_level
	_clamp_camera_position()


func _process(delta: float) -> void:
	# Keyboard camera pan (works in any state — also useful in tutorial/end screen)
	_handle_camera_keyboard_pan(delta)

	# Ambient scenery — runs in any state (menu/pre-game/playing) so the
	# battle screen feels alive even during prep phase or tutorial pauses.
	_tick_ambient(delta)

	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.simulation == null:
		return
	_sync_unit_positions()
	_sync_building_hp()
	_update_castle_hp_bars()
	_update_gold_bar()
	_update_ability_buttons()
	_update_wave_announcement(delta)
	_update_screen_shake(delta)
	_update_ai(delta)
	# T-030: Update ambient intensity based on active unit count
	if GameManager.simulation:
		var unit_count: int = 0
		for e in GameManager.simulation.entities:
			if e.type == "unit":
				unit_count += 1
		SFX.update_ambient_intensity(unit_count)
	# Kill streak decay
	if _kill_streak_timer > 0:
		_kill_streak_timer -= delta
		if _kill_streak_timer <= 0:
			_kill_streak = 0


func _on_building_selected(bd: BuildingData) -> void:
	var local_index: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	# T-085 FIX: Match by player_index value (not variable name) because
	# _apply_perspective_flip() swaps the player_index assignments.
	var grid: Node2D = grid_overlay_0 if grid_overlay_0.player_index == local_index else grid_overlay_1
	if bd == null:
		grid.deselect_building()
	else:
		grid.select_building(bd)
		# T-012: Notify tutorial overlay of card selection
		if _tutorial_overlay and is_instance_valid(_tutorial_overlay):
			_tutorial_overlay._on_card_selected()


func grid_to_screen(player_index: int, grid_x: int, grid_y: int, grid_size_y: int = 1) -> Vector2:
	var x: float = GRID_MARGIN_X + grid_x * CELL_SIZE
	if not view_flipped:
		var zone_y: int = PLAYER_ZONE_Y if player_index == 0 else ENEMY_ZONE_Y
		return Vector2(x, zone_y + grid_y * CELL_SIZE)
	# T-085: When flipped, invert rows. Account for building height so multi-cell
	# buildings appear at the correct visual top-left (not offset by size-1 rows).
	if player_index == 0:
		return Vector2(x, ENEMY_ZONE_Y + (GRID_ROWS - grid_y - grid_size_y) * CELL_SIZE)
	else:
		return Vector2(x, PLAYER_ZONE_Y + (GRID_ROWS - grid_y - grid_size_y) * CELL_SIZE)


# --- Building Visuals ---

func _on_building_placed(player_id: int, building_data: BuildingData, grid_pos: Vector2i) -> void:
	SFX.play_place()
	# Cycle card hand when player places a building
	if player_id == GameManager.local_player_id:
		card_hand.card_played(building_data.id)
		# Tutorial: advance from step 1 → step 2 on first building
		if GameManager.tutorial_mode and GameManager.tutorial_step == 1:
			GameManager.advance_tutorial(2)
	var player_index: int = GameManager.simulation.get_player_index(player_id)

	var entity_id: int = -1
	for entity in GameManager.simulation.entities:
		if entity.type == "building" and entity.owner == player_id \
		   and entity.grid_x == grid_pos.x and entity.grid_y == grid_pos.y:
			entity_id = entity.id

	var visual := _create_building_visual(building_data, player_index, grid_pos)
	buildings_layer.add_child(visual)
	if entity_id >= 0:
		_building_visuals[entity_id] = visual

	# T-004: Construction animation — scale bounce from 0 + dust burst
	visual.scale = Vector2(0.0, 0.0)
	var place_tw: Tween = visual.create_tween()
	place_tw.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	buildings_layer.add_child(Effects.create_dust(visual.position, 0.5))
	SFX.play_place()

	# T-049: Spawner building smoke — subtle rising particles from top
	if building_data.spawns_unit != null:
		var smoke := _BuildingSmoke.new()
		smoke.position = Vector2(0, -building_data.grid_size.y * CELL_SIZE * 0.4)
		visual.add_child(smoke)

	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


func _create_building_visual(bd: BuildingData, player_index: int, grid_pos: Vector2i) -> Node2D:
	var screen_pos := grid_to_screen(player_index, grid_pos.x, grid_pos.y, bd.grid_size.y)
	var w: float = bd.grid_size.x * CELL_SIZE - 4
	var h: float = bd.grid_size.y * CELL_SIZE - 4
	var center := screen_pos + Vector2(bd.grid_size.x * CELL_SIZE * 0.5, bd.grid_size.y * CELL_SIZE * 0.5)

	# Try sprite-based visual first
	var building_tex: Texture2D = SpriteRegistry.get_building_sprite(bd.id, player_index)
	var result: Node2D
	if building_tex:
		var sbv: Node2D = SpriteBuildingVisualScript.new()
		sbv.position = center
		sbv.setup(player_index, bd.id, bd.tier, bd.display_name, w, h)
		result = sbv
	else:
		# Fallback to procedural
		var bv: Node2D = BuildingVisualScript.new()
		bv.position = center
		bv.setup(player_index, bd.id, bd.tier, bd.display_name, w, h)
		result = bv
	return result


func _on_building_destroyed(building_id: int, reason: String) -> void:
	# The sim event payload carries WHY the building went away ("sold" vs
	# "killed"). The old sim-scan heuristic always concluded "combat" because
	# both removal paths delete the entity before this signal dispatches.
	var is_sold: bool = reason == "sold"
	var local_team: int = 0
	if GameManager.simulation:
		for p in GameManager.simulation.players:
			if p.id == GameManager.local_player_id:
				local_team = p.team
				break
	var visual = _building_visuals.get(building_id)
	var is_local_building: bool = visual != null and visual.team == local_team
	if is_sold:
		# Sell feedback only for the local player's own sell action.
		if is_local_building:
			SFX.play_sell()
	else:
		SFX.play_destroy()
	if visual != null:
		var pos: Vector2 = visual.position
		# T-005: Destruction animation — explosion + shrink/rotate + debris
		units_layer.add_child(Effects.create_explosion(pos, 0.5))
		units_layer.add_child(Effects.create_death_poof(pos, Color(0.6, 0.5, 0.3)))
		units_layer.add_child(Effects.create_dust(pos, 0.6))
		# "SOLD" text — only when the local player sold it (enemy-razed buildings
		# used to pop a gold "SOLD" label because this ran unconditionally).
		if is_sold and is_local_building:
			var refund_node := Effects.create_damage_number(0, pos, true)
			var lbl: Label = refund_node.get_child(0)
			if lbl:
				lbl.text = "SOLD"
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			units_layer.add_child(refund_node)
		# Shrink + rotate out
		_building_visuals.erase(building_id)
		var destroy_tw: Tween = visual.create_tween()
		destroy_tw.set_parallel(true)
		destroy_tw.tween_property(visual, "scale", Vector2(0.0, 0.0), 0.3).set_ease(Tween.EASE_IN)
		destroy_tw.tween_property(visual, "rotation", 0.3, 0.3)
		destroy_tw.tween_property(visual, "modulate:a", 0.0, 0.3)
		destroy_tw.set_parallel(false)
		destroy_tw.tween_callback(visual.queue_free)
	grid_overlay_0.queue_redraw()
	grid_overlay_1.queue_redraw()


# --- Unit Visuals ---

func _on_unit_spawned(unit_id: int, _unit_type: StringName) -> void:
	var entity: Dictionary = {}
	for e in GameManager.simulation.entities:
		if e.id == unit_id:
			entity = e
			break
	if entity.is_empty():
		return

	var visual := _create_unit_visual(entity)
	units_layer.add_child(visual)
	_unit_visuals[unit_id] = visual

	# T-058: Stagger walk phase so units don't march in lockstep
	if visual.has_method("get") and "_walk_phase" in visual:
		visual._walk_phase = randf() * TAU

	# Spawn animation: scale from 0 to 1 + burst ring
	visual.scale = Vector2(0.1, 0.1)
	var spawn_tw: Tween = visual.create_tween()
	spawn_tw.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var spawn_color := Color(0.3, 0.6, 1.0) if entity.team == 0 else Color(1.0, 0.35, 0.3)
	units_layer.add_child(Effects.create_spawn_burst(visual.position, spawn_color))
	units_layer.add_child(Effects.create_dust(visual.position, 0.35))

	# Spawn trail: find the building that spawned this unit and draw a line
	var unit_type: StringName = entity.get("unit_type", &"")
	for bld in GameManager.simulation.entities:
		if bld.type != "building" or bld.team != entity.team:
			continue
		var bd = GameManager.simulation.building_registry.get(bld.building_type)
		if bd and bd.spawns_unit and bd.spawns_unit.id == unit_type:
			var bld_screen := grid_to_screen(bld.player_index, bld.grid_x, bld.grid_y, bld.grid_size_y)
			var bld_center := bld_screen + Vector2(bld.grid_size_x * CELL_SIZE * 0.5, bld.grid_size_y * CELL_SIZE * 0.5)
			units_layer.add_child(Effects.create_projectile(bld_center, visual.position, Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.5), 0.3))
			break


func _create_unit_visual(entity: Dictionary) -> Node2D:
	var ut: StringName = entity.get("unit_type", &"")
	var sprite_frames: SpriteFrames = SpriteRegistry.get_unit_sprites(ut, entity.team)

	# Use sprite-based visual if sprites available, else procedural
	if sprite_frames:
		var sv: Node2D = SpriteUnitVisualScript.new()
		# T-085: Transform initial position through perspective flip
		sv.position = sim_to_screen(Vector2(FP.to_float(entity.x), FP.to_float(entity.y)))
		sv.setup(sprite_frames, entity.team, entity.get("role", 0), ut)
		sv.facing = 1.0 if entity.team == 0 else -1.0
		# Design-flow: native palette — terrain is no longer muted, so no brighten
		sv.modulate = Color.WHITE
		return sv
	else:
		var uv: Node2D = UnitVisualScript.new()
		uv.position = sim_to_screen(Vector2(FP.to_float(entity.x), FP.to_float(entity.y)))
		uv.team = entity.team
		uv.role = entity.get("role", 0)
		uv.unit_type = ut
		uv.hp_ratio = 1.0
		uv.facing = 1.0 if entity.team == 0 else -1.0
		# Design-flow: native palette (no brighten)
		uv.modulate = Color.WHITE
		return uv


var _kill_streak: int = 0
var _kill_streak_timer: float = 0.0

func _on_unit_died(unit_id: int, _killer_id: int, bounty: int, _pos_x: float, _pos_y: float) -> void:
	var _dr: int = _unit_visuals[unit_id].role if _unit_visuals.has(unit_id) else -1
	SFX.play_death(_dr)
	_shake_intensity = 1.5
	_shake_timer = 0.05
	_kill_streak += 1
	_kill_streak_timer = 0.5
	if _kill_streak >= 3:
		_shake_intensity = 3.0
		_shake_timer = 0.1
		_kill_streak = 0
	if _unit_visuals.has(unit_id):
		var visual = _unit_visuals[unit_id]
		var death_pos: Vector2 = visual.position
		var team_color := Color(0.3, 0.6, 1.0) if visual.team == 0 else Color(1.0, 0.35, 0.3)
		units_layer.add_child(Effects.create_explosion(death_pos, 0.3))
		units_layer.add_child(Effects.create_death_poof(death_pos, team_color))

		# T-006: Gold bounty floating text (only for player's kills)
		var dead_team: int = visual.team
		var local_team: int = 0
		for p in GameManager.simulation.players:
			if p.id == GameManager.local_player_id:
				local_team = p.team
				break
		if dead_team != local_team:
			# Bounty rides in the entity_died payload — the sim entity is already
			# removed by _cleanup_dead when this signal fires, so the old sim-scan
			# always found 0 and this popup was dead code.
			if bounty > 0:
				var gold_text := Effects.create_damage_number(bounty, death_pos, true)
				var lbl: Label = gold_text.get_child(0)
				if lbl:
					lbl.text = "+%dg" % bounty
					lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
				units_layer.add_child(gold_text)

		_unit_visuals.erase(unit_id)
		var death_tween: Tween = visual.create_tween()
		death_tween.set_parallel(true)
		death_tween.tween_property(visual, "scale", Vector2(0.0, 0.0), 0.15).set_ease(Tween.EASE_IN)
		death_tween.tween_property(visual, "modulate:a", 0.0, 0.15)
		death_tween.set_parallel(false)
		death_tween.tween_callback(visual.queue_free)


func _on_unit_attacked(attacker_id: int, target_id: int, damage: int, target_x: float, target_y: float) -> void:
	# Tutorial: advance from step 2 → step 3 on first combat
	if GameManager.tutorial_mode and GameManager.tutorial_step == 2:
		GameManager.advance_tutorial(3)
	# T-085: Transform sim coords → screen coords
	var target_pos := sim_to_screen(Vector2(target_x, target_y))
	# Sound
	if _unit_visuals.has(attacker_id):
		var av = _unit_visuals[attacker_id]
		if av.position.distance_to(target_pos) > 40:
			SFX.play_shoot(av.role)
		else:
			SFX.play_hit(av.role)
	# Damage number
	units_layer.add_child(Effects.create_damage_number(damage, target_pos))
	# Hit flash on target
	if _unit_visuals.has(target_id):
		_unit_visuals[target_id].flash_hit()
		# T-059: Hit-stop on target (2-frame freeze for combat crunch)
		_unit_visuals[target_id].trigger_hitstop()
	# Attack animation on attacker
	if _unit_visuals.has(attacker_id):
		var attacker_visual = _unit_visuals[attacker_id]
		# T-059: Hit-stop on attacker
		attacker_visual.trigger_hitstop()
		attacker_visual.play_attack(target_pos)
		var from_p: Vector2 = attacker_visual.position
		_spawn_attack_projectile(attacker_visual, from_p, target_pos)
	elif _building_visuals.has(attacker_id):
		# Tower attack — fire a projectile from the building to the target
		var tower_visual = _building_visuals[attacker_id]
		var tower_center: Vector2 = tower_visual.position
		units_layer.add_child(Effects.create_projectile(tower_center, target_pos, Color(1.0, 0.7, 0.2), 0.2))


func _on_unit_healed(healer_id: int, _target_id: int, amount: int, target_x: float, target_y: float) -> void:
	SFX.play_heal()
	# T-085: Transform sim coords → screen coords
	var target_pos := sim_to_screen(Vector2(target_x, target_y))
	# Use Tiny Swords Heal_Effect sprite if available
	var healer_team: int = 0
	if _unit_visuals.has(healer_id):
		healer_team = _unit_visuals[healer_id].team
	units_layer.add_child(Effects.create_sprite_heal(target_pos, healer_team))
	units_layer.add_child(Effects.create_damage_number(amount, target_pos, true))
	# Cast animation on healer
	if _unit_visuals.has(healer_id):
		_unit_visuals[healer_id].play_cast()


func _on_castle_hit(hit_team: int, _damage: int, _remaining_hp: int, attacker_id: int = -1) -> void:
	SFX.play_castle_hit()
	# Play attack animation + projectile on the attacker
	if attacker_id >= 0 and _unit_visuals.has(attacker_id):
		var attacker_visual = _unit_visuals[attacker_id]
		# Castle target position — use simulation castle Y for consistency with unit coords
		# BUG-CASTLE-VFX 2026-04-11: team 0 (player) castle is at y=920
		# BUG-42 2026-04-18: team 1 castle moved 70 → 120 per T-096 (symmetric around FLIP_PIVOT_Y=520)
		var castle_y: float = 920.0 if hit_team == 0 else 120.0
		# T-085: Transform castle position through perspective flip
		var castle_pos := sim_to_screen(Vector2(attacker_visual.position.x, castle_y))
		attacker_visual.play_attack(castle_pos)
		_spawn_attack_projectile(attacker_visual, attacker_visual.position, castle_pos)
	# Brief red flash on the damaged castle area
	var castle_area: ColorRect = get_node_or_null("CastleArea0") if hit_team == 0 else get_node_or_null("CastleArea1")
	if castle_area:
		var original_color: Color = castle_area.color
		castle_area.color = Color(0.8, 0.15, 0.1, 0.5)
		var tw := castle_area.create_tween()
		tw.tween_property(castle_area, "color", original_color, 0.3)


# T-022: Skill visual effects
func _on_skill_activated(unit_id: int, skill_id: StringName) -> void:
	if _unit_visuals.has(unit_id):
		var visual = _unit_visuals[unit_id]
		var effect_pos: Vector2 = visual.position
		# T-084 fireball: the splash lands at the attacker's TARGET, not on
		# the mage himself. Look up the sim target and render the burst there.
		if skill_id == &"fireball" and GameManager.simulation:
			var unit = GameManager.simulation._find_entity_by_id(unit_id)
			if unit and unit.get("target_id", -1) != -1:
				var tgt = GameManager.simulation._find_entity_by_id(unit.target_id)
				if tgt:
					var tgt_pos := Vector2(FP.to_float(tgt.x), FP.to_float(tgt.y))
					effect_pos = sim_to_screen(tgt_pos)
		var effect := Effects.create_skill_effect(skill_id, effect_pos, visual.team)
		units_layer.add_child(effect)
	# T-029: Per-skill differentiated SFX
	SFX.play_skill(skill_id)


## Spawn the appropriate projectile based on attacker role/type.
## Shared between unit-vs-unit and unit-vs-castle attacks.
func _spawn_attack_projectile(attacker_visual: Node2D, from_p: Vector2, target_pos: Vector2) -> void:
	if attacker_visual.role == 4:  # Siege — differentiate catapult (rock) vs ballista (bolt)
		var ut: StringName = attacker_visual.unit_type
		if ut == &"ballista_unit" or ut == &"scorpion":
			var proj := Effects.create_bolt_projectile(from_p, target_pos, attacker_visual.team)
			if proj:
				units_layer.add_child(proj)
		else:
			var proj := Effects.create_rock_projectile(from_p, target_pos, attacker_visual.team)
			if proj:
				units_layer.add_child(proj)
	elif attacker_visual.role == 1:  # Ranged
		var proj := Effects.create_arrow_projectile(from_p, target_pos, attacker_visual.team)
		if proj:
			units_layer.add_child(proj)
	elif attacker_visual.role == 2:  # Caster — magic projectile (T-083)
		var proj := Effects.create_fireball_projectile(from_p, target_pos, attacker_visual.team)
		if proj:
			units_layer.add_child(proj)
	elif attacker_visual.role == 3:  # Flying — also ranged
		var proj := Effects.create_arrow_projectile(from_p, target_pos, attacker_visual.team)
		if proj:
			units_layer.add_child(proj)
	else:
		units_layer.add_child(Effects.create_dust(target_pos, 0.25))


# --- Position Sync ---

func _sync_unit_positions() -> void:
	for entity in GameManager.simulation.entities:
		if entity.type != "unit":
			continue
		if _unit_visuals.has(entity.id):
			var visual = _unit_visuals[entity.id]
			# T-058: Interpolate position between simulation ticks for smooth movement
			var curr_pos := Vector2(FP.to_float(entity.x), FP.to_float(entity.y))
			var prev_pos := Vector2(
				FP.to_float(entity.get("prev_x", entity.x)),
				FP.to_float(entity.get("prev_y", entity.y))
			)
			var t: float = GameManager.tick_interpolation
			# T-085: Transform sim coords → screen coords (Y-flip for Player 2)
			# T-059 fix: hold position during hit-stop so the impact reads as a
			# freeze-then-snap, not a unit sliding through its own hit.
			if not visual.is_in_hitstop():
				visual.position = sim_to_screen(prev_pos.lerp(curr_pos, clampf(t, 0.0, 1.0)))

			# Use simulation-authoritative movement flag
			visual.set_moving(entity.get("is_moving", false))

			# BUG-40 fix: feed walk cadence ratio so legs match ground travel.
			# move_speed is px/TICK (~4.48 for a footman); the old baseline 44.8 was
			# px/SEC, so legs ran at ~10% speed (foot-skate). See walk_ratio_for_speed.
			var curr_speed: float = FP.to_float(entity.get("move_speed", 0))
			visual.set_walk_speed_ratio(CombatTuning.walk_ratio_for_speed(curr_speed))

			# Facing: face toward target X position
			if entity.target_id != -1:
				var target = GameManager.simulation._find_entity_by_id(entity.target_id)
				if target:
					var face_dir: float = 1.0 if FP.to_float(target.x) > curr_pos.x else -1.0
					visual.facing = face_dir

			var max_hp: float = FP.to_float(entity.max_hp)
			if max_hp > 0:
				visual.hp_ratio = clampf(FP.to_float(entity.hp) / max_hp, 0.0, 1.0)

			# T-003: Walking dust (every 0.5s while moving)
			if entity.get("is_moving", false):
				var timer: float = _unit_dust_timers.get(entity.id, 0.0)
				timer -= get_process_delta_time()
				if timer <= 0.0:
					# Tint based on terrain: brown in combat lane, greenish in grass
					var dust_tint := Color(0.7, 0.55, 0.35, 0.6) if (curr_pos.y > 345 and curr_pos.y < 695) else Color(0.5, 0.65, 0.4, 0.5)
					var dust := Effects.create_dust(sim_to_screen(curr_pos + Vector2(0, 8)), 0.25)
					dust.modulate = dust_tint
					units_layer.add_child(dust)
					timer = 0.5
				_unit_dust_timers[entity.id] = timer
			else:
				_unit_dust_timers.erase(entity.id)


# --- Building HP Sync ---

func _sync_building_hp() -> void:
	for entity in GameManager.simulation.entities:
		if entity.type != "building":
			continue
		if _building_visuals.has(entity.id):
			var visual = _building_visuals[entity.id]
			var max_hp: float = FP.to_float(entity.max_hp)
			if max_hp > 0:
				visual.hp_ratio = clampf(FP.to_float(entity.hp) / max_hp, 0.0, 1.0)


# --- T-054: Perk indicator on battle screen ---

const PERK_NAMES := {
	&"iron_discipline": "Iron Discipline",
	&"swift_march": "Swift March",
	&"war_economy": "War Economy",
	&"bloodthirst": "Bloodthirst",
	&"savage_rush": "Savage Rush",
	&"pillage": "Pillage",
}

func _show_perk_indicator() -> void:
	if GameManager.selected_perk == &"":
		return
	var perk_name: String = PERK_NAMES.get(GameManager.selected_perk, str(GameManager.selected_perk))
	var ui_layer = get_node_or_null("UILayer")
	if ui_layer == null:
		return
	var indicator := Label.new()
	indicator.text = perk_name
	indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	indicator.position = Vector2(250, 55)
	indicator.size = Vector2(220, 20)
	indicator.add_theme_font_size_override("font_size", 12)  # BUG-41 mobile readability
	indicator.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 0.8))
	indicator.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01, 0.7))
	indicator.add_theme_constant_override("outline_size", 2)
	ui_layer.add_child(indicator)


# --- Gold Display (above card hand) ---

func _update_gold_bar() -> void:
	if not gold_bar_label:
		return
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var income: int = 10
	if GameManager.simulation:
		var sim = GameManager.simulation
		var pi: int = sim.get_player_index(GameManager.local_player_id)
		if pi >= 0 and pi < sim.players.size():
			var base_income: int = FP.to_int(sim.players[pi].income)
			# BUG-INCOME-DISPLAY: Mirror simulation.gd:306-319 compound formula.
			# Count income_bonus% from this player's buildings and apply mode multiplier.
			var pct_bonus: int = 0
			for e in sim.entities:
				if e.type == "building" and e.player_index == pi and FP.gt(e.hp, FP.ZERO):
					var bd = sim.building_registry.get(e.building_type)
					if bd and bd.income_bonus > 0:
						pct_bonus += bd.income_bonus
			income = base_income * (100 + pct_bonus) / 100
			income = income * sim.mode_income_mult / 100

	gold_bar_label.text = "%dg   (+%d/5s)" % [gold, income]

	# Gold income popup
	if gold > _prev_gold and _prev_gold > 0:
		var diff: int = gold - _prev_gold
		if diff > 0 and diff <= 30:
			SFX.play_gold()
			var popup := Effects.create_damage_number(diff, Vector2(360, 1010), true)
			var lbl: Label = popup.get_child(0)
			if lbl:
				lbl.text = "+%dg" % diff
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			get_tree().root.add_child(popup)
	_prev_gold = gold


# --- T-043: Ability Buttons ---

func _update_ability_buttons() -> void:
	if GameManager.simulation == null:
		return
	var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	if pi < 0:
		return

	# Find player's special buildings (those with ability_max_mana > 0)
	var special_buildings: Array[Dictionary] = []
	for entity in GameManager.simulation.entities:
		if entity.type != "building" or entity.get("player_index", -1) != pi:
			continue
		if entity.get("ability_max_mana", 0) > 0:
			special_buildings.append(entity)

	# Create container if needed
	if _ability_container == null and special_buildings.size() > 0:
		_ability_container = HBoxContainer.new()
		_ability_container.position = Vector2(10, 955)
		_ability_container.add_theme_constant_override("separation", 8)
		$UILayer.add_child(_ability_container)

	# Remove buttons for destroyed buildings
	for bid in _ability_buttons.keys():
		var found := false
		for sb in special_buildings:
			if sb.id == bid:
				found = true
				break
		if not found:
			_ability_buttons[bid].queue_free()
			_ability_buttons.erase(bid)

	# Create/update buttons for each special building
	for sb in special_buildings:
		var bid: int = sb.id
		var max_mana: int = sb.get("ability_max_mana", 600)
		var cur_mana: int = sb.get("ability_mana", 0)
		var active_ticks: int = sb.get("ability_active_ticks", 0)
		var mana_ratio: float = clampf(float(cur_mana) / maxf(float(max_mana), 1.0), 0.0, 1.0)
		var is_ready: bool = cur_mana >= max_mana and active_ticks <= 0
		var is_active: bool = active_ticks > 0

		if not _ability_buttons.has(bid):
			var btn := _AbilityButton.new()
			btn.building_id = bid
			btn.building_type = sb.get("building_type", &"")
			btn.team = sb.team
			btn.pressed.connect(_on_ability_pressed.bind(bid))
			_ability_container.add_child(btn)
			_ability_buttons[bid] = btn

		var ab: _AbilityButton = _ability_buttons[bid]
		ab.mana_ratio = mana_ratio
		ab.is_ready = is_ready
		ab.is_active = is_active
		ab.refresh()


func _on_ability_pressed(building_id: int) -> void:
	# Fire-and-forget. The ring + SFX are driven by the sim-confirmed
	# ability_activated event below, so they play for BOTH players and only when
	# the ability actually activates (not on a press the sim later rejects).
	NetworkManager.send_command(Command.activate_building(GameManager.local_player_id, building_id))


## Ring + SFX for a special-building activation (War Horn / Blood Totem). Driven
## by EventBus.ability_activated so the ENEMY's activations are visible + audible
## too — previously only the local player's press-time prediction showed anything.
func _on_ability_activated(building_id: int, team: int, _ability: String, _duration: int) -> void:
	SFX.play_skill()
	var visual = _building_visuals.get(building_id)
	if visual == null:
		return
	var ring_color := Color(0.3, 0.6, 1.0, 0.6) if team == 0 else Color(1.0, 0.35, 0.3, 0.6)
	var ring := Node2D.new()
	ring.position = visual.position
	ring.z_index = 40
	units_layer.add_child(ring)
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, ring.scale.x * 30, 0, TAU, 32, ring_color, 3.0)
	)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(8, 8), 0.6).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.6)
	tw.tween_callback(ring.queue_free)


## Advance ambient scenery — cloud parallax and water-foam alpha breathing.
## Pure visual, no simulation dependencies, safe to run in any game state.
func _tick_ambient(delta: float) -> void:
	_ambient_time += delta
	# Clouds drift uniformly rightward; wrap back around when they leave screen.
	for c in _ambient_clouds:
		if not is_instance_valid(c):
			continue
		var speed: float = c.get_meta("drift_speed", 8.0)
		c.position.x += speed * delta
		if c.position.x > 740.0:
			c.position.x = -60.0
	# Water foam alpha breathes ±0.15 around a 0.85 base at ~0.35 Hz per sprite
	# (design-flow: decorations near-opaque; the old 0.55 base made the dashes
	# invisible over water). Each sprite has its own phase so the shore isn't
	# synchronized.
	for f in _ambient_foams:
		if not is_instance_valid(f):
			continue
		var phase: float = f.get_meta("breath_phase", 0.0)
		var alpha: float = 0.85 + 0.15 * sin(_ambient_time * 2.2 + phase)
		f.modulate.a = alpha


# T-090 Castle Wrath HUD button + shockwave. Button pulses red when the local
# player's castle HP drops below 30%; tap sends USE_ABILITY("castle_wrath")
# which dispatches in simulation. `castle_wrath_activated` draws a red
# expanding ring at the castle center with the sim-reported range_px.
var _castle_wrath_btn: Control = null

func _on_castle_wrath_ready(team: int, _castle_id: int) -> void:
	if GameManager.simulation == null:
		return
	var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	if pi < 0 or GameManager.simulation.players[pi].team != team:
		return
	_spawn_castle_wrath_button()


func _spawn_castle_wrath_button() -> void:
	if _castle_wrath_btn and is_instance_valid(_castle_wrath_btn):
		return  # Already shown
	var btn := Button.new()
	btn.name = "CastleWrathBtn"
	btn.text = "CASTLE WRATH"
	btn.custom_minimum_size = Vector2(150, 52)
	btn.position = Vector2(560, 955)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.7, 0.08, 0.08, 0.92)
	style.border_color = Color(1.0, 0.3, 0.15, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(6)
	style.shadow_color = Color(0.6, 0.1, 0.1, 0.6)
	style.shadow_size = 6
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.85, 0.15, 0.15, 0.95)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = Color(0.5, 0.05, 0.05, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	btn.add_theme_color_override("font_outline_color", Color(0.2, 0.02, 0.02))
	btn.add_theme_constant_override("outline_size", 2)
	btn.pressed.connect(_on_castle_wrath_pressed)
	$UILayer.add_child(btn)
	_castle_wrath_btn = btn
	# Pulse scale 1.0→1.08→1.0 on 1.0s loop — reads as "urgent, use me".
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	var tw := btn.create_tween().set_loops()
	tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _on_castle_wrath_pressed() -> void:
	var cmd := Command.use_ability(GameManager.local_player_id, &"castle_wrath", 0, 0)
	NetworkManager.send_command(cmd)
	SFX.play_skill()


func _on_castle_wrath_activated(_team: int, _target_ids: Array, center_x: float, center_y: float, range_px: float) -> void:
	# Retire the HUD button — ability is one-time per match.
	if _castle_wrath_btn and is_instance_valid(_castle_wrath_btn):
		var fade := _castle_wrath_btn.create_tween()
		fade.tween_property(_castle_wrath_btn, "modulate:a", 0.0, 0.3)
		fade.tween_callback(_castle_wrath_btn.queue_free)
		_castle_wrath_btn = null

	# Red shockwave ring expanding from castle center to range_px.
	var ring := Node2D.new()
	var center_screen := sim_to_screen(Vector2(center_x, center_y))
	ring.position = center_screen
	ring.z_index = 48
	units_layer.add_child(ring)

	var rctx := {"radius": 0.0, "alpha": 0.85}
	ring.draw.connect(func():
		if rctx.alpha <= 0.01:
			return
		ring.draw_arc(Vector2.ZERO, rctx.radius, 0, TAU, 48, Color(1.0, 0.2, 0.15, rctx.alpha), 6.0)
		ring.draw_arc(Vector2.ZERO, rctx.radius * 0.75, 0, TAU, 40, Color(1.0, 0.55, 0.2, rctx.alpha * 0.65), 3.0)
	)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(r: float):
		rctx.radius = r
		ring.queue_redraw()
	, 0.0, range_px, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float):
		rctx.alpha = a
		ring.queue_redraw()
	, 0.85, 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


## T-049: Spawner building smoke — 3 small particles rising from building top
class _BuildingSmoke extends Node2D:
	var _particles: Array[Dictionary] = []
	var _time: float = 0.0

	func _ready() -> void:
		z_index = 30
		for i in 3:
			_particles.append({
				"x": randf_range(-6, 6),
				"phase": randf() * TAU,
				"speed": randf_range(8.0, 14.0),
				"size": randf_range(1.5, 3.0),
			})

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for p in _particles:
			# Each particle rises on a loop (cycle every ~2.5s)
			var cycle: float = fmod(_time * p.speed * 0.1 + p.phase, 1.0)
			var y_off: float = -cycle * 18.0
			var x_off: float = p.x + sin(_time * 1.5 + p.phase) * 3.0
			var alpha: float = 0.25 * (1.0 - cycle)
			var sz: float = p.size * (0.6 + cycle * 0.8)
			draw_circle(Vector2(x_off, y_off), sz,
				Color(0.5, 0.45, 0.4, alpha))


## Inner class for ability button visual
class _AbilityButton extends Button:
	var building_id: int = -1
	var building_type: StringName = &""
	var team: int = 0
	var mana_ratio: float = 0.0
	var is_ready: bool = false
	var is_active: bool = false
	var _pulse_tween: Tween = null
	var _was_ready: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(64, 38)
		size = Vector2(64, 38)
		mouse_filter = Control.MOUSE_FILTER_STOP
		flat = true

	## Call after updating mana_ratio/is_ready/is_active to refresh visuals + pulse.
	func refresh() -> void:
		disabled = not is_ready
		# Pulse management (side-effect-free from _draw)
		if is_ready and not _was_ready:
			_was_ready = true
			if _pulse_tween and _pulse_tween.is_valid():
				_pulse_tween.kill()
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(self, "modulate", Color(1.2, 1.1, 0.9), 0.3)
			_pulse_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.3)
		elif not is_ready and _was_ready:
			_was_ready = false
			if _pulse_tween and _pulse_tween.is_valid():
				_pulse_tween.kill()
			modulate = Color.WHITE
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y

		# Background
		var bg_color := Color(0.15, 0.12, 0.1, 0.85)
		if is_active:
			bg_color = Color(0.2, 0.35, 0.15, 0.9)
		elif is_ready:
			bg_color = Color(0.3, 0.25, 0.1, 0.9)
		draw_rect(Rect2(0, 0, w, h), bg_color)

		# Border
		var border_color := Color(0.4, 0.35, 0.25, 0.6)
		if is_ready:
			border_color = Color(1.0, 0.85, 0.2, 0.9)
		elif is_active:
			border_color = Color(0.4, 0.8, 0.3, 0.8)
		draw_rect(Rect2(0, 0, w, h), border_color, false, 2.0)

		# Icon text (building name abbreviation)
		var icon_text: String = "WH" if building_type == &"war_horn" else "BT"
		var icon_color := Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.4, 0.3)
		draw_string(ThemeDB.fallback_font, Vector2(6, 16), icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, icon_color)

		# Mana bar
		var bar_y: float = h - 8
		var bar_w: float = w - 8
		draw_rect(Rect2(4, bar_y, bar_w, 5), Color(0.1, 0.08, 0.06, 0.8))
		if mana_ratio > 0:
			var fill_color := Color(0.3, 0.6, 1.0) if not is_ready else Color(1.0, 0.85, 0.2)
			if is_active:
				fill_color = Color(0.4, 0.8, 0.3)
			draw_rect(Rect2(4, bar_y, bar_w * mana_ratio, 5), fill_color)

		# Status text
		if is_active:
			draw_string(ThemeDB.fallback_font, Vector2(w - 30, 16), "ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 1.0, 0.4))
		elif is_ready:
			draw_string(ThemeDB.fallback_font, Vector2(w - 28, 16), "GO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.3))


# --- Screen Shake ---

func _update_screen_shake(delta: float) -> void:
	if _shake_timer > 0:
		_shake_timer -= delta
		var offset := Vector2(randf_range(-_shake_intensity, _shake_intensity), randf_range(-_shake_intensity, _shake_intensity))
		position = _original_position + offset
	else:
		position = _original_position


# --- Castle HP Bars ---
# HP bars are now drawn by castle_visual.gd (same as building_visual.gd)
# This just syncs hp_ratio from simulation to the visuals.

func _update_castle_hp_bars() -> void:
	var c0: Dictionary = GameManager.simulation.castles[0]
	var c1: Dictionary = GameManager.simulation.castles[1]
	var ratio_0: float = clampf(FP.to_float(c0.hp) / FP.to_float(c0.max_hp), 0.0, 1.0)
	var ratio_1: float = clampf(FP.to_float(c1.hp) / FP.to_float(c1.max_hp), 0.0, 1.0)
	var cv0 = get_node_or_null("CastleArea0/CastleVisual0")
	var cv1 = get_node_or_null("CastleArea1/CastleVisual1")
	if cv0:
		cv0.hp_ratio = ratio_0
	if cv1:
		cv1.hp_ratio = ratio_1


# --- Wave Announcement ---

var _tutorial_active: bool = false
var _tutorial_overlay: CanvasLayer = null
const TutorialScript := preload("res://scripts/ui/tutorial.gd")

func _show_tutorial() -> void:
	_tutorial_active = true
	_tutorial_overlay = TutorialScript.new()
	add_child(_tutorial_overlay)


func _on_wave_announced(wave_number: int) -> void:
	SFX.play_wave()
	if wave_label:
		wave_label.text = "WAVE %d" % wave_number
		wave_label.visible = true
		wave_label.modulate.a = 1.0
		wave_label.add_theme_font_size_override("font_size", 36)
		wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		wave_label.add_theme_constant_override("outline_size", 4)
		# Scale punch
		wave_label.scale = Vector2(1.4, 1.4)
		var wave_tw: Tween = wave_label.create_tween()
		wave_tw.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_wave_announce_timer = 2.5


func _update_wave_announcement(delta: float) -> void:
	if _wave_announce_timer <= 0:
		return
	_wave_announce_timer -= delta
	if _wave_announce_timer <= 0:
		if wave_label:
			wave_label.visible = false
	elif _wave_announce_timer < 1.0 and wave_label:
		wave_label.modulate.a = _wave_announce_timer


# --- Terrain Decorations ---

## Extract a single frame from a horizontal sprite sheet.
## Detects frame width automatically — handles both square and non-square frames.
func _extract_sprite_frame(sheet: Texture2D, frame: int) -> AtlasTexture:
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
func _polish_arena_visuals() -> void:
	# Fix castle symmetry: both castles 55px from their grass edge
	# Enemy: y=55-120 (55px from top at y=0). Player must match: y=890-955 (55px from bottom at y=1010)
	var castle0 := get_node_or_null("CastleArea0")
	if castle0 and castle0 is ColorRect:
		castle0.offset_top = 890
		castle0.offset_bottom = 955
	var hp_bg0 := get_node_or_null("CastleHPBarBg0")
	if hp_bg0:
		hp_bg0.offset_top = 880
		hp_bg0.offset_bottom = 890
	var hp_bar0 := get_node_or_null("CastleHPBar0")
	if hp_bar0:
		hp_bar0.offset_top = 882
		hp_bar0.offset_bottom = 888

	# Red ribbon for HUD + gold bar — NinePatchRect keeps pointed ends, tiles center
	var ribbon_tex: Texture2D = _load_texture_safe("res://assets/sprites/ui/ninepatch/ribbon_red.png")
	# Ribbon pointed ends: left=98px, right=97px of 259px total. At 720px → ~272px each side
	# Inset for readable text: don't place text on the pointed ends
	var ribbon_inset: float = 115.0

	if ribbon_tex:
		var gold_bg := get_node_or_null("UILayer/GoldBarBg")
		if gold_bg and gold_bg is ColorRect:
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

	# Hide old fill/track ColorRects — no longer needed (gold is text-only now)
	for old_name in ["GoldBarFill", "GoldBarTrack", "GoldBarTopLine", "GoldBarBottomLine"]:
		var old_node := get_node_or_null("UILayer/GoldBarBg/" + old_name)
		if old_node:
			old_node.visible = false

	# Gold label — centered on ribbon, coin icon left of text
	var gold_bg := get_node_or_null("UILayer/GoldBarBg")
	var coin_icon: Texture2D = SpriteRegistry.get_ui_texture(&"Icon_03")
	if coin_icon and gold_bg:
		var coin := Sprite2D.new()
		coin.texture = coin_icon
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.centered = true
		coin.scale = Vector2(22.0 / coin_icon.get_height(), 22.0 / coin_icon.get_height())
		coin.position = Vector2(ribbon_inset + 16, 25)
		coin.z_index = 3
		gold_bg.add_child(coin)

	var gold_label := get_node_or_null("UILayer/GoldBarBg/GoldBarLabel")
	if gold_label:
		gold_label.offset_left = ribbon_inset + 30
		gold_label.offset_right = 720.0 - ribbon_inset
		# BUG-GOLD-COIN-GAP 2026-04-11: Left-align so gold text starts next to
		# the coin icon instead of centering ~244px away.
		# Vertical center the text so it aligns with the coin Sprite2D at y=25
		# (GoldBarBg is 50px tall, label rect spans y=4-46).
		if gold_label is Label:
			var l := gold_label as Label
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Tiny Swords wood table on card hand — NinePatchRect
	var wood_tex: Texture2D = _load_texture_safe("res://assets/sprites/ui/ninepatch/woodtable.png")
	if wood_tex:
		var card_bg := get_node_or_null("UILayer/CardHand/CardBg")
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
	# Red ribbon on top HUD bar — NinePatchRect
	if ribbon_tex:
		var hud_bg := get_node_or_null("UILayer/HUD/HUDBg")
		if hud_bg and hud_bg is ColorRect:
			var hud_ribbon := NinePatchRect.new()
			hud_ribbon.texture = ribbon_tex
			hud_ribbon.patch_margin_left = 98
			hud_ribbon.patch_margin_right = 97
			hud_ribbon.patch_margin_top = 0
			hud_ribbon.patch_margin_bottom = 0
			hud_ribbon.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
			hud_ribbon.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
			hud_ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hud_ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
			hud_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hud_bg.add_child(hud_ribbon)
	# Inset HUD text from ribbon ripple edges
	var hud_hbox := get_node_or_null("UILayer/HUD/HBox")
	if hud_hbox:
		hud_hbox.offset_left = ribbon_inset
		hud_hbox.offset_right = -ribbon_inset
		hud_hbox.offset_top = 8
		hud_hbox.offset_bottom = -6

	# CombatLane hidden entirely — terrain tiles (T-060) handle the combat zone visual.
	var combat_lane := get_node_or_null("CombatLane")
	if combat_lane:
		combat_lane.visible = false

	# Design-flow port (design/arena_target.png is the spec): water is the NATIVE
	# Tiny Swords teal — the old modulate tints turned (71,171,169) into a murky
	# (28,86,93) gutter, the single largest palette divergence from the mockups.
	# WaterBase now paints the full screen in the native texel color (the water
	# tile is perfectly flat, std=0, so a ColorRect is pixel-identical to tiling
	# it); the old 45px straight TextureRect strips are hidden.
	var water_base := get_node_or_null("WaterBase")
	if water_base:
		water_base.color = Color8(71, 171, 169)
	var water_left := get_node_or_null("WaterLeft")
	if water_left:
		water_left.visible = false
	var water_right := get_node_or_null("WaterRight")
	if water_right:
		water_right.visible = false
	# GrassMain shrinks to sit exactly under the tiled platform (fallback fill);
	# its dark edge children belonged to the old full-bleed rectangle.
	var grass_main := get_node_or_null("GrassMain")
	if grass_main:
		grass_main.position = Vector2(72, 56)
		grass_main.size = Vector2(576, 896)
		for child in grass_main.get_children():
			child.visible = false


# --- T-060: Kingdom Rush 3-Layer Terrain ---

func _build_terrain_textures() -> void:
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
	add_child(terrain_layer)
	# Move after GrassMain+CombatLane so tiles render on top of base colors
	var grass_node := get_node_or_null("GrassMain")
	if grass_node:
		move_child(terrain_layer, grass_node.get_index() + 1)

	var ts: float = 64.0

	# Grass ISLAND PLATFORM on native-teal water: x=[72,648] y=[72,968] (9x14
	# tiles) with proper 3x3 edge/corner tiles. The y-span mirrors EXACTLY about
	# FLIP_PIVOT_Y=520 (72+968=1040) so the multiplayer perspective flip shows
	# both players an identical island. Uniform center tile (per-tile hue mixing
	# betrays the 64px grid — lessons.md 2026-07-07); variation = decoration.
	_build_tiled_zone(terrain_layer, tm1, Rect2(72, 72, 576, 896), 1.0, ts, Color.WHITE)

	_add_fortress_dressing(terrain_layer, tm1, ts)

	_add_water_foam()


## Fortress WALL rows per half (design/arena_target.png): a solid stone wall row
## (elevated stone-face tile, col6 row4) whose bottom edge (y=190) aligns with
## the castle base at 0.68 scale — "the edges align" (user feedback 2026-07-08).
## Towers/houses live in the y-sorted DecorationLayer (see
## _setup_terrain_decorations) so sheep/trees layer correctly against them.
## Enemy half as-authored; player half = exact mirror about FLIP_PIVOT_Y.
func _add_fortress_dressing(parent: Node2D, tm: Texture2D, ts: float) -> void:
	if tm == null:
		return
	var stone := AtlasTexture.new()
	stone.atlas = tm
	stone.region = Rect2(6 * 64, 4 * 64, 64, 64)  # solid stone face
	# LAYOUT: WALL_Y=126 (row 126..190; castle base = 120+141/2 = 190), WALL_X=(140,580)
	for spec in [[false], [true]]:
		var flip: bool = spec[0]
		var wy: float = 126.0 if not flip else 2.0 * FLIP_PIVOT_Y - 126.0 - ts
		var x: float = 140.0
		while x < 580.0:
			var spr := Sprite2D.new()
			spr.texture = stone
			spr.centered = false
			spr.position = Vector2(x, wy)
			spr.flip_v = flip
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			parent.add_child(spr)
			x += ts


## Build a tiled zone using flat ground tiles (cols 0-3) with proper edges
func _build_tiled_zone(parent: Node2D, atlas: Texture2D, rect: Rect2, tile_s: float, ts: float, tint: Color) -> void:
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


func _add_water_foam() -> void:
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
	_ambient_foams.clear()
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
		add_child(foam)
		foam.set_meta("breath_phase", randf() * TAU)
		_ambient_foams.append(foam)


func _setup_terrain_decorations() -> void:
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
	add_child(deco_layer)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Deterministic phase staggering for animations

	# 4-way symmetric expansion helper: [L, R, L-mirrored, R-mirrored]
	var all4 := func(cx: float, gy: float) -> Array:
		return [Vector2(cx, gy), Vector2(720.0 - cx, gy),
			Vector2(cx, 2.0 * FLIP_PIVOT_Y - gy), Vector2(720.0 - cx, 2.0 * FLIP_PIVOT_Y - gy)]

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
			var gy: float = d[2] if not flip else 2.0 * FLIP_PIVOT_Y - d[2]
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
		for cl in [[110.0, 428.0, 3], [110.0, 580.0, 2]]:
			for k in int(cl[2]):
				var sheet: Texture2D = tree_sheets[k % tree_sheets.size()]
				var fh: int = int(sheet.get_height())
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(0, 0, fh, fh)
				var dx: float = (k - cl[2] / 2.0) * 32.0 + 16.0
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


# --- Smart AI Opponent ---

var _ai_strategy: int = -1  # 0=balanced, 1=rush, 2=tech

func _update_ai(delta: float) -> void:
	if ai_disabled or GameManager.is_online_match:
		return
	# Tutorial: AI paused during step 1, half-speed during step 2
	if GameManager.tutorial_mode and GameManager.tutorial_step <= 1:
		return
	_ai_timer -= delta
	if _ai_timer > 0:
		return
	_ai_timer = AI_THINK_INTERVAL * (2.0 if GameManager.tutorial_mode and GameManager.tutorial_step == 2 else 1.0)

	var sim: Simulation = GameManager.simulation
	var ai_index: int = sim.get_player_index(AI_PLAYER_ID)
	if ai_index == -1:
		return
	var faction: FactionData = GameManager.get_player_faction(AI_PLAYER_ID)
	if faction == null:
		return

	# Pick strategy once per match
	if _ai_strategy == -1:
		_ai_strategy = randi() % 3

	var gold: int = GameManager.get_player_gold(AI_PLAYER_ID)
	var match_time: int = GameManager.current_tick

	# Activate special building abilities when ready
	_ai_try_activate(sim, ai_index)

	# Scan AI's buildings
	var ai_bld_count: int = 0
	var has_income: bool = false
	var has_t1: bool = false
	var has_upgrade: bool = false
	var has_special: bool = false
	var wall_count: int = 0
	for entity in sim.entities:
		if entity.type == "building" and entity.player_index == ai_index:
			ai_bld_count += 1
			var bt: StringName = entity.building_type
			var bd_c = sim.building_registry.get(bt)
			if bd_c and bd_c.income_bonus > 0: has_income = true
			if bd_c and bd_c.spawns_unit and bd_c.tier == 1: has_t1 = true
			if bt in [&"armory", &"blood_altar"]: has_upgrade = true
			if bt in [&"war_horn", &"blood_totem"]: has_special = true
			if bt in [&"wall", &"palisade"]: wall_count += 1

	# Affordable buildings (exclude walls from main selection)
	var affordable: Array[BuildingData] = []
	for bd: BuildingData in faction.buildings:
		if bd.gold_cost > gold:
			continue
		if bd.grid_size == Vector2i(1, 1) and not bd.spawns_unit and not bd.is_tower and bd.income_bonus == 0:
			continue  # Skip walls
		if bd.requires_building != &"" and not sim.player_has_building(ai_index, bd.requires_building):
			continue
		affordable.append(bd)

	# Scout player composition
	var p_melee: int = 0
	var p_ranged: int = 0
	var p_siege: int = 0
	for entity in sim.entities:
		if entity.type == "unit" and entity.team != AI_PLAYER_ID:
			match entity.role:
				0: p_melee += 1
				1: p_ranged += 1
				4: p_siege += 1

	var chosen: BuildingData = null

	# Strategy-based build order
	match _ai_strategy:
		0:  # Balanced
			if not has_income and ai_bld_count < 2:
				chosen = _ai_pick(affordable, &"income")
			if chosen == null and ai_bld_count < 5:
				chosen = _ai_pick(affordable, &"t1")
			if chosen == null and match_time > 350 and not has_upgrade:
				chosen = _ai_pick(affordable, &"upgrade")
		1:  # Rush — spam T1 combat, no economy
			if ai_bld_count < 6:
				chosen = _ai_pick(affordable, &"t1")
			if chosen == null and match_time > 400:
				chosen = _ai_pick(affordable, &"t2")
		2:  # Tech — double income then T2
			if ai_bld_count < 2:
				chosen = _ai_pick(affordable, &"income")
			if chosen == null and ai_bld_count < 4:
				chosen = _ai_pick(affordable, &"t1")
			if chosen == null and match_time > 250:
				chosen = _ai_pick(affordable, &"t2")
			if chosen == null and match_time > 400 and not has_special:
				chosen = _ai_pick(affordable, &"special")

	# Counter-play (all strategies)
	if chosen == null and match_time > 200:
		if p_melee > p_ranged + 3:
			chosen = _ai_pick(affordable, &"ranged")
			if chosen == null:
				chosen = _ai_pick(affordable, &"tower")
		elif p_ranged > p_melee + 3:
			chosen = _ai_pick(affordable, &"t2")
		elif p_siege > 1:
			chosen = _ai_pick(affordable, &"t1")

	# Upgrade buildings when ahead on economy
	if chosen == null and match_time > 500 and gold > 150:
		if not has_upgrade:
			chosen = _ai_pick(affordable, &"upgrade")
		elif not has_special:
			chosen = _ai_pick(affordable, &"special")

	# Fallback: random combat building
	if chosen == null:
		var combat: Array[BuildingData] = []
		for bd: BuildingData in affordable:
			if bd.spawns_unit or bd.is_tower:
				combat.append(bd)
		if not combat.is_empty():
			chosen = combat[randi() % combat.size()]
		elif not affordable.is_empty():
			chosen = affordable[randi() % affordable.size()]
		else:
			return

	_ai_place(sim, chosen)

	# Place maze walls periodically
	if wall_count < 4 and ai_bld_count > 3 and match_time > 300 and gold > 30:
		_ai_place_wall(sim, ai_index, faction)


func _ai_pick(list: Array[BuildingData], cat: StringName) -> BuildingData:
	for bd: BuildingData in list:
		match cat:
			&"income":
				if bd.income_bonus > 0: return bd
			&"t1":
				if bd.spawns_unit and bd.tier == 1: return bd
			&"t2":
				if bd.spawns_unit and bd.tier == 2: return bd
			&"ranged":
				if bd.spawns_unit and bd.spawns_unit.role == 1: return bd
			&"tower":
				if bd.is_tower: return bd
			&"upgrade":
				if bd.id in [&"armory", &"blood_altar"]: return bd
			&"special":
				if bd.id in [&"war_horn", &"blood_totem"]: return bd
	return null


func _ai_try_activate(sim: Simulation, ai_index: int) -> void:
	for entity in sim.entities:
		if entity.type != "building" or entity.player_index != ai_index:
			continue
		var max_mana: int = entity.get("ability_max_mana", 0)
		if max_mana > 0 and entity.get("ability_mana", 0) >= max_mana:
			if entity.get("ability_active_ticks", 0) <= 0:
				GameManager.submit_command(Command.activate_building(AI_PLAYER_ID, entity.id))
				return


func _ai_place_wall(sim: Simulation, ai_index: int, faction: FactionData) -> void:
	var wall_bd: BuildingData = null
	for bd: BuildingData in faction.buildings:
		if bd.grid_size == Vector2i(1, 1) and not bd.spawns_unit and not bd.is_tower and bd.income_bonus == 0:
			wall_bd = bd
			break
	if wall_bd == null or GameManager.get_player_gold(AI_PLAYER_ID) < wall_bd.gold_cost:
		return
	# Zigzag walls: rows 2 and 5, alternating columns
	var positions := [[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[2,7],[2,8],
		[5,2],[5,3],[5,4],[5,5],[5,6],[5,7],[5,8],[5,9],[5,10]]
	for pos in positions:
		if sim.can_place_building(AI_PLAYER_ID, wall_bd.id, pos[1], pos[0]):
			GameManager.submit_command(Command.place_building(AI_PLAYER_ID, wall_bd.id, pos[1], pos[0]))
			return


func _ai_place(sim: Simulation, chosen: BuildingData) -> void:
	var prefer_front: bool = chosen.is_tower or chosen.spawns_unit != null
	var prefer_back: bool = chosen.income_bonus > 0
	for _attempt in 25:
		var gx: int
		if prefer_front:
			gx = (GRID_COLS - chosen.grid_size.x) / 2 + randi() % maxi(1, (GRID_COLS - chosen.grid_size.x + 2) / 2)
		elif prefer_back:
			gx = randi() % maxi(1, (GRID_COLS - chosen.grid_size.x + 2) / 2)
		else:
			gx = randi() % maxi(1, GRID_COLS - chosen.grid_size.x + 1)
		var gy: int = randi() % maxi(1, GRID_ROWS - chosen.grid_size.y + 1)
		if sim.can_place_building(AI_PLAYER_ID, chosen.id, gx, gy):
			GameManager.submit_command(Command.place_building(AI_PLAYER_ID, chosen.id, gx, gy))
			return


# --- CR-Standard: Mid-match error overlays ---

func _on_match_aborted(reason: String) -> void:
	_show_error_overlay(reason)

func _on_desync_detected(tick: int) -> void:
	_show_error_overlay("Sync error at tick %d" % tick)

func _show_error_overlay(message: String) -> void:
	# Prevent duplicate overlays
	if get_node_or_null("ErrorOverlay"):
		return
	var overlay := CanvasLayer.new()
	overlay.name = "ErrorOverlay"
	overlay.layer = 100
	add_child(overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.75)
	overlay.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(400, 200)
	vbox.position = Vector2(-200, -100)
	overlay.add_child(vbox)

	var title := Label.new()
	title.text = message
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "Return to Menu"
	btn.custom_minimum_size = Vector2(250, 60)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func():
		GameManager.reset_match()
		NetworkManager._reset_to_offline()
		SceneTransition.change_scene("res://scenes/ui/main_menu.tscn")
	)
	vbox.add_child(btn)
