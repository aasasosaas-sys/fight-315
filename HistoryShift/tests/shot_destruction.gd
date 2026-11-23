extends Node
## 破壊システムのスクリーンショット＆計測:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shot_destruction.tscn [-- edo sengoku ...]
## 自由探索で家・木・船・塀に爆薬を撃ち込み、前/最中/後を撮る。描画コール数・破片数・処理時間を出力する。
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

var sess: Session
var cam: CameraRig
var p: Player
var chaos_log: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "destr_" + name + ".png")
	var d := Destruction.current
	print("saved %s  draws=%d objects=%d debris=%d fires=%d" % [name, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), d.live_debris() if d else -1, d.burning_count() if d else -1])


## target を画面中央に、dist m 離れて見る（テスト専用カメラ）
var tcam: Camera3D


func _frame(target: Vector3, dist: float, height := 6.0, side := 0.0, ignore: Object = null) -> void:
	var w = sess.world
	# 視線が通る向きを探す（建物・木の幹に遮られない位置）
	var space := get_viewport().world_3d.direct_space_state
	var pos := Vector3.ZERO
	var dir := Vector3.ZERO
	for k in 12:
		var a := side + (k / 2) * 0.55 * (1.0 if k % 2 == 0 else -1.0)
		dir = Vector3(sin(a), 0, cos(a))
		pos = target + dir * dist
		pos.y = maxf(float(w.height_at(pos.x, pos.z)), float(w.water_level)) + height
		var q := PhysicsRayQueryParameters3D.create(pos, target, Game.COLLISION_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit["collider"] == ignore or (hit["position"] as Vector3).distance_to(target) < 4.0:
			break
	# プレイヤーは画面外（後ろ）へ
	var pp := target + dir * (dist + 6.0)
	p.teleport(Vector3(pp.x, w.height_at(pp.x, pp.z), pp.z))
	if tcam == null:
		tcam = Camera3D.new()
		tcam.fov = 60.0
		tcam.far = 3000.0
		sess.add_child(tcam)
	tcam.global_position = pos
	tcam.look_at(target, Vector3.UP)
	tcam.make_current()
	await _frames(4)


func _find(kind: String, near: Vector3, max_d := 400.0, filter := Callable()) -> Destructible:
	var best: Destructible = null
	var bd := max_d
	for u in Destruction.current.units.values():
		var du := u as Destructible
		if du.kind != kind or du.destroyed:
			continue
		if filter.is_valid() and not filter.call(du):
			continue
		var dd := du.center().distance_to(near)
		if dd < bd:
			bd = dd
			best = du
	return best


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var eras: Array = []
	for a in args:
		eras.append(a)
	if eras.is_empty():
		eras = ["edo", "sengoku"]
	Game.chaos_event.connect(func(k: String, id: String, info: Dictionary) -> void:
		chaos_log.append([k, id, info.get("type", "")])
		print("  chaos_event: %s %s %s" % [k, id, info.get("type", "")]))
	for era_id in eras:
		await _era(era_id)
	print("chaos events: ", chaos_log.size())
	get_tree().quit()


func _era(era_id: String) -> void:
	sess = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await _frames(2)
	Game.lock_mouse(false)
	p = sess.player
	p.god_mode = true
	cam = sess.cam
	var w = sess.world
	var d := Destruction.current
	await _frames(10)
	var cap: Vector3 = w.landmark_pos("capital")
	print("[%s] units=%d trees=%d build=%dms" % [era_id, d.units.size(), (w.tree_defs as Array).size(), w.build_ms])

	# ---- 1) 家を焙烙玉 → ダイナマイト級で倒壊
	var house := _find("house", cap + Vector3(0, 0, 20))
	if house:
		var c := house.center()
		var hz := house.frame.basis.z
		await _frame(c, 20.0, 5.0, atan2(hz.x, hz.z) + 0.5, house)
		await _shot("%s_house_before" % era_id)
		var t0 := Time.get_ticks_usec()
		Effects.explosion(get_tree(), c + Vector3(0, 0.5, 0), 7.0, 300.0, 0, 0.0)
		print("  house blast1 %.1f ms  hp=%.0f/%.0f stage=%d" % [(Time.get_ticks_usec() - t0) / 1000.0, house.hp, house.max_hp, house.stage])
		await _wait(0.6)
		await _shot("%s_house_cracked" % era_id)
		t0 = Time.get_ticks_usec()
		Effects.explosion(get_tree(), c + Vector3(0.5, 1.0, 0), 11.0, 700.0, 0, 0.0)
		print("  house blast2 %.1f ms  destroyed=%s" % [(Time.get_ticks_usec() - t0) / 1000.0, house.destroyed])
		await _wait(0.12)
		await _shot("%s_house_during" % era_id)
		await _wait(2.5)
		await _shot("%s_house_after" % era_id)
		await _wait(12.0)
		await _shot("%s_house_settled" % era_id)

	# ---- 2) 町並みに棒火矢 → 延焼
	var row := _find("house", cap + Vector3(-25, 0, -10), 400.0, func(u: Destructible) -> bool: return u.flammable)
	if row:
		var c := row.center()
		var fz := row.frame.basis.z
		await _frame(c, 24.0, 8.0, atan2(fz.x, fz.z) + 0.35, row)
		row.last_cause = "player"
		row.ignite()
		Shell.fire(get_tree(), "hiya", c + fz * 10.0 + Vector3(0, 5, 0), -fz * 40.0 + Vector3(0, -8, 0), 0)
		await _wait(2.0)
		await _shot("%s_fire_start" % era_id)
		await _wait(12.0)
		await _shot("%s_fire_spread" % era_id)
		print("  burning=%d" % d.burning_count())
		await _wait(22.0)
		await _shot("%s_fire_late" % era_id)

	# ---- 3) 塀（tsuiji 等）を大筒で
	var wall := _find("wall", cap, 500.0)
	if wall == null:
		wall = _find("fence", cap, 500.0)
	if wall:
		var c := wall.center()
		await _frame(c, 16.0, 4.0, 1.0, wall)
		await _shot("%s_wall_before" % era_id)
		var can := FieldCannon.place(get_tree(), p.global_position + Vector3(2, 0, 0), 0.0, false)
		await _frames(2)
		can.fire_at(c)
		await _wait(1.2)
		await _shot("%s_wall_after" % era_id)

	# ---- 4) 木を倒す
	var trees: Array = w.tree_defs
	var tpos := Vector3.INF
	var best := 1e9
	for td in trees:
		var o: Vector3 = (td["xf"] as Transform3D).origin
		var dd := o.distance_to(cap)
		if d.units_near(o, 10.0).size() > 0:
			continue
		if dd < best and dd > 60.0:
			best = dd
			tpos = o
	if tpos != Vector3.INF:
		await _frame(tpos + Vector3(0, 4, 0), 26.0, 7.0, 0.3)
		await _shot("%s_tree_before" % era_id)
		Effects.explosion(get_tree(), tpos + Vector3(1.5, 0.5, 0), 9.0, 500.0, 0, 0.0)
		await _wait(0.8)
		await _shot("%s_tree_during" % era_id)
		await _wait(1.8)
		await _shot("%s_tree_after" % era_id)

	# ---- 5) 港の船を沈める
	var port: Vector3 = w.landmark_pos("port")
	var boat := _find("boat", port, 300.0, func(u: Destructible) -> bool: return u.max_hp > 400.0)
	if boat == null:
		boat = _find("boat", port, 300.0)
	if boat:
		var c := boat.center()
		var side := atan2(port.x - c.x, port.z - c.z)
		await _frame(c, 30.0, 6.0, side, boat)
		await _shot("%s_boat_before" % era_id)
		Effects.explosion(get_tree(), c + Vector3(0, 1, 0), 10.0, 2000.0, 0, 1.0)
		await _wait(2.0)
		await _shot("%s_boat_during" % era_id)
		await _wait(6.0)
		await _shot("%s_boat_after" % era_id)

	# ---- 6) 天守（戦国）/ 大きな建物を段階的に
	var keep := _find("castle_keep", w.landmark_pos("castle"), 600.0)
	if keep == null:
		keep = _find("castle_keep", cap, 600.0)
	if keep:
		var c := keep.center()
		await _frame(c, 75.0, 14.0, 0.5, keep)
		await _shot("%s_keep_before" % era_id)
		for i in 6:
			Effects.explosion(get_tree(), c + Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4)), 13.0, 900.0, 0, 0.0)
			await _wait(0.25)
		print("  keep hp=%.0f/%.0f stage=%d" % [keep.hp, keep.max_hp, keep.stage])
		await _wait(0.8)
		await _shot("%s_keep_stage" % era_id)
		for i in 6:
			Effects.explosion(get_tree(), c + Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4)), 13.0, 1200.0, 0, 0.0)
			await _wait(0.2)
		await _wait(0.6)
		await _shot("%s_keep_during" % era_id)
		await _wait(4.0)
		await _shot("%s_keep_after" % era_id)
		print("  keep destroyed=%s" % keep.destroyed)

	# ---- 7) 町の中心で大暴れ（性能計測）
	await _frame(cap + Vector3(0, 2, 0), 40.0, 14.0, 0.0)
	var t1 := Time.get_ticks_usec()
	for i in 8:
		Effects.explosion(get_tree(), cap + Vector3(randf_range(-30, 30), 1.0, randf_range(-30, 30)), 11.0, 800.0, 0, 0.3)
	print("  8 blasts %.1f ms  debris=%d peak=%d" % [(Time.get_ticks_usec() - t1) / 1000.0, d.live_debris(), d.debris_peak])
	await _wait(1.0)
	await _shot("%s_rampage" % era_id)
	print("  stats: %s" % d.summary_text())
	tcam = null
	sess.end()
	await _frames(5)
