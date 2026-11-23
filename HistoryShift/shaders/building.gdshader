shader_type spatial;
// 建物用アニメ調シェーダ: テクスチャは平均色（ベタ塗り）＋輝度の明暗を少しだけ（手描きの筆ムラ）。
// セル塗りのライティング（toon.gdshaderinc）。夜は窓（emissive 側）以外も軒下がほんのり暖色に。
render_mode diffuse_burley;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/destruct.gdshaderinc"

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
uniform float albedo_mul = 1.0;
uniform float desat = 0.0;
// アニメ調パラメータ
uniform float detail = 0.55;        // テクスチャの明暗をどれだけ残すか
uniform float posterize = 4.0;      // 明暗の段数（0 で無効）
uniform float sat_boost = 1.25;
uniform float flat_normal = 0.85;   // 法線マップをどれだけ弱めるか（1 で無効）
uniform float rim_mul = 1.0;
uniform vec4 base_override : source_color = vec4(0.0);   // a=1 なら地色をこの色に（テクスチャは模様だけ）
uniform float shine = 0.0;          // 金属・瓦の艶（アニメ的な帯ハイライト）
uniform float glass = 0.0;          // 1: ガラス窓（斜めの映り込み帯、夜は室内灯）
uniform float window_glow = 0.0;    // 1: 暗い頂点色の面（格子窓・開口部）を夜に灯す

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	destruct_vertex(VERTEX, UV2);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	UV *= uv_scale;
}

vec3 saturate_col(vec3 c, float s) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	return max(mix(vec3(l), c, s), vec3(0.0));
}

void fragment() {
	vec3 ta = texture(albedo_tex, UV).rgb;
	// テクスチャの平均色（最小ミップ）= ベタ塗りの地色
	vec3 avg = textureLod(albedo_tex, vec2(0.5), 12.0).rgb;
	float lum = dot(ta, vec3(0.3, 0.59, 0.11));
	float alum = max(dot(avg, vec3(0.3, 0.59, 0.11)), 0.02);
	float rel = lum / alum;
	if (posterize > 0.5) {
		// 段階化（境界は少しだけ滑らかに）
		float q = rel * posterize;
		float fq = floor(q);
		rel = (fq + smoothstep(0.35, 0.65, q - fq)) / posterize;
	}
	rel = clamp(rel, 0.55, 1.45);
	vec3 base = mix(avg, ta, 0.25);
	base = mix(base, vec3(dot(base, vec3(0.3, 0.59, 0.11))), desat) * albedo_mul;
	base = mix(base, base_override.rgb, base_override.a);
	vec3 a = saturate_col(base * mix(1.0, rel, detail), sat_boost) * COLOR.rgb;
	// 筆ムラ（大きめの色ムラ＋斜めのストローク）
	float m1 = texture(macro_tex, v_wpos.xz * 0.031 + v_wpos.y * 0.017).r;
	vec2 sp = vec2(dot(v_wpos.xz, vec2(0.8, 0.6)) + v_wpos.y * 0.5, v_wpos.y - dot(v_wpos.xz, vec2(0.3, -0.4)));
	float stroke = texture(macro_tex, sp * vec2(0.6, 0.09)).r;
	a *= mix(1.0, mix(0.9, 1.07, m1) * mix(0.95, 1.04, stroke), variation);
	// 地面際: 色付きの柔らかい陰り（汚れではなく接地感）
	vec2 huv = (v_wpos.xz + half_size) / (2.0 * half_size);
	huv = huv * ((grid_n - 1.0) / grid_n) + 0.5 / grid_n;
	float gh = texture(height_tex, huv).r;
	float above = v_wpos.y - gh;
	float g = (1.0 - smoothstep(0.0, 1.2, above)) * grime;
	a = mix(a, a * vec3(0.78, 0.74, 0.8), g * 0.45);
	vec3 d_emis = vec3(0.0);
	if (v_dstate.g + v_dstate.b > 0.001 || v_dcut.x < 1e5) {
		vec2 dp = vec2(dot(v_wpos.xz, vec2(0.71, 0.71)) + v_wpos.y * 0.3, v_wpos.y + dot(v_wpos.xz, vec2(0.6, -0.8)) * 0.5);
		float n2 = texture(macro_tex, dp * 0.11).r;
		float n3 = texture(macro_tex, dp * 0.45 + vec2(0.37, 0.11)).r;
		if (v_dcut.x < 1e5 && v_wpos.y > destruct_jag(n2, n3)) {
			discard;
		}
		a = destruct_albedo(a, v_wpos, texture(macro_tex, v_wpos.xz * 0.05 + v_wpos.y * 0.07).r, n2, n3, d_emis);
	}
	ALBEDO = clamp(a, 0.0, 1.0);
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), flat_normal);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	float vlum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	if (glass > 0.5) {
		// アニメのガラス: 空色のグラデーション＋斜めのハイライト帯
		float gy = clamp(fract(v_wpos.y * 0.25), 0.0, 1.0);
		vec3 gc = mix(vec3(0.42, 0.55, 0.68), vec3(0.75, 0.86, 0.95), gy) * (COLOR.rgb * 0.5 + 0.5);
		float st = fract((v_wpos.x + v_wpos.z) * 0.4 + v_wpos.y * 0.5);
		gc += vec3(0.35) * (step(0.78, st) * step(st, 0.86) + step(0.9, st) * step(st, 0.93));
		ALBEDO = gc * (1.0 - world_night * 0.85);
		SPECULAR = 0.5;
		ROUGHNESS = 0.2;
		EMISSION = vec3(1.0, 0.72, 0.38) * world_night * 1.6;
	}
	// 夜: 軒下・壁面がほのかに暖色（屋内の灯りの照り返し）
	float under = smoothstep(0.2, -0.6, v_wnrm.y) * 0.5 + (1.0 - abs(v_wnrm.y)) * 0.15;
	if (glass < 0.5) {
		EMISSION = a * vec3(1.0, 0.62, 0.3) * world_night * under * 0.35 + d_emis;
		if (window_glow > 0.5 && vlum < 0.125 && abs(v_wnrm.y) < 0.3) {
			// 格子窓・開口部から漏れる灯り
			EMISSION += vec3(1.0, 0.66, 0.32) * world_night * 1.4;
		}
	}
}

void light() {
	toon_light_common(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.0, rim_mul, DIFFUSE_LIGHT);
	if (shine > 0.0 && LIGHT_IS_DIRECTIONAL) {
		vec3 h = normalize(VIEW + LIGHT);
		float s = smoothstep(0.93, 0.96, dot(NORMAL, h)) * smoothstep(0.3, 0.6, ATTENUATION);
		SPECULAR_LIGHT += LIGHT_COLOR / PI * s * shine;
	}
}
