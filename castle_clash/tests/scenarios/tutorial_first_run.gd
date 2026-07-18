## SCENARIO (backlog 3.1): first-run tutorial re-enable.
## RED-first: written while the tutorial is still hard-disabled
## (game_manager.gd start_test_match forces tutorial_mode=false).
## Asserts, on a games_played==0 profile: the overlay APPEARS, a building can
## STILL be placed through it (the 2026-04-14 disable reason was the overlay
## eating all input — root cause tutorial.gd MOUSE_FILTER_STOP), and the step
## machine advances on placement. Then asserts a veteran (games_played>0)
## match shows NO overlay.
## Run: godot --path castle_clash -- --scenario tutorial_first_run
extends ScenarioBase


func run() -> void:
	var menu := await wait_for_main_menu()
	check("main menu loaded", menu != null)
	if menu == null:
		return

	# --- Fresh profile: runtime-only (no save) ---
	PlayerData.games_played = 0
	await start_match()
	await wait(1.0)
	var arena := find_arena()
	check("arena loaded", arena != null)
	if arena == null:
		await finish()
		return
	check("tutorial_mode ON for first game", GameManager.tutorial_mode,
		"start_test_match must gate tutorial_mode on games_played==0")
	var overlay: Node = arena.find_child("TutorialOverlay", true, false)
	check("tutorial overlay visible", overlay != null,
		"game_arena._show_tutorial must run on first game")
	await capture("tutorial_step1")

	# The overlay must NOT block building placement (the original disable bug).
	# Cell (2,2): clear of the team-0 castle footprint (rows 6-9, BUG-51).
	var placed: int = await place_building_via_input(&"barracks", Vector2i(2, 2))
	check("building placeable THROUGH the overlay", placed > 0,
		"MOUSE_FILTER_STOP on the overlay root eats the tap")
	await wait(0.5)
	if overlay != null:
		check("step advanced past 1 after placement", GameManager.tutorial_step >= 2,
			"step=%d" % GameManager.tutorial_step)
	await capture("tutorial_step2")

	# --- Veteran profile: no tutorial ---
	GameManager.reset_match()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu.tscn")
	await wait(1.0)
	PlayerData.games_played = 3
	await start_match()
	await wait(1.0)
	var arena2 := find_arena()
	var overlay2: Node = arena2.find_child("TutorialOverlay", true, false) if arena2 else null
	check("no tutorial for veteran (games_played=3)",
		not GameManager.tutorial_mode and overlay2 == null,
		"tutorial_mode=%s overlay=%s" % [GameManager.tutorial_mode, overlay2])
	await finish()
