class_name Session
extends Node3D
## 1回の時空跳躍（ミッション／自由探索／タイトル背景）。ワールド・プレイヤー・カメラ・HUD・町人・乗り物・手配度をまとめて管理する。

signal completed(changes: Array)
signal failed(reason: String)
signal aborted

var mode := "mission"     # mission / free / backdrop
var question: Dictionary = {}
var choice := -1
var method := 0
var mission: Dictionary = {}
var era: Dictionary = {}
var world
var player: Player
var cam: CameraRig
var hud: Hud
var runner: MissionRunner
var wanted: Wanted
var _ended := false
var figures: Array = []    # 自由探索に現れる歴史上の人物（HistFigure）
var interact: ActorInteract
var _appt_announced: Dictionary = {}


static func start_mission(q: Dictionary, p_choice: int, p_method := 0) -> Session:
	var s := Session.new()
	s.mode = "mission"
	s.question = q
	s.choice = p_choice
	s.era = q["era"]
	s.method = p_method
	s.mission = Game.db.mission_for(q, p_choice, p_method)
	return s


static func start_free_roam(era_id: String) -> Session:
	var s := Session.new()
	s.mode = "free"
	s.era = Game.db.get_era(era_id)
	return s


static func start_backdrop(era_id: String) -> Session:
	var s := Session.new()
	s.mode = "backdrop"
	s.era = Game.db.get_era(era_id)
	return s


static func build_world(p_era: Dictionary):
	if ResourceLoader.exists("res://scripts/world/era_world.gd") and not Game.has_meta("force_fallback_world"):
		var W = load("res://scripts/world/era_world.gd")
		if W and W.can_instantiate():
			return W.build(p_era)
	return FallbackWorld.build(p_era)


static func make_vehicle(kind: String, era_id: String, seed: int) -> Node3D:
	match kind:
		"car":
			return Car.create(seed, era_id)
		"plane":
			return Airplane.create(seed)
	return Horse.create(seed)


func _ready() -> void:
	name = "Session"
	add_to_group("session")
	get_tree().paused = false
	world = build_world(era)
	add_child(world)
	Game.set_world(world)
	cam = CameraRig.new()
	add_child(cam)

	if mode == "backdrop":
		var focus := Node3D.new()
		add_child(focus)
		focus.global_position = world.landmark_pos("capital")
		cam.set_target(focus, CameraRig.Mode.ORBIT)
		cam.global_position = focus.global_position + Vector3(190, 85, 0)
		Wanted.enabled = false
		_spawn_civilians(14)
		return

	Wanted.clear()
	Wanted.enabled = true
	hud = Hud.new()
	add_child(hud)
	hud.is_free_roam = mode == "free"
	for key in HistoryDB.LANDMARK_KEYS:
		hud.compass_points[HistoryDB.landmark_name(era, key)] = world.landmark_pos(key)
	hud.pause_abort.connect(_on_abort)

	player = Player.new()
	add_child(player)
	player.global_position = world.player_spawn + Vector3.UP * 0.5
	player.died.connect(_on_player_died)
	cam.set_target(player, CameraRig.Mode.ON_FOOT)
	cam.snap()

	wanted = Wanted.new()
	wanted.era_id = era["eraId"]
	add_child(wanted)
	_spawn_civilians(26)
	_spawn_vehicles()

	Effects.time_warp(get_tree(), player.global_position)
	Sfx.play(get_tree(), Sfx.warp(), -4.0)
	Game.input_blocked = false
	Game.lock_mouse(true)

	if mode == "mission":
		runner = MissionRunner.new()
		add_child(runner)
		runner.setup(mission, era, hud, self)
		runner.completed.connect(_on_completed)
		runner.failed.connect(_on_failed)
		hud.banner(era["eraName"], Color(0.95, 0.78, 0.35), 2.5)
		hud.toast(mission.get("title", ""), 4.0)
		runner.start()
	else:
		hud.banner(era["eraName"] + "　自由探索", Color(0.37, 0.91, 1.0), 2.5)
		hud.set_objective("自由探索", "好きに暴れろ。乗り物は F で奪える。人物に近づいて E で話せる（T でヒント切替）。\n※ 何をしても歴史は変わりうる。わざとでも、うっかりでも。", "")
		hud.toast("馬・車・飛行機を探して乗り回せ！", 4.0)
		_begin_chaos()


# ------------------------------------------------------------------ 自由探索の「歴史の揺らぎ」
func _begin_chaos() -> void:
	if Game.chaos == null:
		return
	Game.chaos.begin_session(era["eraId"], world)
	if not Game.chaos.shifted.is_connected(_on_history_shift):
		Game.chaos.shifted.connect(_on_history_shift)
	_spawn_figures()


