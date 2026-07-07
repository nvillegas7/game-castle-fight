## Grid overlay that draws grid lines, ghost preview, and handles placement input.
## Attached to a Node2D inside each team's build zone.
extends Node2D

signal building_deselected

const CELL_SIZE: int = 28
const GRID_COLS: int = 11
const GRID_ROWS: int = 10

## Which player this grid belongs to (set by parent).
var player_index: int = 0

# Placement state
var selected_building: BuildingData = null
var ghost_grid_pos: Vector2i = Vector2i(-1, -1)
var ghost_valid: bool = false
var _is_hovering: bool = false

# T-097: Hold-to-drag placement state. The ghost preview is shown during a
# press-hold on the grid, updates as the finger drags, and placement commits
# on release only if ghost_valid. Cancels silently if released over an invalid
# cell. The `_placing_finger` tracks which touch index started the hold so a
# second finger does not retarget the drag.
var _placing_held: bool = false
var _placing_finger: int = -1  # -1 = mouse, >=0 = touch index


func _draw() -> void:
	_draw_grid_lines()
	_draw_occupied_cells()
	if selected_building and _is_hovering:
		_draw_ghost()


func _draw_grid_lines() -> void:
	# Grid lines only show when a building is selected for placement
	if selected_building == null:
		return
	# T-039: Brighter grid lines for visual hierarchy
	var grid_color := Color(0.25, 0.45, 0.15, 0.15) if player_index == 0 else Color(0.45, 0.25, 0.15, 0.15)
	var w: int = GRID_COLS * CELL_SIZE
	var h: int = GRID_ROWS * CELL_SIZE

	for row in GRID_ROWS + 1:
		var y: float = row * CELL_SIZE
		draw_line(Vector2(0, y), Vector2(w, y), grid_color, 1.0)

	for col in GRID_COLS + 1:
		var x: float = col * CELL_SIZE
		draw_line(Vector2(x, 0), Vector2(x, h), grid_color, 1.0)

	# Subtle team-colored border
	var border_col := Color(0.2, 0.4, 0.12, 0.15) if player_index == 0 else Color(0.4, 0.2, 0.12, 0.15)
	draw_rect(Rect2(0, 0, w, h), border_col, false, 1.5)


## T-085: Convert a sim grid row to a visual draw row (for 1-cell items).
## Player 1's grid (player_index=1) is displayed in BuildZone0 (bottom of screen)
## with rows inverted so castle (sim row 0) appears at the bottom.
func _visual_row(row: int) -> int:
	if player_index == 1:
		return (GRID_ROWS - 1) - row
	return row


func _draw_occupied_cells() -> void:
	if GameManager.simulation == null:
		return
	if player_index >= GameManager.simulation.grid_cells.size():
		return
	var grid: Array = GameManager.simulation.grid_cells[player_index]
	var occupied_color := Color(0.25, 0.4, 0.15, 0.12) if player_index == 0 else Color(0.4, 0.25, 0.15, 0.12)
	# Only highlight cells occupied by PLACED BUILDINGS (entity IDs >= 0).
	# Skip castle-cell marker (-2) and terrain-obstacle marker (-3) — those
	# aren't player-built and rendering them as "occupied" made the enemy
	# castle footprint look like a gray block of free tiles.
	for row in GRID_ROWS:
		var draw_row: int = _visual_row(row)
		for col in GRID_COLS:
			if grid[row][col] >= 0:
				draw_rect(
					Rect2(col * CELL_SIZE + 1, draw_row * CELL_SIZE + 1, CELL_SIZE - 2, CELL_SIZE - 2),
					occupied_color
				)


