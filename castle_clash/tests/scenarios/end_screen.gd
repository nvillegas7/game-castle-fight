## SCENARIO: end screen — victory then defeat.
## Victory: place a barracks (real input), force the enemy castle to 1 HP,
## let our footmen land the killing blow so the SIM finishes the match, then
## capture the victory screen. Restart via the real Restart button, then force
## own castle to 0 (sim win-check detects it) and capture the defeat screen.
## Run: godot --path castle_clash -- --scenario end_screen
extends ScenarioBase

const BUILD_CELL := Vector2i(4, 6)  # near the front so footmen march sooner


func run() -> void:
	await start_match(&"kingdom", true)  # AI off: enemy can't interfere with the script
	check("match is PLAYING", GameManager.state == GameManager.State.PLAYING)

	var eid: int = await place_building_via_input(&"barracks", BUILD_CELL)
	check("barracks placed for the win push", eid >= 0)

	# Wait for the first friendly footman (prep 15s + spawn interval 13s).
	var have_unit := await _wait_for_friendly_unit(60.0)
	check("friendly unit spawned", have_unit, "no team-0 unit within 60s")

	# Force the enemy castle to its last hit point — the sim must finish it.
	force_state({"castle1_hp": 1})
	await capture("enemy_castle_at_1hp")

	var sim = GameManager.simulation
	var deadline: int = Time.get_ticks_msec() + 60000
	while not sim.match_over and Time.get_ticks_msec() < deadline:
		await wait(0.5)
	check("sim finished the 1-HP castle via unit damage (60s budget)", sim.match_over,
		"match_over=%s — forcing HP to 0 to continue" % str(sim.match_over))
	if not sim.match_over:
		force_state({"castle1_hp": 0})  # fallback: sim win-check still detects it

	var end := await _wait_for_end_screen(15.0)
	check("end screen visible after victory", end != null and end.is_visible_in_tree())
	var result: Label = end.get_node_or_null("VBox/ResultLabel") if end else null
	check("victory text shown", result != null and result.text.begins_with("VICTORY"),
		"result_text='%s'" % (result.text if result else "n/a"))
	await wait(1.2)  # let stars/confetti/trophy animation land
	await capture("victory")

	# --- Defeat variant: restart via the REAL button, then lose ---
	var restart: Button = end.get_node_or_null("VBox/RestartButton") if end else null
	check("restart button present", restart != null)
	if restart == null:
		return
	await tap(restart.get_global_rect().get_center())
	var deadline2: int = Time.get_ticks_msec() + 15000
	while GameManager.state != GameManager.State.PLAYING and Time.get_ticks_msec() < deadline2:
		await get_tree().process_frame
	check("restart began a new match", GameManager.state == GameManager.State.PLAYING)
	if GameManager.state != GameManager.State.PLAYING:
		return
	var arena := find_arena()
	if arena:
		arena.ai_disabled = true
	await wait(1.0)

	# Lose: zero our own castle; the sim's win-condition check emits match_over.
	force_state({"castle0_hp": 0})
	var end2 := await _wait_for_end_screen(15.0)
	check("end screen visible after defeat", end2 != null and end2.is_visible_in_tree())
	var result2: Label = end2.get_node_or_null("VBox/ResultLabel") if end2 else null
	check("defeat text shown", result2 != null and result2.text.begins_with("DEFEAT"),
		"result_text='%s'" % (result2.text if result2 else "n/a"))
	await wait(1.2)
	await capture("defeat")


func _wait_for_friendly_unit(timeout_sec: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var sim = GameManager.simulation
		if sim:
			for e in sim.entities:
				if e.type == "unit" and e.team == 0:
					return true
		await wait(0.5)
	return false


## The end screen lives inside the arena scene (UILayer/EndScreen); it turns
## visible ~1.5s after match_over (dramatic slow-mo in GameManager).
func _wait_for_end_screen(timeout_sec: float) -> Control:
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var arena := find_arena()
		if arena:
			var end: Control = arena.get_node_or_null("UILayer/EndScreen")
			if end and end.is_visible_in_tree():
				return end
		await get_tree().process_frame
	return null
