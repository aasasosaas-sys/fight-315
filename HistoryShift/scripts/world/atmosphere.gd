class_name WorldAtmosphere
extends RefCounted
## 空・太陽・霧・ポストエフェクト・光の柱。品質設定は EraWorld の static 変数を参照する。

static func build_environment(world: Node3D, style: Dictionary) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = WorldMaterials.shader("anime_sky")
	sm.set_shader_parameter("noise_tex", WorldMaterials.macro_noise())
	var sky_keys := {"zenith_color": "sky_zenith", "horizon_color": "sky_horizon", "haze_color": "sky_haze",
		"sunset_color": "sunset_color", "sunset_amount": "sunset_amount", "cloud_light": "cloud_light", "cloud_mid": "cloud_mid",
		"cloud_shade": "cloud_shade", "cloud_cover": "cloud_cover", "tower": "tower", "cirrus": "cirrus", "cloud_seed": "cloud_seed"}
	for k in sky_keys:
		sm.set_shader_parameter(k, style[sky_keys[k]])
	sm.set_shader_parameter("sun_color", (style["sun_color"] as Color).lerp(Color.WHITE, 0.3))
	sm.set_shader_parameter("ground_color", (style["grass_b"] as Color).lerp(style["sky_horizon"], 0.5))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	# 環境光: 空（青い影）＋少しの一様光
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 影の中は空の天頂寄りの青（地平の夕焼け色で影が濁らないように一様光を多めに）
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = (style["sky_zenith"] as Color).lerp(Color.WHITE, 0.55)
	env.ambient_light_energy = style["ambient_energy"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# トーンマップ: 明るく鮮やかに（ハイライトだけ柔らかく）。色調は時代ごとの LUT（_grade_lut）で
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(style["exposure"]) * 1.0
	env.tonemap_white = 6.0

	var q: int = EraWorld.quality
	# ブルーム: しきい値より明るい所（空の太陽まわり・雲の縁・灯り・水のきらめき）だけが柔らかくにじむ
	env.glow_enabled = EraWorld.glow_enabled
	env.glow_intensity = float(style["glow"]) * 0.75
	env.glow_strength = 1.1
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 1.8
	env.glow_hdr_luminance_cap = 10.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.15)
	env.set_glow_level(2, 0.4)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.7)
	env.set_glow_level(5, 0.5)
	env.set_glow_level(6, 0.25)

	# アニメ調: GI 系は使わない（影色はセル塗りで管理）。接地感のため柔らかい SSAO（影の中だけ効く）
	env.ssao_enabled = EraWorld.ssao_enabled and q >= 1
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.1
	env.ssao_power = 1.35
	env.ssao_detail = 0.25
	env.ssao_horizon = 0.08
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false

	# 空気遠近: 遠景が空色に溶ける（薄い霧）＋谷間・水辺にたまる低い霞（奥行きの層）
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = style["aerial"]
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.22
	env.fog_density = float(style["aerial_density"]) * 0.17
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.0
	env.fog_height = float(style.get("haze_height", 6.0))
	env.fog_height_density = float(style.get("haze_density", 0.004)) * 0.35
	env.volumetric_fog_enabled = false

	# 色調: Environment の調整は素通しにして、時代ごとのカラーグレーディング LUT（3D）で
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.adjustment_color_correction = grade_lut(style, false)

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = style["sun_color"]
	sun.light_energy = float(style["sun_energy"]) * 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0 if q >= 2 else (160.0 if q == 1 else 100.0)
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = q >= 2
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	# セル影: 境界は細く柔らかく（にじみすぎると「汚れ」に見える）
	sun.shadow_blur = 0.45
	sun.light_angular_distance = 0.25
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	world.add_child(sun)
	set_sun_dir(sun, style["sun_az"], style["sun_elev"])
	apply_toon_globals(style, 1.0)
	RenderingServer.global_shader_parameter_set("world_indoor", 0.0)

	var post := make_post(style)
	world.add_child(post)
	return {"env": env, "sun": sun, "we": we, "sky_mat": sm, "post": post}


## セル塗りの共通パラメータ（影色など）をグローバルシェーダ変数へ。day: 0=夜 1=昼
static var _night := 0.0


