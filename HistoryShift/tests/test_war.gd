extends SceneTree
## ヘッドレス: godot --headless --path . -s tests/test_war.gd
## 太平洋戦争の帰趨モデル（WarModel・国家事業）を検証する。
##  1. 史実のままなら「敗戦」
##  2. どの事業も1つだけでは勝てない（有利な休戦にも届かない）。明治・昭和の事業と人物の救出をすべて合わせても勝てない
##  3. 複数の時代にまたがる深い戦略なら勝てる（貪欲探索で見つけて年表を表示）
##  4. 開戦を避ける道がある
##  5. ファズ：ランダムな事業の組み合わせで帰趨・設問が正しく解け、セーブ／ロードで帰趨が保たれる
##  6. 勝った世界でも、年代順に直せば満点。エンディングに帰趨が書かれる
##  7. 自由探索で看板（ProjectSite）が立ち、事業を成し遂げると歴史に反映される

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL ", msg)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _apply_set(st: HistoryState, db: HistoryDB, ids: Array, extra: Array = []) -> void:
	var acts: Array = []
	var i := 0
	for pid in ids:
		i += 1
		acts.append({"verb": "project", "target": pid, "seq": i, "era": db.projects[pid]["era"]})
	for a in extra:
		i += 1
		var b: Dictionary = a.duplicate()
		b["seq"] = i
		acts.append(b)
	st.actions = acts
	st.recompute()


## 勝利・開戦回避に向けた貪欲探索。goal(st) が大きいほど良い
func _greedy(st: HistoryState, db: HistoryDB, cands: Array, target: String, goal: Callable, extra_cands: Array = []) -> Array:
	var chosen: Array = []
	var extra: Array = []
	for step in 40:
		_apply_set(st, db, chosen, extra)
		if st.war_tier() == target:
			return [chosen, extra]
		var best = null
		var best_v := -1e9
		for pid in cands:
			if pid in chosen or not WarModel.available(db, st.actions, st.war["pillars"], pid)[0]:
				continue
			_apply_set(st, db, chosen + [pid], extra)
			var v: float = goal.call(st) + (1000.0 if st.war_tier() == target else 0.0)
			if v > best_v:
				best_v = v
				best = pid
		for a in extra_cands:
			if a in extra:
				continue
			_apply_set(st, db, chosen, extra + [a])
			var v2: float = goal.call(st) + (1000.0 if st.war_tier() == target else 0.0)
			if v2 > best_v:
				best_v = v2
				best = a
		if best == null:
			break
		if best is String:
			chosen.append(best)
		else:
			extra.append(best)
	_apply_set(st, db, chosen, extra)
	return [chosen, extra] if st.war_tier() == target else []


