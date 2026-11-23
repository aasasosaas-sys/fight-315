class_name Session
extends Node3D
## 1回の時空跳躍（ミッション／自由探索／タイトル背景）。ワールド・プレイヤー・カメラ・HUD・町人・乗り物・手配度をまとめて管理する。

signal completed(changes: Array)
signal failed(reason: String)
signal aborted

var mode := "mission"     # mission / free / backdrop
var question: Dictionary = {}
var choice := -1
var mission: Dictionary = {}
var era: Dictionary = {}
var world
var player: Player
var cam: CameraRig
var hud: Hud
var runner: MissionRunner
var wanted: Wanted
var _ended := false


static func start_mission(q: Dictionary, p_choice: int) -> Session:
	var s := Session.new()
	s.mode = "mission"
	s.question = q
	s.choice = p_choice
	s.era = q["era"]
	s.mission = Game.db.mission_for(q, p_choice)
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
		hud.set_objective("自由探索", "好きに暴れろ。乗り物は F で奪える。Esc でメニュー。", "")
		hud.toast("馬・車・飛行機を探して乗り回せ！", 4.0)


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
	var changes := Game.state.apply_change(question, choice, mission.get("title", "改変"))
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


func end() -> void:
	_ended = true
	get_tree().paused = false
	Wanted.clear()
	Game.set_world(null)
	Game.player = null
	Game.input_blocked = true
	queue_free()
