class_name AIDriver
extends Node
## Drives one opponent car through the same controls a player has (throttle, brake, steer).
## Follows the racing line with pure-pursuit steering, brakes to the speed plan, moves off
## the line to overtake or avoid cars, catches slides with counter-steer and a lift, and
## gets itself back on track if it ends up stuck or upside down.

var race: RaceManager
var car: Car
var grid_slot := 0
var skill := 0.95                 # fraction of the planned speed this driver dares to carry
var base_skill := 0.95            # the driver's usual level; `skill` varies around it race to race
var aggression := 0.6             # how late it brakes when fighting for position
# personality (set by the race): how late it brakes, how hard it defends, how steady it is
var late_braker := 0.5            # 0 cautious .. 1 brakes very late
var defender := 0.5               # 0 lets you by .. 1 covers the inside when you are close behind
var steadiness := 0.5             # 0 makes more mistakes .. 1 very consistent
var _defend_side := 0.0           # inside line chosen while defending (kept until the corner)

var _avoid := 0.0                 # lateral offset from the racing line, m
var _stuck_t := 0.0
var _flip_t := 0.0
var _rev_phase := 0.0
var _mistake_t := 0.0
var _lane := 0.0                  # grid lane relative to the racing line, held for the first seconds
var _lane_set := false

func _defend(want: float, i: int, v: float, line_here: float, w_max: float) -> float:
	## a car close behind and a braking zone coming: move once to the inside of the next
	## corner and hold it (no weaving). Only drivers with a defending streak do it.
	if defender < 0.45:
		return want
	var n := race.n
	var behind := false
	for o in race.cars:
		if o == car or race.dnf.has(o):
			continue
		var g := race.gap_along(o, car)
		if g > 2.0 and g < 14.0 and o.linear_velocity.length() > v - 2.0:
			behind = true
	# the next real braking point within 160 m, and the inside of that corner
	var apex := -1
	var steps := int(160.0 / race.ds)
	for k in range(4, steps, 3):
		if race.line_speed[(i + k) % n] < v * 0.82:
			apex = (i + k) % n
			break
	if not behind or apex < 0:
		_defend_side = 0.0
		return want
	if _defend_side == 0.0:
		var inside: float = signf(race.line_lat[(apex + int(30.0 / race.ds)) % n])
		_defend_side = inside if inside != 0.0 else 1.0
	return _defend_side * (w_max - 0.8) - line_here

func reset_state() -> void:
	_avoid = 0.0
	_stuck_t = 0.0
	_flip_t = 0.0
	_lane_set = false

