extends SceneTree
## ヘッドレス: godot --headless --path . -s tests/test_chaos.gd
## 自由探索の「歴史の揺らぎ」（data/chaos・ChaosTracker・HistoryState.apply_chaos）を検証する。
##  1. 全ルールについて、条件どおりの出来事を起こすと発動し、介入／パラメータ変化が入り、再計算されること
##  2. しきい値（兵の撃破 30 など）・二重発動の防止・修正力を数えないこと・自由探索外では無効なこと
##  3. セーブ／ロードで混乱が保たれること
##  4. 混乱で崩れた解答に修復ミッションがあり、年代順に直せば満点になること
##  5. 実際の Session（自由探索）で人物を倒す → 歴史が揺らぐ → HUD 通知 → 混乱版のアフター画面・ハブが組めること

var fails := 0
var _backup = null


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL ", msg)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fresh(db: HistoryDB) -> HistoryState:
	var st := HistoryState.new(db)
	for q in db.questions:
		st.answers[q["id"]] = q["real"]
	st.exam_submitted = true
	return st


## ルールの最初の条件を満たす出来事を起こす
func _fire_rule(tr: ChaosTracker, era: String, r: Dictionary) -> Array:
	var t: Variant = r["trigger"]
	var c: Dictionary = t[0] if t is Array else t
	var kind: String = c["kind"]
	var id := ""
	if c.has("id"):
		id = str(c["id"][0]) if c["id"] is Array else str(c["id"])
	var info := {"era": era}
	if c.has("type"):
		info["type"] = str(c["type"][0]) if c["type"] is Array else str(c["type"])
	elif kind == "kill":
		info["type"] = "figure"
	if c.has("at"):
		info["landmark"] = c["at"]
	for k in ["arg", "item", "to", "event", "side", "cause"]:
		if c.has(k):
			info[k] = str(c[k][0]) if c[k] is Array else str(c[k])
	var need := int(c.get("min", 1))
	var hits: Array = []
	if c.has("value"):
		# 建物1棟ずつ（格 100）壊していく
		var left := int(c["value"])
		while left > 0:
			info["value"] = mini(left, 100)
			left -= 100
			hits.append_array(tr.record(kind, id, info.duplicate()))
	elif kind == "fire":
		# 延焼数は名所ごとの累計（5 → 12 → 24）
		for n in [mini(5, need), need]:
			info["count"] = n
			hits.append_array(tr.record(kind, str(c.get("at", "town")), info.duplicate()))
	else:
		for i in need:
			hits.append_array(tr.record(kind, id if id != "" else "兵", info))
	return hits


