## A 2D vector using fixed-point integers for deterministic simulation.
## Stored as Dictionary {"x": int, "y": int} for serialization simplicity.
##
## Usage:
##   var pos := FPVec2.create(FP.from_int(10), FP.from_int(5))
##   var vel := FPVec2.create(FP.from_int(1), FP.ZERO)
##   var new_pos := FPVec2.add(pos, vel)
class_name FPVec2


static func create(x: int = 0, y: int = 0) -> Dictionary:
	return { "x": x, "y": y }


static func from_ints(x: int, y: int) -> Dictionary:
	return { "x": FP.from_int(x), "y": FP.from_int(y) }


static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	return { "x": a.x + b.x, "y": a.y + b.y }


static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return { "x": a.x - b.x, "y": a.y - b.y }


static func mul_scalar(v: Dictionary, s: int) -> Dictionary:
	return { "x": FP.mul(v.x, s), "y": FP.mul(v.y, s) }


static func div_scalar(v: Dictionary, s: int) -> Dictionary:
	return { "x": FP.div(v.x, s), "y": FP.div(v.y, s) }


## Squared length -- prefer this over length() for distance comparisons.
static func length_squared(v: Dictionary) -> int:
	return FP.mul(v.x, v.x) + FP.mul(v.y, v.y)


## Actual length (uses fixed-point sqrt -- expensive).
static func length(v: Dictionary) -> int:
	return FP.sqrt_fp(length_squared(v))


## Squared distance between two points.
static func distance_squared(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return FP.mul(dx, dx) + FP.mul(dy, dy)


## Normalize to unit length. Returns zero vector if input is zero.
static func normalize(v: Dictionary) -> Dictionary:
	var len: int = length(v)
	if len == 0:
		return create()
	return { "x": FP.div(v.x, len), "y": FP.div(v.y, len) }


static func dot(a: Dictionary, b: Dictionary) -> int:
	return FP.mul(a.x, b.x) + FP.mul(a.y, b.y)


## Convert to Godot Vector2 for rendering ONLY.
static func to_vector2(v: Dictionary) -> Vector2:
	return Vector2(FP.to_float(v.x), FP.to_float(v.y))


static func equals(a: Dictionary, b: Dictionary) -> bool:
	return a.x == b.x and a.y == b.y
