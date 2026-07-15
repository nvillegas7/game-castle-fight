## Clash Royale-style main menu with scenic Tiny Swords background,
## styled buttons with rounded corners, and 5 bottom tabs.
extends Control

# --- Tab content panels ---
@onready var battle_panel: Control = $ContentArea/BattlePanel
@onready var shop_panel: Control = $ContentArea/ShopPanel
@onready var army_panel: Control = $ContentArea/ArmyPanel
@onready var social_panel: Control = $ContentArea/SocialPanel
@onready var settings_panel: Control = $ContentArea/SettingsPanel

# --- Battle tab controls ---
@onready var kingdom_btn: Control = $ContentArea/BattlePanel/FactionRow/KingdomBtn
@onready var horde_btn: Control = $ContentArea/BattlePanel/FactionRow/HordeBtn
@onready var faction_desc: Label = $ContentArea/BattlePanel/FactionDesc
@onready var play_btn: Control = $ContentArea/BattlePanel/PlayBtn
@onready var online_btn: Control = $ContentArea/BattlePanel/OnlineBtn
@onready var status_label: Label = $ContentArea/BattlePanel/StatusLabel

# --- Header ---
@onready var trophy_label: Label = $Header/HeaderContent/TrophyLabel

# --- Tab buttons ---
@onready var tab_buttons: Array[Control] = []

var _selected_faction: StringName = &"kingdom"
var _current_tab: int = 2

# Ambient scenic clouds with uniform parallax (advanced in _process).
var _menu_clouds: Array = []

const FACTION_DESCRIPTIONS := {
	&"kingdom": "The Kingdom — Balanced faction with healing priests and heavy lancers. Mages burn packed enemies with fireball splash. Sustain-oriented, wins long fights.",
	&"horde": "The Horde — Aggressive faction with high burst damage. Raiders and Warlords hit hard. Cheap units, fast attacks, snowball or die.",
}


func _ready() -> void:
	# T-052: Castle Fight logo — 2x size, pushed down, with Banner.png backdrop
	var old_logo = battle_panel.get_node_or_null("Logo")
	if old_logo:
		var logo_path := "res://assets/sprites/ui/logo.png"
		var logo_tex = load(logo_path) if ResourceLoader.exists(logo_path) else null
		if logo_tex:
			old_logo.texture = logo_tex
			# Match loading screen logo exactly (loading uses world y=280..580,
			# 400 wide centered). BattlePanel origin is at world y=90, so
			# offset_top=190 maps to world y=280 and offset_bottom=490 maps
			# to world y=580. Keeps the scenic composition identical between
			# the two screens per user ask ("loading screen is reference").
			old_logo.offset_left = -200.0
			old_logo.offset_right = 200.0
			old_logo.offset_top = 190.0
			old_logo.offset_bottom = 490.0
			old_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# Scroll-paper banner backdrop removed per user — logo reads on the scenic bg.
		else:
			old_logo.visible = false
	# Hide redundant labels — logo shows name, progression display replaces "Choose faction"
	for lbl_name in ["Title", "ChooseLabel"]:
		var lbl = battle_panel.get_node_or_null(lbl_name)
		if lbl:
			lbl.visible = false
	_build_scenic_background()
	_build_tab_backdrop()
	_style_all_ui()
	_build_settings_tab()
	_build_army_tab()
	_build_social_tab()
	SFX.play_music("menu_theme")

	var tab_bar: HBoxContainer = $TabBar/TabButtons
	for child in tab_bar.get_children():
		tab_buttons.append(child)

	for i in tab_buttons.size():
		tab_buttons[i].get_node("TouchArea").pressed.connect(_select_tab.bind(i))
		_add_press_feedback(tab_buttons[i])

	# T-066: Single faction — hide faction selection, auto-select Kingdom
	_selected_faction = &"kingdom"
	var faction_row = battle_panel.get_node_or_null("FactionRow")
	if faction_row:
		faction_row.visible = false
	if faction_desc:
		faction_desc.text = "Build towers, spawn units, destroy the enemy castle!"
		# Slogan sized to match the BATTLE button label (font_size=28).
		# Positioned ABOVE the logo (world y=130..260 via BattlePanel offsets)
		# since the loading-screen reference uses world y=280..580 for the logo
		# and has no slogan — this sits in the sky gap between the header bar
		# (ends y=90) and the logo (starts y=280).
		faction_desc.add_theme_font_size_override("font_size", 28)
		faction_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		faction_desc.offset_top = 40.0
		faction_desc.offset_bottom = 170.0
		faction_desc.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
		faction_desc.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
		faction_desc.add_theme_constant_override("outline_size", 3)
	# BATTLE button + ribbon overlay the green plateau grass (world y=790..886).
	# User ask 2026-04-22: "put the Battle button and ribbon on top of the
	# green field on the cliff". Button centered on the 96px grass band; ribbon
	# wings may bleed ~15px into sky/cliff which reads as natural ribbon drape.
	# PLAY ONLINE stays in the water region below the plateau.
	if play_btn:
		play_btn.offset_left = -220.0
		play_btn.offset_right = 220.0
		play_btn.offset_top = 705.0   # world y=795 (5px below grass top at 790)
		play_btn.offset_bottom = 790.0  # world y=880 (6px above cliff top at 886)
	if online_btn:
		# Compact secondary chip (220x86) — subordinate to the 440px BATTLE ribbon,
		# clustered just below the island so it reads as one battle cluster.
		online_btn.offset_left = -110.0
		online_btn.offset_right = 110.0
		online_btn.offset_top = 900.0   # world y=990 (below cliff+foam)
		online_btn.offset_bottom = 986.0  # 86px tall
	play_btn.get_node("TouchArea").pressed.connect(_on_play)
	online_btn.get_node("TouchArea").pressed.connect(_on_play_online)
	_add_press_feedback(play_btn)
	_add_press_feedback(online_btn)

	EventBus.connected_to_server.connect(_on_connected)
	EventBus.disconnected_from_server.connect(_on_disconnected)
	EventBus.match_found.connect(_on_match_found)
	# 1B-2: without this, an in-lobby abort (build/version mismatch, config
	# timeout/conflict) left the menu stuck on "vs Opponent - Starting..." forever.
	NetworkManager.match_error.connect(_on_match_error)

	_select_tab(2)
	_update_faction_selection()
	_start_battle_pulse()
	_start_battle_shine_sweep()
	_build_shop_tab()
	# Header trophy count — previously only refreshed inside _do_reset(), so
	# the tscn default "New Commander" never updated with real trophies.
	_update_player_stats()
	# Progression display removed 2026-04-11 — too early in development for
	# trophies/ranks/arena progression. Functions kept for future use.
	# _build_progression_display()
	# _add_faction_mastery_badges()

	# Hide floating rank/stats — user requested removal
	if status_label:
		status_label.visible = false


# --- T-046: Progression Display ---

func _build_progression_display() -> void:
	# Arena banner + trophy progress bar — positioned BELOW logo (logo ends y=290)
	# BUG-MENU 2026-04-11: Previously at y=170 which overlapped logo area 50-290.
	var prog_panel := Panel.new()
	prog_panel.name = "ProgressionPanel"
	prog_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	prog_panel.position = Vector2(-220, 298)
	prog_panel.size = Vector2(440, 64)
	var prog_style := StyleBoxFlat.new()
	prog_style.bg_color = Color(0.12, 0.08, 0.04, 0.85)
	prog_style.border_color = Color(0.5, 0.38, 0.15, 0.6)
	prog_style.set_border_width_all(2)
	prog_style.set_corner_radius_all(10)
	prog_style.set_content_margin_all(8)
	prog_panel.add_theme_stylebox_override("panel", prog_style)
	prog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_panel.add_child(prog_panel)

	var prog := VBoxContainer.new()
	prog.name = "ProgressionDisplay"
	prog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prog.add_theme_constant_override("separation", 4)
	prog_panel.add_child(prog)

	# Arena name banner
	var arena_label := Label.new()
	arena_label.text = "%s Arena" % PlayerData.get_rank_name()
	arena_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arena_label.add_theme_font_size_override("font_size", 16)
	arena_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	arena_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	arena_label.add_theme_constant_override("outline_size", 3)
	prog.add_child(arena_label)

	# Trophy progress bar
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(300, 16)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.1, 0.06, 0.8)
	bg_style.border_color = Color(0.5, 0.38, 0.15, 0.6)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	prog.add_child(bar_bg)

	# Fill
	var thresholds := [0, 100, 300, 600, 1000, 1500]
	var current_tier: int = 0
	for i in range(thresholds.size() - 1):
		if PlayerData.trophies >= thresholds[i]:
			current_tier = i
	var tier_start: int = thresholds[current_tier]
	var tier_end: int = thresholds[mini(current_tier + 1, thresholds.size() - 1)]
	var trophy_ratio: float = 0.0
	if tier_end > tier_start:
		trophy_ratio = clampf(float(PlayerData.trophies - tier_start) / float(tier_end - tier_start), 0.0, 1.0)

	var fill := ColorRect.new()
	fill.position = Vector2(2, 2)
	fill.size = Vector2(296 * trophy_ratio, 12)
	fill.color = Color(0.9, 0.7, 0.15)
	bar_bg.add_child(fill)

	# Trophy count text
	var trophy_text := Label.new()
	trophy_text.text = "%d / %d" % [PlayerData.trophies, tier_end]
	trophy_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trophy_text.add_theme_font_size_override("font_size", 12)
	trophy_text.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55, 1.0))  # BUG-41: opaque gold for top-bar trophy text
	trophy_text.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03, 1.0))
	trophy_text.add_theme_constant_override("outline_size", 2)
	prog.add_child(trophy_text)

	# Win streak with flame icon (if applicable)
	if PlayerData.games_won > 0:
		var streak: int = _calc_win_streak()
		if streak >= 2:
			var streak_row := HBoxContainer.new()
			streak_row.alignment = BoxContainer.ALIGNMENT_CENTER
			streak_row.add_theme_constant_override("separation", 4)
			prog.add_child(streak_row)
			# Flame icon (procedural — small orange/red triangle)
			var flame := _FlameIcon.new()
			flame.custom_minimum_size = Vector2(16, 16)
			streak_row.add_child(flame)
			var streak_lbl := Label.new()
			streak_lbl.text = "%d" % streak
			streak_lbl.add_theme_font_size_override("font_size", 14)
			streak_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
			streak_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
			streak_lbl.add_theme_constant_override("outline_size", 2)
			streak_row.add_child(streak_lbl)

	# T-046: Miniature building cards from selected faction
	_build_faction_building_preview(battle_panel)

	# T-056: Game mode selection
	_build_mode_selector(battle_panel)


