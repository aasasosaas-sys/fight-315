extends Node
## 自由探索の人口（歴史上の人物・護衛・合戦の兵・町人）の重さを測る。
## godot --headless --path . res://tests/bench_population.tscn [-- eras=edo,showa] [-- fallback] [-- rigs_only]
## （顔の形のメッシュ作りはダミー描画では頂点が読めず軽く出るので、実際の重さは xvfb-run ＋ --rendering-driver opengl3 で rigs_only を測る）
## 各時代について：セッション開始 → 人物を全員実体化（spawn_all_figures）→ 名所を順に巡る、の各段階で
## 構築時間・最大フレーム時間（ヒッチ）・ノード数・メッシュ／素材／スキンの数（総数と共有後の実数）・メモリを出す。

var _rows: Array = []


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> Array:
	## n フレーム進め、[合計 ms, 最大 ms] を返す
	var total := 0.0
	var worst := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		var b0 := _st("stat_builds")
		var u0 := _st("stat_build_usec")
		var w0 := _st("stat_warm_usec")
		await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		if dt > 100.0 and OS.get_environment("BENCH_HITCH") != "":
			print("  hitch %.0fms rig builds=%d (%.0fms) anim warm %.0fms" % [dt, _st("stat_builds") - b0, (_st("stat_build_usec") - u0) / 1000.0, (_st("stat_warm_usec") - w0) / 1000.0])
		total += dt
		worst = maxf(worst, dt)
	return [total, worst]


func _run() -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		print("Game autoload missing"); get_tree().quit(2); return
	var args := Array(OS.get_cmdline_user_args())
	if "fallback" in args:
		game.set_meta("force_fallback_world", true)
	var eras: Array = ["edo", "showa"]
	for a in args:
		if String(a).begins_with("eras="):
			eras = String(a).substr(5).split(",")
	for era_id in eras:
		await _bench_rigs(String(era_id))
	for era_id in eras:
		if "rigs_only" in args:
			break
		await _bench_era(game, String(era_id))
	print("")
	print("==== bench_population summary ====")
	for r in _rows:
		print(r)
	get_tree().quit(0)


## 人物の見た目だけ：その時代の町人・兵・歴史上の人物を 40 人すぐに組み立てる（ワールドなし）→ 捨てる
func _bench_rigs(era_id: String) -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	await _frames(2)
	var base := _snap()
	var names: Array = []
	for nm in Game.db.actors:
		if (Game.db.actors[nm] as Dictionary).get("spawn_eras", {}).has(era_id) and Figures.resolve(nm) != "":
			names.append(nm)
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	for i in 40:
		var t1 := Time.get_ticks_usec()
		var h: Humanoid
		if i % 4 == 3 and not names.is_empty():
			var nm: String = names[(i / 4) % names.size()]
			h = Humanoid.build(Humanoid.outfit_for(era_id, "npc"), hash(nm), false, -1, nm)
		elif i % 4 == 2:
			h = Humanoid.build(Humanoid.outfit_for(era_id, "enemy"), 1000 + i, true)
		else:
			h = Humanoid.build(Humanoid.outfit_for(era_id, "civilian"), 2000 + i, false)
		root.add_child(h)
		h.position = Vector3(i % 8, 0, i / 8) * 1.5
		worst = maxf(worst, (Time.get_ticks_usec() - t1) / 1000.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var f: Array = await _frames(30)
	_report(era_id, "rigs40", root, base, ms, f, "per_rig=%.1fms worst_rig=%.0fms" % [ms / 40.0, worst])
	root.queue_free()
	await _frames(5)
	var now := _snap()
	print("%-6s rigs40 freed: mem=+%.1fMB resources=+%d (kept by caches)" % [era_id, (now["mem"] - base["mem"]) / 1048576.0, int(now["resources"] - base["resources"])])


func _bench_era(game: Node, era_id: String) -> void:
	var base := _snap()
	var t0 := Time.get_ticks_usec()
	var sess: Session = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	var ready_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var f1: Array = await _frames(90)
	_report(era_id, "start", sess, base, ready_ms, f1)
	t0 = Time.get_ticks_usec()
	sess.spawn_all_figures()
	var all_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var f2: Array = await _frames(120)
	_report(era_id, "all_figures", sess, base, all_ms, f2)
	# 名所を巡る（ストリーミングの出入り）
	var worst := 0.0
	var total := 0.0
	var peak_built := 0
	for key in HistoryDB.LANDMARK_KEYS:
		sess.player.teleport(sess.world.landmark_pos(key) + Vector3(3, 0, 3))
		var f3: Array = await _frames(45)
		total += float(f3[0])
		worst = maxf(worst, float(f3[1]))
		peak_built = maxi(peak_built, _count_humanoids(sess)[1])
	_report(era_id, "tour", sess, base, 0.0, [total, worst], "peak_built=%d" % peak_built)
	print("  caches: face meshes=%d face infos=%d face mats=%d cloth mats=%d anim libs=%d trees=%d scenes=%d" % [_cs("anime_face", "_mesh_cache"), _cs("anime_face", "_info_cache"),
		_cs("anime_face", "_mat_share"), _cs("anime_char", "_mat_cache"), _cs("retarget", "_lib_cache"), _cs("humanoid", "_bt_cache"), _cs("anime_char", "_scene_cache")])
	sess.end()
	await _frames(5)
	if game.has_method("set_world"):
		game.set_world(null)


func _snap() -> Dictionary:
	return {
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC),
	}


