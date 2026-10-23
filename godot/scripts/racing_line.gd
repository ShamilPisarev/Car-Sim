class_name RacingLineAssist
extends MeshInstance3D
## Driving aid: the racing line painted on the road ahead of you, green where you can push,
## yellow where you need to lift and red where you must brake (from the AI speed plan
## against your current speed). Mode 0 off, 1 braking zones only, 2 full line.

const AHEAD := 260.0              # metres of line shown
const WIDTH := 0.55

static var mode := 0

var race: RaceManager
var car: Car
var _im := ImmediateMesh.new()

func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 300, 10000))

func _process(_dt: float) -> void:
	_im.clear_surfaces()
	if mode == 0 or race == null or car == null or race.n == 0 or race.laps == -1:
		return
	var n := race.n
	var i0 := race.index_of(car)
	var v := car.linear_velocity.length()
	var steps := int(AHEAD / race.ds / 2.0)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var drawn := 0
	for k in steps:
		var i := (i0 + 3 + k * 2) % n
		var plan: float = race.line_speed[i] * 0.97
		var col: Color
		if plan < v - 3.0:
			col = Color(1.0, 0.12, 0.08)                    # brake
		elif plan < v + 4.0:
			col = Color(1.0, 0.8, 0.1)                      # lift / hold
		else:
			col = Color(0.15, 1.0, 0.35)                    # push
		var show := mode == 2 or col.g < 0.9
		var fade := clampf(1.0 - float(k) / steps, 0.0, 1.0)
		col.a = (0.55 * fade + 0.1) if show else 0.0
		var p := race.line_point(i) + Vector3(0, 0.035, 0)
		var r: Vector3 = race.right[i] * WIDTH * 0.5
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - r)
		_im.surface_set_color(col)
		_im.surface_add_vertex(p + r)
		drawn += 1
	_im.surface_end()
