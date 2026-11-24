extends Node
## 技能・工房・製作・近接のスクリーンショット:
## xvfb-run godot --path . --rendering-driver vulkan res://tests/shot_skills.tscn -- [era] [out_dir]
## 本物のセーブに触れないよう、別の持ち物ファイルを使う。

var OUT := "user://shots_skills/"


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String, wait := 8) -> void:
	await _frames(wait)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT.path_join(name + ".png"))
	print("saved ", OUT.path_join(name + ".png"))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var era_id: String = args[0] if args.size() > 0 else "edo"
	if args.size() > 1:
		OUT = args[1]
	DirAccess.make_dir_recursive_absolute(OUT if OUT.begins_with("/") else ProjectSettings.globalize_path(OUT))
	PlayerProfile.save_path = "user://shot_profile.json"
	var saved = Game.profile
	var prof := PlayerProfile.new()
	prof.autosave = false
	Game.profile = prof
	prof.skills["katana_smith"] = 62.0
	prof.skills["kenjutsu"] = 48.0
	prof.skills["chemistry"] = 71.0
	prof.skills["powder"] = 33.0
	prof.skills["piloting"] = 12.0
	prof.skills["rhetoric"] = 25.0
	prof.add_money(4000 * 12 + 350)
	for pair in [["tamahagane", 4], ["mokutan", 8], ["nendo", 3], ["mokuzai", 4], ["satetsu", 6], ["shoseki", 6], ["iou", 2], ["namari", 2], ["nuno", 2]]:
		prof.add(pair[0], pair[1], 0.55)
	var sess := Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await _frames(5)
	Game.lock_mouse(false)
	var p: Player = sess.player
	p.god_mode = true
	var cam: CameraRig = sess.cam
	var industry_only := "industry" in args
	var st: CraftStation = null if industry_only else sess.craft.find_station("touko")
	if st == null and not industry_only and not sess.craft.stations.is_empty():
		st = sess.craft.stations[0]
	if st:
		var front := st.global_position + st.global_basis.z * 6.0
		p.teleport(front)
		var to := st.global_position - front
		cam.yaw = atan2(-to.x, -to.z)
		cam.pitch = -0.12
		cam.snap()
		await _shot("skills_%s_workshop_world" % era_id, 40)
		# 工房の画面
		sess.craft.ui.open_workshop(st)
		await _shot("skills_%s_workshop_ui" % era_id)
		# 稽古（鍛錬：拍子よく打つ）
		sess.craft.ui._start_lesson(st.def["lessons"][0])
		await _shot("skills_%s_lesson_hammer" % era_id, 10)
		sess.craft.ui.finish_minigame(0.85)
		await get_tree().create_timer(1.0).timeout
		await _shot("skills_%s_lesson_result" % era_id, 10)
		# 焼き入れ
		if st.def["lessons"].size() > 1:
			sess.craft.ui._start_lesson(st.def["lessons"][1])
			await _shot("skills_%s_lesson_heat" % era_id, 15)
			sess.craft.ui.finish_minigame(0.7)
			await get_tree().create_timer(1.0).timeout
		# 製作
		sess.craft.ui.open_crafting(st)
		await _shot("skills_%s_crafting" % era_id)
		sess.craft.ui._craft_now("r_uchigatana", "forge", 0.9)
		await _shot("skills_%s_crafted" % era_id)
		sess.craft.ui.close()
	if industry_only:
		await _industry_shots(sess, prof, era_id)
		Game.profile = saved
		get_tree().quit()
		return
	# 持ち物・技能
	sess.craft.ui._tab = 0
	sess.craft.ui.open_inventory()
	await _shot("skills_%s_inventory" % era_id)
	sess.craft.ui._tab = 1
	sess.craft.ui.open_inventory()
	await _shot("skills_%s_skills" % era_id)
	sess.craft.ui.close()
	# 近接：刀を手に、兵に強い振り
	var kat: Array = prof.weapons().filter(func(w): return str(w["id"]) == "uchigatana")
	if kat.is_empty():
		kat = [prof.add_instance(Crafting.make_item("uchigatana", 0.85, "あなた", era_id))]
	p.arms.equip(int(kat[0]["uid"]))
	var e := Enemy.spawn(sess, p.global_position - Vector3(0, 0, 2.2) + Vector3.UP * 0.5, "足軽", era_id)
	e.aggro_range = 0.0
	cam.yaw = 0.0
	cam.pitch = -0.15
	await _frames(15)
	p.arms._busy_until = 0.0
	p.arms.swing(true)
	await _frames(int(Engine.get_frames_per_second() * 0.25) + 2)
	await _shot("skills_%s_melee" % era_id, 1)
	await _frames(20)
	p.arms.blocking = true
	Input.action_press("aim")
	await _shot("skills_%s_block" % era_id, 10)
	Input.action_release("aim")
	p.arms.blocking = false
	await _industry_shots(sess, prof, era_id)
	Game.profile = saved
	get_tree().quit()


