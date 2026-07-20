## Pure movement/animation tuning math — no node or autoload dependencies, so it
## is unit-testable headless (see tests/test_combat_feel.gd). The visual layer
## reads these; keep them free of scene/sim references.
class_name CombatTuning

# Walk plays at speed_scale 1.0 when a unit moves at the footman reference speed.
# Footman: ud.move_speed(2 cells/s) × CELL_SIZE_PX(28) × 0.80 penalty /
# TICKS_PER_SECOND(10) = 4.48 px/tick (see simulation.gd move_speed_fp).
const WALK_REFERENCE_PX_PER_TICK: float = 4.48


## BUG-40 fix: map a unit's per-TICK move speed to a walk-animation speed_scale.
## The old inline calc divided px/tick by a px/SEC baseline (44.8), so every
## unit's legs cycled at ~10% of ground travel — universal foot-skate. Faster
## units cycle legs proportionally faster so stride matches ground travel.
static func walk_ratio_for_speed(move_speed_px_per_tick: float) -> float:
	if move_speed_px_per_tick <= 0.0:
		return 1.0
	return move_speed_px_per_tick / WALK_REFERENCE_PX_PER_TICK


# 1C-3: projectile flight seconds — single source of truth shared by the
# projectile visuals (effects.gd, both sprite and fallback paths) and
# game_arena's deferred victim-side impact FX, so the damage number lands
# when the projectile does. Speeds mirror the old sprite-path px/sec; mins
# keep the old fallback floors so point-blank shots stay readable.
const _PROJ_FLIGHT := {
	&"arrow": {"speed": 220.0, "min": 0.15},
	&"rock": {"speed": 140.0, "min": 0.2},
	&"fireball": {"speed": 200.0, "min": 0.15},
	&"bolt": {"speed": 250.0, "min": 0.12},
}


static func flight_time(kind: StringName, from_pos: Vector2, to_pos: Vector2) -> float:
	if kind == &"tower":
		return 0.2
	var p: Dictionary = _PROJ_FLIGHT.get(kind, {"speed": 250.0, "min": 0.1})
	return maxf(from_pos.distance_to(to_pos) / float(p.speed), float(p.min))