func _draw_ghost() -> void:
	if ghost_grid_pos.x < 0 or selected_building == null:
		return
	# T-097: affordability check — amber ghost if can't afford, overrides
	# green/red (gold shortage is a distinct state from "blocked cell").
	var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
	var can_afford: bool = gold >= selected_building.gold_cost

	# T-085: Ghost visual Y — convert sim row back to visual row.
	# Must account for building height: visual = (GRID_ROWS - size_y) - sim_gy
	var visual_gy: int = ghost_grid_pos.y
	if GameManager.simulation:
		var local_idx: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
		if local_idx == 1 and player_index == local_idx:
			visual_gy = (GRID_ROWS - selected_building.grid_size.y) - ghost_grid_pos.y
	var rect := Rect2(
		ghost_grid_pos.x * CELL_SIZE,
		visual_gy * CELL_SIZE,
		selected_building.grid_size.x * CELL_SIZE,
		selected_building.grid_size.y * CELL_SIZE
	)

	# T-097: 1-cell halo around footprint — visual breathing room to help
	# the user avoid adjacent-cell thumb misclicks on mobile.
	var halo_rect := Rect2(
		rect.position.x - CELL_SIZE,
		rect.position.y - CELL_SIZE,
		rect.size.x + 2 * CELL_SIZE,
		rect.size.y + 2 * CELL_SIZE
	)
	var halo_color: Color
	if not can_afford:
		halo_color = Color(0.85, 0.7, 0.2, 0.08)
	elif ghost_valid:
		halo_color = Color(0.3, 0.9, 0.3, 0.08)
	else:
		halo_color = Color(0.9, 0.4, 0.4, 0.08)
	draw_rect(halo_rect, halo_color)

	# Footprint fill + border — gold (can't afford) / green (valid) / red (blocked)
	var fill_color: Color
	var border_color: Color
	if not can_afford:
		fill_color = Color(0.75, 0.6, 0.1, 0.45)
		border_color = Color(0.9, 0.75, 0.2, 0.9)
	elif ghost_valid:
		fill_color = Color(0.0, 0.9, 0.0, 0.5)
		border_color = Color(0.2, 1.0, 0.2, 0.9)
	else:
		fill_color = Color(0.9, 0.0, 0.0, 0.5)
		border_color = Color(1.0, 0.2, 0.2, 0.9)
	draw_rect(rect, fill_color)
	draw_rect(rect, border_color, false, 2.0)


