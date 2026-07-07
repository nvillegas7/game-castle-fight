## Scene transition: fade-to-black between scenes.
## Usage: SceneTransition.change_scene("res://scenes/ui/main_menu.tscn")
extends CanvasLayer

var _overlay: ColorRect
const FADE_DURATION := 0.3

func _ready() -> void:
	layer = 100  # Above everything
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)


func change_scene(path: String) -> void:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during transition
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	tw.tween_callback(_do_change.bind(path))


func _do_change(path: String) -> void:
	get_tree().change_scene_to_file(path)
	# Fade back in after scene loads
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, FADE_DURATION)
	tw.tween_callback(func(): _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE)