## 自由探索に置く人物の一覧：揺らぎルールの figures ＋ その時代の人物（spawn のある人）＋ 各問題に「未来を語れる」人物を1人ずつ
static func figure_specs(era_id: String) -> Array:
	var out: Array = []
	var seen := {}
	for spec in Game.chaos.figures_for(era_id):
		var nm: String = Game.db.actor_name(str(spec.get("name", "")))
		var key := nm if nm != "" else str(spec.get("name", ""))
		if seen.has(key):
			continue
		seen[key] = true
		out.append(spec)
	for nm in Game.db.actors:
		var a: Dictionary = Game.db.actors[nm]
		var se: Dictionary = a.get("spawn_eras", {})
		if se.has(era_id) and not seen.has(nm):
			seen[nm] = true
			out.append({"name": nm, "at": se[era_id], "guards": 0 if HistoryActors.is_noncombatant(a) else 2, "lines": []})
	for q in Game.db.questions:
		if q["era"]["eraId"] != era_id:
			continue
		var cands: Array = Game.db.q_actors.get(q["id"], [])
		var has := false
		for c in cands:
			if seen.has(c["name"]):
				has = true
		if has or cands.is_empty():
			continue
		var pick: Dictionary = cands[0]
		for c in cands:
			if str(Game.db.actors[c["name"]].get("era", "")) == era_id:
				pick = c
				break
		seen[pick["name"]] = true
		out.append({"name": pick["name"], "at": pick["at"], "guards": 0, "lines": []})
	return out


func _spawn_figures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(era.get("eraId", "")) + 31
	var i := 0
	for spec in figure_specs(era["eraId"]):
		var key: String = spec.get("at", "capital")
		if not (key in HistoryDB.LANDMARK_KEYS):
			key = "capital"
		var center: Vector3 = world.landmark_pos(key)
		var pos: Vector3 = world.random_ground_point_near(center, 9.0, rng)
		var nm: String = str(spec.get("name", "人物"))
		var ad: Dictionary = Game.db.actor(nm)
		var f := HistFigure.spawn(self, pos + Vector3.UP * 0.5, nm, era["eraId"], spec.get("lines", []), ad)
		var an := Game.db.actor_name(nm)
		for qid in Game.db.q_actors:
			for c in Game.db.q_actors[qid]:
				if c["name"] == an and not (qid in f.questions):
					f.questions.append(qid)
		f.refresh_hint()
		figures.append(f)
		var label: String = spec.get("guard", Wanted.GUARDS.get(era["eraId"], "護衛"))
		var ng := int(spec.get("guards", 0)) if f.killable else 0
		for gi in ng:
			var ang := TAU * gi / maxf(1.0, float(ng))
			var gp: Vector3 = world.random_ground_point_near(pos + Vector3(cos(ang), 0, sin(ang)) * 4.0, 1.5, rng)
			var e := Enemy.spawn(self, gp + Vector3.UP * 0.5, label, era["eraId"], gi == 0 and ng >= 4)
			e.aggro_range = 16.0
			f.guards.append(e)
		# 予定（遅らせると歴史が揺らぐ）
		for sc in ad.get("schedule", []):
			if str(sc.get("at", "")) in HistoryDB.LANDMARK_KEYS:
				var start := 70.0 + i * 25.0
				f.set_appointment(sc, world.landmark_pos(str(sc["at"])), start, start + 120.0)
				break
		hud.compass_points["◆" + f.figure_name] = pos
		i += 1
	hud.extra_markers = figures.duplicate()
	_spawn_battles(rng)
	interact = ActorInteract.new()
	interact.setup(self, hud, figures)
	add_child(interact)
	_appt_announced.clear()


## 合戦：両軍の兵を名所に置く。片方を倒すと、もう片方に加勢したことになる
func _spawn_battles(rng: RandomNumberGenerator) -> void:
	for b in Game.db.battles:
		if str(b.get("era", "")) != era["eraId"]:
			continue
		var center: Vector3 = world.landmark_pos(str(b.get("at", "battlefield")))
		var sides: Array = b.get("sides", [])
		for si in sides.size():
			for k in 6:
				var off := Vector3((si * 2 - 1) * 14.0, 0, (k - 2.5) * 4.0)
				var gp: Vector3 = world.random_ground_point_near(center + off, 2.0, rng)
				var e := Enemy.spawn(self, gp + Vector3.UP * 0.5, str(sides[si].get("label", "兵")), era["eraId"], k == 0)
				e.aggro_range = 12.0
		hud.compass_points["⚔" + str(b.get("name", ""))] = center


func _process(_dt: float) -> void:
	if mode != "free" or hud == null:
		return
	for f in figures:
		if not is_instance_valid(f) or f.dead or f.appointment.is_empty() or _appt_announced.has(f):
			continue
		if f._t >= f.appt_start:
			_appt_announced[f] = true
			hud.toast("%sが「%s」のため%sへ向かい始めた" % [f.figure_name, f.appointment.get("event", ""), HistoryDB.landmark_name(era, str(f.appointment.get("at", "")))], 4.0)


