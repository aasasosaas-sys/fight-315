extends Node3D
## アニメ調（VRM）人物の確認撮影
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
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	e.ambient_light_energy = 0.6
	e.tonemap_exposure = 0.85
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pmesh := PlaneMesh.new(); pmesh.size = Vector2(20, 20)
	fl.mesh = pmesh
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.45, 0.5, 0.38)
	fl.material_override = fm
	add_child(fl)
	var specs: Array = []
	for f in DirAccess.get_files_at("res://assets/characters/vrm/cc0"):
		if f.ends_with(".vrm"):
			specs.append(["res://assets/characters/vrm/cc0/" + f, false])
	var x := -(specs.size() - 1) * 0.35
	for s in specs:
		var n: Node3D = (load(s[0]) as PackedScene).instantiate()
		var sec := n.get_node_or_null("secondary")
		if sec:
			var keep: Array = []
			for sb in sec.spring_bones:
				if sb and not "Tops" in ",".join(sb.joint_nodes):
					keep.append(sb)
			sec.spring_bones.assign(keep)
		var bnc := n.get_node_or_null("BoneNodeConstraintApplier")
		if bnc:
			n.remove_child(bnc)
			bnc.free()
		add_child(n)
		n.position = Vector3(x, 0, 0)
		x += 0.7
		print(specs.find(s), " ", s[0].get_file())
		if s[1]:
			_japanese(n)
		var ap := AnimationPlayer.new()
		n.add_child(ap)
		ap.root_node = ap.get_path_to(n)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		sk.motion_scale = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
		ap.add_animation_library("", Retarget.library_for(sk, s[0]))
		ap.play("Mocap_Stand")
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35
	cam.position = Vector3(0, 1.0, 6.5)
	cam.look_at(Vector3(0, 0.85, 0))
	for i in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "vrm_full.png")
	cam.position = Vector3(0, 1.36, 3.6)
	cam.fov = 18
	cam.look_at(Vector3(0, 1.36, 0))
	for i in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "vrm_face.png")
	get_tree().quit()


## 黒髪・こげ茶の瞳に
func _japanese(n: Node) -> void:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if not (m is ShaderMaterial):
				continue
			var nm := m.resource_name.to_lower()
			var c := Color(0, 0, 0, 0)
			if "hair" in nm:
				c = Color(0.16, 0.14, 0.16)
			elif "iris" in nm or nm == "eye":
				c = Color(0.35, 0.22, 0.16)
			if c.a > 0:
				var mm := (m as ShaderMaterial).duplicate() as ShaderMaterial
				mm.set_shader_parameter("_Color", c)
				mm.set_shader_parameter("_ShadeColor", c * 0.6)
				mi.set_surface_override_material(si, mm)
