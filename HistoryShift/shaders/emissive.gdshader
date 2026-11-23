shader_type spatial;
// 提灯・ガス灯・窓明かりなど。頂点カラーで色を決める。
render_mode diffuse_burley;
uniform float energy = 2.5;
void fragment() {
	ALBEDO = COLOR.rgb * 0.6;
	EMISSION = COLOR.rgb * energy;
	ROUGHNESS = 0.6;
}