func _run() -> void:
	HistoryState.save_path = "user://test_chaos_save.json"   # 本物のセーブや並行テストに触れない
	var db := HistoryDB.load_all()
	var tr := ChaosTracker.new(db, null)
	_check(tr.errors.is_empty(), "chaos json errors: %s" % [tr.errors])
	var total := 0
	var rippling := 0
	var forced_n := 0
	var restore_missions := 0
	for e in db.eras:
		var era: String = e["eraId"]
		var rules := tr.rules_for(era)
		_check(rules.size() >= 6, "%s: rules >= 6 (got %d)" % [era, rules.size()])
		_check(tr.figures_for(era).size() >= 3, "%s: figures >= 3" % era)
		var npcs := {}
		for q in e["questions"]:
			for m in q.get("missions", []):
				for s in m["steps"]:
					if s.has("npc"):
						npcs[s["npc"]] = true
		for f in tr.figures_for(era):
			_check(npcs.has(f["name"]) or db.actor_name(f["name"]) != "", "%s: figure %s is a mission NPC or an actor" % [era, f["name"]])
		for r in rules:
			total += 1
			var st := _fresh(db)
			tr.state = st
			tr.begin_session(era)
			var hits := _fire_rule(tr, era, r)
			var mine := hits.filter(func(h): return h["id"] == r["id"])
			_check(mine.size() == 1, "%s: fires once (got %d of %d hits)" % [r["id"], mine.size(), hits.size()])
			if mine.is_empty():
				continue
			var hit: Dictionary = mine[0]
			var solo := hits.size() == 1
			# 再計算結果が simulate と一致
			var sim := st.simulate(st.interventions)
			for q in db.questions:
				_check(sim["world"][q["id"]] == st.world_choice(q), "%s: recompute consistent %s" % [r["id"], q["id"]])
			# force
			var fs: Variant = r.get("force", [])
			for f in (fs if fs is Array else [fs]):
				forced_n += 1
				var q: Dictionary = db.by_id[f["q"]]
				_check(st.is_chaos(q), "%s: intervention cause chaos" % r["id"])
				if solo:
					_check(st.world_choice(q) == int(f["choice"]), "%s: forced choice" % r["id"])
					_check(not st.is_correct(q), "%s: forced answer broken" % r["id"])
					_check(hit["broke"], "%s: broke flag" % r["id"])
			if r.has("vars"):
				var has := false
				for m in st.chaos_mods:
					if m["rule"] == r["id"]:
						has = true
				_check(has, "%s: chaos mod stored" % r["id"])
			if not hit["changes"].is_empty():
				rippling += 1
			# 変化一覧は旧世界（史実）との差と一致
			var diff := 0
			for q in db.questions:
				if st.world_choice(q) != q["real"]:
					diff += 1
					_check(st.is_chaos_touched(q), "%s: chaos_touched %s" % [r["id"], q["id"]])
			if solo:
				_check(diff == hit["changes"].size(), "%s: changes == diff (%d vs %d)" % [r["id"], hit["changes"].size(), diff])
			# 同じセッションでもう一度起こしても二重に発動しない
			_check(not _fire_rule(tr, era, r).any(func(h): return h.get("id", "") == r["id"]), "%s: no double fire" % r["id"])
			tr.end_session()
			# 次の自由探索でも、効果が残っている限り発動しない
			tr.begin_session(era)
			_check(not _fire_rule(tr, era, r).any(func(h): return h.get("id", "") == r["id"]), "%s: in effect -> no refire" % r["id"])
			tr.end_session()
			# セーブ／ロード
			st.save()
			var st2 := HistoryState.new(db)
			_check(st2.load_save(), "%s: load_save" % r["id"])
			for q in db.questions:
				_check(st2.world_choice(q) == st.world_choice(q), "%s: save/load world %s" % [r["id"], q["id"]])
				_check(st2.is_chaos(q) == st.is_chaos(q), "%s: save/load chaos flag %s" % [r["id"], q["id"]])
			_check(st2.chaos_mods.size() == st.chaos_mods.size(), "%s: save/load mods" % r["id"])
			# 修復：崩れた問題には修復ミッションがあり、年代順に直せば満点
			for q in st.chaos_broken():
				var m := db.mission_for(q, st.answer(q))
				_check(not m.get("steps", []).is_empty(), "%s: restore mission for %s" % [r["id"], q["id"]])
				restore_missions += 1
			for q in db.questions:
				if not st.is_correct(q):
					var m2 := db.mission_for(q, st.answer(q))
					st.apply_change(q, st.answer(q), m2["title"])
			_check(st.perfect(), "%s: chronological repair -> perfect" % r["id"])
			_check(st.chaos_broken().is_empty(), "%s: nothing broken after repair" % r["id"])
			for f in (fs if fs is Array else [fs]):
				_check(not st.is_chaos(db.by_id[f["q"]]), "%s: mission overrides chaos" % r["id"])
	print("chaos rules=%d (rippling %d, forced %d), restore missions checked=%d" % [total, rippling, forced_n, restore_missions])
	_check(total >= 60, "total rules >= 60")

	# しきい値・修正力・無効時
	var st3 := _fresh(db)
	tr.state = st3
	_check(tr.record("kill", "織田信長", {"era": "sengoku", "type": "figure"}).is_empty(), "inactive tracker ignores events")
	tr.begin_session("sengoku")
	for i in 29:
		tr.record("kill", "足軽の追手", {"era": "sengoku", "type": "soldier"})
	for i in 10:
		tr.record("kill", "歴史の修正力", {"era": "sengoku", "type": "guardian"})
	_check(st3.chaos_mods.is_empty(), "29 soldiers + guardians do not trigger massacre")
	var h30 := tr.record("kill", "足軽の追手", {"era": "sengoku", "type": "soldier"})
	_check(h30.size() == 1 and h30[0]["id"] == "sg_massacre", "30th soldier triggers massacre")
	_check(tr.record("kill", "織田信長", {"era": "heian", "type": "figure"}).is_empty(), "other era event ignored")
	_check(not tr.record("fire", "village", {"era": "sengoku", "count": 12}).any(func(h): return h["id"] == "sg_fire_kyoto"), "fire elsewhere does not burn Honno-ji")
	_check(tr.record("fire", "capital", {"era": "sengoku", "count": 3}).is_empty(), "fire 3 < 5 at capital")
	var hf := tr.record("fire", "capital", {"era": "sengoku", "count": 5})
	_check(hf.size() == 1 and hf[0]["id"] == "sg_fire_kyoto", "fire count reaches 5 at capital")
	# 天守ではない家を1軒壊しても大坂城の崩落にはならない
	_check(tr.record("destroy", "castle", {"era": "sengoku", "type": "house", "value": 30}).is_empty(), "one house is not the castle")
	var hk := tr.record("destroy", "castle", {"era": "sengoku", "type": "castle_keep", "value": 5000})
	_check(hk.size() == 1 and hk[0]["id"] == "sg_destroy_osaka", "castle keep destroyed -> Osaka rule")
	_check(tr.session_changes().size() > 0, "session_changes")
	tr.end_session()
	_check(tr.session_hits.filter(func(h): return h.has("rule")).size() == 3, "session hits kept after end")
	# predict_ripple は混乱を含めて予測する
	var q05: Dictionary = db.by_id["sengoku_05"]
	_check(st3.world_choice(q05) == 0, "fire forced sengoku_05=0")
	var rip := st3.predict_ripple(q05, q05["real"])
	_check(rip is Array, "predict_ripple works with chaos")
	# 終章の文章
	var ending := st3.compose_ending()
	_check(String(ending[1]).contains("自由探索での混乱"), "ending mentions chaos")

	_generic_tests(db)
	await _integration()
	HistoryState.delete_save()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)


