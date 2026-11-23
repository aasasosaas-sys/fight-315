extends Node3D
## 時代別アニメ髪（AnimeHair）の確認撮影。
## 既定: 全スタイルを適したモデルで撮影し、行=キャラ, 列=正面/斜め/横/後ろ/顔アップ の
## コンタクトシートと全身写真を書き出す。
## 引数: -- style:Model,style:Model ... で組み合わせを指定可能。
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"
const VRM := "res://assets/characters/vrm/cc0/"

const DEFAULT := [
	["chonmage", "HairSample_Male"], ["chonmage", "Sakurada_Fumiriya"],
	["chasen", "Sakurada_Fumiriya"], ["court_bun", "HairSample_Male"],
	["zangiri", "HairSample_Male"], ["buzz", "Sakurada_Fumiriya"],
	["suberakashi", "Sendagaya_Shino"], ["shimada", "HairSample_Female"],
	["sokuhatsu", "Sendagaya_Shibu"], ["bob", "Sendagaya_Shino"],
]

var cam: Camera3D
var chars: Array = []


func _ready() -> void:
	var combos: Array = DEFAULT
	var tag := "hair"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		combos = []
		for a in args[0].split(","):
			var p := a.split(":")
			combos.append([p[0], p[1]])
		if args.size() > 1:
			tag = args[1]
	_env()
	var x := 0.0
	for c in combos:
		var n: Node3D = (load(VRM + c[1] + ".vrm") as PackedScene).instantiate()
		var bnc := n.get_node_or_null("BoneNodeConstraintApplier")
		if bnc:
			n.remove_child(bnc)
			bnc.free()
		add_child(n)
		n.position = Vector3(x, 0, 0)
		x += 2.0
		AnimeHair.apply(n, c[0])
		var ap := AnimationPlayer.new()
		n.add_child(ap)
		ap.root_node = ap.get_path_to(n)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		sk.motion_scale = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
		ap.add_animation_library("", Retarget.library_for(sk, VRM + c[1] + ".vrm"))
		ap.play("Mocap_Stand")
		ap.seek(0.5, true)
		ap.pause()
		chars.append([n, sk, c[0] + " / " + c[1]])
	cam = Camera3D.new()
	add_child(cam)
	for i in 30: await get_tree().process_frame
	# contact sheet
	var tw := 400
	var th := 450
	var views := [0.0, 40.0, 90.0, 180.0, -25.0]
	var sheet := Image.create(tw * views.size(), th * chars.size(), false, Image.FORMAT_RGBA8)
	for ci in chars.size():
		var n: Node3D = chars[ci][0]
		var sk: Skeleton3D = chars[ci][1]
		var hp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin + Vector3(0, 0.07, 0)
		for vi in views.size():
			var ang := deg_to_rad(views[vi])
			var dist := 1.15 if vi < 4 else 0.7
			var look := hp if vi < 4 else hp + Vector3(0, -0.03, 0)
			cam.fov = 22
			cam.position = look + Vector3(sin(ang), 0.12 if vi == 4 else 0.08, cos(ang)) * dist
			cam.look_at(look)
			for f in 3: await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var w := img.get_width()
			var h := img.get_height()
			var crop := img.get_region(Rect2i(int(w / 2.0 - h * 0.4444), 0, int(h * 0.8889), h))
			crop.convert(Image.FORMAT_RGBA8)
			crop.resize(tw, th, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(crop, Rect2i(0, 0, tw, th), Vector2i(vi * tw, ci * th))
	sheet.save_png(OUT + tag + "_sheet.png")
	# full body row
	cam.fov = 30
	var mid := (chars.size() - 1) * 2.0 * 0.5
	cam.position = Vector3(mid, 1.0, 2.5 + chars.size() * 1.25)
	cam.look_at(Vector3(mid, 0.85, 0))
	for f in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + tag + "_full.png")
	cam.position = Vector3(mid + 2.0, 1.1, -(2.0 + chars.size() * 1.2))
	cam.look_at(Vector3(mid, 0.85, 0))
	for f in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + tag + "_back.png")
	get_tree().quit()


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
	pmesh.size = Vector2(40, 40)
	fl.mesh = pmesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.5, 0.38)
	fl.material_override = fm
	add_child(fl)
