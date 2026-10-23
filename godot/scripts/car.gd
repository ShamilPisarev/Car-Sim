class_name Car
extends RigidBody3D
## Front-mid V8, rear-wheel-drive GT race car (~660 hp, 1250 kg). Custom physics on top of
## Godot's (Jolt) rigid body: per-wheel spring / damper / anti-roll suspension, ray-cast tyres
## with a Pacejka-style grip model and friction circle, engine torque curve, sequential
## gearbox (auto or manual), limited-slip differential, ABS, traction control, aero downforce.
## Godot axes: x = right, y = up, forward = -z.

signal contact_impulse(local_pos: Vector3, impulse: float, normal: Vector3)

# ------------------------------------------------------------------ tuning
const MASS := 1250.0
const COM := Vector3(0.0, 0.46, 0.05)            # front-mid engine, ~48/52
const INERTIA := Vector3(2300.0, 2100.0, 520.0)  # pitch (x), yaw (y), roll (z)
const WEIGHT_FRONT := 0.48
const WHEEL_R := 0.34
const WHEEL_I := 1.6                             # wheel + tyre + drivetrain share, kg m^2
const TRAVEL := 0.24                             # full droop to full bump, m
const D_REST := 0.12                             # wheel centre below the top mount at ride height
const G := 9.81
const K_SPRING := {"F": 62000.0, "R": 56000.0}   # wheel rate, N/m
const C_BUMP := {"F": 4200.0, "R": 3800.0}       # damper, N s/m
const C_REBOUND := {"F": 7200.0, "R": 6400.0}
const K_ARB := {"F": 37000.0, "R": 26000.0}      # anti-roll bar, N/m of left-right difference
const K_BUMPSTOP := 320000.0
const SPRING_LEN := {"F": 0.26, "R": 0.24}       # modelled coil length at ride height
const ARM_LEN := 0.405
const WHEEL_X := 0.83
const WHEELBASE := 2.75
const TIRE_MU := 1.60                            # racing slick on dry asphalt (lateral)
const MU_LONG := 1.12                            # slicks grip ~12 % more in braking / traction than sideways

const GEAR_RATIOS := [3.20, 2.30, 1.75, 1.40, 1.16, 0.98]
const REVERSE_RATIO := 3.0
const FINAL_DRIVE := 3.7
const DRIVE_EFF := 0.92
const IDLE_RPM := 1100.0
const LIMITER_RPM := 8600.0
const TORQUE_CURVE := [[0.0, 0.0], [1000.0, 230.0], [2000.0, 360.0], [3000.0, 450.0], [4000.0, 520.0],
	[5000.0, 575.0], [6000.0, 610.0], [7000.0, 625.0], [7600.0, 620.0], [8200.0, 570.0],
	[8800.0, 460.0], [9300.0, 300.0]]               # Nm, ~660 hp at 7600 rpm
const BRAKE_TORQUE := {"F": 4600.0, "R": 2600.0}   # enough to reach the grip limit even with full downforce
const HANDBRAKE_TORQUE := 5200.0
const MAX_STEER := 0.62
const CD_A := 0.80                               # drag area, m^2
const CL_A := 2.6                                # downforce area, m^2 (40 % front / 60 % rear)
const RELAX_LEN := 0.35                          # tyre relaxation length: slip angle builds up over this distance, m

class Wheel:
	var tag := ""
	var axle := "F"
	var front := true
	var driven := false
	var sx := 1.0                                # +1 right, -1 left
	var anchor := Vector3.ZERO                   # top of travel, body local
	var hub: Node3D
	var steer_node: Node3D
	var wheel_node: Node3D
	var spring: Node3D
	var arm: Node3D
	var axle_shaft: Node3D
	var shaft_rest_angle := 0.0
	var shaft_rest_len := 1.0
	var hub_rest_y := 0.34
	var d := D_REST
	var d_prev := D_REST
	var omega := 0.0
	var angle := 0.0
	var pre_comp := 0.0
	var grounded := false
	var fz := 0.0
	var fx := 0.0
	var fy := 0.0
	var slip_ratio := 0.0
	var slip_angle := 0.0
	var steer := 0.0
	var contact_point := Vector3.ZERO
	var contact_normal := Vector3.UP
	var mu_surface := 1.0
	var wear := 0.0                              # tread wear 0..1
	var drag_surface := 0.0                      # extra rolling drag on loose surfaces, fraction of load
	var slide_speed := 0.0                       # contact patch sliding speed, m/s (smoke, marks, squeal)
	var grip_use := 0.0
	var abs_active := false
	var drive_torque := 0.0
	var toe_damage := 0.0                        # bent steering arm, rad
	var camber_damage := 0.0                     # bent suspension, rad
	var health := 1.0
	var punctured := false
	var detached := false

var wheels: Array[Wheel] = []
var model: Node3D
var parts: CarParts
var hull_cs: CollisionShape3D
var nose_cs: CollisionShape3D
var tail_cs: CollisionShape3D

# ---------------------------------------------------------------- state
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var steer_input := 0.0
var steer_angle := 0.0
var reverse_mode := false
var gear := 1
var manual := false
var engine_rpm := IDLE_RPM
var shift_timer := 0.0
var abs_enabled := true
var tc_enabled := true
var assist_enabled := true
var tc_active := false
var speed_kmh := 0.0
var v_fwd := 0.0
var engine_health := 1.0
var engine_temp := 90.0
var coolant := 1.0
var leak := 0.0
var on_fire := false
var drift_angle := 0.0
var ai_input := {}                               # for scripted tests: throttle, brake, steer, handbrake
var last_accel_local := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _pedal_brake: Node3D
var _pedal_gas: Node3D
var _steering_wheel: Node3D
var _tail_mats: Array[BaseMaterial3D] = []
var _engine_power_scale := 1.0
var _crush_front := 0.0
var _crush_rear := 0.0
var hold := false                                # race start: brakes on, clutch in, engine free to rev
# ---- per-model values (see CarSpecs); set spec_id before adding the car to the tree
var spec_id := "gt"
var spec: Dictionary
var mass_kg := MASS
var com := COM
var weight_front := WEIGHT_FRONT
var limiter_rpm := LIMITER_RPM
var idle_rpm := IDLE_RPM
var final_drive := FINAL_DRIVE
var boost := 0.0                                 # turbo boost 0..1 (lags the throttle)
var use_setup := false                           # your car: apply CarSetup (the AI runs the baseline)
var fuel := 0.0                                  # kg on board (only burns with CarSetup.wear_and_fuel)
var out_of_fuel := false
var speed_cap := 0.0                             # pit-lane limiter, m/s (0 = off)
var nose_len := 2.35                             # body ends from the centre, m
var tail_len := 2.33
var fx: TyreFX
static var all_cars: Array[Car] = []             # every car in the scene (slipstream)
var tow := 0.0                                   # 0..1: how much the car ahead's wake is cutting our drag
# exhaust events (sound and flames listen for changes): pops on lift-off and hard upshifts,
# a throttle blip on every downshift
var pops := 0
var blip_t := 0.0
var _prev_thr := 0.0
var _prev_gear := 1
var _pop_queue := 0
var _pop_timer := 0.0
var _since_upshift := 9.0                        # stops the auto box hunting between two gears
var _pop_gap := 0.0
var brake_temp := [80.0, 80.0, 80.0, 80.0]      # disc temperature per wheel, deg C (glow above ~450)

