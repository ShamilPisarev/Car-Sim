class_name TestWorld
extends Node3D
## Proving ground: asphalt pad, speed bumps, washboard, ramps, slalom cones, crash wall,
## gravel, a steep hill, poles, crates and a skid pad. Forward from the start is -z.

var asphalt_mat: Material = Surfaces.asphalt(false)
var paint_mat := StandardMaterial3D.new()
var concrete_mat := StandardMaterial3D.new()
var grass_mat: Material = Surfaces.grass()
var gravel_mat: Material = Surfaces.gravel()
var cone_mat := StandardMaterial3D.new()
var crate_mat := StandardMaterial3D.new()
var yellow_mat := StandardMaterial3D.new()
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial

func _ready() -> void:
	paint_mat.albedo_color = Color(0.9, 0.9, 0.9)
	concrete_mat.albedo_color = Color(0.55, 0.55, 0.57)
	concrete_mat.roughness = 0.95
	cone_mat.albedo_color = Color(1.0, 0.35, 0.05)
	crate_mat.albedo_color = Color(0.55, 0.38, 0.2)
	yellow_mat.albedo_color = Color(0.95, 0.8, 0.1)
	_environment()
	_ground()
	_markings()
	_bumps_and_washboard()
	_ramps()
	_slalom()
	_crash_area()
	_gravel_and_hill()
	_skidpad()
	_scenery()

const SKY_SHADER := """
shader_type sky;
// Late-afternoon sky: Rayleigh-ish gradient, Mie glow around the sun, sun disc and two layers of fbm clouds.
uniform vec3 zenith : source_color = vec3(0.16, 0.34, 0.72);
uniform vec3 horizon : source_color = vec3(0.70, 0.78, 0.86);
uniform vec3 ground : source_color = vec3(0.30, 0.32, 0.30);
uniform float cloud_cover = 0.48;
uniform float cloud_dark = 0.0;      // rain: heavy grey cloud
uniform float night = 0.0;           // stars, moon instead of sun
uniform vec3 glow_col : source_color = vec3(1.0, 0.62, 0.32);
uniform float disc = 40.0;

// sine-free hash: stays precise for large coordinates (no blocky artefacts near the horizon)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	vec3 sd = LIGHT0_DIRECTION;
	float sun_dot = max(dot(d, sd), 0.0);
	float h = max(d.y, 0.0);
	vec3 col = mix(horizon, zenith, pow(h, 0.45));
	// warm haze towards the sun near the horizon
	col += glow_col * pow(sun_dot, 6.0) * 0.35 * (1.0 - h) * (1.0 - cloud_dark);
	col += vec3(1.0, 0.85, 0.6) * pow(sun_dot, 64.0) * 0.6 * (1.0 - night) * (1.0 - cloud_dark);
	float c = 0.0;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12);
		float t = TIME * 0.004;
		float c1 = fbm(uv * 0.55 + vec2(t, t * 0.3));
		float c2 = fbm(uv * 1.6 - vec2(t * 1.7, 0.0));
		c = smoothstep(cloud_cover, cloud_cover + 0.28, c1 * 0.75 + c2 * 0.35);
		float thick = smoothstep(cloud_cover + 0.1, cloud_cover + 0.6, c1 * 0.75 + c2 * 0.35);
		vec3 lit = mix(vec3(1.0, 0.97, 0.92), vec3(0.62, 0.66, 0.74), thick) * LIGHT0_ENERGY * 0.8;
		lit = mix(lit, vec3(0.30, 0.32, 0.36) * (0.4 + LIGHT0_ENERGY * 0.5), cloud_dark);
		lit += glow_col * pow(sun_dot, 8.0) * 0.6 * (1.0 - thick) * (1.0 - cloud_dark);
		// stars between the clouds
		vec3 cell = floor(d * 420.0);
		float st = step(0.9972, hash(cell.xz + vec2(cell.y * 17.13, cell.y * 3.7)));
		col += vec3(0.9, 0.95, 1.0) * st * night * smoothstep(0.02, 0.25, d.y) * 1.6;
		float fade = smoothstep(0.02, 0.2, d.y);
		col = mix(col, lit, c * fade * 0.92);
	} else {
		col = mix(horizon * 0.9, ground, smoothstep(0.0, 0.25, -d.y));
	}
	// sun disc (only in the real sky, not in the radiance map to avoid fireflies)
	if (AT_CUBEMAP_PASS == false) {
		col += mix(vec3(1.0, 0.9, 0.75), vec3(0.85, 0.9, 1.0), night) * smoothstep(0.9994, 0.99975, sun_dot) * disc * (1.0 - c * 0.9);
	}
	COLOR = col;
}
"""

