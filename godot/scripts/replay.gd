class_name ReplaySystem
extends Node3D
## Records every car during a race (30 times a second) and plays the race back with TV
## cameras round the track that cut from one to the next and zoom onto the car.
## Keys while watching: Left / Right other car, Space pause, Up / Down speed, V TV / chase
## camera, Esc back to the results.

const RATE := 30.0
const STRIDE := 9                     # x, y, z, qx, qy, qz, qw, rpm, throttle

signal finished

var race: RaceManager
var cam: ChaseCam
var recording := false
var playing := false

var _cars: Array[Car] = []
var _data: Array[PackedFloat32Array] = []
var _frames := 0
var _acc := 0.0
var _t := 0.0                         # playback position, frames
var _speed := 1.0
var _paused := false
var _focus := 0
var _tv := true
var _tv_spots := PackedVector3Array()
var _label: Label
var _layer: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 15
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(20, 18)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_label)
	_layer.visible = false

func start_recording() -> void:
	_cars = race.cars.duplicate()
	_data.clear()
	for c in _cars:
		_data.append(PackedFloat32Array())
	_frames = 0
	_acc = 0.0
	recording = true
	_build_tv_spots()

func has_replay() -> bool:
	return _frames > RATE * 3.0

func _build_tv_spots() -> void:
	## trackside camera positions: every ~200 m, out beyond the run-off, on a short pole
	_tv_spots.clear()
	var step := int(200.0 / race.ds)
	var side := 1.0
	for i in range(0, race.n, step):
		side = -side
		var p: Vector3 = race.center[i] + race.right[i] * side * 26.0
		var gy: float = race.track.terrain_height(p.x, p.z) if race.track.has_method("terrain_height") else 0.0
		_tv_spots.append(Vector3(p.x, maxf(gy, race.center[i].y) + 7.5, p.z))

func _physics_process(dt: float) -> void:
	if not recording or playing or race == null:
		return
	if race.phase < RaceManager.Phase.GREEN:
		return
	_acc += dt
	if _acc < 1.0 / RATE:
		return
	_acc -= 1.0 / RATE
	for k in _cars.size():
		var c := _cars[k]
		if not is_instance_valid(c):
			continue
		var q := c.global_transform.basis.get_rotation_quaternion()
		var p := c.global_position
		_data[k].append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w, c.engine_rpm, c.throttle])
	_frames += 1

# ------------------------------------------------------------------ playback
func play() -> void:
	if not has_replay():
		return
	recording = false
	playing = true
	_t = 0.0
	_speed = 1.0
	_paused = false
	_focus = maxi(_cars.find(race.player), 0)
	_tv = true
	for c in _cars:
		if is_instance_valid(c):
			c.freeze = true
			c.process_mode = Node.PROCESS_MODE_DISABLED
	cam.mode = 5                                   # camera is driven from here
	_layer.visible = true

func stop() -> void:
	if not playing:
		return
	playing = false
	for c in _cars:
		if is_instance_valid(c):
			c.process_mode = Node.PROCESS_MODE_INHERIT
			c.freeze = race.dnf.has(c)
	cam.mode = 0
	cam.target = race.player
	_layer.visible = false
	finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not playing or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			stop()
		KEY_LEFT:
			_focus = posmod(_focus - 1, _cars.size())
		KEY_RIGHT:
			_focus = posmod(_focus + 1, _cars.size())
		KEY_SPACE:
			_paused = not _paused
		KEY_UP:
			_speed = minf(_speed * 2.0, 4.0)
		KEY_DOWN:
			_speed = maxf(_speed * 0.5, 0.25)
		KEY_V:
			_tv = not _tv
			cam.mode = 5 if _tv else 0
			cam._initialised = false
	get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if not playing:
		return
	if not _paused:
		_t += dt * RATE * _speed
	if _t >= _frames - 1:
		_t = _frames - 1
		_paused = true
	var i := int(_t)
	var f := _t - i
	for k in _cars.size():
		var c := _cars[k]
		var d := _data[k]
		if not is_instance_valid(c) or d.size() < (i + 2) * STRIDE:
			continue
		var a := i * STRIDE
		var b := a + STRIDE
		var pa := Vector3(d[a], d[a + 1], d[a + 2])
		var pb := Vector3(d[b], d[b + 1], d[b + 2])
		var qa := Quaternion(d[a + 3], d[a + 4], d[a + 5], d[a + 6])
		var qb := Quaternion(d[b + 3], d[b + 4], d[b + 5], d[b + 6])
		c.global_transform = Transform3D(Basis(qa.slerp(qb, f)), pa.lerp(pb, f))
		c.engine_rpm = lerpf(d[a + 7], d[b + 7], f)
		c.throttle = d[a + 8]
		# spin the wheels at road speed
		var v := pa.distance_to(pb) * RATE
		for w in c.wheels:
			w.omega = v / Car.WHEEL_R
			w.angle = wrapf(w.angle - w.omega * dt * _speed, -PI, PI)
			w.wheel_node.rotation.x = w.angle
	var focus := _cars[_focus]
	cam.target = focus
	if _tv and is_instance_valid(focus):
		_tv_camera(focus)
	var secs := int(_t / RATE)
	_label.text = "REPLAY  %d:%02d   %s   x%s%s\n<- -> car   Space pause   Up/Down speed   V camera   Esc back" % [
		secs / 60, secs % 60, race.name_of(focus), str(_speed), "  (paused)" if _paused else ""]

func _tv_camera(target: Car) -> void:
	## nearest trackside camera; long lens when the car is far away, wide when it passes close
	var tp := target.global_position + Vector3(0, 0.6, 0)
	var best := 0
	var bd := INF
	for k in _tv_spots.size():
		var d := _tv_spots[k].distance_squared_to(tp)
		if d < bd:
			bd = d
			best = k
	var cp := _tv_spots[best]
	cam.global_position = cp
	cam.look_at(tp, Vector3.UP)
	var dist := sqrt(bd)
	cam.fov = clampf(rad_to_deg(2.0 * atan(7.0 / maxf(dist, 1.0))), 9.0, 60.0)