func _apply_spec() -> void:
	spec = CarSpecs.get_spec(spec_id)
	mass_kg = spec["mass"]
	com = Vector3(0.0, 0.46, spec["com_z"])
	# static weight split follows from where the centre of mass sits between the axles
	weight_front = (1.37 - com.z) / WHEELBASE
	limiter_rpm = spec["limiter"]
	idle_rpm = spec["idle"]
	final_drive = FINAL_DRIVE * limiter_rpm / LIMITER_RPM     # same road speed at the limiter in every gear
	if use_setup:
		final_drive *= CarSetup.final_drive_scale()
	nose_len = spec["nose"]
	tail_len = spec["tail"]
	engine_rpm = idle_rpm

func _enter_tree() -> void:
	if not all_cars.has(self):
		all_cars.append(self)

func _exit_tree() -> void:
	all_cars.erase(self)

func _slipstream() -> float:
	## the wake of a car ahead: much less drag when tucked in close behind it (fading out by
	## ~40 m and with a sideways offset), measured in this car's frame
	var best := 0.0
	var b := global_transform.basis
	var spd := linear_velocity.length()
	if spd < 15.0:
		return 0.0
	for o in all_cars:
		if o == self or not o.visible:
			continue
		var rel := b.inverse() * (o.global_position - global_position)
		var ahead := -rel.z
		if ahead < 4.0 or ahead > 40.0:
			continue
		var side := absf(rel.x)
		if side > 2.6:
			continue
		var f := (1.0 - (ahead - 4.0) / 36.0) * (1.0 - side / 2.6)
		best = maxf(best, f)
	return best

func _ready() -> void:
	_apply_spec()
	mass = mass_kg
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com
	inertia = spec["inertia"]
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.05
	contact_monitor = true
	max_contacts_reported = 16
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	_load_model()
	_find_cockpit()
	_build_collision()
	_setup_wheels()
	parts = CarParts.new()
	parts.name = "Parts"
	add_child(parts)
	parts.setup(self)
	fx = TyreFX.new()
	fx.name = "TyreFX"
	add_child(fx)
	fx.setup(self)

func _load_model() -> void:
	var ps: PackedScene = load(spec["glb"])
	model = ps.instantiate()
	model.name = "Model"
	add_child(model)
	_pedal_brake = model.find_child("Pedal_Brake", true, false)
	_pedal_gas = model.find_child("Pedal_Gas", true, false)
	_steering_wheel = model.find_child("SteeringWheel", true, false)
	# glossy clear-coated paint, vertex colour used for scraped paint after a crash
	var seen := {}
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mt := mi.mesh.surface_get_material(s)
			if mt is BaseMaterial3D and not seen.has(mt):
				seen[mt] = true
				var bm := mt as BaseMaterial3D
				bm.vertex_color_use_as_albedo = true
				if bm.resource_name == "paint":
					bm.clearcoat_enabled = true
					bm.clearcoat = 1.0
					bm.clearcoat_roughness = 0.04
					bm.metallic = 0.45
					bm.roughness = 0.28
				elif bm.resource_name == "glass":
					bm.roughness = 0.03
					bm.metallic = 0.2
				elif bm.resource_name == "ledred" or bm.resource_name == "tail":
					_tail_mats.append(bm)
	for tm in _tail_mats:
		if tm.emission_enabled:
			tm.emission_energy_multiplier = 0.5

var cockpit_eye := Vector3(-0.36, 1.18, 0.12)   # driver's eye point, car local

func _find_cockpit() -> void:
	## the driver's eyes: about 60 cm behind the steering wheel hub and 20 cm above it
	var tilt := model.find_child("SteeringTilt", true, false) as Node3D
	if tilt != null:
		cockpit_eye = to_local(tilt.global_position) + spec.get("eye", Vector3(0.02, 0.13, 0.42))

var _interior_view := false
var _cabin_light: OmniLight3D

func set_interior_view(on: bool) -> void:
	## seen from the driver's seat the windscreen glass is hidden (from inside its reflections
	## only wash the picture out); from outside it stays
	if on == _interior_view:
		return
	_interior_view = on
	# a soft fill light in the cabin: without it the dark interiors read as black holes
	if _cabin_light == null:
		_cabin_light = OmniLight3D.new()
		_cabin_light.light_energy = 0.55
		_cabin_light.omni_range = 1.6
		_cabin_light.omni_attenuation = 1.2
		_cabin_light.light_color = Color(1.0, 0.96, 0.9)
		_cabin_light.shadow_enabled = false
		_cabin_light.light_specular = 0.1
		add_child(_cabin_light)
		_cabin_light.position = cockpit_eye + Vector3(0.0, -0.05, -0.35)
	_cabin_light.visible = on
	for nm in ["Windshield", "Window_FL", "Window_FR"]:
		var n := model.find_child(nm, true, false) as Node3D
		if n != null and not parts.gone.has(nm):
			n.visible = not on

