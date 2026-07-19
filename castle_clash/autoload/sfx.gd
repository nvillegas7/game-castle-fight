## Kingdom Rush-inspired procedural SFX with metallic impacts, whooshes, and rich tones.
## Includes per-type cooldowns, global rate limiting, and intensity volume scaling.
extends Node

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
const POOL_SIZE: int = 16
const SR: float = 22050.0

# Web export: AudioStreamGenerator is not supported (sample-based audio system).
# Skip all procedural synthesis on web — rely on file-based .ogg sounds only.
var _is_web: bool = false

var _music_player: AudioStreamPlayer = null
var _music_playing: bool = false

# --- Throttle System ---

# Per-type cooldown tracking: sfx_name -> last_play_time (msec)
var _cooldowns: Dictionary = {}

# Minimum milliseconds between plays of the same SFX type
const COOLDOWN_MS := {
	"hit": 150,         # Max ~6.6/sec (down from 33+)
	"shoot": 150,       # Max ~6.6/sec
	"death": 100,       # Max 10/sec (important, less throttled)
	"heal": 200,        # Max 5/sec
	"castle_hit": 300,  # Max 3.3/sec (deep boom needs space)
	"skill": 200,       # Max 5/sec
	"place": 0,         # Player action — always play
	"gold": 0,          # Rare event — always play
	"wave": 0,          # Rare event — always play
	"victory": 0,       # Always play
	"defeat": 0,        # Always play
}

# Priority: HIGH bypasses global frame cap
enum Priority { HIGH, NORMAL }
const SFX_PRIORITY := {
	"hit": Priority.NORMAL,
	"shoot": Priority.NORMAL,
	"death": Priority.NORMAL,
	"heal": Priority.NORMAL,
	"skill": Priority.NORMAL,
	"castle_hit": Priority.HIGH,
	"place": Priority.HIGH,
	"gold": Priority.HIGH,
	"wave": Priority.HIGH,
	"victory": Priority.HIGH,
	"defeat": Priority.HIGH,
}

# Global frame cap
const MAX_SFX_PER_FRAME: int = 4
var _sfx_this_frame: int = 0

# Intensity volume scaling
var _recent_combat_plays: int = 0
var _combat_volume_scale: float = 1.0
var _combat_decay_timer: float = 0.0
const COMBAT_SFX_NAMES := ["hit", "shoot", "death", "heal"]

# Role -> subfolder name for per-role SFX
const ROLE_SFX_FOLDER := { 0: "melee", 1: "ranged", 2: "caster", 3: "flying", 4: "siege" }

# T-030: Ambient battlefield sound
var _ambient_player: AudioStreamPlayer = null
var _ambient_active: bool = false
var _ambient_unit_count: int = 0
const AMBIENT_BASE_DB: float = -24.0
const AMBIENT_MAX_DB: float = -12.0


func _process(_delta: float) -> void:
	_sfx_this_frame = 0
	_combat_decay_timer += _delta
	if _combat_decay_timer >= 0.5:
		_combat_decay_timer = 0.0
		# 0-3 plays in window: full volume. 4-8: gradually quieter. 8+: floor at 0.25
		_combat_volume_scale = clampf(1.0 - (_recent_combat_plays - 3) * 0.08, 0.25, 1.0)
		_recent_combat_plays = 0
	# T-030: Scale ambient volume with unit count
	if _ambient_player and _ambient_active:
		var target_db: float = lerpf(AMBIENT_BASE_DB, AMBIENT_MAX_DB, clampf(float(_ambient_unit_count) / 30.0, 0.0, 1.0))
		_ambient_player.volume_db = lerpf(_ambient_player.volume_db, target_db, 0.05)


## Returns true if this SFX type is allowed to play right now.
func _can_play(sfx_name: String) -> bool:
	# Per-type cooldown check
	var now: int = Time.get_ticks_msec()
	var cd: int = COOLDOWN_MS.get(sfx_name, 0)
	if cd > 0:
		var last: int = _cooldowns.get(sfx_name, 0)
		if now - last < cd:
			return false

	# Global frame cap (high-priority sounds bypass)
	var priority: int = SFX_PRIORITY.get(sfx_name, Priority.NORMAL)
	if priority == Priority.NORMAL:
		if _sfx_this_frame >= MAX_SFX_PER_FRAME:
			return false

	# Track timing and counts
	_cooldowns[sfx_name] = now
	_sfx_this_frame += 1
	if sfx_name in COMBAT_SFX_NAMES:
		_recent_combat_plays += 1
	return true


# --- File-Based SFX System ---

