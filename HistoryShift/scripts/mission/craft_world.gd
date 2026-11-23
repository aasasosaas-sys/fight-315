class_name CraftWorld
extends Node
## 技能・持ち物・製作の世界側（Session の子）。
##  - 自由探索：その時代の工房・学校（data/crafting/workshops.json）・店・蔵／武器庫を名所のそばに置き、E で開く
##  - いつでも：Tab / I / Back で時空鞄（持ち物・技能・製作・メモ）
##  - 技能が上がったら HUD に知らせる
## 置き場所は EraWorld.landmark_pos(at) から名前ごとに決まった方向へ 14〜26m（near: plane / car なら滑走路・車のそば）。

var session: Node
var hud
var era_id := ""
var stations: Array = []
var ui: CraftUI
var course: CourseLesson = null
var _course_station: CraftStation = null
var _course_lesson: Dictionary = {}
var _near: CraftStation = null
var _prompted := false

const RANGE := 3.6


func setup(p_session: Node, p_hud) -> void:
	session = p_session
	hud = p_hud
	era_id = str(p_session.era.get("eraId", "")) if p_session and "era" in p_session else ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ui = CraftUI.new()
	ui.era_id = era_id
	ui.mgr = self
	add_child(ui)
	ui.course_requested.connect(start_course)
	if Game.profile and not Game.profile.skill_up.is_connected(_on_skill_up):
		Game.profile.skill_up.connect(_on_skill_up)
	if Game.profile and not Game.profile.knowledge_up.is_connected(_on_knowledge_up):
		Game.profile.knowledge_up.connect(_on_knowledge_up)
	if session and str(session.get("mode")) == "free":
		spawn_stations()


func _exit_tree() -> void:
	if Game.profile and Game.profile.skill_up.is_connected(_on_skill_up):
		Game.profile.skill_up.disconnect(_on_skill_up)
	if Game.profile and Game.profile.knowledge_up.is_connected(_on_knowledge_up):
		Game.profile.knowledge_up.disconnect(_on_knowledge_up)


func _on_knowledge_up(id: String, old: float, nv: float, learned: bool) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var txt := ("◆ 知識「%s」の原理を知った" % Knowledge.node_name(id)) if learned else ("◆ 知識「%s」習熟 %d → %d" % [Knowledge.node_name(id), int(old), int(nv)])
	if hud.has_method("skill_toast"):
		hud.skill_toast(txt, true)


func _on_skill_up(id: String, old: float, nv: float) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var up := nv > old
	var rk := Skills.rank(nv)
	var txt := "◆ %s %d → %d" % [Skills.skill_name(id), int(old), int(nv)]
	if rk != Skills.rank(old):
		txt += "　「%s」になった！" % rk
	if hud.has_method("skill_toast"):
		hud.skill_toast(txt, up)
	else:
		hud.toast(txt, 3.0)