func _build_collision() -> void:
	# boxes follow the body: overhangs, cabin length and roof height differ per model
	var hf := nose_len - 0.45
	var hr := tail_len - 0.43
	var roof: float = spec["roof"]
	var cab: Array = spec["cab"]
	var defs := [
		["Hull", Vector3(1.90, 0.48, hf + hr), Vector3(0, 0.50, (hr - hf) * 0.5)],
		["Cabin", Vector3(1.45, roof - 0.875, cab[1] - cab[0] - 0.05), Vector3(0, (0.81 + roof - 0.065) * 0.5, (cab[0] + cab[1]) * 0.5)],
		["Nose", Vector3(1.66, 0.30, 0.50), Vector3(0, 0.45, -(nose_len - 0.30))],
		["Tail", Vector3(1.70, 0.34, 0.45), Vector3(0, 0.50, tail_len - 0.28)],
	]
	for d in defs:
		var cs := CollisionShape3D.new()
		cs.name = d[0]
		var bs := BoxShape3D.new()
		bs.size = d[1]
		cs.shape = bs
		cs.position = d[2]
		add_child(cs)
		match d[0]:
			"Hull": hull_cs = cs
			"Nose": nose_cs = cs
			"Tail": tail_cs = cs

func apply_crush(front: float, rear: float) -> void:
	## shorten the collision hull as the nose / tail are pushed in
	_crush_front = maxf(_crush_front, front)
	_crush_rear = maxf(_crush_rear, rear)
	var nose_len_c := maxf(0.50 - _crush_front, 0.04)
	(nose_cs.shape as BoxShape3D).size.z = nose_len_c
	var hf := -(nose_len - 0.45)
	var hr := tail_len - 0.43
	nose_cs.position.z = hf - 0.40 + _crush_front + nose_len_c * 0.5 if _crush_front < 0.46 else hf
	var hull_front := hf + maxf(_crush_front - 0.46, 0.0)
	var tail_len_c := maxf(0.45 - _crush_rear, 0.04)
	(tail_cs.shape as BoxShape3D).size.z = tail_len_c
	tail_cs.position.z = hr + 0.40 - _crush_rear - tail_len_c * 0.5 if _crush_rear < 0.41 else hr
	var hull_rear := hr - maxf(_crush_rear - 0.41, 0.0)
	(hull_cs.shape as BoxShape3D).size.z = hull_rear - hull_front
	hull_cs.position.z = (hull_front + hull_rear) * 0.5

func reset_crush() -> void:
	_crush_front = 0.0
	_crush_rear = 0.0
	apply_crush(0.0, 0.0)

func _find(n: String) -> Node3D:
	return model.find_child(n, true, false) as Node3D

func _setup_wheels() -> void:
	for tag in ["FL", "FR", "RL", "RR"]:
		var w := Wheel.new()
		w.tag = tag
		w.front = tag[0] == "F"
		w.driven = not w.front
		w.axle = tag[0]
		w.sx = -1.0 if tag[1] == "L" else 1.0
		w.hub = _find("Hub_" + tag)
		w.steer_node = _find("Steer_" + tag)
		w.wheel_node = _find("Wheel_" + tag)
		w.spring = _find("Spring_" + tag)
		w.arm = _find("Arm_" + tag)
		w.axle_shaft = _find("Axle_" + tag)
		w.hub_rest_y = w.hub.position.y
		w.anchor = Vector3(w.hub.position.x, w.hub.position.y + D_REST, w.hub.position.z)
		if w.axle_shaft:
			var inner := w.axle_shaft.position
			var outer := Vector3(w.sx * (WHEEL_X - 0.10), WHEEL_R, w.hub.position.z)
			var delta := outer - inner
			w.shaft_rest_angle = atan2(delta.y, absf(delta.x))
			w.shaft_rest_len = Vector2(delta.x, delta.y).length()
		var static_load := mass_kg * G * (weight_front if w.front else 1.0 - weight_front) * 0.5
		w.pre_comp = static_load / _k_spring(w.axle) - (TRAVEL - D_REST)
		wheels.append(w)

# ------------------------------------------------------------------ input
func _read_input(dt: float) -> void:
	var t := 0.0
	var b := 0.0
	var s := 0.0
	var hb := 0.0
	var analog_steer := false
	if ai_input.size() > 0:
		t = ai_input.get("throttle", 0.0)
		b = ai_input.get("brake", 0.0)
		s = ai_input.get("steer", 0.0)
		hb = ai_input.get("handbrake", 0.0)
	else:
		var up := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		var down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		var left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
		var right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
		s = (1.0 if left else 0.0) - (1.0 if right else 0.0)
		hb = 1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0
		var pad_t := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
		var pad_b := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		var pad_s := -Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		if absf(pad_s) > 0.08:
			# progressive curve: fine control round the centre, full lock at the end of travel
			var x := (absf(pad_s) - 0.08) / 0.92
			s = signf(pad_s) * pow(x, 1.5)
			analog_steer = true
		if Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_X):
			hb = 1.0
		var up_v := maxf(1.0 if up else 0.0, pad_t)
		var down_v := maxf(1.0 if down else 0.0, pad_b)
		if reverse_mode:
			t = down_v
			b = up_v
		else:
			t = up_v
			b = down_v
		# switch between forward and reverse when (almost) stopped
		if not reverse_mode and down_v > 0.1 and up_v < 0.1 and v_fwd < 0.6:
			reverse_mode = true
		elif reverse_mode and up_v > 0.1 and down_v < 0.1 and v_fwd > -0.6:
			reverse_mode = false
	throttle = move_toward(throttle, t, dt * 6.0)
	brake = move_toward(brake, b, dt * 11.0)
	handbrake = move_toward(handbrake, hb, dt * 14.0)
	# speed sensitive steering lock
	var spd := absf(v_fwd)
	var lock := steer_lock(spd)
	if analog_steer or ai_input.size() > 0:
		steer_input = move_toward(steer_input, s, dt * 6.0)
	else:
		# keyboard: ramp in slowly, come back quickly
		var rate := 5.0 if absf(s) > absf(steer_input) or signf(s) != signf(steer_input) else 7.0
		steer_input = move_toward(steer_input, s, dt * rate)
	var target := steer_input * lock
	# counter-steer assist: point the front wheels along the direction of travel when sliding
	drift_angle = 0.0
	if v_fwd > 3.0:
		var v_local := global_transform.basis.inverse() * linear_velocity
		drift_angle = atan2(v_local.x, maxf(-v_local.z, 1.0))
		if assist_enabled and ai_input.size() == 0:
			var k := smoothstep(5.0, 14.0, v_fwd) * (1.0 - 0.6 * absf(steer_input))
			# only a real slide (over ~5 deg) gets help; normal cornering slip is left alone
			var excess := signf(drift_angle) * maxf(absf(drift_angle) - 0.09, 0.0)
			target += clampf(-excess * 1.05, -0.5, 0.5) * k
	steer_angle = move_toward(steer_angle, clampf(target, -MAX_STEER, MAX_STEER), dt * 5.0)

