// AnimeFace: face-skin overlay pass (next_pass of the VRoid Face_00_SKIN MToon material).
// Paints anime-style details procedurally in head space, using the rest-pose vertex position
// (relative to the Head bone) that AnimeFace bakes into CUSTOM0:
//   facial hair (stubble / mustache / goatee / full beard / drooping "dojo" mustache),
//   wrinkle lines (crow's feet, under-eye, nasolabial, forehead), blush (+ child hatching),
//   freckles, a mole, a thin scar.
// x: character's left/right (mirrored with abs), y: up, z: forward (face front).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 eye = vec3(0.03, 0.06, 0.03);      // eye centre (|x|, y, z) rel. Head bone
uniform float eye_r = 0.017;                    // eye half width
uniform vec2 mouth = vec2(-0.0, 0.08);          // (y, z) of the mouth
uniform float chin_y = -0.03;
uniform float nose_y = 0.02;
uniform float face_w = 0.07;                    // half width of the face at mouth level

uniform int beard = 0;                          // 0 none 1 stubble 2 mustache 3 goatee 4 full 5 dojo 6 mustache+goatee
uniform vec4 beard_col : source_color = vec4(0.1, 0.08, 0.08, 1.0);
uniform float stubble = 0.0;                    // 0..1 bluish shaved shadow (can combine with beard)
uniform float wrinkles = 0.0;                   // 0..1
uniform vec4 line_col : source_color = vec4(0.55, 0.32, 0.28, 1.0);
uniform float blush = 0.0;
uniform float blush_lines = 0.0;                // anime hatching strokes on the blush (children)
uniform vec4 blush_col : source_color = vec4(1.0, 0.45, 0.45, 1.0);
uniform float freckles = 0.0;
uniform vec4 mole = vec4(0.0, 0.0, 0.0, 0.0);  // x (signed), y, radius, on
uniform vec4 scar = vec4(0.0);                  // x0, y0, x1, y1 (signed x) – active if scar_on
uniform float scar_on = 0.0;

varying vec3 rp;

void vertex() {
	rp = CUSTOM0.xyz;
	// identical transform to MToon (skip_vertex_transform) plus a tiny lift along the normal
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * 0.00025, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// tapered stroke along a segment: width w at the start, fading to w*tip at the end
float stroke(vec2 p, vec2 a, vec2 b, float w, float tip) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * h);
	float ww = w * mix(1.0, tip, h);
	float aa = fwidth(d) * 0.8 + 1e-6;
	return 1.0 - smoothstep(ww - aa, ww + aa, d);
}

