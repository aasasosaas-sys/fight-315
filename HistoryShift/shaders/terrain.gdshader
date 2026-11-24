shader_type spatial;
// アニメ背景調の地形: 時代パレットのベタ色＋筆ムラ。写真テクスチャは「明暗の模様」としてだけ薄く使う。
// 制御マスク（道/広場/田畑/森）・斜面・高さでレイヤを塗り分け、セル塗りで照らす。
render_mode diffuse_burley;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rgh_arr : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D control_tex : filter_linear, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;

uniform float half_size = 600.0;
uniform float grid_n = 513.0;
uniform float water_level = 0.0;

uniform float L_GRASS = 0.0;
uniform float L_FOREST = 1.0;
uniform float L_ROCK = 2.0;
uniform float L_DIRT = 3.0;
uniform float L_SAND = 4.0;
uniform float L_ROAD = 3.0;
uniform float L_PLAZA = 4.0;

// 互換（旧パラメータ）
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 road_tint : source_color = vec3(1.0);
uniform vec3 plaza_tint : source_color = vec3(1.0);
uniform float snow_height = 9999.0;
uniform vec2 snow_center = vec2(0.0);
uniform float snow_radius = 99999.0;
uniform float road_scale = 0.22;
uniform float plaza_scale = 0.25;

// アニメ調パレット
uniform vec3 grass_a : source_color = vec3(0.36, 0.62, 0.22);   // 基本の草色
uniform vec3 grass_b : source_color = vec3(0.24, 0.52, 0.26);   // 青みの草色
uniform vec3 grass_c : source_color = vec3(0.62, 0.74, 0.30);   // 日なたの黄緑
uniform vec3 forest_col : source_color = vec3(0.17, 0.36, 0.22);
uniform vec3 dirt_col : source_color = vec3(0.74, 0.6, 0.42);
uniform vec3 sand_col : source_color = vec3(0.93, 0.86, 0.68);
uniform vec3 rock_col : source_color = vec3(0.58, 0.56, 0.58);
uniform vec3 rock_col2 : source_color = vec3(0.46, 0.47, 0.54);
uniform vec3 field_col : source_color = vec3(0.42, 0.62, 0.26);
uniform vec3 snow_col : source_color = vec3(0.95, 0.97, 1.0);
uniform float road_textured = 0.0;   // 1: 石畳・舗装（テクスチャの模様を強く）
uniform float plaza_textured = 0.0;
uniform float detail = 0.32;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

// レイヤの「明暗の模様」（平均輝度で割った相対値）
float layer_rel(float L, vec2 uv, vec2 dx, vec2 dy) {
	vec3 a = textureGrad(alb_arr, vec3(uv, L), dx, dy).rgb;
	vec3 avg = textureLod(alb_arr, vec3(0.5, 0.5, L), 10.0).rgb;
	return lum(a) / max(lum(avg), 0.03);
}

vec3 layer_avg(float L) {
	return textureLod(alb_arr, vec3(0.5, 0.5, L), 10.0).rgb;
}

vec3 sat(vec3 c, float s) {
	return max(mix(vec3(lum(c)), c, s), vec3(0.0));
}

float posterize(float x, float n) {
	float q = x * n;
	float f = floor(q);
	return (f + smoothstep(0.3, 0.7, q - f)) / n;
}

float hblend(float w, float hgt, float sharp) {
	return clamp((w - 0.5) * sharp + 0.5 + (hgt - 0.5) * (1.0 - abs(w * 2.0 - 1.0)) * 1.4, 0.0, 1.0);
}

