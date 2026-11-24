render_mode skip_vertex_transform;
//render_mode specular_disabled,ambient_light_disabled;

// VARIANTS:
// DEFAULT_MODE:
#ifdef IS_OUTLINE
const float isOutline = 1.0;
#else
const float isOutline = 0.0;
#endif

// OUTLINE:
// // Comment `const float isOutline = 0.0;`
// render_mode cull_front;
// const float isOutline = 1.0;
// // Uncomment `ALPHA = alpha;` and comment `if (alpha < _Cutoff) { discard; }` at end of fragment()

// TRANSPARENT:
// // Uncomment `ALPHA = alpha;` and comment `if (alpha < _Cutoff) { discard; }` at end of fragment()

// TRANSPARENT_WITH_ZWRITE:
//render_mode depth_draw_always;
// // Uncomment `ALPHA = alpha;` and comment `if (alpha < _Cutoff) { discard; }` at end of fragment()

// CULL_OFF:
// render_mode cull_disabled;

// TRANSPARENT_CULL_OFF:
// render_mode cull_disabled;
// // Uncomment `ALPHA = alpha;` and comment `if (alpha < _Cutoff) { discard; }` at end of fragment()

// TRANSPARENT_WITH_ZWRITE_CULL_OFF:
// render_mode cull_disabled,depth_draw_always;
// // Uncomment `ALPHA = alpha;` and comment `if (alpha < _Cutoff) { discard; }` at end of fragment()


const bool CALCULATE_LIGHTING_IN_FRAGMENT = true;


uniform float _AlphaCutoutEnable : hint_range(0,1,1) = 0.0;
uniform float _Cutoff : hint_range(0,1) = 0.5;
uniform vec4 _Color : source_color = vec4(1.0,1.0,1.0,1.0); // "Lit Texture + Alpha"
uniform vec4 _ShadeColor : source_color = vec4(0.97, 0.81, 0.86, 1); // "Shade Color"
uniform sampler2D _MainTex : source_color, hint_default_white;
uniform vec4 _MainTex_ST = vec4(1.0,1.0,0.0,0.0);
uniform sampler2D _ShadeTexture : source_color, hint_default_white;
uniform float _BumpScale : hint_range(-16,16) = 1.0; // "Normal Scale"
uniform sampler2D _BumpMap : hint_normal; // "Normal Texture"
uniform sampler2D _ReceiveShadowTexture : hint_default_white;
uniform float _ReceiveShadowRate = 1.0; // "Receive Shadow"
uniform sampler2D _ShadingGradeTexture : hint_default_white;
uniform float _ShadingGradeRate = 1.0; // "Shading Grade"
uniform float _ShadeShift : hint_range(-1.0, 1.0) = 0.0;
uniform float _ShadeToony : hint_range(0.0, 1.0) = 0.9;
uniform float _LightColorAttenuation : hint_range(0.0, 1.0) = 0.0;
uniform float _IndirectLightIntensity : hint_range(0.0, 1.0) = 0.1;
uniform sampler2D _RimTexture : source_color, hint_default_white;
uniform vec4 _RimColor : source_color = vec4(0,0,0,1);
uniform float _RimLightingMix : hint_range(0.0, 1.0) = 0.0;
uniform float _RimFresnelPower : hint_range(0.0, 100.0) = 1.0;
uniform float _RimLift : hint_range(0.0, 1.0) = 0.0;
uniform vec4 _MatcapColor : source_color = vec4(0,0,0,1);
uniform sampler2D _SphereAdd : source_color, hint_default_black; // "Sphere Texture(Add)"
uniform vec4 _EmissionColor : source_color = vec4(0,0,0,1); // "Color"
uniform float _EmissionMultiplier = 1.0;
uniform sampler2D _EmissionMap : source_color, hint_default_white;
// Not implemented:
uniform float _OutlineWidthMode : hint_range(0,2,1) = 1;
uniform sampler2D _OutlineWidthTexture : hint_default_white;
uniform float _OutlineWidth : hint_range(0.01, 1.0) = 0.5;
uniform float _OutlineScaledMaxDistance : hint_range(1,10) = 1;
uniform float _OutlineColorMode : hint_range(0,1,1) = 0;
uniform vec4 _OutlineColor : source_color = vec4(0,0,0,1);
uniform float _OutlineLightingMix : hint_range(0,1) = 0;
uniform sampler2D _UvAnimMaskTexture : hint_default_white;
uniform float _UvAnimScrollX = 0;
uniform float _UvAnimRotation = 0;
uniform float _UvAnimScrollY = 0;
uniform float _DebugMode : hint_range(0,3,1) = 0.0;