## 一般則（HistoryActors）：どの人物にどの動詞を使っても解決すること、どの問題×選択肢にも行動だけで届くこと
func _generic_tests(db: HistoryDB) -> void:
	_check(db.actors.size() >= 140, "actors loaded (%d)" % db.actors.size())
	_check(db.actor_name("老中 田沼意次") == "田沼意次" and db.actor_name("羽柴秀吉") == "豊臣秀吉" and db.actor_name("厩戸王（聖徳太子）") == "厩戸王", "actor alias resolution")
	var tr := ChaosTracker.new(db, null)
	# ファズ：時代ごとにランダムな動詞×人物
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var verbs := ["kill", "escort", "protect", "persuade", "give", "steal", "forge", "delay", "steer"]
	var by_era := {}
	for nm in db.actors:
		var e: String = db.actors[nm]["era"]
		if not by_era.has(e):
			by_era[e] = []
		by_era[e].append(nm)
	var applied := 0
	for trial in 40:
		var st := _fresh(db)
		tr.state = st
		for e in db.eras:
			var era: String = e["eraId"]
			tr.begin_session(era)
			for k in 6:
				var nm: String = by_era[era][rng.randi() % by_era[era].size()]
				var verb: String = verbs[rng.randi() % verbs.size()]
				var info := {}
				match verb:
					"persuade": info["arg"] = HistoryActors.ARGS.keys()[rng.randi() % HistoryActors.ARGS.size()]
					"give": info["item"] = HistoryActors.ITEMS.keys()[rng.randi() % HistoryActors.ITEMS.size()]
					"escort": info["to"] = HistoryDB.LANDMARK_KEYS[rng.randi() % 7]
					"delay": info["event"] = "大事な会合"
					"steer":
						var qs: Array = e["questions"]
						var q: Dictionary = qs[rng.randi() % qs.size()]
						info["q"] = q["id"]
						info["choice"] = rng.randi() % 4
				if verb == "kill":
					info["type"] = "figure"
					info["cause"] = ["shot", "stray", "explosion", "fire", "horse", "crossfire"][rng.randi() % 6]
				tr.act(verb, nm, info)
				applied += 1
			tr.end_session()
		for q in db.questions:
			var c := st.world_choice(q)
			_check(c >= 0 and c <= 3, "fuzz: valid choice %s" % q["id"])
		var sim := st.simulate(st.interventions)
		for q in db.questions:
			_check(sim["world"][q["id"]] == st.world_choice(q), "fuzz: recompute consistent")
		st.save()
		var st2 := HistoryState.new(db)
		st2.load_save()
		for q in db.questions:
			_check(st2.world_choice(q) == st.world_choice(q), "fuzz: save/load %s" % q["id"])
		# 行動だけ（ミッションなし）で年代順に直せば満点
		for q in db.questions:
			st.answers[q["id"]] = rng.randi_range(0, 3)
		for q in db.questions:
			if not st.is_correct(q):
				_steer(tr, st, db, q, st.answer(q))
		_check(st.perfect(), "fuzz %d: 100点 by free actions only (%d/%d)" % [trial, st.correct_count(), db.questions.size()])
		var mission_ivs := 0
		for k2 in st.interventions:
			if not (str(st.interventions[k2].get("cause", "")) in ["chaos", "actor"]):
				mission_ivs += 1
		_check(mission_ivs == 0, "fuzz: no mission interventions used")
	print("generic fuzz: %d actions applied" % applied)
	# すべての問題×選択肢に「未来を語る」で届く
	var reach := 0
	for q in db.questions:
		for c in 4:
			var st3 := _fresh(db)
			tr.state = st3
			_steer(tr, st3, db, q, c)
			if st3.world_choice(q) == c:
				reach += 1
			else:
				_check(false, "reach %s choice %d" % [q["id"], c])
	print("reachable question×choice by free actions: %d / %d" % [reach, db.questions.size() * 4])
	# 個別の一般則
	var st4 := _fresh(db)
	tr.state = st4
	tr.begin_session("sengoku")
	var h1 := tr.record("kill", "徳川家康", {"era": "sengoku", "type": "figure", "cause": "stray"})
	_check(h1.size() == 1 and str(h1[0]["title"]).contains("流れ弾"), "accidental kill attributed to stray bullet")
	var h2 := tr.record("delay", "織田信長", {"era": "sengoku", "event": "本能寺に入る", "cause_text": "引き止めた"})
	_check(h2.size() == 1 and st4.world_choice(db.by_id["sengoku_05"]) == 0, "delay Nobunaga -> survives Honno-ji")
	for i in 5:
		tr.record("kill", "東軍の兵", {"era": "sengoku", "type": "soldier"})
	var bt := st4.actions.filter(func(a): return a["verb"] == "battle")
	_check(bt.size() == 1 and bt[0]["side"] == "西軍", "killing 5 East soldiers helps the West")
	for i in 5:
		tr.record("destroy", "mountain", {"era": "sengoku", "type": "hall", "value": 100})
	_check(st4.actions.any(func(a): return a["verb"] == "sabotage" and a["target"] == "mountain"), "generic sabotage of an unruled landmark")
	var ref := tr.act("persuade", "徳川家光", {"arg": "開国を勧める"})
	tr.end_session()
	tr.begin_session("edo")
	ref = tr.act("persuade", "徳川家光", {"arg": "開国を勧める"})
	_check(ref.get("refused", false), "closed-minded Iemitsu refuses opening the country")
	var sv := tr.act("protect", "坂本龍馬", {})
	_check(not sv.is_empty() and st4.final_state.get("democracy", 0.0) >= 10.0, "saving Ryoma -> democracy up")
	var st5 := _fresh(db)
	tr.state = st5
	tr.begin_session("heian")
	tr.act("kill", "藤原良房", {"type": "figure"})
	var a5: Dictionary = st5.actions[-1]
	_check(str(a5.get("text", "")).contains("藤原基経"), "successor takes over (%s)" % a5.get("text", ""))
	tr.end_session()
	HistoryState.delete_save()