# SFX file variants: sfx_name -> Array[AudioStream]
var _sfx_variants: Dictionary = {}
var _last_variant: Dictionary = {}  # sfx_name -> last_index (no-repeat)

# UI sound pool (separate from combat, always responsive)
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_next: int = 0
const UI_POOL_SIZE: int = 4
var _ui_sfx: Dictionary = {}  # name -> AudioStream


func _ready() -> void:
	_is_web = OS.has_feature("web")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	# Legacy procedural music player (fallback)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -10
	add_child(_music_player)
	# File-based music system
	_init_music()
	# File-based SFX + UI
	_load_sfx_files()
	_init_ui_pool()
	_load_ui_sfx()
	# T-030: Ambient battlefield sound player
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "SFX"
	_ambient_player.volume_db = AMBIENT_BASE_DB
	add_child(_ambient_player)
	# T-094: Castle Wrath audio cues — connected at autoload level so one-shot
	# SFX fires regardless of arena lifecycle.
	EventBus.castle_wrath_ready.connect(_on_castle_wrath_ready)
	EventBus.castle_wrath_activated.connect(_on_castle_wrath_activated)


func _on_castle_wrath_ready(_team: int, _castle_id: int) -> void:
	play_castle_wrath_ready()


func _on_castle_wrath_activated(_team: int, _target_ids: Array, _center_x: float, _center_y: float, _range_px: float) -> void:
	play_castle_wrath()


func _load_sfx_files() -> void:
	var categories := {
		"hit": "res://assets/audio/sfx/combat/hit_%02d.ogg",
		"shoot": "res://assets/audio/sfx/combat/shoot_%02d.ogg",
		"death": "res://assets/audio/sfx/combat/death_%02d.ogg",
		"heal": "res://assets/audio/sfx/combat/heal_%02d.ogg",
		"castle_hit": "res://assets/audio/sfx/combat/castle_hit_%02d.ogg",
		"place": "res://assets/audio/sfx/building/place_%02d.ogg",
		"gold": "res://assets/audio/sfx/building/gold_%02d.ogg",
		"sell": "res://assets/audio/sfx/building/sell_%02d.ogg",
		"destroy": "res://assets/audio/sfx/building/destroy_%02d.ogg",
		"wave": "res://assets/audio/sfx/announce/wave_%02d.ogg",
		"skill": "res://assets/audio/sfx/announce/skill_%02d.ogg",
	}
	for sfx_name in categories:
		var pattern: String = categories[sfx_name]
		var variants: Array[AudioStream] = []
		for i in range(1, 16):  # Try up to 15 variants per type
			var path: String = pattern % i
			if ResourceLoader.exists(path):
				variants.append(load(path))
			else:
				break
		if not variants.is_empty():
			_sfx_variants[sfx_name] = variants
	# Load per-role combat SFX variants (e.g. combat/melee/hit_01.ogg)
	for role_id in ROLE_SFX_FOLDER:
		var folder: String = ROLE_SFX_FOLDER[role_id]
		for sfx_base in ["hit", "shoot"]:
			var role_key := "%s_role_%d" % [sfx_base, role_id]
			var role_pattern := "res://assets/audio/sfx/combat/%s/%s_%%02d.ogg" % [folder, sfx_base]
			var role_variants: Array[AudioStream] = []
			for i in range(1, 16):
				var path: String = role_pattern % i
				if ResourceLoader.exists(path):
					role_variants.append(load(path))
				else:
					break
			if not role_variants.is_empty():
				_sfx_variants[role_key] = role_variants


func _init_ui_pool() -> void:
	for i in UI_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_players.append(p)


func _load_ui_sfx() -> void:
	for sfx_name in ["button_click", "tab_switch", "card_select", "card_hover", "card_denied"]:
		var path := "res://assets/audio/sfx/ui/%s.ogg" % sfx_name
		if ResourceLoader.exists(path):
			_ui_sfx[sfx_name] = load(path)


## Play a file-based SFX with random variant + pitch. Returns false if no file (use procedural).
func _play_sfx_file(sfx_name: String, is_combat: bool = false) -> bool:
	var variants: Array = _sfx_variants.get(sfx_name, [])
	if variants.is_empty():
		return false
	# Pick variant (no repeat)
	var idx: int
	if variants.size() <= 1:
		idx = 0
	else:
		var last: int = _last_variant.get(sfx_name, -1)
		idx = randi() % variants.size()
		while idx == last:
			idx = randi() % variants.size()
	_last_variant[sfx_name] = idx
	var stream: AudioStream = variants[idx]
	var player := _get_player()
	player.stream = stream
	player.volume_db = linear_to_db(_combat_volume_scale) if is_combat else 0
	player.pitch_scale = randf_range(0.92, 1.08)
	player.play()
	return true