uniform float _MToonVersion = 33;
// HistoryShift: 部位の種類（scripts/player/anime_char.gd が設定）0 服 / 1 髪 / 2 肌 / 3 顔の肌 / 4 目・眉
uniform float _HsKind = 0.0;
uniform float _HsRim = 1.0;          // 背景と同じ調子のリムライトの強さ
uniform float _HsRing = 1.0;         // 髪の天使の輪の強さ
global uniform float world_night;
global uniform vec4 world_sky_color;
global uniform vec4 world_sun_color;

// const
const float PI_2 = 6.283185307180;
const float EPS_COL = 0.00001;


varying vec3 tspace0; // : TEXCOORD1;
varying vec3 tspace1; // : TEXCOORD2;
varying vec3 tspace2; // : TEXCOORD3;

void vertex() {
	UV=UV*_MainTex_ST.xy+_MainTex_ST.zw;
	COLOR=COLOR;

	if (isOutline == 1.0) {
		float outlineTex = textureLod(_OutlineWidthTexture, UV, 0).r;
		vec3 worldNormalLength = vec3(1.0/length(mat3(transpose(MODEL_MATRIX)) * NORMAL));
		vec3 outlineOffset = 0.01 * _OutlineWidth * outlineTex * worldNormalLength * NORMAL;
		vec3 conventional_outlined_vertex = (MODELVIEW_MATRIX * vec4(VERTEX + outlineOffset, 1.0)).xyz;
		if (_OutlineWidthMode < 1.5) {
			VERTEX = conventional_outlined_vertex;
		} else { // #elif defined(MTOON_OUTLINE_WIDTH_SCREEN)
			// 1. Create the clip-space position
			// 2. Get the normal direction, normalized, in clip space.
			// 3. Get the aspect ratio of the currently rendering camera.
			// 4. Scale the normals by the distance to the camera
			// 5. Add the normals to the clip-space XY position scaled by the width.
			VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec4 clipPos = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
			vec4 nearUpperRight = (INV_PROJECTION_MATRIX * vec4(1, 1, 0, 1));
			float aspect = abs(nearUpperRight.y / nearUpperRight.x);
			vec3 viewNormal = mat3(MODELVIEW_MATRIX) * NORMAL.xyz;
			vec3 clipNormal = mat3(PROJECTION_MATRIX) * viewNormal.xyz;
			vec2 projectedNormal = normalize(clipNormal.xy);
			projectedNormal *= min(clipPos.w, _OutlineScaledMaxDistance);
			projectedNormal.x *= aspect;
			clipPos.xy += 0.01 * _OutlineWidth * outlineTex * projectedNormal.xy * clamp(1.0 - abs(normalize(viewNormal).z), 0.0, 1.0); // ignore offset when normal toward camera
			VERTEX = vec3((INV_PROJECTION_MATRIX * clipPos).xy, conventional_outlined_vertex.z);
		}
	} else {
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}


	// posWorld = (MODELVIEW_MATRIX*vec4(VERTEX.xyz, 1.0));
	vec3 worldNormal = mat3(MODELVIEW_MATRIX)*NORMAL;
	vec3 worldTangent = mat3(MODELVIEW_MATRIX)*TANGENT;
	vec3 worldBitangent = mat3(MODELVIEW_MATRIX)*BINORMAL;
	tspace0 = vec3(worldTangent.x, worldBitangent.x, worldNormal.x);
	tspace1 = vec3(worldTangent.y, worldBitangent.y, worldNormal.y);
	tspace2 = vec3(worldTangent.z, worldBitangent.z, worldNormal.z);
}

vec3 UnpackScaleNormal(vec4 normalmap, float scale) {
	normalmap.xy = scale * (normalmap.xy * 2.0 - 1.0);
	normalmap.z = sqrt(max(0.0, 1.0 - dot(normalmap.xy, normalmap.xy))); //always ignore Z, as it can be RG packed, Z may be pos/neg, etc.
	return normalmap.xyz;
}

