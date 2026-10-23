class_name EngineAudio
extends Node
## Procedural sound for the player's car, synthesised from the physics every frame.
## Engine: a pulse train of 8 uneven cylinder firings per engine cycle (cross-plane V8 burble)
## fed through fixed exhaust / body resonances, so the timbre shifts with rpm like a real
## engine. Plus intake roar, straight-cut gear whine, overrun crackle, shift bangs, rev limiter,
## tyre squeal and scrub, kerb rumble, gravel / grass, road roar, wind and crash thumps.

const RATE := 22050.0
const TABLE := 1024

var car: Car
var interior := false            # cockpit / hood camera: muffled exhaust, more intake and gear whine
var player: AudioStreamPlayer
var gen := AudioStreamGenerator.new()
var pb: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _mute := false
var recording := false           # offline render for the audio self test

var _phase := 0.0
var _rpm_s := 1000.0
var _thr_s := 0.0
var _limiter_t := 0.0
var _crash_env := 0.0
var _crash_phase := 0.0
var _pop_env := 0.0
var _pop_lp := 0.0
var _whine_phase := 0.0
var _rumble_phase := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _wind_lp := 0.0
var _road_lp := 0.0
var _road_lp2 := 0.0
var _jitter := 1.0
var _last_gear := 1
var _last_pops := 0
var _rain_lp := 0.0
var _wet_lp := 0.0
var _shift_env := 0.0

var _r1 := Biquad.new()
var _r2 := Biquad.new()
var _r3 := Biquad.new()
var _intake := Biquad.new()
var _squeal := Biquad.new()
var _squeal2 := Biquad.new()
var _scrub := Biquad.new()
var _gravel := Biquad.new()

static var _tables := {}         # firing pattern -> [on-load table, overrun table]
var _tl := PackedFloat32Array()
var _to := PackedFloat32Array()
var _turbo := false
var _whistle_phase := 0.0
var _bov_env := 0.0
var _bov_lp := 0.0
var _last_boost := 0.0

class Biquad:
	## RBJ band-pass, 0 dB peak gain (transposed direct form II)
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var z1 := 0.0
	var z2 := 0.0
	func set_bp(f: float, q: float, rate: float) -> void:
		var w0 := TAU * clampf(f, 20.0, rate * 0.45) / rate
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0
	func step(x: float) -> float:
		var y := b0 * x + z1
		z1 = -a1 * y + z2
		z2 = b2 * x - a2 * y
		return y

static func tables_for(amp: Array) -> Array:
	## one engine cycle (720 deg of crank) = one firing pulse per cylinder. Cylinder-to-cylinder
	## spread in strength gives the burble (a cross-plane V8 has lots, a flat-6 very little);
	## overrun pulses are weak, soft and irregular.
	var key := str(amp)
	if _tables.has(key):
		return _tables[key]
	var nc := amp.size()
	var offs := [0.0, 0.004, -0.006, 0.003, -0.002, 0.007, -0.004, 0.002]   # slight timing scatter
	var table_load := PackedFloat32Array()
	var table_off := PackedFloat32Array()
	table_load.resize(TABLE)
	table_off.resize(TABLE)
	for i in TABLE:
		var x := float(i) / TABLE
		var vl := 0.0
		var vo := 0.0
		for c in nc:
			var t0: float = float(c) / nc + offs[c % offs.size()]
			var t := fposmod(x - t0, 1.0) * nc           # time since this cylinder fired, in firing slots
			# blow-down: steep rise, exponential decay, small negative swing (reflected wave)
			vl += amp[c] * (exp(-t * 9.0) * (1.0 - exp(-t * 90.0)) - 0.11 * exp(-t * 2.5))
			vo += amp[c] * (0.55 + 0.45 * sin(float(c) * 2.1)) * (exp(-t * 4.0) * (1.0 - exp(-t * 30.0)) - 0.12 * exp(-t * 1.5))
		table_load[i] = vl
		table_off[i] = vo * 0.6
	# remove DC
	var ml := 0.0
	var mo := 0.0
	for i in TABLE:
		ml += table_load[i]
		mo += table_off[i]
	ml /= TABLE
	mo /= TABLE
	for i in TABLE:
		table_load[i] -= ml
		table_off[i] -= mo
	_tables[key] = [table_load, table_off]
	return _tables[key]

func _ready() -> void:
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	player = AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -3.0
	SoundSettings.ensure_buses()
	player.bus = "Player"
	add_child(player)
	player.play()
	pb = player.get_stream_playback() as AudioStreamGeneratorPlayback
	_scrub.set_bp(320.0, 1.0, RATE)
	_gravel.set_bp(2200.0, 0.8, RATE)

func bind(c: Car) -> void:
	if car != null and car.contact_impulse.is_connected(_on_contact):
		car.contact_impulse.disconnect(_on_contact)
	car = c
	_last_gear = c.gear
	var t: Array = tables_for(c.spec["pulses"])
	_tl = t[0]
	_to = t[1]
	var res: Array = c.spec["res"]
	_r1.set_bp(res[0], 1.1, RATE)
	_r2.set_bp(res[1], 1.8, RATE)
	_r3.set_bp(res[2], 2.2, RATE)
	_turbo = c.spec["turbo"]
	c.contact_impulse.connect(_on_contact)

