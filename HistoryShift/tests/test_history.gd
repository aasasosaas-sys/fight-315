extends SceneTree
## ヘッドレス検証: godot --headless --path . -s tests/test_history.gd
## 因果エンジンの性質（年代順に改変すれば必ず満点になる）をランダム答案で確かめる。

func _initialize() -> void:
	var db := HistoryDB.load_all()
	var fails := 0
	print("questions=%d rules=%d errors=%d" % [db.questions.size(), db.rules.size(), db.errors.size()])
	if db.questions.size() < 30: fails += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for trial in 200:
		var st := HistoryState.new(db)
		for q in db.questions:
			st.answers[q["id"]] = rng.randi_range(0, 3)
		st.exam_submitted = true
		# 年代順に、間違っている問題だけ改変していく
		var missions := 0
		for q in db.questions:
			if not st.is_correct(q):
				var m := db.mission_for(q, st.answer(q))
				if m.is_empty() or m.get("steps", []).is_empty():
					fails += 1
				st.apply_change(q, st.answer(q), m["title"])
				missions += 1
		if not st.perfect():
			fails += 1
			print("trial %d not perfect: %d/%d" % [trial, st.correct_count(), db.questions.size()])
		var ending := st.compose_ending()
		if String(ending[1]).length() < 20: fails += 1
		if trial == 0:
			print("missions needed=%d  ending=%s" % [missions, ending[0]])
			print(ending[1].substr(0, 400))
	# 連鎖が実際に起きることの確認
	var st2 := HistoryState.new(db)
	var cascades := 0
	for r in db.rules:
		st2.reset_all()
		var ch := st2.apply_change(db.by_id[r["ifQ"]], r["ifChoice"], "test")
		if ch.size() >= 2: cascades += 1
	print("rules that cascade=%d/%d" % [cascades, db.rules.size()])
	if cascades == 0: fails += 1
	HistoryState.delete_save()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