func _input(event: InputEvent) -> void:
	if GameManager.simulation == null:
		return
	var local_idx: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
	if player_index != local_idx:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_building != null:
			deselect_building()
		else:
			# Try to sell building at clicked position
			_try_sell_building(event.position)
		return

	if selected_building == null:
		# T-045: Left tap with no building selected → radial menu on owned building
		if _radial_menu != null:
			var is_tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
				or (event is InputEventScreenTouch and event.pressed)
			if is_tap:
				var tap_pos: Vector2 = event.position
				# BUG-34 FIX: Hit-test radial buttons directly in _input() instead
				# of relying on Area2D physics picking, which fails when the camera
				# transform or input propagation prevents events from reaching Area2D.
				var menu_world_pos: Vector2 = _radial_menu.global_position
				var hit_button: bool = false
				for child in _radial_menu.get_children():
					if child is _RadialButton:
						var btn_world: Vector2 = child.global_position
						var btn_screen: Vector2 = get_viewport().get_canvas_transform() * btn_world
						var dist: float = tap_pos.distance_to(btn_screen)
						if dist <= child.btn_size * 0.5:
							_on_radial_action(child.action, child.entity)
							hit_button = true
							break
				if not hit_button:
					_dismiss_radial()
			return
		var is_left_tap: bool = false
		var left_tap_pos: Vector2 = Vector2.ZERO
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_left_tap = true
			left_tap_pos = event.position
		elif event is InputEventScreenTouch and event.pressed:
			is_left_tap = true
			left_tap_pos = event.position
		if is_left_tap:
			_try_show_radial(left_tap_pos)
		return

	# T-097: HOLD-TO-DRAG PLACEMENT FLOW
	# Press: enter hold, show ghost. Drag: ghost follows finger. Release:
	# commit if valid, silent cancel if invalid. Mouse hover (no button held)
	# also previews the ghost so desktop users see where a click would land.

	# Press start — begin hold, anchor ghost at press point
	var is_press: bool = false
	var press_pos: Vector2 = Vector2.ZERO
	var press_finger: int = -1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_press = true
		press_pos = event.position
		press_finger = -1
	elif event is InputEventScreenTouch and event.pressed:
		is_press = true
		press_pos = event.position
		press_finger = event.index

	if is_press:
		# Multi-touch: if we're already holding, a second finger cancels the
		# placement drag rather than retargeting it. Prevents accidental
		# double-finger place.
		if _placing_held and press_finger != _placing_finger:
			_cancel_placement_drag()
			return
		_placing_held = true
		_placing_finger = press_finger
		_update_ghost_position(press_pos)
		queue_redraw()
		return

	# Release — commit placement if ghost_valid, else cancel silently
	var is_release: bool = false
	var release_pos: Vector2 = Vector2.ZERO
	var release_finger: int = -2
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_release = true
		release_pos = event.position
		release_finger = -1
	elif event is InputEventScreenTouch and not event.pressed:
		is_release = true
		release_pos = event.position
		release_finger = event.index

	if is_release and _placing_held and release_finger == _placing_finger:
		_placing_held = false
		_placing_finger = -1
		_update_ghost_position(release_pos)
		if ghost_valid:
			_place_building()
		elif _is_hovering:
			# Brief feedback only when the tap landed inside the grid but was
			# blocked (can't afford, overlap, anti-block). Silent cancel when
			# released outside the grid.
			var gold: int = GameManager.get_player_gold(GameManager.local_player_id)
			var msg: String = "Blocked!" if gold >= selected_building.gold_cost else "No gold!"
			var err_node := Effects.create_damage_number(0, release_pos, false)
			var label: Label = err_node.get_child(0)
			if label:
				label.text = msg
				label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
			get_tree().root.add_child(err_node)
		_is_hovering = false
		queue_redraw()
		return

	# Drag / hover — update ghost. Touch only tracks during hold; mouse hover
	# previews even without a pressed button so desktop UX matches the old
	# instant-tap feel.
	if event is InputEventScreenDrag and _placing_held and event.index == _placing_finger:
		_update_ghost_position(event.position)
		queue_redraw()
	elif event is InputEventMouseMotion:
		_update_ghost_position(event.position)
		queue_redraw()


## Screen (window/viewport) position → this grid node's local space. MUST invert
## the camera (canvas) transform: under any zoom≠1 or pan, screen and world space
## diverge, so the old `screen_pos - global_position` mapped taps to the wrong
## cell (verified: at zoom 2x a tap on cell (2,4) derived cell (-1,-11)). Mirrors
## the world→screen conversion already used correctly for the radial hit-test.
func _screen_to_local(screen_pos: Vector2) -> Vector2:
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return world_pos - global_position


func _update_ghost_position(screen_pos: Vector2) -> void:
	var local_pos: Vector2 = _screen_to_local(screen_pos)
	var gx: int = int(local_pos.x) / CELL_SIZE
	var gy: int = int(local_pos.y) / CELL_SIZE

	# Check if mouse is within this grid area (BEFORE any inversion)
	if local_pos.x < 0 or local_pos.x > GRID_COLS * CELL_SIZE \
	   or local_pos.y < 0 or local_pos.y > GRID_ROWS * CELL_SIZE:
		_is_hovering = false
		ghost_valid = false
		return

	_is_hovering = true

	# Clamp so building footprint stays in bounds
	gx = clampi(gx, 0, GRID_COLS - selected_building.grid_size.x)
	gy = clampi(gy, 0, GRID_ROWS - selected_building.grid_size.y)

	# T-085: Invert grid Y for flipped player (player 2 in multiplayer).
	var sim_gy: int = gy
	if GameManager.simulation:
		var local_idx: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
		if local_idx == 1:
			sim_gy = (GRID_ROWS - selected_building.grid_size.y) - gy

	ghost_grid_pos = Vector2i(gx, sim_gy)

	if GameManager.simulation:
		ghost_valid = GameManager.simulation.can_place_building(
			GameManager.local_player_id,
			selected_building.id,
			gx, sim_gy  # T-085: use inverted row, not visual row
		)
	else:
		ghost_valid = false


