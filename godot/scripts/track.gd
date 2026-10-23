class_name RaceTrack
extends Node3D
## Procedural race circuit (about 3.5 km, 13 m wide) built entirely in _ready().
## The node is expected to sit at the world origin. Car forward is -Z in Godot.
##
## Physics contract: every surface a tyre ray may hit is a StaticBody3D on
## collision layer 1 (mask 0) with a "mu" meta value (asphalt 1.0, curbs 0.95,
## grass 0.55, gravel 0.40). Loose props are RigidBody3D on layer 4.

signal lap_completed(lap_time: float, lap_number: int)
signal checkpoint_passed(index: int)

# ---------------------------------------------------------------- constants
const ROAD_WIDTH: float = 13.0
const HALF_W: float = 6.5
const SHOULDER: float = 1.5
const COLL_HALF: float = 8.0          # HALF_W + SHOULDER (paved, mu 1.0)
const ROAD_Y: float = 0.02            # road surface height above the grass top (y = 0)
const SPACING: float = 2.0            # centerline sample spacing (m)
const CURB_H: float = 0.035
const START_S: float = 150.0          # start/finish line distance from the loop origin
const NUM_GATES: int = 5
const GROUND_SIZE: float = 4000.0
const SUBDIV: int = 20

# ------------------------------------------------------------------- public
var car: Node3D
var current_lap_time: float = 0.0
var last_lap_time: float = 0.0
var best_lap_time: float = 0.0        # 0.0 = none yet
var lap_number: int = 1               # current lap (1-based; timer idle until the line is first crossed)
var progress: float = 0.0             # 0..1 distance fraction around the lap, 0 = start line

# --------------------------------------------------------------- centerline
var _n: int = 0
var _ds: float = SPACING
var _len: float = 0.0
var _pos: PackedVector3Array = PackedVector3Array()    # at road surface height
var _tan: PackedVector3Array = PackedVector3Array()
var _right: PackedVector3Array = PackedVector3Array()
var _kappa: PackedFloat32Array = PackedFloat32Array()   # lightly smoothed, + = right turn
var _kappa_s: PackedFloat32Array = PackedFloat32Array() # heavily smoothed (classification)
var _bmin: Vector3 = Vector3.ZERO
var _bmax: Vector3 = Vector3.ZERO
var _min_radius: float = 0.0
var _i_line: int = 0
var _s_line: float = 0.0
var _gate_s: PackedFloat32Array = PackedFloat32Array()

# ------------------------------------------------------------------ timing
var _hint: int = -1
var _have_prev: bool = false
var _prev_rel: float = 0.0
var _running: bool = false
var _next_gate: int = 0

# --------------------------------------------------------------- build state
var _mat_cache: Dictionary = {}
var _tex_asphalt: ImageTexture
var _tex_grass: ImageTexture
var _tex_gravel: ImageTexture
var _hairpin_run: Vector2i = Vector2i(-1, 0)
var _hairpin_side: int = 1
var _stands: Array[Vector3] = []   # grandstand centers (for tree exclusion)
static var reversed := false
var _gravel_out: Array = []        # per side (left, right): outer edge of the gravel trap at each sample       # second layout: the same circuit driven the other way round
var _total_raw := 0.0


