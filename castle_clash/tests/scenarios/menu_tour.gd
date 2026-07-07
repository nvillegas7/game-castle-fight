## SCENARIO: main-menu tab tour.
## Walks all 5 bottom-bar tabs by TAPPING each tab button (real GUI input
## path — not _select_tab() calls), asserts the menu switched, captures each.
## Run: godot --path castle_clash -- --scenario menu_tour
extends ScenarioBase

# Tab order from main_menu.gd: 0=Shop, 1=Army, 2=Battle, 3=Social, 4=Settings
const TAB_NAMES := ["shop", "army", "battle", "social", "settings"]


func run() -> void:
	var menu := await wait_for_main_menu()
	check("main menu loaded", menu != null, "no node with _select_tab found")
	if menu == null:
		return
	check("battle tab is the landing tab", menu.get("_current_tab") == 2,
		"current_tab=%s" % str(menu.get("_current_tab")))
	await capture("menu_initial")

	var tab_bar: HBoxContainer = menu.get_node_or_null("TabBar/TabButtons")
	check("tab bar found with 5 tabs", tab_bar != null and tab_bar.get_child_count() == 5,
		"children=%s" % (str(tab_bar.get_child_count()) if tab_bar else "no TabBar/TabButtons"))
	if tab_bar == null:
		return

	for i in TAB_NAMES.size():
		var tab: Control = tab_bar.get_child(i)
		var touch: Control = tab.get_node_or_null("TouchArea")
		if touch == null:
			check("tab %d (%s) has TouchArea" % [i, TAB_NAMES[i]], false)
			continue
		await tap(touch.get_global_rect().get_center())
		await wait(0.7)  # 350ms panel transition + settle
		check("tab %d (%s) selected after tap" % [i, TAB_NAMES[i]],
			menu.get("_current_tab") == i,
			"current_tab=%s" % str(menu.get("_current_tab")))
		await capture("tab_%s" % TAB_NAMES[i])

	# Return to the battle tab so the menu is left in its default state.
	var battle_touch: Control = tab_bar.get_child(2).get_node_or_null("TouchArea")
	if battle_touch:
		await tap(battle_touch.get_global_rect().get_center())
		await wait(0.5)
