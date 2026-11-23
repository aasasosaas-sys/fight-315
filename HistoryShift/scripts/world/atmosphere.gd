class_name WorldAtmosphere
extends RefCounted
## 空・太陽・霧・ポストエフェクト・光の柱。品質設定は EraWorld の static 変数を参照する。

static func build_environment(world: Node3D, style: Dictionary) -> Dictionary:
	var sky_key: String = style["sky"]
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	var hdr_path := "res://assets/polyhaven/hdri/sky_%s.hdr" % sky_key
	if ResourceLoader.exists(hdr_path):
		pano.panorama = load(hdr_path)
	pano.energy_multiplier = 1.0
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	var q: int = EraWorld.quality
	env.glow_enabled = EraWorld.glow_enabled
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.3)

	env.ssao_enabled = EraWorld.ssao_enabled and q >= 1
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = EraWorld.ssil_enabled and q >= 2
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8

	env.sdfgi_enabled = EraWorld.sdfgi_enabled and q >= 1
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 0.9
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_read_sky_light = true

	# 距離フォグ（空気遠近）
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = style["fog_color"]
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = float(style["fog_density"]) * 0.3
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.fog_height = 40.0
	env.fog_height_density = 0.0

	env.volumetric_fog_enabled = EraWorld.volumetric_enabled and q >= 2
	env.volumetric_fog_density = float(style["vol_fog"]) * 0.28
	env.volumetric_fog_albedo = style["vol_albedo"]
	env.volumetric_fog_emission = Color(0, 0, 0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.3

	env.adjustment_enabled = true
	env.adjustment_brightness = style["brightness"]
	env.adjustment_contrast = style["contrast"]
	env.adjustment_saturation = style["saturation"]

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = style["sun_color"]
	sun.light_energy = style["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 300.0 if q >= 2 else (200.0 if q == 1 else 120.0)
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = q >= 2
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.4
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	world.add_child(sun)
	var hs: Dictionary = EraStyles.HDRI_SUN[sky_key]
	set_sun_dir(sun, hs["az"], hs["elev"])
	return {"env": env, "sun": sun, "we": we, "sky_mat": pano}


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