# =============================================================== mesh buffer
class MeshBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()

	## Adds a quad given in cyclic order. The winding is chosen so that the
	## face normal points towards `want` (Godot front faces are clockwise).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, want: Vector3, col: Color,
			t0: Vector2 = Vector2.ZERO, t1: Vector2 = Vector2.ZERO,
			t2: Vector2 = Vector2.ZERO, t3: Vector2 = Vector2.ZERO) -> void:
		var n: Vector3 = (p2 - p0).cross(p1 - p0)
		if n.length_squared() < 1e-12:
			n = (p3 - p0).cross(p2 - p0)
			if n.length_squared() < 1e-12:
				return
		if n.dot(want) < 0.0:
			var tp: Vector3 = p1
			p1 = p3
			p3 = tp
			var tt: Vector2 = t1
			t1 = t3
			t3 = tt
			n = -n
		n = n.normalized()
		var b: int = verts.size()
		verts.append(p0)
		verts.append(p1)
		verts.append(p2)
		verts.append(p3)
		for k in range(4):
			norms.append(n)
			cols.append(col)
		uvs.append(t0)
		uvs.append(t1)
		uvs.append(t2)
		uvs.append(t3)
		idx.append(b)
		idx.append(b + 1)
		idx.append(b + 2)
		idx.append(b)
		idx.append(b + 2)
		idx.append(b + 3)

	func to_faces() -> PackedVector3Array:
		var f: PackedVector3Array = PackedVector3Array()
		f.resize(idx.size())
		for k in range(idx.size()):
			f[k] = verts[idx[k]]
		return f

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if verts.is_empty():
			return
		var arrs: Array = []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = verts
		arrs[Mesh.ARRAY_NORMAL] = norms
		arrs[Mesh.ARRAY_TEX_UV] = uvs
		arrs[Mesh.ARRAY_COLOR] = cols
		arrs[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# ================================================================ public API
func get_start_transform() -> Transform3D:
	_ensure_data()
	var i: int = posmod(roundi((_s_line - 6.0) / _ds), _n)
	var p: Vector3 = _pos[i] + _right[i] * -2.8 + Vector3(0.0, 0.25, 0.0)
	var xf: Transform3D = Transform3D(Basis.looking_at(_tan[i], Vector3.UP), p)
	return _to_world(xf)


func get_grid_transform(slot: int) -> Transform3D:
	## staggered grid: even slots on the left (pole side), odd slots on the right, 9 m per row
	_ensure_data()
	var row: int = slot / 2
	var s: float = _s_line - (6.0 if slot % 2 == 0 else 10.5) - 9.0 * float(row)
	var i: int = posmod(roundi(s / _ds), _n)
	var lat: float = -2.8 if slot % 2 == 0 else 2.8
	var p: Vector3 = _pos[i] + _right[i] * lat + Vector3(0.0, 0.25, 0.0)
	return _to_world(Transform3D(Basis.looking_at(_tan[i], Vector3.UP), p))


func get_right_vectors() -> PackedVector3Array:
	_ensure_data()
	return _right.duplicate()


func get_line_s() -> float:
	## distance of the start / finish line from centerline sample 0
	_ensure_data()
	return _s_line


func get_centerline() -> PackedVector3Array:
	_ensure_data()
	return _pos.duplicate()


func get_track_width() -> float:
	return ROAD_WIDTH


func get_length() -> float:
	_ensure_data()
	return _len


func respawn_transform_near(pos: Vector3) -> Transform3D:
	_ensure_data()
	var lp: Vector3 = pos
	if is_inside_tree():
		lp = to_local(pos)
	var i: int = _nearest_global(lp)
	var p: Vector3 = _pos[i] + Vector3(0.0, 0.4, 0.0)
	var xf: Transform3D = Transform3D(Basis.looking_at(_tan[i], Vector3.UP), p)
	_hint = -1
	_have_prev = false
	return _to_world(xf)


func _to_world(xf: Transform3D) -> Transform3D:
	if is_inside_tree():
		return global_transform * xf
	return transform * xf


# ===================================================================== _ready
func _ready() -> void:
	_ensure_data()
	_make_textures()
	_build_ground()
	_build_road()
	_build_curbs()
	_build_gravel()
	_build_barriers()
	_build_pitlane()
	_build_decor()
	_build_trees()
	_build_grass()
	_build_hills()
	_build_props()
	_build_floodlights()
	_build_dressing()


# ===================================================================== timing
func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or _n == 0:
		return
	var p: Vector3 = to_local(car.global_position)
	var idx: int = _find_near(p)
	var dx: float = p.x - _pos[idx].x
	var dz: float = p.z - _pos[idx].z
	var dist: float = sqrt(dx * dx + dz * dz)
	var s_i: float = float(idx) * _ds + dx * _tan[idx].x + dz * _tan[idx].z
	var rel: float = fposmod(s_i - _s_line, _len)
	progress = rel / _len
	if _running:
		current_lap_time += delta
	if _have_prev:
		var d: float = rel - _prev_rel
		if d < -_len * 0.5:
			d += _len
		elif d > _len * 0.5:
			d -= _len
		if absf(d) < 40.0 and dist < 45.0 and d > 0.0:
			var a: float = _prev_rel
			var b: float = a + d
			if _next_gate < NUM_GATES:
				var gs: float = _gate_s[_next_gate]
				if a < gs and b >= gs:
					var gi: int = _next_gate
					_next_gate += 1
					checkpoint_passed.emit(gi)
			if a < _len and b >= _len:
				var t_after: float = delta * ((b - _len) / d)
				if _running:
					var lap_t: float = current_lap_time - t_after
					if _next_gate >= NUM_GATES:
						last_lap_time = lap_t
						if best_lap_time <= 0.0 or lap_t < best_lap_time:
							best_lap_time = lap_t
						var done: int = lap_number
						lap_number += 1
						lap_completed.emit(lap_t, done)
				else:
					_running = true
				current_lap_time = t_after
				_next_gate = 0
	_prev_rel = rel
	_have_prev = true


func _find_near(p: Vector3) -> int:
	if _hint >= 0:
		var best: int = _hint
		var bd: float = INF
		for o in range(-40, 41):
			var k: int = posmod(_hint + o, _n)
			var ex: float = _pos[k].x - p.x
			var ez: float = _pos[k].z - p.z
			var d2: float = ex * ex + ez * ez
			if d2 < bd:
				bd = d2
				best = k
		if bd < 3600.0:
			_hint = best
			return best
	_hint = _nearest_global(p)
	_have_prev = false
	return _hint


func _nearest_global(p: Vector3) -> int:
	var best: int = 0
	var bd: float = INF
	for k in range(_n):
		var ex: float = _pos[k].x - p.x
		var ez: float = _pos[k].z - p.z
		var d2: float = ex * ex + ez * ez
		if d2 < bd:
			bd = d2
			best = k
	return best


# ============================================================ centerline build
func _ensure_data() -> void:
	if _n > 0:
		return
	_build_centerline()


func _line(pts: Array[Vector2], a: Vector2, b: Vector2, step: float) -> void:
	## Interior points only (a and b are added by the neighbouring pieces).
	var l: float = a.distance_to(b)
	var m: int = maxi(1, roundi(l / step))
	for k in range(1, m):
		pts.append(a.lerp(b, float(k) / float(m)))


func _arc(pts: Array[Vector2], c: Vector2, r: float, a0: float, a1: float, step_deg: float, include_end: bool = true) -> void:
	## Angles in degrees, atan2(dz, dx). Increasing angle = right turn (clockwise on the map).
	var m: int = maxi(1, ceili(absf(a1 - a0) / step_deg))
	var last: int = m if include_end else m - 1
	for k in range(last + 1):
		var a: float = deg_to_rad(lerpf(a0, a1, float(k) / float(m)))
		pts.append(c + Vector2(cos(a), sin(a)) * r)


func _esses(pts: Array[Vector2]) -> void:
	# z from 200 to 500, two full waves, eased in and out.
	for k in range(21):
		var z: float = 200.0 + 15.0 * float(k)
		var e: float = smoothstep(0.0, 1.0, (z - 200.0) / 50.0) * smoothstep(0.0, 1.0, (500.0 - z) / 50.0)
		var x: float = 590.0 - 17.0 * e * sin(TAU * (z - 200.0) / 150.0)
		pts.append(Vector2(x, z))


func _chicane(pts: Array[Vector2]) -> void:
	# x from 330 down to 190, one full wave (left then right) between x=300 and x=210.
	for k in range(15):
		var x: float = 330.0 - 10.0 * float(k)
		var w: float = clampf((300.0 - x) / 90.0, 0.0, 1.0)
		var e: float = smoothstep(0.0, 1.0, w / 0.28) * smoothstep(0.0, 1.0, (1.0 - w) / 0.28)
		var z: float = 565.0 - 8.0 * e * sin(TAU * w)
		pts.append(Vector2(x, z))


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	## Centripetal Catmull-Rom (Barry-Goldman), t in 0..1 between p1 and p2.
	var t0: float = 0.0
	var t1: float = t0 + sqrt(p0.distance_to(p1))
	var t2: float = t1 + sqrt(p1.distance_to(p2))
	var t3: float = t2 + sqrt(p2.distance_to(p3))
	var tt: float = lerpf(t1, t2, t)
	var a1: Vector3 = p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2: Vector3 = p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3: Vector3 = p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1: Vector3 = a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2: Vector3 = a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


func _smooth(src: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(_n)
	for i in range(_n):
		var s: float = 0.0
		for o in range(-w, w + 1):
			s += src[posmod(i + o, _n)]
		out[i] = s / float(2 * w + 1)
	return out


func _build_centerline() -> void:
	# Layout is clockwise on the map (x east, z south). Start of the main straight at (-350, 0).
	var cp: Array[Vector2] = []
	cp.append(Vector2(-350.0, 0.0))
	_line(cp, Vector2(-350, 0), Vector2(440, 0), 30.0)                  # main straight, 790 m
	_arc(cp, Vector2(440, 150), 150.0, -90.0, 0.0, 12.0)                # fast sweeper R150
	_line(cp, Vector2(590, 150), Vector2(590, 200), 25.0)
	_esses(cp)                                                           # esses, 4 bends
	_arc(cp, Vector2(545, 520), 45.0, 0.0, 90.0, 10.0)                  # medium 90 deg R45
	_line(cp, Vector2(545, 565), Vector2(330, 565), 30.0)
	_chicane(cp)                                                         # chicane
	_line(cp, Vector2(190, 565), Vector2(-50, 565), 30.0)
	_arc(cp, Vector2(-50, 533), 32.0, 90.0, 270.0, 10.0)                # hairpin R32
	_line(cp, Vector2(-50, 501), Vector2(100, 501), 30.0)
	_arc(cp, Vector2(100, 441), 60.0, 90.0, -90.0, 10.0)                # long constant radius, left, R60
	_line(cp, Vector2(100, 381), Vector2(-455, 381), 30.0)
	_arc(cp, Vector2(-455, 336), 45.0, 90.0, 180.0, 10.0)               # medium 90 deg R45
	_line(cp, Vector2(-500, 336), Vector2(-500, 150), 30.0)
	_arc(cp, Vector2(-350, 150), 150.0, 180.0, 270.0, 12.0, false)      # long flowing bend R150

	if reversed:
		# same place, other direction: keep the first point, run the rest backwards
		var first: Vector2 = cp[0]
		cp.remove_at(0)
		cp.reverse()
		cp.insert(0, first)
	var m: int = cp.size()
	var ctrl: PackedVector3Array = PackedVector3Array()
	for v in cp:
		ctrl.append(Vector3(v.x, ROAD_Y, v.y))
	var dense: PackedVector3Array = PackedVector3Array()
	for i in range(m):
		var p0: Vector3 = ctrl[posmod(i - 1, m)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[posmod(i + 1, m)]
		var p3: Vector3 = ctrl[posmod(i + 2, m)]
		for k in range(SUBDIV):
			dense.append(_cr(p0, p1, p2, p3, float(k) / float(SUBDIV)))
	var dn: int = dense.size()
	var cum: PackedFloat64Array = PackedFloat64Array()
	cum.resize(dn + 1)
	for i in range(dn):
		cum[i + 1] = cum[i] + dense[i].distance_to(dense[(i + 1) % dn])
	var total: float = cum[dn]
	_total_raw = total
	_n = roundi(total / SPACING)
	_len = total
	_ds = total / float(_n)
	_pos.resize(_n)
	var j: int = 0
	for i in range(_n):
		var target: float = float(i) * _ds
		while j < dn - 1 and cum[j + 1] < target:
			j += 1
		var seg: float = cum[j + 1] - cum[j]
		var f: float = (target - cum[j]) / maxf(seg, 0.000001)
		_pos[i] = dense[j].lerp(dense[(j + 1) % dn], f)
		# the hills belong to the place, not the direction: look them up by the forward distance
		_pos[i].y = ROAD_Y + _elevation(fposmod(total - target, total) if reversed else target) * ELEV_SCALE

	_tan.resize(_n)
	_right.resize(_n)
	for i in range(_n):
		var t: Vector3 = _pos[posmod(i + 1, _n)] - _pos[posmod(i - 1, _n)]
		t.y = 0.0
		t = t.normalized()
		_tan[i] = t
		_right[i] = t.cross(Vector3.UP)
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(_n)
	for i in range(_n):
		var ta: Vector3 = _tan[i]
		var tb: Vector3 = _tan[posmod(i + 1, _n)]
		raw[i] = atan2(ta.x * tb.z - ta.z * tb.x, ta.dot(tb)) / _ds
	_kappa = _smooth(raw, 3)
	_kappa_s = _smooth(raw, 10)

	var mn: Vector3 = _pos[0]
	var mx: Vector3 = _pos[0]
	var kmax: float = 0.0
	for i in range(_n):
		mn = mn.min(_pos[i])
		mx = mx.max(_pos[i])
		kmax = maxf(kmax, absf(_kappa[i]))
	_bmin = mn
	_bmax = mx
	_min_radius = 1.0 / maxf(kmax, 0.000001)
	_i_line = roundi((fposmod(_len - START_S, _len) if reversed else START_S) / _ds)
	_s_line = float(_i_line) * _ds
	_gate_s.resize(NUM_GATES)
	for g in range(NUM_GATES):
		_gate_s[g] = _len * float(g + 1) / float(NUM_GATES + 1)


# ================================================================ elevation
# height of the road (m) at a distance along the lap. The pit straight is flat; the lap climbs
# through the sweeper and esses to a crest, drops through the chicane to the hairpin in the
# valley, climbs round the long left-hander, crests on the back straight and runs back down.
const ELEV_SCALE := 1.35
const ELEV := [[0.0, 0.0], [800.0, 0.0], [1076.0, 6.0], [1250.0, 13.0], [1420.0, 20.0], [1480.0, 21.0],
	[1686.0, 14.0], [1830.0, 9.0], [2070.0, 3.0], [2170.0, 2.0], [2320.0, 5.0], [2508.0, 11.0],
	[2750.0, 16.0], [3063.0, 6.0], [3134.0, 5.0], [3320.0, 2.0], [3470.0, 0.0], [99999.0, 0.0]]

static func _elevation(s: float) -> float:
	## eased between the control heights: smooth, level at each control point, and it never
	## overshoots (a spline did, and sank the "flat" pit straight below the ground)
	var k := 0
	while k < ELEV.size() - 2 and s > ELEV[k + 1][0]:
		k += 1
	var p1: Array = ELEV[k]
	var p2: Array = ELEV[k + 1]
	var t: float = clampf((s - p1[0]) / maxf(p2[0] - p1[0], 1.0), 0.0, 1.0)
	return lerpf(p1[1], p2[1], smoothstep(0.0, 1.0, t))


# =================================================================== helpers
func _vtx(i: int, lat: float, h: float) -> Vector3:
	var k: int = posmod(i, _n)
	return _pos[k] + _right[k] * lat + Vector3(0.0, h, 0.0)


func _fill(v: float) -> PackedFloat32Array:
	var a: PackedFloat32Array = PackedFloat32Array()
	a.resize(_n)
	a.fill(v)
	return a


func _uv_tile() -> float:
	return _len / roundf(_len / 6.0)


func _ribbon(buf: MeshBuf, i0: int, count: int, a: PackedFloat32Array, b: PackedFloat32Array,
		h: float, col: Color, tile: float) -> void:
	for k in range(count):
		var i: int = i0 + k
		var ia: int = posmod(i, _n)
		var ib: int = posmod(i + 1, _n)
		var s0: float = float(i) * _ds / tile
		var s1: float = float(i + 1) * _ds / tile
		buf.quad(_vtx(i, a[ia], h), _vtx(i, b[ia], h), _vtx(i + 1, b[ib], h), _vtx(i + 1, a[ib], h),
				Vector3.UP, col,
				Vector2(a[ia] / tile, s0), Vector2(b[ia] / tile, s0),
				Vector2(b[ib] / tile, s1), Vector2(a[ib] / tile, s1))


func _box_run(buf: MeshBuf, i0: int, count: int, lat: float, width: float, y0: float, y1: float, col: Color) -> void:
	## Extruded box along the centerline; y0/y1 are heights above the grass (y = 0).
	var h0: float = y0 - ROAD_Y
	var h1: float = y1 - ROAD_Y
	var hw: float = width * 0.5
	for k in range(count):
		var i: int = i0 + k
		var r: Vector3 = _right[posmod(i, _n)]
		buf.quad(_vtx(i, lat - hw, h1), _vtx(i, lat + hw, h1), _vtx(i + 1, lat + hw, h1), _vtx(i + 1, lat - hw, h1), Vector3.UP, col)
		buf.quad(_vtx(i, lat - hw, h0), _vtx(i, lat - hw, h1), _vtx(i + 1, lat - hw, h1), _vtx(i + 1, lat - hw, h0), -r, col)
		buf.quad(_vtx(i, lat + hw, h0), _vtx(i, lat + hw, h1), _vtx(i + 1, lat + hw, h1), _vtx(i + 1, lat + hw, h0), r, col)


func _runs(mask: PackedByteArray, min_len: int) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	var i: int = 0
	while i < _n:
		if mask[i] != 0:
			var j: int = i
			while j < _n and mask[j] != 0:
				j += 1
			if j - i >= min_len:
				res.append(Vector2i(i, j - i))
			i = j
		else:
			i += 1
	return res


func _run_angle(r: Vector2i) -> float:
	var a: float = 0.0
	for k in range(r.x, r.x + r.y):
		a += absf(_kappa[k]) * _ds
	return a


func _box(buf: MeshBuf, c: Vector3, size: Vector3, col: Color) -> void:
	var x: float = size.x * 0.5
	var y: float = size.y * 0.5
	var z: float = size.z * 0.5
	buf.quad(c + Vector3(x, -y, -z), c + Vector3(x, y, -z), c + Vector3(x, y, z), c + Vector3(x, -y, z), Vector3.RIGHT, col)
	buf.quad(c + Vector3(-x, -y, -z), c + Vector3(-x, y, -z), c + Vector3(-x, y, z), c + Vector3(-x, -y, z), Vector3.LEFT, col)
	buf.quad(c + Vector3(-x, y, -z), c + Vector3(x, y, -z), c + Vector3(x, y, z), c + Vector3(-x, y, z), Vector3.UP, col)
	buf.quad(c + Vector3(-x, -y, z), c + Vector3(x, -y, z), c + Vector3(x, y, z), c + Vector3(-x, y, z), Vector3.BACK, col)
	buf.quad(c + Vector3(-x, -y, -z), c + Vector3(x, -y, -z), c + Vector3(x, y, -z), c + Vector3(-x, y, -z), Vector3.FORWARD, col)


func _vc_mat(rough: float = 0.8) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m


func _add_static(node_name: String, faces: PackedVector3Array, mu: float) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mu", mu)
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _add_mesh(node_name: String, mesh: Mesh, shadows: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ================================================================== textures
func _noise_tex(seed_v: int, freq: float, size: int, contrast: float) -> ImageTexture:
	var nz: FastNoiseLite = FastNoiseLite.new()
	nz.seed = seed_v
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = freq
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	var img: Image = nz.get_seamless_image(size, size)
	img.convert(Image.FORMAT_RGB8)
	img.adjust_bcs(1.0, contrast, 1.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_textures() -> void:
	_tex_asphalt = _noise_tex(11, 0.045, 256, 0.55)
	_tex_grass = _noise_tex(23, 0.03, 256, 0.5)
	_tex_gravel = _noise_tex(37, 0.16, 256, 0.9)


# ==================================================================== ground
func _build_ground() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mu", 0.55)
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = bs
	cs.position = Vector3(0.0, -1.4, 0.0)
	body.add_child(cs)
	add_child(body)

	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	pm.subdivide_width = 0
	pm.material = Surfaces.grass()
	var gv := _add_mesh("GrassVisual", pm, false)
	gv.position.y = -0.4
	_build_terrain()


# ================================================================== terrain
const T_STEP := 8.0               # terrain grid spacing, m
const T_FLAT := 30.0              # within this distance of the centre line the ground follows the road
const T_BLEND := 95.0             # ... and blends into the rolling countryside by this distance
var _t_origin := Vector2.ZERO
var _t_nx := 0
var _t_nz := 0
var _t_h := PackedFloat32Array()

func terrain_height(x: float, z: float) -> float:
	## ground height at a point (bilinear in the terrain grid; flat outside it)
	if _t_h.is_empty():
		return 0.0
	var gx := (x - _t_origin.x) / T_STEP
	var gz := (z - _t_origin.y) / T_STEP
	if gx < 0.0 or gz < 0.0 or gx >= _t_nx - 1 or gz >= _t_nz - 1:
		return 0.0
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var a := _t_h[iz * _t_nx + ix]
	var b := _t_h[iz * _t_nx + ix + 1]
	var c := _t_h[(iz + 1) * _t_nx + ix]
	var d := _t_h[(iz + 1) * _t_nx + ix + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func _build_terrain() -> void:
	## Ground that carries the road over its hills: next to the track it sits just under the
	## road surface, further out it eases into low rolling countryside, and at the edge of the
	## grid it is back to the flat plain.
	var margin := 520.0
	_t_origin = Vector2(_bmin.x - margin, _bmin.z - margin)
	_t_nx = int((_bmax.x - _bmin.x + 2.0 * margin) / T_STEP) + 1
	_t_nz = int((_bmax.z - _bmin.z + 2.0 * margin) / T_STEP) + 1
	var cells := _t_nx * _t_nz
	var dmin := PackedFloat32Array()
	var enear := PackedFloat32Array()
	var wsum := PackedFloat32Array()
	var wesum := PackedFloat32Array()
	dmin.resize(cells)
	dmin.fill(1e9)
	enear.resize(cells)
	wsum.resize(cells)
	wesum.resize(cells)
	var r := int(ceil(T_BLEND / T_STEP))
	for i in range(0, _n):
		var p := _pos[i]
		var e := p.y - ROAD_Y
		var cx := int(round((p.x - _t_origin.x) / T_STEP))
		var cz := int(round((p.z - _t_origin.y) / T_STEP))
		for gz in range(maxi(cz - r, 0), mini(cz + r + 1, _t_nz)):
			var wz := _t_origin.y + gz * T_STEP - p.z
			for gx in range(maxi(cx - r, 0), mini(cx + r + 1, _t_nx)):
				var wx := _t_origin.x + gx * T_STEP - p.x
				var d2 := wx * wx + wz * wz
				if d2 > T_BLEND * T_BLEND:
					continue
				var k := gz * _t_nx + gx
				var w := 1.0 / ((d2 + 1.0) * (d2 + 1.0))
				wsum[k] += w
				wesum[k] += w * e
				if d2 < dmin[k]:
					dmin[k] = d2
					enear[k] = e
	var nz := FastNoiseLite.new()
	nz.seed = 31
	nz.frequency = 0.0035
	nz.fractal_octaves = 3
	_t_h.resize(cells)
	for gz in _t_nz:
		for gx in _t_nx:
			var k := gz * _t_nx + gx
			var x := _t_origin.x + gx * T_STEP
			var z := _t_origin.y + gz * T_STEP
			# countryside: low rolls, fading to flat at the grid border
			var edge := minf(minf(gx, _t_nx - 1 - gx), minf(gz, _t_nz - 1 - gz)) * T_STEP
			var base := (nz.get_noise_2d(x, z) * 0.5 + 0.5) * 7.0 * smoothstep(0.0, 160.0, edge)
			var h := base
			if dmin[k] < 1e8:
				var d := sqrt(dmin[k])
				# under the road the ground stays well clear of the surface (the grid is coarser than
				# the road's curves); beside it, just under kerb / gravel height
				var road: float = enear[k] - 0.35 if d < 9.0 else wesum[k] / wsum[k] - 0.06
				var a := smoothstep(T_BLEND, T_FLAT, d)
				h = lerpf(base, road, a)
			_t_h[k] = h
	# mesh + collision
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(cells)
	norms.resize(cells)
	for gz in _t_nz:
		for gx in _t_nx:
			var k := gz * _t_nx + gx
			verts[k] = Vector3(_t_origin.x + gx * T_STEP, _t_h[k], _t_origin.y + gz * T_STEP)
			var hl := _t_h[k - 1] if gx > 0 else _t_h[k]
			var hr := _t_h[k + 1] if gx < _t_nx - 1 else _t_h[k]
			var hd := _t_h[k - _t_nx] if gz > 0 else _t_h[k]
			var hu := _t_h[k + _t_nx] if gz < _t_nz - 1 else _t_h[k]
			norms[k] = Vector3(hl - hr, 2.0 * T_STEP, hd - hu).normalized()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	idx.resize((_t_nx - 1) * (_t_nz - 1) * 6)
	faces.resize(idx.size())
	var q := 0
	for gz in _t_nz - 1:
		for gx in _t_nx - 1:
			var a := gz * _t_nx + gx
			var b := a + 1
			var c := a + _t_nx
			var d := c + 1
			# clockwise seen from above = front face up in Godot
			idx[q] = a
			idx[q + 1] = b
			idx[q + 2] = c
			idx[q + 3] = b
			idx[q + 4] = d
			idx[q + 5] = c
			for o in 6:
				faces[q + o] = verts[idx[q + o]]
			q += 6
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = verts
	arrs[Mesh.ARRAY_NORMAL] = norms
	arrs[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	mesh.surface_set_material(0, Surfaces.grass())
	_add_mesh("Terrain", mesh, false)
	_add_static("TerrainBody", faces, 0.55)


# ===================================================================== road
func _mark_rect(buf: MeshBuf, s_center: float, lat_c: float, length: float, width: float, th: float) -> void:
	# Axis-aligned slot marking on the straight section.
	var i: int = posmod(roundi(s_center / _ds), _n)
	var c: Vector3 = _pos[i] + Vector3(0.0, 0.012, 0.0)
	var t: Vector3 = _tan[i]
	var r: Vector3 = _right[i]
	var col: Color = Color(0.92, 0.92, 0.9)
	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var mid: Vector3 = c + r * lat_c
	# back bar, front bar, two side bars
	buf.quad(mid - t * hl - r * hw, mid - t * hl + r * hw, mid - t * (hl - th) + r * hw, mid - t * (hl - th) - r * hw, Vector3.UP, col)
	buf.quad(mid + t * (hl - th) - r * hw, mid + t * (hl - th) + r * hw, mid + t * hl + r * hw, mid + t * hl - r * hw, Vector3.UP, col)
	buf.quad(mid - t * hl - r * hw, mid + t * hl - r * hw, mid + t * hl - r * (hw - th), mid - t * hl - r * (hw - th), Vector3.UP, col)
	buf.quad(mid - t * hl + r * (hw - th), mid + t * hl + r * (hw - th), mid + t * hl + r * hw, mid - t * hl + r * hw, Vector3.UP, col)


func _build_road() -> void:
	var tile: float = _uv_tile()
	var asph: MeshBuf = MeshBuf.new()
	var marks: MeshBuf = MeshBuf.new()
	var rubber: MeshBuf = MeshBuf.new()
	var check: MeshBuf = MeshBuf.new()

	_ribbon(asph, 0, _n, _fill(-HALF_W), _fill(HALF_W), 0.0, Color(0.92, 0.92, 0.93), tile)
	_ribbon(asph, 0, _n, _fill(HALF_W), _fill(COLL_HALF), 0.0, Color(1.15, 1.12, 1.08), tile)
	_ribbon(asph, 0, _n, _fill(-COLL_HALF), _fill(-HALF_W), 0.0, Color(1.15, 1.12, 1.08), tile)

	# white edge lines
	_ribbon(marks, 0, _n, _fill(HALF_W - 0.5), _fill(HALF_W - 0.25), 0.012, Color(0.93, 0.93, 0.9), tile)
	_ribbon(marks, 0, _n, _fill(-HALF_W + 0.25), _fill(-HALF_W + 0.5), 0.012, Color(0.93, 0.93, 0.9), tile)

	# rubbered-in racing line: leans towards the inside of corners
	var line: PackedFloat32Array = PackedFloat32Array()
	line.resize(_n)
	for i in range(_n):
		line[i] = clampf(_kappa_s[i] * 150.0, -3.2, 3.2)
	line = _smooth(line, 15)
	var la: PackedFloat32Array = PackedFloat32Array()
	var lb: PackedFloat32Array = PackedFloat32Array()
	la.resize(_n)
	lb.resize(_n)
	for i in range(_n):
		la[i] = line[i] - 1.2
		lb[i] = line[i] + 1.2
	_ribbon(rubber, 0, _n, la, lb, 0.006, Color(0.02, 0.02, 0.02, 0.38), tile)

	# start / finish checkered band (1 m long, centred on the line)
	var c: Vector3 = _pos[_i_line] + Vector3(0.0, 0.014, 0.0)
	var t: Vector3 = _tan[_i_line]
	var r: Vector3 = _right[_i_line]
	check.quad(c - t * 0.5 - r * HALF_W, c - t * 0.5 + r * HALF_W, c + t * 0.5 + r * HALF_W, c + t * 0.5 - r * HALF_W,
			Vector3.UP, Color.WHITE, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

	# grid slots: 10 staggered boxes behind the line
	for k in range(5):
		_mark_rect(marks, _s_line - 6.0 - 9.0 * float(k), -2.8, 4.8, 2.4, 0.15)
		_mark_rect(marks, _s_line - 10.5 - 9.0 * float(k), 2.8, 4.8, 2.4, 0.15)

	var mesh: ArrayMesh = ArrayMesh.new()
	asph.commit(mesh, Surfaces.asphalt())
	marks.commit(mesh, _vc_mat(0.7))
	var rub_mat: StandardMaterial3D = _vc_mat(0.9)
	rub_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rubber.commit(mesh, rub_mat)

	var cimg: Image = Image.create(26, 2, false, Image.FORMAT_RGB8)
	for x in range(26):
		for y in range(2):
			cimg.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.03, 0.03, 0.03))
	var cmat: StandardMaterial3D = StandardMaterial3D.new()
	cmat.albedo_texture = ImageTexture.create_from_image(cimg)
	cmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cmat.roughness = 0.7
	check.commit(mesh, cmat)
	_add_mesh("Road", mesh)

	# gentle grass ramps from the paved edge down to the ground (drawn and solid): a car coming
	# back from the grass rolls up onto the road instead of catching a thin road edge
	var bank: MeshBuf = MeshBuf.new()
	var bank_col: MeshBuf = MeshBuf.new()
	var soil: Color = Color(0.20, 0.22, 0.12)
	for i in range(_n):
		for side in [-1.0, 1.0]:
			var o: float = side * COLL_HALF
			var o2: float = side * (COLL_HALF + 3.0)
			bank.quad(_vtx(i, o, 0.0), _vtx(i + 1, o, 0.0), _vtx(i + 1, o2, -0.45), _vtx(i, o2, -0.45),
					Vector3.UP + _right[i] * side * 0.15, soil)
			bank_col.quad(_vtx(i, o, 0.0), _vtx(i + 1, o, 0.0), _vtx(i + 1, o2, -0.45), _vtx(i, o2, -0.45),
					Vector3.UP, soil)
	var bank_mesh: ArrayMesh = ArrayMesh.new()
	bank.commit(bank_mesh, Surfaces.grass())
	_add_mesh("RoadBanks", bank_mesh, false)
	_add_static("RoadBanksBody", bank_col.to_faces(), 0.6)

	# collision: one gap-free trimesh over road + paved shoulders
	var col: MeshBuf = MeshBuf.new()
	_ribbon(col, 0, _n, _fill(-COLL_HALF), _fill(COLL_HALF), 0.0, Color.WHITE, tile)
	_add_static("RoadBody", col.to_faces(), 1.0)


# ==================================================================== curbs
func _curb_run(buf: MeshBuf, i0: int, count: int, side: int) -> void:
	var cl: PackedFloat32Array = PackedFloat32Array([6.5, 6.85, 7.65, 8.0])
	var ch: PackedFloat32Array = PackedFloat32Array([0.0, CURB_H, CURB_H, 0.0])
	for k in range(count):
		var i: int = i0 + k
		var col: Color = Color(0.50, 0.035, 0.03) if (i & 1) == 0 else Color(0.80, 0.80, 0.78)
		for j in range(3):
			buf.quad(_vtx(i, side * cl[j], ch[j]), _vtx(i, side * cl[j + 1], ch[j + 1]),
					_vtx(i + 1, side * cl[j + 1], ch[j + 1]), _vtx(i + 1, side * cl[j], ch[j]),
					Vector3.UP, col)


func _build_curbs() -> void:
	var buf: MeshBuf = MeshBuf.new()
	var thr_in: float = 1.0 / 230.0
	var thr_out: float = 1.0 / 80.0
	for side in [1, -1]:
		var m_in: PackedByteArray = PackedByteArray()
		var m_out: PackedByteArray = PackedByteArray()
		m_in.resize(_n)
		m_out.resize(_n)
		for i in range(_n):
			var kk: float = float(side) * _kappa_s[i]
			m_in[i] = 1 if kk > thr_in else 0
			m_out[i] = 1 if kk < -thr_out else 0
		for r: Vector2i in _runs(m_in, 8):
			_curb_run(buf, r.x, r.y, side)
		for r: Vector2i in _runs(m_out, 10):
			_curb_run(buf, r.x, r.y, side)
	var mesh: ArrayMesh = ArrayMesh.new()
	buf.commit(mesh, _vc_mat(0.7))
	_add_mesh("Curbs", mesh)
	if not buf.verts.is_empty():
		_add_static("CurbBody", buf.to_faces(), 0.95)


# =================================================================== gravel
func _build_gravel() -> void:
	var buf: MeshBuf = MeshBuf.new()
	var thr: float = 1.0 / 75.0
	var gh: float = 0.012 - ROAD_Y
	_gravel_out = [_fill(0.0), _fill(0.0)]
	for side in [1, -1]:
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(_n)
		for i in range(_n):
			mask[i] = 1 if float(side) * _kappa_s[i] < -thr else 0
		for r: Vector2i in _runs(mask, 10):
			if _run_angle(r) < 1.0:
				continue
			var st: int = maxi(0, r.x - 12)
			var en: int = mini(_n, r.x + r.y + 12)
			var a: PackedFloat32Array = _fill(float(side) * 8.0)
			var b: PackedFloat32Array = _fill(float(side) * 8.0)
			for k in range(st, en):
				var t: float = clampf(float(mini(k - st, en - 1 - k)) / 10.0, 0.0, 1.0)
				b[k] = float(side) * (8.0 + 20.0 * smoothstep(0.0, 1.0, t))
			_ribbon(buf, st, en - st - 1, a, b, gh, Color.WHITE, 4.0)
			var gout: PackedFloat32Array = _gravel_out[0 if side < 0 else 1]
			for k2 in range(st, en):
				gout[k2] = maxf(gout[k2], absf(b[k2]))
			_gravel_out[0 if side < 0 else 1] = gout
			if _run_angle(r) > 2.6:
				_hairpin_run = Vector2i(st, en - st - 1)
				_hairpin_side = side
	var mesh: ArrayMesh = ArrayMesh.new()
	buf.commit(mesh, Surfaces.gravel())
	_add_mesh("Gravel", mesh, false)
	if not buf.verts.is_empty():
		_add_static("GravelBody", buf.to_faces(), 0.40)


# ================================================================== barriers
func _tyre_wall(col_buf: MeshBuf, xforms: Array[Transform3D], colors: Array[Color],
		rng: RandomNumberGenerator, i0: int, count: int, lat: float) -> void:
	_wall_run(i0, count, lat, 1.0, 1.3)
	for k in range(count):
		var i: int = i0 + k
		for half in range(2):
			var u: float = 0.5 * float(half)
			for column in range(2):
				var cl: float = lat + (-0.5 if column == 0 else 0.5)
				for row in range(4):
					var off: float = 0.0 if (row % 2 == 0) else 0.25
					var ii: float = float(i) + u + off / SPACING
					var i_lo: int = posmod(floori(ii), _n)
					var i_hi: int = posmod(i_lo + 1, _n)
					var f: float = ii - floorf(ii)
					var p: Vector3 = _pos[i_lo].lerp(_pos[i_hi], f) + _right[i_lo] * cl
					p.y = _pos[i_lo].y - ROAD_Y + 0.16 + 0.32 * float(row)
					xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
					var shade: float = rng.randf_range(0.04, 0.16)
					var c: Color = Color(shade, shade, shade * 1.1)
					if rng.randf() < 0.12:
						c = Color(0.85, 0.85, 0.85)
					colors.append(c)


func _build_barriers() -> void:
	var col: MeshBuf = MeshBuf.new()
	var conc: MeshBuf = MeshBuf.new()
	var armco: MeshBuf = MeshBuf.new()
	var posts: Array[Transform3D] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 777

	# concrete walls along the pit straight (both sides)
	var ia: int = _nearest_global(Vector3(-345.0, 0.0, 0.0))
	var ib: int = _nearest_global(Vector3(435.0, 0.0, 0.0))
	if ib < ia:
		var tmp := ia
		ia = ib
		ib = tmp
	# north side (pit lane side) only between pit entry and exit, so cars can get in and out
	var north: float = -1.0 if _right[ia].z > 0.0 else 1.0
	var pa: int = _nearest_global(Vector3(PIT_X0, 0.0, 0.0))
	var pb: int = _nearest_global(Vector3(PIT_X1, 0.0, 0.0))
	if pb < pa:
		var tmp2 := pa
		pa = pb
		pb = tmp2
	for side in [-1.0, 1.0]:
		var a0: int = pa if side == north else ia
		var a1: int = pb if side == north else ib
		_box_run(conc, a0, a1 - a0, side * 9.8, 0.5, 0.0, 0.9, Color(0.46, 0.46, 0.44))
		_wall_run(a0, a1 - a0, side * 9.8, 0.25, 2.2)                       # wall + catch fence

	# Armco all round the lap, behind the run-off: ~7 m of grass beyond the kerbs, further out
	# behind gravel traps. Not on the pit straight (concrete walls there), not where a tyre wall
	# stands, and never across another part of the track.
	var hp_lo: int = _hairpin_run.x
	var hp_hi: int = _hairpin_run.x + _hairpin_run.y
	var ch1: int = _nearest_global(Vector3(300.0, 0.0, 565.0))
	var ch2: int = _nearest_global(Vector3(205.0, 0.0, 565.0))
	var ch_lo: int = mini(ch1, ch2) - 6
	var ch_hi: int = maxi(ch1, ch2) + 6
	for sd in [-1.0, 1.0]:
		var lats: PackedFloat32Array = _fill(0.0)
		var ok: PackedByteArray = PackedByteArray()
		ok.resize(_n)
		var gout: PackedFloat32Array = _gravel_out[0 if sd < 0 else 1] if _gravel_out.size() == 2 else _fill(0.0)
		for i in range(_n):
			lats[i] = maxf(15.0, gout[i] + 2.5)
		lats = _smooth_lat(lats)
		for i in range(_n):
			var lat: float = lats[i]
			var p: Vector3 = _pos[i] + _right[i] * (sd * lat)
			var good := true
			if absf(p.z) < 32.0 and p.x > -365.0 and p.x < 455.0:
				good = false
			elif _hairpin_run.y > 0 and i >= hp_lo and i <= hp_hi and float(_hairpin_side) == sd:
				good = false
			elif i >= ch_lo and i <= ch_hi:
				good = false
			else:
				var j: int = _nearest_global(p)
				var dj: float = Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length()
				var apart: int = absi(posmod(j - i + _n / 2, _n) - _n / 2)
				if dj < lat - 1.5 and apart > 25:
					good = false
			ok[i] = 1 if good else 0
		for r: Vector2i in _runs(ok, 8):
			_barrier_run(armco, col, posts, r.x, r.y, lats, sd)

	# tyre walls: hairpin outside + chicane exits
	var tyre_xf: Array[Transform3D] = []
	var tyre_col: Array[Color] = []
	if _hairpin_run.y > 0:
		_tyre_wall(col, tyre_xf, tyre_col, rng, _hairpin_run.x, _hairpin_run.y, float(_hairpin_side) * 29.6)
	var c1: int = _nearest_global(Vector3(300.0, 0.0, 565.0))
	var c2: int = _nearest_global(Vector3(262.0, 0.0, 565.0))
	var c3: int = _nearest_global(Vector3(245.0, 0.0, 565.0))
	var c4: int = _nearest_global(Vector3(205.0, 0.0, 565.0))
	# heading west: right = north (+lat). North outside of bend 1, south outside of bend 2.
	# the outside of each chicane bend; driving the other way the lateral sides swap
	var flip: float = -1.0 if reversed else 1.0
	_tyre_wall(col, tyre_xf, tyre_col, rng, mini(c1, c2), absi(c2 - c1), 11.5 * flip)
	_tyre_wall(col, tyre_xf, tyre_col, rng, mini(c3, c4), absi(c4 - c3), -11.5 * flip)

	# visuals
	var cm: ArrayMesh = ArrayMesh.new()
	conc.commit(cm, _vc_mat(0.85))
	_add_mesh("ConcreteWalls", cm)
	var am: ArrayMesh = ArrayMesh.new()
	armco.commit(am, _vc_mat(0.4))
	_add_mesh("Armco", am)
	if not _walls.is_empty():
		# walls are solid boxes, not thin mesh shells: a thin shell can throw a car into the air
		var body := StaticBody3D.new()
		body.name = "BarrierBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("mu", 0.4)
		# slippery steel / concrete: a car scrapes along instead of climbing the barrier
		var pm := PhysicsMaterial.new()
		pm.friction = 0.12
		pm.bounce = 0.0
		body.physics_material_override = pm
		for w in _walls:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = w[1]
			cs.shape = bs
			cs.transform = w[0]
			body.add_child(cs)
		add_child(body)

	if not posts.is_empty():
		var pmesh: BoxMesh = BoxMesh.new()
		pmesh.size = Vector3(0.12, 0.8, 0.14)
		var pmat: StandardMaterial3D = StandardMaterial3D.new()
		pmat.albedo_color = Color(0.25, 0.25, 0.27)
		pmesh.material = pmat
		_add_multimesh("ArmcoPosts", pmesh, posts, [], false)

	if not tyre_xf.is_empty():
		var tm: CylinderMesh = CylinderMesh.new()
		tm.top_radius = 0.5
		tm.bottom_radius = 0.5
		tm.height = 0.32
		tm.radial_segments = 12
		tm.rings = 1
		tm.material = _vc_mat(0.95)
		_add_multimesh("TyreWalls", tm, tyre_xf, tyre_col, true)


var _walls: Array = []            # [Transform3D, size] solid wall / barrier boxes

func _wall_box(a: Vector3, b: Vector3, hw: float, h: float) -> void:
	## a solid box standing on the ground from a to b (sunk 0.4 m so there is no gap under it)
	var d := b - a
	d.y = 0.0
	var length := d.length()
	if length < 0.05:
		return
	var z := d / length
	var x := Vector3.UP.cross(z).normalized()
	var mid := (a + b) * 0.5
	var basis := Basis(x, Vector3.UP, z)
	_walls.append([Transform3D(basis, mid + Vector3(0, (h - 0.4) * 0.5, 0)), Vector3(hw * 2.0, h + 0.4, length + 0.3)])

func _wall_run(i0: int, count: int, lat: float, hw: float, h: float) -> void:
	## solid wall boxes along the track at a fixed lateral offset, one per 4 m
	var k := 0
	while k < count:
		var k2 := mini(k + 2, count)
		var a := _vtx(i0 + k, lat, -ROAD_Y)
		var b := _vtx(i0 + k2, lat, -ROAD_Y)
		_wall_box(a, b, hw, h)
		k = k2

var _banner_spots: Array[Transform3D] = []

func _clear_of_track(p: Vector3, own: int, min_d: float) -> bool:
	## true when no other part of the circuit is within min_d of p
	var j := _nearest_global(p)
	var apart: int = absi(posmod(j - own + _n / 2, _n) - _n / 2)
	return apart < 25 or Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length() > min_d

func _on_pit_straight(p: Vector3) -> bool:
	return absf(p.z) < 34.0 and p.x > -370.0 and p.x < 460.0

func _build_dressing() -> void:
	## braking boards, marshal posts, sponsor banners on the armco, spectators in the stands
	var buf := MeshBuf.new()
	var labels: Array[Label3D] = []
	# --- 150 / 100 / 50 m boards before every slow corner, on the outside
	var mask := PackedByteArray()
	mask.resize(_n)
	for i in range(_n):
		mask[i] = 1 if absf(_kappa_s[i]) > 1.0 / 110.0 else 0
	for r: Vector2i in _runs(mask, 8):
		var turn := signf(_kappa_s[r.x + r.y / 2])
		for dist in [150, 100, 50]:
			var i := posmod(r.x - int(float(dist) / _ds), _n)
			var p := _pos[i] + _right[i] * (-turn * 10.5)
			if _on_pit_straight(p) or not _clear_of_track(p, i, 12.0):
				continue
			var gy := terrain_height(p.x, p.z)
			var face := Basis.looking_at(_tan[i], Vector3.UP)      # front (+Z) towards the cars
			var xf := Transform3D(face, Vector3(p.x, gy, p.z))
			_box(buf, xf * Vector3(0, 0.6, 0.05), Vector3(0.12, 1.2, 0.12), Color(0.35, 0.35, 0.37))
			buf.quad(xf * Vector3(-0.6, 1.2, 0.0), xf * Vector3(0.6, 1.2, 0.0), xf * Vector3(0.6, 2.0, 0.0), xf * Vector3(-0.6, 2.0, 0.0),
					face.z, Color(0.95, 0.95, 0.95))
			var lb := Label3D.new()
			lb.text = str(dist)
			lb.font_size = 72
			lb.pixel_size = 0.009
			lb.modulate = Color(0.05, 0.05, 0.05)
			lb.outline_size = 0
			lb.transform = Transform3D(face, xf * Vector3(0, 1.6, 0.02))
			labels.append(lb)
	# --- marshal posts every ~400 m, behind the barrier, alternating sides
	var side := 1.0
	var i2 := 0
	while i2 < _n:
		side = -side
		var gout: PackedFloat32Array = _gravel_out[0 if side < 0 else 1] if _gravel_out.size() == 2 else _fill(0.0)
		var lat: float = maxf(15.0, gout[i2] + 2.5) + 3.0
		var p2 := _pos[i2] + _right[i2] * (side * lat)
		if not _on_pit_straight(p2) and _clear_of_track(p2, i2, lat + 2.0):
			var gy2 := terrain_height(p2.x, p2.z)
			var b2 := Basis.looking_at(-_right[i2] * side, Vector3.UP)
			var x2 := Transform3D(b2, Vector3(p2.x, gy2, p2.z))
			_box(buf, x2 * Vector3(0, 1.1, 0), Vector3(1.6, 2.2, 1.3), Color(0.95, 0.42, 0.05))
			_box(buf, x2 * Vector3(0, 2.3, 0), Vector3(1.9, 0.15, 1.6), Color(0.92, 0.92, 0.92))
			_box(buf, x2 * Vector3(0, 1.4, 0.66), Vector3(1.0, 0.6, 0.02), Color(0.12, 0.15, 0.2))
			_box(buf, x2 * Vector3(0.7, 3.0, 0.5), Vector3(0.04, 1.5, 0.04), Color(0.3, 0.3, 0.3))
			_box(buf, x2 * Vector3(0.92, 3.5, 0.5), Vector3(0.4, 0.3, 0.02), Color(0.1, 0.55, 0.15))
		i2 += 200
	# --- sponsor banners on the armco, facing the track
	var names := ["APEX TYRES", "TURBO OIL", "VALLEY GP", "NITRO FUEL", "GRIP+", "DRIFT CUP", "CARBON WORKS", "RAPID BRAKES"]
	var cols := [Color(0.75, 0.1, 0.08), Color(0.1, 0.3, 0.7), Color(0.95, 0.75, 0.05), Color(0.08, 0.45, 0.2),
		Color(0.1, 0.1, 0.12), Color(0.55, 0.1, 0.55), Color(0.85, 0.85, 0.88), Color(0.95, 0.4, 0.05)]
	for k in _banner_spots.size():
		var xf3: Transform3D = _banner_spots[k]
		var c: Color = cols[k % cols.size()]
		buf.quad(xf3 * Vector3(-2.4, -0.18, 0.0), xf3 * Vector3(2.4, -0.18, 0.0), xf3 * Vector3(2.4, 0.18, 0.0), xf3 * Vector3(-2.4, 0.18, 0.0),
				xf3.basis.z, c)
		var lb2 := Label3D.new()
		lb2.text = names[k % names.size()]
		lb2.font_size = 64
		lb2.pixel_size = 0.0045
		lb2.outline_size = 0
		lb2.modulate = Color(0.05, 0.05, 0.05) if c.get_luminance() > 0.5 else Color(1, 1, 1)
		lb2.transform = Transform3D(xf3.basis, xf3 * Vector3(0, 0, 0.015))
		labels.append(lb2)
	var mesh := ArrayMesh.new()
	buf.commit(mesh, _vc_mat(0.7))
	_add_mesh("TrackDressing", mesh)
	for lb3 in labels:
		add_child(lb3)
	_build_crowd()

func _build_crowd() -> void:
	## spectators on the grandstand tiers (pit straight), standing in loose groups
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var shirts := [Color(0.8, 0.1, 0.1), Color(0.1, 0.25, 0.7), Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1),
		Color(0.95, 0.75, 0.1), Color(0.2, 0.55, 0.25), Color(0.95, 0.45, 0.1), Color(0.5, 0.5, 0.55)]
	var face := Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	for cx in [-250.0, -140.0, -30.0]:
		for t in 6:
			var x: float = cx - 48.0
			while x < cx + 48.0:
				x += rng.randf_range(0.55, 0.9)
				if rng.randf() < 0.3:
					continue
				var h := rng.randf_range(0.92, 1.08)
				var z := 25.5 + 2.5 * t + rng.randf_range(-0.4, 0.4)
				xf.append(Transform3D(face.scaled(Vector3(1.0, h, 1.0)), Vector3(x, float(t + 1) + 0.55 * h, z)))
				col.append((shirts[rng.randi() % shirts.size()] as Color) * rng.randf_range(0.8, 1.1))
	var m := CapsuleMesh.new()
	m.radius = 0.2
	m.height = 1.1
	m.radial_segments = 6
	m.rings = 2
	m.material = _vc_mat(0.9)
	_add_multimesh("Crowd", m, xf, col, false)

func _smooth_lat(a: PackedFloat32Array) -> PackedFloat32Array:
	## ease the barrier line in and out where it steps back behind a gravel trap
	var out: PackedFloat32Array = a.duplicate()
	for pass_i in 4:
		var src := out.duplicate()
		for i in range(_n):
			out[i] = maxf(src[i], (src[posmod(i - 6, _n)] + src[i] * 2.0 + src[posmod(i + 6, _n)]) * 0.25)
	return out

func _barrier_run(armco: MeshBuf, col: MeshBuf, posts: Array[Transform3D], i0: int, count: int,
		lats: PackedFloat32Array, sd: float) -> void:
	## one armco run on the ground: rail 0.45-0.8 m up, collision box 0-1 m, a post every 4 m
	for k in range(count):
		var ia: int = posmod(i0 + k, _n)
		var ib: int = posmod(i0 + k + 1, _n)
		var pa: Vector3 = _pos[ia] + _right[ia] * (sd * lats[ia])
		var pb: Vector3 = _pos[ib] + _right[ib] * (sd * lats[ib])
		var ga: float = terrain_height(pa.x, pa.z)
		var gb: float = terrain_height(pb.x, pb.z)
		var ra: Vector3 = _right[ia] * sd
		var rb: Vector3 = _right[ib] * sd
		var specs := [[armco, 0.07, 0.45, 0.8, Color(0.74, 0.76, 0.78)]]
		for spec in specs:
			var buf: MeshBuf = spec[0]
			var hw: float = spec[1]
			var up0 := Vector3(0, spec[2], 0)
			var up1 := Vector3(0, spec[3], 0)
			var c: Color = spec[4]
			var a_in := Vector3(pa.x, ga, pa.z) - ra * hw
			var a_out := Vector3(pa.x, ga, pa.z) + ra * hw
			var b_in := Vector3(pb.x, gb, pb.z) - rb * hw
			var b_out := Vector3(pb.x, gb, pb.z) + rb * hw
			buf.quad(a_in + up1, a_out + up1, b_out + up1, b_in + up1, Vector3.UP, c)
			buf.quad(a_in + up0, a_in + up1, b_in + up1, b_in + up0, -ra, c)
			buf.quad(a_out + up0, a_out + up1, b_out + up1, b_out + up0, ra, c)
		if k % 2 == 0:
			if k % 30 == 14:
				_banner_spots.append(Transform3D(Basis.looking_at(ra, Vector3.UP), Vector3(pa.x, ga + 0.62, pa.z) - ra * 0.12))   # front faces the track
			# solid collision every 4 m: up to catch-fence height, so cars cannot climb over
			var ic: int = posmod(i0 + mini(k + 2, count), _n)
			var pc: Vector3 = _pos[ic] + _right[ic] * (sd * lats[ic])
			_wall_box(Vector3(pa.x, ga, pa.z), Vector3(pc.x, terrain_height(pc.x, pc.z), pc.z), 0.2, 2.2)
			var bas: Basis = Basis(ra, Vector3.UP, ra.cross(Vector3.UP))
			posts.append(Transform3D(bas, Vector3(pa.x, ga + 0.4, pa.z) + ra * 0.12))

func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], colors: Array, shadows: bool) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in range(xforms.size()):
		mm.set_instance_transform(k, xforms[k])
		if not colors.is_empty():
			mm.set_instance_color(k, colors[k])
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ===================================================================== decor
func _build_decor() -> void:
	var buf: MeshBuf = MeshBuf.new()
	var stand_boxes: Array[Vector3] = []

	# grandstands on the south side of the pit straight
	var seat_cols: Array[Color] = [Color(0.18, 0.32, 0.65), Color(0.75, 0.2, 0.2), Color(0.78, 0.78, 0.8)]
	var stand_x: Array[float] = [-250.0, -140.0, -30.0]
	for si in range(stand_x.size()):
		var cx: float = stand_x[si]
		for t in range(6):
			var h: float = 1.0 * float(t + 1)
			_box(buf, Vector3(cx, h * 0.5, 24.0 + 1.5 + 2.5 * float(t)), Vector3(100.0, h, 2.5), seat_cols[(t + si) % 3])
		_box(buf, Vector3(cx, 8.0, 32.0), Vector3(102.0, 0.3, 19.0), Color(0.9, 0.9, 0.92))
		for px in range(5):
			_box(buf, Vector3(cx - 48.0 + 24.0 * float(px), 4.0, 40.5), Vector3(0.5, 8.0, 0.5), Color(0.5, 0.5, 0.55))
		stand_boxes.append(Vector3(cx, 0.0, 32.0))
		_stands.append(Vector3(cx, 0.0, 32.0))
	# pit building on the north side
	_box(buf, Vector3(-60.0, 3.0, -30.0), Vector3(260.0, 6.0, 10.0), Color(0.55, 0.56, 0.58))
	_box(buf, Vector3(-60.0, 6.2, -30.0), Vector3(264.0, 0.4, 12.0), Color(0.3, 0.3, 0.34))

	# start/finish gantry (visual only; >= 6.8 m clearance)
	var gp: Vector3 = _pos[_i_line]
	_box(buf, Vector3(gp.x, 4.0, gp.z - 11.5), Vector3(0.9, 8.0, 0.9), Color(0.75, 0.1, 0.1))
	_box(buf, Vector3(gp.x, 4.0, gp.z + 11.5), Vector3(0.9, 8.0, 0.9), Color(0.75, 0.1, 0.1))
	_box(buf, Vector3(gp.x, 7.7, gp.z), Vector3(1.6, 1.8, 24.0), Color(0.12, 0.12, 0.15))

	# billboards on the north side, facing the track
	var bb_x: Array[float] = [-120.0, 60.0, 230.0, 370.0]
	var bb_txt: Array[String] = ["CAR SIM GP", "APEX TYRES", "DRIFT CUP", "TURBO OIL"]
	var bb_col: Array[Color] = [Color(0.8, 0.12, 0.1), Color(0.1, 0.3, 0.7), Color(0.9, 0.7, 0.05), Color(0.1, 0.5, 0.25)]
	var labels: Array[Label3D] = []
	for k in range(bb_x.size()):
		var bx: float = bb_x[k]
		# behind the pits, raised so they show over the garage roof
		_box(buf, Vector3(bx - 3.0, 4.6, -40.0), Vector3(0.25, 9.2, 0.25), Color(0.3, 0.3, 0.32))
		_box(buf, Vector3(bx + 3.0, 4.6, -40.0), Vector3(0.25, 9.2, 0.25), Color(0.3, 0.3, 0.32))
		_box(buf, Vector3(bx, 9.5, -40.0), Vector3(8.0, 2.6, 0.3), bb_col[k])
		var lb: Label3D = Label3D.new()
		lb.text = bb_txt[k]
		lb.font_size = 96
		lb.pixel_size = 0.0125
		lb.outline_size = 8
		lb.modulate = Color(1, 1, 1)
		lb.position = Vector3(bx, 9.5, -39.82)
		labels.append(lb)

	var mesh: ArrayMesh = ArrayMesh.new()
	buf.commit(mesh, _vc_mat(0.8))
	_add_mesh("Decor", mesh)
	for lb in labels:
		add_child(lb)
	var gl: Label3D = Label3D.new()
	gl.text = "START / FINISH"
	gl.font_size = 128
	gl.pixel_size = 0.0125
	gl.outline_size = 8
	gl.position = Vector3(gp.x - 0.82, 7.7, gp.z)
	gl.rotation = Vector3(0.0, PI * 0.5 if reversed else -PI * 0.5, 0.0)
	add_child(gl)

	# grandstand collision (one box each)
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = "StandsBody"
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("mu", 0.5)
	for c in stand_boxes:
		var bsh: BoxShape3D = BoxShape3D.new()
		bsh.size = Vector3(100.0, 6.0, 16.5)
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = bsh
		cs.position = Vector3(c.x, 3.0, 33.0)
		sb.add_child(cs)
	add_child(sb)

	# light poles along the straight
	var pole_xf: Array[Transform3D] = []
	var head_xf: Array[Transform3D] = []
	var x: float = -330.0
	while x <= 420.0:
		for side in [-1, 1]:
			# the north posts stand on the pit wall, clear of the pit lane
			var pz: float = 13.5 if side > 0 else 10.05
			pole_xf.append(Transform3D(Basis.IDENTITY, Vector3(x, 5.0, float(side) * pz)))
			head_xf.append(Transform3D(Basis.IDENTITY, Vector3(x, 10.1, float(side) * (pz - 0.8))))
		x += 70.0
	var pm: CylinderMesh = CylinderMesh.new()
	pm.top_radius = 0.1
	pm.bottom_radius = 0.16
	pm.height = 10.0
	pm.radial_segments = 8
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.45, 0.45, 0.48)
	pm.material = pmat
	_add_multimesh("LightPoles", pm, pole_xf, [], true)
	var hm: BoxMesh = BoxMesh.new()
	hm.size = Vector3(0.6, 0.2, 1.8)
	var hmat: StandardMaterial3D = StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.9, 0.85)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.95, 0.8)
	hmat.emission_energy_multiplier = 1.5
	hm.material = hmat
	_add_multimesh("LightHeads", hm, head_xf, [], false)


