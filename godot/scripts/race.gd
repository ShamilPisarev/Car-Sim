class_name RaceManager
extends Node
## A race against AI opponents on the circuit: grid start with five red lights, a fixed number
## of laps, live positions and a results table. Also computes the shared racing line
## (minimum-curvature path inside the track edges) and the speed plan the AI drivers follow.

const AI_COUNT := 5
var ai_count := AI_COUNT
const LAPS := 3
const AI_LEVELS := [["Easy", 0.93], ["Medium", 0.965], ["Hard", 1.0], ["Expert", 1.015]]
static var ai_level := 2
var laps := LAPS                             # 0 = practice: no finish, lap after lap
var _all_ai: Array[Car] = []                 # every opponent built, active or not
var _all_names: Array[String] = []
var _benched := {}                           # opponents sitting this race out
const PLAYER_SLOT := 3                       # start from the second row: you have to earn the lead
const LINE_MARGIN := 1.6                      # keep this far inside the white lines (car half width + air)
# name, base, accent, stripe colour, stripes on, two-tone sides, race number
const DRIVERS := [
	["Vargas", Color(0.72, 0.04, 0.05), Color(0.95, 0.95, 0.95), Color(0.95, 0.95, 0.95), false, true, 3],
	["Lindqvist", Color(0.92, 0.92, 0.94), Color(0.05, 0.35, 0.8), Color(0.05, 0.35, 0.8), true, false, 11],
	["Okafor", Color(0.03, 0.30, 0.15), Color(0.95, 0.75, 0.1), Color(0.95, 0.75, 0.1), true, false, 24],
	["Moreau", Color(0.06, 0.06, 0.07), Color(0.85, 0.65, 0.2), Color(0.85, 0.65, 0.2), false, true, 44],
	["Tanaka", Color(0.98, 0.80, 0.05), Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09), true, true, 63],
	["Novak", Color(0.42, 0.10, 0.55), Color(0.2, 0.85, 0.85), Color(0.95, 0.95, 0.95), true, false, 88],
	["Brennan", Color(0.62, 0.64, 0.66), Color(0.85, 0.1, 0.08), Color(0.85, 0.1, 0.08), false, true, 91],
]

signal race_started
signal car_finished(car: Car, place: int, time: float)

var track                                    # RaceTrack
var player: Car
var listener: Node3D                         # camera, for the opponents' 3D sound
var cars: Array[Car] = []
var names: Array[String] = []
var drivers: Array = []                      # AIDriver per AI car

# racing line (one sample per centerline sample)
var center := PackedVector3Array()
var right := PackedVector3Array()
var line_lat := PackedFloat32Array()         # lateral offset of the racing line, + = right
var line_speed := PackedFloat32Array()       # planned speed, m/s
var n := 0
var ds := 2.0
var track_len := 0.0
var s_line := 0.0

# race state
enum Phase { GRID, LIGHTS, GREEN, DONE }
var phase := Phase.GRID
var phase_t := 0.0
var lights_on := 0                           # 0..5 red lights lit
var _lights_out_at := 0.0
var race_time := 0.0
var _idx := {}                               # car -> nearest centerline index
var _dist := {}                              # car -> race distance from the line, m
var _last_s := {}                            # car -> track position last tick, m
var finish_time := {}                        # car -> race time at the flag
var finish_order: Array[Car] = []
var dnf := {}                                # car -> true when retired (wrecked or broken down)
# race control: track limits (yours), flags, messages for the HUD
const LIMIT_LAT := 7.7                       # car centre this far out = all four wheels past the line
var penalty := {}                            # car -> seconds added to the race time
var limit_strikes := 0
var flag := ""                               # "", "yellow", "blue"
var notice := ""
var notice_t := 0.0
var _off_t := 0.0
var _off_counted := false
var _flag_t := 0.0
# pit stops (your car)
var pit_time_left := 0.0
var _pit_total := 0.0
var _pit_used := false
const FUEL_PER_LAP := 3.1                    # kg, roughly what a lap burns