static func apply_toon_globals(style: Dictionary, day: float) -> void:
	var sc: Color = style["shade_color"]
	var night_shade := Color(0.32, 0.36, 0.62)
	RenderingServer.global_shader_parameter_set("toon_shade_color", night_shade.lerp(sc, day))
	RenderingServer.global_shader_parameter_set("toon_params", Vector4(0.06, 0.045, 0.34, float(style["shade_strength"])))
	RenderingServer.global_shader_parameter_set("world_night", 1.0 - day)
	_night = 1.0 - day
	RenderingServer.global_shader_parameter_set("world_sky_color", Color(0.12, 0.16, 0.3).lerp(style["sky_horizon"], day))
	RenderingServer.global_shader_parameter_set("world_sun_color", Color(0.6, 0.7, 1.0).lerp(style["sun_color"], day))


## 時刻に合わせた色調（夜は月夜の LUT・灯りが映えるブルーム・光芒なし）
static func apply_time_grade(nodes: Dictionary, style: Dictionary, day: float, elev: float) -> void:
	var env: Environment = nodes.get("env")
	if env == null:
		return
	env.adjustment_color_correction = grade_lut(style, day < 0.5)
	if env.has_meta("out_amb"):
		env.remove_meta("out_amb")
	env.glow_hdr_threshold = lerpf(0.75, 0.95, day)
	env.glow_intensity = float(style["glow"]) * lerpf(1.0, 0.75, day)
	env.fog_height_density = float(style.get("haze_density", 0.004)) * 0.35 * lerpf(1.6, 1.0, day)
	var post: MeshInstance3D = nodes.get("post")
	if post and post.material_override:
		var m := post.material_override as ShaderMaterial
		m.set_shader_parameter("ray_strength", float(style["rays"]) * clampf(day, 0.0, 1.0))
		m.set_shader_parameter("ridge_strength", lerpf(0.15, 0.55, day))
		m.set_shader_parameter("vignette", lerpf(0.32, 0.2, day))


## 屋内（k=1）: 空の環境光の代わりに、障子越しの柔らかい暖色の照り返し。露出を上げ、灯りのにじみを強く
static func set_indoor(nodes: Dictionary, style: Dictionary, k: float) -> void:
	var env: Environment = nodes.get("env")
	if env == null:
		return
	if not env.has_meta("out_amb"):
		env.set_meta("out_amb", [env.ambient_light_color, env.ambient_light_sky_contribution, env.ambient_light_energy,
			env.tonemap_exposure, env.ssao_intensity, env.glow_hdr_threshold])
	var o: Array = env.get_meta("out_amb")
	var night := _night
	var warm := Color(1.0, 0.86, 0.68).lerp(Color(0.55, 0.5, 0.6), night)
	env.ambient_light_color = (o[0] as Color).lerp(warm, k)
	env.ambient_light_sky_contribution = lerpf(o[1], 0.1, k)
	env.ambient_light_energy = lerpf(o[2], float(o[2]) * lerpf(1.5, 0.9, night), k)
	env.tonemap_exposure = lerpf(o[3], float(o[3]) * 1.04, k)
	# 屋内は環境光が主なので SSAO が効きすぎ、家具の後ろの壁が黒く櫛状に潰れる。半径・強さを絞る
	env.ssao_intensity = lerpf(o[4], 0.45, k)
	env.ssao_radius = lerpf(1.6, 0.45, k)
	env.glow_hdr_threshold = lerpf(o[5], 0.9, k)
	RenderingServer.global_shader_parameter_set("world_indoor", k)
	# 屋内では日の光が薄い壁を抜けて家具の影が壁に伸びる（法線バイアスが大きいため）。
	# 中にいる間は影の範囲を狭めて解像度を上げ、バイアスを小さくして外殻の影を正しく落とす
	var sun: DirectionalLight3D = nodes.get("sun")
	if sun:
		if not sun.has_meta("out_sh"):
			sun.set_meta("out_sh", [sun.shadow_normal_bias, sun.shadow_bias, sun.directional_shadow_max_distance])
		var so: Array = sun.get_meta("out_sh")
		var inside := k > 0.5
		sun.shadow_normal_bias = 0.2 if inside else float(so[0])
		sun.shadow_bias = 0.012 if inside else float(so[1])
		sun.directional_shadow_max_distance = minf(float(so[2]), 70.0) if inside else float(so[2])


# ---------------------------------------------------------------- カラーグレーディング（3D LUT）
static var _lut_cache := {}
const LUT_N := 32


