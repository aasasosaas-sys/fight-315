shader_type spatial;
// 海・川・池の水面。頂点の波、フレネル、深度による色と岸の泡、屈折。
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.12, 0.42, 0.42);
uniform vec3 deep_color : source_color = vec3(0.02, 0.10, 0.16);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.95);
uniform float wave_amp = 0.35;
uniform float wave_len = 28.0;
uniform float flow_speed = 0.0;      // >0 なら UV.x 方向へ流れる（川）
uniform float depth_scale = 4.0;
uniform float foam_width = 1.2;
uniform float clarity = 0.6;

varying vec3 v_wpos;
varying float v_crest;

vec3 gerstner(vec2 p, vec2 dir, float len, float amp, float t, inout vec3 tan, inout vec3 bin) {
	float k = 6.2831 / len;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = amp;
	float steep = 0.45;
	tan += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	bin += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * a * steep * cos(f), a * sin(f), d.y * a * steep * cos(f));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 off = vec3(0.0);
	float t = TIME;
	if (wave_amp > 0.001) {
		off += gerstner(wp.xz, vec2(1.0, 0.6), wave_len, wave_amp, t, tan, bin);
		off += gerstner(wp.xz, vec2(-0.4, 1.0), wave_len * 0.61, wave_amp * 0.55, t, tan, bin);
		off += gerstner(wp.xz, vec2(0.7, -0.3), wave_len * 0.37, wave_amp * 0.3, t, tan, bin);
	}
	VERTEX += off;
	v_crest = off.y / max(wave_amp, 0.001);
	NORMAL = normalize(cross(bin, tan));
	v_wpos = wp + off;
}

void fragment() {
	float t = TIME;
	vec2 flow = vec2(flow_speed * t, 0.0);
	vec2 uvn = (flow_speed > 0.0) ? UV : v_wpos.xz;
	vec2 n1 = texture(noise_tex, uvn * 0.031 + vec2(t * 0.012, t * 0.007) - flow * 0.031).rg;
	vec2 n2 = texture(noise_tex, uvn * 0.083 - vec2(t * 0.017, -t * 0.011) - flow * 0.083).rg;
	vec2 n3 = texture(noise_tex, uvn * 0.21 + vec2(t * 0.03, t * 0.02) - flow * 0.21).rg;
	vec2 nn = (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.6 + (n3 - 0.5) * 0.35;
	NORMAL_MAP = normalize(vec3(nn * 0.9 + 0.5, 1.0));
	NORMAL_MAP_DEPTH = 1.0;

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float water_dist = -VERTEX.z;
	float thickness = max(scene_dist - water_dist, 0.0);
	float depth_fac = 1.0 - exp(-thickness / depth_scale);

	vec2 refr_uv = SCREEN_UV + nn * 0.03 * clamp(thickness * 0.3, 0.0, 1.0);
	// 屈折先が水より手前なら屈折しない
	float d2 = texture(depth_tex, refr_uv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(refr_uv * 2.0 - 1.0, d2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < water_dist) refr_uv = SCREEN_UV;
	vec3 under = texture(screen_tex, refr_uv).rgb;

	vec3 water_col = mix(shallow_color, deep_color, depth_fac);
	vec3 col = mix(under * mix(vec3(1.0), shallow_color * 2.2, 0.5), water_col, clamp(depth_fac + (1.0 - clarity) * 0.5, 0.0, 1.0));

	// 岸の泡
	float foam_n = texture(noise_tex, v_wpos.xz * 0.15 + vec2(t * 0.05, 0.0)).r;
	float shore_foam = (1.0 - smoothstep(0.0, foam_width, thickness)) * smoothstep(0.35, 0.65, foam_n + 0.25 * sin(t * 1.3 + thickness * 4.0));
	float crest = smoothstep(0.65, 1.0, v_crest) * smoothstep(0.5, 0.7, foam_n) * 0.6;
	float foam = clamp(shore_foam + crest, 0.0, 1.0);

	ALBEDO = mix(col, foam_color, foam);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// 半透明は使わず不透明扱い（屈折で透明感を出す）。遠くはフレネルで空が映る
	EMISSION = vec3(0.0);
	ALPHA = 1.0;
}