## T-056: Game mode selector — horizontal row of 3 mode buttons with description
var _mode_buttons: Array[Button] = []
var _mode_desc_label: Label = null
const MODE_DESCRIPTIONS := {
	0: "Classic match — standard rules",
	1: "2x income & spawn speed — fast games",
	2: "Both players use the same faction",
}

func _build_mode_selector(parent: Control) -> void:
	var mode_row := HBoxContainer.new()
	mode_row.name = "ModeRow"
	# BUG-MENU 2026-04-11: Moved up to y=440 so mode desc at y=494 doesn't collide
	# with FactionDesc at y=560. Previous y=500 put desc at y=550 overlapping.
	mode_row.position = Vector2(120, 440)
	mode_row.size = Vector2(480, 48)
	mode_row.add_theme_constant_override("separation", 12)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(mode_row)

	var modes := [
		{"id": GameManager.GameMode.STANDARD, "name": "Standard"},
		{"id": GameManager.GameMode.BLITZ, "name": "Blitz"},
		{"id": GameManager.GameMode.MIRROR, "name": "Mirror"},
	]

	for i in modes.size():
		var m: Dictionary = modes[i]
		var btn := Button.new()
		btn.text = m.name
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_mode_selected.bind(m.id))
		mode_row.add_child(btn)
		_mode_buttons.append(btn)

	# Description label below mode row (y=440+48+6 = 494)
	_mode_desc_label = Label.new()
	_mode_desc_label.name = "ModeDesc"
	_mode_desc_label.position = Vector2(120, 494)
	_mode_desc_label.size = Vector2(480, 20)
	_mode_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_desc_label.add_theme_font_size_override("font_size", 12)
	_mode_desc_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.68, 1.0))  # BUG-41: opaque cream for mode description
	_mode_desc_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03, 1.0))
	_mode_desc_label.add_theme_constant_override("outline_size", 2)
	parent.add_child(_mode_desc_label)

	_refresh_mode_buttons()


func _on_mode_selected(mode: int) -> void:
	SFX.play_ui("card_select")
	GameManager.selected_game_mode = mode as GameManager.GameMode
	_refresh_mode_buttons()


func _refresh_mode_buttons() -> void:
	var modes_enum := [GameManager.GameMode.STANDARD, GameManager.GameMode.BLITZ, GameManager.GameMode.MIRROR]
	for i in _mode_buttons.size():
		var btn: Button = _mode_buttons[i]
		var selected: bool = (modes_enum[i] == GameManager.selected_game_mode)
		var style := StyleBoxFlat.new()
		if selected:
			style.bg_color = Color(0.5, 0.38, 0.1, 0.9)
			style.border_color = Color(1.0, 0.82, 0.2, 0.85)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.2, 0.15, 0.1, 0.7)
			style.border_color = Color(0.4, 0.3, 0.15, 0.4)
			style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color(1, 0.9, 0.5) if selected else Color(0.6, 0.55, 0.4))
	# Update mode description text
	if _mode_desc_label:
		_mode_desc_label.text = MODE_DESCRIPTIONS.get(GameManager.selected_game_mode, "")


func _calc_win_streak() -> int:
	# Simple heuristic: if last game was a win, count recent wins
	# PlayerData doesn't track per-game history, so estimate from ratio
	if PlayerData.games_played == 0:
		return 0
	var win_rate: float = float(PlayerData.games_won) / float(PlayerData.games_played)
	if win_rate > 0.7 and PlayerData.games_won >= 3:
		return mini(PlayerData.games_won, 5)  # Cap display at 5
	return 0


## T-046: Miniature building cards — show 4 key buildings from selected faction
var _building_preview_row: HBoxContainer = null

func _build_faction_building_preview(parent: Control) -> void:
	_building_preview_row = HBoxContainer.new()
	_building_preview_row.name = "BuildingPreview"
	# BUG-MENU 2026-04-11: Below progression panel (298+64=362), not in logo area.
	_building_preview_row.position = Vector2(150, 370)
	_building_preview_row.size = Vector2(420, 50)
	_building_preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_building_preview_row.add_theme_constant_override("separation", 8)
	parent.add_child(_building_preview_row)
	_refresh_building_preview()


func _refresh_building_preview() -> void:
	if _building_preview_row == null:
		return
	for child in _building_preview_row.get_children():
		child.queue_free()
	var faction: FactionData = GameManager._faction_registry.get(_selected_faction)
	if faction == null:
		return
	# Show first 4 spawning buildings (skip walls, income-only, etc.)
	var shown: int = 0
	for bld: BuildingData in faction.buildings:
		if shown >= 4:
			break
		if bld.spawns_unit == null:
			continue
		var card := _create_mini_building_card(bld)
		_building_preview_row.add_child(card)
		shown += 1


func _create_mini_building_card(bld: BuildingData) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(90, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.04, 0.75)
	style.border_color = Color(0.45, 0.35, 0.15, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Building name
	var name_lbl := Label.new()
	name_lbl.text = bld.display_name
	name_lbl.position = Vector2(4, 2)
	name_lbl.size = Vector2(82, 16)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65))
	name_lbl.clip_text = true
	card.add_child(name_lbl)
	# Cost
	var cost_lbl := Label.new()
	cost_lbl.text = "%dg" % bld.gold_cost
	cost_lbl.position = Vector2(4, 18)
	cost_lbl.size = Vector2(40, 14)
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	card.add_child(cost_lbl)
	# Tier stars
	var stars_lbl := Label.new()
	var star_text: String = ""
	for _i in bld.tier:
		star_text += "*"
	stars_lbl.text = star_text
	stars_lbl.position = Vector2(50, 18)
	stars_lbl.size = Vector2(36, 14)
	stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stars_lbl.add_theme_font_size_override("font_size", 12)  # BUG-41 mobile readability
	stars_lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	card.add_child(stars_lbl)
	# Unit name (spawns)
	if bld.spawns_unit:
		var unit_lbl := Label.new()
		unit_lbl.text = bld.spawns_unit.display_name
		unit_lbl.position = Vector2(4, 30)
		unit_lbl.size = Vector2(82, 14)
		unit_lbl.add_theme_font_size_override("font_size", 12)
		unit_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		unit_lbl.clip_text = true
		card.add_child(unit_lbl)
	return card


## T-046: Faction mastery badge — small badge next to faction button based on wins
func _add_faction_mastery_badges() -> void:
	for btn_data in [{&"btn": kingdom_btn, &"faction": &"kingdom"}, {&"btn": horde_btn, &"faction": &"horde"}]:
		var btn: Control = btn_data[&"btn"]
		var faction_id: StringName = btn_data[&"faction"]
		var mastery: String = PlayerData.get_faction_mastery(faction_id)
		if mastery == "":
			continue
		# Mastery tier from name
		var tier: int = 1
		match mastery:
			"Master": tier = 4
			"Veteran": tier = 3
			"Skilled": tier = 2
		var badge := _MasteryBadge.new()
		badge._tier = tier
		badge._faction_color = Color(0.3, 0.5, 1.0) if faction_id == &"kingdom" else Color(1.0, 0.3, 0.2)
		badge.position = Vector2(btn.size.x - 20, -4)
		badge.z_index = 5
		btn.add_child(badge)


## Flame icon — small procedural fire shape for win streak display
class _FlameIcon extends Control:
	func _draw() -> void:
		var cx: float = size.x * 0.5
		var h: float = size.y
		# Outer flame (orange)
		var pts := PackedVector2Array([
			Vector2(cx, 0), Vector2(cx + 5, h * 0.4),
			Vector2(cx + 4, h * 0.7), Vector2(cx + 2, h),
			Vector2(cx - 2, h), Vector2(cx - 4, h * 0.7),
			Vector2(cx - 5, h * 0.4),
		])
		draw_colored_polygon(pts, Color(1.0, 0.5, 0.1))
		# Inner flame (yellow)
		var inner := PackedVector2Array([
			Vector2(cx, h * 0.25), Vector2(cx + 3, h * 0.55),
			Vector2(cx + 2, h * 0.8), Vector2(cx, h),
			Vector2(cx - 2, h * 0.8), Vector2(cx - 3, h * 0.55),
		])
		draw_colored_polygon(inner, Color(1.0, 0.85, 0.2))


## Mastery badge — small shield shape with tier stars
class _MasteryBadge extends Node2D:
	var _tier: int = 1
	var _faction_color := Color.WHITE

	func _draw() -> void:
		# Shield shape
		var pts := PackedVector2Array([
			Vector2(0, -8), Vector2(8, -4), Vector2(8, 4),
			Vector2(0, 10), Vector2(-8, 4), Vector2(-8, -4),
		])
		draw_colored_polygon(pts, Color(_faction_color.r, _faction_color.g, _faction_color.b, 0.8))
		# Border
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 0.85, 0.3, 0.9), 1.5)
		# Tier dots
		for i in _tier:
			var dx: float = (i - (_tier - 1) * 0.5) * 4.0
			draw_circle(Vector2(dx, 1), 1.5, Color(1.0, 0.9, 0.3))


## T-016: Shop tab with avatar cosmetics
func _build_shop_tab() -> void:
	var title := Label.new()
	title.text = "Choose Your Avatar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	title.add_theme_constant_override("outline_size", 3)
	title.position = Vector2(160, 20)
	title.size = Vector2(400, 30)
	shop_panel.add_child(title)

	# T-016: Daily Pick — 3 featured avatars with decorative frame
	_build_daily_pick(shop_panel)

	# P4: centered scrollable grid (5×112 + 4×12 = 608 wide → x=(720-608)/2=56).
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(56, 210)
	scroll.size = Vector2(608, 705)
	shop_panel.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var current_avatar: int = PlayerData.get_value("selected_avatar", 1)

	for i in range(1, 26):
		var tex_name := "Avatars_%02d" % i
		var tex: Texture2D = SpriteRegistry.get_ui_texture(StringName(tex_name))
		if tex == null:
			continue

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, 112)
		# flat=false: a flat button suppresses its NORMAL stylebox, so the cell frame /
		# selected ring never render (audit's "invisible selected state"). We override
		# all four state styleboxes below, so the button shows only our warm frame.
		btn.flat = false
		btn.icon = tex
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.set_meta("avatar_id", i)
		_style_avatar_cell(btn, i == current_avatar)

		# "Equipped" badge — shown only on the current avatar (P4 affordance).
		var badge := Label.new()
		badge.name = "EquippedBadge"
		badge.text = "Equipped"
		badge.add_theme_font_size_override("font_size", 16)
		badge.add_theme_color_override("font_color", UIStyle.TEXT_DARK)
		badge.add_theme_stylebox_override("normal",
			UIStyle.stat_chip(Color(1.0, 0.82, 0.2, 0.95), Color(0.5, 0.35, 0.1, 0.9)))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		badge.offset_top = -24
		badge.visible = (i == current_avatar)
		btn.add_child(badge)

		btn.pressed.connect(_on_avatar_selected.bind(i, grid))
		grid.add_child(btn)