func _run() -> void:
	HistoryState.save_path = "user://test_war_%d.json" % OS.get_process_id()
	var db := HistoryDB.load_all()
	_check(not db.war_model.is_empty(), "war model loaded")
	_check(db.projects.size() >= 32, "projects loaded (%d)" % db.projects.size())
	var st := HistoryState.new(db)
	_check(st.war_tier() == "敗戦", "baseline is historical defeat (%s, score %.1f)" % [st.war_tier(), st.war.get("score", 0.0)])
	# 2. 1つだけでは勝てない
	for pid in db.projects:
		_apply_set(st, db, [pid])
		_check(not (st.war_tier() in ["勝利", "有利な休戦"]), "single project %s does not win (%s)" % [pid, st.war_tier()])
	var late: Array = db.projects.keys().filter(func(p): return db.projects[p]["era"] in ["meiji_taisho", "showa"])
	var saves: Array = []
	for nm in db.actors:
		var a: Dictionary = db.actors[nm]
		if a.has("saved") and str(a.get("era", "")) in ["meiji_taisho", "showa"]:
			saves.append({"verb": "protect", "target": nm, "era": a["era"]})
	_apply_set(st, db, late, saves)
	_check(st.war_tier() != "勝利", "all Meiji/Showa projects + saves cannot win (%s, score %.1f)" % [st.war_tier(), st.war["score"]])
	print("late-only best: %s (score %.1f)" % [st.war_tier(), st.war["score"]])
	# 3. 深い戦略なら勝てる
	var all_ids: Array = db.projects.keys()
	var win := _greedy(st, db, all_ids, "勝利", func(s): return float(s.war["score"]))
	_check(not win.is_empty(), "a deep multi-era strategy can win")
	if not win.is_empty():
		var eras := {}
		var lines: PackedStringArray = []
		var ids: Array = win[0]
		ids.sort_custom(func(a, b): return int(db.projects[a]["year"]) < int(db.projects[b]["year"]))
		for pid in ids:
			eras[db.projects[pid]["era"]] = true
			lines.append("%d年 %s" % [db.projects[pid]["year"], db.projects[pid]["name"]])
		_apply_set(st, db, ids)
		print("winning strategy (%d projects, %d eras, score %.1f):\n  %s" % [ids.size(), eras.size(), st.war["score"], "\n  ".join(lines)])
		_check(eras.size() >= 2 and ids.size() >= 6, "victory needs several projects across eras")
		var earliest := 9999
		for pid in ids:
			earliest = mini(earliest, int(db.projects[pid]["year"]))
		_check(earliest < 1868, "victory needs a pre-Meiji change (earliest %d)" % earliest)
		# 6. 勝った世界：エンディング・満点
		var ending := st.compose_ending()
		_check(String(ending[1]).contains("太平洋戦争：勝利"), "ending mentions the victory tier")
		var showa_changed: Array = db.questions.filter(func(q): return q["era"]["eraId"] == "showa" and st.is_altered(q)).map(func(q): return q["id"])
		print("victory world: showa facts changed: %s" % [showa_changed])
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for q in db.questions:
			st.answers[q["id"]] = rng.randi_range(0, 3)
		for q in db.questions:
			if not st.is_correct(q):
				st.apply_change(q, st.answer(q), "test")
		_check(st.perfect(), "victory world: chronological repair -> 100点")
	# 別の勝ち筋（戦国より前に触れず、江戸以降だけで勝てるか）
	var st_b := HistoryState.new(db)
	var later: Array = all_ids.filter(func(p): return db.projects[p]["era"] in ["edo", "meiji_taisho", "showa"])
	var win2 := _greedy(st_b, db, later, "勝利", func(s): return float(s.war["score"]))
	if win2.is_empty():
		_apply_set(st_b, db, later)
		print("edo+meiji+showa only: best %s (score %.1f) — no victory without changes before Edo" % [st_b.war_tier(), st_b.war["score"]])
	else:
		print("edo+ strategy: %s" % [win2[0]])
	# 4. 開戦回避
	var st2 := HistoryState.new(db)
	var avoid := _greedy(st2, db, all_ids, "開戦回避", func(s): return minf(float(s.war["pillars"]["diplomacy"]) - 55.0, float(s.war["pillars"]["politics"]) - 45.0), saves)
	_check(not avoid.is_empty(), "a no-war path exists")
	if not avoid.is_empty():
		print("no-war path: projects %s + %s" % [avoid[0], (avoid[1] as Array).map(func(a): return a["verb"] + ":" + a["target"])])
	# 5. ファズ
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	var tiers := {}
	for trial in 60:
		var pick: Array = all_ids.filter(func(_p): return rng2.randf() < 0.35)
		_apply_set(st2, db, pick)
		tiers[st2.war_tier()] = int(tiers.get(st2.war_tier(), 0)) + 1
		_check(st2.war_tier() != "", "fuzz: tier resolved")
		for q in db.questions:
			var c := st2.world_choice(q)
			_check(c >= 0 and c <= 3, "fuzz: valid choice")
		st2.save()
		var st3 := HistoryState.new(db)
		st3.load_save()
		_check(st3.war_tier() == st2.war_tier(), "fuzz: save/load keeps war tier")
	print("fuzz tiers: ", tiers)
	_standing_tests(db)
	HistoryState.delete_save()
	await _integration()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)


