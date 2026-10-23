class_name ChaseCam
extends Camera3D

var target: Car
var mode := 0                      # 0 chase, 1 hood, 2 cockpit, 3 orbit, 4 top
var orbit_yaw := 0.6
var orbit_pitch := 0.35
var orbit_dist := 6.5
var _smooth_pos := Vector3.ZERO
var _initialised := false
var _yaw := 0.0                    # chase heading: lags the car, leans towards the direction of travel
var _shake := Vector3.ZERO
var _shake_t := 0.0
var _fov_s := 65.0
var _noise := FastNoiseLite.new()
# a mouse drag borrows the orbit camera; after a short pause it glides back to the driving view
const MOUSE_RETURN := 2.5
var _mouse_orbit := false
var _back_to := 0
var _idle := 0.0
var _blend_t := 0.0
var _blend_from := Transform3D()
const MODE_NAMES := ["Chase", "Hood", "Cockpit", "Orbit (mouse drag, wheel zoom)", "Top", "TV (replay)"]
const DRIVE_MODES := 5                 # V cycles these; mode 5 is driven by the replay

func cycle() -> void:
	mode = (mode + 1) % DRIVE_MODES
	_initialised = false
	_mouse_orbit = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		orbit_yaw -= event.relative.x * 0.006
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.006, -0.2, 1.4)
		_idle = 0.0
		if mode != 3 and mode != 5:
			_back_to = mode
			_mouse_orbit = true
			mode = 3
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = maxf(orbit_dist - 0.5, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = minf(orbit_dist + 0.5, 30.0)

func _process(dt: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	var fwd := -t.basis.z
	var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
	if _mouse_orbit:
		_idle += dt
		if _idle > MOUSE_RETURN and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_mouse_orbit = false
			_blend_from = global_transform
			_blend_t = 0.6
			mode = _back_to
	target.set_interior_view(mode == 2)
	match mode:
		0:
			var vel := target.linear_velocity
			var spd := vel.length()
			var car_yaw := atan2(-flat_fwd.x, -flat_fwd.z)
			var heading := car_yaw
			if spd > 4.0 and target.v_fwd > 0.0:
				# in a slide, swing round towards where the car is going, so you see the angle
				var vel_yaw := atan2(-vel.x, -vel.z)
				heading = car_yaw + angle_difference(car_yaw, vel_yaw) * 0.55
			if not _initialised:
				_yaw = heading
			_yaw += angle_difference(_yaw, heading) * (1.0 - exp(-dt * 4.0))
			var back := Vector3(sin(_yaw), 0, cos(_yaw))
			var dist := 6.6 + clampf(spd / 80.0, 0.0, 1.0) * 1.2
			var want := t.origin + back * dist + Vector3(0, 2.25, 0)
			if not _initialised:
				_smooth_pos = want
				_initialised = true
			# the heading is already smoothed; only take the edge off vertical bumps here
			_smooth_pos = Vector3(want.x, lerpf(_smooth_pos.y, want.y, 1.0 - exp(-dt * 10.0)), want.z)
			# shake: road texture at speed, plus a kick from hard bumps and kerbs
			_shake_t += dt
			var bump := clampf(absf(target.last_accel_local.y) / 40.0, 0.0, 1.0)
			var amp := 0.006 * clampf(spd / 70.0, 0.0, 1.0) + 0.05 * bump
			_shake = Vector3(_noise.get_noise_2d(_shake_t * 30.0, 0.0), _noise.get_noise_2d(0.0, _shake_t * 30.0), 0.0) * amp
			global_position = _smooth_pos + _shake
			look_at(t.origin + Vector3(0, 1.05, 0) - back * 3.0 + _shake * 0.5, Vector3.UP)
			_fov_s = lerpf(_fov_s, 62.0 + clampf(spd / 75.0, 0.0, 1.0) * 14.0, 1.0 - exp(-dt * 2.0))
			fov = _fov_s
		1:
			global_position = t * (target.cockpit_eye + Vector3(0.36, 0.03, -0.67))
			global_transform.basis = t.basis
			fov = 75.0
		2:
			# head moves with g-forces a little, like a driver against the belts
			var g := target.last_accel_local.limit_length(40.0)
			global_position = t * (target.cockpit_eye - Vector3(g.x, 0.0, g.z) * 0.0012)
			global_transform.basis = t.basis * Basis(Vector3.RIGHT, -0.04) * Basis(Vector3.FORWARD, clampf(g.x * 0.0015, -0.03, 0.03))
			fov = 72.0
		3:
			var dir := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
			global_position = t.origin + Vector3(0, 0.7, 0) + dir * orbit_dist
			look_at(t.origin + Vector3(0, 0.7, 0), Vector3.UP)
			fov = 55.0
		4:
			global_position = t.origin + Vector3(0, 18, 0.1)
			look_at(t.origin, Vector3.FORWARD)
			fov = 60.0
	if _blend_t > 0.0:
		_blend_t = maxf(_blend_t - dt, 0.0)
		var k := smoothstep(0.0, 1.0, 1.0 - _blend_t / 0.6)
		global_transform = _blend_from.interpolate_with(global_transform, k)
