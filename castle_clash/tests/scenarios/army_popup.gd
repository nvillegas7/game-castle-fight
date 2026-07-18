## SCENARIO (backlog 3.6): Army-tab unit detail — expand-in-place.
## RED-first: written BEFORE the feature. Taps the Army tab, taps the Footman
## card, asserts the card EXPANDS with a visible UnitDetail block showing the
## tapped unit's data, captures, taps again and asserts it collapses.
## Spec: design/army_popup_target.png (approved concept B, 2026-07-18).
## Run: godot --path castle_clash -- --scenario army_popup
extends ScenarioBase


func run() -> void:
	var menu := await wait_for_main_menu()
	check("main menu loaded", menu != null, "no node with _select_tab found")
	if menu == null:
		return

	# Tab 1 = Army (0=Avatars/Shop, 1=Army, 2=Battle, 3=Social, 4=Settings)
	var tab_bar: HBoxContainer = menu.get_node_or_null("TabBar/TabButtons")
	check("tab bar found", tab_bar != null)
	if tab_bar == null:
		return
	var army_touch: Control = tab_bar.get_child(1).get_node_or_null("TouchArea")
	check("army tab has TouchArea", army_touch != null)
	if army_touch == null:
		return
	await tap(army_touch.get_global_rect().get_center())
	await wait(0.7)

	# The Footman card (cards are named UnitCard_<unit_id> — part of the 3.6 spec)
	var card: Control = menu.find_child("UnitCard_footman", true, false)
	check("footman card exists (UnitCard_footman)", card != null,
		"cards must be named UnitCard_<id> for tap targeting")
	if card == null:
		await finish()
		return

	var base_h: float = card.size.y
	await tap(card.get_global_rect().get_center())
	await wait(0.5)

	var detail: Control = card.find_child("UnitDetail", true, false)
	check("UnitDetail visible after tap", detail != null and detail.visible,
		"card tap must expand an in-place detail block")
	check("card expanded (h %.0f -> %.0f, need >=400)" % [base_h, card.size.y],
		card.size.y >= 400.0)
	if detail:
		var name_lbl: Label = detail.find_child("DetailName", true, false)
		check("detail shows the tapped unit's name",
			name_lbl != null and name_lbl.text.to_upper().contains("FOOTMAN"),
			"got: %s" % (name_lbl.text if name_lbl else "no DetailName label"))
	await capture("army_popup_open")

	# Tap again (card header area) → collapse
	var rect := card.get_global_rect()
	await tap(Vector2(rect.get_center().x, rect.position.y + 60.0))
	await wait(0.5)
	check("card collapsed after second tap", card.size.y < 200.0,
		"h=%.0f" % card.size.y)
	var detail2: Control = card.find_child("UnitDetail", true, false)
	check("UnitDetail hidden after collapse", detail2 == null or not detail2.visible)
	await capture("army_popup_closed")

	await finish()