# ------------------------------------------------------------------ 配置
func spawn_stations() -> void:
	var w = Game.world
	if w == null or not w.has_method("landmark_pos"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(era_id) + 977
	var used: Array = []
	for d in CraftDB.workshops_for(era_id):
		_place("workshop", d, w, rng, used)
	for d in CraftDB.shops_for(era_id):
		_place("shop", d, w, rng, used)
	for d in CraftDB.loot_for(era_id):
		_place("loot", d, w, rng, used)
	for d in Knowledge.school_workshops(era_id):
		_place("workshop", d, w, rng, used)
	spawn_facilities()


## この時代に主人公が建てた施設
func spawn_facilities() -> void:
	if Game.profile == null:
		return
	for rec in Game.profile.buildings:
		if str(rec.get("era", "")) == era_id:
			var f := Facility.spawn_rec(session, rec)
			stations.append(f)
			if hud and "compass_points" in hud:
				hud.compass_points["▣" + f.display_name + str(rec.get("id", ""))] = f.global_position


## いまいる名所（RANGE_BUILD 以内）。無ければ ""
const RANGE_BUILD := 90.0


func current_landmark() -> String:
	var w = Game.world
	var p = Game.player
	if w == null or p == null:
		return ""
	var best := ""
	var bd := RANGE_BUILD
	for k in HistoryDB.LANDMARK_KEYS:
		var d: float = (w.landmark_pos(k) as Vector3).distance_to((p as Node3D).global_position)
		if d < bd:
			bd = d
			best = k
	return best


## 施設を建てる。戻り値 {ok, reason, facility}
func build(type: String) -> Dictionary:
	var prof := Game.profile
	var b := Knowledge.building(type)
	var at := current_landmark()
	var chk := Knowledge.can_build(prof, b, era_id, at)
	if not chk[0]:
		return {"ok": false, "reason": chk[1]}
	var mats := Knowledge.build_mats(b, at)
	for m in mats:
		prof.take(m, int(mats[m]))
	prof.spend(int(b.get("money", 0)))
	var p: Node3D = Game.player
	var cam := CameraRig.I
	var fwd := cam.flat_forward() if cam else -p.global_basis.z
	var pos := p.global_position + fwd * 10.0
	var w = Game.world
	if w and w.has_method("height_at"):
		pos.y = w.height_at(pos.x, pos.z)
	var rec := {"id": "%s_%d" % [type, prof.next_uid], "type": type, "era": era_id, "at": at, "pos": [pos.x, pos.y, pos.z],
		"yaw": atan2(-fwd.x, -fwd.z) + PI, "workers": 0, "skill": 10.0, "scale": 1, "power": Knowledge.power_mode(b, at),
		"stock": {}, "money": 0, "last": Time.get_unix_time_from_system()}
	prof.next_uid += 1
	if b.get("line", false):
		var bestk := ""
		var bd := INF
		for k in HistoryDB.LANDMARK_KEYS:
			if k == at:
				continue
			var d: float = (w.landmark_pos(k) as Vector3).distance_to(w.landmark_pos(at))
			if d < bd:
				bd = d
				bestk = k
		rec["to"] = bestk
	prof.buildings.append(rec)
	prof.save()
	var f := Facility.spawn_rec(session, rec)
	stations.append(f)
	_industry_event(rec)
	Sfx.play(get_tree(), Sfx.success(), -6.0)
	return {"ok": true, "reason": "", "facility": f}


## 歴史への知らせ：Game.chaos.act("industry", 種類, {era, landmark, scale, mult, bonus})（自由探索の間だけ歴史に効く）
func _industry_event(rec: Dictionary) -> Dictionary:
	if Game.chaos == null or not Game.chaos.is_active():
		return {}
	var b := Knowledge.building(str(rec["type"]))
	var bonus: Dictionary = b.get("bonus", {})
	var has_bonus: bool = bonus.has("vars") and Knowledge.mastery(Game.profile, str(bonus.get("know", ""))) >= float(bonus.get("need", 40))
	return Game.chaos.act("industry", str(rec["type"]), {"landmark": str(rec.get("at", "")), "scale": int(rec.get("scale", 1)),
		"mult": Knowledge.industry_scale(Game.profile, rec) / (1.0 + 0.5 * (int(rec.get("scale", 1)) - 1)), "bonus": has_bonus})


## 拡張（規模 +1、最大 3）
func expand(f: Facility) -> Dictionary:
	var prof := Game.profile
	var rec := f.rec
	if int(rec.get("scale", 1)) >= 3:
		return {"ok": false, "reason": "これ以上は広げられない"}
	var cost := int(float(f.bdef.get("money", 0)) * 0.6)
	if not prof.spend(cost):
		return {"ok": false, "reason": "お金が足りない（%s）" % CraftDB.money_text(cost, era_id)}
	rec["scale"] = int(rec.get("scale", 1)) + 1
	prof.save()
	var hit := _industry_event(rec)
	return {"ok": true, "reason": "", "hit": hit}


## 働き手を雇う（1人の支度金）
func wage() -> int:
	return 2000 + CraftDB.era_index(era_id) * 1000


## 職人に知識を教える（腕が上がる・知識が広まる＝歴史が動く）
func teach_workers(f: Facility, nid: String) -> Dictionary:
	var prof := Game.profile
	var m := Knowledge.mastery(prof, nid)
	if m < 30.0:
		return {"ok": false, "reason": "自分の習熟が足りない（30 以上）"}
	var old := float(f.rec.get("skill", 10))
	f.rec["skill"] = maxf(old, minf(m, old + 20.0))
	prof.practice("rhetoric", 0.3)
	prof.save()
	var hit := {}
	if Game.chaos and Game.chaos.is_active():
		hit = Game.chaos.act("teach", str(f.rec.get("at", "")), {"skill": nid, "level": int(m)})
	return {"ok": true, "old": old, "new": float(f.rec["skill"]), "hit": hit}


func _place(kind: String, d: Dictionary, w, rng: RandomNumberGenerator, used: Array) -> CraftStation:
	var at := str(d.get("at", "village"))
	if not (at in HistoryDB.LANDMARK_KEYS):
		at = "village"
	var center: Vector3 = w.landmark_pos(at)
	var near := str(d.get("near", ""))
	if near != "" and w.has_method("vehicle_spawns"):
		var sp: Array = w.vehicle_spawns(near)
		if not sp.is_empty():
			center = (sp[0] as Transform3D).origin + (sp[0] as Transform3D).basis.x * 12.0
	var ang := float(absi(hash(str(d.get("id", ""))))) / 1000.0
	var pos := center
	for tries in 8:
		var r := 14.0 + float((absi(hash(str(d.get("id", "")))) + tries * 7) % 12)
		var cand: Vector3 = center + Vector3(cos(ang), 0, sin(ang)) * r
		pos = w.random_ground_point_near(cand, 4.0, rng) if w.has_method("random_ground_point_near") else cand
		var ok := true
		for u in used:
			if (u as Vector3).distance_to(pos) < 7.0:
				ok = false
		if ok:
			break
		ang += 0.9
	used.append(pos)
	var yaw := atan2(center.x - pos.x, center.z - pos.z)
	var st := CraftStation.spawn(session, pos, yaw, kind, d, at)
	stations.append(st)
	if hud and "compass_points" in hud:
		var mark: String = {"workshop": "⚒", "shop": "＄", "loot": "蔵"}.get(kind, "")
		hud.compass_points[mark + str(d.get("name", ""))] = pos
	return st


func find_station(id: String) -> CraftStation:
	for s in stations:
		if is_instance_valid(s) and str(s.def.get("id", "")) == id:
			return s
	return null


# ------------------------------------------------------------------ 毎フレーム
func _interact_busy() -> bool:
	var ai = session.get("interact") if session else null
	if ai == null or not is_instance_valid(ai):
		return false
	return ai.is_open() or ai.get("_near") != null or ai.get("_near_site") != null


func _process(_dt: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or ui.is_open():
		return
	_near = null
	if not p.in_vehicle() and not stations.is_empty():
		var bd := RANGE
		for s in stations:
			if not is_instance_valid(s):
				continue
			var d := (s as Node3D).global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				_near = s
	if hud == null or hud.is_dialog_open():
		return
	if _near and not _interact_busy():
		hud.set_prompt(_near.prompt())
		_prompted = true
	elif _prompted:
		_prompted = false
		if not _interact_busy():
			hud.set_prompt("")


func _unhandled_input(ev: InputEvent) -> void:
	if ui.is_open() or Game.player == null:
		return
	if ev.is_action_pressed("inventory") and not Game.input_blocked:
		get_viewport().set_input_as_handled()
		ui.open_inventory()
		return
	if ev.is_action_pressed("interact") and _near and not Game.input_blocked and not _interact_busy() and not (hud and hud.is_dialog_open()):
		get_viewport().set_input_as_handled()
		open_station(_near)


func open_station(st: CraftStation) -> void:
	match st.kind:
		"factory":
			ui.open_factory(st as Facility)
		"workshop":
			ui.open_workshop(st)
		"shop":
			ui.open_shop(st)
		"loot":
			if st.looted:
				if hud:
					hud.toast("%sはもう空っぽだ" % st.display_name, 2.0)
				return
			var got := st.roll_loot()
			for g in got:
				Game.profile.add(str(g["id"]), int(g["n"]), float(g.get("q", 0.5)))
			var heat := float(st.def.get("heat", 1.5))
			Wanted.report(st.global_position, heat)
			ui.open_loot(st, got, heat)


# ------------------------------------------------------------------ 乗り物の稽古
func start_course(st: CraftStation, les: Dictionary) -> void:
	if course and is_instance_valid(course):
		course.abort()
	_course_station = st
	_course_lesson = les
	course = CourseLesson.start(session, st.global_position, str(les.get("vehicle", "horse")), str(les.get("title", "稽古")), hud)
	course.finished.connect(_course_done)


func _course_done(score: float) -> void:
	var sk := str(_course_lesson.get("skill", "riding"))
	var cap := float(_course_station.def.get("teaches", {}).get(sk, 100)) if _course_station and is_instance_valid(_course_station) else 100.0
	var before := Game.profile.raw_level(sk)
	var got := Game.profile.train(sk, 10.0 * (0.35 + 0.65 * score), cap)
	if hud:
		hud.toast("稽古「%s」終了　出来 %d 点　%s %.1f → %.1f" % [_course_lesson.get("title", ""), roundi(score * 100), Skills.skill_name(sk), before, before + got], 5.0)
		if session and str(session.get("mode")) == "free":
			hud.set_objective("自由探索", "好きに暴れろ。工房に弟子入りして技を磨け。人物に近づいて E で話せる。", "")
	course = null


func end_session() -> void:
	if course and is_instance_valid(course):
		course.abort()
	if ui and ui.is_open():
		ui.close()
