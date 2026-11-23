extends Node
## 船のヘッドレス検査: 全船の外装・船内を組み立て、自沈（注水弁）・爆薬・弾火薬庫・転覆のシナリオを早回しで計算する。
## godot --headless --path . res://tests/test_ships.tscn [-- mikasa yamato ...]

const IDS := ["kentoshisen", "sosen", "ming_junk", "atakebune", "sekibune", "nanban_nau", "shuinsen", "susquehanna", "kanrin_maru", "mikasa", "hikawa_maru", "akagi", "kaga", "yamato"]
var fails := 0
var events: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Game.chaos_event.connect(func(k: String, id: String, info: Dictionary) -> void:
		events.append([k, id, info.get("ship", ""), info.get("cause", "")]))
	var ids: Array = IDS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		ids = Array(args)
	for sid in ids:
		await _ship(String(sid))
	print("chaos events: ", events)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _ship(sid: String) -> void:
	var t0 := Time.get_ticks_msec()
	var sd := ShipData.load_ship(sid)
	if sd == null:
		print("FAIL no data ", sid)
		fails += 1
		return
	var t1 := Time.get_ticks_msec()
	var enclosed := 0
	for r in sd.rooms:
		if bool(r["enclosed"]):
			enclosed += 1
	print("== %s %s  L=%.1f B=%.1f T=%.1f disp=%d  decks=%d rooms=%d(enclosed %d) stairs=%d comps=%d doors=%d valves=%d  plan %d ms" % [
		sid, sd.name_ja, sd.L, sd.B, sd.T, int(sd.disp), sd.decks.size(), sd.rooms.size(), enclosed, sd.stairs.size(), sd.comps.size(), sd.doors.size(), sd.valves.size(), t1 - t0])
	for d in sd.decks:
		var n := 0
		for r in sd.rooms:
			if int(r["deck"]) == sd.decks.find(d):
				n += 1
		print("   deck %-44s %6.2f %-8s rooms placed %d / %d" % [String(d["name"]).substr(0, 44), float(d["level"]), String(d["kind"]), n, (d["rooms"] as Array).size()])
	if not sd.headroom_adjusted.is_empty():
		print("   headroom: ", sd.headroom_adjusted)
	var root := Node3D.new()
	add_child(root)
	var xf := Transform3D(Basis(), Vector3(0, 0, 0))
	var s := Ship.create(sd, xf, "test", 7)
	root.add_child(s)
	var t2 := Time.get_ticks_msec()
	var ext_v := 0
	for c in s.body.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			for si in (c as MeshInstance3D).mesh.get_surface_count():
				ext_v += ((c as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# 船内
	s.int_root = Node3D.new()
	s.body.add_child(s.int_root)
	s.interior = ShipInterior.new(sd, s.int_root, 3)
	var steps := 0
	var tb := Time.get_ticks_msec()
	var worst := 0
	while not s.interior.step():
		steps += 1
		var tn := Time.get_ticks_msec()
		worst = maxi(worst, tn - tb)
		tb = tn
		if steps > 500:
			break
	s._finish_interior()
	var t3 := Time.get_ticks_msec()
	print("   build: exterior %d ms (%d verts, %d shapes), interior %d ms in %d steps (worst step %d ms, %d shapes, %d lights)" % [
		t2 - t1, ext_v, s.body.get_child_count(), t3 - t2, steps, worst, s.int_shapes.size(), s.interior.lights.size()])
	# シナリオ: 注水弁を全部開けて沈むまで
	await _scenario(s, "注水弁を全開", func(sh: Ship) -> void:
		for i in sh.flood.valve_open.size():
			sh.flood.set_valve(i, true))
	s.queue_free()
	await get_tree().process_frame
	# シナリオ 2: 片舷の水線下に爆薬（樽 900）
	var s2 := Ship.create(sd, xf, "test", 8)
	root.add_child(s2)
	await _scenario(s2, "左舷水線下に火薬樽×3", func(sh: Ship) -> void:
		for k in 3:
			var p := sh.body.global_transform * Vector3(-sd.half_beam(sd.z_of(sd.L * (0.35 + 0.15 * k)), -0.8) - 0.5, -0.8, sd.z_of(sd.L * (0.35 + 0.15 * k)))
			sh.on_blast(p, 13.0, 900.0, 0, 0.6))
	s2.queue_free()
	await get_tree().process_frame
	if not (sd.sim.get("magazines", []) as Array).is_empty():
		var s3 := Ship.create(sd, xf, "test", 9)
		root.add_child(s3)
		await _scenario(s3, "弾火薬庫に火薬樽", func(sh: Ship) -> void:
			var m: Dictionary = sh.flood.mag[sh.flood.mag.size() - 1]
			var cp: Dictionary = sd.comps[int((m["comps"] as Array)[0])]
			var p := sh.body.global_transform * Vector3(float(cp["cx"]) * 0.5, sd.keel_at(float(cp["cz"])) + 1.5, float(cp["cz"]))
			sh.on_blast(p, 13.0, 900.0, 0, 0.6))
		s3.queue_free()
		await get_tree().process_frame
	if not sd.steel:
		var s4 := Ship.create(sd, xf, "test", 10)
		root.add_child(s4)
		await _scenario(s4, "火矢で放火", func(sh: Ship) -> void:
			sh.flood.ignite_at(0.0, 0.5))
		s4.queue_free()
		await get_tree().process_frame
	root.queue_free()
	await get_tree().process_frame


func _scenario(s: Ship, label: String, act: Callable) -> void:
	await get_tree().process_frame
	act.call(s)
	var t := 0.0
	var dt := 0.1
	var sunk_t := -1.0
	var cap_t := -1.0
	var max_heel := 0.0
	var log := ""
	var limit := 3600.0
	while t < limit:
		s._physics_process(dt)
		t += dt
		max_heel = maxf(max_heel, absf(rad_to_deg(s.heel)))
		if s.phase == "capsizing" and cap_t < 0.0:
			cap_t = t
		if s.phase in ["plunge", "settling", "wreck"] and sunk_t < 0.0:
			sunk_t = t
		if int(t * 10.0) % 3000 == 0:
			log += " | %ds %d%% h%.0f° %s" % [int(t), int(s.flood.flood_ratio() * 100.0), rad_to_deg(s.heel), s.phase]
		if s.phase == "wreck":
			break
	print("   [%s] %s  沈没開始 %s  転覆 %s  最大傾斜 %.0f°  浸水 %d%%  火災 %d%s" % [label, s.phase,
		("%.0f s" % sunk_t) if sunk_t >= 0.0 else "-", ("%.0f s" % cap_t) if cap_t >= 0.0 else "-", max_heel, int(s.flood.flood_ratio() * 100.0), s.flood.burning(), log])
