extends Node3D
## アニメ素体＋和装の確認撮影
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
	e.tonemap_exposure = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pmesh := PlaneMesh.new(); pmesh.size = Vector2(20, 20)
	fl.mesh = pmesh
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.45, 0.5, 0.38)
	fl.material_override = fm
	add_child(fl)
	var args := OS.get_cmdline_user_args()
	var specs: Array = [["HairSample_Male", "samurai"], ["HairSample_Male", "hakama"], ["HairSample_Male", "modern"]]
	if args.size() > 0:
		specs = []
		for a in args:
			specs.append(a.split(":"))
	var x := -(specs.size() - 1) * 0.4
	for s in specs:
		var n := AnimeChar.build(s[0], s[1], {}, s[2] if s.size() > 2 else "")
		add_child(n)
		n.position = Vector3(x, 0, 0)
		x += 0.8
		if OS.get_environment("NO_ANIM") == "":
			(n.get_node("Anim") as AnimationPlayer).play("Mocap_Stand")
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			print(s, " ", mi.name, " ", mi.get_aabb())
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30
	cam.position = Vector3(0, 1.0, 4.2)
	cam.look_at(Vector3(0, 0.85, 0))
	for i in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "wasou_full.png")
	cam.position = Vector3(-(specs.size() - 1) * 0.4, 1.3, 1.6)
	cam.look_at(Vector3(cam.position.x, 1.15, 0))
	for i in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "wasou_close.png")
	cam.position = Vector3(2.5, 1.1, 2.5)
	cam.look_at(Vector3(0, 0.85, 0))
	for i in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "wasou_side.png")
	cam.position = Vector3(-(specs.size() - 1) * 0.4, 1.2, -2.2)
	cam.look_at(Vector3(cam.position.x, 1.0, 0))
	for i in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "wasou_back.png")
	get_tree().quit()
