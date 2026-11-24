shader_type spatial;
// 建物用アニメ調シェーダ: テクスチャは平均色（ベタ塗り）＋輝度の明暗を少しだけ（手描きの筆ムラ）。
// セル塗りのライティング（toon.gdshaderinc）。夜は窓（emissive 側）以外も軒下がほんのり暖色に。
// 手描き背景の塗り: 暖色・寒色の色ムラ、壁の雨だれ・裾の汚れ（色付きの陰り）、瓦の空の映り込みと艶の帯、
// 木部の木目の筆致、石垣の石ごとの濃淡。材質の種類は mat_kind（materials.gd が設定）。
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
// 手描き背景の塗り
uniform float mat_kind = 0.0;       // 0 一般 / 1 漆喰・塗り壁 / 2 木部 / 3 瓦 / 4 石・煉瓦 / 5 茅葺 / 6 布
uniform vec3 era_tint : source_color = vec3(1.0);   // 時代ごとの色味（漆喰の白を落ち着かせるなど）
uniform float sheen = 0.0;          // 空の映り込み（瓦・金属）
uniform float paint = 1.0;          // 筆致の強さ（0 で従来）
instance uniform float hs_indoor = 0.0;   // 1: 屋内の内装（world_interiors.gd が設定）。障子の透け・木と畳の暖色

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	vec4 d_st;
	vec2 d_cut;
	destruct_vertex(VERTEX, UV2, d_st, d_cut);
	v_dstate = d_st;
	v_dcut = d_cut;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	UV *= uv_scale;
	// 内装は外殻の内壁・床と同じ面に重なる板が多い（z ファイティングで黒い櫛状のちらつき）。
	// カメラへわずかに寄せて（画面上の位置はほぼ同じ）、内装側を確実に手前に描く。
	if (hs_indoor > 0.5) {
		vec3 cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		vec3 to_cam = cam_l - VERTEX;
		VERTEX += normalize(to_cam) * min(0.025, length(to_cam) * 0.004);
	}
}

