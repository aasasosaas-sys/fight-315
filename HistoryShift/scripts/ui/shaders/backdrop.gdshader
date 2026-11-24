shader_type canvas_item;
// 動く背景: 墨色のグラデーション + 柔らかい光の塊 + 時空の粒子 + 微かな方眼
uniform float intensity = 0.5;
uniform float stars = 0.5;
uniform vec4 base_top : source_color = vec4(0.09, 0.06, 0.13, 1.0);
uniform vec4 base_bottom : source_color = vec4(0.04, 0.03, 0.06, 1.0);
uniform vec4 tint_a : source_color = vec4(0.37, 0.91, 1.0, 1.0);
uniform vec4 tint_b : source_color = vec4(0.86, 0.24, 0.2, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float aspect = 1.0 / max(SCREEN_PIXEL_SIZE.x, 0.0001) * SCREEN_PIXEL_SIZE.y;
	vec2 p = vec2(uv.x / aspect, uv.y);
	float t = TIME;
	vec3 col = mix(base_top.rgb, base_bottom.rgb, uv.y);
	// 光の塊
	vec2 c1 = vec2(0.25 + 0.1 * sin(t * 0.13), 0.35 + 0.08 * cos(t * 0.11));
	vec2 c2 = vec2(0.8 + 0.08 * cos(t * 0.09), 0.7 + 0.1 * sin(t * 0.07));
	float b1 = exp(-6.0 * length((uv - c1) * vec2(1.0, 1.3)));
	float b2 = exp(-5.0 * length((uv - c2) * vec2(1.0, 1.3)));
	col += tint_a.rgb * b1 * 0.22 * intensity;
	col += tint_b.rgb * b2 * 0.18 * intensity;
	// 揺らぎ
	float n = noise(uv * vec2(3.0, 6.0) + vec2(t * 0.05, -t * 0.03));
	col += vec3(0.04, 0.03, 0.06) * n * intensity;
	// 方眼（時空座標）
	vec2 g = abs(fract(uv * vec2(32.0, 18.0)) - 0.5);
	float grid = smoothstep(0.485, 0.5, max(g.x, g.y));
	col += tint_a.rgb * grid * 0.025 * intensity;
	// 流れる粒子
	float s = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		vec2 q = uv * vec2(60.0 + fk * 30.0, 34.0 + fk * 17.0);
		q.y += t * (0.6 + fk * 0.5);
		q.x += sin(t * 0.2 + fk) * 2.0;
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash(id + fk * 13.0);
		if (h > 0.965) {
			float tw = 0.5 + 0.5 * sin(t * (1.0 + h * 3.0) + h * 40.0);
			s += smoothstep(0.12, 0.0, length(f)) * tw * (0.6 - fk * 0.15);
		}
	}
	col += mix(tint_a.rgb, vec3(1.0), 0.5) * s * stars;
	// ビネット
	float v = smoothstep(1.2, 0.3, length((uv - 0.5) * vec2(1.2, 1.0)));
	col *= mix(0.55, 1.0, v);
	COLOR = vec4(col, 1.0);
}