## Play a UI sound (separate pool, no throttle, always responsive).
func play_ui(sfx_name: String) -> void:
	var stream: AudioStream = _ui_sfx.get(sfx_name)
	if stream == null:
		return
	var p := _ui_players[_ui_next]
	_ui_next = (_ui_next + 1) % UI_POOL_SIZE
	p.stream = stream
	p.volume_db = -3
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()


func _get_player() -> AudioStreamPlayer:
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	return p


# --- SFX Definitions (Kingdom Rush Style) ---

## Building placement: wooden thud + construction hammer
func play_place() -> void:
	if not _can_play("place"):
		return
	if _play_sfx_file("place"):
		return
	_play_layered([
		{"freq": 180, "dur": 0.12, "vol": 0.35, "type": "sine", "attack": 0.002},
		{"freq": 0, "dur": 0.04, "vol": 0.25, "type": "noise", "attack": 0.001},
		{"freq": 350, "dur": 0.06, "vol": 0.15, "type": "square", "attack": 0.002},
		{"freq": 520, "dur": 0.04, "vol": 0.08, "type": "sine", "delay": 0.08},
	])


## Melee attack: metallic sword clang with ring. Pass role for per-unit-type sounds.
func play_hit(role: int = -1) -> void:
	if not _can_play("hit"):
		return
	if role >= 0:
		var role_key := "hit_role_%d" % role
		if _play_sfx_file(role_key, true):
			return
	if _play_sfx_file("hit", true):
		return
	_play_layered([
		{"freq": 0, "dur": 0.025, "vol": 0.4, "type": "noise", "attack": 0.001},
		{"freq": 2200, "dur": 0.12, "vol": 0.18, "type": "sine", "attack": 0.002},
		{"freq": 3100, "dur": 0.10, "vol": 0.12, "type": "sine", "attack": 0.002},
		{"freq": 4400, "dur": 0.06, "vol": 0.06, "type": "sine", "attack": 0.001},
		{"freq": 100, "dur": 0.05, "vol": 0.2, "type": "sine", "attack": 0.002},
		{"freq": 1800, "dur": 0.08, "vol": 0.06, "type": "square", "attack": 0.001},
	], true)


## Ranged attack: arrow whoosh + thud. Pass role for per-unit-type sounds.
func play_shoot(role: int = -1) -> void:
	if not _can_play("shoot"):
		return
	if role >= 0:
		var role_key := "shoot_role_%d" % role
		if _play_sfx_file(role_key, true):
			return
	if _play_sfx_file("shoot", true):
		return
	_play_layered([
		{"freq": 0, "dur": 0.08, "vol": 0.15, "type": "noise", "attack": 0.005},
		{"freq": 600, "dur": 0.06, "vol": 0.12, "type": "saw", "slide": -300, "attack": 0.002},
		{"freq": 1200, "dur": 0.04, "vol": 0.06, "type": "sine", "slide": -500},
		{"freq": 150, "dur": 0.03, "vol": 0.1, "type": "sine", "delay": 0.06, "attack": 0.001},
	], true)


## Unit death: dramatic descending tone + impact. Pass role for future per-type sounds.
func play_death(role: int = -1) -> void:
	if not _can_play("death"):
		return
	if role >= 0:
		var role_key := "death_role_%d" % role
		if _play_sfx_file(role_key, true):
			return
	if _play_sfx_file("death", true):
		return
	_play_layered([
		{"freq": 400, "dur": 0.2, "vol": 0.2, "type": "saw", "slide": -300, "attack": 0.01},
		{"freq": 200, "dur": 0.25, "vol": 0.15, "type": "sine", "slide": -150},
		{"freq": 0, "dur": 0.05, "vol": 0.2, "type": "noise", "attack": 0.002},
		{"freq": 80, "dur": 0.15, "vol": 0.15, "type": "sine", "delay": 0.05},
	], true)


## Heal: magical shimmer with rising harmonics
func play_heal() -> void:
	if not _can_play("heal"):
		return
	if _play_sfx_file("heal", true):
		return
	_play_layered([
		{"freq": 660, "dur": 0.15, "vol": 0.12, "type": "sine", "slide": 300},
		{"freq": 990, "dur": 0.12, "vol": 0.08, "type": "sine", "slide": 250},
		{"freq": 1320, "dur": 0.10, "vol": 0.05, "type": "sine", "slide": 200},
		{"freq": 2600, "dur": 0.06, "vol": 0.04, "type": "sine", "delay": 0.04},
		{"freq": 3200, "dur": 0.04, "vol": 0.03, "type": "sine", "delay": 0.08},
	], true)