## 国際的地位の推移
func _standing_tests(db: HistoryDB) -> void:
	var sm: Dictionary = db.standing_model
	_check(not sm.is_empty(), "standing model loaded")
	var st := HistoryState.new(db)
	for p in st.standing["points"]:
		_check(absf(float(p["score"]) - float(p["base"])) < 0.01 and p["tier"] == p["base_tier"], "untouched history reproduces the real standing at %d" % p["year"])
	_check(not WarModel.power_by(st.standing, sm, 1853), "historically not a power before 1853")
	_check(WarModel.power_by(st.standing, sm, 1919), "historically a power by 1919")
	# 1つの行動では1853年より前に列強にならない（事業・鎖国をしない）
	for pid in db.projects:
		_apply_set(st, db, [pid])
		_check(not WarModel.power_by(st.standing, sm, 1800), "single project %s does not make Japan a power before 1853" % pid)
	st.actions = []
	st.interventions = {"edo_05": {"choice": 0, "method": 0, "seq": 1}}
	st.recompute()
	_check(not WarModel.power_by(st.standing, sm, 1800), "not adopting sakoku alone is not enough")
	# 深い戦略（貪欲）：1700年までに列強の一角
	var cands: Array = db.projects.keys().filter(func(p): return int(db.projects[p]["year"]) < 1700)
	var goal := func(s2: HistoryState) -> float:
		for p in s2.standing["points"]:
			if int(p["year"]) == 1700:
				return float(p["score"])
		return 0.0
	var chosen: Array = []
	var found := false
	for step in 40:
		_apply_set(st, db, chosen)
		if WarModel.power_by(st.standing, sm, 1700):
			found = true
			break
		var best := ""
		var bv := -1e9
		for pid in cands:
			if pid in chosen or not WarModel.available(db, st.actions, st.war["pillars"], pid)[0]:
				continue
			_apply_set(st, db, chosen + [pid])
			var v: float = goal.call(st)
			if v > bv:
				bv = v
				best = pid
		if best == "":
			break
		chosen.append(best)
	_check(found, "a multi-era strategy makes Japan a great power by 1700")
	if found:
		var eras := {}
		var lines: PackedStringArray = []
		chosen.sort_custom(func(a, b): return int(db.projects[a]["year"]) < int(db.projects[b]["year"]))
		for pid in chosen:
			eras[db.projects[pid]["era"]] = true
			lines.append("%d年 %s" % [db.projects[pid]["year"], db.projects[pid]["name"]])
		print("great power by 1700 (%d projects, %d eras, + no sakoku):\n  %s" % [chosen.size(), eras.size(), "\n  ".join(lines)])
		_check(eras.size() >= 4, "power by 1700 needs foundations from several eras (%d)" % eras.size())
		var curve: PackedStringArray = []
		for p in st.standing["points"]:
			curve.append("%d:%s" % [p["year"], p["tier"]])
		print("  curve: ", " → ".join(curve))
		# 1853年に列強なら、ペリー来航と条約が変わる
		var s1853: Dictionary = {}
		for p in st.standing["points"]:
			if int(p["year"]) == 1853:
				s1853 = p
		if float(s1853.get("score", 0.0)) >= 65.0:
			_check(st.world_choice(db.by_id["edo_04"]) == 1, "a great power in 1853 gets an equal treaty (edo_04 → ①)")
		else:
			print("  (1853 score %d: below 65, Perry consequence not tested in this strategy)" % int(s1853.get("score", 0.0)))
		var ending := st.compose_ending()
		_check(String(ending[1]).contains("日本の国際的地位"), "ending mentions the standing")
	# 江戸までの事業をすべて＋鎖国なし → 1853年に列強の一角なら、ペリーは対等の交渉を求め、条約は関税自主権つきに
	var pre1853: Array = db.projects.keys().filter(func(p): return int(db.projects[p]["year"]) < 1853)
	pre1853.sort_custom(func(a, b): return int(db.projects[a]["year"]) < int(db.projects[b]["year"]))
	_apply_set(st, db, pre1853)
	var sc53 := 0.0
	for p in st.standing["points"]:
		if int(p["year"]) == 1853:
			sc53 = float(p["score"])
	print("all projects before 1853 + no sakoku: 1853 standing %d, edo_04 = %d" % [int(sc53), st.world_choice(db.by_id["edo_04"])])
	_check(sc53 >= 65.0, "deep strategy makes Japan a power in 1853")
	_check(st.world_choice(db.by_id["edo_04"]) == 1, "a great power in 1853 gets an equal treaty (edo_04 → ①)")
	st.interventions = {}
	st.actions = []
	st.recompute()


func _integration() -> void:
	var G: Node = root.get_node_or_null("Game")
	if G == null:
		return
	G.set_meta("force_fallback_world", true)
	G.state.reset_all()
	var S: GDScript = load("res://scripts/mission/session.gd")
	var sess: Node = S.start_free_roam("edo")
	root.add_child(sess)
	await _frames(5)
	var n := WarModel.projects_for(G.db, "edo").size()
	_check(sess.interact.sites.size() == n, "edo free roam has %d project sites (%d)" % [n, sess.interact.sites.size()])
	var site = null
	for s in sess.interact.sites:
		if s.project["id"] == "ed_shuinsen":
			site = s
	_check(site != null, "朱印船 site exists")
	if site:
		var before: String = G.state.war_tier()
		sess.interact._finish_project(site)
		await _frames(2)
		_check(WarModel.is_done(G.state.actions, "ed_shuinsen"), "project recorded")
		_check(float(G.state.war["pillars"]["resources"]) > 8.0, "朱印船 raised resources (%.1f)" % G.state.war["pillars"]["resources"])
		_check(site.done, "site shows done")
		print("integration: war %s -> %s" % [before, G.state.war_tier()])
	sess.end()
	await _frames(2)
	G.state.reset_all()
	G.remove_meta("force_fallback_world")
