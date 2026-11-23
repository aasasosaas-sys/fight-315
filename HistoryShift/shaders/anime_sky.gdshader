shader_type sky;
// アニメ背景調の空: グラデーション＋太陽の光暈＋手描き風の積雲（地平線の入道雲と頭上の雲の層）。
// 雲はセル塗り（明・中・影の 3 段）で縁が日に光る。太陽の高さで夕焼け・夜へ自動で移る。
// TIME を使わない（放射輝度マップを毎フレーム更新させないため）。

uniform vec3 zenith_color : source_color = vec3(0.16, 0.42, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.80, 0.96);
uniform vec3 haze_color : source_color = vec3(0.86, 0.92, 0.98);
uniform vec3 ground_color : source_color = vec3(0.45, 0.55, 0.62);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.55, 0.3);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_mid : source_color = vec3(0.86, 0.9, 0.98);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.66, 0.84);
uniform vec3 night_zenith : source_color = vec3(0.02, 0.04, 0.12);
uniform vec3 night_horizon : source_color = vec3(0.08, 0.12, 0.25);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.5;     // 頭上の雲の量 0..1
uniform float tower = 0.6;           // 地平線の入道雲の高さ・量
uniform float cirrus = 0.4;          // 高い所の筋雲
uniform float cloud_seed = 0.0;
uniform float sunset_amount = 1.0;   // 低い太陽での夕焼けの強さ
uniform float exposure = 1.0;
uniform float sun_size = 1.0;

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

float fbm(vec2 p) {
	return n2(p) * 0.6 + n2(p * 2.3 + 0.37) * 0.28 + n2(p * 5.1 + 0.71) * 0.12;
}

