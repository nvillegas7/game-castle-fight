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
# 1C-4: attacker_id -> last sim tick attacker-side attack FX played (dedupe)
var _attacker_fx_tick: Dictionary = {}

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
	EventBus.castle_wrath_refused.connect(_on_castle_wrath_refused)
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
	grid_overlay_0.view_flipped = false
	grid_overlay_1.view_flipped = false
	if camera:
		camera.zoom = Vector2.ONE
		camera.position = Vector2(360, 640)

	if wave_label:
		wave_label.visible = false

	ArenaTerrain.build_textures(self)
	ArenaTerrain.setup_decorations(self)
	ArenaTerrain.polish(self)

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

	# 3.1 (2026-07-18): tutorial RE-ENABLED for first-run only. The 2026-04-14
	# disable reason (overlay blocked all input) is fixed — tutorial.gd's root
	# is MOUSE_FILTER_IGNORE now. Scenario: tests/scenarios/tutorial_first_run.gd
	if PlayerData.games_played == 0 and GameManager.tutorial_mode:
		_show_tutorial()


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
		# BUG-50: overlays must invert rows in lockstep with grid_to_screen
		grid_overlay_0.view_flipped = true
		grid_overlay_1.view_flipped = true


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
	# 1C-4: attacker-side FX (sound, swing, hitstop, projectile) fire ONCE per
	# attack — an AoE emits one unit_attacked per victim in the same tick, and
	# replaying the swing N times read as machine-gun stutter. Victim-side FX
	# (damage number, flash, hit-stop) stay per-event.
	var first_fx: bool = _attacker_fx_tick.get(attacker_id, -1) != GameManager.current_tick
	_attacker_fx_tick[attacker_id] = GameManager.current_tick
	# Sound
	if first_fx and _unit_visuals.has(attacker_id):
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
	# Attack animation on attacker (once per attack — see first_fx above)
	if first_fx and _unit_visuals.has(attacker_id):
		var attacker_visual = _unit_visuals[attacker_id]
		# T-059: Hit-stop on attacker
		attacker_visual.trigger_hitstop()
		attacker_visual.play_attack(target_pos)
		var from_p: Vector2 = attacker_visual.position
		_spawn_attack_projectile(attacker_visual, from_p, target_pos)
	elif first_fx and _building_visuals.has(attacker_id):
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
func _on_skill_activated(unit_id: int, skill_id: StringName, center: Vector2 = Vector2.INF) -> void:
	if _unit_visuals.has(unit_id):
		var visual = _unit_visuals[unit_id]
		var effect_pos: Vector2 = visual.position
		# T-084/1D-2 fireball: the splash lands at the EVENT's center payload —
		# the sim's coords at proc time. (The old live re-lookup chased a target
		# that could move or die before the visual layer handled the event.)
		if skill_id == &"fireball" and center.is_finite():
			effect_pos = sim_to_screen(center)
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
	indicator.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)  # BUG-41 mobile readability
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


## 1D-3: refused wrath gets visible feedback — button shake + reason toast.
## Local player only (the opponent's refusals are not our feedback).
func _on_castle_wrath_refused(team: int, reason: String) -> void:
	if GameManager.simulation == null:
		return
	var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	if pi < 0 or GameManager.simulation.players[pi].team != team:
		return
	if _castle_wrath_btn and is_instance_valid(_castle_wrath_btn):
		var home_x: float = _castle_wrath_btn.position.x
		var tw := _castle_wrath_btn.create_tween()
		for off in [8.0, -8.0, 5.0, -5.0, 0.0]:
			tw.tween_property(_castle_wrath_btn, "position:x", home_x + off, 0.05)
	var toast := Label.new()
	toast.text = "Castle Wrath: " + ("castle not damaged enough" if reason == &"" or reason == "hp_too_high" else reason.replace("_", " "))
	toast.position = Vector2(360 - 180, 860)
	toast.size = Vector2(360, 30)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(1, 0.65, 0.4))
	toast.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	toast.add_theme_constant_override("outline_size", 3)
	$UILayer.add_child(toast)
	var ttw := toast.create_tween()
	ttw.tween_interval(1.4)
	ttw.tween_property(toast, "modulate:a", 0.0, 0.5)
	ttw.tween_callback(toast.queue_free)


func _spawn_castle_wrath_button() -> void:
	if _castle_wrath_btn and is_instance_valid(_castle_wrath_btn):
		return  # Already shown
	var btn := Button.new()
	btn.name = "CastleWrathBtn"
	btn.text = "CASTLE WRATH"
	btn.custom_minimum_size = Vector2(150, 88)
	btn.position = Vector2(560, 896)  # 88px tall clears GoldBarBg at y=990
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
	btn.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
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
		custom_minimum_size = Vector2(88, 88)
		size = Vector2(88, 88)
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

		# Icon text (building name abbreviation) — centered, 32px hero-power style
		var icon_text: String = "WH" if building_type == &"war_horn" else "BT"
		var icon_color := Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.4, 0.3)
		draw_string(ThemeDB.fallback_font, Vector2(0, h * 0.5 + 8), icon_text, HORIZONTAL_ALIGNMENT_CENTER, w, 32, icon_color)

		# Mana bar (bottom)
		var bar_y: float = h - 12
		var bar_w: float = w - 12
		draw_rect(Rect2(6, bar_y, bar_w, 7), Color(0.1, 0.08, 0.06, 0.8))
		if mana_ratio > 0:
			var fill_color := Color(0.3, 0.6, 1.0) if not is_ready else Color(1.0, 0.85, 0.2)
			if is_active:
				fill_color = Color(0.4, 0.8, 0.3)
			draw_rect(Rect2(6, bar_y, bar_w * mana_ratio, 7), fill_color)

		# Status text (top-right)
		if is_active:
			draw_string(ThemeDB.fallback_font, Vector2(w - 40, 20), "ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 1.0, 0.4))
		elif is_ready:
			draw_string(ThemeDB.fallback_font, Vector2(w - 40, 20), "GO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.3))


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
	_tutorial_overlay.name = "TutorialOverlay"  # 3.1: scenario tap target
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


# --- Smart AI Opponent (Phase 2.1: decision logic extracted → ArenaAI) ---
# game_arena keeps only the SCENE-side concerns: the think timer, the
# ai_disabled / online / tutorial gates, and submitting what think() returns.
# All build-order/counter-play/placement logic lives in scripts/game/arena_ai.gd
# (headless-testable: test_arena_ai.gd + test_balance.gd Mode B run the REAL AI).

var _arena_ai: ArenaAI = null

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
	if sim == null:
		return
	var faction: FactionData = GameManager.get_player_faction(AI_PLAYER_ID)
	if faction == null:
		return
	if _arena_ai == null:
		# Fresh randomized RNG per match (the scene is re-instanced per match) —
		# same distribution as the global randi() the pre-extraction code used.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_arena_ai = ArenaAI.new(AI_PLAYER_ID, rng)
	var cmds: Array = _arena_ai.think(sim, faction,
		GameManager.get_player_gold(AI_PLAYER_ID), GameManager.current_tick)
	for cmd in cmds:
		GameManager.submit_command(cmd)


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
