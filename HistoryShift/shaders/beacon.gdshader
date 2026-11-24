shader_type spatial;
// 目標地点の光の柱（加算・アンシェーデッド）
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.3, 0.9, 1.0);
uniform float intensity = 1.6;
varying float v_h;
void vertex() {
	v_h = VERTEX.y;
}
void fragment() {
	float edge = abs(dot(NORMAL, VIEW));
	float core = pow(edge, 2.2);
	float fade_top = 1.0 - smoothstep(60.0, 300.0, v_h);
	float fade_bot = smoothstep(0.0, 2.0, v_h);
	float bands = 0.75 + 0.25 * sin(v_h * 0.35 - TIME * 3.0);
	float a = core * fade_top * fade_bot * bands;
	ALBEDO = color * intensity * a;
	ALPHA = a;
}
