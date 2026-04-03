## Fixed-point math library using Q16.16 format.
## All game-logic math MUST use this instead of float.
##
## A fixed-point value is stored as a regular int.
## The lower 16 bits represent the fractional part.
## Example: the integer 3 is stored as 3 << 16 = 196608.
##
## Usage:
##   var speed := FP.from_int(5)
##   var half := FP.from_float_EDITOR(0.5)  # ONLY for loading data
##   var result := FP.mul(speed, half)       # 2.5 in fixed-point
##   var display := FP.to_float(result)      # Convert back for rendering only
class_name FP

const SHIFT: int = 16
const ONE: int = 1 << SHIFT           # 65536 = 1.0
const HALF: int = ONE >> 1            # 32768 = 0.5
const ZERO: int = 0
const TWO: int = 2 << SHIFT
const NEG_ONE: int = -(1 << SHIFT)

# Common precomputed constants
const PI: int = 205887                 # 3.14159... * 65536
const TWO_PI: int = 411775
const HALF_PI: int = 102944
const SQRT2: int = 92682              # 1.41421... * 65536


# --- Conversion ---

## Convert an integer to fixed-point.
static func from_int(value: int) -> int:
	return value << SHIFT


## Convert a fixed-point value to int (truncates fractional part).
static func to_int(value: int) -> int:
	if value >= 0:
		return value >> SHIFT
	else:
		return -((-value) >> SHIFT)


## Convert a fixed-point value to float FOR DISPLAY/RENDERING ONLY.
## NEVER use the returned float in game logic.
static func to_float(value: int) -> float:
	return float(value) / float(ONE)


## Convert a float to fixed-point. ONLY for editor tools and data loading.
## NEVER call this at runtime during simulation.
static func from_float_EDITOR(value: float) -> int:
	return int(value * float(ONE))


## Create fixed-point from integer + thousandths (0-999).
## Example: from_thousandths(3, 500) = 3.5
static func from_thousandths(integer_part: int, thousandths: int) -> int:
	var frac: int = (thousandths * ONE) / 1000
	if integer_part >= 0:
		return (integer_part << SHIFT) + frac
	else:
		return (integer_part << SHIFT) - frac


# --- Arithmetic ---

static func add(a: int, b: int) -> int:
	return a + b


static func sub(a: int, b: int) -> int:
	return a - b


## Multiply two fixed-point values.
static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT


## Divide a by b.
static func div(a: int, b: int) -> int:
	assert(b != 0, "FP.div: division by zero")
	return (a << SHIFT) / b


static func mod(a: int, b: int) -> int:
	return a % b


static func neg(a: int) -> int:
	return -a


static func abs_fp(a: int) -> int:
	return a if a >= 0 else -a


static func max_fp(a: int, b: int) -> int:
	return a if a >= b else b


static func min_fp(a: int, b: int) -> int:
	return a if a <= b else b


static func clamp_fp(value: int, min_val: int, max_val: int) -> int:
	if value < min_val:
		return min_val
	if value > max_val:
		return max_val
	return value


## Linear interpolation: a + (b - a) * t, where t is fixed-point (0=a, ONE=b).
static func lerp_fp(a: int, b: int, t: int) -> int:
	return a + mul(b - a, t)


# --- Comparison ---

static func gt(a: int, b: int) -> bool:
	return a > b


static func lt(a: int, b: int) -> bool:
	return a < b


static func gte(a: int, b: int) -> bool:
	return a >= b


static func lte(a: int, b: int) -> bool:
	return a <= b


# --- Square Root (integer Newton's method) ---

static func sqrt_fp(a: int) -> int:
	assert(a >= 0, "FP.sqrt_fp: negative input")
	if a == 0:
		return 0
	if a == ONE:
		return ONE

	var val: int = a << SHIFT
	var guess: int = val >> 1 if val > ONE else ONE

	for i in 6:
		if guess == 0:
			return 0
		guess = (guess + val / guess) >> 1

	return guess
