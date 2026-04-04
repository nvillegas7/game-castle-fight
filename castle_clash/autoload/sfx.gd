## Procedural sound effect system. Generates simple sounds without audio files.
## Uses AudioStreamGenerator to create beeps, impacts, and chimes programmatically.
extends Node

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
const POOL_SIZE: int = 12
const SAMPLE_RATE: float = 22050.0


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func _get_player() -> AudioStreamPlayer:
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	return p


## Short pitched beep -- used for UI clicks, placement
func play_place() -> void:
	_play_tone(440.0, 0.08, 0.3)


## Low thud -- unit attack hit
func play_hit() -> void:
	_play_tone(120.0, 0.06, 0.25, true)


## Higher pitch quick -- ranged attack
func play_shoot() -> void:
	_play_tone(800.0, 0.04, 0.15)


## Descending tone -- unit death
func play_death() -> void:
	_play_tone(300.0, 0.12, 0.2, false, -200.0)


## Rising chime -- heal
func play_heal() -> void:
	_play_tone(660.0, 0.1, 0.2, false, 200.0)


## Deep boom -- castle damage
func play_castle_hit() -> void:
	_play_tone(80.0, 0.15, 0.4, true)


## Gold sound -- income/sell
func play_gold() -> void:
	_play_tone(1200.0, 0.05, 0.15)
	# Quick second note
	await get_tree().create_timer(0.06).timeout
	_play_tone(1500.0, 0.05, 0.12)


## Victory fanfare
func play_victory() -> void:
	_play_tone(523.0, 0.15, 0.3)
	await get_tree().create_timer(0.15).timeout
	_play_tone(659.0, 0.15, 0.3)
	await get_tree().create_timer(0.15).timeout
	_play_tone(784.0, 0.25, 0.35)


## Defeat sound
func play_defeat() -> void:
	_play_tone(300.0, 0.2, 0.3, false, -100.0)
	await get_tree().create_timer(0.25).timeout
	_play_tone(200.0, 0.3, 0.25, false, -50.0)


## Skill proc sound -- quick sparkle
func play_skill() -> void:
	_play_tone(900.0, 0.06, 0.15)
	await get_tree().create_timer(0.04).timeout
	_play_tone(1100.0, 0.06, 0.12)


func _play_tone(freq: float, duration: float, volume: float, noise: bool = false, freq_slide: float = 0.0) -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = duration + 0.05

	var player := _get_player()
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.play()

	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback == null:
		return

	var samples: int = int(duration * SAMPLE_RATE)
	var phase: float = 0.0

	for i in samples:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = 1.0 - (t / duration)  # Linear decay
		env = env * env  # Quadratic decay for punchier sound

		var current_freq: float = freq + freq_slide * (t / duration)
		var sample: float

		if noise:
			# Mix tone with noise for impact sounds
			sample = sin(phase * TAU) * 0.6 + randf_range(-0.4, 0.4)
		else:
			sample = sin(phase * TAU)

		sample *= env
		playback.push_frame(Vector2(sample, sample))
		phase += current_freq / SAMPLE_RATE
