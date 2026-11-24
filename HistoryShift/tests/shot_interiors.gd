extends Node
## 建物の内装のスクリーンショット＆計測:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shot_interiors.tscn [-- edo sengoku ...]
## 各時代の代表的な建物に入り、屋内カメラ（テスト用）と三人称カメラ（ゲームのリグ）で撮る。
## 生成時間・描画コール・頂点数、屋内で倒壊したときの押し出し（即死しない）、屋内の火災も確かめる。
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

## 時代ごとに撮る内装キット（[type, landmark or "", floor index]）
const PLAN := {
	"jomon_kofun": [["pit", "", 0], ["takayuka", "", 0], ["raised_hall", "capital", 0]],
	"asuka_nara": [["daigokuden", "capital", 0], ["temple", "temple", 0], ["pagoda", "temple", 0], ["storehouse", "port", 0]],
	"heian": [["shinden", "capital", 0], ["shrine", "village", 0], ["farmhouse", "village", 0]],
	"kamakura_muromachi": [["shoin", "temple", 0], ["kinkaku", "temple", 0], ["minka", "", 0], ["shinden", "capital", 0]],
	"sengoku": [["temple", "temple", 0], ["goten", "capital", 0], ["castle", "castle", 0], ["castle", "castle", 4], ["machiya", "capital", 0], ["kura", "port", 0]],
	"edo": [["machiya", "capital", 0], ["machiya", "capital", 1], ["nagaya", "", 0], ["chaya", "battlefield", 0], ["castle", "capital", 2], ["goten", "capital", 0], ["shoin", "castle", 0], ["yagura", "capital", 0]],
	"meiji_taisho": [["yokan", "battlefield", 0], ["station", "port", 0], ["factory", "port", 0], ["office", "capital", 0], ["office", "capital", 1], ["school", "village", 0], ["farmhouse", "village", 0]],
	"showa": [["diet", "capital", 0], ["showa_shop", "village", 0], ["showa_shop", "village", 1], ["danchi", "village", 0], ["office_showa", "capital", 0], ["bank", "castle", 0], ["showa_house", "village", 0], ["hangar", "battlefield", 0]],
}

var sess: Session
var p: Player
var tcam: Camera3D
var report: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "int_" + name + ".png")
	print("saved %s  draws=%d objects=%d prims=%d fps=%d" % [name, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.TIME_FPS))])


func _run() -> void:
	var eras: Array = []
	for a in OS.get_cmdline_user_args():
		eras.append(a)
	if eras.is_empty():
		eras = PLAN.keys()
	for era_id in eras:
		await _era(String(era_id))
	print("==== interior report")
	for l in report:
		print(l)
	get_tree().quit()


func _pick(w, type: String, lm: String, need_floor: int) -> int:
	var ids: Array = w.find_interiors(type, lm)
	if ids.is_empty() and lm != "":
		ids = w.find_interiors(type, "")
	var best := -1
	var bd := INF
	var c: Vector3 = w.landmark_pos(lm if lm != "" else "capital")
	for id in ids:
		var info: Dictionary = w.get_interior_info(id)
		if int(info["floors"]) <= need_floor:
			continue
		var d: Dictionary = w.interiors.defs[id]
		var dist := (d["_c"] as Vector3).distance_to(c)
		if dist < bd:
			bd = dist
			best = id
	return best


func _era(era_id: String) -> void:
	sess = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await _frames(2)
	Game.lock_mouse(false)
	p = sess.player
	p.god_mode = true
	var w = sess.world
	w.set_time_of_day(15.5)
	await _frames(8)
	var wi: WorldInteriors = w.interiors
	print("[%s] enterable=%d build=%dms" % [era_id, wi.ids.size(), w.build_ms])
	# 種類ごとの数
	var by := {}
	for id in wi.ids:
		var t: String = wi.defs[id]["type"]
		by[t] = int(by.get(t, 0)) + 1
	report.append("%s: %d enterable %s" % [era_id, wi.ids.size(), str(by)])
	var plan: Array = PLAN.get(era_id, [])
	var n := 0
	for item in plan:
		var id := _pick(w, item[0], item[1], int(item[2]))
		if id < 0:
			print("  (no %s)" % str(item))
			continue
		await _shoot(w, id, int(item[2]), "%s_%s_f%d" % [era_id, item[0], int(item[2])], n == 0)
		n += 1
	# 屋内での倒壊と火災（江戸・戦国の町家で）
	if era_id in ["edo", "sengoku"]:
		await _destroy_inside(w, era_id)
	print("  " + wi.debug_summary())
	report.append("  " + wi.debug_summary())
	tcam = null
	sess.end()
	await _frames(5)