# ===================================================================== trees
func _build_trees() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20240611
	var coarse: PackedVector3Array = PackedVector3Array()
	for i in range(0, _n, 6):
		coarse.append(_pos[i])
	var trunk_xf: Array[Transform3D] = []
	var buckets := {}
	var tries: int = 0
	while trunk_xf.size() < 1100 and tries < 12000:
		tries += 1
		var px: float = rng.randf_range(_bmin.x - 450.0, _bmax.x + 450.0)
		var pz: float = rng.randf_range(_bmin.z - 450.0, _bmax.z + 450.0)
		var ok: bool = true
		for c: Vector3 in coarse:
			var dx: float = c.x - px
			var dz: float = c.z - pz
			if dx * dx + dz * dz < 48.0 * 48.0:
				ok = false
				break
		if not ok:
			continue
		for s: Vector3 in _stands:
			if absf(s.x - px) < 75.0 and absf(s.z - pz) < 40.0:
				ok = false
				break
		if not ok:
			continue
		var sc: float = rng.randf_range(0.75, 1.35)
		var yaw: Basis = Basis(Vector3.UP, rng.randf() * TAU)
		var gy := terrain_height(px, pz)
		var conifer := rng.randf() < 0.5
		var v := rng.randi_range(0, 2) if not conifer else rng.randi_range(0, 1)
		var key := ("c%d" if conifer else "b%d") % v
		if not buckets.has(key):
			buckets[key] = [[] as Array[Transform3D], []]
		(buckets[key][0] as Array[Transform3D]).append(Transform3D(yaw.scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.1), sc)), Vector3(px, gy, pz)))
		var g := rng.randf_range(0.8, 1.12)
		var tint := Color(g, g, g) if conifer else Color(g, g * rng.randf_range(0.95, 1.05), g * rng.randf_range(0.8, 1.0))
		(buckets[key][1] as Array).append(tint)
		trunk_xf.append(Transform3D())
	if trunk_xf.is_empty():
		return
	# a few tree shapes, each drawn many times (one MultiMesh per shape)
	for key: String in buckets.keys():
		var mesh: ArrayMesh = Foliage.conifer_mesh(400 + key.unicode_at(1)) if key.begins_with("c") else Foliage.broadleaf_mesh(100 + key.unicode_at(1))
		var xs: Array[Transform3D] = buckets[key][0]
		_add_multimesh("Trees_" + key, mesh, xs, buckets[key][1], not OS.has_feature("web"))


