## Match end screen with detailed stats, trophy change, and restart.
extends Control

@onready var result_label: Label = %ResultLabel
@onready var detail_label: Label = %DetailLabel
@onready var stats_label: Label = %StatsLabel
@onready var trophy_label: Label = %TrophyLabel
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton


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
	visible = false
	EventBus.match_ended.connect(_on_match_ended)
	if restart_button:
		restart_button.pressed.connect(_on_restart)
	if menu_button:
		menu_button.pressed.connect(_on_menu)


func _on_match_ended(winning_team: int) -> void:
	visible = true
	SFX.stop_ambient()  # T-030: Fade out battlefield ambient

	var local_team: int = 0
	var enemy_team: int = 1
	var local_faction: StringName = &""
	if GameManager.simulation:
		for player in GameManager.simulation.players:
			if player.id == GameManager.local_player_id:
				local_team = player.team
				enemy_team = 1 - local_team
				local_faction = player.faction
				break

	var won: bool = (winning_team == local_team)

	# T-100: dim overlay relaxed from 88% → 40% so arena stays visible behind
	# the panel — player feels "still in the match", not kicked to a menu.
	var overlay_node = get_node_or_null("Overlay")
	if overlay_node and overlay_node is ColorRect:
		overlay_node.color = Color(0, 0, 0, 0.40)

	# T-100: 0-3 star rating from own-castle HP remaining.
	# 75%+ = 3, 40-74% = 2, 1-39% = 1, dead = 0 (grayed-out on defeat).
	var hp_ratio: float = _compute_castle_hp_ratio(local_team)
	var star_count: int = 0
	if won:
		if hp_ratio >= 0.75: star_count = 3
		elif hp_ratio >= 0.40: star_count = 2
		elif hp_ratio > 0.0: star_count = 1
		else: star_count = 1  # Safety: shouldn't happen on win
	else:
		star_count = 0
	_spawn_star_row(won, star_count)

	# Near-opaque themed backdrop behind the whole results block. The previous
	# regularpaper NinePatch at alpha 0.3 was too translucent — stats/trophy
	# text visually collided with battlefield sprites behind it. StyleBoxFlat
	# panel parented to SELF (root Control, so manual rect is respected),
	# inserted right after the Overlay so ribbon/stars/VBox draw on top of it.
	# Exact rect is set in _layout_result_decor() once the VBox has sorted.
	_free_decor_node("ResultsBackdrop")
	var backdrop := Panel.new()
	backdrop.name = "ResultsBackdrop"
	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.14, 0.10, 0.055, 0.96)
	backdrop_style.border_color = Color(0.55, 0.42, 0.2, 0.9)
	backdrop_style.set_border_width_all(3)
	backdrop_style.set_corner_radius_all(16)
	backdrop_style.shadow_color = Color(0, 0, 0, 0.5)
	backdrop_style.shadow_size = 10
	backdrop_style.shadow_offset = Vector2(0, 4)
	backdrop.add_theme_stylebox_override("panel", backdrop_style)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.position = Vector2(92, 330)       # Estimate; refined after layout
	backdrop.size = Vector2(720.0 - 92.0 * 2.0, 560)
	add_child(backdrop)
	move_child(backdrop, 1)  # Above Overlay (0), below everything else

	# Tiny Swords ribbon behind result title — NinePatchRect. Parented to SELF,
	# NOT the VBox: VBoxContainer discards manual position/size on sort
	# (container rule), which squashed the ribbon to label height. Placed in
	# tree order after the backdrop and before the VBox so it sits behind the
	# title text; final position comes from the title's settled rect.
	_free_decor_node("TitleRibbon")
	var ribbon: NinePatchRect = null
	var ribbon_color: String = "ribbon_yellow.png" if won else "ribbon_red.png"
	var ribbon_tex = _load_texture("res://assets/sprites/ui/ninepatch/" + ribbon_color)
	if ribbon_tex:
		ribbon = NinePatchRect.new()
		ribbon.name = "TitleRibbon"
		ribbon.texture = ribbon_tex
		ribbon.patch_margin_left = 98
		ribbon.patch_margin_right = 97
		ribbon.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		ribbon.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ribbon.position = Vector2(110, 400)    # Estimate; refined after layout
		ribbon.size = Vector2(500, 103)
		ribbon.modulate.a = 0.85
		add_child(ribbon)
		move_child(ribbon, 2)  # Above backdrop, below VBox

	# VF-6: Animated result title with glow
	if won:
		result_label.text = "VICTORY!"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
		result_label.add_theme_color_override("font_outline_color", Color(0.6, 0.35, 0.05))
		result_label.add_theme_constant_override("outline_size", 5)
		result_label.add_theme_font_size_override("font_size", 46)
		SFX.play_music("victory_fanfare", false)
		SFX.play_victory()
		# Scale punch animation
		result_label.scale = Vector2(0.2, 0.2)
		result_label.pivot_offset = result_label.size * 0.5
		var tw := result_label.create_tween()
		tw.tween_property(result_label, "scale", Vector2(1.2, 1.2), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(result_label, "scale", Vector2(1.0, 1.0), 0.15)
		# Pulsing glow
		var glow_tw := result_label.create_tween().set_loops()
		glow_tw.tween_property(result_label, "modulate", Color(1.15, 1.1, 0.95), 0.6)
		glow_tw.tween_property(result_label, "modulate", Color(1.0, 1.0, 1.0), 0.6)
		_spawn_confetti()
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.15))
		result_label.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.03))
		result_label.add_theme_constant_override("outline_size", 4)
		result_label.add_theme_font_size_override("font_size", 40)
		SFX.play_music("defeat_fanfare", false)
		SFX.play_defeat()
		# Subdued fade-in
		result_label.modulate.a = 0.0
		var tw := result_label.create_tween()
		tw.tween_property(result_label, "modulate:a", 1.0, 0.5)
		# T-048: Encouragement text on defeat
		if detail_label:
			detail_label.text = "Almost! You'll get them next time."
			detail_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5, 0.9))
			detail_label.add_theme_font_size_override("font_size", 16)

	# VF-6: Style ALL labels with outlines for readability
	for label_node in [detail_label, stats_label, trophy_label]:
		if label_node:
			label_node.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02))
			label_node.add_theme_constant_override("outline_size", 3)

	# VF-6: Style buttons — Kingdom Rush parchment feel
	_style_end_button(restart_button, "PLAY AGAIN" if won else "TRY AGAIN",
		Color(0.82, 0.62, 0.08) if won else Color(0.45, 0.32, 0.12),
		Color(1.0, 0.82, 0.2) if won else Color(0.6, 0.45, 0.2), 20)
	_style_end_button(menu_button, "MAIN MENU",
		Color(0.2, 0.15, 0.08), Color(0.45, 0.35, 0.18), 16)

	# Gather match stats
	var buildings_count: int = 0
	var gold: int = 0
	if GameManager.simulation:
		var pi: int = GameManager.simulation.get_player_index(GameManager.local_player_id)
		for entity in GameManager.simulation.entities:
			if entity.get("player_index", -1) == pi and entity.type == "building":
				buildings_count += 1
		if pi >= 0 and pi < GameManager.simulation.players.size():
			gold = FP.to_int(GameManager.simulation.players[pi].get("total_gold_earned", GameManager.simulation.players[pi].get("gold", 0)))

	var match_time: int = GameManager.current_tick / GameManager.TICK_RATE
	var minutes: int = match_time / 60
	var secs: int = match_time % 60

	var spawned: int = GameManager.simulation.units_spawned[local_team] if GameManager.simulation else 0
	var killed: int = GameManager.simulation.units_killed[local_team] if GameManager.simulation else 0
	var enemy_killed: int = GameManager.simulation.units_killed[enemy_team] if GameManager.simulation else 0
	var total_dmg: int = GameManager.simulation.total_damage[local_team] if GameManager.simulation else 0

	# T-017: Kill breakdown + buildings + gold + duration
	var lines: PackedStringArray = []
	lines.append("Match Time: %d:%02d" % [minutes, secs])
	lines.append("Buildings Placed: %d" % buildings_count)
	lines.append("")
	lines.append("Your Units Killed: %d | Enemy Units Killed: %d" % [enemy_killed, killed])
	lines.append("Units Spawned: %d | Total Damage: %d" % [spawned, total_dmg])
	if gold > 0:
		lines.append("Gold Earned: %d" % gold)

	# T-017: MVP unit — find unit type with highest damage from surviving units
	var mvp_type: StringName = &""
	var mvp_dmg: int = 0
	if GameManager.simulation:
		# Count damage per unit type from simulation entities
		var type_damage: Dictionary = {}
		for entity in GameManager.simulation.entities:
			if entity.type == "unit" and entity.team == local_team:
				var ut: StringName = entity.get("unit_type", &"")
				var dmg: int = entity.get("damage_dealt", 0)
				type_damage[ut] = type_damage.get(ut, 0) + dmg
		for ut in type_damage:
			if type_damage[ut] > mvp_dmg:
				mvp_dmg = type_damage[ut]
				mvp_type = ut
	if mvp_type != &"":
		lines.append("")
		lines.append("MVP: %s (%d damage)" % [mvp_type.capitalize(), mvp_dmg])

	# VF-6: Build styled stat cards instead of plain text
	detail_label.text = ""  # Clear — we'll build custom cards
	_build_stat_cards(won, minutes, secs, buildings_count, enemy_killed, killed, spawned, total_dmg, gold, mvp_type, mvp_dmg)

	# Record to persistent data
	var old_trophies: int = PlayerData.trophies
	PlayerData.record_match_result(won, local_faction, match_time, buildings_count)
	var new_trophies: int = PlayerData.trophies

	# VF-6: Trophy change with count-up animation
	var trophy_change: int = new_trophies - old_trophies
	var trophy_sign: String = "+" if trophy_change > 0 else ""
	if trophy_label:
		trophy_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if won else Color(0.7, 0.5, 0.3))
		# Animate count from old to new
		var display_trophies: int = old_trophies
		trophy_label.text = "Trophies: %d" % display_trophies
		var trophy_tw := create_tween()
		trophy_tw.tween_method(func(val: float):
			trophy_label.text = "Trophies: %s%d  (%d — %s)" % [
				trophy_sign, int(val) - old_trophies, int(val), PlayerData.get_rank_name()
			]
		, float(old_trophies), float(new_trophies), 1.0).set_delay(0.8)

	# Overall stats
	if stats_label:
		stats_label.text = "Record: %dW / %dL | Total Games: %d" % [
			PlayerData.games_won, PlayerData.games_played - PlayerData.games_won, PlayerData.games_played
		]

	# T-017: Add share button
	_add_share_button(won, minutes, secs, killed, buildings_count, mvp_type)

	# Position ribbon/stars/backdrop off the title's SETTLED rect (fire and
	# forget — the coroutine waits for the container layout pass).
	_layout_result_decor(backdrop, ribbon)