void fragment() {
	vec2 wp = v_wpos.xz;
	vec3 pdx = dFdx(v_wpos);
	vec3 pdy = dFdy(v_wpos);
	vec2 gdx = pdx.xz, gdy = pdy.xz;
	vec2 cuv = (wp + half_size) / (2.0 * half_size);
	cuv = cuv * ((grid_n - 1.0) / grid_n) + 0.5 / grid_n;
	vec4 ctrl = texture(control_tex, cuv);
	float inside = step(abs(wp.x), half_size) * step(abs(wp.y), half_size);
	ctrl *= inside;

	float m1 = texture(macro_tex, wp * 0.0021).r;
	float m2 = texture(macro_tex, wp * 0.011 + vec2(0.3, 0.6)).r;
	float m3 = texture(macro_tex, wp * 0.047 + vec2(0.7, 0.2)).r;
	// 筆のストローク（細長いノイズ、方向は大きなムラで変える）
	vec2 sp = rot2(wp, m1 * 2.5);
	float stroke = texture(macro_tex, sp * vec2(0.09, 0.012)).r;
	float stroke2 = texture(macro_tex, sp * vec2(0.3, 0.05) + vec2(0.5)).r;

	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float near_k = 1.0 - smoothstep(25.0, 120.0, dist);

	// ---- 草地（パレットのグラデーション）
	vec3 col = mix(grass_a, grass_b, smoothstep(0.32, 0.68, m1));
	col = mix(col, grass_c, smoothstep(0.52, 0.78, m2 + (stroke - 0.5) * 0.25) * 0.65);
	col *= mix(0.93, 1.07, stroke) * mix(0.96, 1.04, stroke2);
	float gr = layer_rel(L_GRASS, wp * 0.24, gdx * 0.24, gdy * 0.24);
	col *= mix(1.0, clamp(posterize(gr, 3.0), 0.75, 1.25), detail * near_k);
	col *= grass_tint;
	// 暖色・寒色の色の揺らぎ（日だまりの黄緑・窪みの青緑）
	float mh = texture(macro_tex, wp * 0.0055 + vec2(0.17, 0.83)).r;
	col *= mix(vec3(0.94, 0.99, 1.05), vec3(1.05, 1.01, 0.92), smoothstep(0.3, 0.72, mh));
	float slope = 1.0 - v_wnrm.y;
	// 斜面の草は少し深い青緑（山肌の森の色）
	col = mix(col, mix(grass_b, forest_col, 0.45) * mix(0.92, 1.08, stroke), smoothstep(0.1, 0.3, slope) * 0.75);
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	float nd = 0.0;

	// 土のパッチ（小さく、乾いた色）
	float dirt_w = smoothstep(0.68, 0.84, m2 * 0.7 + m3 * 0.5) * 0.35;
	col = mix(col, mix(dirt_col, col, 0.45), dirt_w);

	// 森の地面（深い青緑の影色）
	float forest_w = max(ctrl.a * (1.0 - smoothstep(0.12, 0.3, slope)), (1.0 - inside) * 0.85);
	if (forest_w > 0.01) {
		vec3 fc = forest_col * mix(0.85, 1.15, m3) * mix(0.94, 1.06, stroke);
		col = mix(col, fc, hblend(forest_w, m3, 2.0));
	}
	// 田畑（苗の列）
	float field_w = ctrl.b;
	if (field_w > 0.01) {
		vec3 fc = field_col * mix(0.9, 1.1, m3);
		float rows = smoothstep(0.32, 0.5, abs(fract(dot(wp, vec2(0.7071)) * 1.4) - 0.5));
		fc = mix(fc, fc * vec3(0.72, 0.8, 0.9), rows * 0.6);
		col = mix(col, fc, field_w);
	}
	// 砂浜（濡れた帯は少し暗く青み）
	float sand_w = 1.0 - smoothstep(water_level + 1.2, water_level + 3.4, v_wpos.y + (m3 - 0.5) * 1.5);
	if (sand_w > 0.01) {
		float wet = 1.0 - smoothstep(water_level - 0.2, water_level + 0.8, v_wpos.y);
		vec3 sc = sand_col * mix(0.95, 1.05, stroke2);
		sc = mix(sc, sc * vec3(0.72, 0.76, 0.82), wet);
		col = mix(col, sc, sand_w);
	}
	// 岩（急斜面: 三平面投影で模様、パレット 2 色の段階）
	float rock_w = smoothstep(0.36, 0.52, slope + (m3 - 0.5) * 0.14) * mix(1.0, 0.55, 1.0 - inside);
	if (rock_w > 0.01) {
		vec3 bw = pow(abs(v_wnrm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		float rx = layer_rel(L_ROCK, v_wpos.zy * 0.06, pdx.zy * 0.06, pdy.zy * 0.06);
		float rz = layer_rel(L_ROCK, v_wpos.xy * 0.06, pdx.xy * 0.06, pdy.xy * 0.06);
		float ry = layer_rel(L_ROCK, v_wpos.xz * 0.06, pdx.xz * 0.06, pdy.xz * 0.06);
		float rr = rx * bw.x + ry * bw.y + rz * bw.z;
		// 岩肌: 2 色のムラ＋苔（緑）
		vec3 rc = mix(rock_col2, rock_col, smoothstep(0.3, 0.7, m3 + (stroke - 0.5) * 0.3));
		rc = mix(rc, forest_col * 1.2, smoothstep(0.55, 0.75, m2) * 0.45 * (1.0 - smoothstep(0.5, 0.7, slope)));
		rc *= clamp(posterize(rr, 3.0), 0.7, 1.3);
		col = mix(col, rc, hblend(rock_w, rr * 0.5, 2.0));
		vec3 n2 = textureGrad(nrm_arr, vec3(v_wpos.xz * 0.06, L_ROCK), pdx.xz * 0.06, pdy.xz * 0.06).rgb;
		nrm = mix(nrm, n2, rock_w * 0.5);
		nd = max(nd, rock_w);
	}
	// 広場・建物まわり
	float plaza_w = ctrl.g;
	if (plaza_w > 0.01) {
		vec2 uv = wp * plaza_scale;
		float pr = layer_rel(L_PLAZA, uv, gdx * plaza_scale, gdy * plaza_scale);
		vec3 pc = mix(dirt_col * 1.06, sat(layer_avg(L_PLAZA), 1.3) * 1.15, plaza_textured) * plaza_tint;
		pc *= clamp(mix(1.0, posterize(pr, 3.0), mix(0.25, 0.7, plaza_textured)), 0.6, 1.4);
		pc *= mix(0.95, 1.05, stroke2);
		col = mix(col, pc, hblend(plaza_w, m3, 3.0));
	}
	// 道
	float road_w = ctrl.r;
	if (road_w > 0.01) {
		vec2 uv = wp * road_scale;
		float rr = layer_rel(L_ROAD, uv, gdx * road_scale, gdy * road_scale);
		vec3 rc = mix(dirt_col, sat(layer_avg(L_ROAD), 1.2) * 1.1, road_textured) * road_tint;
		rc *= clamp(mix(1.0, posterize(rr, 3.0), mix(0.3, 0.8, road_textured)), 0.55, 1.45);
		// 轍（中央が少し明るい）
		rc *= mix(0.97, 1.05, stroke);
		float w = hblend(road_w, m3 + (stroke2 - 0.5) * 0.4, 3.5);
		// 道の縁: 踏まれて少し濃くなった草と土の境（筆でなぞった縁取り）
		float edge_b = smoothstep(0.08, 0.3, road_w) * (1.0 - smoothstep(0.38, 0.62, road_w + (stroke2 - 0.5) * 0.2));
		col = mix(col, col * vec3(0.8, 0.84, 0.76), edge_b * 0.55);
		col = mix(col, rc, w);
		// 道の中ほどは日に焼けて明るく
		col *= 1.0 + 0.05 * smoothstep(0.75, 1.0, road_w) * (1.0 - road_textured);
		if (road_textured > 0.5) {
			vec3 n2 = textureGrad(nrm_arr, vec3(uv, L_ROAD), gdx * road_scale, gdy * road_scale).rgb;
			nrm = mix(nrm, n2, w * 0.4);
			nd = max(nd, w * 0.6);
		}
	}
	// 山頂の雪
	float snow_w = smoothstep(snow_height, snow_height + 18.0, v_wpos.y + (m2 - 0.5) * 30.0) * smoothstep(0.35, 0.75, v_wnrm.y + 0.2) * (1.0 - smoothstep(snow_radius * 0.7, snow_radius, length(v_wpos.xz - snow_center)));
	if (snow_w > 0.01) {
		col = mix(col, snow_col, snow_w);
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), snow_w);
	}
	// 大きな明暗のムラ（雲の影のような柔らかさ）
	col *= mix(0.92, 1.06, m1);
	ALBEDO = clamp(col, 0.0, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = nd * (1.0 - smoothstep(60.0, 220.0, dist));
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}

void light() {
	toon_light_common(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.12, 0.6, DIFFUSE_LIGHT);
}