## P4: warm inset slot cell; the equipped one gets a thick gold ring with an inner
## content margin so the avatar art can't paint over it (audit main_menu.gd:533).
func _style_avatar_cell(btn: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	if selected:
		sb.bg_color = Color(0.35, 0.28, 0.12, 0.95)
		sb.border_color = Color(1.0, 0.82, 0.2, 1.0)   # thick gold ring
		sb.set_border_width_all(5)
	else:
		# Warm inset cell with a visible affordance (audit: the old Δ6-RGB bg + 1px
		# border was invisible). Flat reads reliably where slots.png washed out.
		sb.bg_color = Color(0.27, 0.21, 0.13, 1.0)
		sb.border_color = Color(0.55, 0.42, 0.22, 0.9)
		sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)   # keep the art off the border on BOTH states
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)


func _on_avatar_selected(avatar_id: int, grid: GridContainer) -> void:
	SFX.play_ui("card_select")
	PlayerData.set_value("selected_avatar", avatar_id)

	# Restyle every cell + toggle its "Equipped" badge (avatar_id via node meta,
	# not a fragile positional index).
	for child in grid.get_children():
		if child is Button:
			var aid: int = child.get_meta("avatar_id", 0)
			_style_avatar_cell(child, aid == avatar_id)
			var badge = child.get_node_or_null("EquippedBadge")
			if badge:
				badge.visible = (aid == avatar_id)

	# Update header avatar
	var header_avatar = get_node_or_null("Header/HeaderContent/Avatar")
	if header_avatar and header_avatar is TextureRect:
		var new_tex: Texture2D = SpriteRegistry.get_ui_texture(StringName("Avatars_%02d" % avatar_id))
		if new_tex:
			header_avatar.texture = new_tex


## T-016: Daily Pick — 3 featured avatars rotated daily
func _build_daily_pick(parent: Control) -> void:
	var pick_panel := Panel.new()
	pick_panel.position = Vector2(30, 58)
	pick_panel.size = Vector2(660, 145)
	var pick_style := StyleBoxFlat.new()
	pick_style.bg_color = Color(0.14, 0.1, 0.05, 0.8)
	pick_style.border_color = Color(0.6, 0.45, 0.15, 0.7)
	pick_style.set_border_width_all(2)
	pick_style.set_corner_radius_all(12)
	pick_style.set_content_margin_all(8)
	pick_panel.add_theme_stylebox_override("panel", pick_style)
	parent.add_child(pick_panel)

	var pick_title := Label.new()
	pick_title.text = "Daily Pick"
	pick_title.position = Vector2(250, 4)
	pick_title.size = Vector2(160, 22)
	pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_title.add_theme_font_size_override("font_size", 15)
	pick_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pick_title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	pick_title.add_theme_constant_override("outline_size", 2)
	pick_panel.add_child(pick_title)

	# Pick 3 avatars deterministically from day-of-year seed
	var day_seed: int = int(Time.get_unix_time_from_system()) / 86400
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed
	var picks: Array[int] = []
	while picks.size() < 3:
		var pick: int = rng.randi_range(1, 25)
		if not picks.has(pick):
			picks.append(pick)

	var row := HBoxContainer.new()
	row.position = Vector2(120, 28)
	row.size = Vector2(420, 110)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	pick_panel.add_child(row)

	var current_avatar: int = PlayerData.get_value("selected_avatar", 1)
	for avatar_id in picks:
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(105, 105)
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color(0.2, 0.15, 0.08, 0.85)
		frame_style.border_color = Color(0.85, 0.65, 0.2, 0.8)
		frame_style.set_border_width_all(2)
		frame_style.set_corner_radius_all(10)
		frame.add_theme_stylebox_override("panel", frame_style)
		row.add_child(frame)

		var tex_name := "Avatars_%02d" % avatar_id
		var tex: Texture2D = SpriteRegistry.get_ui_texture(StringName(tex_name))
		if tex:
			var img := TextureRect.new()
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.position = Vector2(8, 8)
			img.size = Vector2(89, 89)
			frame.add_child(img)

		# Tap to select
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2.ZERO
		btn.size = Vector2(105, 105)
		btn.modulate.a = 0.0
		btn.pressed.connect(func(): _on_daily_pick_selected(avatar_id))
		frame.add_child(btn)

		# Highlight if currently selected
		if avatar_id == current_avatar:
			frame_style.border_color = Color(1.0, 0.82, 0.2, 1.0)
			frame_style.set_border_width_all(3)


func _on_daily_pick_selected(avatar_id: int) -> void:
	SFX.play_ui("card_select")
	PlayerData.set_value("selected_avatar", avatar_id)
	var header_avatar = get_node_or_null("Header/HeaderContent/Avatar")
	if header_avatar and header_avatar is TextureRect:
		var new_tex: Texture2D = SpriteRegistry.get_ui_texture(StringName("Avatars_%02d" % avatar_id))
		if new_tex:
			header_avatar.texture = new_tex


# --- Scenic Background (grass + castle + trees + clouds) ---

func _build_scenic_background() -> void:
	$Background.visible = false

	var scene := Control.new()
	scene.name = "SceneLayer"
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scene)
	move_child(scene, 0)

	# Ported from loading_screen._build_scenic_background() per user request:
	# "Let's use the same screen for Main Menu Battle tab." Composition:
	#   sky → clouds → castle + tree clumps (anchored to logo) → plateau with
	#   animated foam shoreline → subtle darkening overlay.
	# Y offsets adjusted vs loading screen so the castle/trees slot between the
	# logo (y=110..330) and slogan (y=650), and the plateau sits below the
	# ONLINE button (y=820..890). Loading-bar + tip-strip are not ported — the
	# BATTLE + ONLINE buttons occupy that vertical band.

	# --- Sky: blue-zenith → haze → meadow gradient, ported from loading_screen.gd
	# (the flat forest-green wall made clouds read as blobs and flashed green on the
	# loading→menu transition; the final gradient stop equals the old flat color). ---
	var sky_grad := Gradient.new()
	sky_grad.offsets = PackedFloat32Array([0.0, 0.40, 0.47, 0.53, 1.0])
	sky_grad.colors = PackedColorArray([
		Color(0.45, 0.66, 0.90),   # zenith blue
		Color(0.71, 0.84, 0.94),   # pale horizon haze
		Color(0.60, 0.76, 0.58),   # haze→meadow feather
		Color(0.40, 0.60, 0.31),   # sunlit meadow
		Color(0.25, 0.44, 0.20),   # deep field green (matches old flat sky)
	])
	var sky_tex := GradientTexture2D.new()
	sky_tex.gradient = sky_grad
	sky_tex.fill_from = Vector2(0, 0)
	sky_tex.fill_to = Vector2(0, 1)
	sky_tex.width = 64
	sky_tex.height = 1280
	var sky := TextureRect.new()
	sky.texture = sky_tex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.z_index = -10
	scene.add_child(sky)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	# --- 3 parallax clouds above the logo ---
	_menu_clouds.clear()
	var cloud_specs := [
		{"idx": 1, "size": 90.0,  "x": 80.0,  "y": 60.0,  "speed": 5.0,  "alpha": 0.55},
		{"idx": 3, "size": 200.0, "x": 320.0, "y": 100.0, "speed": 7.0,  "alpha": 0.70},
		{"idx": 5, "size": 140.0, "x": 540.0, "y": 180.0, "speed": 6.0,  "alpha": 0.50},
	]
	for spec in cloud_specs:
		var tex = load("res://assets/sprites/terrain/Decorations/Clouds_%02d.png" % spec.idx)
		if tex == null:
			continue
		var cloud := TextureRect.new()
		cloud.texture = tex
		cloud.size = Vector2(spec.size, spec.size * 0.55)
		cloud.position = Vector2(spec.x, spec.y)
		cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cloud.stretch_mode = TextureRect.STRETCH_SCALE
		cloud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cloud.modulate = Color(1, 1, 1, spec.alpha)
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.set_meta("drift_speed", spec.speed)
		scene.add_child(cloud)
		_menu_clouds.append(cloud)

	# --- Castle centerpiece: anchored to the BattlePanel's Logo node ---
	# Logo in the scene sits at y=110..330 (ContentArea+BattlePanel offsets).
	# Castle top aligned to logo.bottom so silhouette reads continuous.
	var castle_tex = load("res://assets/sprites/buildings/blue/Castle.png")
	if castle_tex:
		# Match loading screen castle exactly: 240 wide × 192 tall, anchored to
		# logo_bottom - 50 px so the castle slips into the logo's transparent
		# padding zone for a continuous silhouette.
		var castle_w: float = 240.0
		var castle_h: float = castle_w * (256.0 / 320.0)   # 192
		var logo_bottom: float = 580.0
		var logo_x_center: float = 360.0
		var logo_ref := battle_panel.get_node_or_null("Logo")
		if logo_ref and logo_ref is Control:
			var logo_rect: Rect2 = (logo_ref as Control).get_global_rect()
			logo_bottom = logo_rect.position.y + logo_rect.size.y
			logo_x_center = logo_rect.position.x + logo_rect.size.x * 0.5
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
		scene.add_child(castle_box)

	# --- Tree clumps flanking the castle ---
	# Tree3/Tree4 only (symmetric bbox padding — Tree1/2 hug their right edge
	# and read as cropped). Tight clusters so 6 trees per side read as a grove.
	var tree_sheets: Array = []
	for i in [3, 4]:
		var tex = load("res://assets/sprites/terrain/Resources/Tree%d.png" % i)
		if tex:
			tree_sheets.append(tex)
	# Tree clumps copied verbatim from loading_screen.gd — user asked for
	# positions + sizes to match exactly between the two screens.
	var tree_clumps := [
		# LEFT clump (6, packed within x=15..175, y=490..700).
		{"pos": Vector2(15, 495), "size": 130.0, "z": 2},
		{"pos": Vector2(75, 485), "size": 125.0, "z": 2},
		{"pos": Vector2(120, 505), "size": 115.0, "z": 2},
		{"pos": Vector2(5, 585),  "size": 140.0, "z": 4},
		{"pos": Vector2(70, 595), "size": 130.0, "z": 4},
		{"pos": Vector2(125, 580), "size": 120.0, "z": 4},
		# RIGHT clump (6 — mirror around viewport center x=360).
		{"pos": Vector2(575, 495), "size": 130.0, "z": 2},
		{"pos": Vector2(520, 485), "size": 125.0, "z": 2},
		{"pos": Vector2(480, 505), "size": 115.0, "z": 2},
		{"pos": Vector2(575, 585), "size": 140.0, "z": 4},
		{"pos": Vector2(520, 595), "size": 130.0, "z": 4},
		{"pos": Vector2(475, 580), "size": 120.0, "z": 4},
	]
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
		scene.add_child(box)

	# --- Plateau + water + foam below the BATTLE/ONLINE buttons ---
	# Buttons occupy y=710..890; plateau starts at y=930 leaving 40 px breathing
	# room. Tab bar at y=1160+ so water can extend to y=1155 before clipping.
	_build_menu_plateau(scene)

	# Subtle darkening overlay for readability of text + buttons.
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.18)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.z_index = 8  # above scenic (z=5 for castle) but below UI buttons (default z)
	scene.add_child(ov)