vec3 calculateLighting(vec2 mainUv, float dotNL, float lightAttenuation, vec4 shade_arg, vec4 lit_arg, vec3 lightColor, out vec3 col, out float lightIntensity) {
	// Decide albedo color rate from Direct Light
	float shadingGrade = 1.0 - _ShadingGradeRate * (1.0 - texture(_ShadingGradeTexture, mainUv).r);
	lightIntensity = dotNL; // [-1, +1]
	lightIntensity = lightIntensity * 0.5 + 0.5; // from [-1, +1] to [0, 1]
	lightIntensity = lightIntensity * lightAttenuation; // receive shadow
	lightIntensity = lightIntensity * shadingGrade; // darker
	lightIntensity = lightIntensity * 2.0 - 1.0; // from [0, 1] to [-1, +1]
	// tooned. mapping from [minIntensityThreshold, maxIntensityThreshold] to [0, 1]
	float maxIntensityThreshold = mix(1, _ShadeShift, _ShadeToony);
	float minIntensityThreshold = _ShadeShift;
	lightIntensity = clamp((lightIntensity - minIntensityThreshold) / max(EPS_COL, (maxIntensityThreshold - minIntensityThreshold)),0.0,1.0);

	col = mix(shade_arg.rgb, lit_arg.rgb, lightIntensity);
	// Direct Light
	vec3 lighting = lightColor / 3.14159;
	lighting = mix(lighting, max(vec3(EPS_COL), max(lighting.x, max(lighting.y, lighting.z))), _LightColorAttenuation); // color atten
	return lighting;
}

vec3 calculateAddLighting(vec2 mainUv, float dotNL, float dotNV, float shadowAttenuation, vec3 lighting, vec3 col, out vec3 specularLight) {
//	UNITY_LIGHT_ATTENUATION(shadowAttenuation, i, posWorld.xyz);
//#ifdef _ALPHABLEND_ON
//	lighting *= step(0, dotNL); // darken if transparent. Because Unity's transparent material can't receive shadowAttenuation.
//#endif

	float lightAtten = shadowAttenuation;
	// Godot specific code to deal with clustering artifacts: We balance out the light attenuation to make it appear toony so we can hard-cut it when ATTENUATION == 0
	float maxIntensityThreshold = mix(1, _ShadeShift, _ShadeToony);
	float minIntensityThreshold = _ShadeShift;
	lightAtten = clamp((shadowAttenuation - minIntensityThreshold) / max(EPS_COL, (maxIntensityThreshold - minIntensityThreshold)),0.0,1.0);
	// End Godot Specific code

	lighting *= 0.5; // darken if additional light.
	lighting *= min(0.0, dotNL) + 1.0; // darken dotNL < 0 area by using float lambert
	lighting *= lightAtten; // darken if receiving shadow
	col *= lighting;

	// parametric rim lighting
	vec3 staticRimLighting = vec3(0.0);
	vec3 mixedRimLighting = lighting;

	vec3 rimLighting = mix(staticRimLighting, mixedRimLighting, _RimLightingMix);
	vec3 rimuru = pow(clamp(1.0 - dotNV + _RimLift, 0.0, 1.0), _RimFresnelPower) * _RimColor.rgb * texture(_RimTexture, mainUv).rgb;
	specularLight = mix(rimuru * rimLighting, vec3(0.0), isOutline);
	return col;
}

vec4 GammaToLinearSpace (vec4 sRGB)
{
	// Approximate version from http://chilliant.blogspot.com.au/2012/08/srgb-approximations-for-hlsl.html?m=1
	return vec4(sRGB.rgb * (sRGB.rgb * (sRGB.rgb * 0.305306011 + 0.682171111) + 0.012522878), sRGB.a);
}

vec3 mix_normal(vec3 X, vec3 Y, float factor) {
	float new_x = (1.0 - factor  + factor * dot(X, Y));
	return normalize(cross(cross(X, Y), X)) * sqrt(1.0 - new_x * new_x) + new_x * normalize(X);
}

varying vec4 lit;
varying vec4 shade;
varying vec3 rim;
varying vec3 fragment_albedo_output;
varying vec2 mainUv;
varying vec3 viewNormal;