static func steer_lock(speed: float) -> float:
	## full-lock road-wheel angle for a speed: the angle a ~1.5 g corner needs (wheelbase / radius)
	## plus the tyre's peak slip angle. Past that the front only scrubs, so more lock is no use.
	return clampf(WHEELBASE * 15.0 / maxf(speed * speed, 1.0) + 0.16, 0.16, MAX_STEER)

func shift(dir: int) -> void:
	if reverse_mode:
		return
	var g := clampi(gear + dir, 1, 6)
	if g != gear:
		gear = g
		manual = true
		shift_timer = 0.18

# ----------------------------------------------------------------- engine
func _torque_at(rpm: float) -> float:
	var c: Array = spec["torque"]
	if rpm <= c[0][0]:
		return c[0][1]
	for i in range(1, c.size()):
		if rpm <= c[i][0]:
			var t: float = (rpm - c[i - 1][0]) / (c[i][0] - c[i - 1][0])
			return lerpf(c[i - 1][1], c[i][1], t)
	return c[c.size() - 1][1]

func _gear_ratio(g: int) -> float:
	if reverse_mode:
		return -REVERSE_RATIO * final_drive
	return GEAR_RATIOS[clampi(g, 1, 6) - 1] * final_drive

func _update_engine_thermal(dt: float) -> void:
	if spec["turbo"]:
		var want := throttle * clampf((engine_rpm - 2200.0) / 2600.0, 0.0, 1.0)
		boost = move_toward(boost, want, dt * (1.6 if want > boost else 4.0))
	var load_f := throttle * (engine_rpm / limiter_rpm)
	# the engine copes with some coolant loss; it is the last half that makes it boil
	var lost := 1.0 - coolant
	var target := 92.0 + 22.0 * load_f + lost * lost * 150.0
	var rate := (2.2 if target > engine_temp else 1.0) * (absf(target - engine_temp) / 25.0 + 0.15)
	engine_temp = move_toward(engine_temp, target, dt * rate)
	coolant = maxf(coolant - leak * dt, 0.0)
	if engine_temp > 148.0:
		engine_health = maxf(engine_health - dt * 0.12, 0.0)
	if on_fire:
		engine_health = maxf(engine_health - dt * 0.04, 0.0)

func _update_drivetrain(dt: float) -> float:
	## returns total torque at the driven (rear) wheels
	var w_avg := 0.0
	var nd := 0
	for w in wheels:
		if w.driven and not w.detached:
			w_avg += w.omega
			nd += 1
	if nd > 0:
		w_avg /= nd
	var ratio := _gear_ratio(gear)
	var rpm_w := w_avg * ratio * 60.0 / TAU
	if hold:
		# clutch in on the grid: the engine revs freely against its own inertia
		var free_rpm := idle_rpm + throttle * (limiter_rpm - idle_rpm - 400.0)
		engine_rpm = move_toward(engine_rpm, free_rpm, dt * (14000.0 if free_rpm > engine_rpm else 7000.0))
		return 0.0
	var launch_floor := idle_rpm + throttle * 3600.0
	var target_rpm := maxf(rpm_w, idle_rpm)
	if gear == 1 or reverse_mode:
		target_rpm = maxf(target_rpm, launch_floor if throttle > 0.05 else idle_rpm)
	var rev_rate := 16000.0 if target_rpm > engine_rpm else 9000.0
	engine_rpm = move_toward(engine_rpm, target_rpm, dt * rev_rate)
	# automatic gearbox (sequential): aggressive shift points
	shift_timer = maxf(shift_timer - dt, 0.0)
	if not reverse_mode and not manual and shift_timer <= 0.0:
		var rs := limiter_rpm / LIMITER_RPM                # shift points scale with the rev range
		var up_rpm := (5200.0 + 3100.0 * throttle) * rs
		var down_rpm := (2800.0 + 1400.0 * throttle) * rs
		# a real box will not short-shift while the rears are lit up in a drift / burnout
		var spinning := false
		for w in wheels:
			if w.driven and w.grounded and w.slip_ratio > 0.18:
				spinning = true
		if spinning and engine_rpm < limiter_rpm - 250.0:
			up_rpm = limiter_rpm - 250.0
		if engine_rpm > up_rpm and gear < 6 and rpm_w > 0.0:
			gear += 1
			shift_timer = 0.16
		elif gear > 1 and rpm_w < down_rpm and (_since_upshift > 1.0 or throttle < 0.5 or rpm_w < limiter_rpm * 0.5) and rpm_w * (GEAR_RATIOS[gear - 2] / GEAR_RATIOS[gear - 1]) < limiter_rpm * 0.85:
			gear -= 1
			shift_timer = 0.14
	elif manual and gear > 1 and not reverse_mode and rpm_w < 1700.0 and throttle < 0.1:
		pass
	var temp_factor := 1.0 - clampf((engine_temp - 118.0) / 30.0, 0.0, 1.0) * 0.8
	var torque := 0.0
	var cut := 1.0 if shift_timer < 0.06 else 0.0
	if throttle > 0.02:
		torque = _torque_at(engine_rpm) * throttle * _engine_power_scale * temp_factor * CarSpecs.power_factor()
		if out_of_fuel and CarSetup.wear_and_fuel:
			torque = 0.0
		if speed_cap > 0.0 and v_fwd > speed_cap:
			torque = 0.0
		if spec["turbo"]:
			# turbo: full torque only once the boost has built up (lag on every throttle stab)
			torque *= 0.55 + 0.45 * boost
		if engine_rpm >= limiter_rpm:
			torque = 0.0
	else:
		torque = -(30.0 + 0.012 * engine_rpm) * clampf(rpm_w / 2500.0, 0.0, 1.0)   # engine braking
	return torque * ratio * DRIVE_EFF * (cut if torque > 0.0 else 1.0)

func _split_drive_torque(total: float) -> void:
	## traction control, then a 2-way limited-slip differential to the rear wheels
	var left: Wheel = null
	var right: Wheel = null
	for w in wheels:
		w.drive_torque = 0.0
		if w.driven and not w.detached:
			if w.sx < 0.0:
				left = w
			else:
				right = w
	tc_active = false
	if left == null and right == null:
		return
	var t_in := total
	if tc_enabled and total > 0.0:
		var worst := 0.0
		for w in [left, right]:
			if w != null:
				worst = maxf(worst, w.slip_ratio)
		if worst > 0.22:
			t_in *= clampf(1.0 - (worst - 0.22) * 4.0, 0.15, 1.0)
			tc_active = true
	if left == null or right == null:
		(left if left != null else right).drive_torque = t_in
		return
	var dw := right.omega - left.omega
	var lock := 0.55 if t_in > 0.0 else 0.35
	var limit := lock * absf(t_in) * 0.5 + 140.0
	var transfer := clampf(160.0 * signf(dw) + 110.0 * dw, -limit, limit)
	left.drive_torque = t_in * 0.5 + transfer
	right.drive_torque = t_in * 0.5 - transfer