func _build_menu_plateau(parent: Control) -> void:
	# Ported from loading_screen._build_plateau() at IDENTICAL coords per user
	# ("loading screen is reference"). Same tile structure: (_, 0) top +
	# (_, 128) mid (clean top, dark bottom → unified grass rectangle) + (_, 256)
	# cliff face, 11 cols centered in viewport. Animated foam blobs span the
	# cliff base. BATTLE + PLAY ONLINE buttons are repositioned below the
	# plateau/water (analogous to the loading bar + tip strip).
	var atlas_tex = load("res://assets/sprites/terrain/Tilemap_color1.png")
	if atlas_tex == null:
		return
	var ts: float = 48.0
	var top_y: float = 790.0
	var mid_y: float = 838.0
	var cliff_y: float = 886.0
	var cols: int = 11
	var island_x: float = (720.0 - cols * ts) / 2.0   # 96

	# Water plane behind and around plateau (same 200 px tall as loading).
	var water_tex = load("res://assets/sprites/terrain/Water Background color.png")
	if water_tex:
		var water := TextureRect.new()
		water.texture = water_tex
		water.position = Vector2(0, top_y + ts * 0.5)
		water.size = Vector2(720, 200)
		water.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		water.stretch_mode = TextureRect.STRETCH_TILE
		water.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		water.modulate = Color(0.50, 0.78, 0.90, 1)
		water.z_index = -5
		water.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(water)

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
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.z_index = z
		parent.add_child(r)

	# Atlas: top row (y=0) = grass-top, dark top / clean bot;
	# mid row (y=128) = grass-bottom, clean top / dark bot; cliff (y=256).
	# Island outline: END columns use the side-edge cliff variants (x=320 dark LEFT
	# rim, x=512 dark RIGHT rim); interior stays clean x=384. Edge tiles on ONLY the
	# two end columns give the island its L/R outline — the 2026-04-22 "extra border"
	# complaint was from using them on EVERY column. No flip (perspective lock).
	for col in range(cols):
		var ax: int = 320 if col == 0 else (512 if col == cols - 1 else 384)
		add_tile.call(col, top_y, ax, 0, -3)
		add_tile.call(col, mid_y, ax, 128, -3)
		add_tile.call(col, cliff_y, ax, 256, -2)

	# Continuous animated foam shoreline (same math as loading_screen round 10).
	var foam_tex = load("res://assets/sprites/terrain/Water Foam.png")
	if foam_tex:
		var foam_region_y: int = 56
		var foam_region_h: int = 94
		var foam_atlas := AtlasTexture.new()
		foam_atlas.atlas = foam_tex
		foam_atlas.region = Rect2(0, foam_region_y, 192, foam_region_h)
		var foam_display: float = 120.0
		var foam_center_y: float = cliff_y + ts - 16.0
		var foam_left_shift: float = 27.0
		for tile_i in range(cols):
			var tile_center_x: float = island_x + tile_i * ts + ts * 0.5
			var fx: float = tile_center_x - foam_display * 0.5 - foam_left_shift
			var fy: float = foam_center_y - foam_display * 0.5
			var blob := TextureRect.new()
			blob.texture = foam_atlas
			blob.position = Vector2(fx, fy)
			blob.size = Vector2(foam_display, foam_display)
			blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			blob.stretch_mode = TextureRect.STRETCH_SCALE
			blob.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blob.modulate = Color(1, 1, 1, 0.9)
			blob.z_index = -4
			parent.add_child(blob)
		# Cycle through 16 frames at 20 fps.
		var tw := create_tween().set_loops()
		for i in range(16):
			tw.tween_callback(func():
				if foam_atlas != null:
					foam_atlas.region = Rect2(i * 192, foam_region_y, 192, foam_region_h)
			)
			tw.tween_interval(0.05)


func _process(delta: float) -> void:
	# Ambient cloud parallax — uniform rightward drift, wrap at right edge.
	for c in _menu_clouds:
		if not is_instance_valid(c):
			continue
		var speed: float = c.get_meta("drift_speed", 6.0)
		c.position.x += speed * delta
		if c.position.x > 740.0:
			c.position.x = -c.size.x - 20.0


# --- StyleBoxFlat UI Styling (proven to work) ---

func _make_style(bg: Color, border: Color, corner: int = 14, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(corner)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 5
	s.shadow_offset = Vector2(2, 3)
	return s


func _apply_style(node: Control, style: StyleBoxFlat) -> void:
	var bg = node.get_node_or_null("Bg")
	if bg:
		bg.visible = false
	var panel := Panel.new()
	panel.name = "StyledBg"
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(panel)
	node.move_child(panel, 0)


## Seamless parchment backdrop for non-Battle tabs. SpecialPaper.png is a 3x3
## tile ATLAS with fully-transparent 64px gap bands between tiles — the old
## tscn Background stretched it fullscreen, producing banding through the
## 0.88-alpha tab panels. Stitch the 9 opaque tiles instead (same pattern as
## loading_screen's tip strip, see sprite_registry.gd UI ATLAS CAVEAT). The
## $Background ColorRect beneath stays opaque dark wood, so the backdrop has
## no transparent bands even if the asset is missing.
func _build_tab_backdrop() -> void:
	var paper_tex := _load_texture("res://assets/sprites/ui/SpecialPaper.png")
	if paper_tex == null:
		return  # $Background ColorRect alone is a clean themed fallback
	var paper := SpriteRegistry.make_tiled_panel_9(
		paper_tex, SpriteRegistry.SPECIAL_PAPER_REGIONS, Vector2(720.0, 1280.0)
	)
	paper.name = "PaperBackdrop"
	$Background.add_child(paper)


## Style a raw Button with the wood/parchment theme incl. hover/pressed states
## (mirrors end_screen._style_end_button so both screens share one look).
func _style_menu_button(btn: Button, bg: Color, border: Color, font_size: int = 16) -> void:
	if btn == null:
		return
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
	var disabled := style.duplicate()
	disabled.bg_color = bg.darkened(0.25)
	disabled.border_color = Color(border.r, border.g, border.b, border.a * 0.5)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	btn.add_theme_color_override("font_disabled_color", Color(0.78, 0.72, 0.6, 0.7))
	btn.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	btn.add_theme_constant_override("outline_size", 2)


## CR-style press feedback for TouchArea composites (styled panel + invisible
## Button): depress the whole parent to 96% while held, spring back on release.
func _add_press_feedback(node: Control) -> void:
	var touch: Button = node.get_node_or_null("TouchArea")
	if touch == null:
		return
	touch.button_down.connect(func():
		node.pivot_offset = node.size * 0.5
		# The BATTLE button's idle pulse tweens the same scale property —
		# kill it while pressed, restart it on release.
		if node == play_btn and _battle_pulse_tween and _battle_pulse_tween.is_valid():
			_battle_pulse_tween.kill()
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector2(0.96, 0.96), 0.05).set_ease(Tween.EASE_OUT)
	)
	touch.button_up.connect(func():
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector2.ONE, 0.05).set_ease(Tween.EASE_OUT)
		if node == play_btn:
			tw.tween_callback(_start_battle_pulse)
	)


## Add a parchment backdrop behind the logo with 10px padding.
func _add_banner_behind_logo(logo_node: Control) -> void:
	# Banner.png 9-slice backdrop — all 4 scroll corners as box/border
	var banner_tex = _load_texture("res://assets/sprites/ui/ninepatch/banner.png")
	if banner_tex == null:
		banner_tex = _load_texture("res://assets/sprites/ui/ninepatch/regularpaper.png")
	if banner_tex == null:
		return
	var pad: float = 10.0
	# Bottom scroll curl is 98px vs 64px top border — add 34px extra for symmetry
	var pad_bottom: float = pad + 34.0
	var banner := NinePatchRect.new()
	banner.name = "LogoBanner"
	banner.texture = banner_tex
	# Full 9-slice: 4 scroll corners + tiled edges + tiled center
	banner.patch_margin_left = 60
	banner.patch_margin_right = 44
	banner.patch_margin_top = 64
	banner.patch_margin_bottom = 98
	banner.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	banner.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Position: same anchors as logo, with padding (extra bottom for scroll curl)
	banner.anchor_left = logo_node.anchor_left
	banner.anchor_right = logo_node.anchor_right
	banner.anchor_top = logo_node.anchor_top
	banner.anchor_bottom = logo_node.anchor_bottom
	banner.offset_left = logo_node.offset_left - pad
	banner.offset_right = logo_node.offset_right + pad
	banner.offset_top = logo_node.offset_top - pad
	banner.offset_bottom = logo_node.offset_bottom + pad_bottom
	banner.modulate = Color(1, 1, 1, 0.85)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := logo_node.get_parent()
	parent.add_child(banner)
	parent.move_child(banner, logo_node.get_index())  # Just behind logo


## Load a texture with fallback: tries Godot import system first, then raw PNG.
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res and res is Texture2D:
			return res
	# Fallback: load raw PNG from filesystem (for un-imported textures)
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
		var img := Image.new()
		var err: int = img.load(abs_path if FileAccess.file_exists(abs_path) else path)
		if err == OK and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## Apply a Tiny Swords 9-slice texture as button/panel background.
## Only hides the original Bg if the texture loads successfully — never leaves text floating.
## margins: Dictionary with left/right/top/bottom patch margins for NinePatchRect.
func _apply_texture_bg(node: Control, tex_path: String, tint: Color = Color.WHITE,
		margins: Dictionary = {}) -> void:
	var tex = _load_texture(tex_path)
	if tex == null:
		return  # Keep original Bg intact — don't leave text floating
	# Texture loaded — safe to hide original Bg
	var bg = node.get_node_or_null("Bg")
	if bg:
		bg.visible = false
	# Remove old StyledBg if any
	var old = node.get_node_or_null("StyledBg")
	if old:
		old.queue_free()
	var np := NinePatchRect.new()
	np.name = "StyledBg"
	np.texture = tex
	np.patch_margin_left = margins.get("left", 0)
	np.patch_margin_right = margins.get("right", 0)
	np.patch_margin_top = margins.get("top", 0)
	np.patch_margin_bottom = margins.get("bottom", 0)
	np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.modulate = tint
	node.add_child(np)
	node.move_child(np, 0)


