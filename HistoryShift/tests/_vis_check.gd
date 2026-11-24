extends Node
func _ready() -> void:
	var root := get_tree().root
	var cam := Camera3D.new()
	root.add_child.call_deferred(cam)
	cam.position = Vector3(0, 0, 5)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	skm.shader = load("res://shaders/anime_sky.gdshader")
	sky.sky_material = skm
	env.sky = sky
	var style := EraStyles.get_style("edo")
	env.adjustment_enabled = true
	var t0 := Time.get_ticks_msec()
	env.adjustment_color_correction = WorldAtmosphere.grade_lut(style, false)
	print("lut ms ", Time.get_ticks_msec() - t0)
	we.environment = env
	root.add_child.call_deferred(we)
	var l := DirectionalLight3D.new()
	root.add_child.call_deferred(l)
	var i := 0
	for key in ["plaster", "rooftile", "wood", "stonewall", "metal", "glass", "cloth", "emissive", "water"]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = WorldMaterials.get_mat(key)
		mi.position = Vector3(i - 4, 0, 0)
		root.add_child.call_deferred(mi)
		i += 1
	for sh in ["terrain", "grass", "foliage", "post_anime"]:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/%s.gdshader" % sh)
		mi.material_override = m
		root.add_child.call_deferred(mi)
	for sh in ["mtoon", "mtoon_outline", "mtoon_cull_off", "mtoon_cutout", "mtoon_trans", "mtoon_trans_zwrite"]:
		var mi := MeshInstance3D.new()
		mi.mesh = SphereMesh.new()
		var m := ShaderMaterial.new()
		m.shader = load("res://addons/Godot-MToon-Shader/%s.gdshader" % sh)
		mi.material_override = m
		root.add_child.call_deferred(mi)
	var c := 0
	while c < 4:
		await get_tree().process_frame
		c += 1
	print("shader check done")
	get_tree().quit()
