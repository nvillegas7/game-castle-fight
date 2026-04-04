## Procedural sound with layered harmonics, ADSR envelopes, and filter sweeps.
extends Node

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
const POOL_SIZE: int = 16
const SR: float = 22050.0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func _get_player() -> AudioStreamPlayer:
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	return p


func play_place() -> void:
	_play_layered([
		{"freq": 440, "dur": 0.08, "vol": 0.25, "type": "sine"},
		{"freq": 880, "dur": 0.05, "vol": 0.1, "type": "sine"},
	])


func play_hit() -> void:
	_play_layered([
		{"freq": 120, "dur": 0.07, "vol": 0.3, "type": "sine", "attack": 0.005},
		{"freq": 135, "dur": 0.06, "vol": 0.15, "type": "sine"},  # Detuned 2nd osc
		{"freq": 0, "dur": 0.03, "vol": 0.25, "type": "noise"},   # Noise burst
	])


func play_shoot() -> void:
	_play_layered([
		{"freq": 800, "dur": 0.04, "vol": 0.12, "type": "sine", "slide": 400},
		{"freq": 1600, "dur": 0.03, "vol": 0.06, "type": "sine"},
	])


func play_death() -> void:
	_play_layered([
		{"freq": 300, "dur": 0.15, "vol": 0.2, "type": "sine", "slide": -200},
		{"freq": 150, "dur": 0.12, "vol": 0.1, "type": "sine", "slide": -100},
		{"freq": 0, "dur": 0.04, "vol": 0.15, "type": "noise"},
	])


func play_heal() -> void:
	_play_layered([
		{"freq": 660, "dur": 0.1, "vol": 0.15, "type": "sine", "slide": 200},
		{"freq": 990, "dur": 0.08, "vol": 0.08, "type": "sine", "slide": 150},
	])


func play_castle_hit() -> void:
	_play_layered([
		{"freq": 40, "dur": 0.2, "vol": 0.3, "type": "sine"},    # Sub bass
		{"freq": 80, "dur": 0.18, "vol": 0.35, "type": "sine"},   # Main boom
		{"freq": 0, "dur": 0.06, "vol": 0.3, "type": "noise", "attack": 0.002},  # Impact
	])


func play_gold() -> void:
	_play_layered([
		{"freq": 1200, "dur": 0.05, "vol": 0.12, "type": "sine"},
		{"freq": 1500, "dur": 0.05, "vol": 0.1, "type": "sine", "delay": 0.06},
	])


func play_victory() -> void:
	_play_layered([
		{"freq": 523, "dur": 0.15, "vol": 0.25, "type": "sine"},
		{"freq": 659, "dur": 0.15, "vol": 0.25, "type": "sine", "delay": 0.15},
		{"freq": 784, "dur": 0.3, "vol": 0.3, "type": "sine", "delay": 0.3},
		{"freq": 1046, "dur": 0.2, "vol": 0.15, "type": "sine", "delay": 0.3},
	])


func play_defeat() -> void:
	_play_layered([
		{"freq": 300, "dur": 0.25, "vol": 0.25, "type": "sine", "slide": -100},
		{"freq": 200, "dur": 0.35, "vol": 0.2, "type": "sine", "slide": -60, "delay": 0.25},
	])


func play_skill() -> void:
	_play_layered([
		{"freq": 900, "dur": 0.06, "vol": 0.12, "type": "sine"},
		{"freq": 1100, "dur": 0.06, "vol": 0.1, "type": "sine", "delay": 0.04},
		{"freq": 1400, "dur": 0.04, "vol": 0.06, "type": "sine", "delay": 0.08},
	])


func _play_layered(layers: Array) -> void:
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
	player.volume_db = 0
	player.play()

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

			# Current frequency with slide
			var cur_freq: float = freq + slide * (lt / dur)

			# ADSR envelope
			var env: float
			if lt < attack:
				env = lt / attack  # Attack
			else:
				var decay_t: float = (lt - attack) / (dur - attack)
				env = 1.0 - decay_t * decay_t  # Quadratic decay

			# Oscillator
			var osc: float
			var stype: String = layer.get("type", "sine")
			if stype == "noise":
				osc = randf_range(-1.0, 1.0)
			elif stype == "square":
				osc = 1.0 if fmod(phases[li], 1.0) < 0.5 else -1.0
			else:
				osc = sin(phases[li] * TAU)

			sample += osc * env * vol

			if cur_freq > 0:
				phases[li] += cur_freq / SR

		sample = clampf(sample, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))
