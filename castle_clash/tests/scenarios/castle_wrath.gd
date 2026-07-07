## SCENARIO: Castle Wrath panic button (T-090).
## Start match with the AI opponent active, wait until enemy units approach,
## force own castle to 25% HP (below the 30% wrath threshold), assert the HUD
## button appears enabled, TAP it through the real input path, then assert the
## sim consumed the ability and emitted castle_wrath_activated.
## Run: godot --path castle_clash -- --scenario castle_wrath
extends ScenarioBase

var _activations: Array = []


func run() -> void:
	EventBus.castle_wrath_activated.connect(_on_wrath_activated)

	# Keep the AI ON so enemy units exist to be hit by the shockwave.
	await start_match(&"kingdom", false)
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)
	await capture("match_start")

	# Wait for enemy units to get near our castle (y > 780) so the wrath has
	# targets in its 140px range — capped at 75s, event assert works either way.
	var arena := find_arena()
	var deadline: int = Time.get_ticks_msec() + 75000
	while Time.get_ticks_msec() < deadline:
		if _enemy_units_near_castle().size() > 0:
			break
		await wait(1.0)
	var near := _enemy_units_near_castle()
	print("[Scenario] enemy units near castle when forcing HP: %d" % near.size())

	# Force own castle to 25% — next sim tick emits castle_wrath_ready.
	force_state({"castle0_hp_pct": 25})
	await wait_ticks(3)
	await wait(0.3)  # let the HUD button spawn + first pulse frame render

	var btn: Button = null
	if arena:
		btn = arena.get_node_or_null("UILayer/CastleWrathBtn")
	check("castle wrath button visible at 25% HP", btn != null and btn.is_visible_in_tree(),
		"UILayer/CastleWrathBtn %s" % ("missing" if btn == null else "hidden"))
	check("castle wrath button enabled", btn != null and not btn.disabled,
		"disabled=%s" % (str(btn.disabled) if btn else "n/a"))
	await capture("wrath_button_ready")
	if btn == null:
		check("castle_wrath_activated emitted", false, "no button to tap — ability unreachable")
		return

	# Record HP of enemy units inside the blast range before the tap.
	var before_hp := {}
	for u in _enemy_units_near_castle():
		before_hp[u.id] = FP.to_int(u.hp)

	await tap(btn.get_global_rect().get_center())
	await wait_ticks(5)

	var sim = GameManager.simulation
	check("sim consumed castle wrath (one-time use)",
		sim.castles[0].get("castle_wrath_available", true) == false,
		"castle_wrath_available=%s" % str(sim.castles[0].get("castle_wrath_available")))
	check("castle_wrath_activated event emitted", _activations.size() >= 1,
		"activations=%d" % _activations.size())
	await capture("wrath_vfx")  # shockwave ring runs ~0.6s — catch it mid-flight

	if _activations.size() > 0:
		var act: Dictionary = _activations[0]
		print("[Scenario] wrath hit %d targets at (%.0f,%.0f) range %.0f" % [
			act.target_ids.size(), act.center_x, act.center_y, act.range_px])
		if before_hp.size() > 0:
			var damaged: int = 0
			for u in sim.entities:
				if u.type == "unit" and before_hp.has(u.id) and FP.to_int(u.hp) < before_hp[u.id]:
					damaged += 1
			# Units may also have died outright (removed from entities) — count those too.
			for id in before_hp:
				if sim._find_entity_by_id(id) == null:
					damaged += 1
			check("enemy units in range damaged by wrath", damaged > 0,
				"%d in range before, %d damaged/killed" % [before_hp.size(), damaged])
		else:
			print("[Scenario] no enemy units were in range — damage assert skipped (event assert covers activation)")

	await wait(0.5)
	await capture("after_wrath")


func _enemy_units_near_castle() -> Array:
	var found: Array = []
	var sim = GameManager.simulation
	if sim == null:
		return found
	for e in sim.entities:
		if e.type == "unit" and e.team == 1 and FP.to_float(e.y) > 780.0:
			found.append(e)
	return found


func _on_wrath_activated(team: int, target_ids: Array, cx: float, cy: float, range_px: float) -> void:
	_activations.append({"team": team, "target_ids": target_ids,
		"center_x": cx, "center_y": cy, "range_px": range_px})