# ------------------------------------------------------------------ tyres
func _magic(x: float, b: float, c: float, e: float) -> float:
	var bx := b * x
	return sin(c * atan(bx - e * (bx - atan(bx))))

func _long_force(kappa: float, dmax: float) -> float:
	return dmax * _magic(kappa, 13.0, 1.5, 0.0)

func _lat_force(alpha: float, dmax: float) -> float:
	return dmax * _magic(alpha, 11.0, 1.40, -0.8)

func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	var basis_b := global_transform.basis
	var vel := linear_velocity
	v_fwd = vel.dot(-basis_b.z)
	speed_kmh = vel.length() * 3.6
	_read_input(dt)
	_stability(dt)
	_update_engine_thermal(dt)
	_exhaust_events(dt)
	_wear_and_fuel(dt)
	if use_setup:
		_rumble(dt)
	var drive_total := _update_drivetrain(dt)
	_split_drive_torque(drive_total)

	# --- ray casts and suspension geometry
	var space := get_world_3d().direct_space_state
	var up_b := basis_b.y
	for w in wheels:
		if w.detached:
			w.grounded = false
			w.fz = 0.0
			w.d = move_toward(w.d, TRAVEL, dt * 1.5)
			continue
		var from := global_transform * w.anchor
		var to := from - up_b * (TRAVEL + WHEEL_R + 0.01)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		w.d_prev = w.d
		if hit.size() > 0:
			var dist: float = from.distance_to(hit.position)
			w.d = clampf(dist - WHEEL_R, -0.05, TRAVEL)
			w.grounded = true
			w.contact_point = hit.position
			w.contact_normal = hit.normal
			var col = hit.collider
			w.mu_surface = col.get_meta("mu") if col != null and col.has_meta("mu") else 1.0
			# loose surfaces: gravel traps bleed speed fast, grass a little
			w.drag_surface = 0.0 if w.mu_surface > 0.9 else (0.22 if w.mu_surface < 0.5 else 0.07)
		else:
			w.d = move_toward(w.d, TRAVEL, dt * 1.5)
			w.grounded = false
			w.fz = 0.0
	# --- anti-roll bars
	var arb := {"F": 0.0, "R": 0.0}
	for ax in ["F", "R"]:
		var l: Wheel = null
		var r: Wheel = null
		for w in wheels:
			if w.axle == ax:
				if w.sx < 0.0:
					l = w
				else:
					r = w
		arb[ax] = _k_arb(ax) * ((D_REST - l.d) - (D_REST - r.d))
	# --- forces
	var com_g := global_transform * com
	var brake_pedal := 1.0 if hold else brake
	for w in wheels:
		if w.detached:
			continue
		if not w.grounded:
			var tb := _brake_torque(w, brake_pedal)
			w.omega += w.drive_torque / WHEEL_I * dt
			w.omega = _apply_brake_to_omega(w.omega, tb, dt)
			w.omega *= (1.0 - 0.15 * dt)
			w.slip_ratio = 0.0
			w.slip_angle = 0.0
			w.slide_speed = 0.0
			w.fx = 0.0
			w.fy = 0.0
			w.grip_use = 0.0
			continue
		# spring / damper / bump stop along the suspension axis
		var comp := (TRAVEL - w.d) + w.pre_comp
		var f_spring: float = _k_spring(w.axle) * comp
		var vel_c := (w.d_prev - w.d) / dt
		var f_damp: float = (C_BUMP[w.axle] if vel_c > 0.0 else C_REBOUND[w.axle]) * vel_c
		var f_stop: float = K_BUMPSTOP * maxf(-w.d, 0.0)
		var sign_arb := 1.0 if w.sx < 0.0 else -1.0
		var fz := maxf(f_spring + f_damp + f_stop + sign_arb * arb[w.axle], 0.0)
		w.fz = fz
		var n := w.contact_normal
		var offset := w.contact_point - global_position
		apply_force(up_b * fz, offset)

		# wheel frame on the ground plane
		var steer_a := (w.steer if w.front else 0.0) + w.toe_damage
		var fwd_w := (basis_b * Basis(Vector3.UP, steer_a)) * Vector3(0, 0, -1)
		fwd_w = (fwd_w - n * fwd_w.dot(n)).normalized()
		var right_w := fwd_w.cross(n).normalized()
		var vp := vel + angular_velocity.cross(w.contact_point - com_g)
		var v_long := vp.dot(fwd_w)
		var v_lat := vp.dot(right_w)

		var mu := clampf(w.mu_surface * TIRE_MU * (1.03 - 0.00004 * (fz - 3000.0)), 0.2, 1.7) * CarSpecs.grip_factor() * Weather.grip()
		mu *= 1.0 - 0.3 * w.wear                   # worn tyres lose up to 30 % grip
		if w.punctured:
			mu *= 0.55
		var dmax := mu * fz * clampf(n.dot(up_b), 0.3, 1.0)
		var dmax_x := dmax * MU_LONG

		var t_drive := w.drive_torque
		var t_brake := _brake_torque(w, brake_pedal)
		w.abs_active = false
		# ABS: hold the tyre near its peak slip (~11 %) instead of dumping the pressure
		var lock_slip := -w.slip_ratio * signf(v_long)
		if abs_enabled and t_brake > 0.0 and absf(v_long) > 2.0 and handbrake < 0.3 and lock_slip > 0.12:
			t_brake *= clampf(1.0 - (lock_slip - 0.12) * 12.0, 0.2, 1.0)
			w.abs_active = true

		# --- longitudinal: implicit wheel integration so it stays stable at any slip stiffness
		var vref := maxf(absf(v_long), 2.0)
		var s0 := w.omega * WHEEL_R - v_long
		var fx0 := _long_force(s0 / vref, dmax_x)
		var kx := maxf((_long_force((s0 + 0.2) / vref, dmax_x) - fx0) / 0.2, 0.0)
		var domega := dt / WHEEL_I * (t_drive - WHEEL_R * fx0) / (1.0 + dt * WHEEL_R * WHEEL_R * kx / WHEEL_I)
		w.omega += domega
		w.omega = _apply_brake_to_omega(w.omega, t_brake, dt)
		var s1 := w.omega * WHEEL_R - v_long
		w.slip_ratio = s1 / vref
		var fx := _long_force(w.slip_ratio, dmax_x)
		fx -= (0.012 + w.drag_surface) * fz * signf(v_long) * clampf(absf(v_long) / 0.5, 0.0, 1.0)   # rolling resistance
		# --- lateral: the carcass needs to roll a short distance before the slip angle builds up
		var alpha_ss := atan2(v_lat, maxf(absf(v_long), 1.0))
		var relax := clampf(Vector2(v_long, v_lat).length() * dt / RELAX_LEN, 0.05, 1.0)
		w.slip_angle += (alpha_ss - w.slip_angle) * relax
		w.slide_speed = Vector2(s1, v_lat).length()
		var fy_pac := -_lat_force(w.slip_angle, dmax)
		var fy_stop := -v_lat * (mass_kg * 0.25) * 0.5 / dt
		var blend := smoothstep(1.0, 3.5, absf(v_long))
		var fy := lerpf(fy_stop, fy_pac, blend)
		# friction ellipse: a tyre braking hard has less left for cornering, and vice versa
		var use := Vector2(fx / maxf(dmax_x, 1.0), fy / maxf(dmax, 1.0)).length()
		w.grip_use = use
		if use > 1.0:
			fx /= use
			fy /= use
		w.fx = fx
		w.fy = fy
		apply_force(fwd_w * fx + right_w * fy, offset)

	# --- aerodynamics: drag, plus downforce split between the axles
	var v2 := vel.length()
	if v2 > 0.1:
		var df := CarSetup.downforce_scale() if use_setup else 1.0
		var dr := CarSetup.drag_scale() if use_setup else 1.0
		# slipstream: up to 35 % less drag in the tow; very close behind, the dirty air also
		# costs some downforce (harder to follow through fast corners)
		tow = lerpf(tow, _slipstream(), 0.1)
		dr *= 1.0 - 0.35 * tow
		df *= 1.0 - 0.15 * clampf((tow - 0.6) / 0.4, 0.0, 1.0)
		apply_central_force(-vel.normalized() * 0.5 * 1.2 * CD_A * dr * v2 * v2)
		var down := 0.5 * 1.2 * CL_A * df * v2 * v2 * clampf(v_fwd / maxf(v2, 0.1), 0.0, 1.0)
		# the wing sits at the back: more wing angle moves the aero balance rearwards
		var rear_share := clampf(0.60 + 0.25 * (df - 1.0), 0.45, 0.75)
		apply_force(-up_b * down * (1.0 - rear_share), global_transform.basis * Vector3(0, 0.3, -1.38))
		apply_force(-up_b * down * rear_share, global_transform.basis * Vector3(0, 0.5, 1.37))
	last_accel_local = global_transform.basis.inverse() * ((vel - _prev_vel) / dt)
	_prev_vel = vel
	parts.step(dt)

