## Deterministic pseudo-random number generator (xorshift128).
## Every client uses the same seed and calls in the same order
## to produce identical random sequences.
##
## Usage:
##   var rng := DeterministicRNG.new()
##   rng.seed_from(match_seed)
##   var bounded := rng.range_int(1, 6)           # 1 to 6 inclusive
##   var fp_val := rng.range_fp(FP.ZERO, FP.ONE)  # 0.0 to 1.0 fixed-point
class_name DeterministicRNG

var _s0: int
var _s1: int
var _s2: int
var _s3: int

const MASK32: int = 0xFFFFFFFF


func seed_from(seed_value: int) -> void:
	var s: int = seed_value & MASK32
	if s == 0:
		s = 1
	_s0 = _splitmix(s)
	_s1 = _splitmix(_s0)
	_s2 = _splitmix(_s1)
	_s3 = _splitmix(_s2)
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


func _splitmix(state: int) -> int:
	state = ((state ^ (state >> 16)) * 0x45d9f3b) & MASK32
	state = ((state ^ (state >> 16)) * 0x45d9f3b) & MASK32
	state = (state ^ (state >> 16)) & MASK32
	return state


## Generate the next raw 32-bit unsigned integer.
func next_raw() -> int:
	var t: int = _s3
	var s: int = _s0

	_s3 = _s2
	_s2 = _s1
	_s1 = s

	t = (t ^ ((t << 11) & MASK32)) & MASK32
	t = (t ^ ((t >> 8) & MASK32)) & MASK32
	_s0 = (t ^ s ^ ((s >> 19) & MASK32)) & MASK32

	return _s0


## Integer in range [min_val, max_val] inclusive.
func range_int(min_val: int, max_val: int) -> int:
	assert(max_val >= min_val, "RNG: max must be >= min")
	var span: int = max_val - min_val + 1
	return min_val + (next_raw() % span)


## Fixed-point value in range [min_fp, max_fp].
func range_fp(min_fp: int, max_fp: int) -> int:
	var span: int = max_fp - min_fp
	if span == 0:
		return min_fp
	var raw: int = next_raw()
	var scaled: int = (raw * span) >> 32
	return min_fp + scaled


## Get state for checksum/serialization.
func get_state() -> Array[int]:
	return [_s0, _s1, _s2, _s3]


## Restore state from serialized form.
func set_state(state: Array[int]) -> void:
	_s0 = state[0]
	_s1 = state[1]
	_s2 = state[2]
	_s3 = state[3]
