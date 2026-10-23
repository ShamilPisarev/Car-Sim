class_name SkidMarks
extends MultiMeshInstance3D
## Rubber marks on the road: one ring buffer of flat strips shared by every car.
## Oldest marks are overwritten once the buffer is full.

const CAPACITY := 8000
const WIDTH := 0.24

static var instance: SkidMarks
var _next := 0

func _ready() -> void:
	instance = self
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 4
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = gt
	m.roughness = 1.0
	m.metallic_specular = 0.0                    # rubber dust: no sky reflection, so marks read dark
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.material = m
	mm.mesh = pm
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 200, 10000))

func _exit_tree() -> void:
	if instance == self:
		instance = null

func add_segment(a: Vector3, b: Vector3, normal: Vector3, strength: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var z := d / length
	var x := normal.cross(z).normalized()
	var y := z.cross(x)
	var bas := Basis(x * WIDTH, y, z * (length + 0.06))
	var mid := (a + b) * 0.5 + normal * 0.02
	multimesh.set_instance_transform(_next, Transform3D(bas, mid))
	multimesh.set_instance_color(_next, Color(0.015, 0.015, 0.015, 0.7 * strength))
	_next = (_next + 1) % CAPACITY
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if _next > 0 else CAPACITY)

func clear_marks() -> void:
	multimesh.visible_instance_count = 0
	_next = 0