const LIVERY_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// recolours the stock livery: blue base, orange accents and white stripes are swapped for team colours
uniform sampler2D livery : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 base_col : source_color;
uniform vec3 accent_col : source_color;
uniform vec3 stripe_col : source_color;
uniform float stripes = 1.0;        // 0: no racing stripes (the number roundels stay)
uniform float two_tone = 0.0;       // 1: lower body sides in the accent colour
void fragment() {
	vec3 c = texture(livery, UV).rgb;
	float w_white = smoothstep(0.55, 0.75, min(c.r, min(c.g, c.b)));
	float w_orange = smoothstep(0.15, 0.35, c.r - c.b) * (1.0 - w_white);
	float w_blue = smoothstep(0.03, 0.12, c.b - c.r) * (1.0 - w_white) * (1.0 - w_orange);
	vec3 o = c;
	o = mix(o, base_col, w_blue);
	o = mix(o, accent_col, w_orange);
	// the white number roundels (door sides, bonnet, roof) stay even without stripes
	vec2 u = UV;
	float roundel = 0.0;
	if (u.y < 0.5) {
		roundel = 1.0 - step(1.0, length((u - vec2(0.5, 0.221)) / vec2(0.055, 0.095)));
	} else {
		roundel = max(1.0 - step(1.0, length((u - vec2(0.5, 0.885)) / vec2(0.14, 0.032))),
			1.0 - step(1.0, length((u - vec2(0.5, 0.72)) / vec2(0.14, 0.032))));
	}
	float keep = max(stripes, roundel);
	o = mix(o, mix(base_col, mix(stripe_col, vec3(0.95), roundel), keep), w_white);
	if (two_tone > 0.5 && u.y < 0.5) {
		float zs = u.y * 2.8;
		float band = smoothstep(0.36, 0.38, zs) * (1.0 - smoothstep(0.58, 0.60, zs));
		o = mix(o, accent_col, band * (1.0 - roundel) * (1.0 - w_white * stripes));
	}
	ALBEDO = o * COLOR.rgb;
	METALLIC = 0.45;
	ROUGHNESS = 0.28;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;
}
"""

func set_livery(base: Color, accent: Color, stripe: Color, with_stripes := true, two_tone := false) -> void:
	## give this car its own team colours (the shared stock paint material stays untouched)
	var sh := Shader.new()
	sh.code = LIVERY_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("base_col", base)
	sm.set_shader_parameter("accent_col", accent)
	sm.set_shader_parameter("stripe_col", stripe)
	sm.set_shader_parameter("stripes", 1.0 if with_stripes else 0.0)
	sm.set_shader_parameter("two_tone", 1.0 if two_tone else 0.0)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var mt := mi.mesh.surface_get_material(si)
			if mt is BaseMaterial3D and mt.resource_name == "paint":
				sm.set_shader_parameter("livery", (mt as BaseMaterial3D).albedo_texture)
				mi.set_surface_override_material(si, sm)

func _stability(_dt: float) -> void:
	## arcade only: stability control. Past ~11 deg of slide it trims the throttle and damps the
	## yaw, so a twitch turns into a recoverable slide instead of a spin. Handbrake disables it,
	## so you can still throw the car into a drift on purpose.
	if not CarSpecs.arcade or handbrake > 0.1 or v_fwd < 8.0:
		return
	var excess := absf(drift_angle) - 0.20
	if excess <= 0.0:
		return
	var k := clampf(excess * 4.0, 0.0, 1.0)
	throttle *= clampf(1.0 - excess * 3.0, 0.3, 1.0)
	var up := global_transform.basis.y
	var yaw_rate := angular_velocity.dot(up)
	apply_torque(-up * yaw_rate * inertia.y * 3.0 * k)

var _lights_on := false
var _beams: Array[SpotLight3D] = []

func set_headlights(on: bool, shadows: bool) -> void:
	## dipped-beam spots from both headlamps, lit lamp glass, brighter tail lights
	_lights_on = on
	if _beams.is_empty() and on:
		for side in ["L", "R"]:
			var lamp := model.find_child("Headlight_" + side, true, false) as Node3D
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.95, 0.86)
			sp.spot_range = 95.0
			sp.spot_angle = 24.0
			sp.spot_attenuation = 0.6
			sp.light_energy = 7.0
			sp.light_specular = 0.6
			add_child(sp)
			var p := Vector3(0.64 * (-1.0 if side == "L" else 1.0), 0.62, -(nose_len - 0.2))
			if lamp != null:
				var mi := lamp.find_children("*", "MeshInstance3D", true, false)
				var src: Node3D = mi[0] if mi.size() > 0 else lamp
				if src is MeshInstance3D and (src as MeshInstance3D).mesh != null:
					p = to_local(src.global_transform * (src as MeshInstance3D).mesh.get_aabb().get_center())
				else:
					p = to_local(lamp.global_position)
			sp.position = p + Vector3(0, 0, -0.05)
			sp.rotation = Vector3(deg_to_rad(-3.5), 0.0, 0.0)          # dipped slightly towards the road
			_beams.append(sp)
	for b in _beams:
		b.visible = on
		b.shadow_enabled = shadows
	for nm in ["Headlight_L", "Headlight_R"]:
		var lamp := model.find_child(nm, true, false)
		if lamp == null:
			continue
		for m in lamp.find_children("*", "MeshInstance3D", true, false) + ([lamp] if lamp is MeshInstance3D else []):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var mt := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if mt != null and (mt.resource_name == "lamp" or mt.resource_name == "ledwhite"):
					mt.emission_enabled = true
					mt.emission = Color(1.0, 0.95, 0.85)
					mt.emission_energy_multiplier = 6.0 if on else (1.0 if mt.resource_name == "ledwhite" else 0.0)

var _rumble_t := 0.0
var _impact_rumble := 0.0

func _rumble(dt: float) -> void:
	## gamepad feedback: kerbs and loose ground buzz, sliding tyres hum, impacts thump
	if Input.get_connected_joypads().is_empty():
		return
	_impact_rumble = maxf(_impact_rumble - dt * 3.0, 0.0)
	_rumble_t -= dt
	if _rumble_t > 0.0:
		return
	_rumble_t = 0.05
	var weak := 0.0
	for w in wheels:
		if not w.grounded:
			continue
		if absf(w.mu_surface - 0.95) < 0.01:
			weak = maxf(weak, 0.55)                           # kerb
		elif w.mu_surface < 0.9:
			weak = maxf(weak, clampf(linear_velocity.length() / 30.0, 0.0, 0.45))
		weak = maxf(weak, clampf((w.slide_speed - 2.0) / 10.0, 0.0, 0.6))
	var strong := _impact_rumble
	if weak > 0.02 or strong > 0.02:
		Input.start_joy_vibration(0, weak, strong, 0.08)

func _pop() -> void:
	if _pop_gap <= 0.0:
		pops += 1
		_pop_gap = 0.3

func _exhaust_events(dt: float) -> void:
	_since_upshift += dt
	_pop_gap = maxf(_pop_gap - dt, 0.0)
	if gear < _prev_gear and not reverse_mode:
		blip_t = 0.18                                     # rev-matching blip on the way down
		if throttle < 0.2 and engine_rpm > limiter_rpm * 0.5 and randf() < 0.65:
			_pop()                                        # downshift into a braking zone
	elif gear > _prev_gear:
		_since_upshift = 0.0
		if engine_rpm > limiter_rpm * 0.82 and throttle > 0.8:
			_pop()                                        # flat-out upshift: one bang
	_prev_gear = gear
	blip_t = maxf(blip_t - dt, 0.0)
	# lift off at high revs: unburnt fuel fires in the hot exhaust a few times
	if _prev_thr > 0.6 and throttle < 0.2 and engine_rpm > limiter_rpm * 0.6:
		_pop_queue = randi_range(2, 5)
		_pop_timer = randf_range(0.04, 0.12)
	_prev_thr = throttle
	if _pop_queue > 0:
		if throttle > 0.4:
			_pop_queue = 0
		else:
			_pop_timer -= dt
			if _pop_timer <= 0.0:
				_pop()
				_pop_queue -= 1
				_pop_timer = randf_range(0.07, 0.2)
	# brake discs: heat from braking work, cooled by the air flowing past
	var spd := linear_velocity.length()
	for k in wheels.size():
		var w: Wheel = wheels[k]
		var heat := _brake_torque(w, brake) * absf(w.omega) * 0.0016 * dt
		brake_temp[k] = maxf(brake_temp[k] + heat - (brake_temp[k] - 60.0) * (0.08 + spd * 0.004) * dt, 60.0)

func apply_setup() -> void:
	## re-read CarSetup (gearing, spring preload) after it was changed in the menu
	_apply_spec()
	for w in wheels:
		var static_load := mass_kg * G * (weight_front if w.front else 1.0 - weight_front) * 0.5
		w.pre_comp = static_load / _k_spring(w.axle) - (TRAVEL - D_REST)

func _k_spring(axle: String) -> float:
	return K_SPRING[axle] * (CarSetup.spring_scale() if use_setup else 1.0)

func _k_arb(axle: String) -> float:
	return K_ARB[axle] * (CarSetup.arb_scale(axle == "F") if use_setup else 1.0)

func _wear_and_fuel(dt: float) -> void:
	## tyres wear with load and sliding; fuel burns with throttle and revs and its weight counts
	if not CarSetup.wear_and_fuel:
		return
	var spd := linear_velocity.length()
	for w in wheels:
		if w.grounded:
			w.wear = minf(w.wear + (w.grip_use * w.grip_use * spd * 2.5e-5 + w.slide_speed * 5e-5) * dt, 1.0)
	fuel = maxf(fuel - (0.004 + 0.05 * throttle * engine_rpm / limiter_rpm) * dt, 0.0)
	out_of_fuel = fuel <= 0.0
	mass = mass_kg + fuel

func service(tyres: bool, fuel_kg: float, repair: bool) -> void:
	## pit stop work
	if tyres:
		for w in wheels:
			w.wear = 0.0
	fuel = maxf(fuel, fuel_kg)
	mass = mass_kg + (fuel if CarSetup.wear_and_fuel else 0.0)
	if repair:
		parts.repair()
		reset_crush()

func set_race_number(num: int) -> void:
	## replace the modelled "7" on the doors and bonnet with this car's own number
	for nm in ["Number_L", "Number_R", "Number_Hood"]:
		var mi := model.find_child(nm, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var centre: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
		mi.visible = false
		var lb := Label3D.new()
		lb.text = str(num)
		lb.font_size = 96
		lb.pixel_size = 0.0034 if nm != "Number_Hood" else 0.0038
		lb.modulate = Color(0.04, 0.04, 0.05)
		lb.outline_size = 0
		lb.double_sided = false
		mi.get_parent().add_child(lb)
		var b := global_transform.basis
		var face: Basis
		if nm == "Number_L":
			face = Basis.looking_at(b.x, b.y)                 # front of the label faces out to the left
		elif nm == "Number_R":
			face = Basis.looking_at(-b.x, b.y)
		else:
			face = Basis.looking_at(-b.y, -b.z)               # flat on the bonnet, top towards the nose
		lb.global_transform = Transform3D(face, centre + face.z * 0.004)

func _brake_torque(w: Wheel, pedal: float) -> float:
	var base: float = BRAKE_TORQUE[w.axle]
	if use_setup:
		var total: float = BRAKE_TORQUE["F"] + BRAKE_TORQUE["R"]
		var share := CarSetup.front_brake_share()
		base = total * (share if w.front else 1.0 - share)
	var t: float = base * pedal * CarSpecs.grip_factor()
	if not w.front:
		t = maxf(t, HANDBRAKE_TORQUE * handbrake)
	if w.punctured:
		t += 120.0
	return t

func _apply_brake_to_omega(omega: float, torque: float, dt: float) -> float:
	var dw := torque / WHEEL_I * dt
	if absf(omega) <= dw:
		return 0.0
	return omega - signf(omega) * dw

# ----------------------------------------------------------------- visuals
func _process(dt: float) -> void:
	for w in wheels:
		var c := D_REST - w.d                     # compression of the wheel, +ve = wheel moves up
		w.hub.position.y = w.hub_rest_y + c
		w.steer = 0.0
		if w.front:
			w.steer = _ackermann(w)
		w.steer_node.rotation.y = w.steer + w.toe_damage
		w.hub.rotation.z = w.camber_damage * w.sx
		w.angle = wrapf(w.angle - w.omega * dt, -PI, PI)
		w.wheel_node.rotation.x = w.angle
		var s: float = SPRING_LEN[w.axle]
		w.spring.scale.y = clampf((s - c) / s, 0.35, 1.4)
		w.arm.rotation.z = atan2(c, ARM_LEN) * w.sx
		if w.axle_shaft:
			var inner := w.axle_shaft.position
			var outer := Vector2(w.sx * (WHEEL_X - 0.10), WHEEL_R + c)
			var delta := outer - Vector2(inner.x, inner.y)
			var ang := atan2(delta.y, absf(delta.x))
			w.axle_shaft.rotation.z = (ang - w.shaft_rest_angle) * w.sx
			w.axle_shaft.scale.x = delta.length() / w.shaft_rest_len
	if _pedal_gas:
		_pedal_gas.rotation.x = -throttle * 0.25
	if _pedal_brake:
		_pedal_brake.rotation.x = -brake * 0.25
	if _steering_wheel:
		_steering_wheel.rotation.z = -steer_input * 3.4
	var glow := (2.2 if _lights_on else 0.5) + 6.0 * clampf(brake * 1.5, 0.0, 1.0)
	for tm in _tail_mats:
		if tm.emission_enabled:
			tm.emission_energy_multiplier = glow

func _ackermann(w: Wheel) -> float:
	var d := steer_angle
	if absf(d) < 0.001:
		return 0.0
	var inner_sign := 1.0 if d > 0.0 else -1.0
	var r := WHEELBASE / tan(absf(d))
	var inner := atan(WHEELBASE / (r - WHEEL_X))
	var outer := atan(WHEELBASE / (r + WHEEL_X))
	var is_inner := (w.sx * inner_sign) < 0.0
	return inner_sign * (inner if is_inner else outer)

# ------------------------------------------------------------------ utility
func compression(tag: String) -> float:
	for w in wheels:
		if w.tag == tag:
			return D_REST - w.d
	return 0.0

func get_wheel(tag: String) -> Wheel:
	for w in wheels:
		if w.tag == tag:
			return w
	return null

func reset_car(pos: Vector3, yaw: float = 0.0) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	for w in wheels:
		w.omega = 0.0
	gear = 1
	engine_rpm = idle_rpm
	reverse_mode = false
	manual = false
	_prev_vel = Vector3.ZERO

func handle_part_key(key: int) -> void:
	match key:
		KEY_E:
			shift(1)
		KEY_Q:
			shift(-1)
		KEY_Y:
			manual = false
		KEY_N:
			tc_enabled = not tc_enabled
		KEY_M:
			assist_enabled = not assist_enabled
		KEY_B:
			abs_enabled = not abs_enabled
		_:
			parts.handle_key(key)

func set_xray(mode: int) -> void:
	if model == null:
		return
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var n := String(mi.name)
		var shell := n in ["Hood", "Trunk", "Bumper_F", "Bumper_R", "Fender_L", "Fender_R", "Body_Sides", "Body_Rear",
			"Roof_Pillars", "Windshield", "Rear_Glass", "Splitter", "RearWing", "Diffuser", "HoodVents", "RoofScoop"] or n.begins_with("Door_") or n.begins_with("Window_")
		if shell and not parts.gone.has(n):
			mi.visible = (mode == 0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var imp := state.get_contact_impulse(i)
		var j := imp.length()
		if j > 20.0:
			var local := state.get_contact_local_position(i)
			var lp := global_transform.affine_inverse() * local
			contact_impulse.emit(lp, j, state.get_contact_local_normal(i))
			if use_setup:
				_impact_rumble = maxf(_impact_rumble, clampf(j / 6000.0, 0.2, 1.0))
