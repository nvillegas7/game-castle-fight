## Entry point. Loads the game arena for development.
## Will be replaced with a main menu later.
extends Node


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game_arena.tscn")
