shader_type spatial;
// アニメ調の水面: 明るいベタ色（浅瀬→深みの段階）、岸の泡の帯（2 本の線）、きらめき（太陽方向の点状ハイライト）、
// 遠くは空色に。ゆるい波で頂点を揺らす。
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.3, 0.78, 0.82);
uniform vec3 deep_color : source_color = vec3(0.1, 0.42, 0.7);
uniform vec3 foam_color : source_color = vec3(0.97, 0.99, 1.0);
uniform vec3 sky_color : source_color = vec3(0.62, 0.8, 0.97);
uniform float wave_amp = 0.35;
uniform float wave_len = 28.0;
uniform float flow_speed = 0.0;      // >0 なら UV.x 方向へ流れる（川）
uniform float depth_scale = 4.0;
uniform float foam_width = 1.2;
uniform float clarity = 0.6;
uniform float sparkle = 1.0;
// 船体の中には海面を描かない（scripts/world/ships/ship_yard.gd が毎フレーム設定）。
// o: 船の原点(xyz)・半長 / x: 船の右舷軸・半幅 / z: 船尾軸・平行部 / y: 上軸・甲板の高さ / p: (船首の細り, 船尾の細り, 指数, 縮小) / t: (船首・船尾のトランサム幅)
uniform int dry_n = 0;
uniform vec4 dry_o[8];
uniform vec4 dry_x[8];
uniform vec4 dry_z[8];
uniform vec4 dry_y[8];
uniform vec4 dry_p[8];
uniform vec4 dry_t[8];

varying vec3 v_wpos;
varying float v_crest;
varying float v_spark;

vec3 gerstner(vec2 p, vec2 dir, float len, float amp, float t, inout vec3 tan, inout vec3 bin) {
	float k = 6.2831 / len;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float steep = 0.35;
	tan += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	bin += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * amp * steep * cos(f), amp * sin(f), d.y * amp * steep * cos(f));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 off = vec3(0.0);
	float t = TIME;
	if (wave_amp > 0.001) {
		off += gerstner(wp.xz, vec2(1.0, 0.6), wave_len, wave_amp * 0.7, t, tan, bin);
		off += gerstner(wp.xz, vec2(-0.4, 1.0), wave_len * 0.61, wave_amp * 0.4, t, tan, bin);
	}
	VERTEX += off;
	v_crest = off.y / max(wave_amp, 0.001);
	NORMAL = normalize(cross(bin, tan));
	v_wpos = wp + off;
}

