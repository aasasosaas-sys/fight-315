extends SceneTree
## ヘッドレス: godot --headless --path . -s tests/test_flow.gd
## Flow の遷移（試験提出 → ハブ → 出発 → Session → completed/aborted → 結果 → ハブ → エンディング）を確認する。

var fails := 0
var _backup = null


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	var G: Node = root.get_node("Game")
	if FileAccess.file_exists(HistoryState.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(HistoryState.SAVE_PATH)
	var flow: Node = load("res://scripts/ui/flow.gd").new()
	flow.name = "Flow"
	flow.allow_backdrop = OS.get_environment("BACKDROP") == "1"
	root.add_child(flow)
	await _secs(0.5)
	_check(flow.current == "title", "title shown")
	_check(G.input_blocked, "input blocked on title")
	flow.start_new_game()
	await _secs(0.3)
	_check(flow.current == "exam", "exam shown")
	var st: HistoryState = G.state
	st.set_answer(G.db.questions[0], (int(G.db.questions[0]["real"]) + 1) % 4)
	flow.screen.submitted.emit()
	await _secs(0.3)
	_check(flow.current == "hub", "hub after submit")
	_check(st.exam_submitted, "exam_submitted")
	var unanswered := 0
	for q in G.db.questions:
		if st.answer(q) < 0: unanswered += 1
	_check(unanswered == 0, "unanswered filled")
	var q: Dictionary = G.db.questions[0]
	_check(not st.is_correct(q), "q0 wrong")
	flow.show_briefing(q)
	await _secs(0.2)
	_check(flow.current == "briefing", "briefing shown")
	flow.depart(q)
	await _secs(3.5)
	var has_session: bool = flow.session != null
	print("session available: ", flow.session_available(), " created: ", has_session)
	if has_session:
		_check(not G.input_blocked, "input unblocked during session")
		var changes := st.apply_change(q, st.answer(q), "test")
		flow.session.completed.emit(changes)
		await _secs(3.0)
		_check(flow.session == null, "session ended")
	else:
		await _secs(0.5)
	_check(flow.current == "aftermath", "aftermath shown (current=%s)" % flow.current)
	_check(st.is_correct(q), "q0 now correct")
	_check(G.input_blocked, "input blocked after return")
	flow.show_hub()
	await _secs(0.3)
	# 自由探索 → aborted → ハブ
	flow.start_free_roam(G.db.eras[0]["eraId"], "hub")
	await _secs(3.5)
	if flow.session != null:
		flow.session.aborted.emit()
		await _secs(3.0)
		_check(flow.current == "hub", "hub after abort (current=%s)" % flow.current)
	# 自由探索で人物を倒す → 歴史が揺らぐ → 中断 → 混乱版のアフター画面 → ハブ
	flow.start_free_roam("sengoku", "hub")
	await _secs(3.5)
	if flow.session != null:
		G.chaos_event.emit("kill", "羽柴秀吉", {"era": "sengoku", "type": "figure"})
		await _secs(0.3)
		_check(st.is_chaos(G.db.by_id["sengoku_05"]), "free-roam kill rewrote history")
		flow.session.aborted.emit()
		await _secs(3.0)
		_check(flow.current == "aftermath", "chaos aftermath after free roam (current=%s)" % flow.current)
		flow.screen.to_hub.emit()
		await _secs(0.4)
		_check(flow.current == "hub", "hub after chaos aftermath (current=%s)" % flow.current)
	# 失敗
	var q2: Dictionary = {}
	for x in G.db.questions:
		if not st.is_correct(x):
			q2 = x
			break
	if not q2.is_empty() and flow.session_available():
		flow.depart(q2)
		await _secs(3.5)
		if flow.session != null:
			flow.session.failed.emit("テスト失敗")
			await _secs(3.0)
			_check(flow.current == "failed", "failure screen (current=%s)" % flow.current)
	# 満点 → エンディング
	for x in G.db.questions:
		st.world[x["id"]] = st.answer(x)
	flow.show_ending()
	await _secs(0.5)
	_check(flow.current == "ending", "ending shown")
	st.reset_all()
	HistoryState.delete_save()
	if _backup != null:
		var f := FileAccess.open(HistoryState.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	print("FLOW TEST: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