func setup(t, p: Car, cam: Node3D) -> void:
	track = t
	player = p
	listener = cam
	center = track.get_centerline()
	right = track.get_right_vectors()
	n = center.size()
	track_len = track.get_length()
	ds = track_len / n
	s_line = track.get_line_s()
	_build_racing_line()
	_build_speed_plan()
	cars.append(player)
	names.append("You")
	var slot := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in ai_count:
		if slot == PLAYER_SLOT:
			slot += 1
		var c := Car.new()
		c.name = "AI_%d" % k
		c.spec_id = CarSpecs.ORDER[(k + 1) % CarSpecs.ORDER.size()]   # a mixed field of all four models
		get_parent().add_child(c)
		var d: Array = DRIVERS[k % DRIVERS.size()]
		c.set_livery(d[1], d[2], d[3], d[4], d[5])
		c.set_race_number(d[6])
		c.abs_enabled = true
		c.tc_enabled = true
		var drv := AIDriver.new()
		drv.name = "Driver"
		drv.race = self
		drv.car = c
		drv.grid_slot = slot
		# the field is spread a little: the front runners are a touch quicker
		drv.base_skill = 0.955 + rng.randf_range(-0.01, 0.01)
		drv.late_braker = rng.randf()
		drv.defender = rng.randf()
		drv.steadiness = rng.randf()
		drv.skill = drv.base_skill
		drv.aggression = rng.randf_range(0.3, 1.0)
		c.add_child(drv)
		var snd := RemoteEngine.new()
		snd.car = c
		snd.listener = listener
		c.add_child(snd)
		cars.append(c)
		names.append(d[0])
		_all_ai.append(c)
		_all_names.append(d[0])
		drivers.append(drv)
		slot += 1
	restart()

func replace_player(c: Car) -> void:
	## the player switched car: the new one takes the old one's place in the field
	var i := cars.find(player)
	_idx.erase(player)
	_dist.erase(player)
	_last_s.erase(player)
	cars[i] = c
	player = c

func set_field(opponents: int) -> void:
	## race against the first `opponents` AI cars; the rest are parked out of sight
	cars = [player]
	names = ["You"]
	for k in _all_ai.size():
		var c := _all_ai[k]
		if k < opponents:
			cars.append(c)
			names.append(_all_names[k])
			if _benched.has(c):
				_benched.erase(c)
				_unretire(c)
		elif not _benched.has(c):
			_benched[c] = true
			_park(c)

func _park(c: Car) -> void:
	c.visible = false
	c.freeze = true
	c.collision_layer = 0
	c.collision_mask = 0
	c.process_mode = Node.PROCESS_MODE_DISABLED
	c.global_position = Vector3(0, -80, 0)

func model_of(c: Car) -> String:
	return c.spec["title"]

func restart() -> void:
	_build_speed_plan()                      # grip differs between realistic and arcade mode
	phase = Phase.GRID
	phase_t = 0.0
	lights_on = 0
	race_time = 0.0
	finish_time.clear()
	finish_order.clear()
	penalty.clear()
	limit_strikes = 0
	pit_time_left = 0.0
	_pit_used = false
	flag = ""
	notice = ""
	_off_t = 0.0
	_off_counted = false
	for c in dnf.keys():
		_unretire(c)
	dnf.clear()
	if SkidMarks.instance:
		SkidMarks.instance.clear_marks()
	# a different starting order every race (as if qualifying went differently); you keep your slot
	var free_slots: Array[int] = []
	for c in cars:
		if c != player:
			free_slots.append((c.get_node("Driver") as AIDriver).grid_slot)
	free_slots.shuffle()
	var si := 0
	for c in cars:
		if c != player:
			(c.get_node("Driver") as AIDriver).grid_slot = free_slots[si]
			si += 1
	for c in cars:
		var slot := PLAYER_SLOT
		if c != player:
			slot = (c.get_node("Driver") as AIDriver).grid_slot
			var dr := c.get_node("Driver") as AIDriver
			dr.reset_state()
			# form on the day: a driver can be a little quicker or slower than usual
			dr.skill = (dr.base_skill + randf_range(-0.018, 0.018)) * AI_LEVELS[ai_level][1]
		var tr: Transform3D = track.get_grid_transform(slot)
		c.reset_car(tr.origin - Vector3(0, 0.17, 0), tr.basis.get_euler().y)
		c.parts.repair()
		c.reset_crush()
		for w in c.wheels:
			w.wear = 0.0
		c.fuel = (laps * FUEL_PER_LAP + 3.0) if laps > 0 else 40.0
		c.out_of_fuel = false
		c.speed_cap = 0.0
		c.mass = c.mass_kg + (c.fuel if CarSetup.wear_and_fuel else 0.0)
		c.hold = true
		_idx[c] = _nearest(c.global_position, -1)
		var s := _s_of(c)
		_last_s[c] = s
		_dist[c] = fposmod(s - s_line, track_len) - track_len
	_lights_out_at = 5.0 + randf_range(0.4, 2.2)

