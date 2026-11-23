extends SceneTree
## ヘッドレス: godot --headless --path . -s res://tests/test_skills.gd
## 技能・持ち物・製作の検証:
##  1. 技能 → 能力値の式（低いほどぎこちない・単調・端点の値）
##  2. 製作：材料・場所・時代・未来の技術・品質と等級・能力値が技能で変わる
##  3. 保存：技能・持ち物・所持金の保存と読み込み、貸与品は保存しない、時代をまたいで持ち越す（実際の Session）
##  4. 技術完全習得モード
##  5. 歴史：技術を教える（teach）／時代錯誤の品（anachronism）が歴史パラメータを動かす
##  6. 戦い：素手→刀の威力・振りの時間が剣術で変わる、受け、銃の装填と弾、兵の落とし物、ミッションの武器の貸与

var fails := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		print("FAIL ", msg)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	PlayerProfile.save_path = "user://test_profile_%d.json" % OS.get_process_id()
	HistoryState.save_path = "user://test_skills_save_%d.json" % OS.get_process_id()
	GameSettings.values["master_mode"] = false
	GameSettings.values["start_armed"] = false
	_formulas()
	_crafting()
	_persistence()
	_master()
	_history()
	_knowledge()
	await _integration()
	await _industry()
	PlayerProfile.delete_save()
	HistoryState.delete_save()
	GameSettings.values["master_mode"] = false
	print("skills tests: %d checks, %d failed" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails else 0)


# ------------------------------------------------------------------ 1. 式
func _formulas() -> void:
	_check(is_equal_approx(Skills.melee_damage_mult(0), 0.7) and is_equal_approx(Skills.melee_damage_mult(100), 1.3), "melee damage 0.7..1.3")
	_check(Skills.melee_time_mult(0) > Skills.melee_time_mult(50) and Skills.melee_time_mult(50) > Skills.melee_time_mult(100), "swing gets faster")
	_check(Skills.block_reduction(100) > Skills.block_reduction(0) and Skills.block_reduction(100) < 1.0, "block 0.3..0.85")
	_check(Skills.wear_mult(100) < Skills.wear_mult(0), "less wear with skill")
	_check(Skills.spread_mult(100) < Skills.spread_mult(0) and Skills.recoil_mult(100) < Skills.recoil_mult(0) and Skills.reload_mult(100) < Skills.reload_mult(0) and Skills.misfire_mult(100) < Skills.misfire_mult(0), "gun handling improves")
	_check(Skills.car_grip(100) > Skills.car_grip(0) and Skills.car_steer_rate(100) > Skills.car_steer_rate(0) and Skills.car_wobble(100) < 0.0001 and Skills.car_wobble(0) > 0.1, "car handling")
	_check(Skills.horse_speed_mult(100) > 1.0 and Skills.horse_speed_mult(0) < 0.8 and Skills.horse_throw_chance(100) < 0.001 and Skills.horse_throw_chance(0) > 0.5, "horse")
	_check(Skills.plane_turn_mult(100) > 1.0 and Skills.plane_turn_mult(0) <= 0.5 and Skills.plane_stall_speed(0) > Skills.plane_stall_speed(100), "plane turn & stall")
	_check(Skills.plane_land_speed(100) > Skills.plane_land_speed(0) and Skills.plane_wobble(100) < Skills.plane_wobble(0), "plane landing & stability")
	_check(Skills.persuade_bonus(0) == 0 and Skills.persuade_bonus(100) == 2, "persuade bonus 0..2")
	_check(Skills.forge_success(100) > 0.9 and Skills.forge_success(0) < 0.35, "forge odds")
	_check(Skills.regen_mult(100) > Skills.regen_mult(0), "medicine regen")
	_check(Skills.gain(0, 10) > Skills.gain(90, 10), "diminishing gains")
	_check(Skills.lesson_zone(100) < Skills.lesson_zone(0), "lessons get harder")
	_check(Skills.rank(0) == "素人" and Skills.rank(100) == "極み" and Skills.rank(65) == "熟練", "ranks")
	_check(Skills.ids().size() == 18, "18 skills")
	for k in Skills.ids():
		_check(Skills.effect_line(k, 50) != "", "effect text for %s" % k)


