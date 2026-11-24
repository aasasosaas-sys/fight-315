extends Node
## 時代の中の年の比較写真（同じ場所を年ごとに）。
## xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1280x720 res://tests/shot_timeline.tscn -- edo 1615,1657,1853
## 出力: <scratch>/shots/timeline_<era>_<year>_<view>.png（view: capital = 江戸城と城下、port = 港）

const OUT_DIR := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots"

var era_id := "edo"
var years: Array = [1615, 1853]
var db: HistoryDB


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		era_id = args[0]
	if args.size() > 1:
		years = Array(args[1].split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	db = HistoryDB.load_all()
	_run.call_deferred()


func _run() -> void:
	var era := db.get_era(era_id)
	for y in years:
		var w := EraWorld.build(era, int(y), {})
		get_tree().root.add_child(w)
		w.set_time_of_day(10.5)
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.far = 4000.0
		get_tree().root.add_child(cam)
		cam.current = true
		var lm: Dictionary = w.landmarks
		var b := Basis(Vector3.UP, float(lm["capital"]["angle"]))
		var cap: Vector3 = lm["capital"]["pos"]
		var port: Vector3 = lm["port"]["pos"]
		var views := {
			"capital": [cap + b * Vector3(62, 40, 70), cap + b * Vector3(0, 8, -30)],
			"port": [port + b * Vector3(-40, 30, -70), port + b * Vector3(0, 0, 90)],
		}
		for i in 3:
			await get_tree().process_frame
		for id in w.destruction.units:
			var u = w.destruction.units[id]
			if u.kind == "castle_keep":
				print("keep id=%d destroyed=%s hide=%d px=%s same_tex=%s stats=%s" % [id, u.destroyed, u.hide_bits, w.destruction._img.get_pixel(id % 256, (id / 256) * 2), RenderingServer.global_shader_parameter_get("destruct_tex") == w.destruction._tex, w.timeline_stats])
		for vn in views:
			cam.look_at_from_position(views[vn][0], views[vn][1])
			for i in 50:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := OUT_DIR.path_join("timeline_%s_%d_%s.png" % [era_id, int(y), vn])
			img.save_png(path)
			print("saved ", path)
		cam.queue_free()
		w.queue_free()
		for i in 4:
			await get_tree().process_frame
	get_tree().quit(0)
