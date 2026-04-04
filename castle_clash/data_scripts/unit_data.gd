## Defines stats for a unit type. Stored as .tres resources.
@tool
class_name UnitData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var faction: StringName = &""

@export_group("Combat Stats")
@export var max_hp: int = 100
@export var attack_damage: int = 10
@export var attack_speed_ticks: int = 10   # Ticks between attacks
@export var attack_range: int = 1          # Grid cells (how close to attack)
@export var aggro_range: int = 4           # Grid cells (how far to detect/chase enemies)
@export var move_speed: int = 2            # Grid cells per second
@export var armor: int = 0                 # Reduces Physical/Pierce/Siege damage
@export var magic_defense: int = 0         # Reduces Magic damage

@export_group("Economy")
@export var bounty: int = 5  # Gold awarded to enemy team on kill

@export_group("Skill")
@export var skill_id: StringName = &""     # Unique ability identifier
@export var skill_param_1: int = 0         # Skill-specific parameter
@export var skill_param_2: int = 0         # Secondary skill parameter

@export_group("Type Classification")
@export_enum("Physical", "Pierce", "Magic", "Siege") var attack_type: int = 0
@export_enum("Light", "Medium", "Heavy", "Fortified") var armor_type: int = 0
@export_enum("Melee", "Ranged", "Caster", "Flying", "Siege") var role: int = 0

@export_group("Visuals")
@export var sprite_frames: SpriteFrames = null
@export var scale_factor: float = 1.0  # Visual only, NOT used in simulation
