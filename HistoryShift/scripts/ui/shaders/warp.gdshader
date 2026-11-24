shader_type canvas_item;
// 時空跳躍: 放射状の光の筋 + トンネル + 色収差
uniform float progress = 0.0;   // 0..1 演出の進行
uniform float strength = 1.0;   // 0..1 全体の強さ（フェード用）
uniform vec4 cyan : source_color = vec4(0.37, 0.91, 1.0, 1.0);
uniform vec4 shu : source_color = vec4(0.86, 0.24, 0.2, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }

float streaks(vec2 d, float t, float speed) {
	float r = length(d);
	float a = atan(d.y, d.x);
	float seg = 220.0;
	float id = floor((a / 6.2831853 + 0.5) * seg);
	float h = hash(id);
	float h2 = hash(id + 17.3);
	float z = fract(1.0 / max(r, 0.02) * 0.15 + h - t * speed * (0.6 + h2));
	float line = smoothstep(0.0, 0.05, z) * smoothstep(0.35 + h2 * 0.3, 0.05, z);
	float width = smoothstep(0.5, 0.0, abs(fract((a / 6.2831853 + 0.5) * seg) - 0.5));
	return line * width * step(0.35, h) * smoothstep(0.02, 0.35, r);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = (FRAGCOORD.xy - 0.5 * res) / res.y;
	float t = TIME;
	float speed = 0.6 + progress * 2.5;
	// 渦
	float r = length(uv);
	float ang = atan(uv.y, uv.x) + 0.6 / (r + 0.25) * progress;
	vec2 d = vec2(cos(ang), sin(ang)) * r;
	// 色収差: RGB をずらしてサンプル
	float ca = 0.012 + 0.02 * progress;
	float sr = streaks(d * (1.0 + ca), t, speed);
	float sg = streaks(d, t, speed);
	float sb = streaks(d * (1.0 - ca), t, speed);
	vec3 col = vec3(sr, sg, sb) * mix(cyan.rgb, vec3(1.0), 0.45) * 1.6;
	// トンネルの輪
	float rings = 0.5 + 0.5 * sin(18.0 / max(r, 0.05) - t * 8.0 * speed);
	col += cyan.rgb * pow(rings, 8.0) * smoothstep(0.05, 0.6, r) * 0.25;
	// 中心の閃光
	float core = exp(-r * (9.0 - 6.0 * progress));
	col += mix(cyan.rgb, vec3(1.0), 0.7) * core * (0.6 + 1.2 * progress);
	// 縁の朱の残光
	col += shu.rgb * smoothstep(0.5, 1.1, r) * 0.18 * (0.5 + 0.5 * sin(t * 3.0));
	// 背景
	vec3 bg = mix(vec3(0.02, 0.03, 0.08), vec3(0.03, 0.1, 0.16), core);
	col += bg;
	// 走査線
	col *= 0.92 + 0.08 * sin(FRAGCOORD.y * 1.5 + t * 30.0);
	// 終盤のホワイトアウト
	col = mix(col, vec3(1.0), smoothstep(0.85, 1.0, progress) * 0.85);
	COLOR = vec4(col, strength);
}
