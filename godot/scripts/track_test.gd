extends SceneTree
## Headless check for RaceTrack. Run with:
##   Godot --headless --path . --script res://scripts/track_test.gd
## Results are written to res://track_test_out.txt.

var lines: PackedStringArray = PackedStringArray()
var fails: int = 0


func _initialize() -> void:
	_run()


func _log(s: String) -> void:
	lines.append(s)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		_log("FAIL: " + msg)


func _count_nodes(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _ray(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p + Vector3(0, -3, 0), 1)
	return space.intersect_ray(q)


func _run() -> void:
	var t0: int = Time.get_ticks_msec()
	var scr: GDScript = load("res://scripts/track.gd")
	var track: Node3D = scr.new()
	root.add_child(track)
	var build_ms: int = Time.get_ticks_msec() - t0
	await physics_frame
	await physics_frame
	await physics_frame

	var cl: PackedVector3Array = track.call("get_centerline")
	var n: int = cl.size()
	var length: float = 0.0
	for i in range(n):
		length += cl[i].distance_to(cl[(i + 1) % n])
	_log("build time ms: %d" % build_ms)
	_log("centerline points: %d, loop length: %.1f m, width: %.1f" % [n, length, track.call("get_track_width")])

	# min radius via circumscribed circle over +-6 samples (12 m)
	var min_r: float = 1e9
	var min_r_at: Vector3 = Vector3.ZERO
	for i in range(n):
		var a: Vector3 = cl[posmod(i - 6, n)]
		var b: Vector3 = cl[i]
		var c: Vector3 = cl[posmod(i + 6, n)]
		var ab: float = a.distance_to(b)
		var bc: float = b.distance_to(c)
		var ca: float = c.distance_to(a)
		var cross_y: float = absf((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x))
		if cross_y > 0.001:
			var r: float = ab * bc * ca / (2.0 * cross_y)
			if r < min_r:
				min_r = r
				min_r_at = b
	_log("min corner radius: %.1f m at %s" % [min_r, str(min_r_at)])
	_check(min_r >= 18.0, "min radius < 18")

	var mn: Vector3 = cl[0]
	var mx: Vector3 = cl[0]
	for p in cl:
		mn = mn.min(p)
		mx = mx.max(p)
	_log("bbox centerline x: %.0f..%.0f  z: %.0f..%.0f" % [mn.x, mx.x, mn.z, mx.z])
	_log("node count: %d" % _count_nodes(track))

	# separation of parts of the loop that are far apart along the track
	var min_sep: float = 1e9
	for i in range(0, n, 2):
		for j in range(i + 1, n, 2):
			var arc: int = mini(j - i, n - (j - i))
			if arc * 2 < 300:
				continue
			var d: float = Vector2(cl[i].x - cl[j].x, cl[i].z - cl[j].z).length()
			if d < min_sep:
				min_sep = d
	_log("min separation between parts (arc distance > 300 m): %.1f m" % min_sep)
	_check(min_sep >= 60.0, "parts closer than 60 m")

	# ray checks
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var tested: int = 0
	var bad: int = 0
	for i in range(0, n, 10):
		var tan_v: Vector3 = cl[posmod(i + 1, n)] - cl[posmod(i - 1, n)]
		tan_v.y = 0.0
		tan_v = tan_v.normalized()
		var right: Vector3 = tan_v.cross(Vector3.UP)
		for lat in [0.0, 5.5, -5.5]:
			var p: Vector3 = cl[i] + right * lat
			var hit: Dictionary = _ray(space, p)
			tested += 1
			var ok: bool = false
			if not hit.is_empty():
				var body: Object = hit["collider"]
				var hp: Vector3 = hit["position"]
				var mu: float = float(body.get_meta("mu", -1.0))
				ok = mu == 1.0 and absf(hp.y - p.y) < 0.06
			if not ok:
				bad += 1
				if bad < 6:
					_log("  ray miss at i=%d lat=%.1f pos=%s hit=%s" % [i, lat, str(p), str(hit.get("position", "none"))])
	_log("ray checks: %d tested, %d bad" % [tested, bad])
	_check(bad == 0, "ray failures")

	# other surfaces
	var off_hit: Dictionary = _ray(space, Vector3(-100.0, 0.0, 200.0))
	_log("grass at (-100,0,200): mu=%s y=%s" % [str(off_hit["collider"].get_meta("mu", -1.0)), str(off_hit["position"].y)])
	_check(is_equal_approx(float(off_hit["collider"].get_meta("mu", -1.0)), 0.55), "grass mu")
	var mu_counts: Dictionary = {}
	for i in range(0, n, 1):
		var right2: Vector3 = (cl[posmod(i + 1, n)] - cl[posmod(i - 1, n)]).normalized().cross(Vector3.UP)
		for lat in [-7.2, 7.2, -15.0, 15.0, -22.0, 22.0]:
			var h2: Dictionary = _ray(space, cl[i] + right2 * lat)
			if not h2.is_empty():
				var key: String = "%.2f" % float(h2["collider"].get_meta("mu", -1.0))
				mu_counts[key] = int(mu_counts.get(key, 0)) + 1
	_log("surface mu counts around track (shoulder/curb/gravel/grass probes): " + str(mu_counts))

	# start transform
	var st: Transform3D = track.call("get_start_transform")
	var sh: Dictionary = _ray(space, st.origin)
	var fwd: Vector3 = -st.basis.z
	_log("start origin %s forward %s" % [str(st.origin), str(fwd)])
	_check(not sh.is_empty() and float(sh["collider"].get_meta("mu", -1.0)) == 1.0, "start not on asphalt")
	if not sh.is_empty():
		var hp2: Vector3 = sh["position"]
		_check(absf(st.origin.y - hp2.y - 0.25) < 0.05, "start height")
	var rs: Transform3D = track.call("respawn_transform_near", Vector3(10.0, 3.0, 40.0))
	_log("respawn near (10,3,40): %s" % str(rs.origin))

	# lap timing simulation: teleport a dummy car along the centerline
	var dummy: Node3D = Node3D.new()
	root.add_child(dummy)
	dummy.global_transform = st
	track.set("car", dummy)
	var laps: Array = []
	var gates: Array = []
	track.connect("lap_completed", func(t: float, ln: int) -> void: laps.append([t, ln]))
	track.connect("checkpoint_passed", func(gi: int) -> void: gates.append(gi))
	var start_i: int = 0
	var best_d: float = 1e9
	for i in range(n):
		var d3: float = cl[i].distance_to(st.origin)
		if d3 < best_d:
			best_d = d3
			start_i = i
	var dt: float = 0.02
	var step_samples: int = 1       # 2 m per tick -> 100 m/s
	var i2: int = start_i
	var ticks: int = 0
	while ticks < 2 * n / step_samples + 400 and laps.size() < 2:
		i2 = posmod(i2 + step_samples, n)
		dummy.global_position = cl[i2] + Vector3(0.0, 0.3, 0.0)
		track.call("_physics_process", dt)
		ticks += 1
	_log("sim laps: %s gates: %s best %.3f last %.3f lap_number %d" % [str(laps), str(gates), track.get("best_lap_time"), track.get("last_lap_time"), track.get("lap_number")])
	_check(laps.size() == 2, "expected 2 laps from simulation")
	if laps.size() > 0:
		var expect: float = length / 100.0
		_check(absf(float(laps[0][0]) - expect) < 0.1, "lap time off: %.3f vs %.3f" % [laps[0][0], expect])
		_check(gates.size() >= 10, "gate count")

	_log("RESULT: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f: FileAccess = FileAccess.open("res://track_test_out.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0 if fails == 0 else 1)