func _style_all_ui() -> void:
	# Header — dark wood (with guaranteed opaque backdrop to prevent floating text)
	# BUG-MENU 2026-04-11: Previous panel-only backdrop wasn't rendering reliably.
	# Keep the existing HeaderBg ColorRect visible and restyle it to dark wood color.
	var hdr_bg = $Header.get_node_or_null("HeaderBg")
	if hdr_bg and hdr_bg is ColorRect:
		hdr_bg.visible = true
		hdr_bg.color = Color(0.14, 0.09, 0.04, 0.96)  # Dark wood, fully opaque
	# Styled panel on top for the border/wood styling
	var hdr_panel := Panel.new()
	hdr_panel.add_theme_stylebox_override("panel", UIStyle.wood_panel())  # Tiny Swords wood beam
	hdr_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hdr_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Header.add_child(hdr_panel)
	$Header.move_child(hdr_panel, 1)  # Above HeaderBg, below HeaderContent

	# Faction buttons
	_apply_style(kingdom_btn, _make_style(Color(0.12, 0.28, 0.58, 0.92), Color(0.25, 0.5, 0.9, 0.8), 16, 3))
	_apply_style(horde_btn, _make_style(Color(0.55, 0.1, 0.06, 0.92), Color(0.85, 0.25, 0.12, 0.8), 16, 3))

	# BATTLE button — yellow ribbon backdrop (NinePatchRect)
	var ribbon_path := "res://assets/sprites/ui/ninepatch/ribbon_yellow.png"
	_apply_texture_bg(play_btn, ribbon_path, Color.WHITE, {"left": 98, "right": 97})
	if not ResourceLoader.exists(ribbon_path) and _load_texture(ribbon_path) == null:
		_apply_style(play_btn, _make_style(Color(0.75, 0.55, 0.08, 0.98), Color(1.0, 0.82, 0.2, 0.95), 20, 3))
	# Center BATTLE text within ribbon's visible band (ribbon has pointed ends top/bottom)
	var battle_label := play_btn.get_node_or_null("Label")
	if battle_label:
		battle_label.offset_top = 8
		battle_label.offset_bottom = -8
		# Tiny Swords ribbon convention: dark-brown text on the tan ribbon with a
		# light cream outline (was washed near-white-on-tan at ~2:1).
		battle_label.add_theme_color_override("font_color", Color(0.25, 0.13, 0.02, 1.0))
		battle_label.add_theme_color_override("font_outline_color", Color(0.95, 0.9, 0.78, 1.0))
		battle_label.add_theme_constant_override("outline_size", 4)
		battle_label.add_theme_font_size_override("font_size", UIStyle.FONT_TITLE)  # 32, quantized

	# PLAY ONLINE — demoted to a COMPACT blue-ribbon chip (single-CTA hierarchy):
	# BATTLE is the one primary CTA; online is a subordinate option. Mirror the
	# BATTLE ribbon pattern (ribbon_blue 9-patch behind the frame + centered label),
	# keeping the transparent TouchArea as the click/disabled target.
	var online_bg = online_btn.get_node_or_null("Bg")
	if online_bg:
		online_bg.visible = false
	_apply_texture_bg(online_btn, "res://assets/sprites/ui/ninepatch/ribbon_blue.png",
		Color.WHITE, {"left": 97, "right": 97})
	var online_label: Label = online_btn.get_node_or_null("Label")
	if online_label:
		online_label.visible = true
		online_label.text = "PLAY ONLINE"
		online_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		online_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		online_label.add_theme_font_size_override("font_size", UIStyle.FONT_BODY)
		online_label.add_theme_color_override("font_color", UIStyle.TEXT_CREAM)
		online_label.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
		online_label.add_theme_constant_override("outline_size", 2)
	var online_touch: Button = online_btn.get_node("TouchArea")
	online_touch.flat = true

	# Tab bar — dark wood
	var tb_bg = $TabBar.get_node_or_null("TabBarBg")
	if tb_bg:
		tb_bg.visible = false
	var tb_line = $TabBar.get_node_or_null("TabBarTopLine")
	if tb_line:
		tb_line.visible = false
	var tb_panel := Panel.new()
	tb_panel.add_theme_stylebox_override("panel", UIStyle.wood_panel())  # Tiny Swords wood beam
	tb_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TabBar.add_child(tb_panel)
	$TabBar.move_child(tb_panel, 0)

	# Tab buttons
	var tab_bar: HBoxContainer = $TabBar/TabButtons
	for child in tab_bar.get_children():
		_apply_style(child, _make_style(Color(0.2, 0.15, 0.08, 0.85), Color(0.45, 0.32, 0.15, 0.5), 10, 2))

	# T-099: raise the currently-selected tab +12px with a gold ring highlight.
	# BUG-51: this used to run ONCE on _ready for the Battle tab and never
	# toggle off when other tabs were selected — Battle stayed permanently
	# raised + ringed. Moved into `_select_tab` so the emphasis follows the
	# current tab. Initial application happens via the `_select_tab(2)` call
	# at the end of `_ready`.

	# Coming soon panels
	for path in ["ShopPanel/ShopBg", "ArmyPanel/ArmyBg", "SocialPanel/SocialBg", "SettingsPanel/SettingsBg"]:
		var node = $ContentArea.get_node_or_null(path)
		if node:
			node.visible = false
			var p := Panel.new()
			p.add_theme_stylebox_override("panel", _make_style(Color(0.15, 0.1, 0.06, 0.88), Color(0.45, 0.32, 0.15, 0.5), 14, 2))
			p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.get_parent().add_child(p)
			node.get_parent().move_child(p, node.get_index())


