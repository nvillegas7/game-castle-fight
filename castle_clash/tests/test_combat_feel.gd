## Combat/movement FEEL regression. Logic-level checks on the visual layer's
## speed/timing math — no rendering, runs headless. Grows with each 1C fix.
## Run: godot --headless -s tests/test_combat_feel.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	print("\n=== COMBAT FEEL ===\n")
	_test_walk_cadence()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % name)
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


func _test_walk_cadence() -> void:
	print("[Walk cadence ratio (BUG-40)]")
	# Footman reference speed (4.48 px/tick) → legs at 1.0x, matching ground travel.
	var footman: float = CombatTuning.walk_ratio_for_speed(4.48)
	_ok("footman (4.48 px/tick) -> ~1.0x cadence", is_equal_approx(footman, 1.0),
		"got %f" % footman)
	# Guards against the old bug: baseline 44.8 (px/SEC) gave ratio ~0.10 = foot-skate.
	_ok("not the old ~10%% foot-skate cadence", footman > 0.5,
		"ratio %f looks like the px/sec-baseline bug" % footman)
	# Faster unit cycles legs faster; slower slower; stationary safe.
	_ok("2x speed -> ~2x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(8.96), 2.0),
		"got %f" % CombatTuning.walk_ratio_for_speed(8.96))
	_ok("half speed -> ~0.5x cadence", is_equal_approx(CombatTuning.walk_ratio_for_speed(2.24), 0.5),
		"got %f" % CombatTuning.walk_ratio_for_speed(2.24))
	_ok("stationary -> 1.0 (no divide-by-zero)", CombatTuning.walk_ratio_for_speed(0.0) == 1.0)