func _industry_shots(sess: Session, prof: PlayerProfile, era_id: String) -> void:
	var p: Player = sess.player
	var cam: CameraRig = sess.cam
	# 知識の木・建設・施設（江戸で産業革命）
	Knowledge.read_textbook(prof)
	for nid in ["m_tatara", "m_hansharo", "p_suisha", "p_jouki", "k_karakuri", "k_senban", "t_teori", "t_boseki", "m_saikutsu", "m_koro", "p_tetsudo"]:
		Knowledge.learn(prof, nid, true)
		prof.knowledge[nid]["m"] = 62.0
	sess.craft.ui._tab = 2
	sess.craft.ui._sel_node = "p_jouki"
	sess.craft.ui.open_inventory()
	await _shot("skills_%s_knowledge" % era_id)
	prof.permits[era_id] = true
	for pair in [["hagane", 12], ["kikai_buhin", 20], ["renga", 20], ["jouki", 3], ["mokuzai", 40], ["rail", 40], ["wata", 20], ["tetsu", 20], ["sekitan", 30]]:
		prof.add(pair[0], pair[1], 0.6)
	prof.add_money(4000000)
	var vpos: Vector3 = sess.world.landmark_pos("village")
	p.teleport(vpos + Vector3(12, 0, 12))
	cam.yaw = 0.0
	await _frames(10)
	sess.craft.ui._tab = 3
	sess.craft.ui.open_inventory()
	await _shot("skills_%s_build_menu" % era_id)
	sess.craft.ui.close()
	var made: Array = []
	for t in ["kikai_kojo", "boseki", "tetsudo"]:
		var r: Dictionary = sess.craft.build(t)
		print("build ", t, " ", r.get("ok"), " ", r.get("reason", ""))
		if r.get("ok", false):
			var f = r["facility"]
			f.rec["workers"] = f.needed_workers()
			f.deposit(prof)
			made.append(f)
		p.teleport(p.global_position + Vector3(-26, 0, 6))
		await _frames(5)
	if not made.is_empty():
		var f0: Node3D = made[0]
		for i in 3:
			f0.produce_once()
		sess.craft.ui.open_factory(f0)
		await _shot("skills_%s_factory_panel" % era_id)
		sess.craft.ui.close()
	# 町の家並みに隠れないよう、カメラを止めて斜め上から見下ろす（「歴史が揺らいだ」の通知は消す）
	var hud = sess.hud
	if hud and "_shift" in hud:
		hud._shift_queue.clear()
		hud._shift.visible = false
	cam.set_process(false)
	cam.set_physics_process(false)
	var names := {"kikai_kojo": "factory_world", "boseki": "mill_world", "tetsudo": "railway"}
	for f in made:
		var key := str(names.get(str(f.rec.get("type", "")), ""))
		if key == "":
			continue
		var c: Vector3 = f.global_position
		var far := 46.0 if key == "railway" else 26.0
		cam.global_position = c + Vector3(far * 0.7, far * 0.55, far * 0.7)
		cam.look_at(c + Vector3(0, 3, 0), Vector3.UP)
		if hud and "_shift" in hud:
			hud._shift.visible = false
		await _shot("skills_%s_%s" % [era_id, key], 40)
	cam.set_process(true)
	cam.set_physics_process(true)