# ------------------------------------------------------------------ racing line
func _build_racing_line() -> void:
	## Iterative smoothing of the path inside the track edges converges on a minimum-curvature
	## line: outside on entry, clipping the apex, out to the edge on exit. Coarse grid first.
	var w_max: float = track.get_track_width() * 0.5 - LINE_MARGIN
	var off := _relax(16, 900, w_max, PackedFloat32Array())
	off = _relax(4, 500, w_max, off)
	line_lat.resize(n)
	var step := 4
	var m := off.size()
	for i in n:
		var f := float(i) / step
		var a := int(f) % m
		var b := (a + 1) % m
		line_lat[i] = lerpf(off[a], off[b], f - floorf(f))

func _relax(step: int, iters: int, w_max: float, init: PackedFloat32Array) -> PackedFloat32Array:
	var m := n / step
	var c := PackedVector3Array()
	var r := PackedVector3Array()
	c.resize(m)
	r.resize(m)
	for k in m:
		c[k] = center[k * step]
		r[k] = right[k * step]
	var off := PackedFloat32Array()
	off.resize(m)
	if not init.is_empty():
		var ratio := float(init.size()) / m
		for k in m:
			var f := k * ratio
			var a := int(f) % init.size()
			off[k] = lerpf(init[a], init[(a + 1) % init.size()], f - floorf(f))
	for it in iters:
		for k in m:
			var kp := (k - 1 + m) % m
			var kn := (k + 1) % m
			var mid := (c[kp] + r[kp] * off[kp] + c[kn] + r[kn] * off[kn]) * 0.5
			var want := (mid - c[k]).dot(r[k])
			off[k] = clampf(lerpf(off[k], want, 0.6), -w_max, w_max)
	return off

func line_point(i: int) -> Vector3:
	var k := posmod(i, n)
	return center[k] + right[k] * line_lat[k]

func _build_speed_plan() -> void:
	line_speed.resize(n)
	var k_aero := 0.5 * 1.2 * Car.CL_A / Car.MASS
	var mu := 1.22 * CarSpecs.grip_factor() * Weather.grip()  # what the car really holds at speed (load sensitivity, combined slip)
	for i in n:
		var a := line_point(i - 5)
		var b := line_point(i)
		var c := line_point(i + 5)
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var area2 := absf((b - a).cross(c - a).y)
		var radius := 1e6 if area2 < 1e-4 else (ab * bc * ca) / (2.0 * area2)
		# lateral grip grows with downforce: v^2 / r = mu (g + k v^2)
		var den := maxf(1.0 - mu * k_aero * radius, 0.12)
		line_speed[i] = minf(sqrt(mu * Car.G * radius / den), 88.0)
	# braking zones: from every corner, back up the track at the achievable deceleration
	for pass_i in 2:
		for k in range(n * 2 - 1, -1, -1):
			var i := k % n
			var j := (i + 1) % n
			var v1 := line_speed[j]
			var decel := (11.0 + 0.0016 * v1 * v1) * Weather.grip()
			line_speed[i] = minf(line_speed[i], sqrt(v1 * v1 + 2.0 * decel * ds))