## Remove a previously-spawned decor node by name (end screen can be re-shown).
## Rename before queue_free so a same-frame replacement can reuse the name.
func _free_decor_node(node_name: String) -> void:
	var old = get_node_or_null(NodePath(node_name))
	if old:
		old.name = node_name + "_old"
		old.queue_free()


## Positions the title ribbon, star row, and backdrop against the ACTUAL
## laid-out title rect. Runs two frames after _on_match_ended so the
## VBoxContainer has sorted (labels/stat cards/share button all added the
## same frame). Uses layout `position`/`size` (unaffected by the title's
## scale-punch tween, which only animates the render transform).
func _layout_result_decor(backdrop: Panel, ribbon: NinePatchRect) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	var vbox = get_node_or_null("VBox")
	if vbox == null or result_label == null:
		return
	# EndScreen root is FULL_RECT at the layer origin, so VBox-relative
	# coordinates ARE screen coordinates.
	var title_top: float = vbox.position.y + result_label.position.y
	var title_center_y: float = title_top + result_label.size.y * 0.5

	if is_instance_valid(ribbon):
		ribbon.position = Vector2(360.0 - ribbon.size.x * 0.5, title_center_y - ribbon.size.y * 0.5)

	var star_row = get_node_or_null("StarRow")
	if star_row:
		star_row.position = Vector2(360.0, title_top - 52.0)

	if is_instance_valid(backdrop):
		# Cover stars (top) through the last VBox row (bottom) with padding.
		var top_y: float = title_top - 96.0
		var bottom_y: float = vbox.position.y + vbox.size.y + 24.0
		backdrop.position = Vector2(92.0, top_y)
		backdrop.size = Vector2(720.0 - 92.0 * 2.0, bottom_y - top_y)


