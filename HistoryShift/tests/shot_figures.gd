extends Node3D
## 歴史上の人物（Figures）の並び撮影。
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shot_figures.tscn
## 引数（-- の後）に人物名を並べると、その人物だけを撮る。SHOT_TAG で出力名の接頭辞、SHOT_OUT で出力先
## 環境変数 SHOT_PER=4 などで 1 枚あたりの人数、SHOT_CLOSE=0 で寄りの撮影を省く
const OUT_DEFAULT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"
const LINEUP := ["卑弥呼", "厩戸王", "紫式部", "平清盛", "織田信長", "羽柴秀吉", "徳川家康", "坂本龍馬", "西郷隆盛", "伊藤博文", "東條英機", "山本五十六"]
const SPACING := 0.95


func _ready() -> void:
	var out := OUT_DEFAULT
	if OS.get_environment("SHOT_OUT") != "":
		out = OS.get_environment("SHOT_OUT")
	var tag := OS.get_environment("SHOT_TAG")
	if tag == "":
		tag = "figures"
	var per := int(OS.get_environment("SHOT_PER")) if OS.get_environment("SHOT_PER") != "" else 6
	var close := OS.get_environment("SHOT_CLOSE") != "0"
	_stage()
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = LINEUP.duplicate()
	var font: Font = load("res://assets/fonts/NotoSerifJP-Bold.ttf")
	var xs: Array[float] = []
	var i := 0
	for nm: String in names:
		var x := (i % per - (mini(per, names.size()) - 1) * 0.5) * SPACING + (i / per) * 40.0
		xs.append(x)
		var n := Figures.build(nm, hash(nm), {"helmet": OS.get_environment("SHOT_HELMET") == "1"})
		if n == null:
			print("unknown figure: ", nm)
			i += 1
			continue
		add_child(n)
		n.position = Vector3(x, 0, 0)
		var ap := n.get_node_or_null("Anim") as AnimationPlayer
		if ap and ap.has_animation("Mocap_Stand"):
			ap.play("Mocap_Stand")
		var s := Figures.spec_for(nm)
		var lab := Label3D.new()
		lab.text = "%s\n%s" % [s.get("name", nm), s.get("title", "")]
		lab.font = font
		lab.font_size = 40
		lab.pixel_size = 0.0016
		lab.outline_size = 10
		lab.modulate = Color(1, 0.95, 0.75)
		lab.outline_modulate = Color(0.1, 0.08, 0.06)
		lab.width = 560
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.position = Vector3(x, 1.95, 0)
		add_child(lab)
		i += 1
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30
	for _f in 30:
		await get_tree().process_frame
	var groups := int(ceil(float(names.size()) / per))
	for g in groups:
		var cx := g * 40.0
		var cnt := mini(per, names.size() - g * per)
		var w := cnt * SPACING
		cam.position = Vector3(cx, 1.15, 1.2 + w * 1.05)
		cam.look_at(Vector3(cx, 0.95, 0))
		for _f in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "%s_%d_full.png" % [tag, g])
		cam.position = Vector3(cx + 0.3, 1.3, -(1.2 + w * 1.05))
		cam.look_at(Vector3(cx + 0.3, 1.0, 0))
		for _f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "%s_%d_back.png" % [tag, g])
		if close:
			# 3 人ずつ寄る
			var j := 0
			while j < cnt:
				var a := xs[g * per + j]
				var b := xs[g * per + mini(j + 2, cnt - 1)]
				var mx := (a + b) * 0.5
				cam.position = Vector3(mx, 1.4, 1.75)
				cam.look_at(Vector3(mx, 1.22, 0))
				for _f in 8:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out + "%s_%d_close%d.png" % [tag, g, j / 3])
				j += 3
	get_tree().quit()


func _stage() -> void:
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
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(200, 30)
	fl.mesh = pmesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.47, 0.4)
	fl.material_override = fm
	fl.position = Vector3(40, 0, 0)
	add_child(fl)