## Castle hit: massive boom with sub-bass rumble
func play_castle_hit() -> void:
	if not _can_play("castle_hit"):
		return
	if _play_sfx_file("castle_hit"):
		return
	_play_layered([
		{"freq": 35, "dur": 0.35, "vol": 0.4, "type": "sine", "attack": 0.005},
		{"freq": 70, "dur": 0.25, "vol": 0.3, "type": "sine"},
		{"freq": 0, "dur": 0.06, "vol": 0.45, "type": "noise", "attack": 0.001},
		{"freq": 140, "dur": 0.12, "vol": 0.15, "type": "square", "attack": 0.003},
		# Debris rattle
		{"freq": 0, "dur": 0.15, "vol": 0.08, "type": "noise", "delay": 0.08},
	])


## Building destroyed by enemy: crumble/collapse sound
func play_destroy() -> void:
	if not _can_play("destroy"):
		return
	if _play_sfx_file("destroy"):
		return
	# Procedural fallback: low rumble + crumble
	_play_layered([
		{"freq": 80, "dur": 0.4, "vol": 0.15, "type": "noise"},
		{"freq": 120, "dur": 0.3, "vol": 0.10, "type": "sine", "slide": -60},
		{"freq": 200, "dur": 0.15, "vol": 0.08, "type": "noise", "delay": 0.1},
	])


## Gold collected: bright metallic coin clink
func play_gold() -> void:
	if not _can_play("gold"):
		return
	if _play_sfx_file("gold"):
		return
	_play_layered([
		{"freq": 2400, "dur": 0.08, "vol": 0.12, "type": "sine", "attack": 0.001},
		{"freq": 3600, "dur": 0.06, "vol": 0.06, "type": "sine", "attack": 0.001},
		{"freq": 3000, "dur": 0.06, "vol": 0.08, "type": "sine", "delay": 0.06, "attack": 0.001},
		{"freq": 4500, "dur": 0.04, "vol": 0.04, "type": "sine", "delay": 0.06, "attack": 0.001},
	])


## Building sold/destroyed: short demolish + coin refund
func play_sell() -> void:
	if not _can_play("gold"):
		return
	if _play_sfx_file("sell"):
		return
	# Fallback: quick descending thud + coin
	_play_layered([
		{"freq": 300, "dur": 0.08, "vol": 0.2, "type": "sine", "slide": -200, "attack": 0.002},
		{"freq": 0, "dur": 0.03, "vol": 0.15, "type": "noise", "attack": 0.001},
		{"freq": 2400, "dur": 0.06, "vol": 0.08, "type": "sine", "delay": 0.06, "attack": 0.001},
		{"freq": 3000, "dur": 0.05, "vol": 0.05, "type": "sine", "delay": 0.08, "attack": 0.001},
	])


## Victory: brass-like triumphant fanfare (C major)
func play_victory() -> void:
	if not _can_play("victory"):
		return
	_play_layered([
		{"freq": 523, "dur": 0.2, "vol": 0.25, "type": "saw"},
		{"freq": 523, "dur": 0.2, "vol": 0.1, "type": "square"},
		{"freq": 659, "dur": 0.2, "vol": 0.25, "type": "saw", "delay": 0.18},
		{"freq": 784, "dur": 0.35, "vol": 0.3, "type": "saw", "delay": 0.36},
		{"freq": 784, "dur": 0.35, "vol": 0.12, "type": "square", "delay": 0.36},
		{"freq": 1046, "dur": 0.4, "vol": 0.2, "type": "saw", "delay": 0.55},
	])


## Defeat: somber descending brass
func play_defeat() -> void:
	if not _can_play("defeat"):
		return
	_play_layered([
		{"freq": 350, "dur": 0.35, "vol": 0.25, "type": "saw", "slide": -80},
		{"freq": 250, "dur": 0.4, "vol": 0.2, "type": "saw", "slide": -60, "delay": 0.3},
		{"freq": 175, "dur": 0.5, "vol": 0.2, "type": "sine", "slide": -40, "delay": 0.6},
	])


