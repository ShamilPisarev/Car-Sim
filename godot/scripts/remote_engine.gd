class_name RemoteEngine
extends AudioStreamPlayer3D
## Engine and tyre sound of an opponent, placed in 3D at the car: distance attenuation,
## air absorption (high frequencies fade first) and Doppler shift as it passes.
## A cheaper version of EngineAudio: same firing-pulse tables, two resonances, low sample rate.

const RATE := 11025.0
const MAX_DIST := 260.0

var car: Car
var listener: Node3D
var gen := AudioStreamGenerator.new()
var pb: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _rpm_s := 1000.0
var _thr_s := 0.0
var _lp := 0.0
var _r1 := EngineAudio.Biquad.new()
var _r2 := EngineAudio.Biquad.new()
var _sq := EngineAudio.Biquad.new()
var _active := false

var _tl := PackedFloat32Array()
var _to := PackedFloat32Array()

func _ready() -> void:
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	unit_size = 9.0
	max_db = 2.0
	volume_db = -2.0
	max_distance = MAX_DIST
	attenuation_filter_cutoff_hz = 5000.0
	attenuation_filter_db = -18.0
	doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	_rng.seed = get_instance_id()
	var res: Array = car.spec["res"]
	_r1.set_bp(res[0] * _rng.randf_range(0.93, 1.07), 1.1, RATE)
	_r2.set_bp(res[1] * _rng.randf_range(0.93, 1.07), 1.8, RATE)
	var t: Array = EngineAudio.tables_for(car.spec["pulses"])
	_tl = t[0]
	_to = t[1]
	_sq.set_bp(800.0, 6.0, RATE)
	position = Vector3(0, 0.5, 1.6)                          # at the exhaust

func _process(dt: float) -> void:
	if car == null or listener == null:
		return
	var near := listener.global_position.distance_to(global_position) < MAX_DIST
	if near != _active:
		_active = near
		if near:
			play()
			pb = get_stream_playback() as AudioStreamGeneratorPlayback
		else:
			stop()
			pb = null
	if pb == null:
		return
	var n := pb.get_frames_available()
	if n <= 0:
		return
	_rpm_s = lerpf(_rpm_s, car.engine_rpm, clampf(dt * 20.0, 0.0, 1.0))
	_thr_s = lerpf(_thr_s, 0.0 if car.shift_timer >= 0.06 else car.throttle, clampf(dt * 25.0, 0.0, 1.0))
	var thr := _thr_s
	var rpm_n := clampf(_rpm_s / car.limiter_rpm, 0.0, 1.0)
	var f_cycle := _rpm_s / 120.0
	var amp := (0.3 + 0.7 * thr) * (0.55 + 0.45 * rpm_n) * 0.6
	var lp_k := 1.0 - exp(-TAU * (1400.0 + 3000.0 * thr * rpm_n) / RATE)
	var squeal := 0.0
	for w in car.wheels:
		if w.grounded and w.mu_surface > 0.9:
			squeal = maxf(squeal, smoothstep(0.85, 1.0, w.grip_use) * clampf((w.slide_speed - 0.8) / 3.0, 0.0, 1.0))
	var tl := _tl
	var to := _to
	var tsize := EngineAudio.TABLE
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_phase += f_cycle / RATE
		if _phase >= 1.0:
			_phase -= 1.0
		var fi := _phase * tsize
		var i0 := int(fi)
		var fr := fi - i0
		var i1 := (i0 + 1) % tsize
		var el := tl[i0] + (tl[i1] - tl[i0]) * fr
		var eo := to[i0] + (to[i1] - to[i0]) * fr
		var e := eo + (el - eo) * thr
		var s := _r1.step(e) * 1.2 + _r2.step(e) * 0.8 + e * 0.15
		_lp += (s - _lp) * lp_k
		var out := _lp * amp
		if squeal > 0.01:
			out += _sq.step(_rng.randf() * 2.0 - 1.0) * squeal * 0.5
		out = tanh(out * 1.3) * 0.85
		buf[i] = Vector2(out, out)
	pb.push_buffer(buf)
