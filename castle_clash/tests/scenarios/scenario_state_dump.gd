## Serializes assertable game state to a Dictionary. Written as JSON next to
## every scenario capture so each screenshot ships with the sim/UI state that
## produced it (foundation for future golden diffing).
class_name ScenarioStateDump


static func build(tree: SceneTree) -> Dictionary:
	var out := {
		"timestamp": Time.get_datetime_string_from_system(),
		"scene": String(tree.current_scene.name) if tree.current_scene else "",
	}
	var gm := tree.root.get_node_or_null("GameManager")
	if gm == null:
		return out
	out["game_state"] = ["MENU", "LOADING", "COUNTDOWN", "PLAYING", "MATCH_OVER"][gm.state]
	out["tick"] = gm.current_tick

	var sim = gm.simulation
	if sim != null:
		out["sim"] = _dump_sim(sim)

	var cs := tree.current_scene
	if cs and cs.has_method("grid_to_screen"):
		out["camera"] = _dump_camera(cs)
		out["ui"] = _dump_arena_ui(cs)
	elif cs and cs.has_method("_select_tab"):
		out["ui"] = {"screen": "main_menu", "current_tab": cs.get("_current_tab")}
	return out


static func _dump_sim(sim) -> Dictionary:
	var d := {
		"tick": sim.tick,
		"seed": sim.match_seed,
		"prep_phase": sim.prep_phase,
		"match_over": sim.match_over,
		"winning_team": sim.winning_team,
		"wave_number": sim.wave_number,
		"gold": [],
		"castles": [],
		"units": [],
		"buildings": [],
		"occupied_cells": [],
	}
	for p in sim.players:
		d.gold.append(FP.to_int(p.gold))
	for c in sim.castles:
		d.castles.append({
			"team": c.team,
			"hp": FP.to_int(c.hp),
			"max_hp": FP.to_int(c.max_hp),
			"wrath_available": c.get("castle_wrath_available", false),
			"wrath_ready_emitted": c.get("castle_wrath_ready_emitted", false),
		})
	for e in sim.entities:
		if e.type == "unit":
			var px: float = FP.to_float(e.x)
			var py: float = FP.to_float(e.y)
			var state_i: int = e.get("state", 0)
			d.units.append({
				"id": e.id,
				"type": String(e.get("unit_type", &"")),
				"team": e.team,
				"hp": FP.to_int(e.hp),
				"x": snappedf(px, 0.1),
				"y": snappedf(py, 0.1),
				# Occupancy-grid cell (col from GRID_ORIGIN_X=206, row from Y=55)
				"cell": [int((px - sim.GRID_ORIGIN_X) / sim.CELL_SIZE_PX),
					int((py - sim.UNIT_GRID_Y_OFFSET) / sim.CELL_SIZE_PX)],
				"state": ["march", "chase", "attack"][state_i] if state_i < 3 else str(state_i),
			})
		elif e.type == "building":
			d.buildings.append({
				"id": e.id,
				"type": String(e.get("building_type", &"")),
				"team": e.team,
				"hp": FP.to_int(e.hp),
				"grid": [e.get("grid_x", -1), e.get("grid_y", -1)],
			})
	# Build-zone occupancy: entity-occupied cells per player grid, "col,row=id"
	for pi in sim.grid_cells.size():
		var cells: Array = []
		for row in sim.GRID_ROWS:
			for col in sim.GRID_COLS:
				var v: int = sim.grid_cells[pi][row][col]
				if v >= 0:
					cells.append("%d,%d=%d" % [col, row, v])
		d.occupied_cells.append(cells)
	return d


static func _dump_camera(arena: Node2D) -> Dictionary:
	var cam: Camera2D = arena.get_node_or_null("Camera2D")
	if cam == null:
		return {}
	return {
		"zoom": snappedf(cam.zoom.x, 0.001),
		"x": snappedf(cam.position.x, 0.1),
		"y": snappedf(cam.position.y, 0.1),
	}


static func _dump_arena_ui(arena: Node2D) -> Dictionary:
	var ui := {"screen": "game_arena"}
	var layer := arena.get_node_or_null("UILayer")
	if layer == null:
		return ui

	var hud: Control = layer.get_node_or_null("HUD")
	if hud:
		ui["hud"] = {"visible": hud.is_visible_in_tree(), "rect": _rect(hud.get_global_rect())}
		var castle_label: Label = hud.get_node_or_null("HBox/CastleLabel")
		if castle_label:
			ui.hud["castle_text"] = castle_label.text
		var wave_label: Label = hud.get_node_or_null("HBox/WaveLabel")
		if wave_label:
			ui.hud["wave_text"] = wave_label.text

	var gold_bar: Control = layer.get_node_or_null("GoldBarBg")
	if gold_bar:
		var lbl: Label = gold_bar.get_node_or_null("GoldBarLabel")
		ui["gold_bar"] = {
			"visible": gold_bar.is_visible_in_tree(),
			"rect": _rect(gold_bar.get_global_rect()),
			"text": lbl.text if lbl else "",
		}

	var hand: Control = layer.get_node_or_null("CardHand")
	if hand:
		var card_count: int = 0
		var selected: String = ""
		for child in hand.get_children():
			if child.get("bd") != null:
				card_count += 1
		var grid = arena.get("grid_overlay_0")
		if grid and grid.selected_building != null:
			selected = String(grid.selected_building.id)
		ui["card_hand"] = {
			"visible": hand.is_visible_in_tree(),
			"rect": _rect(hand.get_global_rect()),
			"cards": card_count,
			"selected_building": selected,
		}

	var end_screen: Control = layer.get_node_or_null("EndScreen")
	if end_screen:
		var result: Label = end_screen.get_node_or_null("VBox/ResultLabel")
		ui["end_screen"] = {
			"visible": end_screen.is_visible_in_tree(),
			"result_text": result.text if result else "",
		}

	# T-090 Castle Wrath panic button (spawned dynamically when HP < 30%)
	var wrath: Button = layer.get_node_or_null("CastleWrathBtn")
	if wrath:
		ui["castle_wrath_button"] = {
			"visible": wrath.is_visible_in_tree(),
			"disabled": wrath.disabled,
			"rect": _rect(wrath.get_global_rect()),
		}
	else:
		ui["castle_wrath_button"] = null

	# T-043 special-building ability buttons
	var ability_buttons: Array = []
	var btn_map = arena.get("_ability_buttons")
	if btn_map is Dictionary:
		for bid in btn_map:
			var b = btn_map[bid]
			if is_instance_valid(b):
				ability_buttons.append({
					"building_id": bid,
					"visible": b.is_visible_in_tree(),
					"disabled": b.disabled,
					"ready": b.is_ready,
					"rect": _rect(b.get_global_rect()),
				})
	ui["ability_buttons"] = ability_buttons
	return ui


static func _rect(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1),
		snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]
