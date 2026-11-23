// アニメ調（セルルック）共通ライティング。地形・建物・植生・小道具で共有する。
// MToon（人物）に合わせ、2〜3 段の明暗・色付きの影・柔らかいリムライト。
// グローバル: toon_shade_color（影色）, toon_params = (境界, ぼかし幅, リム強さ, 影の明るさ)
global uniform vec4 toon_shade_color;
global uniform vec4 toon_params;
global uniform float world_night;

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
		// 影（シャドウマップ）は少しだけ硬く
		float sh = smoothstep(0.25, 0.65, atten);
		float lit = toon_band(ndl + wrap, edge, soft) * sh;
		// 明部の中のハイライト帯（3 段目）
		float hi = toon_band(ndl + wrap, 0.62, soft * 1.5) * sh;
		vec3 shade = toon_shade_color.rgb * toon_params.w;
		vec3 tone = mix(shade, vec3(1.0), lit) + vec3(0.07) * hi;
		// リム（逆光側のふち）: 光の方向から少し回り込む柔らかい縁取り
		float fres = 1.0 - clamp(dot(N, V), 0.0, 1.0);
		float rim = smoothstep(0.55, 0.85, fres) * smoothstep(-0.5, 0.3, dot(-V, L) + ndl * 0.3);
		tone += vec3(rim * toon_params.z * rim_mul) * mix(0.5, 1.0, sh);
		diffuse += lcol / PI * tone;
	} else {
		// 灯籠・街灯など: 柔らかい半ランバート
		float d = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
		diffuse += lcol / PI * atten * smoothstep(0.2, 0.8, d) * 1.2;
	}
}
