shader_type spatial;
// 建物用 PBR: PolyHaven テクスチャ×頂点カラー、マクロな色ムラ、地面付近の汚れ、雨だれ。
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float half_size = 600.0;
uniform float grid_n = 513.0;
uniform float uv_scale = 0.5;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metallic = 0.0;
uniform float grime = 1.0;
uniform float normal_depth = 1.0;
uniform float variation = 1.0;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	UV *= uv_scale;
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb * COLOR.rgb;
	float m1 = texture(macro_tex, v_wpos.xz * 0.031 + v_wpos.y * 0.017).r;
	float m2 = texture(macro_tex, (v_wpos.xy + v_wpos.zy) * 0.09).r;
	a *= mix(1.0, mix(0.84, 1.1, m1), variation);
	vec2 huv = (v_wpos.xz + half_size) / (2.0 * half_size);
	huv = huv * ((grid_n - 1.0) / grid_n) + 0.5 / grid_n;
	float gh = texture(height_tex, huv).r;
	float above = v_wpos.y - gh;
	float g = (1.0 - smoothstep(0.0, 0.9 + m2 * 1.1, above)) * grime;
	vec3 dirt = vec3(0.42, 0.36, 0.3);
	a = mix(a, a * dirt * 1.3, g * 0.65);
	// 縦面の雨だれ
	float vert = 1.0 - abs(v_wnrm.y);
	float streak = texture(macro_tex, vec2((v_wpos.x + v_wpos.z) * 0.9, v_wpos.y * 0.04)).r;
	a *= mix(1.0, mix(0.78, 1.04, streak), vert * grime * 0.55);
	ALBEDO = clamp(a, 0.0, 1.0);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = clamp(texture(rough_tex, UV).r * rough_mul + rough_add + g * 0.1, 0.04, 1.0);
	METALLIC = metallic;
}
