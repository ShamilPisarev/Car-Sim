class_name Surfaces
extends RefCounted
## Shared ground materials (asphalt, grass, gravel). World-space shaders with a fine grain
## texture, a bump map from the same noise, and a large-scale colour patch layer, so
## surfaces read as real materials at every distance instead of one tiled blotch.

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint_a : source_color = vec3(0.16);
uniform vec3 tint_b : source_color = vec3(0.20);
uniform float grain_scale = 0.5;
uniform float macro_scale = 0.01;
uniform float grain_amount = 0.5;
uniform float rough_lo = 0.7;
uniform float rough_hi = 0.95;
uniform float normal_depth = 0.6;
uniform float use_vcol = 1.0;
uniform float wet_amount = 1.0;     // how much this surface shows the rain
uniform float puddles = 0.0;        // standing water in the dips (asphalt)
global uniform float wetness;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * grain_scale;
	float g = texture(grain, uv).r;
	float g2 = texture(grain, uv * 0.137 + vec2(0.31, 0.71)).r;
	float m = texture(macro, wpos.xz * macro_scale).r;
	float m2 = texture(macro, wpos.xz * macro_scale * 4.3 + vec2(0.5)).r;
	vec3 base = mix(tint_a, tint_b, smoothstep(0.25, 0.75, m * 0.7 + m2 * 0.3));
	vec3 c = base * (1.0 - grain_amount * 0.5 + grain_amount * g) * (0.88 + 0.24 * g2);
	c *= mix(vec3(1.0), COLOR.rgb, use_vcol);
	// rain: a wet surface is darker and glossy; puddles collect in the low patches
	float wet = clamp(wetness * wet_amount, 0.0, 1.0);
	float pud = smoothstep(0.56, 0.68, m2 * 0.7 + g2 * 0.3) * wet * puddles;
	c *= mix(1.0, 0.5, wet);
	ALBEDO = c * mix(1.0, 0.7, pud);
	float r = mix(rough_lo, rough_hi, clamp(g * 0.6 + m2 * 0.4, 0.0, 1.0));
	r = mix(r, 0.14, wet * 0.85);
	ROUGHNESS = mix(r, 0.02, pud);
	float dist = length(VERTEX);
	NORMAL_MAP = texture(grain_n, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - smoothstep(30.0, 140.0, dist)) * (1.0 - pud) * (1.0 - 0.4 * wet);
}
"""

static var _cache := {}

static func _noise(seed_v: int, type: int, freq: float, octaves: int, size: int, normal := false, bump := 6.0) -> NoiseTexture2D:
	var key := "%d_%d_%f_%d_%d_%s" % [seed_v, type, freq, octaves, size, str(normal)]
	if _cache.has(key):
		return _cache[key]
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.noise_type = type
	nz.frequency = freq
	if type == FastNoiseLite.TYPE_CELLULAR:
		nz.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
		nz.cellular_jitter = 0.9
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	nz.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = nz
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	_cache[key] = t
	return t

static func _shader() -> Shader:
	if not _cache.has("shader"):
		var s := Shader.new()
		s.code = GROUND_SHADER
		_cache["shader"] = s
	return _cache["shader"]

static func _make(grain: Texture2D, grain_n: Texture2D, a: Color, b: Color, gscale: float, gamount: float,
		r_lo: float, r_hi: float, ndepth: float, vcol: bool, wet := 1.0, pud := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader()
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("grain_n", grain_n)
	m.set_shader_parameter("macro", _noise(5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 5, 256))
	m.set_shader_parameter("tint_a", a)
	m.set_shader_parameter("tint_b", b)
	m.set_shader_parameter("grain_scale", gscale)
	m.set_shader_parameter("grain_amount", gamount)
	m.set_shader_parameter("rough_lo", r_lo)
	m.set_shader_parameter("rough_hi", r_hi)
	m.set_shader_parameter("normal_depth", ndepth)
	m.set_shader_parameter("use_vcol", 1.0 if vcol else 0.0)
	m.set_shader_parameter("wet_amount", wet)
	m.set_shader_parameter("puddles", pud)
	return m

static func asphalt(vcol := true) -> ShaderMaterial:
	# speckled aggregate (cell noise) over a fine fbm, dark grey with lighter worn patches
	var g := _noise(11, FastNoiseLite.TYPE_CELLULAR, 0.09, 2, 512)
	var n := _noise(11, FastNoiseLite.TYPE_CELLULAR, 0.09, 2, 512, true, 5.0)
	return _make(g, n, Color(0.105, 0.105, 0.11), Color(0.17, 0.165, 0.16), 0.45, 0.55, 0.62, 0.92, 0.55, vcol, 1.0, 1.0)

static func grass() -> ShaderMaterial:
	var g := _noise(23, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 4, 512)
	var n := _noise(23, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 4, 512, true, 9.0)
	return _make(g, n, Color(0.13, 0.22, 0.07), Color(0.26, 0.31, 0.12), 0.35, 0.8, 0.85, 1.0, 0.8, false, 0.35)

static func gravel() -> ShaderMaterial:
	var g := _noise(37, FastNoiseLite.TYPE_CELLULAR, 0.14, 1, 512)
	var n := _noise(37, FastNoiseLite.TYPE_CELLULAR, 0.14, 1, 512, true, 12.0)
	return _make(g, n, Color(0.42, 0.37, 0.30), Color(0.55, 0.50, 0.42), 1.6, 0.9, 0.9, 1.0, 1.0, false, 0.6)
