extends Node
## 実寸の船のスクリーンショット: 各船の外観・船内 2 か所・沈没の連続写真（早回し）。
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shot_ships.tscn [-- edo showa ...]
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"
const ERAS := ["asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
## 時代ごとの沈没シナリオ: [船, 方法]
const SINK := {"asuka_nara": ["kentoshisen", "plug"], "heian": ["sosen", "fire"], "kamakura_muromachi": ["ming_junk", "keg"],
	"sengoku": ["atakebune", "fire"], "edo": ["susquehanna", "magazine"], "meiji_taisho": ["mikasa", "magazine"], "showa": ["yamato", "torpedo"]}

var sess: Session
var p: Player
var tcam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "ship_" + name + ".png")
	print("saved %s  fps=%d draws=%d objects=%d prims=%d  mem=%.0fMB" % [name, int(Performance.get_monitor(Performance.TIME_FPS)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])


func _cam(pos: Vector3, at: Vector3, fov := 60.0) -> void:
	if tcam == null:
		tcam = Camera3D.new()
		tcam.far = 3000.0
		tcam.near = 0.05
		sess.add_child(tcam)
	tcam.fov = fov
	tcam.global_position = pos
	tcam.look_at(at, Vector3.UP)
	tcam.make_current()


func _run() -> void:
	var eras: Array = Array(OS.get_cmdline_user_args())
	if eras.is_empty():
		eras = ERAS
	Game.chaos_event.connect(func(k: String, id: String, info: Dictionary) -> void:
		print("  chaos_event: %s %s ship=%s cause=%s" % [k, id, info.get("ship", ""), info.get("cause", "")]))
	for e in eras:
		await _era(String(e))
	get_tree().quit()


func _era(era_id: String) -> void:
	var t0 := Time.get_ticks_msec()
	sess = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await _frames(3)
	Game.lock_mouse(false)
	p = sess.player
	p.god_mode = true
	var yard := ShipYard.current
	print("== %s  world %d ms  ships=%d" % [era_id, Time.get_ticks_msec() - t0, yard.ships.size() if yard else 0])
	if yard == null:
		sess.end()
		await _frames(5)
		return
	for pl in yard.placements:
		print("   placed %s inner=%s at %s" % [pl["id"], str(pl["inner"]), str((pl["xf"] as Transform3D).origin)])
	await _frames(20)
	# 港の全景
	var c := Vector3.ZERO
	for s in yard.ships:
		c += (s as Ship).xf_cur.origin
	c /= yard.ships.size()
	var lm: Vector3 = sess.world.landmark_pos("port")
	_cam(lm + (lm - c).normalized() * 40.0 + Vector3(0, 60, 0), c, 60.0)
	p.teleport(lm)
	await _frames(10)
	await _shot(era_id + "_harbour")
	for s in yard.ships:
		var sh := s as Ship
		await _exterior(sh)
		await _interiors(sh)
	var sk: Array = SINK.get(era_id, [])
	if sk.size() == 2:
		for s in yard.ships:
			if (s as Ship).sd.id == sk[0]:
				await _sink(s as Ship, String(sk[1]))
	sess.end()
	sess.queue_free()
	tcam = null
	await _frames(10)


func _exterior(sh: Ship) -> void:
	var sd := sh.sd
	var xf := sh.xf_cur
	# 斜め前（右舷側）から
	var d := maxf(sd.L * 0.75, 30.0)
	var pos := xf * Vector3(sd.B * 0.5 + d * 0.8, maxf(sd.top_m + d * 0.22, 6.0), -sd.L * 0.35)
	p.teleport(xf * Vector3(sd.B * 0.5 + 40.0, 0, 0) + Vector3(0, 0.5, 0))
	_cam(pos, xf * Vector3(0, sd.top_m * 0.6 + 2.0, 0), 55.0)
	await _frames(8)
	await _shot(sd.id + "_ext")
	# 甲板の上（乗船して上甲板から船首方向）
	var deck := xf * Vector3(0, sd.top_m + 1.7, sd.L * 0.38)
	p.teleport(xf * Vector3(sd.B * 0.25, sd.top_at(sd.L * 0.3) + 0.3, sd.L * 0.3))
	await _wait_interior(sh)
	_cam(deck + xf.basis * Vector3(sd.B * 0.2, 2.0, 0), xf * Vector3(0, sd.top_m + 3.0, -sd.L * 0.2), 65.0)
	await _frames(6)
	await _shot(sd.id + "_deck")


func _wait_interior(sh: Ship) -> void:
	for i in 240:
		await get_tree().process_frame
		if sh.int_ready:
			break
	await _frames(4)


## 船内を 2 か所（いちばん大きい囲われた部屋と、船体内の別の甲板の部屋）
func _interiors(sh: Ship) -> void:
	var sd := sh.sd
	var picks: Array = []
	var best: Dictionary = {}
	var ba := 0.0
	for r in sd.rooms:
		var rd: Dictionary = r
		var a := (float(rd["z1"]) - float(rd["z0"])) * (float(rd["x1"]) - float(rd["x0"]))
		if bool(rd["enclosed"]) and a > ba and String(rd["region"]) != "top":
			ba = a
			best = rd
	if not best.is_empty():
		picks.append(best)
	for r in sd.rooms:
		var rd: Dictionary = r
		if rd != best and String(rd["region"]) == "hull" and float(rd["y"]) < sd.top_m - 1.0:
			picks.append(rd)
			break
	if picks.size() < 2:
		for r in sd.rooms:
			if not (r in picks):
				picks.append(r)
			if picks.size() >= 2:
				break
	var k := 0
	for r in picks:
		var rd: Dictionary = r
		var xf := sh.xf_cur
		var cz := (float(rd["z0"]) + float(rd["z1"])) * 0.5
		var cx := (float(rd["x0"]) + float(rd["x1"])) * 0.5
		var y := float(rd["y"])
		p.teleport(xf * Vector3(cx, y + 0.3, cz))
		await _wait_interior(sh)
		# 部屋の角から反対の角へ
		var h := minf(float(rd.get("h", 2.5)), 3.0)
		var along_z := float(rd["z1"]) - float(rd["z0"]) >= float(rd["x1"]) - float(rd["x0"])
		var from := Vector3(cx, y + minf(1.9, h - 0.35), float(rd["z1"]) - 0.35) if along_z else Vector3(float(rd["x1"]) - 0.35, y + minf(1.9, h - 0.35), cz)
		var to := Vector3(cx, y + 0.9, float(rd["z0"])) if along_z else Vector3(float(rd["x0"]), y + 0.9, cz)
		p.teleport(xf * Vector3(cx, y + 0.3, float(rd["z0"]) + 0.6))
		_cam(sh.xf_cur * from, sh.xf_cur * to, 75.0)
		await _frames(6)
		k += 1
		print("   room %s: %s y=%.1f %s enclosed=%s" % [sd.id, String(rd["name"]), y, String(rd["region"]), str(rd["enclosed"])])
		await _shot("%s_int%d" % [sd.id, k])


func _sink(sh: Ship, how: String) -> void:
	var sd := sh.sd
	print("   sinking %s by %s" % [sd.id, how])
	p.teleport(sh.xf_cur * Vector3(0, sd.top_m + 0.3, 0))
	await _wait_interior(sh)
	match how:
		"plug", "valves":
			for i in sh.flood.valve_open.size():
				sh.flood.set_valve(i, true)
			sh.cause = "player"
		"fire":
			sh.flood.ignite_at(0.0, 0.8)
			sh.flood.ignite_at(sd.L * 0.25, 0.6)
			sh.cause = "player"
		"keg":
			var pp := sh.xf_cur * Vector3(0, sd.keel_at(0.0) + 1.0, 0.0)
			Effects.explosion(get_tree(), pp, 13.0, 900.0, 0, 0.6)
		"magazine":
			var m: Dictionary = sh.flood.mag[sh.flood.mag.size() - 1]
			var cp: Dictionary = sd.comps[int((m["comps"] as Array)[0])]
			var pp := sh.xf_cur * Vector3(0, sd.keel_at(float(cp["cz"])) + 1.5, float(cp["cz"]))
			Effects.explosion(get_tree(), pp, 13.0, 900.0, 0, 0.6)
		"torpedo":
			# 大和: 左舷に魚雷が集中（爆薬 3,000 相当 ×6）→ 左へ傾き転覆
			for k in 6:
				var z := sd.z_of(sd.L * (0.3 + 0.08 * k))
				var pp := sh.xf_cur * Vector3(-sd.half_beam(z, -4.0) - 0.5, -4.0, z)
				sh.on_blast(pp, 10.0, 6000.0, 0, 0.3)
			Effects.explosion(get_tree(), sh.xf_cur * Vector3(-sd.B * 0.5, 0.5, 0), 12.0, 300.0, 0, 0.2)
	# 遠くから早回しで撮る
	p.teleport(sh.xf_cur * Vector3(sd.B * 0.5 + 60.0, 0.5, 0))
	var view := sh.xf_cur * Vector3(sd.B * 0.5 + maxf(sd.L * 0.9, 45.0), maxf(sd.L * 0.15, 8.0), -sd.L * 0.2)
	var shots := 0
	var t := 0.0
	var next_shot := 0.0
	var dt := 0.1
	while t < 4000.0 and shots < 6:
		for i in 20:
			sh._physics_process(dt)
			t += dt
		await get_tree().process_frame
		var tgt := sh.xf_cur.origin + Vector3(0, sd.top_m * 0.5, 0)
		_cam(view, Vector3(tgt.x, maxf(tgt.y, -2.0), tgt.z), 55.0)
		var interesting := sh.phase != "afloat" or sh.flood.flood_ratio() > 0.15 * (shots + 1) or absf(sh.heel) > 0.08 * (shots + 1) or sh.flood.burning() > shots
		if (t >= next_shot and interesting) or (sh.phase == "wreck"):
			await _frames(2)
			await _shot("%s_sink%d" % [sd.id, shots])
			print("     t=%.0fs %s flood=%d%% heel=%.0f trim=%.1f fire=%d" % [t, sh.phase, int(sh.flood.flood_ratio() * 100.0), rad_to_deg(sh.heel), rad_to_deg(sh.trim), sh.flood.burning()])
			shots += 1
			next_shot = t + 20.0
			if sh.phase == "wreck":
				break
