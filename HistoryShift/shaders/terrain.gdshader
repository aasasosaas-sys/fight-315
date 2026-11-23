shader_type spatial;
// 地形スプラット: 斜面・高さ・道/広場/田畑/森マスクで PolyHaven テクスチャ配列をブレンド。
// 2 スケール＋回転サンプリングとマクロノイズでタイリング感を消す。
render_mode diffuse_burley, specular_schlick_ggx;

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

uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 lush_color : source_color = vec3(0.32, 0.42, 0.16);
uniform vec3 forest_tint : source_color = vec3(0.85, 0.8, 0.7);
uniform vec3 rock_tint : source_color = vec3(0.62, 0.6, 0.56);
uniform vec3 road_tint : source_color = vec3(1.0);
uniform vec3 plaza_tint : source_color = vec3(1.0);
uniform vec3 field_color : source_color = vec3(0.24, 0.27, 0.15);
uniform float snow_height = 9999.0;
uniform float road_scale = 0.22;
uniform float plaza_scale = 0.25;

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

// 1 レイヤを 2 スケールでサンプル（回転で継ぎ目を崩す）
void sample_layer(float L, vec2 wp, vec2 gdx, vec2 gdy, float scale, float mixv, out vec3 a, out vec3 n, out float r) {
	vec2 uv1 = wp * scale;
	vec2 uv2 = rot2(wp, 1.1) * scale * 0.43 + vec2(0.37, 0.71);
	vec2 dx1 = gdx * scale, dy1 = gdy * scale;
	vec2 dx2 = rot2(gdx, 1.1) * scale * 0.43, dy2 = rot2(gdy, 1.1) * scale * 0.43;
	vec3 a1 = textureGrad(alb_arr, vec3(uv1, L), dx1, dy1).rgb;
	vec3 a2 = textureGrad(alb_arr, vec3(uv2, L), dx2, dy2).rgb;
	vec3 n1 = textureGrad(nrm_arr, vec3(uv1, L), dx1, dy1).rgb;
	vec3 n2 = textureGrad(nrm_arr, vec3(uv2, L), dx2, dy2).rgb;
	float r1 = textureGrad(rgh_arr, vec3(uv1, L), dx1, dy1).r;
	float r2 = textureGrad(rgh_arr, vec3(uv2, L), dx2, dy2).r;
	a = mix(a1, a2, mixv);
	n = mix(n1, n2, mixv);
	r = mix(r1, r2, mixv);
}

void sample_single(float L, vec2 uv, vec2 dx, vec2 dy, out vec3 a, out vec3 n, out float r) {
	a = textureGrad(alb_arr, vec3(uv, L), dx, dy).rgb;
	n = textureGrad(nrm_arr, vec3(uv, L), dx, dy).rgb;
	r = textureGrad(rgh_arr, vec3(uv, L), dx, dy).r;
}

