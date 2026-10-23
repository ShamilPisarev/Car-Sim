class_name Weather
extends Node3D
## Time of day (day / sunset / night) and rain. Sets the sky and light (TestWorld),
## the wet-road shader global, rain falling around the camera, car headlights and the
## circuit floodlights. Physics reads Weather.grip() for the wet.

static var time_of_day := "day"
static var rain := false

const TIMES := ["day", "sunset", "night"]

static func grip() -> float:
	## wet tarmac on wet-weather tyres: roughly three quarters of the dry grip
	return 0.74 if rain else 1.0

static func lights_on() -> bool:
	return time_of_day != "day"

var world: TestWorld
var track                                      # RaceTrack (duck-typed)
var cam: Camera3D
var cars_fn: Callable                          # returns the cars currently in the scene
var _rain: GPUParticles3D

func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 9000
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1, 28)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 3.0
	pm.initial_velocity_min = 19.0
	pm.initial_velocity_max = 23.0
	pm.gravity = Vector3(0, -4, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.albedo_color = Color(0.78, 0.82, 0.88, 0.32)
	m.disable_receive_shadows = true
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)

func apply() -> void:
	if world != null:
		world.set_conditions(time_of_day, rain)
	RenderingServer.global_shader_parameter_set("wetness", 1.0 if rain else 0.0)
	_rain.emitting = rain
	var dm := _rain.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	# unlit streaks: keep them faint in the dark so they read as rain caught in the lights
	dm.albedo_color.a = 0.32 if time_of_day == "day" else (0.22 if time_of_day == "sunset" else 0.12)
	if track != null and track.has_method("set_floodlights"):
		track.set_floodlights(time_of_day == "night")
	refresh_cars()

func refresh_cars() -> void:
	if not cars_fn.is_valid():
		return
	var cars: Array = cars_fn.call()
	for k in cars.size():
		var c: Car = cars[k]
		if is_instance_valid(c):
			c.set_headlights(lights_on(), k == 0)

func _process(_dt: float) -> void:
	if cam != null and rain:
		# rain falls in a box that travels with the camera, a little ahead of it
		_rain.global_position = cam.global_position + Vector3(0, 13, 0) - cam.global_transform.basis.z * 8.0