func _bounce_tab_icon(tab_idx: int) -> void:
	# T-099: small elastic bounce on the tapped tab's icon.
	var tab_bar: HBoxContainer = $TabBar/TabButtons
	if tab_idx < 0 or tab_idx >= tab_bar.get_child_count():
		return
	var tab: Control = tab_bar.get_child(tab_idx)
	var icon: Node = tab.get_node_or_null("Icon")
	if icon == null or not (icon is Control):
		return
	var icon_c: Control = icon as Control
	icon_c.pivot_offset = icon_c.size * 0.5
	var tw := create_tween()
	tw.tween_property(icon_c, "scale", Vector2(1.18, 1.18), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(icon_c, "scale", Vector2(1.0, 1.0), 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


var _lifted_tab_idx: int = -1

func _apply_selected_tab_emphasis(selected_idx: int) -> void:
	# BUG-51: dynamic version of the former `_apply_center_tab_emphasis`.
	# The selected tab rises 12 px with a gold ring; previously-lifted tab
	# drops back down and has its ring removed.
	var tab_bar: HBoxContainer = $TabBar/TabButtons
	var tabs := tab_bar.get_children()
	if selected_idx == _lifted_tab_idx:
		return
	# Unlift the previous tab first.
	if _lifted_tab_idx >= 0 and _lifted_tab_idx < tabs.size():
		var old_tab: Control = tabs[_lifted_tab_idx]
		for child in old_tab.get_children():
			if child is Control:
				(child as Control).position.y += 12.0
		var old_ring := old_tab.get_node_or_null("CenterRing")
		if old_ring:
			old_ring.queue_free()
	# Lift the newly-selected tab.
	if selected_idx >= 0 and selected_idx < tabs.size():
		var tab: Control = tabs[selected_idx]
		for child in tab.get_children():
			if child is Control:
				(child as Control).position.y -= 12.0
		var ring := Node2D.new()
		ring.name = "CenterRing"
		ring.z_index = -1
		ring.position.y = -12.0
		tab.add_child(ring)
		ring.draw.connect(func():
			if not is_instance_valid(ring):
				return
			var cx: float = tab.size.x * 0.5
			var cy: float = tab.size.y * 0.5
			var r: float = minf(tab.size.x, tab.size.y) * 0.52
			ring.draw_arc(Vector2(cx, cy), r, 0, TAU, 36, Color(0.95, 0.75, 0.2, 0.65), 2.5)
		)
	_lifted_tab_idx = selected_idx


var _battle_pulse_tween: Tween = null

func _start_battle_pulse() -> void:
	# T-099: 1.2 s pulse (0.6s up / 0.6s down), 1.0→1.04 scale — CR parity.
	# Tween is tracked so press feedback can kill/restart it (it animates the
	# same scale property). Shine sweep is started separately from _ready so
	# pulse restarts don't stack extra shine strips.
	play_btn.pivot_offset = play_btn.size * 0.5
	if _battle_pulse_tween and _battle_pulse_tween.is_valid():
		_battle_pulse_tween.kill()
	_battle_pulse_tween = play_btn.create_tween().set_loops()
	_battle_pulse_tween.tween_property(play_btn, "scale", Vector2(1.04, 1.04), 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_battle_pulse_tween.tween_property(play_btn, "scale", Vector2(1.0, 1.0), 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _start_battle_shine_sweep() -> void:
	var shine := ColorRect.new()
	shine.color = Color(1.0, 1.0, 1.0, 0.25)
	shine.size = Vector2(40.0, play_btn.size.y)
	shine.position = Vector2(-80.0, 0.0)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_btn.add_child(shine)
	play_btn.clip_contents = true
	var tw := shine.create_tween().set_loops()
	tw.tween_property(shine, "position:x", play_btn.size.x + 20.0, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(shine, "position:x", -80.0, 0.0)
	tw.tween_interval(1.6)


# --- Tab Navigation ---

var _tab_tween: Tween = null
# Slide-in tween + anchored base X per panel. Rapid tab switching used to
# compound the +/-30px slide offset because each re-entry offset position.x
# again while an untracked tween was still returning it — panels drifted
# permanently. Kill the tracked tween and reset to base X before offsetting.
var _panel_slide_tween: Tween = null
var _panel_base_x: Dictionary = {}

func _select_tab(index: int) -> void:
	var changed: bool = (index != _current_tab)
	if changed:
		SFX.play_ui("tab_switch")

	var old_tab: int = _current_tab
	_current_tab = index

	# BUG-51: lift + gold-ring the currently-selected tab (and drop the old one).
	_apply_selected_tab_emphasis(index)

	# BUG-52: scenic composition (sky/castle/trees/plateau) only shows on the
	# Battle tab. Hide the SceneLayer on non-battle tabs; restore the default
	# plain $Background so the other panels have a clean neutral backdrop.
	var scene_layer := get_node_or_null("SceneLayer")
	if scene_layer:
		scene_layer.visible = (index == 2)
	if has_node("Background"):
		$Background.visible = (index != 2)

	var panels := [shop_panel, army_panel, battle_panel, social_panel, settings_panel]

	# Capture each panel's anchored base X once (first call happens in _ready
	# before any slide, so position.x is the layout value).
	for p in panels:
		if not _panel_base_x.has(p):
			_panel_base_x[p] = (p as Control).position.x
	if _panel_slide_tween and _panel_slide_tween.is_valid():
		_panel_slide_tween.kill()

	# T-047 + T-099: 350ms ease-out-cubic panel transition (was 100ms fade).
	if _tab_tween and _tab_tween.is_valid():
		_tab_tween.kill()
	if changed and old_tab >= 0 and old_tab < panels.size():
		var old_panel: Control = panels[old_tab]
		_tab_tween = create_tween()
		_tab_tween.tween_property(old_panel, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tab_tween.tween_callback(func():
			old_panel.visible = false
			old_panel.modulate.a = 1.0
			old_panel.position.x = _panel_base_x.get(old_panel, old_panel.position.x)
		)
		# T-099: bounce the tapped tab's icon on selection
		_bounce_tab_icon(index)

	# Show new panel with slide-in (always from its anchored base X)
	for i in panels.size():
		var base_x: float = _panel_base_x[panels[i]]
		if i == index:
			panels[i].visible = true
			panels[i].position.x = base_x
			if changed:
				var slide_dir: float = 30.0 if index > old_tab else -30.0
				panels[i].modulate.a = 0.0
				panels[i].position.x = base_x + slide_dir
				_panel_slide_tween = panels[i].create_tween()
				_panel_slide_tween.set_parallel(true)
				_panel_slide_tween.tween_property(panels[i], "modulate:a", 1.0, 0.2)
				_panel_slide_tween.tween_property(panels[i], "position:x", base_x, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif i != old_tab:  # Don't hide old tab yet — tween handles it
			panels[i].visible = false
			panels[i].position.x = base_x

	# Update tab button styles
	for i in tab_buttons.size():
		var btn: Control = tab_buttons[i]
		var styled: Panel = btn.get_node_or_null("StyledBg")
		var icon: TextureRect = btn.get_node("Icon")
		var lbl: Label = btn.get_node("TabLabel")

		if i == index:
			if styled:
				styled.add_theme_stylebox_override("panel", _make_style(
					Color(0.55, 0.42, 0.1, 0.95), Color(0.85, 0.7, 0.2, 0.85), 10, 2))
			icon.modulate = Color(1, 1, 1, 1)
			lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4, 1))
			lbl.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
			lbl.add_theme_constant_override("outline_size", 2)
			# T-047: Icon bounce on selection
			if changed:
				var bounce_tw := icon.create_tween()
				bounce_tw.tween_property(icon, "scale", Vector2(1.25, 1.25), 0.08).set_ease(Tween.EASE_OUT)
				bounce_tw.tween_property(icon, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
		else:
			if styled:
				styled.add_theme_stylebox_override("panel", _make_style(
					Color(0.2, 0.15, 0.08, 0.85), Color(0.45, 0.32, 0.15, 0.5), 10, 2))
			# Inactive tabs were 2.1:1 contrast (60%/40% alpha) — the most-used
			# navigation was nearly invisible. Cream label + outline + brighter icon.
			icon.modulate = Color(1, 1, 1, 0.85)
			lbl.add_theme_color_override("font_color", UIStyle.TEXT_CREAM)
			lbl.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
			lbl.add_theme_constant_override("outline_size", 2)


# --- Faction Selection ---

func _select_kingdom() -> void:
	SFX.play_ui("button_click")
	_selected_faction = &"kingdom"
	_update_faction_selection()

func _select_horde() -> void:
	SFX.play_ui("button_click")
	_selected_faction = &"horde"
	_update_faction_selection()

func _update_faction_selection() -> void:
	# T-066: Always Kingdom. Faction row is hidden, no toggle needed.
	_selected_faction = &"kingdom"
	_refresh_building_preview()


func _on_play() -> void:
	SFX.play_ui("button_click")
	GameManager.selected_faction = _selected_faction
	# T-054: Show perk selection before starting match
	_show_perk_selection()


## T-054: Perk selection screen
func _show_perk_selection() -> void:
	var overlay := Control.new()
	overlay.name = "PerkOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Dark background
	var dark := ColorRect.new()
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0, 0, 0, 0.7)
	overlay.add_child(dark)

	# Title
	var title := Label.new()
	title.text = "Choose a Perk"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(160, 180)
	title.size = Vector2(400, 40)
	overlay.add_child(title)

	# Perks based on faction
	var perks: Array[Dictionary] = []
	if _selected_faction == &"kingdom":
		perks = [
			{"id": &"iron_discipline", "name": "Iron Discipline", "up": "+10% HP", "down": "-10% DMG"},
			{"id": &"swift_march", "name": "Swift March", "up": "+15% Speed", "down": "-1 Armor"},
			{"id": &"war_economy", "name": "War Economy", "up": "+25% Income", "down": "1st building +50% cost"},
		]
	else:
		perks = [
			{"id": &"bloodthirst", "name": "Bloodthirst", "up": "+10% DMG", "down": "5% HP bleed"},
			{"id": &"savage_rush", "name": "Savage Rush", "up": "3 instant spawns", "down": "-15% income"},
			{"id": &"pillage", "name": "Pillage", "up": "+50% bounty", "down": "Income blds +40% cost"},
		]

	var card_y: float = 260.0
	for i in perks.size():
		var perk := perks[i]
		var card := Panel.new()
		card.position = Vector2(110, card_y + i * 130)
		card.size = Vector2(500, 110)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.18, 0.15, 0.1, 0.9)
		card_style.border_color = Color(0.55, 0.42, 0.2, 0.6)
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(10)
		card_style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", card_style)
		overlay.add_child(card)

		# Perk name
		var name_lbl := Label.new()
		name_lbl.text = perk.name
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		name_lbl.position = Vector2(16, 8)
		card.add_child(name_lbl)

		# Upside (green)
		var up_lbl := Label.new()
		up_lbl.text = perk.up
		up_lbl.add_theme_font_size_override("font_size", 14)
		up_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 0.3))
		up_lbl.position = Vector2(16, 38)
		card.add_child(up_lbl)

		# Downside (red)
		var down_lbl := Label.new()
		down_lbl.text = perk.down
		down_lbl.add_theme_font_size_override("font_size", 14)
		down_lbl.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
		down_lbl.position = Vector2(16, 60)
		card.add_child(down_lbl)

		# Tap card to select (highlight)
		var card_btn := Button.new()
		card_btn.flat = true
		card_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_btn.modulate.a = 0.0
		card_btn.pressed.connect(_on_perk_card_tapped.bind(perk.id, card, overlay))
		card.add_child(card_btn)

		# Animate card in
		card.modulate.a = 0.0
		card.position.x += 40
		var tw := card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(i * 0.08)
		tw.tween_property(card, "position:x", 110, 0.25).set_delay(i * 0.08).set_ease(Tween.EASE_OUT)

	# "No Perk" option
	var no_perk_btn := Button.new()
	no_perk_btn.text = "No Perk"
	no_perk_btn.position = Vector2(210, card_y + perks.size() * 130 + 15)
	no_perk_btn.custom_minimum_size = Vector2(300, 40)
	no_perk_btn.add_theme_font_size_override("font_size", 14)
	no_perk_btn.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	var np_style := StyleBoxFlat.new()
	np_style.bg_color = Color(0.2, 0.15, 0.1, 0.7)
	np_style.border_color = Color(0.4, 0.32, 0.2, 0.4)
	np_style.set_border_width_all(1)
	np_style.set_corner_radius_all(8)
	np_style.set_content_margin_all(6)
	no_perk_btn.add_theme_stylebox_override("normal", np_style)
	no_perk_btn.pressed.connect(_on_perk_card_tapped.bind(&"", null, overlay))
	overlay.add_child(no_perk_btn)

	# Confirm button (initially hidden until a perk is selected)
	var confirm_btn := Button.new()
	confirm_btn.name = "PerkConfirmBtn"
	confirm_btn.text = "CONFIRM"
	confirm_btn.position = Vector2(210, card_y + perks.size() * 130 + 65)
	confirm_btn.custom_minimum_size = Vector2(300, 52)
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.add_theme_color_override("font_color", Color(0.15, 0.1, 0.02))
	var conf_style := StyleBoxFlat.new()
	conf_style.bg_color = Color(0.85, 0.65, 0.1, 0.95)
	conf_style.border_color = Color(1.0, 0.82, 0.2, 0.9)
	conf_style.set_border_width_all(2)
	conf_style.set_corner_radius_all(10)
	conf_style.set_content_margin_all(8)
	confirm_btn.add_theme_stylebox_override("normal", conf_style)
	confirm_btn.visible = false
	confirm_btn.pressed.connect(_on_perk_confirmed.bind(overlay))
	overlay.add_child(confirm_btn)


var _selected_perk_id: StringName = &""
var _perk_cards: Array[Panel] = []

func _on_perk_card_tapped(perk_id: StringName, card: Panel, overlay: Control) -> void:
	SFX.play_ui("card_select")
	_selected_perk_id = perk_id
	# Highlight selected card, dim others
	for child in overlay.get_children():
		if child is Panel:
			var style: StyleBoxFlat = child.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				if child == card:
					style.border_color = Color(1.0, 0.82, 0.2, 0.95)
					style.set_border_width_all(3)
				else:
					style.border_color = Color(0.55, 0.42, 0.2, 0.4)
					style.set_border_width_all(2)
				child.add_theme_stylebox_override("panel", style)
	# Show confirm button
	var confirm := overlay.get_node_or_null("PerkConfirmBtn")
	if confirm:
		confirm.visible = true


func _on_perk_confirmed(overlay: Control) -> void:
	SFX.play_ui("button_click")
	GameManager.selected_perk = _selected_perk_id
	overlay.queue_free()
	SceneTransition.change_scene("res://scenes/game/game_arena.tscn")

func _on_play_online() -> void:
	SFX.play_ui("button_click")
	if status_label:
		status_label.visible = true
		status_label.text = "Connecting to server..."
		status_label.modulate.a = 1.0
	online_btn.get_node("TouchArea").disabled = true
	play_btn.get_node("TouchArea").disabled = true
	# Show cancel button during matchmaking
	_show_cancel_search_btn(true)
	NetworkManager.local_faction = _selected_faction
	NetworkManager.connect_to_server()

func _on_connected() -> void:
	if status_label:
		status_label.text = "Finding opponent..."
		# Pulse animation so the user knows matchmaking is active
		var tw := status_label.create_tween().set_loops()
		tw.tween_property(status_label, "modulate:a", 0.3, 0.8)
		tw.tween_property(status_label, "modulate:a", 1.0, 0.8)
	NetworkManager.start_matchmaking(_selected_faction)

func _on_disconnected() -> void:
	_restore_online_buttons()


## 1B-2: surface an in-lobby abort so the player sees why matchmaking stopped
## and can retry, instead of an infinite "Starting..." spinner.
func _on_match_error(kind: String, message: String) -> void:
	if status_label:
		status_label.modulate.a = 1.0  # stop any pulse tween
		status_label.visible = true
		var msg: String = message if message != "" else "Match error (%s)" % kind
		if kind == "version_mismatch":
			msg = "Update available — refresh your browser to play online."
		status_label.text = msg
	_show_cancel_search_btn(false)
	# Re-enable the online/play buttons after a short beat so the message reads.
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(func():
		online_btn.get_node("TouchArea").disabled = false
		play_btn.get_node("TouchArea").disabled = false)

func _on_match_found(_match_id: String) -> void:
	if status_label:
		status_label.modulate.a = 1.0  # stop pulse
		var opp_name: String = NetworkManager.opponent_username
		if opp_name == "":
			opp_name = "Opponent"
		status_label.text = "vs %s - Starting..." % opp_name
	_show_cancel_search_btn(false)
	NetworkManager.set_ready()

## Re-enable buttons after disconnect or cancel.
func _restore_online_buttons() -> void:
	online_btn.get_node("TouchArea").disabled = false
	play_btn.get_node("TouchArea").disabled = false
	_show_cancel_search_btn(false)
	if status_label:
		status_label.modulate.a = 1.0
		status_label.visible = false

## Show/hide the "Cancel" button during matchmaking search.
func _show_cancel_search_btn(show: bool) -> void:
	var existing = battle_panel.get_node_or_null("CancelSearchBtn")
	if not show:
		if existing:
			existing.queue_free()
		return
	if existing:
		return
	var btn := Button.new()
	btn.name = "CancelSearchBtn"
	btn.text = "Cancel"
	btn.custom_minimum_size = Vector2(140, 45)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_menu_button(btn, Color(0.25, 0.18, 0.1, 0.96), Color(0.55, 0.4, 0.18, 0.85), 16)
	# Position below status label
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.position = Vector2(-70, 850)
	btn.pressed.connect(func():
		SFX.play_ui("button_click")
		NetworkManager.cancel_matchmaking()
		NetworkManager._reset_to_offline()
		_restore_online_buttons()
	)
	battle_panel.add_child(btn)

func _update_player_stats() -> void:
	if trophy_label:
		if PlayerData.games_played > 0:
			trophy_label.text = "%d Trophies" % PlayerData.trophies
		else:
			trophy_label.text = "New Commander"
	if status_label:
		if PlayerData.games_played > 0:
			var rank := PlayerData.get_rank_name()
			var record := "%dW / %dL" % [PlayerData.games_won, PlayerData.games_played - PlayerData.games_won]
			var bonus := " | First Win Bonus!" if PlayerData.first_win_bonus_available else ""
			status_label.text = "%s | %s%s" % [rank, record, bonus]
		else:
			status_label.text = "Welcome, Commander! Pick a faction and fight."


# --- T-015: Army Tab ---

const ROLE_NAMES := ["Melee", "Ranged", "Caster", "Flying", "Siege"]
const ATTACK_TYPE_NAMES := ["Physical", "Pierce", "Magic", "Siege"]
const ARMOR_TYPE_NAMES := ["Light", "Medium", "Heavy", "Fortified"]
const ROLE_COLORS := [
	Color(0.8, 0.5, 0.3), Color(0.5, 0.8, 0.4), Color(0.6, 0.5, 0.9),
	Color(0.4, 0.75, 0.9), Color(0.7, 0.6, 0.4),
]

func _build_army_tab() -> void:
	var army_bg = army_panel.get_node_or_null("ArmyBg")
	if army_bg:
		army_bg.visible = false
	for old in army_panel.get_children():
		if old.name.begins_with("Styled"):
			old.visible = false

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	army_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(700, 0)
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var title := Label.new()
	title.text = "UNIT ROSTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.35, 1))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 1))
	title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(title)

	# T-066: Single faction — only show Kingdom units
	# T-068: Group by building tier (T1 → T2 → T3) for clear progression
	var faction: FactionData = GameManager._faction_registry.get(&"kingdom")
	if faction:
		var tier_names := {1: "TIER 1 — Basic Units", 2: "TIER 2 — Advanced Units", 3: "TIER 3 — Elite Units"}
		var current_tier: int = 0
		# Sort buildings by tier for progression display
		var sorted_buildings: Array = []
		for bd: BuildingData in faction.buildings:
			if bd.spawns_unit == null:
				continue
			sorted_buildings.append(bd)
		sorted_buildings.sort_custom(func(a, b): return a.tier < b.tier)
		for bd: BuildingData in sorted_buildings:
			# Add tier header when tier changes — P4: on a dark ribbon (was a bare
			# floating gold label) matching the Battle tab's ribbon language.
			if bd.tier != current_tier:
				current_tier = bd.tier
				var ribbon := PanelContainer.new()
				ribbon.add_theme_stylebox_override("panel", UIStyle.ribbon_style("dark"))
				ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				ribbon.custom_minimum_size = Vector2(430, 46)
				var tier_header := Label.new()
				tier_header.text = tier_names.get(current_tier, "TIER %d" % current_tier)
				tier_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tier_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				tier_header.add_theme_font_size_override("font_size", 16)
				tier_header.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
				tier_header.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
				tier_header.add_theme_constant_override("outline_size", 3)
				ribbon.add_child(tier_header)
				vbox.add_child(ribbon)
			_add_unit_card(vbox, bd.spawns_unit, bd, true)

		# P4: trailing spacer so the last card clears the tab bar when fully scrolled.
		var tail := Control.new()
		tail.custom_minimum_size = Vector2(0, 24)
		vbox.add_child(tail)


func _add_unit_card(parent: VBoxContainer, ud: UnitData, bd: BuildingData, is_kingdom: bool) -> void:
	var card := Panel.new()
	# P4: warm wood card (UIStyle palette) — replaces the cold-navy programmer box
	# (audit main_menu.gd:1755, card bg RGB(29,42,69) clashed with the whole kit).
	card.add_theme_stylebox_override("panel", _make_style(
		Color(UIStyle.PANEL_WOOD.r, UIStyle.PANEL_WOOD.g, UIStyle.PANEL_WOOD.b, 0.95),
		Color(UIStyle.PANEL_BORDER.r, UIStyle.PANEL_BORDER.g, UIStyle.PANEL_BORDER.b, 0.85),
		10, 2))
	card.custom_minimum_size = Vector2(680, 140)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# BUG-52: keep the icon inset ≥26 so its left edge clears the scenic-bleed
	# detector band (capture x<30) on the neighbouring tabs' shared background.
	hbox.offset_left = 26; hbox.offset_right = -10
	hbox.offset_top = 8; hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# P4 (backlog 3.6): show the UNIT idle sprite, not the spawner building. Tiny
	# Swords frames are 192x192 with the character ~60px centered, so crop to the
	# opaque content rect or it renders as a ~27px speck in the 88px box.
	var team: int = 0 if is_kingdom else 1
	var unit_tex: Texture2D = null
	var frames: SpriteFrames = SpriteRegistry.get_unit_sprites(ud.id, team)
	if frames and frames.has_animation(&"idle") and frames.get_frame_count(&"idle") > 0:
		var f: Texture2D = frames.get_frame_texture(&"idle", 0)
		if f:
			unit_tex = f
			var im: Image = f.get_image()
			if im:
				var r: Rect2i = im.get_used_rect()
				if r.size.x > 0 and r.size.y > 0:
					var at := AtlasTexture.new()
					at.atlas = f
					at.region = Rect2(r)
					unit_tex = at
	if unit_tex == null:  # never render an empty row: fall back to the building icon
		unit_tex = SpriteRegistry.get_building_sprite(bd.id, team)
	if unit_tex:
		var icon := TextureRect.new()
		icon.texture = unit_tex
		icon.custom_minimum_size = Vector2(88, 88)
		icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hbox.add_child(icon)

	# Stats column
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation", 5)
	hbox.add_child(stats)

	# Name — the row header. Role/type move to chips (drop the "[Role]" text suffix).
	var role_idx: int = clampi(ud.role, 0, 4)
	var name_lbl := Label.new()
	name_lbl.text = ud.display_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	name_lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1))
	name_lbl.add_theme_constant_override("outline_size", 2)
	stats.add_child(name_lbl)

	# Role + attack/armor type as small chips (was a dense colon-separated line).
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	_add_unit_chip(chips, ROLE_NAMES[role_idx], ROLE_COLORS[role_idx])
	_add_unit_chip(chips, ATTACK_TYPE_NAMES[clampi(ud.attack_type, 0, 3)], Color(0.55, 0.5, 0.5))
	_add_unit_chip(chips, ARMOR_TYPE_NAMES[clampi(ud.armor_type, 0, 3)] + " armor", Color(0.5, 0.52, 0.55))
	stats.add_child(chips)

	# One 16px middot stat line (was three dense 15px spreadsheet lines).
	var stat_lbl := Label.new()
	stat_lbl.text = "HP %d · DMG %d · SPD %d · RNG %d · ARM %d" % [ud.max_hp, ud.attack_damage, ud.move_speed, ud.attack_range, ud.armor]
	stat_lbl.add_theme_font_size_override("font_size", 16)
	stat_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78, 1.0))
	stats.add_child(stat_lbl)

	if ud.skill_id != &"":
		var skill_lbl := Label.new()
		skill_lbl.text = "Skill: %s" % str(ud.skill_id).replace("_", " ").capitalize()
		skill_lbl.add_theme_font_size_override("font_size", 16)
		skill_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35, 1.0))
		stats.add_child(skill_lbl)

	# Cost (bumped to match name prominence)
	var cost_lbl := Label.new()
	cost_lbl.text = "%dg" % bd.gold_cost
	cost_lbl.custom_minimum_size = Vector2(72, 0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 22)
	cost_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	cost_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 1))
	cost_lbl.add_theme_constant_override("outline_size", 2)
	hbox.add_child(cost_lbl)