## Skill activated: per-skill differentiated sounds (T-029)
func play_skill(skill_id: StringName = &"") -> void:
	if not _can_play("skill"):
		return
	# Try file-based first for generic skill sound
	if skill_id == &"" and _play_sfx_file("skill"):
		return
	# Per-skill procedural synthesis. (1D-4: devotion_aura/cleave arms deleted —
	# the sim never procs them; re-add together with a sim-side skill_proc.)
	match skill_id:
		&"piercing_shot":
			# Sharp whistle
			_play_layered([
				{"freq": 1800, "dur": 0.1, "vol": 0.15, "type": "sine", "slide": 600, "attack": 0.002},
				{"freq": 0, "dur": 0.02, "vol": 0.1, "type": "noise", "attack": 0.001},
			])
		&"mana_shield":
			# Glass/crystal barrier
			_play_layered([
				{"freq": 2200, "dur": 0.08, "vol": 0.1, "type": "sine", "attack": 0.002},
				{"freq": 3300, "dur": 0.06, "vol": 0.06, "type": "sine", "delay": 0.02},
				{"freq": 4400, "dur": 0.04, "vol": 0.04, "type": "sine", "delay": 0.04},
				{"freq": 1100, "dur": 0.15, "vol": 0.05, "type": "triangle", "attack": 0.01},
			])
		&"critical_strike":
			# Heavy impact thud
			_play_layered([
				{"freq": 60, "dur": 0.15, "vol": 0.35, "type": "sine", "attack": 0.002},
				{"freq": 0, "dur": 0.04, "vol": 0.3, "type": "noise", "attack": 0.001},
				{"freq": 120, "dur": 0.08, "vol": 0.15, "type": "square", "attack": 0.002},
			])
		&"evasion":
			# Quick whoosh
			_play_layered([
				{"freq": 0, "dur": 0.1, "vol": 0.12, "type": "noise", "attack": 0.005},
				{"freq": 400, "dur": 0.08, "vol": 0.08, "type": "sine", "slide": -300, "attack": 0.002},
			])
		&"battle_cry":
			# Horn/war cry
			_play_layered([
				{"freq": 165, "dur": 0.3, "vol": 0.2, "type": "saw", "attack": 0.05},
				{"freq": 330, "dur": 0.25, "vol": 0.1, "type": "saw", "attack": 0.06},
				{"freq": 247, "dur": 0.2, "vol": 0.08, "type": "sine", "attack": 0.04, "delay": 0.05},
			])
		&"burning_ground":
			# Crackling fire
			_play_layered([
				{"freq": 0, "dur": 0.25, "vol": 0.12, "type": "noise", "attack": 0.01},
				{"freq": 150, "dur": 0.2, "vol": 0.06, "type": "noise", "delay": 0.05},
				{"freq": 80, "dur": 0.15, "vol": 0.08, "type": "sine", "attack": 0.02},
			])
		&"enrage":
			# Aggressive growl
			_play_layered([
				{"freq": 100, "dur": 0.2, "vol": 0.2, "type": "saw", "slide": -40, "attack": 0.01},
				{"freq": 0, "dur": 0.08, "vol": 0.15, "type": "noise", "attack": 0.005},
				{"freq": 200, "dur": 0.1, "vol": 0.1, "type": "square", "delay": 0.05},
			])
		&"toughness":
			# Armor clank
			_play_layered([
				{"freq": 1800, "dur": 0.06, "vol": 0.12, "type": "sine", "attack": 0.001},
				{"freq": 100, "dur": 0.1, "vol": 0.15, "type": "sine", "attack": 0.002},
				{"freq": 2500, "dur": 0.04, "vol": 0.06, "type": "sine", "delay": 0.03},
			])
		&"fireball":
			# T-084 Mage fireball: fiery whoosh + bassy impact + splash crackle
			_play_layered([
				{"freq": 0, "dur": 0.12, "vol": 0.2, "type": "noise", "attack": 0.01},
				{"freq": 180, "dur": 0.15, "vol": 0.25, "type": "saw", "slide": -120, "attack": 0.002},
				{"freq": 70, "dur": 0.18, "vol": 0.2, "type": "sine", "attack": 0.005, "delay": 0.04},
				{"freq": 0, "dur": 0.08, "vol": 0.1, "type": "noise", "delay": 0.1},
			])
		&"arcane_shield":
			# T-084 Mage arcane shield absorb: ethereal purple chime, softer than mana_shield
			_play_layered([
				{"freq": 1760, "dur": 0.1, "vol": 0.08, "type": "sine", "attack": 0.008},
				{"freq": 2640, "dur": 0.08, "vol": 0.05, "type": "sine", "delay": 0.03},
				{"freq": 880, "dur": 0.18, "vol": 0.06, "type": "triangle", "attack": 0.02},
			])
		&"arcane_shield_break":
			# T-084 Mage arcane shield depletion: sharp descending crystal shatter
			_play_layered([
				{"freq": 3200, "dur": 0.08, "vol": 0.15, "type": "sine", "slide": -1400, "attack": 0.001},
				{"freq": 2000, "dur": 0.06, "vol": 0.1, "type": "sine", "slide": -800, "delay": 0.02},
				{"freq": 0, "dur": 0.04, "vol": 0.08, "type": "noise", "attack": 0.001},
			])
		_:
			# Generic magic sweep fallback
			if _play_sfx_file("skill"):
				return
			_play_layered([
				{"freq": 600, "dur": 0.08, "vol": 0.15, "type": "sine", "slide": 400},
				{"freq": 900, "dur": 0.08, "vol": 0.1, "type": "sine", "slide": 300, "delay": 0.03},
				{"freq": 1400, "dur": 0.06, "vol": 0.06, "type": "sine", "delay": 0.06},
				{"freq": 0, "dur": 0.03, "vol": 0.08, "type": "noise", "delay": 0.02},
			])


