class_name TyreFX
extends Node3D
## Per-car tyre effects: smoke when a tyre slides on tarmac, dust when driving over grass or
## gravel, and rubber skid marks laid onto the road (shared ring buffer, see SkidMarks).

var car: Car
var _smoke: Array[GPUParticles3D] = []
var _spray: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _last_mark: Array[Vector3] = []
var _marking: Array[bool] = []

static var _smoke_tex: Texture2D

static func _soft_puff() -> Texture2D:
	if _smoke_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_smoke_tex = t
	return _smoke_tex

func _make_emitter(col: Color, amount: int, life: float, size: float, grow: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 1.2
	pm.damping_max = 2.0
	pm.inherit_velocity_ratio = 0.25
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = size
	pm.scale_max = size * 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, grow))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.08, Color(col.r, col.g, col.b, col.a))
	ramp.add_point(0.5, Color(col.r, col.g, col.b, col.a * 0.55))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_puff()
	m.roughness = 1.0
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	q.material = m
	p.draw_pass_1 = q
	return p

var _flames: Array[MeshInstance3D] = []
var _flash: OmniLight3D
var _flame_t := 0.0
var _last_pops := 0
var _discs: Array[StandardMaterial3D] = []

func _setup_flames() -> void:
	## a short flame from each exhaust tip, and a flash of light, on every pop
	var ex: Vector2 = car.spec.get("exhaust", Vector2(0.2, 0.28))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.055
	cone.height = 0.38
	cone.radial_segments = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.2, 0.85)
	m.disable_receive_shadows = true
	cone.material = m
	for sx in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		f.mesh = cone
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# cylinder axis is Y: lay it along +Z (backwards out of the tip)
		f.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		f.position = Vector3(sx * ex.x, ex.y, car.tail_len + 0.2)
		f.visible = false
		car.add_child(f)
		_flames.append(f)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.2)
	_flash.omni_range = 3.5
	_flash.light_energy = 0.0
	_flash.position = Vector3(0.0, ex.y + 0.1, car.tail_len + 0.35)
	car.add_child(_flash)

func _setup_discs() -> void:
	## each car gets its own disc material per wheel so it can glow on its own
	for w in car.wheels:
		var disc := car.model.find_child("Disc_" + w.tag, true, false) as MeshInstance3D
		var mt: StandardMaterial3D = null
		if disc != null and disc.mesh != null and disc.mesh.get_surface_count() > 0:
			var base := disc.mesh.surface_get_material(0) as StandardMaterial3D
			if base != null:
				mt = base.duplicate()
				mt.emission_enabled = true
				mt.emission = Color(1.0, 0.25, 0.05)
				mt.emission_energy_multiplier = 0.0
				disc.material_override = mt
		_discs.append(mt)

func _process(dt: float) -> void:
	if car == null:
		return
	if car.pops != _last_pops:
		_last_pops = car.pops
		_flame_t = 0.07
		for f in _flames:
			f.scale = Vector3.ONE * randf_range(0.7, 1.3)
	_flame_t = maxf(_flame_t - dt, 0.0)
	var on := _flame_t > 0.0
	for f in _flames:
		f.visible = on
	_flash.light_energy = 4.0 if on else 0.0
	for k in _discs.size():
		if _discs[k] != null:
			_discs[k].emission_energy_multiplier = clampf((car.brake_temp[k] - 420.0) / 260.0, 0.0, 1.0) * 3.0

func setup(c: Car) -> void:
	car = c
	_setup_flames()
	_setup_discs()
	for i in car.wheels.size():
		var s := _make_emitter(Color(0.80, 0.80, 0.82, 0.22), 110, 2.4, 0.55, 7.0)
		var d := _make_emitter(Color(0.52, 0.44, 0.33, 0.3), 40, 1.6, 0.5, 4.0)
		# rain: a plume of mist thrown up behind every wheel
		var sp := _make_emitter(Color(0.82, 0.84, 0.88, 0.2), 70, 1.3, 0.9, 6.0)
		add_child(s)
		add_child(d)
		add_child(sp)
		_smoke.append(s)
		_dust.append(d)
		_spray.append(sp)
		_last_mark.append(Vector3.ZERO)
		_marking.append(false)

func _physics_process(_dt: float) -> void:
	if car == null:
		return
	var skids := SkidMarks.instance
	for i in car.wheels.size():
		var w: Car.Wheel = car.wheels[i]
		var smoke := _smoke[i]
		var dust := _dust[i]
		var on_road := w.mu_surface > 0.9
		var slide := w.slide_speed if w.grounded else 0.0
		# a tyre only smokes and marks the road once it is really past its grip (spinning, locked
		# or sliding sideways), not from the normal few percent of slip at speed
		var past := maxf(absf(w.slip_ratio), absf(w.slip_angle) * 1.2)
		var sliding := clampf((past - 0.2) * 3.5, 0.0, 1.0) * clampf((slide - 2.0) / 6.0, 0.0, 1.0)
		var spd := car.linear_velocity.length()
		smoke.global_position = w.contact_point + Vector3(0, 0.25, 0)
		dust.global_position = w.contact_point + Vector3(0, 0.2, 0)
		var wet := Weather.rain
		var smoke_amt := sliding if on_road and not wet else 0.0
		var spray := _spray[i]
		spray.global_position = w.contact_point + Vector3(0, 0.3, 0) + car.global_transform.basis.z * 0.35
		var spray_amt := clampf((spd - 8.0) / 45.0, 0.0, 1.0) if wet and w.grounded and on_road else 0.0
		spray.amount_ratio = spray_amt
		spray.emitting = spray_amt > 0.02
		smoke.amount_ratio = smoke_amt
		smoke.emitting = smoke_amt > 0.01
		var dust_amt := 0.0
		if w.grounded and not on_road:
			dust_amt = clampf(spd / 25.0, 0.0, 1.0) * 0.6 + clampf(slide / 8.0, 0.0, 0.4)
		dust.amount_ratio = dust_amt
		dust.emitting = dust_amt > 0.02
		# skid marks
		var mark := w.grounded and on_road and sliding > 0.12 and not Weather.rain
		if skids != null and mark:
			var p := w.contact_point
			if _marking[i]:
				if p.distance_to(_last_mark[i]) > 0.35:
					skids.add_segment(_last_mark[i], p, w.contact_normal, clampf(sliding * 1.3, 0.25, 1.0))
					_last_mark[i] = p
			else:
				_last_mark[i] = p
		_marking[i] = mark
