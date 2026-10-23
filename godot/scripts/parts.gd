class_name CarParts
extends Node
## Opening parts (doors, hood, trunk, windows) with hinge physics, plus the damage model:
## every panel and mechanical part dents where it is hit (crumple + scraped paint), the
## collision hull shortens as the nose is crushed, latches break, parts and wheels fall
## off, glass shatters, the radiator leaks, the engine overheats, smokes and can catch fire.

var car: Car
var hinges := {}                   # name -> Hinge
var panels := {}                   # name -> DentPanel (deformable mesh)
var damage := {}                   # name -> 0..1+
var gone := {}                     # name -> true when detached / destroyed (also "_cracked"/"_dead" flags)
var windows_down := false
var _window_nodes := {}            # name -> [node, rest_y]
var _spawned: Array[Node] = []
var _noise := FastNoiseLite.new()
var _smoke: CPUParticles3D
var _steam: CPUParticles3D
var _fire: CPUParticles3D
var _glass_mat: StandardMaterial3D
var _dead_lamp_mat: StandardMaterial3D
var _total_impulse := 0.0
var _rebuild_queue := {}
var _contacts: Array = []
var _crush_f := 0.0
var _crush_r := 0.0
var _nodes := {}

const CAPACITY := {
	"Hood": 9000.0, "Trunk": 9000.0, "Bumper_F": 7000.0, "Bumper_R": 7000.0,
	"Fender_L": 10000.0, "Fender_R": 10000.0, "Door_FL": 9000.0, "Door_FR": 9000.0,
	"Windshield": 6000.0, "Rear_Glass": 6000.0, "Window_FL": 4500.0, "Window_FR": 4500.0,
	"Headlight_L": 3500.0, "Headlight_R": 3500.0, "Taillight_L": 3500.0, "Taillight_R": 3500.0,
	"Mirror_FL": 2500.0, "Mirror_FR": 2500.0, "Grille": 4000.0, "Splitter": 3500.0,
	"Canard_L": 2000.0, "Canard_R": 2000.0, "RearWing": 6000.0, "Diffuser": 4500.0,
	"SideSkirt_L": 5000.0, "SideSkirt_R": 5000.0,
}
const PART_MASS := {"Hood": 11.0, "Trunk": 9.0, "Bumper_F": 7.0, "Bumper_R": 7.0, "Fender_L": 4.0,
	"Fender_R": 4.0, "Door_FL": 18.0, "Door_FR": 18.0, "Splitter": 5.0, "RearWing": 9.0, "Diffuser": 4.0,
	"Mirror_FL": 0.8, "Mirror_FR": 0.8, "Canard_L": 0.6, "Canard_R": 0.6, "SideSkirt_L": 2.0, "SideSkirt_R": 2.0}
const SKIP_PREFIX := ["Tire", "Rim", "Disc", "Window", "Windshield", "Rear_Glass", "Number", "Spring", "Arm_",
	"Axle", "Damper", "TopMount", "SpringSeat", "StrutBracket", "BumpStop", "Caliper", "Knuckle", "Pedal", "SteeringWheel"]

class Hinge:
	var name := ""
	var node: Node3D
	var axis := Vector3.UP
	var sgn := 1.0
	var r0 := Vector3(0, 0, 0.5)
	var a := 0.0                   # opening angle, rad (0 = closed)
	var w := 0.0
	var a_max := 1.1
	var detent := 1.0              # where the check strap / gas strut holds it
	var latched := true
	var driven := false
	var target := 0.0
	var free := false

class DentPanel:
	var node: MeshInstance3D
	var orig: Array = []           # per surface: PackedVector3Array
	var cur: Array = []
	var moved: Array = []          # per surface: PackedFloat32Array of accumulated displacement
	var dirty := false

func setup(c: Car) -> void:
	car = c
	_noise.seed = 3
	_noise.frequency = 1.0
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.9, 0.93, 0.97, 0.82)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.5
	_dead_lamp_mat = StandardMaterial3D.new()
	_dead_lamp_mat.albedo_color = Color(0.25, 0.22, 0.2)
	_dead_lamp_mat.roughness = 0.8
	_setup_hinges()
	_setup_panels()
	_setup_windows()
	_setup_particles()
	for n in CAPACITY.keys():
		damage[n] = 0.0
	car.contact_impulse.connect(on_impact)

