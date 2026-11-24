// アニメ調（セルルック）共通ライティング。地形・建物・植生・小道具で共有する。
// MToon（人物）に合わせ、2〜3 段の明暗・色付きの影・柔らかいリムライト。
// グローバル: toon_shade_color（影色）, toon_params = (境界, ぼかし幅, リム強さ, 影の明るさ)
//             world_sky_color（空の地平の色: 影の照り返し・リム）, world_sun_color（日なたのハイライトの色味）
global uniform vec4 toon_shade_color;
global uniform vec4 toon_params;
global uniform float world_night;
global uniform vec4 world_sky_color;
global uniform vec4 world_sun_color;

// 呼び出し側で TOON_RIM / TOON_WRAP を上書きしたい場合は #define 前にこのファイルを include しない

float toon_band(float x, float edge, float soft) {
	return smoothstep(edge - soft, edge + soft, x);
}

void toon_light_common(vec3 N, vec3 V, vec3 L, vec3 lcol, float atten, bool directional, float wrap, float rim_mul,
		inout vec3 diffuse) {
	float ndl = dot(N, L);
	if (directional) {
		float edge = toon_params.x;
		float soft = toon_params.y;
		// 影（シャドウマップ）は少しだけ硬く＝セル影のくっきりした境界
		float sh = smoothstep(0.3, 0.62, atten);
		float x = ndl + wrap;
		float lit = toon_band(x, edge, soft) * sh;
		// 明部の中のハイライト帯（3 段目）: 日の色に寄せた暖色
		float hi = toon_band(x, 0.6, soft * 1.5) * sh;
		vec3 shade = toon_shade_color.rgb * toon_params.w;
		// 影の中でも空を向く面は少し明るく（空の照り返し＝青みの段）
		float sky_up = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
		shade *= mix(0.92, 1.08, sky_up);
		vec3 warm = normalize(world_sun_color.rgb + vec3(0.001)) * 1.732;
		vec3 tone = mix(shade, vec3(1.0), lit) + (warm * 0.5 + 0.5) * 0.08 * hi - vec3(0.0, 0.0, 0.03) * hi;
		// 明暗の境目にごく薄く彩度の高い帯（塗りの境界の「色の転び」）
		float term = lit * (1.0 - toon_band(x, edge + 0.14, soft * 2.0));
		tone *= 1.0 + vec3(0.05, 0.0, -0.04) * term;
		// リム（逆光側のふち）: 光の方向から少し回り込む柔らかい縁取り。空の色を帯びる
		float fres = 1.0 - clamp(dot(N, V), 0.0, 1.0);
		float rim = smoothstep(0.55, 0.85, fres) * smoothstep(-0.5, 0.3, dot(-V, L) + ndl * 0.3);
		vec3 rim_col = mix(vec3(1.0), world_sky_color.rgb * 1.25 + 0.15, 0.35);
		tone += rim_col * rim * toon_params.z * rim_mul * mix(0.5, 1.0, sh);
		diffuse += lcol / PI * tone;
	} else {
		// 灯籠・街灯など: 柔らかい半ランバート
		float d = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
		diffuse += lcol / PI * atten * smoothstep(0.2, 0.8, d) * 1.2;
	}
}