## 時代の色調の LUT。入力・出力とも sRGB（トーンマップ後に Environment が引く）。
## 各テクセル i は (i+0.5)/N の色の変換結果（線形補間で正確に恒等になる）
static func grade_lut(style: Dictionary, night: bool) -> Texture3D:
	var g: Dictionary = (style.get("grade", {}) as Dictionary).duplicate()
	if night:
		g.merge(style.get("grade_night", {"contrast": 1.12, "sat": 0.78, "lift": Color(0.012, 0.02, 0.05),
			"gain": Color(0.92, 0.98, 1.1), "shadow": Vector3(-0.02, 0.0, 0.05), "high": Vector3(0.03, 0.01, -0.02),
			"green_sat": 0.7, "blue_sat": 1.05}), true)
	var key := str(g)
	if _lut_cache.has(key):
		return _lut_cache[key]
	var N := LUT_N
	var imgs: Array[Image] = []
	var gain: Color = g.get("gain", Color(1, 1, 1))
	var lift: Color = g.get("lift", Color(0, 0, 0))
	var con: float = g.get("contrast", 1.0)
	var pivot: float = g.get("pivot", 0.46)
	var sat: float = g.get("sat", 1.0)
	var vib: float = g.get("vibrance", 0.15)
	var gsat: float = g.get("green_sat", 0.85)
	var gshift: float = g.get("green_shift", 0.015)
	var bsat: float = g.get("blue_sat", 1.1)
	var wsat: float = g.get("warm_sat", 1.0)
	var sh_t: Vector3 = g.get("shadow", Vector3(-0.015, 0.0, 0.035))
	var hi_t: Vector3 = g.get("high", Vector3(0.02, 0.01, -0.015))
	var gamma: float = g.get("gamma", 1.0)
	for bz in N:
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for gy in N:
			for rx in N:
				var c := Vector3((rx + 0.5) / N, (gy + 0.5) / N, (bz + 0.5) / N)
				c = _grade_px(c, gain, lift, con, pivot, sat, vib, gsat, gshift, bsat, wsat, sh_t, hi_t, gamma)
				img.set_pixel(rx, gy, Color(c.x, c.y, c.z))
		imgs.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, N, N, N, false, imgs)
	_lut_cache[key] = tex
	return tex


static func _scurve(x: float, k: float, p: float) -> float:
	x = clampf(x, 0.0, 1.0)
	if x < p:
		return p * pow(x / p, k)
	return 1.0 - (1.0 - p) * pow((1.0 - x) / (1.0 - p), k)


static func _grade_px(c: Vector3, gain: Color, lift: Color, con: float, pivot: float, sat: float, vib: float,
		gsat: float, gshift: float, bsat: float, wsat: float, sh_t: Vector3, hi_t: Vector3, gamma: float) -> Vector3:
	# ホワイトバランス（ゲイン）
	c = Vector3(c.x * gain.r, c.y * gain.g, c.z * gain.b)
	# コントラスト（S 字。黒と白は潰さない）
	c = Vector3(_scurve(c.x, con, pivot), _scurve(c.y, con, pivot), _scurve(c.z, con, pivot))
	if gamma != 1.0:
		c = Vector3(pow(c.x, gamma), pow(c.y, gamma), pow(c.z, gamma))
	# スプリットトーン（影は寒色、明部は暖色）
	var l := c.x * 0.3 + c.y * 0.59 + c.z * 0.11
	var ws := 1.0 - smoothstep(0.05, 0.6, l)
	var wh := smoothstep(0.4, 0.95, l)
	c += sh_t * ws + hi_t * wh
	# 彩度（色相ごと）: 黄緑のネオン感を抑えて少し青緑へ、空の青を澄ませる
	var col := Color(clampf(c.x, 0, 1), clampf(c.y, 0, 1), clampf(c.z, 0, 1))
	var h := col.h
	var s := col.s
	var v := col.v
	var gw := smoothstep(0.12, 0.2, h) * (1.0 - smoothstep(0.36, 0.46, h))   # 黄緑〜緑
	var bw := smoothstep(0.5, 0.56, h) * (1.0 - smoothstep(0.7, 0.78, h))    # 空色〜青
	var rw := 1.0 - smoothstep(0.06, 0.12, h) + smoothstep(0.9, 0.97, h)     # 赤〜橙
	s *= sat * lerpf(1.0, gsat, gw) * lerpf(1.0, bsat, bw) * lerpf(1.0, wsat, rw)
	s += (1.0 - s) * s * vib
	h = fposmod(h + gshift * gw, 1.0)
	col = Color.from_hsv(h, clampf(s, 0.0, 1.0), v)
	# 黒の持ち上げ（色付きの締まった影）
	var out := Vector3(col.r, col.g, col.b)
	out = out + Vector3(lift.r, lift.g, lift.b) * (Vector3.ONE - out)
	return out.clamp(Vector3.ZERO, Vector3.ONE)