# ------------------------------------------------------------------ 2. 製作
func _crafting() -> void:
	CraftDB.ensure()
	_check(CraftDB.items().size() > 50 and CraftDB.recipes().size() > 30 and CraftDB.workshops().size() > 15, "crafting data loaded")
	for r in CraftDB.recipes():
		_check(CraftDB.has_item(str(r.get("out", ""))), "recipe %s output exists" % r.get("id"))
		for m in r.get("mats", {}):
			_check(CraftDB.has_item(m), "recipe %s material %s exists" % [r.get("id"), m])
		for k in r.get("skill", {}):
			_check(Skills.LIST.has(k), "recipe %s skill %s" % [r.get("id"), k])
		_check(str(r.get("era", "")) in HistoryDB.ERA_ORDER, "recipe %s era" % r.get("id"))
	for w in CraftDB.workshops():
		for k in w.get("teaches", {}):
			_check(Skills.LIST.has(k), "workshop %s teaches %s" % [w.get("id"), k])
		_check(str(w.get("basis", "")) != "", "workshop %s has a historical basis" % w.get("id"))
		for l in w.get("lessons", []):
			_check(str(l.get("game", "")) in ["hammer", "heat", "assembly", "mix", "target", "course"], "lesson game %s" % l.get("game"))
			_check(w.get("teaches", {}).has(str(l.get("skill", ""))), "workshop %s lesson skill is taught" % w.get("id"))
	for e in HistoryDB.ERA_ORDER:
		_check(not CraftDB.workshops_for(e).is_empty(), "era %s has workshops" % e)
	var novice := PlayerProfile.new()
	novice.autosave = false
	var master := PlayerProfile.new()
	master.autosave = false
	for k in Skills.ids():
		master.skills[k] = 100.0
	novice.skills["katana_smith"] = 35.0
	for p in [novice, master]:
		p.add("tamahagane", 4, 0.5)
		p.add("mokutan", 6, 0.5)
		p.add("nendo", 2, 0.5)
		p.add("mokuzai", 2, 0.5)
	var c0 := Crafting.can_craft(novice, CraftDB.recipe("r_uchigatana"), "sengoku", "gunsmith")
	_check(not c0[0], "wrong station refused")
	var a := Crafting.craft(novice, "r_uchigatana", "sengoku", "forge", 0.5)
	var b := Crafting.craft(master, "r_uchigatana", "sengoku", "forge", 0.5)
	_check(a["ok"] and b["ok"], "craft katana")
	_check(float(b["q"]) > float(a["q"]) + 0.3, "master quality higher (%.2f vs %.2f)" % [b["q"], a["q"]])
	var ia: Dictionary = a["item"]
	var ib: Dictionary = b["item"]
	_check(float(ib["stats"]["damage"]) > float(ia["stats"]["damage"]), "sharper katana")
	_check(float(ib["stats"]["max_dur"]) > float(ia["stats"]["max_dur"]), "more durable katana")
	_check(float(ib["stats"]["speed"]) < float(ia["stats"]["speed"]), "lighter katana swings faster")
	_check(b["grade"] in ["上", "名工"] and a["grade"] in ["粗悪", "並", "上"], "grades %s / %s" % [a["grade"], b["grade"]])
	_check(novice.count("tamahagane") == 2 and novice.count("uchigatana") == 1, "materials consumed, item added")
	_check(Crafting.grade(0.1) == "粗悪" and Crafting.grade(0.4) == "並" and Crafting.grade(0.6) == "上" and Crafting.grade(0.9) == "名工", "grade thresholds")
	# 未来の技術：平安で無煙火薬は普通は作れない。化学 75・火薬 50 なら作れる
	var chem := PlayerProfile.new()
	chem.autosave = false
	chem.add("wata", 2, 0.5)
	chem.add("shousan", 2, 0.5)
	chem.skills["chemistry"] = 50.0
	chem.skills["powder"] = 35.0
	var c1 := Crafting.can_craft(chem, CraftDB.recipe("r_muen"), "heian", "lab")
	_check(not c1[0] and c1[2], "anachronistic recipe blocked without future skill (%s)" % c1[1])
	chem.skills["chemistry"] = 80.0
	chem.skills["powder"] = 55.0
	var c2 := Crafting.can_craft(chem, CraftDB.recipe("r_muen"), "heian", "lab")
	_check(c2[0] and c2[2], "future knowledge lets you make smokeless powder in Heian")
	# 江戸で学んだ化学が昭和の弾薬の品質を上げる（補助技能）
	var am1 := PlayerProfile.new()
	am1.autosave = false
	am1.skills["powder"] = 40.0
	var am2 := PlayerProfile.new()
	am2.autosave = false
	am2.skills["powder"] = 40.0
	am2.skills["chemistry"] = 90.0
	_check(Crafting.quality(am2, CraftDB.recipe("r_dan38")) > Crafting.quality(am1, CraftDB.recipe("r_dan38")) + 0.05, "chemistry (learned in Edo) improves Showa ammo")
	# 銃の能力値
	var g1 := Crafting.make_item("hinawaju", 0.2)
	var g2 := Crafting.make_item("hinawaju", 0.95)
	_check(float(g2["stats"]["misfire"]) < float(g1["stats"]["misfire"]) and float(g2["stats"]["spread"]) < float(g1["stats"]["spread"]) and float(g2["stats"]["reload"]) < float(g1["stats"]["reload"]), "gun quality: misfire/accuracy/reload")
	var bm1 := Crafting.item_stats("horoku", 0.2)
	var bm2 := Crafting.item_stats("horoku", 0.9)
	_check(float(bm2["power"]) > float(bm1["power"]) and float(bm2["dud"]) < float(bm1["dud"]), "bomb power & fuse reliability")