func _place_building() -> void:
	var cmd := Command.place_building(
		GameManager.local_player_id,
		selected_building.id,
		ghost_grid_pos.x,
		ghost_grid_pos.y
	)
	NetworkManager.send_command(cmd)
	queue_redraw()


func select_building(building_data: BuildingData) -> void:
	selected_building = building_data
	ghost_grid_pos = Vector2i(-1, -1)
	ghost_valid = false
	queue_redraw()


func deselect_building() -> void:
	selected_building = null
	ghost_grid_pos = Vector2i(-1, -1)
	ghost_valid = false
	_is_hovering = false
	_placing_held = false
	_placing_finger = -1
	queue_redraw()
	building_deselected.emit()


func _cancel_placement_drag() -> void:
	_placing_held = false
	_placing_finger = -1
	_is_hovering = false
	ghost_valid = false
	queue_redraw()


# T-045: Radial menu state
var _radial_menu: Node2D = null
var _radial_building_id: int = -1

func _try_sell_building(screen_pos: Vector2) -> void:
	if GameManager.simulation == null:
		return
	var local_pos: Vector2 = _screen_to_local(screen_pos)
	if local_pos.x < 0 or local_pos.x > GRID_COLS * CELL_SIZE \
	   or local_pos.y < 0 or local_pos.y > GRID_ROWS * CELL_SIZE:
		return

	var gx: int = int(local_pos.x) / CELL_SIZE
	# T-085: visual → sim row inversion for flipped player (reflection is self-inverse).
	var sim_gy: int = _visual_row(int(local_pos.y) / CELL_SIZE)

	var grid: Array = GameManager.simulation.grid_cells[player_index]
	var entity_id: int = grid[sim_gy][gx]
	if entity_id == -1:
		return

	var cmd := Command.sell_building(GameManager.local_player_id, entity_id)
	NetworkManager.send_command(cmd)


## T-045: Show radial menu on tapping owned building (no building selected for placement)
func _try_show_radial(screen_pos: Vector2) -> bool:
	if GameManager.simulation == null:
		return false
	var local_pos: Vector2 = _screen_to_local(screen_pos)
	if local_pos.x < 0 or local_pos.x > GRID_COLS * CELL_SIZE \
	   or local_pos.y < 0 or local_pos.y > GRID_ROWS * CELL_SIZE:
		_dismiss_radial()
		return false

	var gx: int = int(local_pos.x) / CELL_SIZE
	# T-085: visual → sim row inversion for flipped player (reflection is self-inverse).
	var sim_gy: int = _visual_row(int(local_pos.y) / CELL_SIZE)
	var grid: Array = GameManager.simulation.grid_cells[player_index]
	var entity_id: int = grid[sim_gy][gx]
	if entity_id == -1:
		_dismiss_radial()
		return false

	# Find entity data
	var entity: Dictionary = {}
	for e in GameManager.simulation.entities:
		if e.id == entity_id:
			entity = e
			break
	if entity.is_empty():
		return false

	_show_radial_menu(entity, local_pos)
	return true