func _build_grass() -> void:
	## clumps of long grass on the verges and the banks behind the barriers; built in ~120 m
	## blocks so each block can fade out with distance on its own
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var mesh := Foliage.grass_mesh()
	var block := 60
	var i0 := 0
	while i0 < _n:
		var xs: Array[Transform3D] = []
		var cols: Array = []
		for i in range(i0, mini(i0 + block, _n)):
			for side: float in [-1.0, 1.0]:
				var gout: PackedFloat32Array = _gravel_out[0 if side < 0 else 1] if _gravel_out.size() == 2 else _fill(0.0)
				var barrier := maxf(15.0, gout[i] + 2.5)
				for k in 8:
					# denser close to the road, thinning out up the banks
					var lat := 9.6 + pow(rng.randf(), 1.6) * 32.0
					if lat < gout[i] + 0.8 or absf(lat - barrier) < 0.9:
						continue
					var p := _pos[i] + _right[i] * (side * lat) + (_pos[(i + 1) % _n] - _pos[i]).normalized() * rng.randf_range(-1.0, 1.0)
					if _on_pit_straight(p) or not _clear_of_track(p, i, 9.0):
						continue
					var sc := rng.randf_range(0.7, 1.5)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc))
					xs.append(Transform3D(b, Vector3(p.x, terrain_height(p.x, p.z) - 0.04, p.z)))
					var g := rng.randf_range(0.75, 1.1)
					cols.append(Color(g, g * rng.randf_range(0.95, 1.05), g * rng.randf_range(0.85, 1.0)))
		if not xs.is_empty():
			var mi := _add_multimesh("Grass", mesh, xs, cols, false)
			mi.visibility_range_end = 110.0 if not OS.has_feature("web") else 55.0
			mi.visibility_range_end_margin = 20.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		i0 += block


