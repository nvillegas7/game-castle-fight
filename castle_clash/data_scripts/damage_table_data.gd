## Damage multiplier table: attack_type vs armor_type.
## Values are percentages (100 = 1.0x, 150 = 1.5x).
@tool
class_name DamageTableData
extends Resource

# 4x4 matrix: [attack_type][armor_type]
# Attack: 0=Physical, 1=Pierce, 2=Magic, 3=Siege
# Armor:  0=Light, 1=Medium, 2=Heavy, 3=Fortified
@export var table: Array[Array] = [
	[100, 100, 75, 50],   # Physical
	[150, 75, 100, 50],   # Pierce
	[125, 75, 100, 100],  # Magic
	[50, 50, 50, 150],    # Siege
]


## Look up damage multiplier as fixed-point value.
func get_multiplier_fp(attack_type: int, armor_type: int) -> int:
	var percent: int = table[attack_type][armor_type]
	return FP.div(FP.from_int(percent), FP.from_int(100))