# ------------------------------------------------------------------ 3. 保存
func _persistence() -> void:
	var p := PlayerProfile.new()
	p.autosave = false
	_check(p.weapons().is_empty() and p.count("smartphone") == 1 and p.count("kyokasho") == 1, "starts unarmed with a smartphone and a textbook")
	p.skills["kenjutsu"] = 42.5
	var it := p.add_instance(Crafting.make_item("tachi", 0.7, "あなた", "heian"))
	it["dur"] = 50.0
	p.equip(int(it["uid"]))
	p.add("ya", 25, 0.6)
	p.add_money(12345)
	p.lend("arisaka38", 1, 0.5)
	p.lend("dan38", 30, 0.5)
	p.save()
	var q := PlayerProfile.new()
	q.autosave = false
	_check(q.load_save(), "profile loads")
	_check(is_equal_approx(q.raw_level("kenjutsu"), 42.5), "skill saved")
	_check(q.count("tachi") == 1 and q.count("ya") == 25 and q.money == p.money, "items & money saved")
	_check(q.count("arisaka38") == 0 and q.count("dan38") == 0, "loans are not saved")
	_check(not q.weapon().is_empty() and str(q.weapon()["id"]) == "tachi" and is_equal_approx(float(q.weapon()["dur"]), 50.0), "equipped weapon & durability saved")
	p.return_loans()
	_check(p.count("arisaka38") == 0 and p.count("dan38") == 0 and p.count("tachi") == 1, "loans returned, own items kept")
	# 使うだけで上がるのは 50 まで
	var r := PlayerProfile.new()
	r.autosave = false
	for i in 400:
		r.practice("shageki", 1.0)
	_check(r.raw_level("shageki") <= Skills.PRACTICE_CAP + 0.001 and r.raw_level("shageki") > 45.0, "practice caps at 50 (%.1f)" % r.raw_level("shageki"))
	_check(r.train("shageki", 9.0, 100.0) > 0.0, "apprenticeship goes beyond the practice cap")


# ------------------------------------------------------------------ 4. 技術完全習得モード
func _master() -> void:
	var p := PlayerProfile.new()
	p.autosave = false
	GameSettings.values["master_mode"] = true
	_check(p.level("piloting") == 100.0 and p.level("katana_smith") == 100.0, "master mode: all skills 100")
	p.add("hagane", 6, 0.5)
	p.add("mokuzai", 2, 0.5)
	p.add("dou", 1, 0.5)
	var c := Crafting.can_craft(p, CraftDB.recipe("r_lmg"), "sengoku", "machine")
	_check(c[0], "master mode: future recipes unlocked (LMG in Sengoku)")
	_check(p.train("kenjutsu", 10.0) == 0.0 and p.raw_level("kenjutsu") == 0.0, "master mode does not touch learned values")
	GameSettings.values["master_mode"] = false
	_check(p.level("piloting") == 0.0, "master mode off: learned values return")


# ------------------------------------------------------------------ 5. 歴史
func _history() -> void:
	var db := HistoryDB.load_all()
	var st := HistoryState.new(db)
	var tr := ChaosTracker.new(db, st)
	tr.begin_session("edo")
	var nm := ""
	for a in db.actors:
		if str(db.actors[a].get("era", "")) == "edo":
			nm = a
			break
	_check(nm != "", "an Edo figure exists")
	var tech0: float = float(st.era_states.get("edo", {}).get("tech", 0.0))
	var hit := tr.act("teach", nm, {"skill": "chemistry", "level": 90})
	_check(not hit.is_empty() and str(st.actions[-1].get("verb", "")) == "teach", "teach recorded as an action")
	var tech1: float = float(st.era_states.get("edo", {}).get("tech", 0.0))
	_check(tech1 > tech0, "teaching chemistry raises Edo tech (%.1f -> %.1f)" % [tech0, tech1])
	_check(tr.act("teach", nm, {"skill": "chemistry", "level": 90}).is_empty(), "same lesson twice does nothing")
	var mil0: float = float(st.era_states.get("edo", {}).get("militarism", 0.0))
	var h2 := tr.act("anachronism", "arisaka38", {"item": "arisaka38", "gap": 2, "cause": "lost", "type": "gun"})
	_check(not h2.is_empty() and str(st.actions[-1].get("verb", "")) == "anachronism", "anachronism recorded")
	var mil: float = float(st.era_states.get("edo", {}).get("militarism", 0.0))
	_check(mil > mil0, "a lost rifle in Edo nudges militarism (%.1f -> %.1f)" % [mil0, mil])
	_check(HistoryActors.headline(db, st.actions[-1]).contains("三八式"), "headline names the item")
	_check(st.war_tier() != "" or db.war_model.is_empty(), "war model still evaluates")
	tr.end_session()
	_check(tr.record("anachronism", "arisaka38", {"item": "arisaka38", "gap": 2}).is_empty(), "inactive outside free roam")