# ------------------------------------------------------------------ tracking
func _nearest(p: Vector3, hint: int) -> int:
	var best := 0
	var bd := INF
	if hint >= 0:
		for o in range(-12, 50):
			var k := posmod(hint + o, n)
			var d := Vector2(center[k].x - p.x, center[k].z - p.z).length_squared()
			if d < bd:
				bd = d
				best = k
		if bd < 900.0:
			return best
	for k in n:
		var d := Vector2(center[k].x - p.x, center[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best

func index_of(c: Car) -> int:
	return _idx.get(c, 0)

func _s_of(c: Car) -> float:
	var i: int = _idx[c]
	var d := c.global_position - center[i]
	var t := (center[(i + 1) % n] - center[(i - 1 + n) % n]).normalized()
	return float(i) * ds + d.x * t.x + d.z * t.z

func lateral_of(c: Car) -> float:
	var i: int = _idx[c]
	return (c.global_position - center[i]).dot(right[i])

func gap_along(from: Car, to: Car) -> float:
	## track distance from one car forward to another, wrapped to -len/2 .. len/2
	return wrapf(_s_of(to) - _s_of(from), -track_len * 0.5, track_len * 0.5)

func lap_of(c: Car) -> int:
	var lap := maxi(int(floorf(_dist.get(c, 0.0) / track_len)) + 1, 1)
	return lap if laps == 0 else mini(lap, laps)

func standings() -> Array[Car]:
	var order: Array[Car] = finish_order.duplicate()
	var rest: Array[Car] = []
	var out: Array[Car] = []
	for c in cars:
		if finish_time.has(c):
			continue
		if dnf.has(c):
			out.append(c)
		else:
			rest.append(c)
	rest.sort_custom(func(a: Car, b: Car) -> bool: return _dist[a] > _dist[b])
	order.append_array(rest)
	order.append_array(out)
	return order

func retire(c: Car) -> void:
	## a wrecked car is recovered by the marshals: taken off the circuit, out of the race
	if dnf.has(c) or c == player:
		return
	dnf[c] = true
	_park(c)

func _unretire(c: Car) -> void:
	c.visible = true
	c.freeze = false
	c.collision_layer = 2
	c.collision_mask = 1 | 2 | 4
	c.process_mode = Node.PROCESS_MODE_INHERIT

func position_of(c: Car) -> int:
	return standings().find(c) + 1

func name_of(c: Car) -> String:
	return names[cars.find(c)]

func gap_text(c: Car) -> String:
	## gap to the car in front, as time at the current speed (shown in the HUD)
	var st := standings()
	var p := st.find(c)
	if p <= 0:
		return ""
	var ahead: Car = st[p - 1]
	var metres: float = _dist[ahead] - _dist[c]
	var v := maxf(c.linear_velocity.length(), 15.0)
	return "+%.1f s to %s" % [metres / v, name_of(ahead)]

# ------------------------------------------------------------------ race flow
func _physics_process(dt: float) -> void:
	if n == 0:
		return
	phase_t += dt
	match phase:
		Phase.GRID:
			if phase_t > 1.0:
				phase = Phase.LIGHTS
				phase_t = 0.0
		Phase.LIGHTS:
			lights_on = mini(int(phase_t) + 1, 5)
			if phase_t >= _lights_out_at:
				lights_on = 0
				phase = Phase.GREEN
				phase_t = 0.0
				for c in cars:
					c.hold = false
				race_started.emit()
		Phase.GREEN, Phase.DONE:
			race_time += dt
	for c in cars:
		if dnf.has(c):
			continue
		_idx[c] = _nearest(c.global_position, _idx[c])
		var s := _s_of(c)
		var d := wrapf(s - _last_s[c], -track_len * 0.5, track_len * 0.5)
		_last_s[c] = s
		if absf(d) < 40.0 and phase >= Phase.GREEN:
			_dist[c] += d
		if phase >= Phase.GREEN and not finish_time.has(c) and laps > 0 and _dist[c] >= laps * track_len:
			finish_time[c] = race_time + float(penalty.get(c, 0.0))
			finish_order.append(c)
			finish_order.sort_custom(func(a: Car, b: Car) -> bool: return finish_time[a] < finish_time[b])
			car_finished.emit(c, finish_order.size(), race_time)
			if c == player:
				phase = Phase.DONE
	if phase == Phase.GREEN:
		_race_control(dt)
	if phase >= Phase.GREEN:
		_pits(dt)
	notice_t = maxf(notice_t - dt, 0.0)

func say(msg: String, secs := 3.5) -> void:
	notice = msg
	notice_t = secs

func _in_pits(c: Car) -> bool:
	return track.has_method("in_pit_lane") and track.in_pit_lane(c.global_position)

func _race_control(dt: float) -> void:
	# track limits: whole car past the white line for more than half a second is one strike
	if laps > 0 and not finish_time.has(player):
		var off := absf(lateral_of(player)) > LIMIT_LAT and player.linear_velocity.length() > 11.0 and not _in_pits(player)
		if off:
			_off_t += dt
			if _off_t > 0.5 and not _off_counted:
				_off_counted = true
				limit_strikes += 1
				if limit_strikes <= 3:
					say("TRACK LIMITS  warning %d / 3" % limit_strikes)
				else:
					penalty[player] = float(penalty.get(player, 0.0)) + 5.0
					say("TRACK LIMITS  +5 s penalty  (total %d s)" % int(penalty[player]), 4.5)
		elif absf(lateral_of(player)) < 6.6:
			_off_t = 0.0
			_off_counted = false
	# flags for the player, a few times a second
	_flag_t -= dt
	if _flag_t > 0.0:
		return
	_flag_t = 0.25
	flag = ""
	if incident_ahead(player, 300.0):
		flag = "yellow"
	for o in cars:
		if o == player or dnf.has(o) or finish_time.has(o):
			continue
		var behind := gap_along(o, player)
		if behind > 0.0 and behind < 80.0 and _dist[o] - _dist[player] > track_len * 0.5:
			flag = "blue"

func _pits(dt: float) -> void:
	## pit lane limiter, and the stop itself: stand still in your box and the crew works
	if not track.has_method("in_pit_lane"):
		return
	var p := player.global_position
	var in_lane: bool = track.in_pit_lane(p)
	player.speed_cap = RaceTrack.PIT_SPEED if in_lane else 0.0
	if not in_lane:
		_pit_used = false
	if pit_time_left > 0.0:
		pit_time_left -= dt
		player.hold = true
		if pit_time_left <= 0.0:
			var left := maxi(laps - lap_of(player) + 1, 1) if laps > 0 else 10
			player.service(true, left * FUEL_PER_LAP + 3.0, true)
			player.hold = false
			say("PIT STOP done  %.1f s - go!" % _pit_total, 3.0)
		return
	if in_lane and not _pit_used and track.in_pit_box(p) and player.linear_velocity.length() < 1.2:
		_pit_used = true
		# 2.5 s for the wheels; refuelling and repairs add time
		var dmg := 0.0
		for k in player.parts.damage.keys():
			dmg += minf(float(player.parts.damage[k]), 1.0)
		var left2 := maxi(laps - lap_of(player) + 1, 1) if laps > 0 else 10
		var fuel_in := maxf(left2 * FUEL_PER_LAP + 3.0 - player.fuel, 0.0) if CarSetup.wear_and_fuel else 0.0
		_pit_total = 2.5 + fuel_in / 2.4 + minf(dmg * 1.2, 15.0) + (2.0 if player.engine_health < 0.9 else 0.0)
		pit_time_left = _pit_total
		say("PIT STOP", _pit_total)

func incident_ahead(c: Car, within: float) -> bool:
	## a car stopped, crawling or off the road in the next `within` metres (yellow flag zone)
	for o in cars:
		if o == c or dnf.has(o) or finish_time.has(o):
			continue
		var gap := gap_along(c, o)
		if gap > 0.0 and gap < within:
			if o.linear_velocity.length() < 6.0 or absf(lateral_of(o)) > 10.0:
				return true
	return false
