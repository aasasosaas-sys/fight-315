shader_type spatial;
// 全画面ポスト: 深度・法線のエッジ検出で輪郭線（下地の色を暗くした色線）＋太陽からの光芒（画面空間の放射ブラー）。
// 画面を覆うクアッドとして描く（EraWorld が生成）。乗算済みアルファで合成。
render_mode unshaded, blend_premul_alpha, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest;

uniform float line_strength = 0.75;
uniform vec3 line_tint : source_color = vec3(0.32, 0.22, 0.28);
uniform float line_far = 260.0;       // この距離で線が消える
uniform float depth_thresh = 0.06;    // 相対深度差
uniform float normal_thresh = 0.45;
uniform float line_width = 1.0;
// 光芒
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float sun_vis = 0.0;          // 0..1（太陽が画面内・手前にある度合い）
uniform vec3 ray_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float ray_strength = 0.35;
uniform float vignette = 0.18;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	vec4 nr = texture(nr_tex, uv);
	return normalize(nr.xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = line_width / VIEWPORT_SIZE * max(VIEWPORT_SIZE.y / 1080.0, 0.75);
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = lin_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// 手前側のピクセルにだけ線を出す（太さ 1px で外側の輪郭）
	float dmin = min(min(dl, dr), min(du, dd));
	float dmax = max(max(dl, dr), max(du, dd));
	float rel = (dmax - dc) / max(dc, 0.1);
	float thr = depth_thresh * (1.0 + 2.5 * (1.0 - smoothstep(4.0, 20.0, dc)));
	float e_depth = smoothstep(thr, thr * 1.8, rel);
	// 法線の折れ（近距離のみ）
	vec3 nc = view_normal(uv);
	vec3 nl = view_normal(uv - vec2(px.x, 0.0));
	vec3 nu = view_normal(uv - vec2(0.0, px.y));
	float ndiff = max(1.0 - dot(nc, nl), 1.0 - dot(nc, nu));
	float same_surface = 1.0 - smoothstep(0.01, 0.03, abs(dl - dc) / max(dc, 0.1) + abs(du - dc) / max(dc, 0.1));
	float e_norm = smoothstep(normal_thresh, normal_thresh + 0.2, ndiff) * (1.0 - smoothstep(30.0, 70.0, dc)) * mix(1.0, 0.6, same_surface);
	float sky = step(texture(depth_tex, uv).r, 0.000001);
	float edge = max(e_depth, e_norm) * (1.0 - smoothstep(line_far * 0.4, line_far, dc)) * (1.0 - sky);
	edge *= line_strength;
	vec3 sc = textureLod(screen_tex, uv, 0.0).rgb;
	// 線の色: 下地を暗く・少し彩度を上げた色（黒ではない）
	float l = dot(sc, vec3(0.3, 0.59, 0.11));
	vec3 lc = mix(vec3(l), sc, 1.4) * 0.4 * (line_tint * 2.0);
	lc = max(lc, vec3(0.0));

	// ---- 光芒: 太陽に向かって空のピクセルを集める
	vec3 rays = vec3(0.0);
	if (sun_vis > 0.001) {
		vec2 dir = (sun_uv - uv);
		float acc = 0.0;
		float wsum = 0.0;
		float w = 1.0;
		vec2 step_v = dir / 24.0;
		vec2 p = uv;
		float jit = fract(sin(dot(uv * VIEWPORT_SIZE, vec2(12.9898, 78.233))) * 43758.5453);
		p += step_v * jit;
		for (int i = 0; i < 24; i++) {
			float dz = texture(depth_tex, p).r;
			acc += step(dz, 0.000001) * w;
			wsum += w;
			w *= 0.94;
			p += step_v;
		}
		acc /= wsum;
		float fall = 1.0 - smoothstep(0.0, 0.85, length(dir * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0)));
		rays = ray_color * acc * fall * fall * ray_strength * sun_vis;
	}
	// 周辺減光（ごく弱く）
	vec2 vc = uv - 0.5;
	float vig = smoothstep(0.35, 0.95, length(vc * vec2(1.0, 0.85)) * 1.25) * vignette;
	float a = clamp(edge + vig * (1.0 - edge), 0.0, 1.0);
	ALBEDO = lc * edge + vec3(0.06, 0.05, 0.1) * vig * (1.0 - edge) + rays;
	ALPHA = a;
}