# ------------------------------------------------------------------ 6. 実際のセッション
func _integration() -> void:
	var G: Node = root.get_node_or_null("Game")
	if G == null:
		print("Game autoload missing: skip integration")
		return
	G.set_meta("force_fallback_world", true)
	var saved_prof = G.profile
	var prof := PlayerProfile.new()
	prof.autosave = false
	G.profile = prof
	var S: GDScript = load("res://scripts/mission/session.gd")
	var E: GDScript = load("res://scripts/mission/enemy.gd")
	var sess: Node = S.start_free_roam("edo")
	root.add_child(sess)
	await _frames(5)
	var player: Node = sess.player
	_check(player.arms != null and player.arms.kind() == "fists", "player starts unarmed (fists)")
	_check(sess.craft != null and sess.craft.stations.size() >= 5, "workshops/shops/storehouses placed (%d)" % sess.craft.stations.size())
	var forge = sess.craft.find_station("touko")
	_check(forge != null, "katana smith workshop in Edo")
	# 稽古：刀鍛冶が上がる
	if forge:
		sess.craft.ui.open_workshop(forge)
		await _frames(1)
		_check(sess.craft.ui.is_open() and G.input_blocked, "workshop UI opens")
		var les: Dictionary = forge.def["lessons"][0]
		sess.craft.ui._start_lesson(les)
		await _frames(2)
		sess.craft.ui.finish_minigame(1.0)
		await create_timer(0.9).timeout
		_check(prof.raw_level("katana_smith") > 5.0, "lesson raised katana smithing (%.1f)" % prof.raw_level("katana_smith"))
		sess.craft.ui.close()
	# 製作：刀
	prof.skills["katana_smith"] = 80.0
	prof.add("tamahagane", 2); prof.add("mokutan", 3); prof.add("nendo", 1); prof.add("mokuzai", 1)
	if forge:
		sess.craft.ui._station = forge
		sess.craft.ui._craft_now("r_uchigatana", "forge", 0.9)
		sess.craft.ui.close()
	_check(prof.count("uchigatana") == 1, "crafted a katana at the forge")
	# 素手と刀の威力・振りの時間
	var e1 = E.spawn(sess, player.global_position + Vector3(0, 0.5, -1.6), "足軽", "edo")
	e1.aggro_range = 0.0
	await _frames(3)
	var cam = sess.cam
	cam.yaw = 0.0
	var hp0: float = e1.hp
	player.arms._busy_until = 0.0
	player.arms.swing(false)
	await create_timer(0.6).timeout
	var fist_dmg: float = hp0 - e1.hp
	_check(fist_dmg > 0.0, "a punch hurts (%.1f)" % fist_dmg)
	var kat: Dictionary = prof.weapons()[0]
	player.arms.equip(int(kat["uid"]))
	prof.skills["kenjutsu"] = 0.0
	var hp1: float = e1.hp
	player.arms._busy_until = 0.0
	player.arms.swing(false)
	var t_low: float = player.arms._swing_end - Time.get_ticks_msec() / 1000.0
	await create_timer(0.8).timeout
	var low_dmg: float = hp1 - e1.hp
	prof.skills["kenjutsu"] = 100.0
	var e2 = E.spawn(sess, player.global_position + Vector3(0, 0.5, -1.6), "足軽", "edo")
	e2.aggro_range = 0.0
	if is_instance_valid(e1):
		e1.queue_free()
	await _frames(3)
	var hp2: float = e2.hp
	player.arms._busy_until = 0.0
	player.arms.swing(false)
	var t_high: float = player.arms._swing_end - Time.get_ticks_msec() / 1000.0
	await create_timer(0.6).timeout
	var high_dmg: float = hp2 - e2.hp if not e2.dead else 999.0
	_check(low_dmg > fist_dmg, "katana beats fists (%.1f > %.1f)" % [low_dmg, fist_dmg])
	_check(high_dmg > low_dmg * 1.5, "kenjutsu 100 hits harder than 0 (%.1f vs %.1f)" % [high_dmg, low_dmg])
	_check(t_high < t_low, "kenjutsu 100 swings faster (%.2f < %.2f)" % [t_high, t_low])
	_check(float(prof.weapon()["dur"]) < float(prof.weapon()["stats"]["max_dur"]), "the blade wears with use")
	# 受け
	player.god_mode = false
	player.hp = player.max_hp
	player.arms.blocking = true
	player.arms._block_start = -100.0
	player.take_hit(20.0, 1)
	var blocked_dmg: float = player.max_hp - player.hp
	_check(blocked_dmg < 20.0 * 0.2, "blocking with kenjutsu 100 absorbs most damage (%.1f)" % blocked_dmg)
	player.arms.blocking = false
	# 兵の落とし物
	var drops_before := get_nodes_in_group("loot_drop").size()
	var e3 = E.spawn(sess, player.global_position + Vector3(6, 0.5, 0), "足軽", "edo")
	await _frames(2)
	e3.take_hit(9999.0, 0)
	await _frames(2)
	var drops: Array = get_nodes_in_group("loot_drop")
	_check(drops.size() > drops_before, "a defeated soldier drops loot")
	var nw := prof.weapons().size()
	var money0 := prof.money
	for d in drops:
		if is_instance_valid(d):
			d.take()
	_check(prof.weapons().size() >= nw and prof.money > money0, "loot picked up (weapons %d, money +%d)" % [prof.weapons().size() - nw, prof.money - money0])
	# 銃：装填と弾
	var gun := prof.add_instance(Crafting.make_item("hinawaju", 0.8))
	prof.add("hayago", 3, 0.8)
	player.arms.equip(int(gun["uid"]))
	player.arms.start_reload()
	_check(player.arms.reloading, "matchlock reload starts")
	prof.skills["shageki"] = 0.0
	var r0: float = player.arms._reload_end - Time.get_ticks_msec() / 1000.0
	player.arms.reloading = false
	prof.skills["shageki"] = 100.0
	player.arms.start_reload()
	var r1: float = player.arms._reload_end - Time.get_ticks_msec() / 1000.0
	_check(r1 < r0 * 0.7, "shooting skill speeds up the matchlock reload (%.1f s vs %.1f s)" % [r1, r0])
	var hy0 := prof.count("hayago")
	player.arms._finish_reload()
	player.arms.reloading = false
	_check(int(gun["mag"]) == 1 and prof.count("hayago") == hy0 - 1, "one hayago loaded")
	# 蔵を探る（盗み）
	var kura = null
	for s in sess.craft.stations:
		if s.kind == "loot":
			kura = s
	if kura:
		var W: GDScript = load("res://scripts/mission/wanted.gd")
		W.set("heat", 0.0)
		sess.craft.open_station(kura)
		_check(float(W.get("heat")) > 0.5 and kura.looted, "looting a storehouse raises wanted")
		sess.craft.ui.close()
	# 店
	var shop = null
	for s in sess.craft.stations:
		if s.kind == "shop":
			shop = s
	if shop:
		prof.add_money(100000)
		var m0 := prof.money
		sess.craft.ui.open_shop(shop)
		sess.craft.ui._buy("ya", 10, 300)
		_check(prof.money == m0 - 300 and prof.count("ya") >= 10, "buying arrows")
		sess.craft.ui.close()
	_check(CraftDB.money_text(4000 * 3 + 200, "edo") == "3両 200文" and CraftDB.money_text(8000, "showa") == "2円", "era currency text")
	# 時代をまたいで持ち越す
	var katana_count := prof.count("uchigatana")
	var ks := prof.raw_level("katana_smith")
	sess.end()
	await _frames(3)
	var sess2: Node = S.start_free_roam("showa")
	root.add_child(sess2)
	await _frames(5)
	_check(prof.count("uchigatana") == katana_count and prof.raw_level("katana_smith") == ks, "katana and smithing carried from Edo to Showa")
	_check(sess2.craft.find_station("hikou") != null, "flight school in Showa")
	# 乗り物の稽古（飛行訓練）
	var fs = sess2.craft.find_station("hikou")
	if fs:
		var p0 := prof.raw_level("piloting")
		sess2.craft.start_course(fs, fs.def["lessons"][0])
		await _frames(2)
		_check(sess2.craft.course != null, "flight lesson course started")
		sess2.craft.course.complete_now(0.9)
		await _frames(2)
		_check(prof.raw_level("piloting") > p0, "flight lesson raised piloting (%.1f)" % prof.raw_level("piloting"))
	# 飛行機の操縦の技能が旋回に効く
	var plane = null
	for v in get_nodes_in_group("vehicle"):
		if v.get("kind") == "plane":
			plane = v
	if plane:
		sess2.player.enter_vehicle(plane)
		await _frames(1)
		prof.skills["piloting"] = 0.0
		var lo: float = plane._skill()
		prof.skills["piloting"] = 100.0
		var hi: float = plane._skill()
		_check(lo == 0.0 and hi == 100.0, "plane reads the pilot's skill")
		sess2.player.exit_vehicle()
	sess2.end()
	await _frames(3)
	# ミッション：武器がなければ時代の武器を貸す
	var empty := PlayerProfile.new()
	empty.autosave = false
	G.profile = empty
	var q: Dictionary = {}
	for qq in G.db.questions:
		if qq["era"]["eraId"] == "sengoku":
			q = qq
			break
	var c: int = (int(q["real"]) + 1) % 4
	var ms: Node = S.start_mission(q, c, 0)
	root.add_child(ms)
	await _frames(4)
	_check(empty.has_ranged_weapon() and not empty.weapon().is_empty() and empty.weapon().get("loan", false), "mission loans a period weapon (%s)" % str(empty.weapon().get("id", "")))
	ms.end()
	await _frames(3)
	_check(empty.weapons().is_empty() and empty.count("hayago") == 0, "loan returned after the mission")
	# 最初から武装
	GameSettings.values["start_armed"] = true
	var fr: Node = S.start_free_roam("heian")
	root.add_child(fr)
	await _frames(4)
	_check(str(empty.weapon().get("id", "")) == "jikuju", "start armed: future gun")
	fr.end()
	await _frames(3)
	GameSettings.values["start_armed"] = false
	G.profile = saved_prof
	G.remove_meta("force_fallback_world")
	G.state.reset_all()