func _foliage_mat() -> StandardMaterial3D:
	## leaf canopy: rough, with a bumpy normal so the light breaks up, and some light bleeding through
	var m: StandardMaterial3D = _vc_mat(1.0)
	m.normal_enabled = true
	var nt: NoiseTexture2D = NoiseTexture2D.new()
	var nz: FastNoiseLite = FastNoiseLite.new()
	nz.frequency = 0.08
	nt.noise = nz
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 14.0
	m.normal_texture = nt
	m.normal_scale = 1.4
	m.uv1_scale = Vector3(3, 3, 3)
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.35, 0.1)
	return m


# ================================================================ pit lane
# north of the pit straight, between the pit wall and the garages; entry just after the
# last corner, exit before turn one. Stop in your box to change tyres, refuel and repair.
const PIT_X0 := -262.0
const PIT_X1 := 305.0
const PIT_Z := -16.5
const PIT_BOX := Vector3(-60.0, 0.0, -19.6)
const PIT_SPEED := 60.0 / 3.6

func in_pit_lane(p: Vector3) -> bool:
	return p.x > -338.0 and p.x < 383.0 and p.z < -8.7 and p.z > -23.0

func in_pit_box(p: Vector3) -> bool:
	return absf(p.x - PIT_BOX.x) < 3.2 and absf(p.z - PIT_BOX.z) < 2.6

