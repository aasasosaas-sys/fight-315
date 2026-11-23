extends Node
## 自由探索の人口（歴史上の人物・護衛・合戦の兵・町人）の重さを測る。
## godot --headless --path . res://tests/bench_population.tscn [-- eras=edo,showa] [-- fallback]
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
		await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
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
		await _bench_era(game, String(era_id))
	print("")
	print("==== bench_population summary ====")
	for r in _rows:
		print(r)
	get_tree().quit(0)


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
	var line := "%-6s %-12s humanoids=%d built=%d  build=%.0fms frames(sum=%.0fms max=%.1fms)  nodes=+%d objects=+%d resources=+%d mem=+%.1fMB  meshinst=%d meshes=%d materials=%d(refs %d) skins=%d shadowcasters=%d %s" % [
		era_id, phase, hc[0], hc[1], build_ms, float(frames[0]), float(frames[1]),
		int(now["nodes"] - base["nodes"]), int(now["objects"] - base["objects"]), int(now["resources"] - base["resources"]),
		(now["mem"] - base["mem"]) / 1048576.0, mis, meshes.size(), mats.size(), mat_refs, skins.size(), shadow, extra]
	print(line)
	_rows.append(line)


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