# time of day presets: sun angle (pitch, yaw), colour, energy; sky colours; fog; exposure
const PRESETS := {
	"day": {"rot": Vector3(-30, -58, 0), "col": Color(1.0, 0.92, 0.80), "energy": 2.1,
		"zenith": Color(0.16, 0.34, 0.72), "horizon": Color(0.70, 0.78, 0.86), "glow": Color(1.0, 0.62, 0.32),
		"fog": Color(0.66, 0.73, 0.82), "density": 0.00055, "ambient": 0.9, "exposure": 1.05, "night": 0.0, "disc": 40.0},
	"sunset": {"rot": Vector3(-6, -96, 0), "col": Color(1.0, 0.58, 0.30), "energy": 1.7,
		"zenith": Color(0.18, 0.24, 0.46), "horizon": Color(0.96, 0.62, 0.40), "glow": Color(1.0, 0.45, 0.18),
		"fog": Color(0.80, 0.58, 0.46), "density": 0.0007, "ambient": 0.55, "exposure": 1.15, "night": 0.0, "disc": 30.0},
	"night": {"rot": Vector3(-48, 35, 0), "col": Color(0.62, 0.72, 1.0), "energy": 0.10,
		"zenith": Color(0.006, 0.010, 0.028), "horizon": Color(0.035, 0.045, 0.08), "glow": Color(0.3, 0.35, 0.5),
		"fog": Color(0.03, 0.04, 0.07), "density": 0.0009, "ambient": 0.22, "exposure": 1.5, "night": 1.0, "disc": 5.0},
}

func set_conditions(time: String, rain: bool) -> void:
	## sky, sun / moon, fog and exposure for a time of day, darker and murkier when it rains
	var p: Dictionary = PRESETS.get(time, PRESETS["day"])
	var grey := Color(0.42, 0.44, 0.47) if time != "night" else Color(0.03, 0.035, 0.045)
	var r := 0.75 if rain else 0.0
	sun.rotation_degrees = p["rot"]
	sun.light_color = (p["col"] as Color).lerp(Color(0.8, 0.85, 0.9), r * 0.6)
	sun.light_energy = p["energy"] * (1.0 - 0.7 * r)
	sun.shadow_enabled = true
	sky_mat.set_shader_parameter("zenith", (p["zenith"] as Color).lerp(grey, r))
	sky_mat.set_shader_parameter("horizon", (p["horizon"] as Color).lerp(grey * 1.15, r))
	sky_mat.set_shader_parameter("glow_col", p["glow"])
	sky_mat.set_shader_parameter("cloud_cover", 0.48 - 0.36 * r)
	sky_mat.set_shader_parameter("cloud_dark", r)
	sky_mat.set_shader_parameter("night", p["night"])
	sky_mat.set_shader_parameter("disc", p["disc"])
	env.fog_light_color = (p["fog"] as Color).lerp(grey, r)
	env.fog_density = p["density"] * (1.0 + 3.5 * r)
	env.fog_sun_scatter = 0.35 * (1.0 - r)
	env.ambient_light_energy = p["ambient"] * (1.0 - 0.25 * r)
	env.tonemap_exposure = p["exposure"] * (1.0 + 0.25 * r)
	env.glow_intensity = 0.35 if time == "day" else 0.7          # lamps bloom in the dark

func _environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sky_mat = sm
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sm.shader = sh
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# filmic look: AgX tone mapping, a touch of contrast and bloom on bright highlights
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 12.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	# contact shadows and screen-space reflections (wet-looking paint, glass)
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	# aerial perspective: distant scenery fades into a warm haze
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.66, 0.73, 0.82)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.00055
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-30, -58, 0)
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 2.1
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)