// 地平線の入道雲の輪郭（>0 で雲の中）。a: 方位(0..1), y: 仰角(sin)
float tower_field(float a, float y) {
	float h = n2(vec2(a * 3.0 + cloud_seed, 0.21));
	h = smoothstep(0.38, 0.75, h) * 0.32 * tower + 0.035 * tower;
	// もこもこ（大小の丸い盛り上がり）
	float puff = n2(vec2(a * 15.0 + cloud_seed, y * 6.0 + 0.5)) * 0.65 + n2(vec2(a * 40.0, y * 15.0 + 0.2)) * 0.35;
	return h * (0.72 + 0.5 * puff) - y;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 L = normalize(LIGHT0_DIRECTION);
	float sun_y = L.y;
	float day = smoothstep(-0.12, 0.12, sun_y);
	float low_sun = (1.0 - smoothstep(0.02, 0.4, sun_y)) * smoothstep(-0.2, 0.0, sun_y) * sunset_amount;
	float y = d.y;
	float yu = max(y, 0.0);
	float mu = dot(d, L);
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 lh = normalize(L.xz + vec2(1e-5));
	float toward_sun = dot(dh, lh) * 0.5 + 0.5;

	// ---- 空のグラデーション
	vec3 zen = mix(night_zenith, zenith_color, day);
	vec3 hor = mix(night_horizon, horizon_color, day);
	vec3 haze = mix(night_horizon * 1.2, haze_color, day);
	// 夕焼け: 太陽側の地平線をオレンジ〜ピンクに
	hor = mix(hor, mix(sunset_color * 0.9 + vec3(0.1, 0.0, 0.1), sunset_color, toward_sun), low_sun * mix(0.45, 1.0, toward_sun));
	haze = mix(haze, sunset_color * 1.15 + vec3(0.05), low_sun * mix(0.35, 1.0, toward_sun));
	zen = mix(zen, zen * vec3(0.85, 0.8, 1.05), low_sun * 0.5);
	float t = pow(yu, 0.45);
	vec3 col = mix(hor, zen, smoothstep(0.0, 1.0, t));
	col = mix(haze, col, smoothstep(0.0, 0.16, yu));

	// ---- 太陽の光暈
	float glow = pow(max(mu, 0.0), 6.0) * 0.35 + pow(max(mu, 0.0), 48.0) * 0.6;
	vec3 sglow = mix(sun_color, sunset_color, low_sun);
	col += sglow * glow * mix(0.6, 1.2, low_sun) * day;

	// ---- 頭上の雲の層（平面投影）
	vec3 ccol = vec3(0.0);
	float calpha = 0.0;
	if (y > 0.0) {
		vec2 p = d.xz / (y + 0.09) * 0.11 + vec2(cloud_seed * 0.37, cloud_seed * 0.19);
		float den = fbm(p);
		float cov = mix(0.82, 0.42, cloud_cover);
		float m = smoothstep(cov, cov + 0.06, den);
		// 光源側へずらしたサンプルとの差で陰影（セル 3 段）
		float den2 = fbm(p + lh * 0.035);
		float lit = clamp((den - den2) * 9.0 + 0.55, 0.0, 1.0);
		float thick = smoothstep(cov, cov + 0.25, den);
		vec3 cc = mix(cloud_shade, cloud_mid, smoothstep(0.35, 0.45, lit - thick * 0.25));
		cc = mix(cc, cloud_light, smoothstep(0.62, 0.7, lit - thick * 0.15));
		// 縁の光（太陽に近いほど強い）
		float rimc = (1.0 - smoothstep(cov, cov + 0.035, den)) * (0.4 + 0.8 * pow(max(mu, 0.0), 4.0));
		cc += sglow * rimc * 0.5;
		float fade = smoothstep(0.0, 0.14, y);
		ccol = cc;
		calpha = m * fade;
		// 筋雲（高い薄雲）
		vec2 q = d.xz / (y + 0.2) * vec2(0.05, 0.4);
		float ci = n2(q + vec2(0.3, cloud_seed)) * n2(q * vec2(2.0, 0.5) + 0.6);
		float cm = smoothstep(0.3, 0.42, ci) * cirrus * smoothstep(0.08, 0.35, y) * (1.0 - calpha);
		col = mix(col, mix(cloud_mid, cloud_light, 0.6), cm * 0.55);
	}
	col = mix(col, ccol, calpha);

	// ---- 地平線の入道雲（方位・仰角の空間で輪郭を作る）
	if (y > -0.02 && y < 0.5 && tower > 0.01) {
		float a = atan(d.x, d.z) / 6.2831853 + 0.5;
		float f = tower_field(a, y);
		if (f > 0.0) {
			float e = 0.004;
			float fa = tower_field(a + e, y) - f;
			float fy = tower_field(a, y + e) - f;
			vec2 g = normalize(vec2(fa, fy) + vec2(1e-6));
			// 太陽の方位（左右）と高さから 2D の光方向
			float side = dh.x * lh.y - dh.y * lh.x;
			vec2 l2 = normalize(vec2(-sign(side) * (1.0 - toward_sun) * 1.2 - 0.0001, 0.8 + sun_y));
			float lit = dot(-g, l2);
			float depth = clamp(f / 0.05, 0.0, 1.0);
			vec3 tc = mix(cloud_shade, cloud_mid, smoothstep(-0.15, 0.0, lit - depth * 0.35));
			tc = mix(tc, cloud_light, smoothstep(0.35, 0.45, lit - depth * 0.2));
			// 下の方は空気遠近で地平線の色へ
			tc = mix(tc, haze * 1.05, (1.0 - smoothstep(0.0, 0.09, y)) * 0.55);
			// 夕方は雲が茜色に
			tc = mix(tc, tc * mix(vec3(1.0), sunset_color * 1.4, 0.7), low_sun * (0.4 + 0.6 * toward_sun));
			float edge = 1.0 - smoothstep(0.0, 0.006, f);
			tc += sglow * edge * (0.25 + 0.6 * toward_sun) * day;
			col = mix(col, tc, smoothstep(0.0, 0.002, f));
		}
	}
	// 雲全体の明るさは昼夜と夕焼けで変化
	// ---- 太陽本体
	float disk = smoothstep(0.99955 - 0.0004 * sun_size, 0.99975 - 0.0004 * sun_size, mu);
	col += sglow * disk * 6.0 * day;
	// ---- 夜の星
	if (day < 0.99 && y > 0.0) {
		vec3 sd = floor(d * 380.0);
		float h = fract(sin(dot(sd, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float star = step(0.9985, h) * (1.0 - day) * smoothstep(0.05, 0.3, y);
		col += vec3(star) * 1.5;
	}
	// 地平線より下: 霞〜地面色
	if (y < 0.0) {
		col = mix(haze, ground_color * mix(0.15, 1.0, day), smoothstep(0.0, 0.25, -y));
	}
	col *= mix(0.25, 1.0, day) * exposure;
	COLOR = col;
}
