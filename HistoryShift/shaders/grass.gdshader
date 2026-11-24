shader_type spatial;
// GPU 配置の草。MultiMesh の格子をカメラに追従させ、高さ・マスクテクスチャで地面に乗せる。
render_mode cull_disabled, world_vertex_coords, diffuse_burley;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D control_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float half_size = 600.0;
uniform float grid_n = 513.0;
uniform float spacing = 0.5;
uniform float radius = 50.0;
uniform float water_level = 0.0;
uniform float density = 1.0;
uniform float blade_height = 0.5;
uniform float wind = 1.0;
uniform vec3 base_color : source_color = vec3(0.1, 0.2, 0.05);
uniform vec3 tip_color : source_color = vec3(0.45, 0.6, 0.2);
uniform vec3 dry_color : source_color = vec3(0.62, 0.56, 0.3);
uniform vec3 rice_color : source_color = vec3(0.36, 0.58, 0.16);
uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap, repeat_enable;
uniform float L_GRASS = 0.0;
uniform float use_ground = 0.0;
uniform vec3 ground_tint : source_color = vec3(1.0);
uniform float inner_radius = 0.0;
// 地形と同じパレット（根元が地面の色に溶ける）
uniform vec3 grass_a : source_color = vec3(0.36, 0.62, 0.22);
uniform vec3 grass_b : source_color = vec3(0.24, 0.52, 0.26);
uniform vec3 grass_c : source_color = vec3(0.62, 0.74, 0.30);
uniform vec3 tip_light : source_color = vec3(0.78, 0.9, 0.42);
uniform float anime = 1.0;
uniform float flowers = 1.0;         // 花の混じる量（0 で無し）
uniform vec3 flower_a : source_color = vec3(0.98, 0.96, 0.9);
uniform vec3 flower_b : source_color = vec3(1.0, 0.72, 0.82);
uniform vec3 flower_c : source_color = vec3(1.0, 0.86, 0.38);
global uniform vec4 world_wind;      // xy 風向き, z 強さ