# ------------------------------------------------------------------ 7. 知識の木
func _knowledge() -> void:
	Knowledge.ensure()
	_check(Knowledge.ids().size() >= 35, "knowledge tree has %d nodes" % Knowledge.ids().size())
	var all_ids := Knowledge.ids()
	for nid in all_ids:
		var nd := Knowledge.node(nid)
		_check(Knowledge.domains().has(str(nd.get("domain", ""))), "node %s domain" % nid)
		_check(str(nd.get("basis", "")) != "", "node %s has basis" % nid)
		_check(str(nd.get("era", "")) in HistoryDB.ERA_ORDER, "node %s era" % nid)
		for pr in nd.get("prereq", []):
			_check(pr in all_ids, "node %s prereq %s exists" % [nid, pr])
		for sid in nd.get("schools", []):
			_check(Knowledge.schools().has(sid) or not CraftDB.workshop(sid).is_empty(), "node %s school %s exists" % [nid, sid])
		if nd.has("book"):
			_check(CraftDB.has_item(str(nd["book"])), "node %s book exists" % nid)
		_check(not Knowledge.vars_for(nid).is_empty(), "node %s has history vars" % nid)
	for b in Knowledge.buildings():
		for k in b.get("know", {}):
			_check(k in all_ids, "building %s knowledge %s" % [b.get("id"), k])
		for m in b.get("mats", {}):
			_check(CraftDB.has_item(m), "building %s material %s" % [b.get("id"), m])
		for m in b.get("inputs", {}):
			_check(CraftDB.has_item(m), "building %s input %s" % [b.get("id"), m])
		for m in b.get("outputs", {}):
			_check(CraftDB.has_item(m), "building %s output %s" % [b.get("id"), m])
		_check(not (b.get("vars", {}) as Dictionary).is_empty(), "building %s vars" % b.get("id"))
	# 前提のない循環が無いこと（どのノードも前提をたどると根に着く）
	for nid in all_ids:
		var seen := {}
		var stack: Array = [nid]
		var ok := true
		while not stack.is_empty():
			var x: String = stack.pop_back()
			if seen.has(x):
				continue
			seen[x] = true
			for pr in Knowledge.node(x).get("prereq", []):
				if pr == nid:
					ok = false
				stack.append(pr)
		_check(ok, "no prerequisite cycle through %s" % nid)
	var p := PlayerProfile.new()
	p.autosave = false
	_check(Knowledge.knows(p, "p_jouki") and Knowledge.mastery(p, "p_jouki") == 0.0, "modern common sense: steam principle known, no hands-on mastery")
	_check(not Knowledge.knows(p, "m_hansharo"), "reverberatory furnace is not common knowledge")
	_check(not Knowledge.learn(p, "m_koro"), "cannot learn the blast furnace without prerequisites")
	# 実験は 60 まで、前提 +30 まで
	for i in 60:
		Knowledge.train(p, "p_suisha", 7.0, Knowledge.CAP_EXPERIMENT)
	_check(absf(Knowledge.mastery(p, "p_suisha") - 60.0) < 0.01, "experiments cap at 60 (%.1f)" % Knowledge.mastery(p, "p_suisha"))
	for i in 80:
		Knowledge.train(p, "p_jouki", 12.0, Knowledge.CAP_TEACHER)
	_check(absf(Knowledge.mastery(p, "p_jouki") - 90.0) < 0.01, "mastery limited by prerequisites + 30 (%.1f)" % Knowledge.mastery(p, "p_jouki"))
	var got := Knowledge.read_textbook(p)
	_check(got.size() > 0 and Knowledge.knows(p, "t_teori"), "the future textbook teaches principles whose prerequisites are known (%d)" % got.size())
	_check(Knowledge.read_textbook(p).is_empty(), "rereading teaches nothing new")
	var q := PlayerProfile.new()
	q.autosave = false
	q.from_dict(p.to_dict())
	_check(absf(Knowledge.mastery(q, "p_jouki") - 90.0) < 0.01 and Knowledge.knows(q, "t_teori"), "knowledge saved")
	# 本
	var r := PlayerProfile.new()
	r.autosave = false
	var br := Knowledge.read_book(r, "hon_tekkou")
	_check(not br["ok"], "a book needs its prerequisites (%s)" % br.get("reason", ""))
	Knowledge.learn(r, "m_tatara", true)
	var br2 := Knowledge.read_book(r, "hon_tekkou")
	_check(br2["ok"] and Knowledge.knows(r, "m_hansharo"), "reading 鉄熕全書 teaches the reverberatory furnace")
	# 知識で作る品
	var s := PlayerProfile.new()
	s.autosave = false
	s.skills["machining"] = 40.0
	s.add("hagane", 4); s.add("dou", 2); s.add("kikai_buhin", 3)
	_check(not Crafting.can_craft(s, CraftDB.recipe("r_jouki"), "edo", "machine")[0], "steam engine needs steam mastery")
	s.knowledge["p_suisha"] = {"p": true, "m": 60.0}
	s.knowledge["p_jouki"] = {"p": true, "m": 45.0}
	_check(Crafting.can_craft(s, CraftDB.recipe("r_jouki"), "sengoku", "machine")[0], "with the knowledge, a steam engine can be built even in Sengoku")
	# 建てられるか
	var b := Knowledge.building("boseki")
	var c := PlayerProfile.new()
	c.autosave = false
	_check(not Knowledge.can_build(c, b, "edo", "village")[0], "spinning mill needs knowledge")
	c.knowledge["t_boseki"] = {"p": true, "m": 45.0}
	_check(str(Knowledge.can_build(c, b, "edo", "village")[1]).contains("許し"), "spinning mill needs the ruler's permission")
	c.permits["edo"] = true
	_check(str(Knowledge.can_build(c, b, "edo", "village")[1]).contains("建材"), "then materials")
	_check(Knowledge.power_mode(b, "village") == "water" and Knowledge.power_mode(b, "castle") == "steam", "water power by the river, steam elsewhere")
	_check(Knowledge.build_mats(b, "castle").has("jouki"), "steam power needs a steam engine")
	GameSettings.values["master_mode"] = true
	_check(Knowledge.knows(c, "e_hatsuden") and Knowledge.mastery(c, "f_hikoki") == 100.0, "master mode unlocks all knowledge")
	GameSettings.values["master_mode"] = false
	# 歴史：施設と学校
	var db := HistoryDB.load_all()
	var st := HistoryState.new(db)
	var tr := ChaosTracker.new(db, st)
	tr.begin_session("edo")
	var e0: Dictionary = st.era_states.get("edo", {}).duplicate()
	var h := tr.act("industry", "boseki", {"landmark": "village", "scale": 1})
	_check(not h.is_empty() and str(st.actions[-1].get("verb", "")) == "industry", "industry event recorded")
	var e1: Dictionary = st.era_states.get("edo", {})
	_check(float(e1.get("economy", 0)) > float(e0.get("economy", 0)), "a spinning mill raises Edo economy")
	_check(tr.act("industry", "boseki", {"landmark": "village", "scale": 1}).is_empty(), "the same building counts once")
	_check(not tr.act("industry", "boseki", {"landmark": "village", "scale": 2}).is_empty(), "expanding counts again")
	var w0 := st.war.duplicate(true)
	var e2: Dictionary = st.era_states.get("edo", {}).duplicate()
	tr.act("industry", "gakko", {"landmark": "capital", "scale": 1, "mult": 3.0})
	var e3: Dictionary = st.era_states.get("edo", {})
	_check(float(e3.get("education", 0)) - float(e2.get("education", 0)) >= 10.0, "a school spreading much knowledge has a big effect on education (+%.0f)" % (float(e3.get("education", 0)) - float(e2.get("education", 0))))
	_check(HistoryActors.headline(db, st.actions[-1]).contains("学校"), "headline names the building")
	_check(not tr.act("teach", "village", {"skill": "p_jouki", "level": 80}).is_empty(), "teaching artisans a knowledge node moves history")
	_check(tr.act("teach", "village", {"skill": "p_jouki", "level": 80}).is_empty(), "teaching the same thing to the same place again does nothing")
	var pil0: Dictionary = w0.get("pillars", {})
	var pil1: Dictionary = st.war.get("pillars", {})
	if pil0.has("industry") and pil1.has("industry"):
		_check(float(pil1["industry"].get("score", pil1["industry"]) if pil1["industry"] is Dictionary else pil1["industry"]) >= float(pil0["industry"].get("score", pil0["industry"]) if pil0["industry"] is Dictionary else pil0["industry"]), "industrialisation does not lower the 1941 industry pillar")
	tr.end_session()