## 未来の教科書を渡して信頼を得てから「未来を語る」（行動だけで問題 q を choice にする）
func _steer(tr: ChaosTracker, st: HistoryState, db: HistoryDB, q: Dictionary, c: int) -> void:
	var cands: Array = db.q_actors.get(q["id"], [])
	if cands.is_empty():
		_check(false, "no actor for %s" % q["id"])
		return
	var nm: String = cands[0]["name"]
	tr.begin_session(q["era"]["eraId"])
	if tr.trust(nm) == 0:
		tr.act("give", nm, {"item": "未来の教科書"})
	if st.world_choice(q) != c:
		tr.act("steer", nm, {"q": q["id"], "choice": c})
	tr.end_session()


## 実際の自由探索セッションで人物を倒す
func _integration() -> void:
	var G: Node = root.get_node_or_null("Game")
	if G == null:
		print("Game autoload missing: skip integration")
		return
	G.set_meta("force_fallback_world", true)
	G.state.reset_all()
	for q in G.db.questions:
		G.state.answers[q["id"]] = q["real"]
	G.state.exam_submitted = true
	G.state.recompute()
	# Game を参照するスクリプトは autoload の登録後に読み込む（-s 実行時の静的参照は解決できない）
	var S: GDScript = load("res://scripts/mission/session.gd")
	var E: GDScript = load("res://scripts/mission/enemy.gd")
	var sess: Node = S.start_free_roam("sengoku")
	root.add_child(sess)
	await _frames(5)
	var specs: Array = G.chaos.figures_for("sengoku")
	_check(sess.figures.size() <= sess.MAX_FIGS, "figure population capped (%d near the player)" % sess.figures.size())
	sess.spawn_all_figures()
	await _frames(2)
	_check(sess.figures.size() == S.figure_specs("sengoku").size() and sess.figures.size() >= specs.size(), "free roam spawns figures (%d)" % sess.figures.size())
	_check(sess.interact != null, "actor interaction node")
	for q in G.db.questions:
		if q["era"]["eraId"] == "sengoku":
			_check(sess.figures.any(func(f): return q["id"] in f.questions), "a free-roam figure can be told the future of %s" % q["id"])
	# 会話メニューから：渡す → 未来を語る（sengoku_03 を別の選択肢へ）
	var q03: Dictionary = G.db.by_id["sengoku_03"]
	var talker = null
	for f in sess.figures:
		if "sengoku_03" in f.questions:
			talker = f
	if talker:
		sess.interact.open(talker)
		sess.interact._do("give", {"item": "未来の教科書"})
		sess.interact.open(talker)
		sess.interact._do("steer", {"q": "sengoku_03", "choice": 0})
		await _frames(2)
		_check(G.state.world_choice(q03) == 0, "menu: give + tell the future rewrites sengoku_03")
		_check(not sess.interact.is_open(), "menu closed after action")
	_check(G.chaos.is_active() and G.chaos.active_era == "sengoku", "chaos session active")
	var nobu = null
	for f in sess.figures:
		if f.figure_name == "織田信長":
			nobu = f
	_check(nobu != null and nobu.guards.size() > 0, "Nobunaga with guards")
	if nobu:
		nobu.take_hit(9999.0, 0, nobu.global_position)
		await _frames(3)
		_check(nobu.dead, "Nobunaga died")
		var q05: Dictionary = G.db.by_id["sengoku_05"]
		_check(G.state.is_chaos(q05) and G.state.world_choice(q05) == 3, "killing Nobunaga -> Mori restore shogunate")
		_check(sess.hud.is_history_shift_showing(), "HUD history_shift shown")
	# 兵の撃破（Enemy._die → kill/soldier）
	var e = E.spawn(sess, sess.world.landmark_pos("battlefield") + Vector3.UP, "足軽の追手", "sengoku")
	await _frames(2)
	var before: int = G.chaos.events.size()
	e.take_hit(9999.0, 0)
	await _frames(2)
	_check(G.chaos.events.size() == before + 1 and G.chaos.events[-1]["type"] == "soldier", "enemy death emits kill/soldier")
	# 破壊担当の信号（城下町の破壊）
	for i in 10:
		G.chaos_event.emit("destroy", "village", {"era": "sengoku", "type": "house", "value": 30, "pos": sess.world.landmark_pos("village")})
	await _frames(2)
	_check(G.state.is_chaos(G.db.by_id["sengoku_02"]), "destroy village -> sengoku_02 chaos")
	var hits: Array = G.chaos.session_hits.duplicate()
	sess.end()
	await _frames(2)
	_check(not G.chaos.is_active(), "chaos session ended")
	_check(hits.size() >= 2, "session hits recorded (%d)" % hits.size())
	# 混乱版のアフター画面・ハブ
	var A := load("res://scripts/ui/aftermath_screen.gd")
	var a: Control = A.new()
	a.chaos_hits = hits
	a.chaos_era = "sengoku"
	a.changes = G.chaos.session_changes()
	a.score_before = 100
	a.correct_before = G.db.questions.size()
	root.add_child(a)
	await _frames(2)
	_check(a.get_child_count() > 0, "chaos aftermath builds")
	a.queue_free()
	var H := load("res://scripts/ui/hub_screen.gd")
	var h: Control = H.new()
	root.add_child(h)
	await _frames(2)
	_check(G.state.chaos_broken().size() >= 2, "hub: chaos broke answers (%d)" % G.state.chaos_broken().size())
	h.queue_free()
	await _frames(2)
	print("integration: figures=%d hits=%d broken=%d" % [specs.size(), hits.size(), G.state.chaos_broken().size()])
	G.state.reset_all()
	G.remove_meta("force_fallback_world")
