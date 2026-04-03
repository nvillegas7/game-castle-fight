## Defines a faction and its available buildings.
@tool
class_name FactionData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

@export_group("Buildings")
@export var buildings: Array[BuildingData] = []

@export_group("Visuals")
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.GRAY
@export var icon: Texture2D = null
