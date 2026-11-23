// 破壊状態（scripts/world/destruction.gd が更新）。UV2.x = ユニット ID（0 = 対象外）, UV2.y = 部位（0 躯体 / 1 屋根）
// 行 2k:   (隠すビット, 焦げ, ひび, 燃焼)   行 2k+1: (切断高さ y, 切断のギザギザ幅, 切断フラグ, -)
global uniform sampler2D destruct_tex;

varying flat vec4 v_dstate;
varying flat vec2 v_dcut;

void destruct_vertex(inout vec3 vtx, vec2 uv2) {
	v_dstate = vec4(0.0);
	v_dcut = vec2(1e6, 0.0);
	int id = int(uv2.x + 0.5);
	if (id > 0) {
		ivec2 tc = ivec2(id % 256, (id / 256) * 2);
		vec4 st = texelFetch(destruct_tex, tc, 0);
		int hide = int(st.r + 0.5);
		int part = int(uv2.y + 0.5);
		if ((hide & (1 << part)) != 0) {
			vtx = vec3(0.0);
		}
		v_dstate = st;
		vec4 cut = texelFetch(destruct_tex, tc + ivec2(0, 1), 0);
		if (cut.b > 0.5) {
			v_dcut = cut.rg;
		}
	}
}

// 切断線（崩れた壁のギザギザの上端）
float destruct_jag(float n2, float n3) {
	return v_dcut.x + (n2 - 0.5) * 2.0 * v_dcut.y + (n3 - 0.5) * 0.6;
}

// 焦げ・ひび・燃えさし。base はアルベド、n1/n2 はノイズ（0-1）。返り値 xyz=アルベド, emission は out 引数
vec3 destruct_albedo(vec3 base, vec3 wpos, float n1, float n2, float n3, out vec3 emis) {
	emis = vec3(0.0);
	vec3 a = base;
	float ch = v_dstate.g;
	float cr = v_dstate.b;
	float burn = v_dstate.a;
	if (ch > 0.001) {
		// 斑の焦げ（ベタの黒茶）
		float blot = n1 * 0.65 + n2 * 0.35;
		float m = clamp((ch * 1.35 - (1.0 - blot)) * 7.0, 0.0, 1.0);
		vec3 coal = vec3(0.12, 0.09, 0.08);
		a = mix(a, a * vec3(0.55, 0.45, 0.4), clamp(ch * 1.6, 0.0, 1.0) * 0.6);
		a = mix(a, coal, m);
		if (burn > 0.01) {
			// 燃えさしの赤い筋
			float e = smoothstep(0.47, 0.5, n3) * (1.0 - smoothstep(0.5, 0.53, n3));
			emis = vec3(1.0, 0.32, 0.06) * burn * (m * 0.6 + e * 2.5);
		}
	}
	if (cr > 0.001) {
		// ひび（墨の線）
		float line = 1.0 - smoothstep(0.0, 0.018, abs(n3 - 0.5));
		float mask = smoothstep(1.0 - cr * 1.2, 1.0 - cr * 1.2 + 0.15, n1);
		a = mix(a, vec3(0.08, 0.07, 0.08), line * mask * 0.9);
		a *= 1.0 - mask * cr * 0.12;
	}
	// 崩れた断面の縁（切断線のすぐ下を暗く）
	if (v_dcut.x < 1e5) {
		float jag = destruct_jag(n2, n3);
		float edge = 1.0 - smoothstep(0.0, 0.35, jag - wpos.y);
		a = mix(a, vec3(0.1, 0.08, 0.07), edge * 0.85);
	}
	return a;
}