func _body(pos: Vector3, size: Vector3, mat: Material, mu := 1.05, rot := Vector3.ZERO, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot
	sb.set_meta("mu", mu)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb

func _visual_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _ground() -> void:
	_body(Vector3(0, -0.6, 0), Vector3(3000, 1.2, 3000), grass_mat, 0.55)         # top at y = -0.0
	# asphalt pad: top at y = 0.0, grass top is 0.0 - 0.0 -> lift pad by a hair visually only
	_body(Vector3(0, -0.48, -150), Vector3(500, 1.0, 700), asphalt_mat, 1.05)
	for b in get_children():
		pass

func _markings() -> void:
	for i in range(0, 120):
		_visual_box(Vector3(0, 0.012, -6.0 - i * 6.0), Vector3(0.18, 0.02, 2.5), paint_mat)
	for sx in [-8.0, 8.0]:
		_visual_box(Vector3(sx, 0.012, -250), Vector3(0.2, 0.02, 500), paint_mat)

func _cyl_static(pos: Vector3, radius: float, height: float, mat: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot
	sb.set_meta("mu", 1.0)
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = radius
	shp.height = height
	cs.shape = shp
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb

func _bumps_and_washboard() -> void:
	# three round speed bumps, 0.09 m high
	for i in 3:
		_cyl_static(Vector3(0, 0.09 - 0.6, -60.0 - i * 4.0), 0.6, 6.0, yellow_mat, Vector3(0, 0, 90))
	# washboard: 40 little ridges
	for i in 40:
		_body(Vector3(-0, 0.03 - 0.04, -100.0 - i * 0.7), Vector3(7.0, 0.08, 0.22), asphalt_mat)
	# kerb stones, one side of the first stretch
	_body(Vector3(9.2, 0.075, -40), Vector3(0.5, 0.15, 60), concrete_mat)
	_body(Vector3(-9.2, 0.075, -40), Vector3(0.5, 0.15, 60), concrete_mat)

func _ramps() -> void:
	# jump ramp (14 degrees) with a landing slope behind it
	var ang := 14.0
	var length := 8.0
	var h := sin(deg_to_rad(ang)) * length
	_body(Vector3(0, h * 0.5 - 0.1, -150.0), Vector3(6.0, 0.4, length), concrete_mat, 1.0, Vector3(ang, 0, 0))
	_body(Vector3(0, 0.35, -170.0), Vector3(8, 0.7, 14), concrete_mat, 1.0, Vector3(-6.0, 0, 0))

func _cone(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 4.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	rb.position = pos
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = 0.16
	shp.height = 0.55
	cs.shape = shp
	cs.position.y = 0.0
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.2
	cm.height = 0.55
	mi.mesh = cm
	mi.material_override = cone_mat
	rb.add_child(mi)
	add_child(rb)

func _slalom() -> void:
	for i in 10:
		var x := 3.0 if i % 2 == 0 else -3.0
		_cone(Vector3(x, 0.3, -190.0 - i * 12.0))

func _crate(pos: Vector3, size := 0.6, mass := 18.0) -> void:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	rb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE * size
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	mi.mesh = bm
	mi.material_override = crate_mat
	rb.add_child(mi)
	add_child(rb)

func _crash_area() -> void:
	# concrete wall across the road, poles, crates
	_body(Vector3(0, 0.6, -330), Vector3(16, 1.2, 0.8), concrete_mat)
	for i in 6:
		_cyl_static(Vector3(-12 + i * 2.0, 1.25, -300), 0.14, 2.5, yellow_mat)
	for r in 4:
		for c in 3:
			_crate(Vector3(14 + c * 0.62, 0.3 + r * 0.61, -280))
	for i in 5:
		_body(Vector3(-16 - i * 0.2, 0.5, -270 - i * 6.0), Vector3(0.6, 1.0, 5.0), concrete_mat, 1.0, Vector3(0, 8 * i, 0))
	# angled wall for glancing hits
	_body(Vector3(-25, 0.6, -200), Vector3(0.6, 1.2, 40), concrete_mat, 1.0, Vector3(0, -6, 0))

func _gravel_and_hill() -> void:
	_body(Vector3(40, 0.0, -90), Vector3(30, 0.04, 80), gravel_mat, 0.55)
	# 15 degree hill
	var ang := 15.0
	var len_ := 40.0
	_body(Vector3(65, sin(deg_to_rad(ang)) * len_ * 0.5 - 0.3, -40), Vector3(10, 0.6, len_), asphalt_mat, 1.05, Vector3(ang, 0, 0))

func _skidpad() -> void:
	var seg := 72
	for i in seg:
		var a := TAU * i / seg
		var p := Vector3(-60 + cos(a) * 25.0, 0.012, 20 + sin(a) * 25.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.02, 2.2)
		mi.mesh = bm
		mi.material_override = paint_mat
		mi.position = p
		mi.rotation.y = -a
		add_child(mi)

func _scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 24:
		var h := rng.randf_range(8.0, 40.0)
		var w := rng.randf_range(10.0, 25.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(rng.randf_range(0.4, 0.7), rng.randf_range(0.4, 0.7), rng.randf_range(0.45, 0.75))
		_visual_box(Vector3(side * rng.randf_range(80, 140), h * 0.5, -rng.randf_range(0, 500)), Vector3(w, h, w), m)