func _slab(buf: MeshBuf, body_faces: MeshBuf, a: Vector3, b: Vector3, width: float) -> void:
	## flat road strip from a to b (also used for the angled entry and exit lanes)
	var d := (b - a)
	d.y = 0.0
	var side := d.normalized().cross(Vector3.UP) * width * 0.5
	var y := ROAD_Y
	var p0 := Vector3(a.x, y, a.z) - side
	var p1 := Vector3(a.x, y, a.z) + side
	var p2 := Vector3(b.x, y, b.z) + side
	var p3 := Vector3(b.x, y, b.z) - side
	buf.quad(p0, p1, p2, p3, Vector3.UP, Color(0.92, 0.92, 0.93))
	body_faces.quad(p0, p1, p2, p3, Vector3.UP, Color.WHITE)

func _build_pitlane() -> void:
	var road: MeshBuf = MeshBuf.new()
	var faces: MeshBuf = MeshBuf.new()
	var marks: MeshBuf = MeshBuf.new()
	_slab(road, faces, Vector3(-336.0, 0, -6.0), Vector3(PIT_X0, 0, PIT_Z + 2.0), 7.5)       # entry
	_slab(road, faces, Vector3(PIT_X0 - 4.0, 0, PIT_Z), Vector3(PIT_X1 + 4.0, 0, PIT_Z), 11.0)  # lane
	_slab(road, faces, Vector3(PIT_X1, 0, PIT_Z + 2.0), Vector3(381.0, 0, -6.0), 7.5)        # exit
	var white := Color(0.92, 0.92, 0.9)
	var yellow := Color(0.95, 0.78, 0.1)
	# lane lines, speed-limit lines, and the six pit boxes in front of the garages
	for z in [-11.2, -21.8]:
		marks.quad(Vector3(PIT_X0, 0.034, z - 0.1), Vector3(PIT_X1, 0.034, z - 0.1), Vector3(PIT_X1, 0.034, z + 0.1), Vector3(PIT_X0, 0.034, z + 0.1), Vector3.UP, white)
	for x in [PIT_X0 + 2.0, PIT_X1 - 2.0]:
		marks.quad(Vector3(x - 0.3, 0.034, -21.8), Vector3(x + 0.3, 0.034, -21.8), Vector3(x + 0.3, 0.034, -11.2), Vector3(x - 0.3, 0.034, -11.2), Vector3.UP, yellow)
	var garage := MeshBuf.new()
	for k in 6:
		var bx := PIT_BOX.x - 100.0 + 40.0 * k
		var col := yellow if absf(bx - PIT_BOX.x) < 1.0 else white
		var hx := 3.2
		var z0 := -22.0
		var z1 := -17.0
		for e in [[bx - hx, bx - hx + 0.15], [bx + hx - 0.15, bx + hx]]:
			marks.quad(Vector3(e[0], 0.035, z0), Vector3(e[1], 0.035, z0), Vector3(e[1], 0.035, z1), Vector3(e[0], 0.035, z1), Vector3.UP, col)
		marks.quad(Vector3(bx - hx, 0.035, z1 - 0.15), Vector3(bx + hx, 0.035, z1 - 0.15), Vector3(bx + hx, 0.035, z1), Vector3(bx - hx, 0.035, z1), Vector3.UP, col)
		# open garage door in the pit building front
		_box(garage, Vector3(bx, 2.2, -24.96), Vector3(6.0, 4.4, 0.1), Color(0.05, 0.05, 0.06))
	var mesh: ArrayMesh = ArrayMesh.new()
	road.commit(mesh, Surfaces.asphalt())
	marks.commit(mesh, _vc_mat(0.6))
	garage.commit(mesh, _vc_mat(0.9))
	_add_mesh("PitLane", mesh)
	_add_static("PitLaneBody", faces.to_faces(), 1.0)
	var sign := Label3D.new()
	sign.text = "PIT"
	sign.font_size = 160
	sign.pixel_size = 0.02
	sign.outline_size = 10
	sign.modulate = Color(1.0, 0.85, 0.2)
	sign.position = Vector3(PIT_BOX.x, 7.6, -24.9)
	add_child(sign)