## 被写界深度（スクリーンショット・演出用）。focus は焦点の距離 m、0 で無効
static func set_dof(nodes: Dictionary, focus: float, near_blur := false) -> void:
	var we: WorldEnvironment = nodes.get("we")
	if we == null:
		return
	if focus <= 0.0:
		we.camera_attributes = null
		return
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = focus * 1.6 + 2.0
	ca.dof_blur_far_transition = focus * 3.0 + 6.0
	ca.dof_blur_near_enabled = near_blur
	ca.dof_blur_near_distance = maxf(focus * 0.4, 0.3)
	ca.dof_blur_near_transition = maxf(focus * 0.3, 0.2)
	ca.dof_blur_amount = 0.05
	we.camera_attributes = ca


## 全画面ポスト（輪郭線・光芒・周辺減光）
static func make_post(style: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "AnimePost"
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mi.mesh = qm
	mi.extra_cull_margin = 16384.0
	mi.ignore_occlusion_culling = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var m := ShaderMaterial.new()
	m.shader = WorldMaterials.shader("post_anime")
	m.render_priority = 127
	m.set_shader_parameter("line_strength", style["line"])
	m.set_shader_parameter("ray_strength", style["rays"])
	m.set_shader_parameter("ray_color", (style["sun_color"] as Color).lerp(style["sunset_color"], 0.3))
	m.set_shader_parameter("ridge_color", (style["sun_color"] as Color).lerp(Color(1, 0.96, 0.88), 0.4))
	m.set_shader_parameter("glare_strength", float(style.get("glare", 0.35)))
	m.set_shader_parameter("haze_color", style["aerial"])
	mi.material_override = m
	return mi


## 毎フレーム: 光芒の中心（太陽の画面位置）を更新
static func update_post(post: MeshInstance3D, sun: DirectionalLight3D, cam: Camera3D) -> void:
	if post == null or sun == null or cam == null:
		return
	var m := post.material_override as ShaderMaterial
	var to_sun := sun.global_transform.basis.z.normalized()
	var fwd := -cam.global_transform.basis.z
	var vis := 0.0
	if sun.visible and to_sun.dot(fwd) > 0.0 and to_sun.y > -0.05:
		var p := cam.global_position + to_sun * 1000.0
		var sp := cam.unproject_position(p)
		var vs := cam.get_viewport().get_visible_rect().size
		var uv := sp / vs
		m.set_shader_parameter("sun_uv", uv)
		var off := maxf(absf(uv.x - 0.5), absf(uv.y - 0.5))
		vis = (1.0 - smoothstep(0.5, 1.1, off)) * smoothstep(0.0, 0.35, to_sun.dot(fwd)) * smoothstep(-0.05, 0.1, to_sun.y)
	m.set_shader_parameter("sun_vis", vis)
	# 稜線のハイライト用: ビュー空間の太陽の向き
	m.set_shader_parameter("sun_dir_view", cam.global_transform.basis.inverse() * to_sun)


## az: atan2(x, z) 方位（度）。elev: 仰角（度）
static func set_sun_dir(sun: DirectionalLight3D, az: float, elev: float) -> void:
	var a := deg_to_rad(az)
	var e := deg_to_rad(elev)
	var to_sun := Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e)).normalized()
	var up := Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD
	sun.basis = Basis.looking_at(-to_sun, up)


static func make_beacon(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Beacon"
	root.position = pos
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 3.2
	cyl.height = 320.0
	cyl.radial_segments = 24
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	mi.position = Vector3(0, 160.0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = WorldMaterials.shader("beacon")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var inner := MeshInstance3D.new()
	var cyl2 := CylinderMesh.new()
	cyl2.top_radius = 0.7
	cyl2.bottom_radius = 1.1
	cyl2.height = 320.0
	cyl2.radial_segments = 12
	cyl2.rings = 1
	cyl2.cap_top = false
	cyl2.cap_bottom = false
	inner.mesh = cyl2
	inner.position = Vector3(0, 160.0, 0)
	var mat2 := ShaderMaterial.new()
	mat2.shader = WorldMaterials.shader("beacon")
	mat2.set_shader_parameter("intensity", 2.4)
	mat2.set_shader_parameter("color", Color(0.75, 1.0, 1.0))
	inner.material_override = mat2
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.9, 1.0)
	light.light_energy = 3.0
	light.omni_range = 18.0
	light.position = Vector3(0, 3.0, 0)
	light.shadow_enabled = false
	root.add_child(light)
	root.visible = false
	return root
