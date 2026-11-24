extends Node
## 時代の中の年（data/eras/<era>_timeline.json・scripts/core/era_timeline.gd）の検査。
## godot --headless --path . res://tests/test_timeline.tscn [-- --no-world]
##  1. データ：全時代に時点・代表の年・範囲。問題の年が範囲内。時点の説明に年の入った史実
##  2. 人物：生没年・活動の外には出ない（救った人だけ没年の後も）。倒した年から先にいない。年齢の区分
##  3. 船：年ごとの港の船（朱印船・サスケハナ・咸臨丸・三笠・赤城/加賀・大和・氷川丸）
##  4. ミッションの年＝問題の年
##  5. 別解を失わない：手作りの道（data/chaos のルール・人物の動詞・予定・合戦・国家事業・各問題の「未来を語る」相手）は、
##     その時代のどこかの時点で必ず起こせる（人物がいる・名所の建物/船が足りる・合戦/事業が現れる）
##  6. 前の年に壊した建物は後の年にも壊れたまま（記録・保存・建て直し）。実際の箱庭でも（江戸 1615/1700/1853）

var fails := 0
var checks := 0
var db: HistoryDB


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)


func _run() -> void:
	db = Game.db
	EraTimeline.clear_cache()
	_data()
	_actors()
	_ships()
	_missions()
	_coverage()
	_ruins_state()
	if not ("--no-world" in OS.get_cmdline_user_args()):
		await _worlds()
	print("RESULT: %s (%d checks, %d failed)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	get_tree().quit(0 if fails == 0 else 1)


# ------------------------------------------------------------------ 1
func _data() -> void:
	var digit := RegEx.create_from_string("[0-9]{2,4}年")
	for e in db.eras:
		var id: String = e["eraId"]
		var pts := EraTimeline.points(id)
		_check(pts.size() >= 4, "%s has >= 4 time points (%d)" % [id, pts.size()])
		var ys := EraTimeline.years(id)
		_check(EraTimeline.default_year(id) in ys, "%s default year is a time point" % id)
		var rg := EraTimeline.year_range(id)
		for y in ys:
			_check(int(y) >= int(rg[0]) and int(y) <= int(rg[1]), "%s point %d within range %s" % [id, y, rg])
		for p in pts:
			_check(str(p.get("label", "")) != "" and str(p.get("basis", "")) != "", "%s %d has label and basis" % [id, p["year"]])
			_check(digit.search(str(p.get("desc", ""))) != null or int(p["year"]) < 0, "%s %d desc is dated" % [id, p["year"]])
		for q in e.get("questions", []):
			_check(int(q["year"]) >= int(rg[0]) and int(q["year"]) <= int(rg[1]), "%s question %s year %d within era range" % [id, q["id"], q["year"]])


# ------------------------------------------------------------------ 2
func _actors() -> void:
	var n := 0
	for e in db.eras:
		var id: String = e["eraId"]
		for nm in db.actors:
			var a: Dictionary = db.actors[nm]
			for y in EraTimeline.years(id):
				if not EraTimeline.actor_present(db, [], a, id, int(y)):
					continue
				n += 1
				if a.get("born") != null:
					var young_death: bool = a.get("died") != null and int(a["died"]) < int(a["born"]) + EraTimeline.MIN_AGE   # 幼くして没した（宋の順帝など）
					_check(int(y) >= int(a["born"]) + EraTimeline.MIN_AGE or (young_death and int(y) >= int(a["born"])), "%s not shown before age 15 (%s %d)" % [nm, id, y])
				if a.get("died") != null:
					_check(int(y) <= int(a["died"]), "%s not shown after death (%s %d)" % [nm, id, y])
	print("actor presences checked: %d" % n)
	var ryoma := db.actor("坂本龍馬")
	var ieyasu_era := "edo"
	_check(not EraTimeline.actor_present(db, [], ryoma, ieyasu_era, 1615) and not EraTimeline.actor_present(db, [], ryoma, "edo", 1700), "Ryoma absent in 1615/1700")
	_check(EraTimeline.actor_present(db, [], ryoma, "edo", 1853) and EraTimeline.actor_present(db, [], ryoma, "edo", 1867), "Ryoma present in 1853/1867")
	var hide := db.actor("豊臣秀頼")
	_check(EraTimeline.actor_present(db, [], hide, "edo", 1615) and not EraTimeline.actor_present(db, [], hide, "edo", 1638), "Hideyori in 1615 only")
	# 徳川家康（1616 没）と坂本龍馬（1836 生）が同じ年に並ぶことはない
	var ie := db.actor("徳川家康")
	if not ie.is_empty():
		for e in db.eras:
			for y in EraTimeline.years(e["eraId"]):
				_check(not (EraTimeline.actor_present(db, [], ie, e["eraId"], y) and EraTimeline.actor_present(db, [], ryoma, e["eraId"], y)), "Ieyasu and Ryoma never coexist (%s %d)" % [e["eraId"], y])
	# 救った人は没年の後もいる
	var ii := db.actor("井伊直弼")
	_check(not EraTimeline.actor_present(db, [], ii, "edo", 1867), "Ii Naosuke absent in 1867 (d.1860)")
	var saved := [{"verb": "protect", "target": "井伊直弼", "era": "edo", "year": 1860, "seq": 1}]
	_check(EraTimeline.actor_present(db, saved, ii, "edo", 1867), "saved Ii Naosuke still alive in 1867")
	# 倒した年から先にはいない（それより前の年にはまだいる）
	var sada := db.actor("松平定信")
	var killed := [{"verb": "kill", "target": "松平定信", "era": "edo", "year": 1792, "seq": 2}]
	_check(EraTimeline.actor_present(db, killed, sada, "edo", 1783) and not EraTimeline.actor_present(db, killed, sada, "edo", 1792), "killed in 1792: present 1783, absent 1792")
	var old_kill := [{"verb": "kill", "target": "松平定信", "era": "edo", "seq": 3}]
	_check(not EraTimeline.actor_present(db, old_kill, sada, "edo", 1783), "kill without a year (old save) removes the actor in that era")
	var prev_era := [{"verb": "kill", "target": "高橋是清", "era": "meiji_taisho", "year": 1905, "seq": 4}]
	_check(not EraTimeline.actor_present(db, prev_era, db.actor("高橋是清"), "showa", 1927), "killed in Meiji -> absent in Showa")
	# 年齢
	_check(EraTimeline.age_class(EraTimeline.actor_age(ryoma, 1853)) == "young" and EraTimeline.age_class(EraTimeline.actor_age(db.actor("杉田玄白"), 1817 - 1)) == "elder", "age classes")
	# 予定は人物がいる時点に（井伊直弼 1860 桜田門 → 1860 の時点）
	var sch := EraTimeline.schedules_at(db, [], ii, "edo", 1860)
	_check(sch.size() == 1 and EraTimeline.schedules_at(db, [], ii, "edo", 1853).is_empty(), "Ii's 1860 appointment at the 1860 point only")


# ------------------------------------------------------------------ 3
func _ships() -> void:
	var f := func(era: String, y: int) -> Array: return ShipYard.ships_for(era, y)
	_check(f.call("edo", 1615) == ["shuinsen"], "edo 1615: 朱印船 (%s)" % [f.call("edo", 1615)])
	_check(f.call("edo", 1700).is_empty(), "edo 1700: no big ships")
	_check(f.call("edo", 1853) == ["susquehanna"], "edo 1853: 黒船 only (%s)" % [f.call("edo", 1853)])
	_check("kanrin_maru" in f.call("edo", 1860) and "susquehanna" in f.call("edo", 1860), "edo 1860: 咸臨丸 and サスケハナ")
	_check(not ("susquehanna" in f.call("edo", 1792)), "no 黒船 before 1853")
	_check(f.call("meiji_taisho", 1889).is_empty() and f.call("meiji_taisho", 1905) == ["mikasa"] and f.call("meiji_taisho", 1923) == ["mikasa"], "三笠 1902–1923")
	var s31: Array = f.call("showa", 1931)
	_check("akagi" in s31 and "kaga" in s31 and "hikawa_maru" in s31 and not ("yamato" in s31), "showa 1931: 赤城・加賀・氷川丸, no 大和")
	_check((f.call("showa", 1941) as Array).size() == 4, "showa 1941: all four")
	var s45: Array = f.call("showa", 1945)
	_check("yamato" in s45 and not ("akagi" in s45), "showa 1945: 大和 (Apr), carriers lost at Midway")
	_check(f.call("showa", 1964) == ["hikawa_maru"], "showa 1964: 氷川丸 only")
	_check(not ("nanban_nau" in f.call("sengoku", 1543)) and "nanban_nau" in f.call("sengoku", 1582), "南蛮船 from 1550")
	_check(f.call("edo", 0).size() == 3, "year 0 = all ships of the era (backward compatible)")
	# 建物の有無
	_check(EraTimeline.absent_rules("edo", 1615).is_empty() and EraTimeline.absent_rules("edo", 1700).size() == 1, "江戸城天守 absent from 1657")
	_check(EraTimeline.absent_rules("meiji_taisho", 1871).size() >= 1 and EraTimeline.absent_rules("meiji_taisho", 1923).is_empty(), "Meiji brick buildings appear after 1872")


# ------------------------------------------------------------------ 4
func _missions() -> void:
	var S: GDScript = load("res://scripts/mission/session.gd")
	for q in db.questions:
		_check(int(S.mission_year(q)) == int(q["year"]), "mission %s starts at its year" % q["id"])
		_check(not EraTimeline.point_for(q["era"]["eraId"], int(q["year"])).is_empty(), "mission %s has a governing time point" % q["id"])
	var q0: Dictionary = db.by_id["edo_04"]
	var s: Node = S.start_mission(q0, q0["real"])
	_check(int(s.year) == 1858, "Session.start_mission(edo_04).year == 1858")
	s.free()
	var fr: Node = S.start_free_roam("edo")
	_check(int(fr.year) == EraTimeline.default_year("edo"), "free roam default year")
	fr.free()
	var fr2: Node = S.start_free_roam("edo", 1853)
	_check(int(fr2.year) == 1853, "free roam chosen year")
	fr2.free()


# ------------------------------------------------------------------ 5
var _units: Dictionary = {}


func _spawnable(era_id: String) -> Array:
	var out: Array = []
	var seen := {}
	for f in Game.chaos.figures_for(era_id):
		var nm := db.actor_name(str(f.get("name", "")))
		if nm != "" and not seen.has(nm):
			seen[nm] = true
			out.append(nm)
	for nm in db.actors:
		if (db.actors[nm].get("spawn_eras", {}) as Dictionary).has(era_id) and not seen.has(nm):
			seen[nm] = true
			out.append(nm)
	return out


func _present_somewhere(nm: String, era_id: String) -> bool:
	for y in EraTimeline.years(era_id):
		if EraTimeline.actor_present(db, [], db.actor(nm), era_id, y):
			return true
	return false


## その年に名所にある建物の数（tools/landmark_units.json − まだ無い/もう無い − その年の被災）
func _lm_kinds(era_id: String, lm: String, year: int) -> Dictionary:
	var k: Dictionary = (_units.get(era_id, {}).get(lm, {}).get("kinds", {}) as Dictionary).duplicate()
	for r in EraTimeline.absent_rules(era_id, year):
		if str(r.get("landmark", lm)) != lm:
			continue
		for kd in EraTimeline._kinds(r):
			if k.has(kd):
				k[kd] = mini(int(k[kd]), int(r.get("keep", 0)))
	for r in EraTimeline.ruin_rules(era_id, year):
		if str(r.get("landmark", lm)) != lm:
			continue
		for kd in EraTimeline._kinds(r):
			if k.has(kd):
				k[kd] = int(floor(int(k[kd]) * (1.0 - float(r.get("frac", 0.5)))))
	return k


func _cond_ok(era_id: String, c: Dictionary, year: int, spawn: Array) -> bool:
	var kind := str(c.get("kind", ""))
	var ids: Array = c["id"] if c.get("id") is Array else ([c["id"]] if c.has("id") else [])
	match kind:
		"destroy", "fire", "bridge":
			var lms: Array = []
			if c.has("at"):
				lms = [str(c["at"])]
			elif kind == "destroy" and not ids.is_empty():
				lms = ids.map(func(x): return str(x))
			else:
				lms = (_units.get(era_id, {}) as Dictionary).keys()
			var types: Array = (c["type"] if c["type"] is Array else [c["type"]]) if c.has("type") else []
			var cnt := 0
			var val := 0
			var flam := 0
			var bridges := 0
			for lm in lms:
				if not (_units.get(era_id, {}) as Dictionary).has(lm):
					return true      # 道沿い（town）・川など：表に無い場所は年で変わらない
				var kk := _lm_kinds(era_id, lm, year)
				for kd in kk:
					var n := int(kk[kd])
					var cfg: Dictionary = Destructible.KINDS.get(kd, {})
					if kd == "bridge":
						bridges += n
					if bool(cfg.get("fire", false)):
						flam += n
					if not bool(cfg.get("chaos", false)) or kd == "bridge":
						continue
					if types.is_empty() or kd in types:
						cnt += n
						val += n * int(cfg.get("value", 100))
			match kind:
				"bridge":
					return true      # 橋は年で消さない
				"fire":
					var need := int(c.get("min", 1))
					for step in Destruction.FIRE_CHAOS_STEPS:
						if need <= int(step):
							need = int(step)
							break
					return flam >= mini(need, 5) if not c.has("at") else flam >= need
				_:
					return (val >= int(c["value"])) if c.has("value") else cnt >= int(c.get("min", 1))
		"sink":
			var boats := 0
			for lm in (_units.get(era_id, {}) as Dictionary):
				if c.has("at") and str(c["at"]) != lm:
					continue
				boats += int(_lm_kinds(era_id, lm, year).get("boat", 0))
			var big := ShipYard.ships_for(era_id, year).size() if (not c.has("at") or str(c["at"]) == "port") else 0
			return boats + big >= int(c.get("min", 1))
		_:
			# 人物への行動（kill/protect/persuade/give/steal/forge/escort/delay/steer/teach）：人物がその年にいるか
			if kind == "kill" and str(c.get("type", "")) == "soldier":
				return true
			for i in ids:
				var nm := db.actor_name(str(i))
				if nm == "":
					return true      # 名もない人物・名所キー
				if EraTimeline.actor_present(db, [], db.actor(nm), era_id, year):
					return true
			return ids.is_empty()


func _coverage() -> void:
	_units = JSON.parse_string(FileAccess.get_file_as_string("res://tools/landmark_units.json"))
	var total := 0
	for e in db.eras:
		var id: String = e["eraId"]
		var ys := EraTimeline.years(id)
		var spawn := _spawnable(id)
		# 名所に立つ人物（人物の動詞 contrib/saved/persuade/give/doc/schedule の対象）
		for nm in spawn:
			total += 1
			_check(_present_somewhere(nm, id), "%s: %s appears at some time point" % [id, nm])
			for sc in db.actor(nm).get("schedule", []):
				if str(sc.get("era", db.actor(nm).get("era", ""))) != id:
					continue
				total += 1
				var ok := false
				for y in ys:
					if EraTimeline.schedules_at(db, [], db.actor(nm), id, y).has(sc):
						ok = true
				_check(ok, "%s: %s's appointment %s happens at some time point" % [id, nm, sc.get("event", "")])
		# 各問題の「未来を語る」相手
		for q in e.get("questions", []):
			var cands: Array = db.q_actors.get(q["id"], [])
			if cands.is_empty():
				continue
			total += 1
			var ok := false
			for y in ys:
				for c in cands:
					if EraTimeline.actor_present(db, [], db.actor(c["name"]), id, y):
						ok = true
			_check(ok, "%s: someone to steer %s at some time point" % [id, q["id"]])
		# 揺らぎのルール（どれか 1 つの条件がどこかの時点で起こせる）
		for r in Game.chaos.rules_for(id):
			total += 1
			var t: Variant = r.get("trigger", {})
			var ok := false
			for y in ys:
				for c in (t if t is Array else [t]):
					if c is Dictionary and _cond_ok(id, c, y, spawn):
						ok = true
			_check(ok, "%s: chaos rule %s can fire at some time point" % [id, r.get("id", "")])
		# 合戦・国家事業
		for b in db.battles:
			if str(b.get("era", "")) != id:
				continue
			total += 1
			_check(ys.any(func(y): return EraTimeline.battle_at(b, id, y)), "%s: battle %s appears at some time point" % [id, b["id"]])
		for pid in db.projects:
			var pr: Dictionary = db.projects[pid]
			if str(pr.get("era", "")) != id:
				continue
			total += 1
			_check(ys.any(func(y): return EraTimeline.project_at(pr, id, y)), "%s: project %s appears at some time point" % [id, pid])
	print("hand-made paths reachable at some time point: %d checked" % total)


# ------------------------------------------------------------------ 6
func _ruins_state() -> void:
	var keep := HistoryState.save_path
	HistoryState.save_path = "user://test_timeline_save.json"
	var st := HistoryState.new(db)
	st.record_ruins("edo", [{"kind": "castle_keep", "landmark": "capital", "x": 1.0, "z": 2.0, "year": 1615},
		{"kind": "house", "landmark": "village", "x": 10.0, "z": 20.0, "year": 1615},
		{"kind": "ship", "ship": "shuinsen", "landmark": "port", "year": 1615}])
	var r := st.ruins["edo"] as Array
	_check(EraTimeline.ruins_at(r, 1700).any(func(x): return x["kind"] == "castle_keep"), "keep destroyed in 1615 stays destroyed in 1700")
	_check(EraTimeline.ruins_at(r, 1853).any(func(x): return x["kind"] == "castle_keep"), "... and in 1853")
	_check(EraTimeline.ruins_at(r, 1638).any(func(x): return x["kind"] == "house") and not EraTimeline.ruins_at(r, 1700).any(func(x): return x["kind"] == "house"), "a burned house is rebuilt after ~25 years")
	_check(EraTimeline.ruins_at([{"kind": "hall", "year": 1700}], 1615).is_empty(), "destroyed in 1700 is intact in 1615")
	_check(st.record_ruins("edo", [{"kind": "castle_keep", "landmark": "capital", "x": 1.2, "z": 2.0, "year": 1700}]) == 0, "same keep is not recorded twice")
	st.save()
	var st2 := HistoryState.new(db)
	st2.load_save()
	_check((st2.ruins.get("edo", []) as Array).size() == 3, "ruins saved and loaded (%d)" % (st2.ruins.get("edo", []) as Array).size())
	HistoryState.delete_save()
	HistoryState.save_path = keep
	# 行動の年：自由探索で選んだ年に一般則の効果が起きる
	var tr := ChaosTracker.new(db, st2)
	tr.begin_session("edo", null, 1783)
	tr.act("give", "松平定信", {"item": "千両箱"})
	var a: Dictionary = st2.actions[-1]
	_check(int(a.get("year", 0)) == 1783, "free-roam action records the chosen year")
	var lay := HistoryActors.resolve(db, st2.actions)
	_check((lay["mods"] as Array).any(func(m): return int(m["year"]) == 1783), "generic effect applies at the chosen year")
	tr.end_session()
	HistoryState.save_path = "user://test_timeline_save.json"
	HistoryState.delete_save()
	HistoryState.save_path = keep


# ------------------------------------------------------------------ 6'（実際の箱庭）
func _worlds() -> void:
	var era := db.get_era("edo")
	var w1: EraWorld = EraWorld.build(era, 1615, {})
	add_child(w1)
	await get_tree().process_frame
	var keep1 = _find(w1, "castle_keep", "capital")
	_check(keep1 != null and not keep1.destroyed, "edo 1615: 江戸城天守 stands")
	var ids1: Array = (w1.get_node("ShipYard").placements as Array).map(func(p): return p["id"]) if w1.get_node_or_null("ShipYard") else []
	_check(ids1 == ["shuinsen"], "edo 1615 port: 朱印船 (%s)" % [ids1])
	# 1615 年に寺の御堂を壊した（自由探索の記録）
	var hall = _find(w1, "hall", "temple")
	var rec := {}
	if hall:
		hall.destroy(Vector3.ZERO, 1.0)
		rec = TimelineWorld.ruin_record(hall, 1615)
	var n_units: int = w1.destruction.units.size()
	w1.queue_free()
	await get_tree().process_frame
	var w2: EraWorld = EraWorld.build(era, 1853, {"ruins": [rec] if not rec.is_empty() else []})
	add_child(w2)
	await get_tree().process_frame
	_check(w2.destruction.units.size() == n_units, "unit ids are the same in every year (%d)" % n_units)
	var keep2 = _find(w2, "castle_keep", "capital")
	_check(keep2 != null and keep2.destroyed and keep2.hide_bits == 3, "edo 1853: 天守 gone since 1657 (天守台 only)")
	var hall2 = TimelineWorld.find_unit(w2.destruction.units, rec) if not rec.is_empty() else null
	_check(hall2 != null and hall2.destroyed, "hall destroyed in 1615 is still a ruin in 1853")
	var ids2: Array = (w2.get_node("ShipYard").placements as Array).map(func(p): return p["id"]) if w2.get_node_or_null("ShipYard") else []
	_check(ids2 == ["susquehanna"], "edo 1853 port: サスケハナ (%s)" % [ids2])
	w2.queue_free()
	await get_tree().process_frame
	var w3: EraWorld = EraWorld.build(era, 1657, {})
	add_child(w3)
	await get_tree().process_frame
	_check(int(w3.timeline_stats.get("ruin", 0)) >= 10, "edo 1657: 明暦の大火 ruins (%d)" % int(w3.timeline_stats.get("ruin", 0)))
	w3.queue_free()
	await get_tree().process_frame


func _find(w: EraWorld, kind: String, lm: String):
	for id in w.destruction.units:
		var u = w.destruction.units[id]
		if u.kind == kind and u.landmark == lm:
			return u
	return null