float hblend(float w, float hgt, float sharp) {
	// 高さ（輝度）を使った境界のギザギザ
	return clamp((w - 0.5) * sharp + 0.5 + (hgt - 0.45) * (1.0 - abs(w * 2.0 - 1.0)) * 1.6, 0.0, 1.0);
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
	float mixv = smoothstep(0.35, 0.65, m2);

	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float far_k = smoothstep(60.0, 260.0, dist);

	vec3 alb; vec3 nrm; float rgh;
	// 草（基本）
	sample_layer(L_GRASS, wp, gdx, gdy, 0.24, mix(mixv, 0.8, far_k * 0.6), alb, nrm, rgh);
	vec3 lush = alb * lush_color * 2.6;
	alb = mix(alb, lush, smoothstep(0.3, 0.75, m1) * 0.75);
	alb *= grass_tint;

	vec3 a2; vec3 n2; float r2;
	// 土のパッチ
	float dirt_w = smoothstep(0.62, 0.8, m2 * 0.7 + m3 * 0.5) * 0.7;
	// 森の地面
	float forest_w = ctrl.a;
	if (forest_w > 0.01) {
		sample_layer(L_FOREST, wp, gdx, gdy, 0.25, mixv, a2, n2, r2);
		a2 *= forest_tint;
		float w = hblend(forest_w, dot(a2, vec3(0.33)), 2.0);
		alb = mix(alb, a2, w); nrm = mix(nrm, n2, w); rgh = mix(rgh, r2, w);
	}
	if (dirt_w > 0.01) {
		sample_layer(L_DIRT, wp, gdx, gdy, 0.2, mixv, a2, n2, r2);
		a2 *= vec3(0.9, 0.85, 0.8);
		float w = hblend(dirt_w, dot(a2, vec3(0.33)), 2.5);
		alb = mix(alb, a2, w); nrm = mix(nrm, n2, w); rgh = mix(rgh, r2, w);
	}
	// 田畑（湿った土＋苗の列）
	float field_w = ctrl.b;
	if (field_w > 0.01) {
		sample_single(L_DIRT, wp * 0.3, gdx * 0.3, gdy * 0.3, a2, n2, r2);
		a2 = mix(a2 * 0.55, field_color, 0.55);
		float rows = smoothstep(0.35, 0.5, abs(fract(dot(wp, vec2(0.7071)) * 1.4) - 0.5));
		a2 *= mix(1.0, 0.82, rows);
		alb = mix(alb, a2, field_w); nrm = mix(nrm, n2, field_w); rgh = mix(rgh, r2 * 0.35, field_w);
	}
	// 砂浜
	float sand_w = 1.0 - smoothstep(water_level + 1.2, water_level + 3.4, v_wpos.y + (m3 - 0.5) * 1.5);
	if (sand_w > 0.01) {
		sample_layer(L_SAND, wp, gdx, gdy, 0.2, mixv, a2, n2, r2);
		float wet = 1.0 - smoothstep(water_level - 0.2, water_level + 0.9, v_wpos.y);
		a2 *= mix(1.0, 0.6, wet);
		r2 = mix(r2, 0.25, wet);
		alb = mix(alb, a2, sand_w); nrm = mix(nrm, n2, sand_w); rgh = mix(rgh, r2, sand_w);
	}
	// 岩（急斜面: 三平面投影）
	float slope = 1.0 - v_wnrm.y;
	float rock_w = smoothstep(0.2, 0.34, slope + (m3 - 0.5) * 0.12);
	if (rock_w > 0.01) {
		vec3 bw = pow(abs(v_wnrm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 ax; vec3 nx; float rx;
		vec3 ay; vec3 ny; float ry;
		vec3 az; vec3 nz; float rz;
		sample_single(L_ROCK, v_wpos.zy * 0.08, pdx.zy * 0.08, pdy.zy * 0.08, ax, nx, rx);
		sample_single(L_ROCK, v_wpos.xz * 0.08, pdx.xz * 0.08, pdy.xz * 0.08, ay, ny, ry);
		sample_single(L_ROCK, v_wpos.xy * 0.08, pdx.xy * 0.08, pdy.xy * 0.08, az, nz, rz);
		a2 = ax * bw.x + ay * bw.y + az * bw.z;
		n2 = ny;
		r2 = rx * bw.x + ry * bw.y + rz * bw.z;
		float lum = dot(a2, vec3(0.33));
		a2 = mix(vec3(lum), a2, 0.35) * rock_tint * 1.6;
		float w = hblend(rock_w, lum, 2.0);
		alb = mix(alb, a2, w); nrm = mix(nrm, n2, w); rgh = mix(rgh, r2, w);
	}
	// 広場・建物まわり
	float plaza_w = ctrl.g;
	if (plaza_w > 0.01) {
		sample_layer(L_PLAZA, wp, gdx, gdy, plaza_scale, mixv * 0.5, a2, n2, r2);
		a2 *= plaza_tint;
		float w = hblend(plaza_w, dot(a2, vec3(0.33)), 3.0);
		alb = mix(alb, a2, w); nrm = mix(nrm, n2, w); rgh = mix(rgh, r2, w);
	}
	// 道
	float road_w = ctrl.r;
	if (road_w > 0.01) {
		sample_layer(L_ROAD, wp, gdx, gdy, road_scale, mixv * 0.5, a2, n2, r2);
		a2 *= road_tint;
		float w = hblend(road_w, dot(a2, vec3(0.33)) + (m3 - 0.5) * 0.4, 3.5);
		alb = mix(alb, a2, w); nrm = mix(nrm, n2, w); rgh = mix(rgh, r2, w);
	}

	// 山頂の雪
	float snow_w = smoothstep(snow_height, snow_height + 18.0, v_wpos.y + (m2 - 0.5) * 30.0) * smoothstep(0.35, 0.75, v_wnrm.y + 0.2);
	if (snow_w > 0.01) {
		alb = mix(alb, vec3(0.92, 0.94, 0.98), snow_w);
		rgh = mix(rgh, 0.55, snow_w);
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), snow_w * 0.7);
	}
	// マクロな明暗・色ムラ
	alb *= mix(0.82, 1.12, m1) * mix(0.92, 1.06, m3);
	ALBEDO = clamp(alb, 0.0, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, far_k);
	ROUGHNESS = clamp(rgh, 0.05, 1.0);
	SPECULAR = 0.35;
}