void fragment() {
	bool _NORMALMAP = textureSize(_BumpMap, 0).x > 8;
	bool MTOON_OUTLINE_COLOR_FIXED = _OutlineColorMode == 0.0;
	bool MTOON_OUTLINE_COLOR_MIXED = _OutlineColorMode == 1.0;

	ROUGHNESS = 1.0; // for now
	SPECULAR = 0.0; // for now
	RIM = 1.0;
	// uv
	mainUv = UV; //TRANSFORM_TEX(i.uv0, _MainTex);
	// uv anim
	float uvAnim = texture(_UvAnimMaskTexture, mainUv).r * TIME;
	// translate uv in bottom-left origin coordinates.
	mainUv += vec2(_UvAnimScrollX, -_UvAnimScrollY) * uvAnim;
	// rotate uv counter-clockwise around (0.5, 0.5) in bottom-left origin coordinates.
	float rotateRad = _UvAnimRotation * PI_2 * uvAnim;
	const vec2 rotatePivot = vec2(0.5, 0.5);
	mainUv = mat2(vec2(cos(rotateRad), sin(rotateRad)), vec2(-sin(rotateRad), cos(rotateRad))) * (mainUv - rotatePivot) + rotatePivot;

	// main tex
	vec4 mainTex = texture(_MainTex, mainUv);
	// alpha
	float alpha = _Color.a * mainTex.a;
	 // Albedo color
	shade = texture(_ShadeTexture, mainUv);
	lit = mainTex;
	vec3 emission = texture(_EmissionMap, mainUv).rgb * _EmissionColor.rgb * _EmissionMultiplier;

	vec3 tangentNormal = vec3(0.0,0.0,1.0);
	if (_NORMALMAP) {
		tangentNormal = UnpackScaleNormal(texture(_BumpMap, mainUv), _BumpScale);
	}

	shade *= _ShadeColor;
	lit *= _Color;
	
	//shade = min(shade, lit); ///// Mimic look of non-PBR min() clamp we commented out below.

	// normal
	viewNormal = vec3(0.0);
	if (_NORMALMAP) {
		viewNormal.x = dot(tspace0, tangentNormal);
		viewNormal.y = dot(tspace1, tangentNormal);
		viewNormal.z = dot(tspace2, tangentNormal);
	} else {
		viewNormal = vec3(tspace0.z, tspace1.z, tspace2.z);
	}
	vec3 viewView = VIEW;
	viewNormal *= step(0.0, dot(viewView, viewNormal)) * 2.0 - 1.0; // flip if projection matrix is flipped
	viewNormal *= mix(+1.0, -1.0, isOutline);
	viewNormal = normalize(viewNormal);

	// Unity lighting

	// Indirect Light
	vec3 up_normal = mat3(VIEW_MATRIX) * vec3(0.0,1.0,0.0);
	float LIGHT_COME_FROM_UP_RATIO = mix(0.8, 1.0, sin(_IndirectLightIntensity));
	fragment_albedo_output = max(lit.rgb, vec3(0.0001));

	rim = pow(clamp(1.0 - dot(viewNormal, viewView) + _RimLift, 0.0, 1.0), max(_RimFresnelPower, 0.001)) * _RimColor.rgb;

	// additive matcap
	vec3 viewCameraUp = vec3(0.0,1.0,0.0);//normalize(INV_VIEW_MATRIX[1].xyz); // FIXME!!
	vec3 viewViewUp = normalize(viewCameraUp - viewView * dot(viewView, viewCameraUp));
	vec3 viewViewRight = normalize(cross(viewView, viewViewUp));
	vec2 matcapUv = vec2(-dot(viewViewRight, viewNormal), -dot(viewViewUp, viewNormal)) * 0.5 + 0.5;
	vec3 matcapLighting = _MatcapColor.rgb * texture(_SphereAdd, matcapUv).rgb;

	rim = (rim + matcapLighting) * texture(_RimTexture, mainUv).rgb;

	emission += mix(rim * (1.0 - _RimLightingMix), vec3(0, 0, 0), isOutline);
	fragment_albedo_output += mix(rim * _RimLightingMix, vec3(0, 0, 0), isOutline);
	vec3 albedo = LIGHT_COME_FROM_UP_RATIO * fragment_albedo_output;
	NORMAL = normalize(mix_normal(up_normal, viewNormal, _IndirectLightIntensity));

	// Emission
	emission = mix(emission, vec3(0, 0, 0), isOutline);

	// outline
	if (isOutline == 1.0) {
		vec3 outlineColor = _OutlineColor.rgb;
		if (MTOON_OUTLINE_COLOR_FIXED) {
			albedo = vec3(0.0);
			emission = outlineColor;
		} else if (MTOON_OUTLINE_COLOR_MIXED) {
			emission = outlineColor.rgb * (1.0 - _OutlineLightingMix);
			// ALBEDO *= _OutlineLightingMix;
			lit.rgb *= outlineColor.rgb * _OutlineLightingMix;
			shade.rgb = lit.rgb;
			fragment_albedo_output = lit.rgb;
			albedo = LIGHT_COME_FROM_UP_RATIO * fragment_albedo_output;
		}
	}

	// debug
	if (_DebugMode >= 1.0) {
		shade = vec4(0.0);
		lit = vec4(0.0);
		// ALBEDO = vec3(0.0);
		emission = vec3(0.0);
		albedo = vec3(0.0);
		if (_DebugMode == 1.0) { //MTOON_DEBUG_NORMAL
			emission = ((mat3(INV_VIEW_MATRIX) * viewNormal * vec3(1.0,1.0,-1.0)) * 0.5 + vec3(0.5));
		} else if (_DebugMode == 2.0) { //MTOON_DEBUG_LITSHADERATE
			albedo = vec3(1.0) * LIGHT_COME_FROM_UP_RATIO; // lightIntensity * lighting;
		} else if (_DebugMode == 3.0) { // Add pass lighting
			emission = vec3(0.0); //addLightIntensity;
		}
	}
	//if (!LM_SCENEDATA_BOOL(lm_macro_system_enabled_)) {
	//	col.rgb = vec3(0.5 + 0.5 * sin(TIME +UV.x+UV.y),0.0,1.0);4
	//}
	fragment_albedo_output = max(fragment_albedo_output.rgb, vec3(0.0001));

	ALBEDO = albedo;
	EMISSION = emission;
	// HistoryShift: Godot の環境光（空）がそのまま全量加わると白飛びするので、MToon 本来の「間接光は控えめ」に寄せる
	AO = 0.35;
	AO_LIGHT_AFFECT = 0.0;

	ROUGHNESS = 1.0;
	METALLIC = 0.0;
#if defined(ALPHA_BLEND)
	ALPHA = alpha;
#elif defined(ALPHA_CUTOUT)
	if (_AlphaCutoutEnable > 0.5 && alpha < _Cutoff) { discard; }
#endif

	//METALLIC = metallic;
	//ROUGHNESS = roughness;
	//SPECULAR = specular;
}

