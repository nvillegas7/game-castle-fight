## Entry point. Loads the main menu.
extends Node


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
