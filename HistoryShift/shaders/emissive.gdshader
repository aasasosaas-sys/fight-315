shader_type spatial;
// 提灯・ガス灯・窓明かりなど。頂点カラーで色を決める。
render_mode diffuse_burley;
#include "res://shaders/destruct.gdshaderinc"
uniform float energy = 2.5;
varying vec3 v_wpos;
void vertex() {
	vec4 d_st;
	vec2 d_cut;
	destruct_vertex(VERTEX, UV2, d_st, d_cut);
	v_dstate = d_st;
	v_dcut = d_cut;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float lit = 1.0 - clamp(v_dstate.g * 2.0 + v_dstate.b, 0.0, 1.0);
	if (v_dcut.x < 1e5 && v_wpos.y > v_dcut.x) {
		discard;
	}
	ALBEDO = COLOR.rgb * mix(0.15, 0.6, lit);
	EMISSION = COLOR.rgb * energy * lit;
	ROUGHNESS = 0.6;
}