# ------------------------------------------------------------------ 8. 実際に建てて動かす（江戸で産業革命）
func _industry() -> void:
	var G: Node = root.get_node_or_null("Game")
	if G == null:
		return
	G.set_meta("force_fallback_world", true)
	G.state.reset_all()
	var saved_prof = G.profile
	var prof := PlayerProfile.new()
	prof.autosave = false
	G.profile = prof
	var S: GDScript = load("res://scripts/mission/session.gd")
	var sess: Node = S.start_free_roam("edo")
	root.add_child(sess)
	await _frames(5)
	_check(sess.craft.find_station("seirenkata") != null and sess.craft.find_station("denshujo") != null, "Edo schools (佐賀藩精錬方・長崎海軍伝習所) placed")
	# 学問所で知識を学ぶ
	var sr = sess.craft.find_station("seirenkata")
	if sr:
		sess.craft.ui.open_workshop(sr)
		sess.craft.ui._start_know_lesson("m_hansharo")
		await _frames(2)
		sess.craft.ui.finish_minigame(1.0)
		await create_timer(0.9).timeout
		_check(Knowledge.knows(prof, "m_hansharo") and Knowledge.mastery(prof, "m_hansharo") > 0.0, "learned the reverberatory furnace at 佐賀藩精錬方 (%.1f)" % Knowledge.mastery(prof, "m_hansharo"))
		sess.craft.ui.close()
	# 江戸の村に蒸気でない紡績工場（川沿い＝水力）を建てる
	prof.knowledge["t_teori"] = {"p": true, "m": 60.0}
	prof.knowledge["p_suisha"] = {"p": true, "m": 60.0}
	prof.knowledge["t_boseki"] = {"p": true, "m": 50.0}
	prof.add("mokuzai", 10); prof.add("kikai_buhin", 6)
	prof.add_money(400000)
	sess.player.teleport(sess.world.landmark_pos("village") + Vector3(5, 0, 5))
	await _frames(2)
	_check(sess.craft.current_landmark() == "village", "standing at the village")
	var r0: Dictionary = sess.craft.build("boseki")
	_check(not r0["ok"] and str(r0["reason"]).contains("許し"), "needs permission first")
	prof.permits["edo"] = true
	var n_act: int = G.state.actions.size()
	var r1: Dictionary = sess.craft.build("boseki")
	_check(r1["ok"], "built a spinning mill in Edo (%s)" % r1.get("reason", ""))
	await _frames(2)
	_check(G.state.actions.size() > n_act and str(G.state.actions[-1].get("verb", "")) == "industry", "building it moves history (industry action)")
	var f = r1.get("facility")
	if f:
		_check(str(f.rec.get("power", "")) == "water", "village mill runs on water")
		_check(not f.produce_once(), "no workers, no production")
		f.rec["workers"] = f.needed_workers()
		prof.add("wata", 9)
		f.deposit(prof)
		_check(f.produce_once() and f.produce_once(), "the mill spins cotton")
		var got: Array = f.collect(prof)
		_check(prof.count("menshi") >= 6, "collected cotton yarn (%d)" % prof.count("menshi"))
		var old_skill := float(f.rec.get("skill", 0))
		var tw: Dictionary = sess.craft.teach_workers(f, "t_boseki")
		_check(tw["ok"] and float(f.rec["skill"]) > old_skill, "teaching artisans raises their skill")
		var eff0 := Knowledge.efficiency(f.rec)
		prof.add_money(300000)
		var ex: Dictionary = sess.craft.expand(f)
		_check(ex["ok"] and Knowledge.efficiency(f.rec) > eff0, "expanding raises output")
		sess.craft.ui.open_factory(f)
		await _frames(1)
		_check(sess.craft.ui.is_open(), "factory panel opens")
		sess.craft.ui.close()
	# 蒸気の機械工場は蒸気機関と石炭が要る
	prof.knowledge["k_karakuri"] = {"p": true, "m": 60.0}
	prof.knowledge["m_tatara"] = {"p": true, "m": 60.0}
	prof.knowledge["m_hansharo"] = {"p": true, "m": 60.0}
	prof.knowledge["k_senban"] = {"p": true, "m": 50.0}
	prof.add("hagane", 6); prof.add("kikai_buhin", 4); prof.add("renga", 10)
	prof.add_money(400000)
	var r2: Dictionary = sess.craft.build("kikai_kojo")
	_check(not r2["ok"] and str(r2["reason"]).contains("蒸気機関"), "steam factory needs a steam engine (%s)" % r2.get("reason", ""))
	prof.add("jouki", 1)
	var r3: Dictionary = sess.craft.build("kikai_kojo")
	_check(r3["ok"], "built a steam machine works in Edo")
	if r3.get("facility"):
		var f2 = r3["facility"]
		f2.rec["workers"] = f2.needed_workers()
		prof.add("tetsu", 4)
		f2.deposit(prof)
		_check(not f2.produce_once(), "no coal, no steam")
		prof.add("sekitan", 2)
		f2.deposit(prof)
		_check(f2.produce_once(), "with coal the machine works runs")
	var nb := prof.buildings.size()
	sess.end()
	await _frames(3)
	# 同じ時代に戻ると施設が残っている（離れていた間の分も生産）
	var sess2: Node = S.start_free_roam("edo")
	root.add_child(sess2)
	await _frames(4)
	var facs := get_nodes_in_group("facility")
	_check(facs.size() == nb, "buildings persist when revisiting Edo (%d)" % facs.size())
	sess2.end()
	await _frames(3)
	var sess3: Node = S.start_free_roam("showa")
	root.add_child(sess3)
	await _frames(4)
	_check(get_nodes_in_group("facility").is_empty(), "Edo buildings stay in Edo")
	sess3.end()
	await _frames(3)
	G.profile = saved_prof
	G.state.reset_all()
	G.remove_meta("force_fallback_world")
