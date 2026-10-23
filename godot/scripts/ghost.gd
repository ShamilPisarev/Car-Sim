class_name GhostLap
extends Node3D
## Time trial: records every lap you drive, keeps the fastest as a see-through ghost car that
## replays it next to you, and shows the live gap to it. The best lap is saved per car and
## conditions (user://), so it is waiting for you next time.

const RATE := 20.0                     # samples per second
const STRIDE := 9                      # t, progress, x, y, z, qx, qy, qz, qw

var car: Car
var track                              # RaceTrack
var enabled := false
var best_time := 0.0
var best := PackedFloat32Array()       # the ghost lap
var delta := 0.0                       # gap to the ghost at this point of the lap (+ = slower)
var has_delta := false

var _rec := PackedFloat32Array()
var _last_lap_t := 0.0
var _sample_t := 0.0
var _model: Node3D
var _model_id := ""

func setup(c: Car, t) -> void:
	car = c
	track = t
	if not track.lap_completed.is_connected(_on_lap):
		track.lap_completed.connect(_on_lap)
	_load()

func _key() -> String:
	return "user://ghost_%s_%s%s%s.dat" % [car.spec_id, Weather.time_of_day, "_wet" if Weather.rain else "",
		"_arcade" if CarSpecs.arcade else ""]

func _load() -> void:
	best = PackedFloat32Array()
	best_time = 0.0
	if FileAccess.file_exists(_key()):
		var f := FileAccess.open(_key(), FileAccess.READ)
		var d = f.get_var()
		if d is Dictionary:
			best = d.get("samples", PackedFloat32Array())
			best_time = d.get("time", 0.0)
	_build_model()

func reset() -> void:
	## new session (car or conditions may have changed)
	_rec = PackedFloat32Array()
	_last_lap_t = 0.0
	if car != null:
		_load()

func _build_model() -> void:
	if _model != null and _model_id == car.spec_id:
		return
	if _model != null:
		_model.queue_free()
	_model_id = car.spec_id
	_model = (load(car.spec["glb"]) as PackedScene).instantiate()
	add_child(_model)
	var ghost := StandardMaterial3D.new()
	ghost.albedo_color = Color(0.55, 0.8, 1.0, 0.28)
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.emission_enabled = true
	ghost.emission = Color(0.3, 0.55, 0.9)
	ghost.emission_energy_multiplier = 0.4
	ghost.cull_mode = BaseMaterial3D.CULL_BACK
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = ghost
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.visible = false

func _on_lap(lap_time: float, _n: int) -> void:
	if not enabled:
		return
	if best_time <= 0.0 or lap_time < best_time:
		best_time = lap_time
		best = _rec.duplicate()
		var f := FileAccess.open(_key(), FileAccess.WRITE)
		if f != null:
			f.store_var({"time": lap_time, "samples": best})
	_rec = PackedFloat32Array()

func _physics_process(dt: float) -> void:
	if not enabled or car == null or track == null:
		if _model != null:
			_model.visible = false
		has_delta = false
		return
	var t: float = track.current_lap_time
	if t < _last_lap_t - 0.5:
		_rec = PackedFloat32Array()            # a new lap started (or the timer was reset)
	_last_lap_t = t
	if not track._running:
		has_delta = false
		if _model != null:
			_model.visible = false
		return
	_sample_t += dt
	if _sample_t >= 1.0 / RATE:
		_sample_t = 0.0
		var q := car.global_transform.basis.get_rotation_quaternion()
		var p := car.global_position
		_rec.append_array([t, track.progress, p.x, p.y, p.z, q.x, q.y, q.z, q.w])
	_play(t)

func _find(arr: PackedFloat32Array, col: int, value: float) -> int:
	## last sample index whose column `col` is <= value (binary search, column is increasing)
	var lo := 0
	var hi := arr.size() / STRIDE - 1
	if hi < 1:
		return -1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if arr[mid * STRIDE + col] <= value:
			lo = mid
		else:
			hi = mid - 1
	return lo

func _play(t: float) -> void:
	var n := best.size() / STRIDE
	if n < 4 or _model == null:
		has_delta = false
		if _model != null:
			_model.visible = false
		return
	# ghost position at this lap time
	var i := _find(best, 0, t)
	if i < 0 or i >= n - 1:
		_model.visible = false
	else:
		var a := i * STRIDE
		var b := a + STRIDE
		var f := clampf((t - best[a]) / maxf(best[b] - best[a], 0.001), 0.0, 1.0)
		var pa := Vector3(best[a + 2], best[a + 3], best[a + 4])
		var pb := Vector3(best[b + 2], best[b + 3], best[b + 4])
		var qa := Quaternion(best[a + 5], best[a + 6], best[a + 7], best[a + 8])
		var qb := Quaternion(best[b + 5], best[b + 6], best[b + 7], best[b + 8])
		_model.global_transform = Transform3D(Basis(qa.slerp(qb, f)), pa.lerp(pb, f))
		# fade out when it sits right on top of you
		_model.visible = _model.global_position.distance_to(car.global_position) > 2.5
	# gap: when was the ghost at the point of the lap you are at now?
	var prog: float = track.progress
	var j := _find(best, 1, prog)
	if j >= 0 and j < n - 1 and prog > 0.01 and prog < 0.99:
		var a2 := j * STRIDE
		var b2 := a2 + STRIDE
		var g := clampf((prog - best[a2 + 1]) / maxf(best[b2 + 1] - best[a2 + 1], 1e-6), 0.0, 1.0)
		delta = t - lerpf(best[a2], best[b2], g)
		has_delta = true
	else:
		has_delta = false
