extends SceneTree
## ワールドのスクリーンショット検証。
## xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1280x720 -s tests/shot_world.gd -- heian [shot,shot...] [quality]
## 出力: <scratch>/shots/<era>_<n>.png

const OUT_DIR := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots"

var world: EraWorld
var cam: Camera3D
var shots: Array = []
var frame := 0
var shot_i := 0
var wait := 0
var era_id := "heian"
var only: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		era_id = args[0]
	if args.size() > 1 and args[1] != "all":
		for s in args[1].split(","):
			only.append(int(s))
	if args.size() > 2:
		EraWorld.quality = int(args[2])
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var db := HistoryDB.load_all()
	var era := db.get_era(era_id)
	if era.is_empty():
		push_error("unknown era " + era_id)
		quit(1)
		return
	EraWorld.debug_timing = true
	world = EraWorld.build(era)
	if world == null:
		quit(1)
		return
	root.add_child(world)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	cam.near = 0.1
	root.add_child(cam)
	cam.current = true
	_make_shots()
	_check_api()


func _check_api() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for key in ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]:
		var p := world.landmark_pos(key)
		var g := world.random_ground_point_near(p, 30.0, rng)
		print("  landmark %s pos=%s ground_pt=%s" % [key, p, g])
	print("  spawn=", world.player_spawn, " streets=", world.street_points().size())
	for k in ["horse", "car", "plane"]:
		print("  vehicles %s: %d" % [k, world.vehicle_spawns(k).size()])


func _look(from: Vector3, to: Vector3) -> Dictionary:
	return {"from": from, "to": to}


func _make_shots() -> void:
	var lm := world.landmarks
	var ang: float = lm["capital"]["angle"]
	var b := Basis(Vector3.UP, ang)
	var cap: Vector3 = lm["capital"]["pos"]
	# 0: 都の俯瞰
	shots.append(_look(cap + b * Vector3(75, 48, 115), cap + b * Vector3(0, 0, -18)))
	# 1: 都の通り（スポーン地点）
	var sp := world.player_spawn
	shots.append(_look(sp + Vector3(0, 1.7, 0), cap + Vector3(0, 6, 0)))
	# 2: 村の通り
	var vil: Vector3 = lm["village"]["pos"]
	var vp := vil + b * Vector3(10, 0, 30)
	vp.y = world.height_at(vp.x, vp.z) + 1.7
	shots.append(_look(vp, vil + Vector3(0, 3, 0)))
	# 3: 城
	var cas: Vector3 = lm["castle"]["pos"]
	shots.append(_look(cas + b * Vector3(48, 24, 72), cas + Vector3(0, 8, 0)))
	# 4: 港
	var port: Vector3 = lm["port"]["pos"]
	shots.append(_look(port + b * Vector3(-40, 16, -50), port + b * Vector3(0, 0, 45)))
	# 5: 寺社
	var tem: Vector3 = lm["temple"]["pos"]
	shots.append(_look(tem + b * Vector3(-30, 12, 50), tem + Vector3(0, 8, 0)))
	# 6: 戦場
	var bf: Vector3 = lm["battlefield"]["pos"]
	shots.append(_look(bf + b * Vector3(-25, 20, 75), bf + Vector3(0, 0, 0)))
	# 7: 全景
	shots.append(_look(b * Vector3(110, 210, 390), b * Vector3(0, 0, -40)))
	# 8: 山
	var mt: Vector3 = lm["mountain"]["pos"]
	shots.append(_look(mt + b * Vector3(40, 20, 60), mt + Vector3(0, 5, 0)))
	if not only.is_empty():
		var keep: Array = []
		for i in only:
			if i < shots.size():
				var s: Dictionary = shots[i]
				s["idx"] = i
				keep.append(s)
		shots = keep
	else:
		for i in shots.size():
			shots[i]["idx"] = i
	_apply_shot()


func _apply_shot() -> void:
	var s: Dictionary = shots[shot_i]
	var from: Vector3 = s["from"]
	var to: Vector3 = s["to"]
	from.y = maxf(from.y, world.height_at(from.x, from.z) + 1.5)
	cam.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
	wait = 26 if shot_i == 0 else 10


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		_check_collision()
	wait -= 1
	if wait > 0:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s_%d.png" % [OUT_DIR, era_id, shots[shot_i]["idx"]]
	if img:
		img.save_png(path)
	print("saved ", path, " fps=", Engine.get_frames_per_second())
	shot_i += 1
	if shot_i >= shots.size():
		print("draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" prims: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		return true
	_apply_shot()
	return false


func _check_collision() -> void:
	var space := world.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var max_err := 0.0
	for i in 40:
		var x := rng.randf_range(-550, 550)
		var z := rng.randf_range(-550, 550)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 500, z), Vector3(x, -100, z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("  ray miss at ", x, ",", z)
			continue
		if hit["collider"].name == "TerrainBody":
			max_err = maxf(max_err, absf(hit["position"].y - world.height_at(x, z)))
	print("  terrain collision max err: ", max_err)
