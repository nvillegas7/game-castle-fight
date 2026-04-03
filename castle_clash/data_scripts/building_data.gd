## Defines stats for a building type. Stored as .tres resources.
@tool
class_name BuildingData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var faction: StringName = &""

@export_group("Economy")
@export var gold_cost: int = 50
@export var sell_refund_percent: int = 50  # 0-100

@export_group("Spawning")
@export var spawns_unit: UnitData = null
@export var units_per_wave: int = 1
@export var tier: int = 1  # 1-4

@export_group("Requirements")
@export var requires_building: StringName = &""  # Tech tree prerequisite

@export_group("Grid")
@export var grid_size: Vector2i = Vector2i(1, 1)

@export_group("Visuals")
@export var sprite: Texture2D = null
