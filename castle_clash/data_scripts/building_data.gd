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
@export var income_bonus: int = 0  # Extra gold per income tick (for economy buildings)

@export_group("Spawning")
@export var spawns_unit: UnitData = null
@export var units_per_wave: int = 1
@export var spawn_interval_ticks: int = 200  # Ticks between spawns (20s at 10tps)
@export var tier: int = 1  # 1-4

@export_group("Tower")
@export var is_tower: bool = false              # Attacks enemies directly instead of spawning units
@export var tower_damage: int = 0               # Damage per attack
@export var tower_range: int = 4                # Range in grid cells
@export var tower_attack_speed: int = 15        # Ticks between attacks
@export_enum("Physical", "Pierce", "Magic", "Siege") var tower_attack_type: int = 0

@export_group("Requirements")
@export var requires_building: StringName = &""

@export_group("Combat")
# T-079: per-building HP and armor. max_hp=0 → use formula max(300, gold_cost*5).
# armor defaults to 2 (basic). Set 5 for towers/walls, 3-4 for spawners, etc.
@export var max_hp: int = 0
@export var armor: int = 2

@export_group("Grid")
@export var grid_size: Vector2i = Vector2i(1, 1)

@export_group("Visuals")
@export var sprite: Texture2D = null