void fragment() {
	for (int i = 0; i < dry_n; i++) {
		float hl = dry_o[i].w;
		if (hl <= 0.0) {
			continue;
		}
		vec3 dd = v_wpos - dry_o[i].xyz;
		float lz = dot(dd, dry_z[i].xyz);
		float tt = lz / hl;
		if (abs(tt) < 0.985) {
			float ly = dot(dd, dry_y[i].xyz);
			if (ly < dry_y[i].w) {
				float lx = dot(dd, dry_x[i].xyz);
				float m = dry_z[i].w;
				float a = clamp((abs(tt) - m) / max(1.0 - m, 0.01), 0.0, 1.0);
				float pe = tt < 0.0 ? dry_p[i].x : dry_p[i].y;
				float base = pow(max(0.0, 1.0 - pow(a, pe)), dry_p[i].z);
				float tr = tt < 0.0 ? dry_t[i].x : dry_t[i].y;
				float hb = dry_x[i].w * (tr + (1.0 - tr) * base) * dry_p[i].w - 0.15;
				if (abs(lx) < hb) {
					discard;
				}
			}
		}
	}
	float t = TIME;
	vec2 flow = vec2(flow_speed * t, 0.0);
	vec2 uvn = (flow_speed > 0.0) ? UV : v_wpos.xz;
	vec2 n1 = texture(noise_tex, uvn * 0.031 + vec2(t * 0.012, t * 0.007) - flow * 0.031).rg;
	vec2 n2 = texture(noise_tex, uvn * 0.083 - vec2(t * 0.017, -t * 0.011) - flow * 0.083).rg;
	vec2 nn = (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.6;
	// 法線は控えめ（ベタ塗り感を保つ）
	NORMAL_MAP = normalize(vec3(nn * 0.35 + 0.5, 1.0));
	NORMAL_MAP_DEPTH = 1.0;

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float water_dist = -VERTEX.z;
	float thickness = max(scene_dist - water_dist, 0.0);
	float depth_fac = 1.0 - exp(-thickness / depth_scale);
	// 段階的な色（浅瀬・中間・深み）
	float band = smoothstep(0.18, 0.24, depth_fac) * 0.5 + smoothstep(0.55, 0.62, depth_fac) * 0.5;
	vec3 water_col = mix(shallow_color, deep_color, band);

	vec2 refr_uv = SCREEN_UV + nn * 0.015 * clamp(thickness * 0.3, 0.0, 1.0);
	float d2 = texture(depth_tex, refr_uv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(refr_uv * 2.0 - 1.0, d2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < water_dist) refr_uv = SCREEN_UV;
	vec3 under = texture(screen_tex, refr_uv).rgb;
	// ごく浅い所だけ底が透ける
	float see = (1.0 - smoothstep(0.0, 0.25, depth_fac)) * clarity;
	vec3 col = mix(water_col, under * mix(vec3(1.0), shallow_color * 1.6, 0.5), see * 0.7);

	// 遠く・浅い角度は空色（フレネル）
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float far_k = smoothstep(80.0, 600.0, water_dist);
	col = mix(col, sky_color * 1.05, clamp(fres * 0.6 + far_k * 0.35, 0.0, 0.75));

	// 岸の泡: 岸沿いのベタ帯＋少し沖の細い線（寄せては返す）
	float fn = texture(noise_tex, v_wpos.xz * 0.12 + vec2(t * 0.03, 0.0)).r;
	float fw = foam_width * (0.75 + fn * 0.6);
	float shore = 1.0 - step(fw * 0.55, thickness);
	float wave = sin(t * 0.9 + fn * 4.0) * 0.5 + 0.5;
	float l1 = fw * (1.0 + wave * 0.9);
	float line1 = step(abs(thickness - l1), 0.06 + 0.04 * fn) * (1.0 - smoothstep(0.6, 1.0, wave)) ;
	float l2 = fw * (2.2 + wave * 0.5);
	float line2 = step(abs(thickness - l2), 0.04) * step(0.45, fn) * 0.8;
	float crest = step(0.95, v_crest + fn * 0.2) * step(0.6, fn) * 0.7 * (1.0 - smoothstep(30.0, 120.0, water_dist));
	float foam = clamp(shore + line1 + line2 + crest, 0.0, 1.0);
	foam *= 1.0 - smoothstep(150.0, 400.0, water_dist);

	// きらめき（細かいノイズのピーク）
	float s1 = texture(noise_tex, v_wpos.xz * 0.9 + vec2(t * 0.11, -t * 0.07)).r;
	float s2 = texture(noise_tex, v_wpos.xz * 1.3 - vec2(t * 0.09, t * 0.05)).r;
	v_spark = step(0.84, s1 * s2 * 1.7) * sparkle * (1.0 - foam);

	ALBEDO = mix(col, foam_color, foam);
	ROUGHNESS = 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	ALPHA = 1.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float sh = smoothstep(0.25, 0.65, ATTENUATION);
		// 水はほぼフラットに照らす（影はうっすら）
		vec3 tone = mix(toon_shade_color.rgb * toon_params.w + 0.25, vec3(1.0), sh);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * tone * 0.95;
		// 太陽の照り返し: 反射方向に近いきらめきだけを強く
		vec3 r = reflect(-VIEW, NORMAL);
		float sun_r = pow(max(dot(r, LIGHT), 0.0), 12.0);
		float glint = v_spark * (0.25 + sun_r * 4.0);
		float spot = smoothstep(0.985, 0.995, dot(r, LIGHT));
		SPECULAR_LIGHT += LIGHT_COLOR / PI * (glint + spot * 0.8) * sh;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * 0.6;
	}
}