# ============================================================== floodlights
var _flood: Array[Light3D] = []
var _flood_heads: StandardMaterial3D

func _build_floodlights() -> void:
	## masts round the lap (every ~110 m, outside the road, clear of other parts of the track)
	## plus the existing lamp posts on the pit straight. The lamps only switch on at night.
	var mast_xf: Array[Transform3D] = []
	var head_xf: Array[Transform3D] = []
	var spots: Array[Vector3] = []
	var i := 0
	var side := 1.0
	while i < _n:
		side = -side
		for lat in [17.0, 23.0, 30.0]:
			var p: Vector3 = _pos[i] + _right[i] * (side * lat)
			var j := _nearest_global(p)
			if Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length() > 14.0:
				var gy: float = terrain_height(p.x, p.z)
				mast_xf.append(Transform3D(Basis.IDENTITY, Vector3(p.x, gy + 7.0, p.z)))
				var head := Vector3(p.x, gy + 14.2, p.z) - _right[i] * side * 1.2
				head_xf.append(Transform3D(Basis(Vector3.UP, atan2(_right[i].x, _right[i].z)), head))
				spots.append(head)
				break
		i += 55
	if not mast_xf.is_empty():
		var mm: CylinderMesh = CylinderMesh.new()
		mm.top_radius = 0.12
		mm.bottom_radius = 0.2
		mm.height = 14.0
		mm.radial_segments = 8
		var mmat: StandardMaterial3D = StandardMaterial3D.new()
		mmat.albedo_color = Color(0.4, 0.4, 0.43)
		mmat.metallic = 0.6
		mmat.roughness = 0.5
		mm.material = mmat
		_add_multimesh("FloodMasts", mm, mast_xf, [], true)
		var hm: BoxMesh = BoxMesh.new()
		hm.size = Vector3(2.2, 0.3, 0.8)
		_flood_heads = StandardMaterial3D.new()
		_flood_heads.albedo_color = Color(0.85, 0.85, 0.8)
		_flood_heads.emission_enabled = true
		_flood_heads.emission = Color(1.0, 0.95, 0.85)
		_flood_heads.emission_energy_multiplier = 0.0
		hm.material = _flood_heads
		_add_multimesh("FloodHeads", hm, head_xf, [], false)
	# the pit-straight lamp posts (heads at 10.1 m, both sides, every 70 m)
	var x: float = -330.0
	while x <= 420.0:
		for s in [-1.0, 1.0]:
			spots.append(Vector3(x, 10.0, s * (12.7 if s > 0 else 9.25)))
		x += 70.0
	for sp in spots:
		var l := OmniLight3D.new()
		l.position = sp
		l.omni_range = 46.0
		l.omni_attenuation = 1.3
		l.light_energy = 3.2
		l.light_color = Color(1.0, 0.93, 0.82)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_flood.append(l)