func _on_contact(_p: Vector3, j: float, _n: Vector3) -> void:
	_crash_env = maxf(_crash_env, clampf(j / 4000.0, 0.15, 1.0))

func toggle_mute() -> void:
	_mute = not _mute
	player.volume_db = -80.0 if _mute else -3.0

func _process(dt: float) -> void:
	if car == null or pb == null or recording:
		return
	var n := pb.get_frames_available()
	if n <= 0:
		return
	pb.push_buffer(render(n, dt))

func render(n: int, dt: float) -> PackedVector2Array:
	# ---------------------------------------------------------- per-block parameters
	_rpm_s = lerpf(_rpm_s, car.engine_rpm, clampf(dt * 20.0, 0.0, 1.0))
	var cut := car.shift_timer >= 0.06                       # ignition cut during a shift
	var thr_target := 0.0 if cut else car.throttle
	_thr_s = lerpf(_thr_s, thr_target, clampf(dt * 25.0, 0.0, 1.0))
	var thr := _thr_s
	# downshift blip: the engine note flares for a moment
	thr = maxf(thr, clampf(car.blip_t / 0.18, 0.0, 1.0) * 0.8)
	if car.pops != _last_pops:
		_pop_env = maxf(_pop_env, _rng.randf_range(0.7, 1.0))
		_last_pops = car.pops
	var f_cycle := _rpm_s / 120.0                           # engine cycles per second
	var rpm_n := clampf(_rpm_s / car.limiter_rpm, 0.0, 1.0)
	var health := clampf(car.engine_health * 1.3, 0.25, 1.0)
	var limiter := car.engine_rpm >= car.limiter_rpm - 60.0 and car.throttle > 0.5
	var overrun := (1.0 - thr) * clampf((_rpm_s - 3200.0) / 4500.0, 0.0, 1.0)
	if car.gear != _last_gear:
		if car.gear > _last_gear and _rpm_s > 5500.0:
			_pop_env = 1.0                                  # upshift bang
		_shift_env = 1.0
		_last_gear = car.gear
	_intake.set_bp(500.0 + 1400.0 * rpm_n, 1.4, RATE)
	var bright: float = car.spec["bright"]
	var lp_cut := (1800.0 + 5200.0 * thr * rpm_n + 800.0 * rpm_n) * (0.55 if interior else 1.0) * bright
	# turbo: whistle rising with boost, blow-off valve hiss when the throttle closes on boost
	var whistle_f := 2400.0 + 4200.0 * car.boost
	var whistle_amp := 0.035 * car.boost * car.boost * (1.4 if interior else 1.0) if _turbo else 0.0
	if _turbo and _last_boost > 0.55 and car.throttle < 0.15:
		_bov_env = maxf(_bov_env, _last_boost)
	_last_boost = car.boost
	var lp_k := 1.0 - exp(-TAU * lp_cut / RATE)
	var eng_amp := (0.50 + 0.50 * thr) * health * (0.55 + 0.45 * rpm_n) * (0.8 if interior else 1.0)
	var rasp := (0.15 + 0.6 * thr * rpm_n) * (0.6 if interior else 1.0)
	var intake_amp := thr * rpm_n * (0.22 if interior else 0.10)
	var spd := car.linear_velocity.length()
	var whine_f := _rpm_s / 60.0 * 17.0
	var whine_amp := clampf(spd / 40.0, 0.0, 1.0) * (0.012 + 0.02 * thr) * (2.2 if interior else 1.0)

	# tyres and surfaces: strongest wheel decides
	var squeal := 0.0
	var scrub := 0.0
	var loose := 0.0
	var kerb := 0.0
	var squeal_pitch := 0.0
	for w in car.wheels:
		if not w.grounded:
			continue
		var on_road := w.mu_surface > 0.9
		if on_road:
			# squeal lives near the peak of the grip curve; past it the sound turns into a roar
			var sq := smoothstep(0.82, 1.0, w.grip_use) * clampf((w.slide_speed - 0.6) / 2.5, 0.0, 1.0)
			sq *= 1.0 - clampf((w.slide_speed - 9.0) / 12.0, 0.0, 0.6)
			if sq > squeal:
				squeal = sq
				squeal_pitch = clampf(absf(w.slip_angle) * 3.0 + absf(w.slip_ratio), 0.0, 1.0)
			scrub = maxf(scrub, clampf((w.slide_speed - 3.0) / 12.0, 0.0, 1.0))
			if absf(w.mu_surface - 0.95) < 0.01:
				kerb = maxf(kerb, clampf(spd / 15.0, 0.0, 1.0))
		else:
			loose = maxf(loose, clampf(spd / 20.0, 0.0, 1.0) + clampf(w.slide_speed / 10.0, 0.0, 0.5))
	if spd < 2.0:
		squeal *= spd / 2.0
	_squeal.set_bp(700.0 + 350.0 * squeal_pitch, 7.0, RATE)
	_squeal2.set_bp(1450.0 + 600.0 * squeal_pitch, 9.0, RATE)
	var wind := clampf(spd / 85.0, 0.0, 1.0)
	var road := clampf(spd / 60.0, 0.0, 1.0)
	var kerb_f := maxf(spd / 0.4, 10.0)
	# rain: steady hiss (drumming on the roof inside), plus tyre swish rising with speed
	var rain_amp := (0.10 if interior else 0.06) if Weather.rain else 0.0
	var wet_amp := clampf(spd / 50.0, 0.0, 1.0) * 0.14 if Weather.rain else 0.0

	# ---------------------------------------------------------- per-sample synthesis
	var buf := PackedVector2Array()
	buf.resize(n)
	var tl := _tl
	var to := _to
	var inv := 1.0 / RATE
	for i in n:
		_phase += f_cycle * inv
		if _phase >= 1.0:
			_phase -= 1.0
			_jitter = 1.0 + _rng.randf_range(-0.08, 0.08) * (1.4 - thr)   # cycle-to-cycle combustion scatter
		var fi := _phase * TABLE
		var i0 := int(fi)
		var fr := fi - i0
		var i1 := (i0 + 1) % TABLE
		var e_load := tl[i0] + (tl[i1] - tl[i0]) * fr
		var e_off := to[i0] + (to[i1] - to[i0]) * fr
		var e := (e_off + (e_load - e_off) * thr) * _jitter
		var nz := _rng.randf() * 2.0 - 1.0
		# exhaust resonances
		var s := _r1.step(e) * 1.2 + _r2.step(e) * 0.8 + _r3.step(e) * rasp + e * 0.12
		s += _intake.step(nz * (0.4 + absf(e))) * intake_amp
		_lp += (s - _lp) * lp_k
		_lp2 += (_lp - _lp2) * lp_k
		var out := _lp2 * eng_amp * 1.5
		if limiter:
			_limiter_t += inv
			if fmod(_limiter_t, 0.075) > 0.045:
				out *= 0.2
		# overrun crackle and shift bangs
		if overrun > 0.15 and _rng.randf() < 0.00012 * overrun:
			_pop_env = maxf(_pop_env, _rng.randf_range(0.3, 0.8) * overrun)
		if _pop_env > 0.003:
			_pop_lp += (nz - _pop_lp) * 0.45
			out += (_pop_lp * 0.7 + nz * 0.3) * _pop_env * (0.35 if interior else 0.6)
			_pop_env *= 0.9965
		if _shift_env > 0.003:
			out += sin(TAU * _crash_phase * 0.6) * _shift_env * 0.08
			_shift_env *= 0.996
		if whistle_amp > 0.0005:
			_whistle_phase = fmod(_whistle_phase + whistle_f * inv, 1.0)
			out += sin(TAU * _whistle_phase) * whistle_amp
		if _bov_env > 0.003:
			_bov_lp += (nz - _bov_lp) * 0.3
			out += (nz - _bov_lp) * _bov_env * 0.22
			_bov_env *= 0.9997
		# straight-cut gearbox whine
		_whine_phase = fmod(_whine_phase + whine_f * inv, 1.0)
		out += sin(TAU * _whine_phase) * whine_amp
		# tyres
		if squeal > 0.01:
			out += (_squeal.step(nz) * 1.6 + _squeal2.step(nz) * 0.7) * squeal * 0.55
		if scrub > 0.01:
			out += _scrub.step(nz) * scrub * 0.35
		if loose > 0.01:
			var crunch := nz if _rng.randf() < 0.25 else nz * 0.2
			out += _gravel.step(crunch) * loose * 0.25
		if kerb > 0.01:
			_rumble_phase = fmod(_rumble_phase + kerb_f * inv, 1.0)
			out += (1.0 if _rumble_phase < 0.35 else -0.4) * kerb * 0.09
		# road roar and wind
		_road_lp += (nz - _road_lp) * 0.03
		_road_lp2 += (_road_lp - _road_lp2) * 0.03
		out += _road_lp2 * road * 0.9
		_wind_lp += (nz - _wind_lp) * (0.03 + 0.12 * wind)
		out += _wind_lp * wind * wind * (0.12 if interior else 0.35)
		if rain_amp > 0.0:
			_rain_lp += (nz - _rain_lp) * 0.55
			out += (nz - _rain_lp) * rain_amp
			_wet_lp += (nz - _wet_lp) * 0.18
			out += (_wet_lp - _road_lp) * wet_amp
		# crash thump
		if _crash_env > 0.002:
			_crash_phase += (55.0 + 30.0 * _crash_env) * inv
			out += (sin(TAU * _crash_phase) * 0.7 + nz * 0.5) * _crash_env * 0.9
			_crash_env *= 0.9992
		else:
			_crash_phase += 40.0 * inv
		out = tanh(out * 1.3) * 0.85                       # soft clip, like a mic on a loud car
		buf[i] = Vector2(out, out)
	return buf
