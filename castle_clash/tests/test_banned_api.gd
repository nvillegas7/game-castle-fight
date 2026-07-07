## Determinism lint for the fixed-point simulation (see
## tasks/design-verification-workflow.md L0). Same-binary re-run tests cannot
## catch nondeterminism that only diverges across BUILDS/platforms (global RNG,
## wall clock, node access, transcendental floats). This scans the sim source
## and hard-fails on those, fencing the lockstep core before a leak ships.
##
## Run: godot --headless --path castle_clash -s tests/test_banned_api.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

# Files that make up the deterministic core. All sim math flows through these.
const CORE_FILES: Array = [
	"res://core/simulation.gd",
	"res://core/command.gd",
	"res://core/command_buffer.gd",
	"res://core/deterministic_rng.gd",
	"res://core/fixed_vec2.gd",
]

# Zero-tolerance patterns: each would diverge two peers running different builds
# (or the editor binary vs the export template) even on identical inputs.
const HARD_BANNED: Array = [
	# Engine RNG instead of DeterministicRNG
	["global RNG", "\\brand(f|i|fn)\\s*\\(|\\brand(f|i)_range\\b|\\brandomize\\b|RandomNumberGenerator"],
	# Wall clock / frame counters
	["wall clock", "\\bTime\\.|OS\\.get_ticks|OS\\.get_unix|OS\\.get_system_time|Engine\\.get_frames|Engine\\.get_process_frames|Engine\\.get_physics_frames"],
	# Scene-tree / node access — the sim must be node-free
	["node access", "\\bget_tree\\s*\\(|\\bget_node\\b|\\bget_viewport\\b|\\bget_instance_id\\b|\\binstance_from_id\\b"],
	# Transcendental / non-exact float math (cross-platform rounding drift).
	# FP.sqrt_fp etc. are fixed-point method calls and do NOT match (word boundary).
	["transcendental float", "\\bsin\\s*\\(|\\bcos\\s*\\(|\\btan\\s*\\(|\\bsqrt\\s*\\(|\\bpow\\s*\\(|\\batan2?\\s*\\(|\\basin\\s*\\(|\\bacos\\s*\\(|\\blog\\s*\\(|\\bexp\\s*\\(|\\bfmod\\s*\\("],
]

# Benign single-op float literals (e.g. `int(cd * 0.85)`) are deterministic under
# IEEE-754 within a build. We ratchet their count in simulation.gd so they can't
# proliferate: raising this baseline must be a conscious, reviewed act.
const FLOAT_LITERAL_BASELINE: int = 1


func _init() -> void:
	print("\n=== BANNED-API DETERMINISM LINT ===\n")
	_check_hard_banned()
	_check_float_literal_ratchet()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(name: String) -> void:
	_pass += 1
	print("  PASS: %s" % name)


func _bad(name: String, detail: String) -> void:
	_fail += 1
	print("  FAIL: %s — %s" % [name, detail])


# Remove `#` comments and double-quoted strings so tokens inside them (e.g. the
# armor-formula comment) don't false-positive.
func _strip(line: String) -> String:
	var hash_idx := line.find("#")
	if hash_idx >= 0:
		line = line.substr(0, hash_idx)
	var rx := RegEx.new()
	rx.compile('"[^"]*"')
	return rx.sub(line, '""', true)


func _read_lines(path: String) -> PackedStringArray:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var text := f.get_as_text()
	f.close()
	return text.split("\n")


func _check_hard_banned() -> void:
	print("[Hard-banned nondeterministic APIs (expect zero)]")
	var total_hits: int = 0
	for entry in HARD_BANNED:
		var label: String = entry[0]
		var rx := RegEx.new()
		rx.compile(entry[1])
		var hits: Array = []
		for path in CORE_FILES:
			var lines := _read_lines(path)
			for i in lines.size():
				if rx.search(_strip(lines[i])):
					hits.append("%s:%d  %s" % [path, i + 1, lines[i].strip_edges()])
		if hits.is_empty():
			_ok("no %s in the sim core" % label)
		else:
			total_hits += hits.size()
			_bad("%d %s occurrence(s) in sim core" % [hits.size(), label],
				"determinism leak — sim must be node/clock/RNG/transcendental-free")
			for h in hits:
				print("      %s" % h)
	if total_hits == 0:
		print("  (core is clean)")


func _check_float_literal_ratchet() -> void:
	print("[Float-literal ratchet in simulation.gd]")
	var rx := RegEx.new()
	# Decimal literal not part of an identifier/member (e.g. 0.85, 1.5) —
	# excludes range operators (..) and integer.method chains.
	rx.compile("(?<![\\w.])\\d+\\.\\d+")
	var lines := _read_lines("res://core/simulation.gd")
	var sites: Array = []
	for i in lines.size():
		var stripped := _strip(lines[i])
		if rx.search(stripped):
			sites.append("core/simulation.gd:%d  %s" % [i + 1, lines[i].strip_edges()])
	var count := sites.size()
	if count <= FLOAT_LITERAL_BASELINE:
		_ok("%d float literals <= baseline %d (reviewed-benign single ops)" % [count, FLOAT_LITERAL_BASELINE])
		for s in sites:
			print("      (allowed) %s" % s)
	else:
		_bad("%d float literals > baseline %d — new float(s) added" % [count, FLOAT_LITERAL_BASELINE],
			"convert to fixed-point, or consciously raise FLOAT_LITERAL_BASELINE")
		for s in sites:
			print("      %s" % s)
