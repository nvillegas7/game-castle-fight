## T-101 investigation: F3-togglable performance overlay.
## Produces quantitative evidence for the MP lag / "brick walking" bug without
## requiring video capture. Strictly observational — reads state, does not
## modify sim, lockstep, or any networking behavior.
extends CanvasLayer

const WINDOW_FRAMES: int = 60       # rolling window for max/avg dt
const WINDOW_TICKS_MSEC: int = 1000  # rolling window for measured TPS
const REMOTE_GAP_FLOOD_GUARD_MSEC: int = 100  # don't reset gap on spurious tick_advance without remote msg

var _label: Label = null
var _visible_flag: bool = false

var _frame_deltas_msec: Array = []            # last N frame deltas (int msec)
var _tick_times_msec: Array = []              # msec when we first observed each new sim tick
var _last_seen_tick: int = -1
var _last_interp: float = 0.0
var _last_interp_deltas: Array = []           # per-frame |interp_now - interp_last| (int‰, so 0-1000)

var _last_remote_commands_count: int = 0
var _last_remote_event_msec: int = 0


func _ready() -> void:
	layer = 100  # render above everything
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 3)
	_label.visible = _visible_flag
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_visible_flag = not _visible_flag
		_label.visible = _visible_flag
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _visible_flag:
		return

	var now: int = Time.get_ticks_msec()
	var dt_msec: int = int(delta * 1000.0)

	_frame_deltas_msec.append(dt_msec)
	if _frame_deltas_msec.size() > WINDOW_FRAMES:
		_frame_deltas_msec.pop_front()

	# Track sim tick progression. Only advances when GameManager._advance_simulation_tick runs,
	# so measured TPS reflects the ACTUAL sim rate including any lockstep stalls.
	if GameManager.simulation != null:
		if GameManager.current_tick != _last_seen_tick:
			_tick_times_msec.append(now)
			_last_seen_tick = GameManager.current_tick
		while _tick_times_msec.size() > 0 and now - _tick_times_msec[0] > WINDOW_TICKS_MSEC:
			_tick_times_msec.pop_front()

	# Interpolation jitter: |delta of tick_interpolation between frames|. Spikes here = the
	# brick-walk symptom. Stored as per-mille ints (0-1000) to keep the array cheap.
	var cur_interp: float = GameManager.tick_interpolation
	var interp_delta_pm: int = int(absf(cur_interp - _last_interp) * 1000.0)
	_last_interp = cur_interp
	_last_interp_deltas.append(interp_delta_pm)
	if _last_interp_deltas.size() > WINDOW_FRAMES:
		_last_interp_deltas.pop_front()

	# MP remote activity — track when new remote commands arrive without hooking signals.
	# Poll the size of _remote_commands_received; if it grew since last frame we saw a message.
	if not NetworkManager.offline_mode:
		var cnt: int = NetworkManager._remote_commands_received.size()
		if cnt > _last_remote_commands_count:
			_last_remote_event_msec = now
		_last_remote_commands_count = cnt

	_label.text = _render_text(now, dt_msec)


func _render_text(now: int, dt_msec: int) -> String:
	var max_dt: int = 0
	var sum_dt: int = 0
	for d in _frame_deltas_msec:
		if d > max_dt:
			max_dt = d
		sum_dt += d
	var avg_dt: float = 0.0 if _frame_deltas_msec.is_empty() else float(sum_dt) / float(_frame_deltas_msec.size())

	var max_interp: int = 0
	var sum_interp: int = 0
	for d in _last_interp_deltas:
		if d > max_interp:
			max_interp = d
		sum_interp += d
	var avg_interp: float = 0.0 if _last_interp_deltas.is_empty() else float(sum_interp) / float(_last_interp_deltas.size())

	var mp_line: String = "MP:     offline"
	if not NetworkManager.offline_mode:
		var gap: int = now - _last_remote_event_msec
		if _last_remote_event_msec == 0:
			gap = -1
		var stall: int = GameManager._stall_msec
		var local_ticks: int = NetworkManager._local_commands_sent.size()
		var remote_ticks: int = NetworkManager._remote_commands_received.size()
		mp_line = "MP:     online  stall=%dms  remote_gap=%s  local_sent=%d  remote_rcv=%d" % [
			stall,
			"--" if gap < 0 else ("%dms" % gap),
			local_ticks,
			remote_ticks,
		]

	var lines: Array = [
		"FPS: %d  dt=%dms  avg60=%.1f  max60=%d" % [Engine.get_frames_per_second(), dt_msec, avg_dt, max_dt],
		"sim: tick=%d  measured_tps=%d  interp=%.3f" % [GameManager.current_tick, _tick_times_msec.size(), GameManager.tick_interpolation],
		"interp_jitter: avg=%.1f‰  max=%d‰" % [avg_interp, max_interp],
		mp_line,
		"state: %s" % _state_name(GameManager.state),
	]
	return "\n".join(lines)


func _state_name(st: int) -> String:
	match st:
		GameManager.State.MENU: return "MENU"
		GameManager.State.LOADING: return "LOADING"
		GameManager.State.COUNTDOWN: return "COUNTDOWN"
		GameManager.State.PLAYING: return "PLAYING"
		GameManager.State.MATCH_OVER: return "MATCH_OVER"
	return "?"
