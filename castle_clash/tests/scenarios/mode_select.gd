## SCENARIO (backlog 3.1): battle-tab game-mode selector.
## RED-first: written BEFORE the selector was rebuilt (the T-056 selector was
## buried with _build_progression_display). Taps Blitz and Mirror chips and
## asserts GameManager.selected_game_mode follows; Standard restores.
## Spec: design/battle_mode_row_target.png (variant b, approved 2026-07-18).
## Run: godot --path castle_clash -- --scenario mode_select
extends ScenarioBase


func run() -> void:
	var menu := await wait_for_main_menu()
	check("main menu loaded", menu != null)
	if menu == null:
		return
	check("landing mode is STANDARD",
		GameManager.selected_game_mode == GameManager.GameMode.STANDARD)

	# Mode chips are named ModeChip_<Name> (part of the 3.1 spec)
	for pair in [["Blitz", GameManager.GameMode.BLITZ],
			["Mirror", GameManager.GameMode.MIRROR],
			["Standard", GameManager.GameMode.STANDARD]]:
		var chip: Control = menu.find_child("ModeChip_%s" % pair[0], true, false)
		check("%s chip exists" % pair[0], chip != null,
			"chips must be named ModeChip_<Name>")
		if chip == null:
			await finish()
			return
		await tap(chip.get_global_rect().get_center())
		await wait(0.3)
		check("mode == %s after tap" % pair[0],
			GameManager.selected_game_mode == pair[1],
			"got %d" % GameManager.selected_game_mode)
	await capture("mode_row")
	await finish()
