extends Node3D
## AnimeFace（顔の個性・年齢）の確認撮影。
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shot_faces.tscn
## 書き出し: faces_full.png（全身 12x2）, faces_close.png（顔 8x3）, faces_34.png（顔 斜め 8x3）
## 環境変数: SHOT_OUT（出力先, 末尾 /）, SHOT_TAG（接頭辞, 既定 faces）, NO_FACE=1（AnimeFace なしで比較）,
##           FACE_SEED（種のずらし）, FACE_ONLY="0,3,5"（番号を絞る）
const OUT_DEFAULT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

## [素体, 服装, 髪型, 年齢, 明治以降]
const CAST := [
	["HairSample_Male", "samurai", "chonmage", "adult", false],
	["Sakurada_Fumiriya", "hakama", "chonmage", "elder", false],
	["Sendagaya_Shibu", "hakama", "zangiri", "young", true],
	["HairSample_Male", "hakama", "chasen", "adult", false],
	["Sakurada_Fumiriya", "samurai", "chasen", "adult", false],
	["HairSample_Male", "hakama", "buzz", "child", false],
	["Sendagaya_Shibu", "samurai", "chonmage", "elder", false],
	["HairSample_Male", "hakama", "zangiri", "elder", true],
	["Sakurada_Fumiriya", "hakama", "zangiri", "young", true],
	["Sendagaya_Shibu", "hakama", "buzz", "adult", true],
	["HairSample_Male", "samurai", "chonmage", "young", false],
	["Sakurada_Fumiriya", "hakama", "court_bun", "elder", false],
	["HairSample_Female", "kimono", "shimada", "young", false],
	["Sendagaya_Shino", "kimono", "shimada", "adult", false],
	["HairSample_Female", "kimono", "sokuhatsu", "adult", true],
	["Sendagaya_Shino", "kimono", "bob", "child", true],
	["HairSample_Female", "kimono", "bob", "child", false],
	["Sendagaya_Shino", "kimono", "suberakashi", "young", false],
	["HairSample_Female", "kimono", "shimada", "elder", false],
	["Sendagaya_Shino", "kimono", "sokuhatsu", "elder", true],
	["HairSample_Female", "hakama", "sokuhatsu", "young", true],
	["Sendagaya_Shino", "kimono", "shimada", "young", false],
	["Sakurada_Fumiriya", "hakama", "chonmage", "child", false],
	["Sendagaya_Shibu", "hakama", "zangiri", "adult", true],
]
const SPACING := 1.4

var OUT := OUT_DEFAULT
var cam: Camera3D
var chars: Array = []


func _ready() -> void:
	if OS.get_environment("SHOT_OUT") != "":
		OUT = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(OUT)
	var tag := OS.get_environment("SHOT_TAG")
	if tag == "":
		tag = "faces"
	var no_face := OS.get_environment("NO_FACE") != ""
	var seed_off := int(OS.get_environment("FACE_SEED")) if OS.get_environment("FACE_SEED") != "" else 0
	var only: Array = []
	if OS.get_environment("FACE_ONLY") != "":
		for s in OS.get_environment("FACE_ONLY").split(","):
			only.append(int(s))
	_env()
	var x := 0.0
	var t0 := Time.get_ticks_msec()
	for i in CAST.size():
		if only.size() > 0 and not i in only:
			continue
		var c: Array = CAST[i]
		var female: bool = String(c[0]) in AnimeFace.FEMALE_BASES
		var n := AnimeChar.build(String(c[0]), String(c[1]), {}, String(c[2]))
		add_child(n)
		n.position = Vector3(x, 0, 0)
		x += SPACING
		var p := {}
		if not no_face:
			var t1 := Time.get_ticks_msec()
			p = AnimeFace.apply(n, 1000 + i * 37 + seed_off, {"age": String(c[3]), "female": female, "modern": bool(c[4])})
			print("[%d] %s %s %s %s  (%d ms)" % [i, c[0], c[1], c[2], c[3], Time.get_ticks_msec() - t1])
			var keys := p.keys()
			keys.sort()
			var line := ""
			for k in keys:
				if String(k).begins_with("_"):
					continue
				line += "%s=%s " % [k, p[k]]
			print("     ", line)
		var ap := n.get_node_or_null("Anim") as AnimationPlayer
		if ap and ap.has_animation("Mocap_Stand"):
			ap.play("Mocap_Stand")
			ap.seek(0.5, true)
			ap.pause()
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		chars.append([n, sk, i])
	print("built %d characters in %d ms" % [chars.size(), Time.get_ticks_msec() - t0])
	cam = Camera3D.new()
	add_child(cam)
	for f in 20:
		await get_tree().process_frame
	var cols := 12 if chars.size() > 12 else chars.size()
	var rows := int(ceil(chars.size() / float(cols)))
	# ---- full body tiles
	var tw := 200
	var th := 450
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.22))
	cam.fov = 30
	for ci in chars.size():
		var n: Node3D = chars[ci][0]
		cam.position = n.position + Vector3(0, 0.88, 3.6)
		cam.look_at(n.position + Vector3(0, 0.8, 0))
		for f in 3:
			await get_tree().process_frame
		sheet.blit_rect(_crop(tw, th), Rect2i(0, 0, tw, th), Vector2i((ci % cols) * tw, (ci / cols) * th))
	sheet.save_png(OUT + tag + "_full.png")
	# ---- face close-ups (front and 3/4)
	var fc := 8 if chars.size() > 8 else chars.size()
	var fr := int(ceil(chars.size() / float(fc)))
	var fs := 300
	for view in ["close", "34"]:
		var fsheet := Image.create(fs * fc, fs * fr, false, Image.FORMAT_RGBA8)
		fsheet.fill(Color(0.2, 0.2, 0.22))
		cam.fov = 20
		for ci in chars.size():
			var sk: Skeleton3D = chars[ci][1]
			var hb := sk.find_bone("Head")
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(hb).origin
			var hs: float = sk.global_transform.basis.get_scale().x
			var look := hp + Vector3(0, 0.065 * hs, 0)
			var dist := 0.62 * maxf(hs, 0.8) * (1.15 if String(CAST[chars[ci][2]][3]) == "child" else 1.0)
			var ang := 0.0 if view == "close" else deg_to_rad(35.0)
			cam.position = look + Vector3(sin(ang) * dist, 0.02, cos(ang) * dist)
			cam.look_at(look)
			for f in 3:
				await get_tree().process_frame
			fsheet.blit_rect(_crop(fs, fs), Rect2i(0, 0, fs, fs), Vector2i((ci % fc) * fs, (ci / fc) * fs))
		fsheet.save_png(OUT + tag + "_" + view + ".png")
	# ---- crowd overview
	cam.fov = 28
	var mid := (chars.size() - 1) * SPACING * 0.5
	cam.position = Vector3(mid, 1.4, 6.0 + chars.size() * 0.55)
	cam.look_at(Vector3(mid, 0.8, 0))
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + tag + "_crowd.png")
	print("saved ", OUT + tag + "_*.png")
	get_tree().quit()


func _crop(tw: int, th: int) -> Image:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var cw := int(h * float(tw) / th)
	var crop := img.get_region(Rect2i(int((w - cw) / 2.0), 0, cw, h))
	crop.convert(Image.FORMAT_RGBA8)
	crop.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	return crop


func _env() -> void:
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
	e.ambient_light_energy = 0.6
	e.tonemap_exposure = 0.85
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(80, 40)
	fl.mesh = pmesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.5, 0.38)
	fl.material_override = fm
	fl.position = Vector3(16, 0, 0)
	add_child(fl)