func set_floodlights(on: bool) -> void:
	for l in _flood:
		l.visible = on
	if _flood_heads != null:
		_flood_heads.emission_energy_multiplier = 8.0 if on else 0.0


# ===================================================================== hills
func _build_hills() -> void:
	## a ring of low rolling hills on the horizon, so the world does not end at a flat edge
	var nz: FastNoiseLite = FastNoiseLite.new()
	nz.seed = 99
	nz.frequency = 0.9
	nz.fractal_octaves = 4
	var c: Vector3 = (_bmin + _bmax) * 0.5
	var seg: int = 160
	var radii: Array[float] = [1150.0, 1350.0, 1550.0, 1750.0, 1950.0]
	var buf: MeshBuf = MeshBuf.new()
	var hgt := func(a: float, ri: int) -> float:
		var edge: float = 0.0 if ri == 0 else 1.0
		var n: float = nz.get_noise_2d(cos(a) * 3.0 + float(ri) * 0.7, sin(a) * 3.0) * 0.5 + 0.5
		return edge * (25.0 + 170.0 * n * n) * (0.55 + 0.45 * float(ri) / 4.0)
	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		for r in range(radii.size() - 1):
			var p00: Vector3 = c + Vector3(cos(a0) * radii[r], hgt.call(a0, r), sin(a0) * radii[r])
			var p01: Vector3 = c + Vector3(cos(a1) * radii[r], hgt.call(a1, r), sin(a1) * radii[r])
			var p11: Vector3 = c + Vector3(cos(a1) * radii[r + 1], hgt.call(a1, r + 1), sin(a1) * radii[r + 1])
			var p10: Vector3 = c + Vector3(cos(a0) * radii[r + 1], hgt.call(a0, r + 1), sin(a0) * radii[r + 1])
			p00.y -= 0.5
			p01.y -= 0.5
			var shade: float = 0.8 + 0.2 * nz.get_noise_2d(a0 * 40.0, float(r))
			var col: Color = Color(0.17, 0.25, 0.10).lerp(Color(0.12, 0.17, 0.09), float(r) / 3.0) * shade
			buf.quad(p00, p01, p11, p10, Vector3.UP, col)
	var mesh: ArrayMesh = ArrayMesh.new()
	buf.commit(mesh, _vc_mat(1.0))
	_add_mesh("Hills", mesh, false)


# ===================================================================== props
func _spawn_prop(parent: Node3D, p: Vector3, mesh: Mesh, shape: Shape3D, mass: float) -> void:
	var rb: RigidBody3D = RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	rb.mass = mass
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	rb.position = p
	parent.add_child(rb)


func _build_props() -> void:
	var props: Node3D = Node3D.new()
	props.name = "Props"
	add_child(props)

	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.03
	cone_mesh.bottom_radius = 0.16
	cone_mesh.height = 0.5
	cone_mesh.radial_segments = 8
	cone_mesh.rings = 1
	var cmat: StandardMaterial3D = StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.4, 0.05)
	cone_mesh.material = cmat
	var cone_shape: CylinderShape3D = CylinderShape3D.new()
	cone_shape.radius = 0.15
	cone_shape.height = 0.5

	# cones on the chicane apex curbs
	var apexes: Array[Vector3] = [Vector3(277.5, 0.0, 557.0), Vector3(232.5, 0.0, 573.0)]
	for a in apexes:
		var ai: int = _nearest_global(a)
		var sgn: float = signf(_kappa_s[ai])
		for o in range(-8, 9, 4):
			var k: int = posmod(ai + o, _n)
			var p: Vector3 = _pos[k] + _right[k] * (sgn * 7.2)
			p.y = _pos[k].y + CURB_H + 0.25
			_spawn_prop(props, p, cone_mesh, cone_shape, 1.2)

	# clipping-point cones along the inside of the long constant radius corner
	var di: int = _nearest_global(Vector3(160.0, 0.0, 441.0))
	for o in range(-45, 46, 9):
		var k2: int = posmod(di + o, _n)
		var p2: Vector3 = _pos[k2] + _right[k2] * (signf(_kappa_s[k2]) * 5.4)
		p2.y = _pos[k2].y + 0.25
		_spawn_prop(props, p2, cone_mesh, cone_shape, 1.2)

	# loose tyre stacks in front of the hairpin tyre wall
	if _hairpin_run.y > 0:
		var ty_mesh: CylinderMesh = CylinderMesh.new()
		ty_mesh.top_radius = 0.45
		ty_mesh.bottom_radius = 0.45
		ty_mesh.height = 0.9
		ty_mesh.radial_segments = 12
		ty_mesh.rings = 1
		var tmat: StandardMaterial3D = StandardMaterial3D.new()
		tmat.albedo_color = Color(0.07, 0.07, 0.08)
		tmat.roughness = 0.95
		ty_mesh.material = tmat
		var ty_shape: CylinderShape3D = CylinderShape3D.new()
		ty_shape.radius = 0.45
		ty_shape.height = 0.9
		var st: int = _hairpin_run.x + 10
		var en: int = _hairpin_run.x + _hairpin_run.y - 10
		var k3: int = st
		while k3 < en:
			var kk: int = posmod(k3, _n)
			var p3: Vector3 = _pos[kk] + _right[kk] * (float(_hairpin_side) * 27.4)
			p3.y = _pos[kk].y - ROAD_Y + 0.46
			_spawn_prop(props, p3, ty_mesh, ty_shape, 30.0)
			k3 += 7