func _node(n: String) -> Node3D:
	if not _nodes.has(n):
		_nodes[n] = car.model.find_child(n, true, false) as Node3D
	return _nodes[n]

func _add_hinge(name: String, axis: Vector3, sgn: float, r0: Vector3, a_max: float, detent: float) -> void:
	var n := _node(name)
	if n == null:
		return
	var h := Hinge.new()
	h.name = name
	h.node = n
	h.axis = axis
	h.sgn = sgn
	h.r0 = r0
	h.a_max = a_max
	h.detent = detent
	hinges[name] = h

func _setup_hinges() -> void:
	_add_hinge("Door_FL", Vector3.UP, -1.0, Vector3(0, 0, 0.78), 1.30, 1.10)
	_add_hinge("Door_FR", Vector3.UP, 1.0, Vector3(0, 0, 0.78), 1.30, 1.10)
	_add_hinge("Hood", Vector3.RIGHT, 1.0, Vector3(0, 0, -0.65), 1.05, 1.0)
	_add_hinge("Trunk", Vector3.RIGHT, -1.0, Vector3(0, 0, 0.33), 1.2, 1.1)

func _is_suspension(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != car.model:
		var nm := String(p.name)
		if nm == "Suspension" or nm.begins_with("Hub_") or nm.begins_with("Wheel_") or nm.begins_with("Steer_"):
			return true
		p = p.get_parent()
	return false

func _setup_panels() -> void:
	for m in car.model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var nm := String(mi.name)
		var skip := false
		for pre in SKIP_PREFIX:
			if nm.begins_with(pre):
				skip = true
				break
		if skip or _is_suspension(mi):
			continue
		var p := DentPanel.new()
		p.node = mi
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			p.orig.append(v.duplicate())
			p.cur.append(v.duplicate())
			var mv := PackedFloat32Array()
			mv.resize(v.size())
			p.moved.append(mv)
		panels[nm] = p

func _setup_windows() -> void:
	for tag in ["FL", "FR"]:
		var n := _node("Window_" + tag)
		if n:
			_window_nodes["Window_" + tag] = [n, n.position.y]

func _particles(color: Color, amount: int, size: float, vel_min: float, vel_max: float, life: float, emissive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 3.0
	sm.material = mat
	p.mesh = sm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	return p

func _setup_particles() -> void:
	_smoke = _particles(Color(0.12, 0.12, 0.12, 0.35), 40, 0.12, 1.0, 2.2, 2.2)
	_smoke.position = Vector3(0, 0.9, -1.4)
	car.add_child(_smoke)
	_steam = _particles(Color(0.95, 0.95, 0.98, 0.3), 40, 0.09, 1.4, 2.6, 1.3)
	_steam.position = Vector3(0, 0.75, -1.9)
	car.add_child(_steam)
	_fire = _particles(Color(1.0, 0.45, 0.08, 0.7), 60, 0.07, 1.2, 2.6, 0.7, true)
	_fire.position = Vector3(0, 0.8, -1.5)
	_fire.gravity = Vector3(0, 2.0, 0)
	car.add_child(_fire)

# ------------------------------------------------------------ keys / UI
func handle_key(key: int) -> void:
	match key:
		KEY_1: toggle("Door_FL")
		KEY_2: toggle("Door_FR")
		KEY_H: toggle("Hood")
		KEY_T: toggle("Trunk")
		KEY_F: windows_down = not windows_down
		KEY_G: repair()

func toggle(name: String) -> void:
	var h: Hinge = hinges.get(name)
	if h == null or gone.has(name):
		return
	var opening := h.a < 0.2 and not (h.driven and h.target > 0.0)
	if opening:
		if car.speed_kmh > 7.0 and name.begins_with("Door"):
			# opened while moving: the latch lets go and the door is free to swing
			h.latched = false
			h.driven = false
			h.w = 0.6
		else:
			h.latched = false
			h.driven = true
			h.target = h.detent
	else:
		h.driven = true
		h.target = 0.0
		h.latched = false

# ---------------------------------------------------------- physics step
func step(dt: float) -> void:
	var g_local := car.global_transform.basis.inverse() * Vector3(0, -Car.G, 0)
	var acc_car := car.last_accel_local.limit_length(60.0)
	for h: Hinge in hinges.values():
		if gone.has(h.name):
			continue
		if h.latched and not h.driven:
			continue
		var th := h.sgn * h.a
		var r := Basis(h.axis, th) * h.r0
		var f := g_local - acc_car
		var torque := r.cross(f).dot(h.axis)
		var acc := h.sgn * torque / (1.3333 * h.r0.length_squared())
		if h.driven:
			acc += 55.0 * (h.target - h.a) - 13.0 * h.w
		else:
			acc -= 0.6 * h.w
			if h.name.begins_with("Door") and absf(h.a - h.detent) < 0.06:
				acc -= 4.0 * h.w
		acc = clampf(acc, -400.0, 400.0)
		h.w += acc * dt
		h.a += h.w * dt
		if h.a > h.a_max:
			h.a = h.a_max
			if h.w > 0.0:
				h.w = -h.w * 0.2
		if h.a < 0.0:
			var impact := absf(h.w)
			h.a = 0.0
			if h.w < 0.0:
				if not h.free and (impact > 0.15 or h.driven):
					h.w = 0.0
					h.latched = true
					h.driven = false
				else:
					h.w = -h.w * 0.25
		h.node.rotation[0 if h.axis == Vector3.RIGHT else 1] = h.sgn * h.a
		if h.driven and absf(h.target - h.a) < 0.01 and absf(h.w) < 0.05 and h.target > 0.0:
			h.a = h.target
			h.w = 0.0
	for k in _window_nodes.keys():
		if gone.has(k):
			continue
		var wn: Node3D = _window_nodes[k][0]
		var rest: float = _window_nodes[k][1]
		wn.position.y = move_toward(wn.position.y, rest - (0.36 if windows_down else 0.0), dt * 0.25)
	_process_contacts()
	for n in _rebuild_queue.keys():
		_rebuild(panels[n])
	_rebuild_queue.clear()
	# fluids, smoke, steam, fire
	var hp := car.engine_health
	_smoke.emitting = hp < 0.65 or car.engine_temp > 130.0
	_smoke.amount = int(lerpf(70.0, 15.0, clampf(hp / 0.65, 0.0, 1.0)))
	_steam.emitting = (car.leak > 0.0 and car.coolant > 0.02) or car.engine_temp > 112.0
	_fire.emitting = car.on_fire
	var steam_pos := Vector3(0, 0.75, -1.9 + _crush_f)
	_steam.position = steam_pos
	car._engine_power_scale = 0.0 if hp < 0.08 else clampf(hp * 1.1, 0.25, 1.0)

# --------------------------------------------------------------- damage
func on_impact(local_pos: Vector3, impulse: float, normal: Vector3) -> void:
	# arcade mode: the same hit does a quarter of the damage
	_contacts.append([local_pos, impulse * CarSpecs.damage_factor(), normal])

func _process_contacts() -> void:
	if _contacts.is_empty():
		return
	var merged: Array = []
	for c in _contacts:
		var hit := false
		for m in merged:
			if (m[0] as Vector3).distance_to(c[0]) < 0.4:
				var tot: float = m[1] + c[1]
				m[0] = ((m[0] as Vector3) * m[1] + (c[0] as Vector3) * c[1]) / tot
				m[2] = ((m[2] as Vector3) * m[1] + (c[2] as Vector3) * c[1]).normalized()
				m[1] = tot
				hit = true
				break
		if not hit:
			merged.append([c[0], c[1], c[2]])
	_contacts.clear()
	merged.sort_custom(func(a, b): return a[1] > b[1])
	for i in mini(merged.size(), 5):
		_apply_hit(merged[i][0], merged[i][1], merged[i][2])

func _sparks(world_p: Vector3, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.emitting = true
	cp.amount = amount
	cp.lifetime = 0.6
	cp.explosiveness = 0.9
	cp.direction = Vector3.UP
	cp.spread = 80.0
	cp.initial_velocity_min = 2.0
	cp.initial_velocity_max = 7.0
	cp.gravity = Vector3(0, -9.8, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	cp.mesh = bm
	car.get_parent().add_child(cp)
	cp.global_position = world_p
	get_tree().create_timer(1.2).timeout.connect(cp.queue_free)

func _apply_hit(local_pos: Vector3, impulse: float, normal: Vector3) -> void:
	var world_p := car.global_transform * local_pos
	var n_local := (car.global_transform.basis.inverse() * normal).normalized()
	# scraping along the ground: sparks only
	if local_pos.y < 0.5 and absf(n_local.y) > 0.7:
		if impulse > 250.0 and car.speed_kmh > 15.0:
			_sparks(world_p, 10)
		return
	if impulse < 100.0:
		return
	_total_impulse += impulse
	if impulse > 500.0:
		_sparks(world_p, clampi(int(impulse / 150.0), 6, 40))
	var centre := Vector3(0, 0.7, 0.0)
	var out := (local_pos - centre).normalized()
	if n_local.dot(out) < 0.0:
		n_local = -n_local
	var dir := (-(n_local * 0.6 + out * 0.4)).normalized()   # push inwards
	var depth := clampf(impulse * 3.2e-5, 0.0, 0.22)
	var radius := 0.45 + clampf(impulse * 4.0e-5, 0.0, 0.8)
	for n in panels.keys():
		if gone.has(n):
			continue
		var p: DentPanel = panels[n]
		var wgt := _weight(p.node, world_p, radius)
		if wgt <= 0.0:
			continue
		_dent(p, world_p, dir, depth, wgt, radius)
		_rebuild_queue[n] = true
	for n in CAPACITY.keys():
		if gone.has(n):
			continue
		var node := _node(n)
		if node == null:
			continue
		var wgt := _weight(node, world_p, 0.55)
		if wgt <= 0.0:
			continue
		damage[n] += impulse * wgt / CAPACITY[n]
		_check_part(n, node, world_p, impulse)
	_hit_wheels(local_pos, impulse, n_local)
	# crush zones shorten the collision hull
	var crush := depth * 0.8
	if local_pos.z < -1.2:
		_crush_f = minf(_crush_f + crush, 1.3)
		car.apply_crush(_crush_f, _crush_r)
	elif local_pos.z > 1.2:
		_crush_r = minf(_crush_r + crush, 1.0)
		car.apply_crush(_crush_f, _crush_r)
	# mechanical damage
	# the engine is hurt by hits on its end of the car (front, or rear for mid / rear engines);
	# the radiator always sits in the nose
	var rear_engine: bool = car.spec["engine_rear"]
	var ez := local_pos.z if rear_engine else -local_pos.z
	if ez > 0.6:
		var end_w := clampf(1.0 - (2.3 - ez) / 1.7, 0.0, 1.0)
		car.engine_health = clampf(car.engine_health - impulse * end_w / 45000.0, 0.0, 1.0)
		if car.engine_health < 0.25 and impulse > 2500.0 and not CarSpecs.arcade:
			car.on_fire = true
	if local_pos.z < -0.6 and not CarSpecs.arcade:
		var rad := _node("Radiator")
		# a nudge does not hole a radiator; a real hit does, and a harder one leaks faster
		var rw := _weight(rad, world_p, 0.7) if rad != null else 0.0
		if rw > 0.0 and impulse * rw > 5000.0:
			# a few minutes for a normal knock, much less for a big hit; a pit stop fixes it
			car.leak = maxf(car.leak, 0.0008 + (impulse * rw - 5000.0) / 1500000.0)

func _weight(node: Node3D, world_p: Vector3, reach: float) -> float:
	if not (node is MeshInstance3D) or (node as MeshInstance3D).mesh == null:
		return 0.0
	var aabb := (node as MeshInstance3D).mesh.get_aabb()
	var wa := node.global_transform * aabb
	var cp := Vector3(clampf(world_p.x, wa.position.x, wa.end.x), clampf(world_p.y, wa.position.y, wa.end.y), clampf(world_p.z, wa.position.z, wa.end.z))
	var d := cp.distance_to(world_p)
	var t := clampf(1.0 - d / reach, 0.0, 1.0)
	return t * t

func _dent(p: DentPanel, world_p: Vector3, dir_car: Vector3, depth: float, wgt: float, radius: float) -> void:
	var inv := p.node.global_transform.affine_inverse()
	var lp := inv * world_p
	var ldir := (inv.basis * (car.global_transform.basis * dir_car)).normalized()
	for s in p.cur.size():
		var verts: PackedVector3Array = p.cur[s]
		var orig: PackedVector3Array = p.orig[s]
		var moved: PackedFloat32Array = p.moved[s]
		for i in verts.size():
			var d := verts[i].distance_to(lp)
			if d >= radius:
				continue
			var f := 1.0 - d / radius
			f = f * f * (3.0 - 2.0 * f)
			var crumple := 0.55 + 0.9 * (_noise.get_noise_3dv(orig[i] * 9.0) * 0.5 + 0.5)
			var disp := depth * f * crumple * (0.35 + 0.65 * wgt)
			if moved[i] + disp > 1.0:
				disp = maxf(1.0 - moved[i], 0.0)
			moved[i] += disp
			var ox := orig[i]
			var scatter := Vector3(_noise.get_noise_3d(ox.x * 17.0, ox.y * 17.0, 1.0), _noise.get_noise_3d(ox.y * 17.0, ox.z * 17.0, 5.0), _noise.get_noise_3d(ox.z * 17.0, ox.x * 17.0, 9.0)) * 0.35
			verts[i] += (ldir + scatter) * disp
		p.cur[s] = verts
		p.moved[s] = moved
	p.dirty = true

func _rebuild(p: DentPanel) -> void:
	var old := p.node.mesh
	var mesh := ArrayMesh.new()
	for s in old.get_surface_count():
		var arr := old.surface_get_arrays(s)
		var verts: PackedVector3Array = p.cur[s]
		var moved: PackedFloat32Array = p.moved[s]
		arr[Mesh.ARRAY_VERTEX] = verts
		var idx = arr[Mesh.ARRAY_INDEX]
		var orig_n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var nrm := PackedVector3Array()
		nrm.resize(verts.size())
		if idx != null and (idx as PackedInt32Array).size() >= 3:
			var ia: PackedInt32Array = idx
			for t in range(0, ia.size() - 2, 3):
				var a := ia[t]
				var b := ia[t + 1]
				var c := ia[t + 2]
				var fnrm := (verts[b] - verts[a]).cross(verts[c] - verts[a])
				nrm[a] += fnrm
				nrm[b] += fnrm
				nrm[c] += fnrm
			for i in nrm.size():
				nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 1e-12 else orig_n[i]
				# keep the facing of the original surface (triangle winding gives the inward normal);
				# an inverted normal lights the panel from behind and the paint looks silver / grey
				if i < orig_n.size() and nrm[i].dot(orig_n[i]) < 0.0:
					nrm[i] = -nrm[i]
			arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TANGENT] = null
		var col := PackedColorArray()
		col.resize(verts.size())
		for i in verts.size():
			var k := clampf(moved[i] * 7.0, 0.0, 1.0)
			col[i] = Color(1, 1, 1, 1).lerp(Color(0.2, 0.18, 0.18, 1), k) if moved[i] > 0.015 else Color(1, 1, 1, 1)
		arr[Mesh.ARRAY_COLOR] = col
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, old.surface_get_material(s))
	p.node.mesh = mesh
	p.dirty = false

func _check_part(n: String, node: Node3D, world_p: Vector3, impulse: float) -> void:
	var dmg: float = damage[n]
	if hinges.has(n):
		var h: Hinge = hinges[n]
		if dmg > 0.2 and h.latched:
			h.latched = false
			h.driven = false
			h.free = true
			h.w = 0.8
		if dmg > 0.85:
			_detach(n, world_p, impulse)
		return
	if n.begins_with("Bumper"):
		if dmg > 0.7:
			_detach(n, world_p, impulse)
	elif n.begins_with("Fender"):
		if dmg > 0.9:
			_detach(n, world_p, impulse)
	elif n in ["Splitter", "RearWing", "Diffuser"] or n.begins_with("Canard") or n.begins_with("SideSkirt"):
		if dmg > 0.6:
			_detach(n, world_p, impulse)
	elif n.begins_with("Mirror"):
		if dmg > 0.5:
			_detach(n, world_p, impulse)
	elif n.begins_with("Window") or n == "Windshield" or n == "Rear_Glass":
		var crack := 0.15 if n == "Windshield" else 0.2
		if dmg > crack and node is MeshInstance3D and not gone.has(n + "_cracked"):
			(node as MeshInstance3D).material_override = _glass_mat
			gone[n + "_cracked"] = true
		if dmg > 0.5:
			_shatter(n, node, world_p)
	elif n.begins_with("Headlight") or n.begins_with("Taillight") or n == "Grille":
		if dmg > 0.4 and not gone.has(n + "_dead"):
			(node as MeshInstance3D).material_override = _dead_lamp_mat
			gone[n + "_dead"] = true
		if dmg > 0.9:
			node.visible = false
			gone[n] = true

func _shatter(n: String, node: Node3D, world_p: Vector3) -> void:
	node.visible = false
	gone[n] = true
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.emitting = true
	cp.amount = 80
	cp.lifetime = 1.4
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 70.0
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 5.0
	cp.gravity = Vector3(0, -9.8, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.005, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	cp.mesh = bm
	car.get_parent().add_child(cp)
	cp.global_position = node.global_position + Vector3(0, 0.1, 0)
	get_tree().create_timer(2.5).timeout.connect(cp.queue_free)

func _detach(n: String, world_p: Vector3, impulse: float) -> void:
	if gone.has(n):
		return
	var node := _node(n)
	if node == null:
		return
	gone[n] = true
	var rb := RigidBody3D.new()
	rb.name = "Loose_" + n
	var mass_kg: float = PART_MASS.get(n, 3.0)
	rb.mass = mass_kg
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	rb.global_transform = node.global_transform
	var dup := node.duplicate()
	dup.name = n
	rb.add_child(dup)
	(dup as Node3D).transform = Transform3D.IDENTITY
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var cs := CollisionShape3D.new()
		cs.shape = (node as MeshInstance3D).mesh.create_convex_shape(true, true)
		rb.add_child(cs)
	car.get_parent().add_child(rb)
	rb.global_transform = node.global_transform
	var vp := car.linear_velocity + car.angular_velocity.cross(node.global_position - car.global_position)
	rb.linear_velocity = vp + (node.global_position - world_p).normalized() * 3.0 + Vector3(0, 1.5, 0)
	rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	node.visible = false
	for ch in node.get_children():
		if ch is Node3D:
			(ch as Node3D).visible = false
	_spawned.append(rb)
	car.mass -= mass_kg
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.collision_mask = 1 | 2 | 4)

func _hit_wheels(local_pos: Vector3, impulse: float, n_local: Vector3) -> void:
	for w: Car.Wheel in car.wheels:
		if w.detached:
			continue
		var hub_pos := Vector3(w.sx * Car.WHEEL_X, Car.WHEEL_R, w.hub.position.z)
		var d := Vector2(local_pos.x - hub_pos.x, local_pos.z - hub_pos.z).length()
		if local_pos.y > 0.75 or d > 0.6:
			continue
		var wgt := clampf(1.0 - d / 0.6, 0.0, 1.0)
		var dw := impulse * wgt / 11000.0
		w.health -= dw
		var side := signf(n_local.x) if absf(n_local.x) > 0.2 else signf(n_local.z)
		w.toe_damage += dw * 0.10 * side * w.sx
		w.camber_damage += dw * 0.07 * w.sx * signf(n_local.x + 0.001)
		w.toe_damage = clampf(w.toe_damage, -0.25, 0.25)
		w.camber_damage = clampf(w.camber_damage, -0.35, 0.35)
		if w.health < 0.4:
			w.punctured = true
		if w.health <= 0.0:
			_detach_wheel(w, impulse)

func _detach_wheel(w: Car.Wheel, impulse: float) -> void:
	w.detached = true
	var node := w.wheel_node
	var rb := RigidBody3D.new()
	rb.name = "Loose_Wheel_" + w.tag
	rb.mass = 24.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Car.WHEEL_R
	cyl.height = 0.27
	cs.shape = cyl
	cs.rotation.z = PI / 2.0
	rb.add_child(cs)
	car.get_parent().add_child(rb)
	rb.global_transform = node.global_transform
	for m in node.get_children():
		var dup := m.duplicate()
		rb.add_child(dup)
		if dup is Node3D:
			(dup as Node3D).transform = Transform3D.IDENTITY
	rb.global_transform = node.global_transform
	rb.linear_velocity = car.linear_velocity + Vector3(w.sx * 2.0, 2.0, 0).rotated(Vector3.UP, car.global_rotation.y)
	rb.angular_velocity = car.global_transform.basis.x * 20.0
	node.visible = false
	_spawned.append(rb)
	car.mass -= 24.0
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.collision_mask = 1 | 2 | 4)

func repair() -> void:
	for n in gone.keys():
		var nm := String(n)
		if nm.ends_with("_cracked") or nm.ends_with("_dead"):
			var base := nm.replace("_cracked", "").replace("_dead", "")
			var nd := _node(base)
			if nd is MeshInstance3D:
				(nd as MeshInstance3D).material_override = null
			continue
		var node := _node(nm)
		if node:
			node.visible = true
			for ch in node.get_children():
				if ch is Node3D:
					(ch as Node3D).visible = true
	gone.clear()
	for rb in _spawned:
		if is_instance_valid(rb):
			rb.queue_free()
	_spawned.clear()
	for n in panels.keys():
		var p: DentPanel = panels[n]
		var changed := false
		for s in p.cur.size():
			var m: PackedFloat32Array = p.moved[s]
			for v in m:
				if v > 0.0:
					changed = true
					break
			p.cur[s] = (p.orig[s] as PackedVector3Array).duplicate()
			m.fill(0.0)
			p.moved[s] = m
		if changed:
			_rebuild(p)
	for h: Hinge in hinges.values():
		h.a = 0.0
		h.w = 0.0
		h.latched = true
		h.driven = false
		h.free = false
		h.node.rotation = Vector3.ZERO
	for k in damage.keys():
		damage[k] = 0.0
	for w: Car.Wheel in car.wheels:
		w.detached = false
		w.punctured = false
		w.health = 1.0
		w.toe_damage = 0.0
		w.camber_damage = 0.0
		w.wheel_node.visible = true
	car.engine_health = 1.0
	car.coolant = 1.0
	car.leak = 0.0
	car.engine_temp = 90.0
	car.on_fire = false
	car.mass = car.mass_kg
	_crush_f = 0.0
	_crush_r = 0.0
	car.reset_crush()
	_total_impulse = 0.0

func summary() -> String:
	var lines := PackedStringArray()
	for n in ["Hood", "Bumper_F", "Splitter", "Fender_L", "Fender_R", "Door_FL", "Door_FR", "Trunk", "Bumper_R", "RearWing",
			"Windshield", "Headlight_L", "Headlight_R"]:
		var d: float = damage.get(n, 0.0)
		if gone.has(n):
			lines.append("%s GONE" % n)
		elif d > 0.02:
			lines.append("%s %d%%" % [n, int(minf(d, 1.0) * 100.0)])
	for w: Car.Wheel in car.wheels:
		if w.detached:
			lines.append("wheel %s GONE" % w.tag)
		elif w.health < 0.98:
			lines.append("wheel %s %d%%" % [w.tag, int(w.health * 100.0)])
	if car.engine_health < 0.98:
		lines.append("engine %d%%" % int(car.engine_health * 100.0))
	if car.leak > 0.0:
		lines.append("coolant %d%%" % int(car.coolant * 100.0))
	if car.on_fire:
		lines.append("ENGINE ON FIRE")
	if _crush_f > 0.02 or _crush_r > 0.02:
		lines.append("crush nose %.0f cm tail %.0f cm" % [_crush_f * 100.0, _crush_r * 100.0])
	return "\n".join(lines)