## T-090 Castle Wrath readiness ping: subtle ascending 3-note chime, "ready to fire"
func play_castle_wrath_ready() -> void:
	if not _can_play("skill"):
		return
	_play_layered([
		{"freq": 523, "dur": 0.12, "vol": 0.15, "type": "sine", "attack": 0.01},
		{"freq": 659, "dur": 0.12, "vol": 0.13, "type": "sine", "attack": 0.01, "delay": 0.1},
		{"freq": 988, "dur": 0.25, "vol": 0.18, "type": "sine", "attack": 0.02, "delay": 0.2},
		{"freq": 1976, "dur": 0.15, "vol": 0.05, "type": "sine", "delay": 0.2},
	])


## T-090 Castle Wrath activation: massive panic-button shockwave — horn + bass slam + magical crackle
func play_castle_wrath() -> void:
	# Bypass global frame cap (critical feedback) — reuse castle_hit slot for HP priority
	if not _can_play("castle_hit"):
		return
	_play_layered([
		# Deep bass detonation
		{"freq": 45, "dur": 0.45, "vol": 0.4, "type": "sine", "slide": -20, "attack": 0.005},
		{"freq": 90, "dur": 0.3, "vol": 0.25, "type": "saw", "slide": -50, "attack": 0.002},
		# Shockwave noise burst
		{"freq": 0, "dur": 0.25, "vol": 0.35, "type": "noise", "attack": 0.001},
		# Horn call layered on top
		{"freq": 220, "dur": 0.4, "vol": 0.18, "type": "saw", "attack": 0.04, "delay": 0.08},
		{"freq": 330, "dur": 0.35, "vol": 0.1, "type": "saw", "attack": 0.05, "delay": 0.1},
		# Magical sweep tail
		{"freq": 1760, "dur": 0.2, "vol": 0.08, "type": "sine", "slide": -600, "delay": 0.15},
		{"freq": 2640, "dur": 0.15, "vol": 0.06, "type": "sine", "slide": -800, "delay": 0.25},
	])


## Wave announcement: war horn blast
func play_wave() -> void:
	if not _can_play("wave"):
		return
	if _play_sfx_file("wave"):
		return
	_play_layered([
		{"freq": 110, "dur": 0.5, "vol": 0.2, "type": "saw", "attack": 0.1},
		{"freq": 220, "dur": 0.45, "vol": 0.12, "type": "saw", "attack": 0.12},
		{"freq": 165, "dur": 0.35, "vol": 0.08, "type": "sine", "attack": 0.1},
	])


# --- T-030: Ambient Battlefield Sound ---

## Start ambient battle layer (wind + distant crowd). Call during match start.
func start_ambient() -> void:
	if _ambient_active:
		return
	_ambient_active = true
	_ambient_unit_count = 0
	_generate_ambient_loop()


## Stop ambient sound (call on match end).
func stop_ambient(fade_out: float = 0.5) -> void:
	_ambient_active = false
	_ambient_unit_count = 0
	if _ambient_player and _ambient_player.playing:
		var tw := _ambient_player.create_tween()
		tw.tween_property(_ambient_player, "volume_db", -40.0, fade_out)
		tw.tween_callback(_ambient_player.stop)


## Update unit count for volume scaling. Call each tick from game_arena.
func update_ambient_intensity(unit_count: int) -> void:
	_ambient_unit_count = unit_count