## 自由探索中に混乱ルールが発動した：派手に知らせる
func _on_history_shift(hit: Dictionary) -> void:
	if hud == null or _ended:
		return
	var lines: PackedStringArray = []
	var number := {}
	for i in Game.db.questions.size():
		number[Game.db.questions[i]["id"]] = i + 1
	var changes: Array = hit.get("changes", [])
	for c in changes.slice(0, 3):
		var q: Dictionary = c["question"]
		var ans := Game.state.answer(q)
		var mark := "－" if ans < 0 else ("○" if Game.state.is_correct(q) else "×")
		lines.append("%s 問%02d『%s』の史実 → %s" % [mark, number.get(q["id"], 0), q["topic"], JSUI.circled(int(c["to"]))])
	if changes.size() > 3:
		lines.append("……ほか %d 問の史実も連鎖して変化" % (changes.size() - 3))
	if changes.is_empty():
		lines.append("（試験の設問の史実は無事。だが、その後の歴史の流れが変わった）")
	hud.history_shift("%s\n%s" % [hit.get("title", ""), hit.get("text", "")], bool(hit.get("broke", false)), "\n".join(lines))
	for c in changes:
		if c.get("now_correct", false) and not c.get("was_correct", true):
			hud.toast("第%d問 ○ 正解に！" % number.get(c["question"]["id"], 0), 5.0)
	for f in figures:
		if is_instance_valid(f):
			f.refresh_hint()
	if player:
		Effects.time_warp(get_tree(), player.global_position)


func _spawn_civilians(n: int) -> void:
	var pts: Array = world.street_points() if world.has_method("street_points") else []
	if pts.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(era.get("eraId", ""))
	for i in n:
		var p: Vector3 = pts[rng.randi() % pts.size()]
		Civilian.spawn(self, p + Vector3(rng.randf_range(-3, 3), 0.5, rng.randf_range(-3, 3)), era["eraId"], pts)


func _spawn_vehicles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(era.get("eraId", "")) + 7
	for kind in era.get("vehicles", []):
		var spawns: Array = world.vehicle_spawns(kind)
		var cap := 6 if kind == "horse" else (5 if kind == "car" else 3)
		for i in mini(cap, spawns.size()):
			var v := make_vehicle(kind, era["eraId"], rng.randi())
			add_child(v)
			v.global_transform = spawns[i]
			v.global_position += Vector3.UP * 0.6
	# 確実に1台はプレイヤーのそばに
	var first: String = era.get("vehicles", ["horse"])[0]
	var v0 := make_vehicle(first, era["eraId"], 99)
	add_child(v0)
	v0.global_position = world.random_ground_point_near(world.player_spawn, 7.0, rng) + Vector3.UP * 0.6


func _on_completed() -> void:
	if _ended:
		return
	Sfx.play(get_tree(), Sfx.success(), -2.0)
	hud.banner("歴史改変 成功", Color(0.37, 0.91, 1.0), 2.0)
	Effects.time_warp(get_tree(), player.global_position)
	var changes := Game.state.apply_change(question, choice, "%s（%s）" % [mission.get("title", "改変"), mission.get("method", "介入")], method)
	Game.input_blocked = true
	await get_tree().create_timer(2.8).timeout
	if _ended:
		return
	Game.lock_mouse(false)
	completed.emit(changes)


func _on_failed(reason: String) -> void:
	if _ended:
		return
	Sfx.play(get_tree(), Sfx.fail(), -2.0)
	hud.show_death(reason)
	Game.input_blocked = true
	await get_tree().create_timer(2.5).timeout
	if _ended:
		return
	Game.lock_mouse(false)
	failed.emit(reason)


func _on_player_died() -> void:
	if mode == "free":
		hud.show_death("力尽きた……")
		await get_tree().create_timer(2.5).timeout
		if _ended:
			return
		hud._death.visible = false
		Wanted.clear()
		player.heal_full()
		player.rig.queue_free()
		player.rig = Humanoid.build(Humanoid.Outfit.AGENT, 7, true)
		player.rig.rotation.y = PI
		player.add_child(player.rig)
		player.teleport(world.player_spawn)
		return
	_on_failed("力尽きた")


func _on_abort() -> void:
	if _ended:
		return
	Game.lock_mouse(false)
	aborted.emit()


func _exit_tree() -> void:
	# end() を経ずに破棄された場合も、混乱の記録を止める
	if mode == "free" and Game.chaos and Game.chaos.world == world:
		Game.chaos.end_session()


func end() -> void:
	_ended = true
	if mode == "free" and Game.chaos:
		Game.chaos.end_session()
		if Game.chaos.shifted.is_connected(_on_history_shift):
			Game.chaos.shifted.disconnect(_on_history_shift)
	get_tree().paused = false
	Wanted.clear()
	Game.set_world(null)
	Game.player = null
	Game.input_blocked = true
	queue_free()