## P4: a small tinted role/type chip (cream text on the role colour) via the shared kit.
func _add_unit_chip(parent: Control, text: String, col: Color) -> void:
	var chip := Label.new()
	chip.text = text
	chip.add_theme_font_size_override("font_size", 16)
	chip.add_theme_color_override("font_color", UIStyle.TEXT_CREAM)
	chip.add_theme_color_override("font_outline_color", UIStyle.OUTLINE_DARK)
	chip.add_theme_constant_override("outline_size", 1)
	chip.add_theme_stylebox_override("normal", UIStyle.stat_chip(
		Color(col.r, col.g, col.b, 0.40), Color(col.r, col.g, col.b, 0.75)))
	parent.add_child(chip)


# --- Social Tab: match record + friends placeholder ---

func _build_social_tab() -> void:
	# Hide the tscn "Coming Soon" placeholder (SocialBg + its labels).
	var social_bg = social_panel.get_node_or_null("SocialBg")
	if social_bg:
		social_bg.visible = false

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	social_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(700, 0)
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var title := Label.new()
	title.text = "SOCIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.35, 1))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 1))
	title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(title)

	# Match record card — styled like the Army tab unit cards.
	var record := Panel.new()
	record.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.18, 0.3, 0.88), Color(0.3, 0.45, 0.7, 0.6), 10, 2))
	record.custom_minimum_size = Vector2(680, 150)
	record.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(record)

	var rec_v := VBoxContainer.new()
	rec_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rec_v.offset_left = 26
	rec_v.offset_right = -26
	rec_v.offset_top = 12
	rec_v.offset_bottom = -12
	rec_v.add_theme_constant_override("separation", 8)
	record.add_child(rec_v)

	var rec_title := Label.new()
	rec_title.text = "MATCH RECORD"
	rec_title.add_theme_font_size_override("font_size", 22)
	rec_title.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	rec_title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1))
	rec_title.add_theme_constant_override("outline_size", 2)
	rec_v.add_child(rec_title)

	var losses: int = PlayerData.games_played - PlayerData.games_won
	var rec_stats := Label.new()
	rec_stats.text = "Wins: %d   Losses: %d   Games: %d" % [PlayerData.games_won, losses, PlayerData.games_played]
	rec_stats.add_theme_font_size_override("font_size", 15)
	rec_stats.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78, 1.0))
	rec_v.add_child(rec_stats)

	var rec_trophies := Label.new()
	rec_trophies.text = "Trophies: %d   Rank: %s" % [PlayerData.trophies, PlayerData.get_rank_name()]
	rec_trophies.add_theme_font_size_override("font_size", 15)
	rec_trophies.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	rec_v.add_child(rec_trophies)

	# Friends card — placeholder until multiplayer social features land.
	var friends := Panel.new()
	friends.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.18, 0.3, 0.88), Color(0.3, 0.45, 0.7, 0.6), 10, 2))
	friends.custom_minimum_size = Vector2(680, 110)
	friends.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(friends)

	var fr_v := VBoxContainer.new()
	fr_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fr_v.offset_left = 26
	fr_v.offset_right = -26
	fr_v.offset_top = 12
	fr_v.offset_bottom = -12
	fr_v.add_theme_constant_override("separation", 8)
	friends.add_child(fr_v)

	var fr_title := Label.new()
	fr_title.text = "FRIENDS"
	fr_title.add_theme_font_size_override("font_size", 22)
	fr_title.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	fr_title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1))
	fr_title.add_theme_constant_override("outline_size", 2)
	fr_v.add_child(fr_title)

	var fr_note := Label.new()
	fr_note.text = "Coming soon — challenge your friends to a duel!"
	fr_note.add_theme_font_size_override("font_size", 15)
	fr_note.add_theme_color_override("font_color", Color(0.82, 0.78, 0.65, 1.0))
	fr_v.add_child(fr_note)


