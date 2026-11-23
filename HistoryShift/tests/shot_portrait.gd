extends Node3D
## 人物モデルの確認用: xvfb-run godot --path . --rendering-driver vulkan res://tests/shot_portrait.tscn -- <glbパス...>
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/polyhaven/hdri/sky_day.hdr")
	sky.sky_material = pm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pmesh := PlaneMesh.new(); pmesh.size = Vector2(20, 20)
	floor_mi.mesh = pmesh
	add_child(floor_mi)
	var paths := OS.get_cmdline_user_args()
	var x := -(paths.size() - 1) * 0.45
	for p in paths:
		var inst: Node3D = (load(p) as PackedScene).instantiate()
		add_child(inst)
		inst.position = Vector3(x, 0, 0)
		x += 0.9
		var sk = inst.find_children("*", "Skeleton3D", true, false)
		if sk.size() > 0:
			var names := []
			for i in mini(sk[0].get_bone_count(), 12): names.append(sk[0].get_bone_name(i))
			print(p, " bones=", sk[0].get_bone_count(), " ", names)
		var aabb := AABB()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge(mi.get_aabb())
		print("  aabb ", aabb)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.45, 2.6)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.fov = 40
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "portrait_full.png")
	cam.position = Vector3(paths.size() > 1 and -0.45 or 0.0, 1.62, 0.75)
	cam.look_at(Vector3(cam.position.x, 1.58, 0))
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "portrait_face.png")
	print("saved")
	get_tree().quit()