func _show_radial_menu(entity: Dictionary, local_pos: Vector2) -> void:
	_dismiss_radial()
	_radial_building_id = entity.id

	_radial_menu = Node2D.new()
	_radial_menu.position = local_pos
	_radial_menu.z_index = 100
	add_child(_radial_menu)

	var bd = GameManager.simulation.building_registry.get(entity.get("building_type", &""))
	var refund: int = 0
	if bd:
		refund = bd.gold_cost * bd.sell_refund_percent / 100

	# --- Kingdom Rush-style dark backdrop circle ---
	var backdrop := Node2D.new()
	backdrop.z_index = -1
	_radial_menu.add_child(backdrop)
	backdrop.draw.connect(func():
		# Dark circle behind everything
		backdrop.draw_circle(Vector2.ZERO, 55, Color(0, 0, 0, 0.5))
		backdrop.draw_arc(Vector2.ZERO, 55, 0, TAU, 24, Color(0.6, 0.45, 0.15, 0.4), 2.0)
		# Inner highlight ring around building
		backdrop.draw_arc(Vector2.ZERO, 18, 0, TAU, 16, Color(1.0, 0.85, 0.3, 0.35), 1.5)
	)
	# Animate backdrop scale-in
	backdrop.scale = Vector2.ZERO
	var bd_tw := backdrop.create_tween()
	bd_tw.tween_property(backdrop, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# --- Circular icon buttons (Kingdom Rush semicircle arrangement) ---
	# Icon assignments: Icon_03 = gold/sell, Icon_11 = info, Icon_09 = close/X
	var sell_icon: Texture2D = SpriteRegistry.get_ui_texture(&"Icon_03")
	var info_icon: Texture2D = SpriteRegistry.get_ui_texture(&"Icon_11")
	var close_icon: Texture2D = SpriteRegistry.get_ui_texture(&"Icon_09")

	var menu_items := [
		{"icon": sell_icon, "angle": PI + 0.3, "bg": Color(0.65, 0.48, 0.08), "border": Color(0.9, 0.7, 0.15), "action": "sell", "tooltip": "Sell +%dg" % refund},
		{"icon": info_icon, "angle": -PI / 2, "bg": Color(0.15, 0.35, 0.6), "border": Color(0.3, 0.55, 0.85), "action": "info", "tooltip": "Info"},
		{"icon": close_icon, "angle": -0.3, "bg": Color(0.4, 0.18, 0.12), "border": Color(0.65, 0.3, 0.2), "action": "cancel", "tooltip": "Cancel"},
	]

	var radius: float = 44.0  # Distance from center
	var btn_size: float = 36.0  # Button diameter

	for i in menu_items.size():
		var item: Dictionary = menu_items[i]
		var target_pos := Vector2(cos(item.angle) * radius, sin(item.angle) * radius)

		# Circular button container (Node2D for draw + input)
		var btn_node := _RadialButton.new()
		btn_node.btn_size = btn_size
		btn_node.bg_color = item.bg
		btn_node.border_color = item.border
		btn_node.icon_texture = item.icon
		btn_node.tooltip_text = item.tooltip
		btn_node.action = item.action
		btn_node.entity = entity
		btn_node.grid_ref = self
		btn_node.position = Vector2.ZERO  # Start at center
		_radial_menu.add_child(btn_node)

		# Elastic pop-out animation (staggered)
		btn_node.scale = Vector2(0.1, 0.1)
		btn_node.modulate.a = 0.0
		var tw := btn_node.create_tween()
		tw.set_parallel(true)
		tw.tween_property(btn_node, "position", target_pos, 0.25).set_delay(i * 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn_node, "scale", Vector2(1, 1), 0.25).set_delay(i * 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn_node, "modulate:a", 1.0, 0.15).set_delay(i * 0.05)

	# --- Info banner below (building name + stats) ---
	if bd:
		var banner := Node2D.new()
		banner.position = Vector2(0, 65)
		banner.z_index = 2
		_radial_menu.add_child(banner)

		var banner_text: String = bd.display_name
		if bd.spawns_unit:
			banner_text += "  |  Spawns: %s" % bd.spawns_unit.display_name
		elif bd.is_tower:
			banner_text += "  |  DMG: %d  RNG: %d" % [bd.tower_damage, bd.tower_range]
		elif bd.income_bonus > 0:
			banner_text += "  |  +%d%% Income" % (15)  # Compound income display

		banner.draw.connect(func():
			# Dark rounded banner background
			var bw: float = maxf(banner_text.length() * 6.5, 120)
			banner.draw_rect(Rect2(-bw * 0.5 - 8, -10, bw + 16, 22), Color(0.08, 0.06, 0.04, 0.85))
			banner.draw_rect(Rect2(-bw * 0.5 - 8, -10, bw + 16, 22), Color(0.5, 0.38, 0.15, 0.5), false, 1.5)
			banner.draw_string(ThemeDB.fallback_font, Vector2(-bw * 0.5, 5), banner_text, HORIZONTAL_ALIGNMENT_LEFT, int(bw), 11, Color(0.92, 0.85, 0.65))
		)
		# Fade in banner
		banner.modulate.a = 0.0
		var b_tw := banner.create_tween()
		b_tw.tween_property(banner, "modulate:a", 1.0, 0.2).set_delay(0.15)


func _on_radial_action(action: String, entity: Dictionary) -> void:
	match action:
		"sell":
			var cmd := Command.sell_building(GameManager.local_player_id, entity.id)
			NetworkManager.send_command(cmd)
			SFX.play_ui("button_click")
		"info":
			_show_building_info(entity)
		"cancel":
			SFX.play_ui("card_hover")
	_dismiss_radial()


func _dismiss_radial() -> void:
	if _radial_menu and is_instance_valid(_radial_menu):
		# Animate out before freeing
		var tw := _radial_menu.create_tween()
		tw.tween_property(_radial_menu, "scale", Vector2(0.3, 0.3), 0.12).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_radial_menu, "modulate:a", 0.0, 0.12)
		tw.tween_callback(_radial_menu.queue_free)
		_radial_menu = null
	_radial_building_id = -1