var _share_text: String = ""

func _add_share_button(won: bool, mins: int, secs: int, kills: int, buildings: int, mvp: StringName) -> void:
	_share_text = "%s in Castle Fight!\nTime: %d:%02d | Kills: %d | Buildings: %d" % [
		"Victory" if won else "Defeat", mins, secs, kills, buildings
	]
	if mvp != &"":
		_share_text += " | MVP: %s" % mvp.capitalize()

	# Check if share button already exists
	var existing = get_node_or_null("ShareButton")
	if existing:
		return

	var share_btn := Button.new()
	share_btn.name = "ShareButton"
	share_btn.text = "Share Result"
	share_btn.custom_minimum_size = Vector2(180, 40)
	share_btn.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.2, 0.15, 0.8)
	style.border_color = Color(0.6, 0.5, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	share_btn.add_theme_stylebox_override("normal", style)
	share_btn.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	share_btn.pressed.connect(_on_share)

	# Add to the VBox
	var vbox = get_node_or_null("VBox")
	if vbox:
		vbox.add_child(share_btn)
	else:
		share_btn.position = Vector2(270, 750)
		add_child(share_btn)


func _on_share() -> void:
	DisplayServer.clipboard_set(_share_text)
	SFX.play_ui("card_select")
	# Brief "Copied!" feedback
	var copied := Label.new()
	copied.text = "Copied to clipboard!"
	copied.add_theme_font_size_override("font_size", 14)
	copied.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	copied.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copied.position = Vector2(220, 800)
	copied.size = Vector2(280, 30)
	add_child(copied)
	var tw := copied.create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(copied, "modulate:a", 0.0, 0.5)
	tw.tween_callback(copied.queue_free)


func _on_restart() -> void:
	SFX.play_ui("button_click")
	visible = false
	# CR-standard: after online match, "Play Again" returns to menu for new
	# matchmaking search (can't rematch the same opponent directly).
	# Offline matches restart immediately.
	if GameManager.is_online_match:
		GameManager.reset_match()
		NetworkManager._reset_to_offline()
		SceneTransition.change_scene("res://scenes/ui/main_menu.tscn")
	else:
		SceneTransition.change_scene("res://scenes/game/game_arena.tscn")


func _on_menu() -> void:
	SFX.play_ui("button_click")
	visible = false
	GameManager.reset_match()
	if not NetworkManager.offline_mode:
		NetworkManager._reset_to_offline()
	SceneTransition.change_scene("res://scenes/ui/main_menu.tscn")


## T-100: Compute own-team castle HP ratio at match end for star rating.
func _compute_castle_hp_ratio(local_team: int) -> float:
	if GameManager.simulation == null:
		return 0.0
	for castle in GameManager.simulation.castles:
		if castle.team == local_team:
			var maxv: float = FP.to_float(castle.get("max_hp", FP.from_int(1)))
			var hpv: float = FP.to_float(castle.get("hp", FP.from_int(0)))
			if maxv <= 0.0:
				return 0.0
			return clampf(hpv / maxv, 0.0, 1.0)
	return 0.0


## T-100: Spawn the star-row above the title ribbon and play the pop sequence.
func _spawn_star_row(won: bool, star_count: int) -> void:
	# Remove any existing StarRow (on replay the end screen is re-shown).
	_free_decor_node("StarRow")

	var row := Node2D.new()
	row.name = "StarRow"
	row.z_index = 5
	# Anchored to the results panel, just above the title ribbon — NOT to
	# screen-top (previous y=60 left the stars floating over the battlefield).
	# Estimate here; _layout_result_decor() refines it from the title's rect.
	row.position = Vector2(360, 430)
	add_child(row)

	var slot_spacing: float = 100.0
	for i in 3:
		var star := _StarSlot.new()
		star.star_on = (i < star_count) if won else false
		star.star_dim = not won
		star.position = Vector2((i - 1) * slot_spacing, 0)
		row.add_child(star)

		# Pop sequence: dim outline always visible; bright star scales from
		# 0 → 1.2 → 1.0 over 300ms ease-out-back with a 200ms gap between stars.
		if star.star_on:
			star.set_bright_scale(0.0)
			var tw := star.create_tween()
			tw.tween_interval(0.2 * i)
			tw.tween_method(Callable(star, "set_bright_scale"), 0.0, 1.2, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_method(Callable(star, "set_bright_scale"), 1.2, 1.0, 0.12).set_ease(Tween.EASE_OUT)
			# Radial flash behind star during the overshoot peak.
			tw.parallel().tween_callback(star.flash).set_delay(0.2 * i + 0.15)


class _StarSlot extends Node2D:
	var star_on: bool = false
	var star_dim: bool = false  # Defeat shows all three as dim
	var _bright_scale: float = 1.0
	var _flash_alpha: float = 0.0
	var _flash_radius: float = 0.0

	func set_bright_scale(s: float) -> void:
		_bright_scale = s
		queue_redraw()

	func flash() -> void:
		var tw := create_tween()
		tw.tween_method(Callable(self, "_set_flash"), Vector2(0.0, 0.8), Vector2(80.0, 0.0), 0.2).set_ease(Tween.EASE_OUT)

	func _set_flash(state: Vector2) -> void:
		_flash_radius = state.x
		_flash_alpha = state.y
		queue_redraw()

	func _draw() -> void:
		# Radial flash (behind star)
		if _flash_alpha > 0.0:
			draw_circle(Vector2.ZERO, _flash_radius, Color(1.0, 0.95, 0.65, _flash_alpha))
		# Dim outline slot (always visible)
		_draw_star(30.0, Color(0.25, 0.2, 0.1, 0.5))
		# Bright star (on) — scaled by the pop animation
		if star_on and _bright_scale > 0.01:
			_draw_star(30.0 * _bright_scale, Color(1.0, 0.85, 0.25, 1.0))
		elif star_dim:
			# Defeat: show dim crossed-out star
			_draw_star(30.0, Color(0.45, 0.4, 0.3, 0.75))
			draw_line(Vector2(-20, -20), Vector2(20, 20), Color(0.15, 0.08, 0.04, 0.9), 3.0)
			draw_line(Vector2(-20, 20), Vector2(20, -20), Color(0.15, 0.08, 0.04, 0.9), 3.0)

	func _draw_star(r: float, col: Color) -> void:
		# 5-point star via 10-vertex polygon.
		var pts: PackedVector2Array = PackedVector2Array()
		for i in 10:
			var angle: float = -PI * 0.5 + (i * PI / 5.0)
			var radius: float = r if (i % 2 == 0) else r * 0.45
			pts.append(Vector2(cos(angle) * radius, sin(angle) * radius))
		draw_colored_polygon(pts, col)
		# Dark outline for legibility on parchment
		var outline: PackedVector2Array = pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.1, 0.07, 0.03, 0.85), 2.0, true)


