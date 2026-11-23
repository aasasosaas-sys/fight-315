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
	env.ambient_light_sky_contribution = 0.8
	env.ambient_light_color = (style["sky_horizon"] as Color).lerp(Color.WHITE, 0.4)
	env.ambient_light_energy = style["ambient_energy"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# トーンマップ: 明るく鮮やかに（ハイライトだけ柔らかく）
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(style["exposure"]) * 1.05
	env.tonemap_white = 5.0

	var q: int = EraWorld.quality
	# ブルーム: 空・雲の縁・太陽・灯りがにじむ
	env.glow_enabled = EraWorld.glow_enabled
	env.glow_intensity = float(style["glow"])
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.3)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.4)
	env.set_glow_level(6, 0.2)

	# アニメ調: GI 系は使わない（影色はセル塗りで管理）。接地感のため弱い SSAO のみ
	env.ssao_enabled = EraWorld.ssao_enabled and q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 0.8
	env.ssao_power = 1.2
	env.ssao_detail = 0.3
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false

	# 空気遠近: 遠景が空色に溶ける（薄い霧）
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = style["aerial"]
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.15
	env.fog_density = float(style["aerial_density"]) * 0.5
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.fog_height = 60.0
	env.fog_height_density = 0.0
	env.volumetric_fog_enabled = false

	env.adjustment_enabled = true
	env.adjustment_brightness = style["brightness"]
	env.adjustment_contrast = float(style["contrast"]) * 1.02
	env.adjustment_saturation = maxf(float(style["saturation"]), 0.95) * 1.12

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
	sun.shadow_blur = 0.6
	sun.light_angular_distance = 0.3
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	world.add_child(sun)
	set_sun_dir(sun, style["sun_az"], style["sun_elev"])
	apply_toon_globals(style, 1.0)

	var post := make_post(style)
	world.add_child(post)
	return {"env": env, "sun": sun, "we": we, "sky_mat": sm, "post": post}


## セル塗りの共通パラメータ（影色など）をグローバルシェーダ変数へ。day: 0=夜 1=昼
static func apply_toon_globals(style: Dictionary, day: float) -> void:
	var sc: Color = style["shade_color"]
	var night_shade := Color(0.32, 0.36, 0.62)
	RenderingServer.global_shader_parameter_set("toon_shade_color", night_shade.lerp(sc, day))
	RenderingServer.global_shader_parameter_set("toon_params", Vector4(0.06, 0.05, 0.3, float(style["shade_strength"])))
	RenderingServer.global_shader_parameter_set("world_night", 1.0 - day)


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
