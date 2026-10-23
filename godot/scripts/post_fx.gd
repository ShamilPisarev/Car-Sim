class_name PostFX
extends CanvasLayer
## Speed blur: at high speed the edges of the picture smear outwards from the centre,
## the way the eye (and an onboard camera) loses detail at the sides. The centre stays sharp.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5, 0.52);
	float edge = smoothstep(0.18, 0.62, length(d * vec2(1.0, 0.8)));
	float s = strength * edge * 0.02;
	vec3 c = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		c += textureLod(screen, uv - d * s * float(i), 0.0).rgb;
	}
	COLOR = vec4(c / 8.0, 1.0);
}
"""

var car: Car
var cam: ChaseCam
var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = -1                      # under the HUD
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)

func _process(_dt: float) -> void:
	if car == null or cam == null:
		return
	var kmh := car.linear_velocity.length() * 3.6
	var s := clampf((kmh - 170.0) / 150.0, 0.0, 1.0)
	if cam.mode >= 3:
		s = 0.0                      # orbit, top and replay cameras stay clean
	_mat.set_shader_parameter("strength", s)
	_rect.visible = s > 0.01