varying float v_t;
varying vec3 v_col;
varying vec3 v_base;
varying float v_gust;
varying float v_flower;
varying vec3 v_fcol;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 tuv(vec2 xz) {
	vec2 uv = (xz + half_size) / (2.0 * half_size);
	return uv * ((grid_n - 1.0) / grid_n) + 0.5 / grid_n;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - origin;
	vec2 cid = floor(origin.xz / spacing + 0.5);
	float r1 = hash12(cid);
	float r2 = hash12(cid + 17.31);
	float r3 = hash12(cid * 1.71 + 3.1);
	vec2 pos = (cid + vec2(r1, r2) - 0.5) * spacing;
	vec2 uv = tuv(pos);
	float hgt = textureLod(height_tex, uv, 0.0).r;
	vec4 ctrl = textureLod(control_tex, uv, 0.0);
	float e = 2.0 * half_size / (grid_n - 1.0);
	float hx = textureLod(height_tex, tuv(pos + vec2(e, 0.0)), 0.0).r - textureLod(height_tex, tuv(pos - vec2(e, 0.0)), 0.0).r;
	float hz = textureLod(height_tex, tuv(pos + vec2(0.0, e)), 0.0).r - textureLod(height_tex, tuv(pos - vec2(0.0, e)), 0.0).r;
	vec3 n = normalize(vec3(-hx, 2.0 * e, -hz));
	float patch = textureLod(noise_tex, pos * 0.013, 0.0).r;
	float patch2 = textureLod(noise_tex, pos * 0.061 + vec2(0.4), 0.0).r;
	float inside = step(abs(pos.x), half_size - 2.0) * step(abs(pos.y), half_size - 2.0);
	float field = smoothstep(0.4, 0.7, ctrl.b);
	float dens = density * (1.0 - smoothstep(0.1, 0.5, ctrl.r)) * (1.0 - smoothstep(0.15, 0.55, ctrl.g)) * mix(1.0, 0.35, ctrl.a);
	dens *= smoothstep(0.74, 0.86, n.y);
	dens *= smoothstep(water_level + 1.2, water_level + 2.2, hgt);
	dens *= mix(smoothstep(0.1, 0.32, patch + patch2 * 0.3), 1.0, field);
	dens *= inside;
	float camd = length(pos - CAMERA_POSITION_WORLD.xz);
	float fade = (1.0 - smoothstep(radius * 0.55, radius, camd)) * smoothstep(inner_radius * 0.6, inner_radius, camd);
	// 田: 列状の稲株
	if (field > 0.5) {
		vec2 rp = floor(pos / 0.6 + 0.5) * 0.6;
		pos = rp + (vec2(r1, r2) - 0.5) * 0.08;
		dens = step(0.15, r3) * density * inside;
	}
	float keep = step(r3, dens) * fade;
	float hs = blade_height * mix(0.55, 1.15, r2) * mix(0.55, 1.15, patch) * mix(1.0, 1.35, field);
	hs *= mix(0.3, 1.0, fade);
	float ang = r1 * 6.2831;
	float ca = cos(ang), sa = sin(ang);
	local.xz = vec2(ca * local.x - sa * local.z, sa * local.x + ca * local.z) * mix(0.8, 1.25, r3);
	float t = clamp(local.y, 0.0, 1.0);
	local.y *= hs;
	float wn = textureLod(noise_tex, pos * 0.012 + vec2(TIME * 0.035, TIME * 0.02), 0.0).r;
	// 突風の波: 風下へ流れる帯状のノイズ。草が大きく倒れ、先端が白く光る（草原を渡る風が見える）
	vec2 wd = normalize(world_wind.xy + vec2(1e-4));
	float gp = dot(pos, wd);
	float gq = dot(pos, vec2(-wd.y, wd.x));
	float gust_n = textureLod(noise_tex, vec2(gp * 0.011 - TIME * 0.09 * world_wind.z, gq * 0.004), 0.0).r;
	float gust = smoothstep(0.5, 0.78, gust_n) * world_wind.z;
	float sway = (sin(TIME * 1.9 + pos.x * 0.37 + pos.y * 0.23) * 0.35 + (wn - 0.45) * 1.4 + gust * 1.6) * wind;
	local.x += sway * t * t * hs * 0.55 * mix(1.0, 0.4, gust) + wd.x * gust * t * t * hs * 0.5 * wind;
	local.z += sway * t * t * hs * 0.3 * mix(1.0, 0.4, gust) + wd.y * gust * t * t * hs * 0.5 * wind;
	local.y *= 1.0 - gust * t * 0.18;
	local *= keep;
	VERTEX = vec3(pos.x, hgt - 0.03, pos.y) + local;
	NORMAL = normalize(mix(n, NORMAL, 0.08));
	v_t = t;
	v_gust = gust;
	// 花: 草むらの所々に白・桃・黄の花（先端だけ色を変える）
	float fh = hash12(cid + 5.31);
	float fpatch = smoothstep(0.58, 0.74, textureLod(noise_tex, pos * 0.035 + vec2(0.71, 0.13), 0.0).r);
	v_flower = step(1.0 - 0.22 * flowers * fpatch, fh) * (1.0 - field);
	float fk = hash12(cid + 9.7);
	v_fcol = fk < 0.45 ? flower_a : (fk < 0.78 ? flower_b : flower_c);
	vec3 tipc = mix(tip_color, dry_color, smoothstep(0.55, 0.85, patch2) * 0.7);
	tipc = mix(tipc, rice_color, field);
	v_col = tipc * mix(0.85, 1.1, r1);
	v_base = base_color;
	if (anime > 0.5) {
		// 地形シェーダと同じ式で地色を求める
		float m1 = textureLod(noise_tex, pos * 0.0021, 0.0).r;
		float m2 = textureLod(noise_tex, pos * 0.011 + vec2(0.3, 0.6), 0.0).r;
		vec3 g = mix(grass_a, grass_b, smoothstep(0.32, 0.68, m1));
		g = mix(g, grass_c, smoothstep(0.52, 0.78, m2) * 0.65) * mix(0.92, 1.06, m1);
		v_base = g * 0.92;
		vec3 tc = mix(g * 1.12, tip_light, 0.4 + 0.25 * r2);
		tc = mix(tc, dry_color, smoothstep(0.6, 0.9, patch2) * 0.35);
		v_col = mix(tc, rice_color, field) * mix(0.92, 1.08, r1);
	} else if (use_ground > 0.5) {
		vec3 g = textureLod(alb_arr, vec3(pos * 0.24, L_GRASS), 3.0).rgb;
		g = mix(g, g * vec3(0.72, 1.0, 0.5) * 1.15, 0.8) * ground_tint;
		v_base = g * 0.55;
		v_col = mix(v_col, g * vec3(1.15, 1.35, 0.9), 0.45) * mix(0.85, 1.12, r2);
		v_col = mix(v_col, tipc, field);
	}
}

void fragment() {
	vec3 basec = v_base;
	vec3 c = mix(basec, v_col, smoothstep(0.0, 1.0, v_t));
	// 突風の先端の照り（明るい黄緑〜白っぽい筋）
	c = mix(c, tip_light * 1.08 + 0.03, v_gust * smoothstep(0.45, 1.0, v_t) * 0.3);
	// 花（先端の 30%）
	c = mix(c, v_fcol, v_flower * smoothstep(0.68, 0.74, v_t));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	AO = mix(0.8, 1.0, v_t);
}

void light() {
	// 地面の法線で照らす（地形と同じ明暗）＋先端は少し透過して明るく
	toon_light_common(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.12, 0.0, DIFFUSE_LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * back * back * 0.25 * smoothstep(0.3, 0.6, ATTENUATION);
	}
}