## T-048: Gold confetti particles on victory
func _spawn_confetti() -> void:
	var confetti_node := Node2D.new()
	confetti_node.z_index = 100
	confetti_node.name = "Confetti"
	add_child(confetti_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())

	for i in 20:
		var particle := ColorRect.new()
		var colors := [Color(1, 0.85, 0.2), Color(0.3, 0.8, 0.4), Color(0.4, 0.6, 1.0), Color(1.0, 0.4, 0.3)]
		particle.color = colors[rng.randi() % colors.size()]
		particle.size = Vector2(rng.randf_range(4, 8), rng.randf_range(4, 8))
		var start_x: float = rng.randf_range(50, 670)
		particle.position = Vector2(start_x, -20)
		confetti_node.add_child(particle)

		var tw := particle.create_tween()
		var end_y: float = rng.randf_range(400, 900)
		var drift_x: float = rng.randf_range(-60, 60)
		var dur: float = rng.randf_range(1.0, 2.5)
		tw.set_parallel(true)
		tw.tween_property(particle, "position:y", end_y, dur).set_ease(Tween.EASE_IN)
		tw.tween_property(particle, "position:x", start_x + drift_x, dur)
		tw.tween_property(particle, "rotation", rng.randf_range(-TAU, TAU), dur)
		tw.tween_property(particle, "modulate:a", 0.0, dur * 0.3).set_delay(dur * 0.7)
		tw.chain().tween_callback(particle.queue_free)

	# Clean up confetti container after all particles done
	var cleanup_tw := confetti_node.create_tween()
	cleanup_tw.tween_interval(3.0)
	cleanup_tw.tween_callback(confetti_node.queue_free)


