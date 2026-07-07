## Global signal bus for decoupled communication between systems.
extends Node

# -- Match Lifecycle --
signal match_started
signal match_ended(winning_team: int)
signal match_aborted(reason: String)
signal countdown_tick(seconds_left: int)  # 3, 2, 1, 0 (0 = GO)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal prep_phase_ended

# -- Economy --
signal gold_changed(player_id: int, new_amount: int)
signal income_tick(player_id: int, amount: int)

# -- Buildings --
signal building_placed(player_id: int, building_data: Resource, grid_pos: Vector2i)
## reason: "sold" (owner sell action) or "killed" (destroyed in combat).
signal building_destroyed(building_id: int, reason: String)

# -- Units --
signal unit_spawned(unit_id: int, unit_type: StringName)
## bounty/pos come from the sim event payload — the entity is already removed
## from the simulation when this fires, so receivers must NOT re-look it up.
signal unit_died(unit_id: int, killer_id: int, bounty: int, pos_x: float, pos_y: float)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, target_x: float, target_y: float)
signal unit_healed(healer_id: int, target_id: int, amount: int, target_x: float, target_y: float)
signal skill_activated(unit_id: int, skill_id: StringName)
## Special-building active ability (War Horn rally_cry, Blood Totem blood_rage).
## Fires for BOTH teams from the sim, so enemy activations are visible/audible.
signal ability_activated(building_id: int, team: int, ability: String, duration: int)

# -- Castle --
signal castle_damaged(team: int, damage: int, remaining_hp: int, attacker_id: int)
signal castle_wrath_ready(team: int, castle_id: int)
signal castle_wrath_activated(team: int, target_ids: Array, center_x: float, center_y: float, range_px: float)
## reason: "already_used" | "hp_above_threshold" | "castle_missing"
signal castle_wrath_refused(team: int, reason: String)

# -- Network --
signal connected_to_server
signal disconnected_from_server
signal match_found(match_id: String)
signal desync_detected(tick: int)
signal connection_status_changed(status: String)  # UI-friendly status text

# -- UI --
signal show_toast(message: String, duration: float)

# -- Tutorial --
signal tutorial_step_changed(step: int)