# --- T-014: Settings Tab ---

var _reset_confirm: Control = null

func _build_settings_tab() -> void:
	# Hide the placeholder "Coming Soon" content
	var settings_bg = settings_panel.get_node_or_null("SettingsBg")
	if settings_bg:
		settings_bg.visible = false
	var styled_bg = settings_panel.get_node_or_null("StyledBg")
	if styled_bg:
		styled_bg.visible = false

	# Rebuilds (e.g. _do_reset) used to stack a second ScrollContainer on top
	# of the old one — _find_slider_by_callback then found the stale sliders
	# and the visible percentage labels stopped updating. Free any existing
	# container first (remove_child immediately, queue_free is deferred).
	for child in settings_panel.get_children():
		if child is ScrollContainer:
			settings_panel.remove_child(child)
			child.queue_free()

	# Scrollable container for settings content
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(700, 0)
	vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(vbox)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Title
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.35, 1))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 1))
	title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(title)

	# Volume sliders
	_add_volume_slider(vbox, "Music Volume", PlayerData.music_volume, _on_music_volume)
	_add_volume_slider(vbox, "SFX Volume", PlayerData.sfx_volume, _on_sfx_volume)
	_add_volume_slider(vbox, "UI Volume", PlayerData.ui_volume, _on_ui_volume)

	# Divider
	var div1 := ColorRect.new()
	div1.custom_minimum_size = Vector2(600, 2)
	div1.color = Color(0.5, 0.38, 0.15, 0.4)
	div1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(div1)

	# Replay Tutorial button — DISABLED: the tutorial system is globally off
	# (game_manager.gd hard-forces tutorial_mode = false and game_arena's
	# _show_tutorial() call is commented out), so "replaying" just launched a
	# normal match. Keep the button visible but inert until it returns.
	var tutorial_btn := Button.new()
	tutorial_btn.text = "Replay Tutorial (coming soon)"
	tutorial_btn.custom_minimum_size = Vector2(400, 50)
	tutorial_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tutorial_btn.disabled = true
	_style_menu_button(tutorial_btn, Color(0.25, 0.18, 0.1, 0.96), Color(0.55, 0.4, 0.18, 0.85), 16)
	vbox.add_child(tutorial_btn)

	# Reset Progress button
	var reset_btn := Button.new()
	reset_btn.text = "Reset All Progress"
	reset_btn.custom_minimum_size = Vector2(400, 50)
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_menu_button(reset_btn, Color(0.45, 0.13, 0.08, 0.96), Color(0.85, 0.3, 0.15, 0.85), 16)
	reset_btn.pressed.connect(_on_reset_progress)
	vbox.add_child(reset_btn)

	# Divider
	var div2 := ColorRect.new()
	div2.custom_minimum_size = Vector2(600, 2)
	div2.color = Color(0.5, 0.38, 0.15, 0.4)
	div2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(div2)

	# Credits
	var credits := Label.new()
	credits.text = "Made with Godot 4\nArt: Tiny Swords by Pixel Frog\n\nv0.1 — Castle Fight"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", 13)
	credits.add_theme_color_override("font_color", Color(0.88, 0.82, 0.66, 1.0))  # BUG-41: opaque, readable
	credits.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03, 1.0))
	credits.add_theme_constant_override("outline_size", 1)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(credits)


func _add_volume_slider(parent: VBoxContainer, label_text: String, initial_value: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.add_theme_constant_override("separation", 12)

	# Left padding
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(30, 0)
	row.add_child(pad)

	# Label
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 1))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	# Slider
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(250, 0)
	slider.value_changed.connect(callback)
	row.add_child(slider)

	# Percentage label
	var pct := Label.new()
	pct.text = "%d%%" % int(initial_value * 100)
	pct.custom_minimum_size = Vector2(50, 0)
	pct.add_theme_font_size_override("font_size", 14)
	pct.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)

	# Right padding
	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(30, 0)
	row.add_child(pad2)

	# Store reference to update pct label when slider changes
	slider.set_meta("pct_label", pct)

	parent.add_child(row)


func _on_music_volume(value: float) -> void:
	PlayerData.set_music_volume(value)
	var slider := _find_slider_by_callback(settings_panel, 0)
	if slider:
		var pct: Label = slider.get_meta("pct_label")
		if pct:
			pct.text = "%d%%" % int(value * 100)


func _on_sfx_volume(value: float) -> void:
	PlayerData.set_sfx_volume(value)
	var slider := _find_slider_by_callback(settings_panel, 1)
	if slider:
		var pct: Label = slider.get_meta("pct_label")
		if pct:
			pct.text = "%d%%" % int(value * 100)


func _on_ui_volume(value: float) -> void:
	PlayerData.set_ui_volume(value)
	var slider := _find_slider_by_callback(settings_panel, 2)
	if slider:
		var pct: Label = slider.get_meta("pct_label")
		if pct:
			pct.text = "%d%%" % int(value * 100)


func _find_slider_by_callback(panel: Control, index: int) -> HSlider:
	var sliders: Array[HSlider] = []
	for child in panel.get_children():
		if child is ScrollContainer:
			for sc_child in child.get_children():
				if sc_child is VBoxContainer:
					for row in sc_child.get_children():
						if row is HBoxContainer:
							for widget in row.get_children():
								if widget is HSlider:
									sliders.append(widget)
	if index < sliders.size():
		return sliders[index]
	return null


func _on_reset_progress() -> void:
	SFX.play_ui("button_click")
	if _reset_confirm:
		return
	# Show confirmation dialog
	_reset_confirm = Control.new()
	_reset_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_confirm.add_child(overlay)

	var dialog := Panel.new()
	dialog.add_theme_stylebox_override("panel", _make_style(Color(0.15, 0.1, 0.06, 0.95), Color(0.6, 0.35, 0.1, 0.8), 16, 3))
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialog.offset_left = -180
	dialog.offset_right = 180
	dialog.offset_top = -100
	dialog.offset_bottom = 100
	_reset_confirm.add_child(dialog)

	var dvbox := VBoxContainer.new()
	dvbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dvbox.add_theme_constant_override("separation", 12)
	dvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog.add_child(dvbox)

	var warn := Label.new()
	warn.text = "Reset ALL progress?\nTrophies, wins, and settings\nwill be erased."
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_font_size_override("font_size", 16)
	warn.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	warn.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 1))
	warn.add_theme_constant_override("outline_size", 2)
	dvbox.add_child(warn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	dvbox.add_child(btn_row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(120, 40)
	_style_menu_button(cancel, Color(0.25, 0.18, 0.1, 0.96), Color(0.55, 0.4, 0.18, 0.85), 16)
	cancel.pressed.connect(func():
		_reset_confirm.queue_free()
		_reset_confirm = null
	)
	btn_row.add_child(cancel)

	var confirm := Button.new()
	confirm.text = "RESET"
	confirm.custom_minimum_size = Vector2(120, 40)
	_style_menu_button(confirm, Color(0.45, 0.13, 0.08, 0.96), Color(0.85, 0.3, 0.15, 0.85), 16)
	confirm.pressed.connect(func():
		_do_reset()
		_reset_confirm.queue_free()
		_reset_confirm = null
	)
	btn_row.add_child(confirm)

	add_child(_reset_confirm)


func _do_reset() -> void:
	PlayerData.trophies = 0
	PlayerData.games_played = 0
	PlayerData.games_won = 0
	PlayerData.total_buildings = 0
	PlayerData.total_waves = 0
	PlayerData.kingdom_wins = 0
	PlayerData.horde_wins = 0
	PlayerData.last_win_timestamp = 0
	PlayerData.music_volume = 0.8
	PlayerData.sfx_volume = 1.0
	PlayerData.ui_volume = 1.0
	PlayerData._apply_audio_volumes()
	PlayerData._save()
	_update_player_stats()
	# Rebuild settings to reset slider positions
	_build_settings_tab()