float SchlickFresnel(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m; // pow(m,5)
}

void light() {
	bool isDirectional = true; // TODO: Generates clustered forward artifacts unless godotegnine/godot#48012 is applied
	// isDirectional = (RIM == 1.0);
	vec3 indirectLighting = vec3(0.0);
	// TODO if isFirstLight:
	//indirectLighting = DIFFUSE_LIGHT.rgb / fragment_albedo_output;
	//indirectLighting = mix(indirectLighting, max(vec3(EPS_COL), max(indirectLighting.x, max(indirectLighting.y, indirectLighting.z))), _LightColorAttenuation); // color atten
	// in light():

	float addDotNL =  dot(normalize(viewNormal), LIGHT);

	vec3 lighting = vec3(0.0);
	float lightIntensity = 0.0;
	vec3 addLightIntensity = vec3(0.0);
	vec3 diffuse_output = vec3(0.0);

	if (LIGHT_IS_DIRECTIONAL) {
		//UNITY_LIGHT_ATTENUATION(shadowAttenuation, i, posWorld.xyz);
		float lightAttenuation = mix(1.0, length(vec3(ATTENUATION))/length(vec3(1.0)), _ReceiveShadowRate * texture(_ReceiveShadowTexture, mainUv).r);

		vec3 col;
		float hsDotNL = addDotNL;
		if (_HsKind > 2.5 && _HsKind < 3.5) {
			// 顔: 法線の凹凸で斑な影が出ないよう、明暗をほぼ光の向きだけで決める（アニメの顔の影）
			hsDotNL = mix(addDotNL, 0.45 + 0.35 * addDotNL, 0.75);
			lightAttenuation = mix(1.0, lightAttenuation, 0.7);
		}
		vec4 hsShade = shade;
		if (_HsKind < 1.5 || _HsKind > 3.5) {
			// 服・髪の影: 背景の影と同じく空の色を少し帯びる
			hsShade.rgb = mix(shade.rgb, shade.rgb * (world_sky_color.rgb * 0.6 + 0.55), 0.35);
		}
		// shade
		lighting = calculateLighting(mainUv, hsDotNL, lightAttenuation, hsShade, lit, LIGHT_COLOR, col, lightIntensity);
		if (_HsKind > 1.5 && _HsKind < 3.5) {
			// 肌: 明暗の境目に赤みの帯（血色）
			float term = lightIntensity * (1.0 - lightIntensity) * 4.0;
			col += lit.rgb * vec3(0.16, 0.03, -0.01) * term;
		} else if (_HsKind < 1.5) {
			// 服・髪: 深い影の 3 段目（光の反対側だけ一段沈む）
			col *= mix(0.86, 1.0, smoothstep(-0.65, -0.3, addDotNL));
		}

		// base light does not darken.
		diffuse_output = col * lighting + indirectLighting * lit.rgb;

		//col = min(col, lit.rgb); // comment out if you want to PBR absolutely.

		// parametric rim lighting
		vec3 staticRimLighting = vec3(0.0);
		vec3 mixedRimLighting = lighting + indirectLighting;

		vec3 rimLighting = mix(staticRimLighting, mixedRimLighting, _RimLightingMix);
		SPECULAR_LIGHT += mix(rim * rimLighting, vec3(0, 0, 0), isOutline);

		if (isOutline < 0.5) {
			vec3 hsN = normalize(viewNormal);
			float hsSh = smoothstep(0.25, 0.65, lightAttenuation);
			// リムライト（日の当たる側と逆光の縁）: 地の色を明るくした色。目・眉には付けない
			if (_HsKind < 3.5) {
				float fres = 1.0 - clamp(dot(hsN, VIEW), 0.0, 1.0);
				float side = clamp(dot(hsN, LIGHT) * 0.7 + 0.35 + max(dot(-VIEW, LIGHT), 0.0) * 0.8, 0.0, 1.0);
				float rimk = smoothstep(0.6, 0.85, fres) * side * mix(0.35, 1.0, hsSh);
				vec3 rimc = mix(lit.rgb, vec3(1.0), 0.5) * mix(vec3(1.0), world_sun_color.rgb, 0.4);
				SPECULAR_LIGHT += LIGHT_COLOR / PI * rimc * rimk * 0.45 * _HsRim;
			}
			// 髪の天使の輪: 頭の上寄り（ビュー空間の法線の高さ）にぎざぎざの光の帯
			if (_HsKind > 0.5 && _HsKind < 1.5) {
				float jag = sin(hsN.x * 38.0) * 0.035 + sin(hsN.x * 91.0 + 1.3) * 0.015;
				float c = 0.5 + jag;
				float band = smoothstep(c - 0.13, c - 0.05, hsN.y) * (1.0 - smoothstep(c + 0.03, c + 0.11, hsN.y));
				band *= smoothstep(0.1, 0.4, hsN.z);
				float lightk = clamp(dot(hsN, LIGHT) * 0.5 + 0.65, 0.0, 1.0) * mix(0.25, 1.0, hsSh);
				vec3 ringc = lit.rgb * 1.6 + vec3(0.2, 0.21, 0.26);
				SPECULAR_LIGHT += LIGHT_COLOR / PI * ringc * band * lightk * 0.75 * _HsRing;
			}
		}

	} else {
		vec3 addCol = vec3(0.0);
		float addTmp;
		vec3 addLighting = calculateLighting(mainUv, addDotNL, 1.0, vec4(0.0), lit, LIGHT_COLOR, addCol, addTmp);
		vec3 specLight;
		// addLighting *= step(0, addDotNL); // darken if transparent. Because Unity's transparent material can't receive shadowAttenuation.
		float attenuation_multiplier = pow(length(vec3(ATTENUATION))/length(vec3(1.0)), 0.1); // Godot specific code to prevent clustering artifacts.
		diffuse_output = attenuation_multiplier * calculateAddLighting(mainUv, addDotNL, dot(viewNormal, VIEW), length(vec3(ATTENUATION))/length(vec3(1.0)), addLighting, addCol, specLight);
		SPECULAR_LIGHT += attenuation_multiplier * specLight;
	}
	if (_DebugMode >= 1.0) {
		if (_DebugMode == 2.0) { //MTOON_DEBUG_LITSHADERATE
			diffuse_output = lightIntensity * lighting;
		} else if (_DebugMode == 3.0) { // Add pass lighting
			diffuse_output = addLightIntensity;
		}
		SPECULAR_LIGHT = vec3(0.0);
	}
	DIFFUSE_LIGHT += diffuse_output / fragment_albedo_output;
}