## VF-6: Style a button with Kingdom Rush parchment look
func _style_end_button(btn: Button, text: String, bg: Color, border: Color, font_size: int) -> void:
	if btn == null:
		return
	btn.text = text
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	style.shadow_offset = Vector2(1, 3)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = bg.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = bg.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	btn.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_constant_override("outline_size", 2)


## VF-6: Build styled stat cards (parchment bg, gold border, staggered reveal)
func _build_stat_cards(won: bool, mins: int, secs: int, buildings: int,
		enemy_killed: int, killed: int, spawned: int, total_dmg: int,
		gold: int, mvp_type: StringName, mvp_dmg: int) -> void:

	var vbox = get_node_or_null("VBox")
	if vbox == null:
		return

	# Remove old stat cards if any
	for child in vbox.get_children():
		if child.name.begins_with("StatCard"):
			child.queue_free()

	var stats := [
		["Time", "%d:%02d" % [mins, secs]],
		["Buildings", str(buildings)],
		["Kills", "%d enemies | %d lost" % [enemy_killed, killed]],
		["Spawned", "%d units | %d damage" % [spawned, total_dmg]],
	]
	if gold > 0:
		stats.append(["Gold", "%d earned" % gold])
	if mvp_type != &"":
		stats.append(["MVP", "%s (%d dmg)" % [mvp_type.capitalize(), mvp_dmg]])

	# T-048: MVP unit sprite spotlight
	var mvp_sprite_frames: SpriteFrames = null
	if mvp_type != &"":
		mvp_sprite_frames = SpriteRegistry.get_unit_sprites(mvp_type)

	for i in stats.size():
		var card := Panel.new()
		card.name = "StatCard%d" % i
		card.custom_minimum_size = Vector2(0, 32)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.28, 0.22, 0.14, 0.75)
		card_style.border_color = Color(0.55, 0.42, 0.15, 0.6) if won else Color(0.35, 0.25, 0.12, 0.5)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(6)
		card_style.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", card_style)

		var hbox := HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("separation", 8)
		card.add_child(hbox)

		var key_lbl := Label.new()
		key_lbl.text = stats[i][0]
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
		key_lbl.custom_minimum_size = Vector2(80, 0)
		hbox.add_child(key_lbl)

		# T-048: MVP sprite spotlight — add unit sprite before value label
		if stats[i][0] == "MVP" and mvp_sprite_frames:
			var mvp_spr := AnimatedSprite2D.new()
			mvp_spr.sprite_frames = mvp_sprite_frames
			mvp_spr.centered = true
			mvp_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var first_anim: StringName = mvp_sprite_frames.get_animation_names()[0]
			var frame_tex: Texture2D = mvp_sprite_frames.get_frame_texture(first_anim, 0)
			var frame_h: float = frame_tex.get_height() if frame_tex else 192.0
			var mvp_scale: float = 32.0 / maxf(frame_h, 1.0)
			mvp_spr.scale = Vector2(mvp_scale, mvp_scale)
			if mvp_sprite_frames.has_animation(&"idle"):
				mvp_spr.play(&"idle")
			var spr_container := CenterContainer.new()
			spr_container.custom_minimum_size = Vector2(36, 32)
			var sub := SubViewportContainer.new()
			sub.custom_minimum_size = Vector2(36, 32)
			sub.stretch = true
			var sv := SubViewport.new()
			sv.size = Vector2i(36, 32)
			sv.transparent_bg = true
			sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			mvp_spr.position = Vector2(18, 16)
			sv.add_child(mvp_spr)
			sub.add_child(sv)
			hbox.add_child(sub)
			# Gold highlight border on MVP card
			card_style.border_color = Color(1.0, 0.82, 0.2, 0.9)
			card_style.set_border_width_all(2)

		var val_lbl := Label.new()
		val_lbl.text = stats[i][1]
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(val_lbl)

		# Insert before buttons (after detail_label)
		var insert_idx: int = detail_label.get_index() + 1 + i
		vbox.add_child(card)
		vbox.move_child(card, mini(insert_idx, vbox.get_child_count() - 1))

		# Staggered slide-in animation.
		# T-100: delay stat reveal until AFTER the star-pop sequence finishes
		# (~0.9s for 3 stars) so the eye focuses on stars first, then stats.
		card.modulate.a = 0.0
		card.position.x += 30
		var tw := card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(i * 0.1 + 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(card, "position:x", 0, 0.3).set_delay(i * 0.1 + 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