func _physics_process(dt: float) -> void:
	if race == null or race.n == 0:
		return
	var n := race.n
	var v := car.linear_velocity.length()
	if car.hold:
		# on the grid: blip the throttle like a driver warming the engine
		_rev_phase += dt * (1.5 + skill)
		var blip := 0.35 + 0.3 * sin(_rev_phase * 2.3 + grid_slot) if race.lights_on < 5 else 0.55
		car.ai_input = {"throttle": blip, "brake": 1.0, "steer": 0.0, "handbrake": 0.0}
		return

	var i := race.index_of(car)
	if not _lane_set:
		_lane = race.lateral_of(car) - race.line_lat[i]
		_avoid = _lane
		_lane_set = true
	# ---- speed target from the plan (a little ahead, the car needs time to react)
	# late brakers react to the speed plan a little later
	var look_brake := int(clampf(v * (0.42 - 0.14 * late_braker), 2.0, 30.0) / race.ds)
	var vt := INF
	for k in range(0, look_brake + 1, 2):
		vt = minf(vt, race.line_speed[(i + k) % n])
	vt *= skill
	# yellow flag: something happened ahead, lift through the incident zone
	if race.incident_ahead(car, 180.0):
		vt *= 0.88
	# opening seconds: everyone brakes a little earlier into turn one, like real drivers do
	if race.race_time < 30.0:
		vt *= 0.94
	# ---- traffic: overtake on the side with room, never drive into a car alongside
	var my_lat := race.lateral_of(car)
	var line_here: float = race.line_lat[(i + int(12.0 / race.ds)) % n]
	# off the start everyone keeps to their own lane and merges onto the line over ~12 s
	var want_avoid := _lane * clampf(1.0 - race.race_time / 12.0, 0.0, 1.0)
	var w_max: float = race.track.get_track_width() * 0.5 - 1.3
	var look_traffic := maxf(32.0, v * v / 16.0 + 10.0)    # far enough to stop for a wreck
	for o in race.cars:
		if o == car or race.dnf.has(o):
			continue
		var gap := race.gap_along(car, o)
		if gap < -7.0 or gap > look_traffic:
			continue
		var o_lat := race.lateral_of(o)
		var target_lat := line_here + _avoid
		var closing := v - o.linear_velocity.length()
		if gap > 3.0:
			# car ahead: if it is on our line and we are faster, pick a side
			if absf(o_lat - target_lat) < 2.6 and (closing > -1.0 or gap < 10.0):
				var left_room: bool = o_lat - 2.9 > -w_max
				var right_room: bool = o_lat + 2.9 < w_max
				var go_left: bool = left_room and (not right_room or (o_lat > line_here))
				var side_lat := (o_lat - 2.9) if go_left else (o_lat + 2.9)
				if left_room or right_room:
					want_avoid = side_lat - line_here
				# overlapping our path and closing fast: brake now, whatever the passing plan says
				var ttc := gap / maxf(closing, 0.1)
				if absf(o_lat - my_lat) < 2.3 and closing > 3.0 and ttc < 1.6:
					vt = minf(vt, o.linear_velocity.length() - 1.0)
				# no room, or about to hit it: match its speed instead
				if (not left_room and not right_room) or (gap < 9.0 and absf(o_lat - my_lat) < 2.0):
					vt = minf(vt, o.linear_velocity.length() - 0.5 + gap * (0.15 + 0.2 * aggression))
		else:
			# alongside: keep at least a car width of air
			var dl := my_lat - o_lat
			if absf(dl) < 2.4:
				want_avoid = (line_here + _avoid) - line_here + signf(dl if dl != 0.0 else 1.0) * (2.4 - absf(dl)) * 1.5
	want_avoid = _defend(want_avoid, i, v, line_here, w_max)
	want_avoid = clampf(want_avoid, -w_max - line_here, w_max - line_here)
	# feeling the car run wide (understeer): ease off until it comes back to the line
	var line_err := absf(my_lat - (race.line_lat[i] + _avoid))
	if line_err > 1.0:
		vt *= 1.0 - clampf((line_err - 1.0) * 0.06, 0.0, 0.3)
	_avoid = move_toward(_avoid, want_avoid, dt * (3.5 if absf(want_avoid) > absf(_avoid) else 1.8))

	# ---- steering: pure pursuit on the (offset) racing line
	var look := clampf(9.0 + v * 0.5, 11.0, 42.0)
	var ia := (i + int(look / race.ds)) % n
	var target: Vector3 = race.center[ia] + race.right[ia] * clampf(race.line_lat[ia] + _avoid, -w_max, w_max)
	var tp := car.global_transform.affine_inverse() * target
	var alpha := atan2(tp.x, -tp.z)
	var ld := maxf(Vector2(tp.x, tp.z).length(), 4.0)
	var delta := -atan(2.0 * Car.WHEELBASE * sin(alpha) / ld)
	var lock := Car.steer_lock(absf(car.v_fwd))
	var st := delta / lock
	# ---- slides: counter-steer and feather the throttle
	var slide := car.drift_angle
	if absf(slide) > 0.08:
		st -= slide * 1.4 / lock
	st = clampf(st, -1.0, 1.0)

	var thr := clampf((vt - v) * 0.35 + 0.05, 0.0, 1.0)
	var brk := clampf((v - vt) * 0.22, 0.0, 1.0)
	if absf(slide) > 0.12:
		thr *= clampf(1.0 - (absf(slide) - 0.12) * 4.0, 0.15, 1.0)
	if absf(st) > 0.85 and v > 25.0:
		thr *= 0.7                                          # understeer: unload the front less
	# once in a while a small error (late turn-in / early lift), so races are not a procession
	_mistake_t -= dt
	if _mistake_t <= 0.0:
		_mistake_t = randf_range(6.0, 18.0) * (0.5 + skill) * (0.6 + 0.8 * steadiness)
	elif _mistake_t < 0.35 and v > 30.0:
		thr *= 0.5
	car.ai_input = {"throttle": thr, "brake": brk, "steer": st, "handbrake": 0.0}

	# ---- recovery
	if race.phase >= RaceManager.Phase.GREEN and v < 2.0:
		_stuck_t += dt
	else:
		_stuck_t = 0.0
	if car.global_transform.basis.y.y < 0.3:
		_flip_t += dt
	else:
		_flip_t = 0.0
	# broken beyond driving: no engine, or a wheel gone -> retire
	var wrecked := car.engine_health < 0.05
	for w in car.wheels:
		if w.detached:
			wrecked = true
	if wrecked and (v < 8.0 or car.engine_health <= 0.0):
		race.retire(car)
		return
	if _stuck_t > 4.0 or _flip_t > 2.0:
		var k := race.index_of(car)
		var fwd := race.line_point(k + 2) - race.line_point(k - 2)
		car.reset_car(race.line_point(k) + Vector3(0, 0.4, 0), atan2(-fwd.x, -fwd.z))
		_stuck_t = 0.0
		_flip_t = 0.0
		_avoid = 0.0
