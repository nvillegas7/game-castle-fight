## DEBUG scenario: prints window/viewport transform data and probes where
## synthesized events actually land. Not part of the v1 suite.
extends ScenarioBase


func run() -> void:
	var window := get_window()
	print("window.size = %s" % window.size)
	print("window.content_scale_size = %s" % window.content_scale_size)
	print("window.content_scale_factor = %s" % window.content_scale_factor)
	print("window.get_final_transform() = %s" % window.get_final_transform())
	print("window.get_screen_transform() = %s" % window.get_screen_transform())
	print("viewport rect = %s" % get_viewport().get_visible_rect())

	# Probe Control that reports what the GUI actually receives.
	var probe := ProbeControl.new()
	probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	probe.mouse_filter = Control.MOUSE_FILTER_PASS
	get_tree().root.add_child(probe)

	var target := Vector2(360, 640)
	var candidates := {
		"final": window.get_final_transform(),
		"final_inv": window.get_final_transform().affine_inverse(),
		"identity": Transform2D.IDENTITY,
	}
	for label in candidates:
		var xform: Transform2D = candidates[label]
		var fed: Vector2 = xform * target
		probe.last_pos = Vector2(-1, -1)
		var ev := InputEventMouseMotion.new()
		ev.position = fed
		ev.global_position = fed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame
		await get_tree().process_frame
		print("candidate '%s': fed window-pos %s -> viewport.get_mouse_position()=%s, probe _gui_input pos=%s" % [
			label, fed, get_viewport().get_mouse_position(), probe.last_pos])
	check("debug complete", true)


class ProbeControl extends Control:
	var last_pos := Vector2(-1, -1)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			last_pos = event.position

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			print("    [probe _input] event.position=%s" % event.position)