func _count_humanoids(root: Node) -> Array:
	var total := 0
	var built := 0
	for n in _all(root):
		if n is Humanoid:
			total += 1
			if (n as Humanoid).has_method("is_built"):
				if bool((n as Humanoid).call("is_built")):
					built += 1
			elif (n as Humanoid).get_child_count() > 1:
				built += 1
	return [total, built]


func _all(root: Node) -> Array:
	var out: Array = [root]
	var i := 0
	while i < out.size():
		out.append_array((out[i] as Node).get_children())
		i += 1
	return out


func _report(era_id: String, phase: String, sess: Node, base: Dictionary, build_ms: float, frames: Array, extra := "") -> void:
	var now := _snap()
	var hc := _count_humanoids(sess)
	var mis := 0
	var meshes := {}
	var mats := {}
	var skins := {}
	var mat_refs := 0
	var shadow := 0
	for n in _all(sess):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not _in_humanoid(mi):
			continue
		mis += 1
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.is_visible_in_tree():
			shadow += 1
		if mi.mesh:
			meshes[mi.mesh.get_instance_id()] = true
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(si)
				if m == null:
					m = mi.mesh.surface_get_material(si)
				_add_mat(m, mats)
				mat_refs += 1
		if mi.material_override:
			_add_mat(mi.material_override, mats)
			mat_refs += 1
		if mi.skin:
			skins[mi.skin.get_instance_id()] = true
	if _st("stat_builds") >= 0:
		extra = "rig_builds=%d (avg %.1fms max %.1fms) unbuilds=%d %s" % [_st("stat_builds"), _st("stat_build_usec") / 1000.0 / maxf(1.0, _st("stat_builds")),
			_st("stat_build_max_usec") / 1000.0, _st("stat_unbuilds"), extra]
	var line := "%-6s %-12s humanoids=%d built=%d  build=%.0fms frames(sum=%.0fms max=%.1fms)  nodes=+%d objects=+%d resources=+%d mem=+%.1fMB  meshinst=%d meshes=%d materials=%d(refs %d) skins=%d shadowcasters=%d %s" % [
		era_id, phase, hc[0], hc[1], build_ms, float(frames[0]), float(frames[1]),
		int(now["nodes"] - base["nodes"]), int(now["objects"] - base["objects"]), int(now["resources"] - base["resources"]),
		(now["mem"] - base["mem"]) / 1048576.0, mis, meshes.size(), mats.size(), mat_refs, skins.size(), shadow, extra]
	print(line)
	_rows.append(line)


## Humanoid の統計（静的変数。古い版には無いので -1）
func _st(nm: String) -> int:
	var v: Variant = (load("res://scripts/player/humanoid.gd") as GDScript).get(nm)
	return int(v) if v != null else -1


## キャッシュの大きさ（無ければ -1）
func _cs(file: String, nm: String) -> int:
	var dirs := {"anime_face": "player", "anime_char": "player", "retarget": "player", "humanoid": "player"}
	var v: Variant = (load("res://scripts/%s/%s.gd" % [dirs[file], file]) as GDScript).get(nm)
	return (v as Dictionary).size() if v is Dictionary else -1


func _in_humanoid(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is Humanoid:
			return true
		p = p.get_parent()
	return false


func _add_mat(m: Material, mats: Dictionary) -> void:
	var guard := 0
	while m and guard < 4:
		mats[m.get_instance_id()] = true
		m = m.next_pass
		guard += 1