func _generate_ambient_loop() -> void:
	if not _ambient_active:
		return
	if _is_web:
		return  # AudioStreamGenerator not supported on web export
	# Procedural ambient: wind + subtle crowd murmur (8 second loop)
	var dur: float = 8.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SR
	stream.buffer_length = dur + 0.1

	_ambient_player.stream = stream
	_ambient_player.play()
	if not _ambient_player.finished.is_connected(_on_ambient_finished):
		_ambient_player.finished.connect(_on_ambient_finished)

	await get_tree().process_frame

	var playback: AudioStreamGeneratorPlayback = _ambient_player.get_stream_playback()
	if playback == null:
		return

	var total_samples: int = int(dur * SR)
	var phase_wind: float = 0.0

	for i in total_samples:
		var t: float = float(i) / SR
		# Wind: filtered noise with slow modulation
		var wind: float = randf_range(-1.0, 1.0) * 0.15
		wind *= 0.5 + 0.5 * sin(t * 0.4 * TAU)  # Slow wind gusts
		# Distant crowd murmur: very low filtered noise
		var crowd: float = randf_range(-1.0, 1.0) * 0.05
		crowd *= 0.4 + 0.6 * sin(t * 0.15 * TAU)  # Slow swell
		# Low drone (adds weight)
		phase_wind += 55.0 / SR
		var drone: float = sin(phase_wind * TAU) * 0.03

		var sample: float = clampf(wind + crowd + drone, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))


func _on_ambient_finished() -> void:
	if _ambient_active:
		_generate_ambient_loop()


# --- Layered Synthesis Engine ---

func _play_layered(layers: Array, is_combat: bool = false) -> void:
	if _is_web:
		return  # AudioStreamGenerator not supported on web export
	var max_dur: float = 0.0
	for layer in layers:
		var d: float = layer.get("delay", 0.0) + layer.get("dur", 0.1)
		if d > max_dur:
			max_dur = d

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SR
	stream.buffer_length = max_dur + 0.05

	var player := _get_player()
	player.stream = stream
	player.volume_db = linear_to_db(_combat_volume_scale) if is_combat else 0
	player.play()

	# Wait one frame for AudioStreamGenerator playback to initialize
	await get_tree().process_frame

	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback == null:
		return

	var total_samples: int = int(max_dur * SR)
	var phases: Array[float] = []
	for l in layers:
		phases.append(0.0)

	for i in total_samples:
		var t: float = float(i) / SR
		var sample: float = 0.0

		for li in layers.size():
			var layer: Dictionary = layers[li]
			var delay: float = layer.get("delay", 0.0)
			if t < delay:
				continue
			var lt: float = t - delay
			var dur: float = layer.get("dur", 0.1)
			if lt > dur:
				continue

			var vol: float = layer.get("vol", 0.2)
			var freq: float = layer.get("freq", 440.0)
			var slide: float = layer.get("slide", 0.0)
			var attack: float = layer.get("attack", 0.01)

			var cur_freq: float = freq + slide * (lt / dur)

			# ADSR envelope with exponential decay for natural sound
			var env: float
			if lt < attack:
				env = lt / attack
			else:
				var decay_pos: float = (lt - attack) / (dur - attack)
				env = exp(-decay_pos * 3.0)  # Exponential decay (more natural)

			# Oscillator
			var osc: float
			var stype: String = layer.get("type", "sine")
			if stype == "noise":
				osc = randf_range(-1.0, 1.0)
			elif stype == "square":
				var phase_mod: float = fmod(phases[li], 1.0)
				# Band-limited square (softer, less buzzy)
				osc = 1.0 if phase_mod < 0.5 else -1.0
				osc *= 0.7  # Reduce harshness
			elif stype == "saw":
				# Sawtooth wave (brass/string character)
				osc = 2.0 * fmod(phases[li], 1.0) - 1.0
				osc *= 0.6  # Reduce harshness
			elif stype == "triangle":
				var phase_mod: float = fmod(phases[li], 1.0)
				osc = 4.0 * absf(phase_mod - 0.5) - 1.0
			else:
				osc = sin(phases[li] * TAU)

			sample += osc * env * vol

			if cur_freq > 0:
				phases[li] += cur_freq / SR

		sample = clampf(sample, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))


# --- Music System (file-based with crossfade, procedural fallback) ---

var _music_tracks: Dictionary = {}  # track_name -> AudioStream
var _music_player_a: AudioStreamPlayer = null
var _music_player_b: AudioStreamPlayer = null
var _active_music_player: AudioStreamPlayer = null
var _current_track: String = ""
const CROSSFADE_DURATION: float = 1.5
const MUSIC_VOLUME_DB: float = -6.0