float fill(float d) {   // d < 0 inside
	float aa = fwidth(d) * 0.8 + 1e-6;
	return 1.0 - smoothstep(-aa, aa, d);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void over(inout vec4 acc, vec3 col, float a) {
	a = clamp(a, 0.0, 1.0);
	acc.rgb = mix(acc.rgb, col, a);
	acc.a = acc.a + a * (1.0 - acc.a);
}

void fragment() {
	vec3 p = rp;
	float ax = abs(p.x);
	float F = eye.x;                 // face unit: half the distance between the eyes
	vec2 q = vec2(ax, p.y);
	vec4 acc = vec4(0.0);
	float front = smoothstep(eye.z - 0.045, eye.z - 0.02, p.z);   // front part of the head only
	float my = mouth.x;

	// ---- blush ----
	if (blush > 0.0) {
		vec2 bc = vec2(eye.x * 1.08, eye.y - F * 0.72);
		vec2 bd = (q - bc) / vec2(F * 0.52, F * 0.26);
		float g = exp(-dot(bd, bd) * 1.6);
		over(acc, blush_col.rgb, g * blush * 0.42 * front);
		if (blush_lines > 0.0) {
			for (int i = 0; i < 3; i++) {
				float ox = (float(i) - 1.0) * F * 0.2;
				vec2 a = bc + vec2(ox + F * 0.08, F * 0.12);
				vec2 b = bc + vec2(ox - F * 0.04, -F * 0.12);
				over(acc, blush_col.rgb * 0.8, stroke(q, a, b, F * 0.022, 0.4) * blush_lines * 0.8 * front);
			}
		}
	}

	// ---- freckles ----
	if (freckles > 0.0) {
		vec2 cell = q / (F * 0.13);
		vec2 ci = floor(cell);
		vec2 cf = fract(cell) - 0.5;
		float h = hash(ci + vec2(p.x > 0.0 ? 3.0 : 7.0));
		vec2 off = vec2(hash(ci + 1.3), hash(ci + 2.7)) - 0.5;
		float d = length(cf - off * 0.5) - 0.17;
		vec2 fc = (q - vec2(eye.x * 0.9, eye.y - F * 0.62)) / vec2(F * 0.75, F * 0.32);
		float region = exp(-dot(fc, fc) * 1.5);
		if (h < 0.55) {
			over(acc, vec3(0.62, 0.38, 0.3), fill(d * F * 0.13) * region * freckles * 0.75 * front);
		}
	}

	// ---- wrinkle lines (anime style: few, clean strokes) ----
	if (wrinkles > 0.0) {
		float lw = F * 0.022;
		vec3 lc = line_col.rgb;
		float wa = wrinkles * front;
		// crow's feet from the outer eye corner
		vec2 o = vec2(eye.x + eye_r * 1.05, eye.y - eye_r * 0.05);
		over(acc, lc, stroke(q, o + vec2(eye_r * 0.12, eye_r * 0.18), o + vec2(eye_r * 0.62, eye_r * 0.42), lw, 0.3) * wa * 0.75);
		over(acc, lc, stroke(q, o + vec2(eye_r * 0.16, -eye_r * 0.04), o + vec2(eye_r * 0.7, -eye_r * 0.08), lw, 0.3) * wa * 0.75);
		over(acc, lc, stroke(q, o + vec2(eye_r * 0.12, -eye_r * 0.26), o + vec2(eye_r * 0.58, -eye_r * 0.52), lw, 0.3) * wa * 0.6);
		// under-eye bag: a soft arc
		vec2 ue = q - vec2(eye.x + eye_r * 0.05, eye.y + eye_r * 0.15);
		float ang = atan(ue.y, ue.x);
		float rr = abs(length(ue / vec2(1.0, 0.85)) - eye_r * 1.12);
		float arcm = smoothstep(-2.75, -2.35, ang) * (1.0 - smoothstep(-0.8, -0.4, ang));
		float aa = fwidth(rr) + 1e-6;
		over(acc, lc, (1.0 - smoothstep(lw * 0.8 - aa, lw * 0.8 + aa, rr)) * arcm * wa * 0.55);
		// nasolabial fold: nose wing → beside the mouth corner
		vec2 n0 = vec2(F * 0.34, nose_y - F * 0.02);
		vec2 n1 = vec2(F * 0.52, my + F * 0.06);
		vec2 n2 = vec2(F * 0.56, my - F * 0.16);
		float d1 = min(seg(q, n0, n1), seg(q, n1, n2));
		float fade = smoothstep(n2.y, n2.y + F * 0.1, p.y) * (1.0 - smoothstep(n0.y - F * 0.04, n0.y, p.y));
		float a1 = fwidth(d1) + 1e-6;
		over(acc, lc, (1.0 - smoothstep(lw - a1, lw + a1, d1)) * fade * wa * 0.7);
		// forehead lines (visible when the hairstyle leaves the forehead bare)
		for (int i = 0; i < 2; i++) {
			float fy = eye.y + F * (1.55 + float(i) * 0.22);
			float yy = fy + (ax * ax) / (F * 4.0);
			float d2 = abs(p.y - yy);
			float ef = 1.0 - smoothstep(F * 0.55, F * 0.95 - float(i) * F * 0.2, ax);
			float a2 = fwidth(d2) + 1e-6;
			over(acc, lc, (1.0 - smoothstep(lw * 0.8 - a2, lw * 0.8 + a2, d2)) * ef * wa * 0.45);
		}
		// mouth-corner lines (marionette) only for strong wrinkles
		vec2 m0 = vec2(F * 0.42, my - F * 0.08);
		over(acc, lc, stroke(q, m0, m0 + vec2(F * 0.04, -F * 0.22), lw * 0.9, 0.2) * max(wa - 0.5, 0.0) * 1.1);
	}

	// ---- facial hair ----
	float lipm = length((q - vec2(0.0, my)) / vec2(F * 0.5, F * 0.1)) - 1.0;   // lips (keep clear)
	if (stubble > 0.0 || beard == 1 || beard == 4) {
		// beard area: under the nose, around the mouth, along the jaw up to the sideburns
		float top = mix(nose_y - F * 0.12, eye.y - F * 0.55, smoothstep(F * 0.35, face_w * 0.95, ax));
		float reg = (1.0 - smoothstep(top - F * 0.05, top + F * 0.05, p.y));
		reg *= smoothstep(-0.035, -0.015, p.z);
		reg *= smoothstep(-0.2, 0.25, lipm);
		float st = max(stubble, beard == 1 ? 1.0 : 0.0);
		if (st > 0.0) {
			float n = hash(floor(vec2(p.x, p.y) / (F * 0.035)));
			vec3 sc = mix(vec3(0.42, 0.5, 0.62), beard_col.rgb, 0.35);
			over(acc, sc, reg * st * (0.22 + 0.12 * n));
		}
		if (beard == 4) {
			// full beard: solid with a jagged lower-cheek edge
			float jag = sin(ax / (F * 0.09) * 3.14159) * F * 0.04;
			float top2 = mix(my - F * 0.06, eye.y - F * 0.7, smoothstep(F * 0.3, face_w * 0.9, ax)) + jag;
			float reg2 = (1.0 - smoothstep(top2 - F * 0.02, top2 + F * 0.02, p.y)) * smoothstep(-0.04, -0.02, p.z);
			reg2 *= smoothstep(-0.05, 0.1, lipm);
			over(acc, beard_col.rgb, reg2 * 0.95);
		}
	}
	if (beard == 2 || beard == 4 || beard == 5 || beard == 6) {
		// mustache: an arch above the upper lip, thick in the middle, thin at the ends
		float lx = F * (beard == 5 ? 0.62 : 0.55);
		float t = clamp(ax / lx, 0.0, 1.0);
		float cy = my + F * 0.16 - F * 0.1 * t * t;
		float th = F * 0.075 * (1.0 - 0.75 * t * t) + F * 0.012;
		float d = abs(p.y - cy) - th;
		d = max(d, ax - lx);
		d = max(d, -(ax - F * 0.03) * 0.6 - (p.y - (my + F * 0.22)) * 0.2);   // little philtrum notch
		float a = fill(d) * front;
		over(acc, beard_col.rgb, a * 0.97);
		if (beard == 5) {
			// drooping ends (dojo / sage): continue down past the mouth corners
			over(acc, beard_col.rgb, stroke(q, vec2(lx * 0.95, my + F * 0.08), vec2(lx * 1.05, my - F * 0.55), F * 0.045, 0.35) * front);
		}
	}
	if (beard == 3 || beard == 4 || beard == 6 || beard == 5) {
		// goatee on the chin + small patch under the lower lip
		vec2 gc = vec2(0.0, chin_y + F * 0.3);
		float g = length((q - gc) / vec2(F * (beard == 5 ? 0.22 : 0.3), F * 0.32)) - 1.0;
		float soul = length((q - vec2(0.0, my - F * 0.17)) / vec2(F * 0.1, F * 0.06)) - 1.0;
		float a = max(fill(g * F * 0.3), fill(soul * F * 0.06));
		over(acc, beard_col.rgb, a * smoothstep(-0.03, -0.01, p.z) * 0.97);
	}

	// ---- mole ----
	if (mole.w > 0.0) {
		float d = length(vec2(p.x, p.y) - mole.xy) - mole.z;
		over(acc, vec3(0.25, 0.14, 0.12), fill(d) * front * 0.9);
	}
	// ---- scar ----
	if (scar_on > 0.0) {
		vec2 sp = vec2(p.x, p.y);
		over(acc, vec3(0.78, 0.45, 0.42), stroke(sp, scar.xy, scar.zw, F * 0.04, 0.5) * 0.55 * smoothstep(eye.z - 0.03, eye.z - 0.01, p.z));
		over(acc, vec3(0.5, 0.22, 0.22), stroke(sp, scar.xy, scar.zw, F * 0.016, 0.4) * 0.7 * smoothstep(eye.z - 0.03, eye.z - 0.01, p.z));
	}

	ALBEDO = acc.rgb;
	ALPHA = acc.a;
}
