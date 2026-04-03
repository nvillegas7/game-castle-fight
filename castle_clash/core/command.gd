## Command types that players send. Commands are the ONLY input
## to the deterministic simulation -- serialized, relayed, replayed identically.
class_name Command

enum Type {
	PLACE_BUILDING,
	SELL_BUILDING,
	USE_ABILITY,
}


static func place_building(player_id: int, building_type: StringName, grid_x: int, grid_y: int) -> Dictionary:
	return {
		"type": Type.PLACE_BUILDING,
		"player_id": player_id,
		"building_type": building_type,
		"grid_x": grid_x,
		"grid_y": grid_y,
	}


static func sell_building(player_id: int, building_id: int) -> Dictionary:
	return {
		"type": Type.SELL_BUILDING,
		"player_id": player_id,
		"building_id": building_id,
	}


static func use_ability(player_id: int, ability_id: StringName, target_x: int, target_y: int) -> Dictionary:
	return {
		"type": Type.USE_ABILITY,
		"player_id": player_id,
		"ability_id": ability_id,
		"target_x": target_x,
		"target_y": target_y,
	}
