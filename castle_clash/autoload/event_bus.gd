## Global signal bus for decoupled communication between systems.
extends Node

# -- Match Lifecycle --
signal match_started
signal match_ended(winning_team: int)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)

# -- Economy --
signal gold_changed(player_id: int, new_amount: int)
signal income_tick(player_id: int, amount: int)

# -- Buildings --
signal building_placed(player_id: int, building_data: Resource, grid_pos: Vector2i)
signal building_destroyed(building_id: int)

# -- Units --
signal unit_spawned(unit_id: int, unit_type: StringName)
signal unit_died(unit_id: int, killer_id: int)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, target_x: float, target_y: float)
signal unit_healed(healer_id: int, target_id: int, amount: int, target_x: float, target_y: float)
signal skill_activated(unit_id: int, skill_id: StringName)

# -- Castle --
signal castle_damaged(team: int, damage: int, remaining_hp: int)

# -- Network --
signal connected_to_server
signal disconnected_from_server
signal match_found(match_id: String)
signal desync_detected(tick: int)

# -- UI --
signal show_toast(message: String, duration: float)