func _show_building_info(entity: Dictionary) -> void:
	var bd = GameManager.simulation.building_registry.get(entity.get("building_type", &""))
	if bd == null:
		return

	# Kingdom Rush-style info panel (detailed stats popup)
	var info_panel := Control.new()
	info_panel.set_anchors_preset(Control.PRESET_CENTER)
	info_panel.position = Vector2(110, 300)
	info_panel.size = Vector2(500, 200)
	info_panel.z_index = 150
	get_tree().root.add_child(info_panel)

	# Dark panel background
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.08, 0.05, 0.92)
	panel_style.border_color = Color(0.6, 0.45, 0.15, 0.7)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	info_panel.add_child(panel)

	# Building name (gold, large)
	var name_lbl := Label.new()
	name_lbl.text = bd.display_name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	name_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	name_lbl.add_theme_constant_override("outline_size", 2)
	name_lbl.position = Vector2(16, 12)
	panel.add_child(name_lbl)

	# Stats lines
	var stats_text: String = ""
	stats_text += "Cost: %dg  |  Sell: %dg\n" % [bd.gold_cost, bd.gold_cost * bd.sell_refund_percent / 100]
	if bd.spawns_unit:
		var ud: UnitData = bd.spawns_unit
		stats_text += "Spawns: %s (every %.1fs)\n" % [ud.display_name, bd.spawn_interval_ticks / 10.0]
		stats_text += "HP: %d  DMG: %d  SPD: %d  RNG: %d\n" % [ud.max_hp, ud.attack_damage, ud.move_speed, ud.attack_range]
		if ud.skill_id != &"":
			stats_text += "Skill: %s\n" % ud.skill_id.capitalize().replace("_", " ")
	elif bd.is_tower:
		stats_text += "Tower — DMG: %d  RNG: %d cells  SPD: %.1f/s\n" % [bd.tower_damage, bd.tower_range, 10.0 / bd.tower_attack_speed]
	elif bd.income_bonus > 0:
		stats_text += "Economy — +15%% income bonus (multiplicative)\n"

	var stats_lbl := Label.new()
	stats_lbl.text = stats_text
	stats_lbl.add_theme_font_size_override("font_size", 13)
	stats_lbl.add_theme_color_override("font_color", Color(0.82, 0.78, 0.65))
	stats_lbl.position = Vector2(16, 42)
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_lbl.size = Vector2(468, 140)
	panel.add_child(stats_lbl)

	# Building sprite icon (top right)
	var building_tex: Texture2D = SpriteRegistry.get_building_sprite(entity.get("building_type", &""), entity.team)
	if building_tex:
		var icon := TextureRect.new()
		icon.texture = building_tex
		icon.position = Vector2(400, 10)
		icon.size = Vector2(70, 70)
		icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		panel.add_child(icon)

	# Tap anywhere to dismiss
	var dismiss_btn := Button.new()
	dismiss_btn.text = "Close"
	dismiss_btn.position = Vector2(200, 160)
	dismiss_btn.custom_minimum_size = Vector2(100, 30)
	dismiss_btn.add_theme_font_size_override("font_size", 13)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.3, 0.22, 0.1, 0.8)
	close_style.border_color = Color(0.5, 0.38, 0.18, 0.5)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(6)
	close_style.set_content_margin_all(4)
	dismiss_btn.add_theme_stylebox_override("normal", close_style)
	dismiss_btn.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	dismiss_btn.pressed.connect(func(): info_panel.queue_free())
	panel.add_child(dismiss_btn)

	# Scale-in animation
	info_panel.scale = Vector2(0.5, 0.5)
	info_panel.pivot_offset = info_panel.size * 0.5
	var tw := info_panel.create_tween()
	tw.tween_property(info_panel, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Auto-dismiss after 8s
	var dismiss_tw := info_panel.create_tween()
	dismiss_tw.tween_interval(8.0)
	dismiss_tw.tween_property(info_panel, "modulate:a", 0.0, 0.3)
	dismiss_tw.tween_callback(info_panel.queue_free)


## Kingdom Rush-style circular radial button with icon
class _RadialButton extends Node2D:
	var btn_size: float = 36.0
	var bg_color := Color(0.3, 0.2, 0.1)
	var border_color := Color(0.6, 0.4, 0.15)
	var icon_texture: Texture2D = null
	var tooltip_text: String = ""
	var action: String = ""
	var entity: Dictionary = {}
	var grid_ref: Node2D = null
	var _hover: bool = false

	func _ready() -> void:
		# Input area
		var area := Area2D.new()
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = btn_size * 0.5
		shape.shape = circle
		area.add_child(shape)
		area.input_pickable = true
		area.input_event.connect(_on_input_event)
		area.mouse_entered.connect(func(): _hover = true; queue_redraw())
		area.mouse_exited.connect(func(): _hover = false; queue_redraw())
		add_child(area)

	func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if grid_ref and grid_ref.has_method("_on_radial_action"):
				grid_ref._on_radial_action(action, entity)
			get_viewport().set_input_as_handled()

	func _draw() -> void:
		var r: float = btn_size * 0.5
		var hover_boost: float = 1.15 if _hover else 1.0

		# Outer shadow
		draw_circle(Vector2(1, 2), r + 1, Color(0, 0, 0, 0.4))
		# Background circle
		var bg := bg_color.lightened(0.1) if _hover else bg_color
		draw_circle(Vector2.ZERO, r * hover_boost, bg)
		# Border ring
		draw_arc(Vector2.ZERO, r * hover_boost, 0, TAU, 20, border_color, 2.5)
		# Inner bright highlight (top half)
		draw_arc(Vector2.ZERO, r * 0.75 * hover_boost, PI * 1.1, PI * 1.9, 10, Color(1, 1, 1, 0.12), r * 0.3)

		# Icon
		if icon_texture:
			var icon_s: float = (btn_size * 0.55) * hover_boost
			draw_texture_rect(icon_texture, Rect2(-icon_s * 0.5, -icon_s * 0.5, icon_s, icon_s), false)

		# Tooltip text below
		if tooltip_text != "":
			draw_string(ThemeDB.fallback_font, Vector2(-30, r + 14), tooltip_text,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 9,
				Color(0.95, 0.88, 0.65) if _hover else Color(0.75, 0.68, 0.5))