func _shoot(w, id: int, fi: int, name: String, rig_shot: bool) -> void:
	var wi: WorldInteriors = w.interiors
	var d: Dictionary = wi.defs[id]
	var xf: Transform3D = d["xf"]
	var f: Dictionary = d["floors"][fi]
	var r: Rect2 = f["rect"]
	var y: float = f["y"]
	var dd: Dictionary = d["doors"][0]
	# 外から入口を見る（最初の 1 棟だけ）
	if rig_shot:
		var outp: Vector3 = xf * (dd["out"] as Vector3)
		var dp: Vector3 = xf * (dd["p"] as Vector3)
		outp.y = maxf(outp.y, float(w.height_at(outp.x, outp.z)))
		p.teleport(outp + (outp - dp).normalized() * 4.0)
		await _frames(2)
		_tcam(outp + (outp - dp).normalized() * 3.0 + Vector3(0, 1.7, 0), dp + Vector3(0, 1.2, 0))
		await _wait(0.4)
		await _shot(name + "_door")
	var t0 := Time.get_ticks_usec()
	var node: Node3D = w.ensure_interior(id, true)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var verts := int(node.get_meta("tris", 0)) if node else 0
	# 部屋の中へ: プレイヤーは部屋の中央付近、カメラは入口側の角から奥を見る
	var c := r.get_center()
	var back := Vector3(c.x, y + 1.0, r.position.y + r.size.y * 0.25)
	var cam_l := Vector3(c.x + r.size.x * 0.3, y + 1.55, r.end.y - 0.45)
	if fi > 0:
		cam_l = Vector3(r.end.x - 0.5, y + 1.5, r.end.y - 0.5)
		back = Vector3(r.position.x + r.size.x * 0.3, y + 0.8, r.position.y + r.size.y * 0.3)
	if d.get("floors")[fi].has("round"):
		cam_l = Vector3(0.6, y + 1.5, float(f["round"]) - 0.4)
		back = Vector3(-0.3, y + 0.5, -0.8)
	var pl := xf * Vector3(c.x - r.size.x * 0.15, y + 0.1, c.y + r.size.y * 0.1)
	p.teleport(pl)
	await _frames(3)
	_tcam(xf * cam_l, xf * back)
	await _wait(0.5)
	var inside := wi.player_inside == id
	await _shot(name)
	# ゲームのカメラ（三人称リグ）でも
	if rig_shot or fi > 0 or String(d["type"]) in ["pit", "nagaya", "machiya", "castle", "danchi"]:
		var cam: CameraRig = sess.cam
		cam.make_current()
		cam.yaw = xf.basis.get_euler().y + PI * 0.15
		cam.pitch = -0.25
		cam.snap()
		await _wait(0.6)
		await _shot(name + "_rig")
	var nspots: int = w.get_interior_points(id).size()
	var line := "  %s: id=%d build=%.1fms verts=%d spots=%d inside=%s lights=%d draws=%d" % [name, id, ms, verts, nspots, inside,
		int(wi.stats["lights"]), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	print(line)
	report.append(line)
	w.release_interior(id)


func _tcam(pos: Vector3, look: Vector3) -> void:
	if tcam == null or not is_instance_valid(tcam):
		tcam = Camera3D.new()
		tcam.fov = 72.0
		tcam.near = 0.05
		tcam.far = 3000.0
		sess.add_child(tcam)
	tcam.global_position = pos
	tcam.look_at(look, Vector3.UP)
	tcam.make_current()


## 中にいる時に燃える → 屋内に炎。倒壊 → 外へ押し出されてダメージ（即死しない）
func _destroy_inside(w, era_id: String) -> void:
	var wi: WorldInteriors = w.interiors
	var id := _pick(w, "machiya", "capital", 0)
	if id < 0:
		return
	var u: Destructible = Destruction.current.units.get(id)
	if u == null:
		return
	var d: Dictionary = wi.defs[id]
	var xf: Transform3D = d["xf"]
	var r: Rect2 = d["floors"][0]["rect"]
	w.ensure_interior(id, false)
	p.god_mode = false
	p.heal_full()
	p.teleport(xf * Vector3(r.get_center().x, float(d["floors"][0]["y"]) + 0.1, r.get_center().y))
	await _wait(0.4)
	print("  inside before fire: %s" % (wi.player_inside == id))
	u.last_cause = "player"
	u.ignite()
	await _wait(1.2)
	_tcam(xf * Vector3(r.end.x - 0.4, float(d["floors"][0]["y"]) + 1.6, r.end.y - 0.4), xf * Vector3(r.get_center().x, float(d["floors"][0]["y"]) + 0.8, r.position.y + 1.0))
	await _wait(1.0)
	await _shot("%s_fire_inside" % era_id)
	var hp0 := p.hp
	u.damage(u.hp + 10.0, u.center(), Vector3.FORWARD, 0.0, "player")
	await _wait(0.3)
	var still_in := wi.inside_at(p.global_position) == id
	var line := "  collapse-while-inside: hp %.0f -> %.0f dead=%s outside=%s blocked=%s" % [hp0, p.hp, p.dead, not still_in, wi.blocked.get(id, "")]
	print(line)
	report.append(line)
	await _wait(1.5)
	var cp := p.global_position
	_tcam(cp + Vector3(4, 3, 4), cp + Vector3(0, 1, 0))
	await _shot("%s_collapse_pushed" % era_id)
	p.god_mode = true
