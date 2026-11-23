extends SceneTree
## UI スクリーンショット:
## xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 -s tests/shot_ui.gd
## 出力先は環境変数 SHOT_DIR（無ければ user://shots）。ONLY=hub,exam のように絞り込み可。

var out_dir := ""
var flow: Node
var only: PackedStringArray = []
var _save_backup = null


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var o := OS.get_environment("ONLY")
	if o != "":
		only = o.split(",")
	_run.call_deferred()


func _game() -> Node:
	return root.get_node("Game")


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _want(name: String) -> bool:
	return only.is_empty() or name in only


func _shot(name: String) -> void:
	await _wait(3)
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("ui_%s.png" % name)
	img.save_png(path)
	print("shot: ", path)


func _clear_modals() -> void:
	for n in get_nodes_in_group("ui_modal"):
		n.remove_from_group("ui_modal")
		n.queue_free()
	await _wait(2)


func _run() -> void:
	var G := _game()
	if FileAccess.file_exists(HistoryState.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(HistoryState.SAVE_PATH)
	G.state.reset_all()
	var no_bd := OS.get_environment("NO_BACKDROP") == "1"
	var flow_script := load("res://scripts/ui/flow.gd")
	flow = flow_script.new()
	flow.name = "Flow"
	if no_bd:
		flow.set("allow_backdrop", false)
	root.add_child(flow)
	var db: HistoryDB = G.db
	var st: HistoryState = G.state

	# ---------------- タイトル
	if _want("title"):
		await _secs(2.5)
		await _shot("title")
	# ---------------- 試験
	if _want("exam"):
		flow.show_exam()
		await _secs(0.8)
		await _shot("exam_intro")
		await _clear_modals()
		flow.screen.running = true
		for i in 9:
			st.set_answer(db.questions[i], (i * 3 + 1) % 4)
		flow.screen._show_q(4, false)
		flow.screen.time_left = 61 * 60 + 23
		await _secs(0.5)
		await _shot("exam")
		flow.screen._show_q(26, false)
		await _secs(0.3)
		await _shot("exam_q27")
		flow.screen._ask_submit()
		await _secs(0.5)
		await _shot("exam_submit")
		await _clear_modals()
	# ---------------- ハブ（正答と誤答を混在させる）
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	st.reset_all()
	for q in db.questions:
		var a: int = q["real"] if rng.randf() < 0.6 else (int(q["real"]) + rng.randi_range(1, 3)) % 4
		st.answers[q["id"]] = a
	st.exam_submitted = true
	# ripple のある誤答を探して改変
	var target: Dictionary = {}
	for q in db.questions:
		if not st.is_correct(q) and not st.predict_ripple(q, st.answer(q)).is_empty():
			target = q
			break
	if target.is_empty():
		for q in db.questions:
			if not st.is_correct(q):
				target = q
				break
	var before_score := st.score()
	var before_correct := st.correct_count()
	var changes := st.apply_change(target, st.answer(target), "テスト")
	HistoryState.delete_save()
	var wrong: Dictionary = {}
	for q in db.questions:
		if not st.is_correct(q) and not st.predict_ripple(q, st.answer(q)).is_empty():
			wrong = q
			break
	if wrong.is_empty():
		for q in db.questions:
			if not st.is_correct(q):
				wrong = q
				break
	if _want("hub"):
		flow.show_hub(wrong.get("id", ""), true)
		await _secs(2.0)
		await _shot("hub")
		flow.screen._select(target, false)
		await _secs(0.4)
		await _shot("hub_correct")
		flow.screen._show_log()
		await _secs(0.5)
		await _shot("hub_log")
		await _clear_modals()
	if _want("briefing"):
		flow.show_briefing(wrong)
		await _secs(0.8)
		await _shot("briefing")
		var showa: Dictionary = {}
		for q in db.questions:
			if q["era"]["eraId"] == "showa" and not st.is_correct(q):
				showa = q
		if not showa.is_empty():
			flow.show_briefing(showa)
			await _secs(0.8)
			await _shot("briefing_showa")
	if _want("warp"):
		var w: Control = flow.WarpScreen.new()
		w.title = wrong["era"]["eraName"]
		w.subtitle = JSUI.era_years(wrong["era"]["eraId"])
		flow.warp_layer.add_child(w)
		await _secs(1.2)
		await _shot("warp")
		w.queue_free()
	if _want("aftermath"):
		flow._score_before = before_score
		flow._correct_before = before_correct
		flow.show_aftermath(target, changes)
		await _secs(1.0 + changes.size() * 0.5 + 1.5)
		await _shot("aftermath")
		flow.show_failure(wrong, "制限時間内に目的地へ到着できなかった。")
		await _secs(0.8)
		await _shot("failed")
	if _want("ending"):
		for q in db.questions:
			st.world[q["id"]] = st.answer(q)
		flow.show_ending()
		await _secs(6.0)
		await _shot("ending_typing")
		flow.screen._finish_typing()
		await _secs(1.0)
		await _shot("ending")
	if _want("modals"):
		flow.show_hub()
		await _secs(0.5)
		flow.SettingsScreen.open(flow.root)
		await _secs(0.5)
		await _shot("settings")
		await _clear_modals()
		flow.CreditsScreen.open(flow.root)
		await _secs(0.5)
		await _shot("credits")
		await _clear_modals()
		load("res://scripts/ui/era_picker.gd").open(flow.root, func(_id): pass)
		await _secs(0.5)
		await _shot("era_picker")
		await _clear_modals()
	# 後片付け
	st.reset_all()
	HistoryState.delete_save()
	if _save_backup != null:
		var f := FileAccess.open(HistoryState.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
	print("shots done")
	quit()