func _init_music() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = "Music"
	add_child(_music_player_a)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = "Music"
	add_child(_music_player_b)
	_active_music_player = _music_player_a

	# Load available music files
	for track_name in ["menu_theme", "battle_theme", "victory_fanfare", "defeat_fanfare",
			"loading_ambient", "bards_tale", "kings_feast", "market_day", "rejoicing"]:
		var path := "res://assets/audio/music/%s.ogg" % track_name
		if ResourceLoader.exists(path):
			_music_tracks[track_name] = load(path)


## Play a named music track with crossfade. Falls back to procedural if file missing.
func play_music(track_name: String, loop: bool = true) -> void:
	if track_name == _current_track and _active_music_player.playing:
		return

	var stream: AudioStream = _music_tracks.get(track_name)
	if stream == null:
		# Fallback: use procedural for battle, ignore others
		if track_name == "battle_theme":
			start_music()
		return

	_current_track = track_name
	_music_playing = true

	# Pick the inactive player for crossfade
	var incoming: AudioStreamPlayer
	var outgoing: AudioStreamPlayer = _active_music_player
	if _active_music_player == _music_player_a:
		incoming = _music_player_b
	else:
		incoming = _music_player_a

	# Configure looping
	if stream is AudioStreamOggVorbis:
		stream.loop = loop

	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()

	# Crossfade tween
	var tw := create_tween().set_parallel(true)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -40.0, CROSSFADE_DURATION)
	tw.tween_property(incoming, "volume_db", MUSIC_VOLUME_DB, CROSSFADE_DURATION)
	tw.set_parallel(false)
	tw.tween_callback(func(): if outgoing != incoming: outgoing.stop())

	_active_music_player = incoming


## Stop music with optional fade out duration.
func stop_music(fade_out: float = 0.5) -> void:
	_music_playing = false
	_current_track = ""
	var tw := create_tween()
	tw.tween_property(_active_music_player, "volume_db", -40.0, fade_out)
	tw.tween_callback(_active_music_player.stop)
	# Also stop the other player if playing
	var other: AudioStreamPlayer = _music_player_b if _active_music_player == _music_player_a else _music_player_a
	if other.playing:
		var tw2 := create_tween()
		tw2.tween_property(other, "volume_db", -40.0, fade_out)
		tw2.tween_callback(other.stop)


## Legacy start_music() — procedural fallback for battle theme.
func start_music() -> void:
	# Try file-based first
	if _music_tracks.has("battle_theme"):
		play_music("battle_theme")
		return
	# Procedural fallback
	if _music_playing:
		return
	_music_playing = true
	_current_track = "battle_theme"
	_generate_music_loop()


func _generate_music_loop() -> void:
	if _is_web:
		return  # AudioStreamGenerator not supported on web export
	var dur: float = 24.0  # 24 second loop
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SR
	stream.buffer_length = dur + 0.1

	_music_player.stream = stream
	_music_player.play()
	if not _music_player.finished.is_connected(_on_music_finished):
		_music_player.finished.connect(_on_music_finished)

	await get_tree().process_frame

	var playback: AudioStreamGeneratorPlayback = _music_player.get_stream_playback()
	if playback == null:
		return

	# Medieval ambient: D minor pentatonic with slow arpeggiation
	var notes := [146.8, 174.6, 196.0, 220.0, 261.6, 293.7, 261.6, 220.0]
	var note_dur: float = dur / notes.size()
	var total_samples: int = int(dur * SR)

	var phase_main: float = 0.0
	var phase_oct: float = 0.0
	var phase_fifth: float = 0.0

	for i in total_samples:
		var t: float = float(i) / SR
		var note_idx: int = int(t / note_dur) % notes.size()
		var note_t: float = fmod(t, note_dur)
		var freq: float = notes[note_idx]

		var env: float
		if note_t < 0.5:
			env = note_t / 0.5
		elif note_t > note_dur - 0.3:
			env = (note_dur - note_t) / 0.3
		else:
			env = 1.0

		var sample: float = sin(phase_main * TAU) * 0.5
		sample += sin(phase_oct * TAU) * 0.12
		sample += sin(phase_fifth * TAU) * 0.15
		sample *= 1.0 + sin(t * 2.5) * 0.08
		sample *= env * 0.1

		sample += sin(t * 73.4 * TAU) * 0.02  # D2 drone
		sample = clampf(sample, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))

		phase_main += freq / SR
		phase_oct += (freq * 2.0) / SR
		phase_fifth += (freq * 1.5) / SR


func _on_music_finished() -> void:
	if _music_playing:
		_generate_music_loop()