vec3 saturate_col(vec3 c, float s) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	return max(mix(vec3(l), c, s), vec3(0.0));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
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
	vec3 a = saturate_col(base * mix(1.0, rel, detail), sat_boost) * COLOR.rgb * era_tint;
	float vlum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	// 壁面に沿った水平座標（雨だれ・木目の向きに使う）
	vec2 wall_dir = normalize(vec2(-v_wnrm.z, v_wnrm.x) + vec2(1e-4));
	float wall_u = dot(v_wpos.xz, wall_dir);
	float vert = 1.0 - smoothstep(0.35, 0.7, abs(v_wnrm.y));   // 1 = 鉛直な面
	// 筆ムラ（大きめの色ムラ＋斜めのストローク）
	float m1 = texture(macro_tex, v_wpos.xz * 0.031 + v_wpos.y * 0.017).r;
	vec2 sp = vec2(dot(v_wpos.xz, vec2(0.8, 0.6)) + v_wpos.y * 0.5, v_wpos.y - dot(v_wpos.xz, vec2(0.3, -0.4)));
	float stroke = texture(macro_tex, sp * vec2(0.6, 0.09)).r;
	a *= mix(1.0, mix(0.9, 1.07, m1) * mix(0.95, 1.04, stroke), variation);
	// 暖色・寒色の色ムラ（手描きの背景画の「色の揺らぎ」）
	float mh = texture(macro_tex, v_wpos.xz * 0.011 - v_wpos.y * 0.013 + vec2(0.41, 0.17)).r;
	a *= mix(vec3(1.0), mix(vec3(0.95, 0.98, 1.05), vec3(1.05, 1.0, 0.94), smoothstep(0.3, 0.7, mh)), 0.8 * paint * variation);
	// 地面際: 色付きの柔らかい陰り（汚れではなく接地感）
	vec2 huv = (v_wpos.xz + half_size) / (2.0 * half_size);
	huv = huv * ((grid_n - 1.0) / grid_n) + 0.5 / grid_n;
	float gh = texture(height_tex, huv).r;
	float above = v_wpos.y - gh;
	float g = (1.0 - smoothstep(0.0, 1.2, above)) * grime;
	a = mix(a, a * vec3(0.78, 0.74, 0.8), g * 0.45);
	// 壁の下ほど少し沈む大きなグラデーション（環境光の遮蔽の代わり。影色寄りの寒色）
	float ao_g = (1.0 - smoothstep(0.0, 3.2, above)) * vert * grime * paint * step(mat_kind, 2.5);
	a *= mix(vec3(1.0), mix(vec3(0.84, 0.84, 0.92), toon_shade_color.rgb * 1.3, 0.25), ao_g * 0.6);
	if (mat_kind > 0.5 && mat_kind < 1.5) {
		// 漆喰・塗り壁: 白いほど汚れが見える。雨だれの縦筋（上から）と、裾の泥はね
		float white = smoothstep(0.55, 0.85, vlum);
		float big = texture(macro_tex, vec2(wall_u * 0.05, v_wpos.y * 0.06) + vec2(0.13, 0.71)).r;
		a *= mix(vec3(0.9, 0.89, 0.88), vec3(1.0, 0.995, 0.98), smoothstep(0.3, 0.7, big));
		float drip = texture(macro_tex, vec2(wall_u * 0.42, v_wpos.y * 0.035) + vec2(0.7, 0.2)).r;
		float drip2 = texture(macro_tex, vec2(wall_u * 1.3, v_wpos.y * 0.09) + vec2(0.2, 0.5)).r;
		float streak = smoothstep(0.6, 0.78, drip * 0.7 + drip2 * 0.45) * vert;
		a *= 1.0 - streak * vec3(0.13, 0.12, 0.09) * (0.4 + white) * paint;
		float splash = (1.0 - smoothstep(0.0, 0.7 + drip * 0.6, above)) * vert;
		a = mix(a, a * vec3(0.8, 0.74, 0.68), splash * 0.35 * white * paint * grime);
	} else if (mat_kind > 1.5 && mat_kind < 2.5) {
		// 木部: 木目の筆致（縦横どちらの材にも馴染むよう、壁沿い方向と高さの両方で細い筋）
		float gr = texture(macro_tex, vec2(wall_u * 0.06 + v_wpos.y * 0.9, v_wpos.y * 0.05 + wall_u * 0.7) * vec2(1.0, 0.25)).r;
		float rings = smoothstep(0.45, 0.6, fract(gr * 9.0));
		a *= mix(1.0, mix(0.92, 1.05, rings), 0.6 * paint);
		a = saturate_col(a, 1.08);
	} else if (mat_kind > 2.5 && mat_kind < 3.5) {
		// 瓦: 列ごとの濃淡（棟から軒へ）。軒先ほど少し明るく、谷は暗く
		float row = texture(macro_tex, vec2(wall_u * 0.03, v_wpos.y * 0.6) + vec2(0.3, 0.9)).r;
		a *= mix(0.93, 1.06, row);
	} else if (mat_kind > 3.5 && mat_kind < 4.5) {
		// 石・煉瓦: 石ごとの濃淡（ざっくりしたセル）
		vec3 cell = floor(v_wpos * vec3(1.6, 2.2, 1.6));
		float h = hash13(cell);
		a *= mix(0.9, 1.08, h);
		a = mix(a, a * vec3(0.86, 0.94, 0.8), smoothstep(0.75, 0.95, h) * 0.5 * (1.0 - smoothstep(0.0, 2.0, above)));
	} else if (mat_kind > 6.5 && mat_kind < 7.5) {
		// 畳: い草の目（細い縞）と、縁に向かう日焼けのムラ
		float rush = smoothstep(0.35, 0.65, fract(dot(v_wpos.xz, vec2(1.0, 0.0)) * 9.0 + texture(macro_tex, v_wpos.xz * 0.3).r * 0.5));
		a *= mix(0.95, 1.03, rush);
		a *= mix(vec3(1.0), vec3(1.05, 1.0, 0.86), texture(macro_tex, v_wpos.xz * 0.07).r);
	} else if (mat_kind > 4.5 && mat_kind < 5.5) {
		// 茅葺: 毛羽立った筆の縦筋
		float fib = texture(macro_tex, vec2(wall_u * 2.2, v_wpos.y * 0.2)).r;
		a *= mix(0.88, 1.08, fib);
	}
	vec3 d_emis = vec3(0.0);
	if (v_dstate.g + v_dstate.b > 0.001 || v_dcut.x < 1e5) {
		vec2 dp = vec2(dot(v_wpos.xz, vec2(0.71, 0.71)) + v_wpos.y * 0.3, v_wpos.y + dot(v_wpos.xz, vec2(0.6, -0.8)) * 0.5);
		float n2 = texture(macro_tex, dp * 0.11).r;
		float n3 = texture(macro_tex, dp * 0.45 + vec2(0.37, 0.11)).r;
		if (v_dcut.x < 1e5 && v_wpos.y > destruct_jag(v_dcut, n2, n3)) {
			discard;
		}
		a = destruct_albedo(v_dstate, v_dcut, a, v_wpos, texture(macro_tex, v_wpos.xz * 0.05 + v_wpos.y * 0.07).r, n2, n3, d_emis);
	}
	vec3 in_emis = vec3(0.0);
	if (hs_indoor > 0.5) {
		// 屋内: 木部・畳は暖かく、白い紙・漆喰の壁は外光が透けてほのかに光る（障子）。天井は少し沈む
		if (mat_kind > 1.5 && mat_kind < 2.5) {
			a *= vec3(1.06, 1.0, 0.9);
		}
		float paper = smoothstep(0.78, 0.92, vlum) * vert * step(mat_kind, 1.5);
		in_emis = a * vec3(1.0, 0.95, 0.84) * paper * (0.09 * (1.0 - world_night) + 0.06 * world_night);
		a *= mix(1.0, 0.86, smoothstep(-0.3, -0.8, v_wnrm.y));
	}
	// 瓦・金属: 空の映り込み（浅い角度ほど空の色）。夜は弱く
	if (sheen > 0.0) {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		float up = smoothstep(-0.2, 0.6, v_wnrm.y);
		vec3 sheen_col = mix(world_sky_color.rgb, vec3(0.42, 0.52, 0.72), 0.55) * 0.8;
		a = mix(a, sheen_col, clamp(fres * up * sheen, 0.0, 0.5) * (1.0 - world_night * 0.7));
	}
	ALBEDO = clamp(a, 0.0, 1.0);
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), flat_normal);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	if (glass > 0.5) {
		// アニメのガラス: 空色のグラデーション＋斜めのハイライト帯
		float gy = clamp(fract(v_wpos.y * 0.25), 0.0, 1.0);
		vec3 skyc = mix(vec3(0.42, 0.55, 0.68), world_sky_color.rgb, 0.5);
		vec3 gc = mix(skyc * 0.75, skyc * 1.15 + 0.08, gy) * (COLOR.rgb * 0.5 + 0.5);
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
		EMISSION = a * vec3(1.0, 0.62, 0.3) * world_night * under * 0.7 * (1.0 - hs_indoor) + d_emis + in_emis;
		if (window_glow > 0.5 && vlum < 0.125 && abs(v_wnrm.y) < 0.3 && hs_indoor < 0.5) {
			// 格子窓・開口部から漏れる灯り（夜）。昼は奥の暗がりを少し青く沈める
			float flick = 0.85 + 0.15 * texture(macro_tex, v_wpos.xz * 0.2 + vec2(TIME * 0.05)).r;
			EMISSION += vec3(1.0, 0.66, 0.32) * world_night * 2.6 * flick;
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.8, 0.85, 1.1), 1.0 - world_night);
		}
	}
}

void light() {
	toon_light_common(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.0, rim_mul, DIFFUSE_LIGHT);
	if (shine > 0.0 && LIGHT_IS_DIRECTIONAL) {
		vec3 h = normalize(VIEW + LIGHT);
		float nh = dot(NORMAL, h);
		// くっきりした帯ハイライト＋外側の柔らかいにじみ（アニメの艶）
		float s = smoothstep(0.93, 0.96, nh) + smoothstep(0.8, 0.92, nh) * 0.08;
		s *= smoothstep(0.3, 0.6, ATTENUATION);
		SPECULAR_LIGHT += LIGHT_COLOR / PI * s * shine;
	}
}
