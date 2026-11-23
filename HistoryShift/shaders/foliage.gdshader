shader_type spatial;
// 葉カード（手続き的な葉の形で alpha scissor）＋内側の塊。風で揺れる。
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 leaf_color : source_color = vec3(0.16, 0.3, 0.08);
uniform vec3 leaf_color2 : source_color = vec3(0.24, 0.36, 0.1);
uniform float leaf_count = 6.0;
uniform float leaf_size = 0.42;
uniform float leaf_aspect = 0.5;
uniform float sway = 1.0;
uniform float translucency = 0.45;
// 写真の葉アトラス（黒背景・上段5枚/下段3枚）。use_tex=1 で使用
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float use_tex = 0.0;
uniform vec3 tex_tint : source_color = vec3(1.0);
uniform float tex_desat = 0.0;

varying vec3 v_col;
varying float v_core;

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
	// 葉先の細かい揺れ
	VERTEX += NORMAL * sin(TIME * 4.0 + VERTEX.x * 3.0 + VERTEX.y * 2.0) * 0.03 * (1.0 - COLOR.a) * sway;
	v_col = mix(leaf_color, leaf_color2, hv) * mix(0.55, 1.08, COLOR.r);
	v_core = COLOR.a;
}

vec4 atlas_leaf(vec2 lp, float r, float lod) {
	// lp: 葉ローカル座標（-0.5..0.5、y が葉の長さ方向）
	float idx = floor(r * 7.999);
	vec2 rect_pos = idx < 5.0 ? vec2(idx * 0.2, 0.0) : vec2((idx - 5.0) * 0.2, 0.5);
	vec2 uv = rect_pos + vec2(lp.x + 0.5, 0.5 - lp.y) * vec2(0.2, 0.5);
	if (lp.x < -0.5 || lp.x > 0.5 || lp.y < -0.5 || lp.y > 0.5) return vec4(0.0);
	vec3 c = textureLod(leaf_tex, uv, lod).rgb;
	float a = smoothstep(0.05, 0.12, max(c.r, max(c.g, c.b)));
	return vec4(c, a);
}

void fragment() {
	float a = 1.0;
	float shade = 1.0;
	vec3 texc = vec3(-1.0);
	if (v_core < 0.5) {
		vec2 g = UV * leaf_count;
		vec2 id = floor(g);
		float best = 10.0;
		float bid = 0.0;
		float lod = clamp(log2(max(length(dFdx(UV)), length(dFdy(UV))) * 1024.0 / leaf_count * 2.5), 0.0, 8.0);
		bool tex_mode = use_tex > 0.5;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 c = id + vec2(float(x), float(y));
				float r = hash12(c);
				float r2 = hash12(c + 7.7);
				vec2 ctr = c + vec2(r, r2);
				vec2 d = g - ctr;
				float ang = r * 6.2831;
				vec2 rd = vec2(cos(ang) * d.x + sin(ang) * d.y, -sin(ang) * d.x + cos(ang) * d.y);
				if (tex_mode) {
					vec2 lp = vec2(rd.x / (leaf_size * leaf_aspect * 2.0), rd.y / (leaf_size * 2.0));
					vec4 lc = atlas_leaf(lp, r2, lod);
					if (lc.a > 0.5 && r2 < best) { best = r2; bid = r2; texc = lc.rgb; }
				} else {
					rd.y /= leaf_aspect;
					rd.x *= 1.0 + 0.4 * rd.y;
					float dd = length(rd) / leaf_size;
					if (dd < best) { best = dd; bid = r2; }
				}
			}
		}
		if (tex_mode) {
			a = texc.r >= 0.0 ? 1.0 : 0.0;
		} else {
			a = 1.0 - step(1.0, best);
		}
		float edge = length(UV - 0.5) * 2.0;
		a *= step(edge, 0.98 - hash12(floor(g)) * 0.15);
		shade = mix(0.78, 1.12, bid);
	}
	vec3 col = v_col * shade;
	if (texc.r >= 0.0) {
		vec3 tc = mix(texc, vec3(dot(texc, vec3(0.3, 0.59, 0.11))), tex_desat);
		col = tc * tex_tint * 2.2 * mix(0.6, 1.1, (v_col.g + v_col.r) * 2.0) * shade;
	}
	ALBEDO = col;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.65;
	SPECULAR = 0.35;
	BACKLIGHT = col * translucency;
}
