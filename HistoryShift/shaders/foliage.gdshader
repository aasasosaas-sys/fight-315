shader_type spatial;
// アニメ調の樹冠: 葉カード（丸い塊＋縁の葉っぱ形で alpha scissor）と内側の塊。
// 法線は塊の中心から外向き（頂点側で設定済み）→ セル塗りで柔らかい塊の陰影になる。風で揺れる。
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/toon.gdshaderinc"

uniform vec3 leaf_color : source_color = vec3(0.16, 0.3, 0.08);
uniform vec3 leaf_color2 : source_color = vec3(0.24, 0.36, 0.1);
uniform float leaf_count = 6.0;
uniform float leaf_size = 0.42;
uniform float leaf_aspect = 0.5;
uniform float sway = 1.0;
uniform float translucency = 0.45;
uniform float blob = 0.62;          // 中央の塊の半径（UV 0..1 に対する比）
uniform vec3 tip_color : source_color = vec3(0.75, 0.88, 0.4);   // 逆光で透ける色
uniform float ao_strength = 0.55;
// 互換（未使用）
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float use_tex = 0.0;
uniform vec3 tex_tint : source_color = vec3(1.0);
uniform float tex_desat = 0.0;

varying vec3 v_col;
varying float v_core;
varying float v_seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hv = hash12(origin.xz * 0.37);
	float ph = TIME * 1.25 + origin.x * 0.07 + origin.z * 0.09;
	float bend = (sin(ph) * 0.6 + sin(ph * 2.3 + VERTEX.x) * 0.25) * sway;
	float fy = max(VERTEX.y, 0.0);
	VERTEX.x += bend * 0.012 * fy * COLOR.g * (1.0 + fy * 0.05);
	VERTEX.z += bend * 0.008 * fy * COLOR.g;
	VERTEX += NORMAL * sin(TIME * 3.0 + VERTEX.x * 2.0 + VERTEX.y * 1.5) * 0.04 * (1.0 - COLOR.a) * sway;
	float ao = mix(1.0 - ao_strength * 0.75, 1.06, COLOR.r);
	v_col = mix(leaf_color, leaf_color2, hv) * ao;
	v_core = COLOR.a;
	v_seed = fract(VERTEX.x * 3.17 + VERTEX.y * 1.71 + VERTEX.z * 2.33);
}

void fragment() {
	// 両面: 裏面でも外向き法線のまま（塊の陰影を保つ）
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float a = 1.0;
	float shade = 1.0;
	if (v_core < 0.5) {
		vec2 c = UV - 0.5;
		float r = length(c) * 2.0;
		float ang = atan(c.y, c.x);
		// 丸い塊（ゆるい凹凸）
		float lobes = blob * (1.0 + 0.12 * sin(ang * 4.0 + v_seed * 20.0) + 0.06 * sin(ang * 9.0 + v_seed * 7.0));
		float inner = step(r, lobes);
		// 縁の葉っぱ（ボロノイ風に並べた尖った楕円）
		vec2 g = UV * leaf_count;
		vec2 id = floor(g);
		float best = 10.0;
		float bid = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 cc = id + vec2(float(x), float(y));
				float r1 = hash12(cc);
				float r2 = hash12(cc + 7.7);
				vec2 d = g - (cc + vec2(r1, r2));
				float an = r1 * 6.2831;
				vec2 rd = vec2(cos(an) * d.x + sin(an) * d.y, -sin(an) * d.x + cos(an) * d.y);
				rd.y /= leaf_aspect;
				rd.x *= 1.0 + 0.5 * rd.y;
				float dd = length(rd) / leaf_size;
				if (dd < best) { best = dd; bid = r2; }
			}
		}
		float leaf = (1.0 - step(1.0, best)) * step(r, 0.97);
		a = max(inner, leaf);
		// 塊の内側はほぼ均一、縁の葉は少し明暗（筆のタッチ）
		shade = mix(mix(0.9, 1.1, bid), 1.0, inner * 0.6);
	}
	vec3 col = v_col * shade;
	ALBEDO = col;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}

void light() {
	toon_light_common(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.1, 1.2, DIFFUSE_LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		// 逆光の透過（明るい黄緑）
		float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * tip_color * pow(back, 3.0) * edge * translucency * smoothstep(0.3, 0.6, ATTENUATION);
	}
}
