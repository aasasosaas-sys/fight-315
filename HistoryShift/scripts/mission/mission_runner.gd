class_name MissionRunner
extends Node
## ミッションのステップ（goto / talk / defeat / collect / ride）を順に進める。

signal completed
signal failed(reason: String)
signal step_changed(index: int)

var mission: Dictionary
var era: Dictionary
var steps: Array = []
var idx := -1
var hud
var spawn_root: Node3D
var _kills := 0
var _need := 0
var _targets: Array = []
var _npc: Npc
var _talking := false
var _timer := -1.0
var _ride_started := false
var _active_key := ""
var _rng := RandomNumberGenerator.new()


func setup(p_mission: Dictionary, p_era: Dictionary, p_hud, p_root: Node3D) -> void:
	mission = p_mission
	era = p_era
	steps = mission.get("steps", [])
	hud = p_hud
	spawn_root = p_root
	_rng.randomize()


func start() -> void:
	_begin(0)


func _world():
	return Game.world


func _player():
	return Game.player


func _pos(key: String) -> Vector3:
	var w = _world()
	return w.landmark_pos(key) if w else Vector3.ZERO


func _player_pos() -> Vector3:
	var p = _player()
	if p == null:
		return Vector3.ZERO
	return p.vehicle.global_position if p.in_vehicle() else p.global_position


func _counter_text() -> String:
	return "ステップ %d / %d" % [idx + 1, steps.size()]


func _begin(i: int) -> void:
	idx = i
	if _active_key != "" and _world():
		_world().set_beacon(_active_key, false)
	_active_key = ""
	_targets.clear()
	hud.extra_markers = []
	_timer = -1.0
	hud.set_timer(-1)
	hud.set_prompt("")
	if idx >= steps.size():
		hud.target_world = null
		completed.emit()
		return
	step_changed.emit(idx)
	var s: Dictionary = steps[idx]
	var key: String = s.get("at", "village")
	_active_key = key
	var lp := _pos(key)
	if _world():
		_world().set_beacon(key, true)
	hud.target_world = lp + Vector3.UP * 2.0
	hud.target_label = HistoryDB.landmark_name(era, key)
	var title: String = mission.get("title", "")
	var t: String = s.get("type", "goto")
	match t:
		"goto":
			hud.set_objective(title, s.get("text", ""), _counter_text())
		"talk":
			var pos: Vector3 = _world().random_ground_point_near(lp, 6.0, _rng) if _world() else lp
			_npc = Npc.spawn(spawn_root, pos, s.get("npc", "人物"), s.get("lines", ["……"]), era["eraId"])
			hud.target_world = pos + Vector3.UP * 2.4
			hud.target_label = s.get("npc", "人物")
			hud.set_objective(title, s.get("text", ""), _counter_text() + "　（近づいて E で話す）")
		"defeat":
			_kills = 0
			_need = int(s.get("count", 4))
			var label: String = s.get("enemy", "歴史の修正力")
			if s.get("air", false):
				_ensure_vehicle("plane")
				for n in _need:
					var ap := lp + Vector3(_rng.randf_range(-200, 200), _rng.randf_range(140, 230), _rng.randf_range(-200, 200))
					var ae := AirEnemy.spawn(spawn_root, ap, label)
					ae.mission_target = true
					ae.killed.connect(_on_kill)
					_targets.append(ae)
				hud.toast("上空に%sが現れた！ 飛行機で迎え撃て" % label, 4.0)
			else:
				for n in _need:
					var gp: Vector3 = _world().random_ground_point_near(lp, 22.0, _rng) if _world() else lp
					var e := Enemy.spawn(spawn_root, gp + Vector3.UP * 0.5, label, era["eraId"], n == _need - 1 and _need >= 4)
					e.mission_target = true
					e.killed.connect(_on_kill)
					_targets.append(e)
			hud.extra_markers = _targets.duplicate()
			hud.set_objective(title, s.get("text", ""), "撃破 0 / %d" % _need)
		"collect":
			_kills = 0
			_need = int(s.get("count", 3))
			var item: String = s.get("item", "アイテム")
			for n in _need:
				var cp: Vector3 = _world().random_ground_point_near(lp, 35.0, _rng) if _world() else lp
				var pk := Pickup.spawn(spawn_root, cp, item)
				pk.collected.connect(_on_collect)
				_targets.append(pk)
			if _need >= 3:
				for n in 2:
					var gp2: Vector3 = _world().random_ground_point_near(lp, 25.0, _rng)
					Enemy.spawn(spawn_root, gp2 + Vector3.UP * 0.5, "歴史の修正力", era["eraId"])
			hud.extra_markers = _targets.duplicate()
			hud.set_objective(title, s.get("text", ""), "%s 0 / %d" % [item, _need])
		"ride":
			var kind: String = s.get("vehicle", "horse")
			_ensure_vehicle(kind)
			_ride_started = false
			var spd := {"horse": 16.0, "car": 28.0, "plane": 70.0}.get(kind, 16.0) as float
			var dist := _player_pos().distance_to(lp)
			_timer = maxf(float(s.get("time", 60)), dist / spd * 1.7 + 20.0)
			var vname: String = {"horse": "馬", "car": "自動車", "plane": "飛行機"}.get(kind, kind)
			hud.set_objective(title, s.get("text", ""), "%sに乗って制限時間内に到着せよ" % vname)
			hud.set_timer(_timer)
		_:
			hud.set_objective(title, s.get("text", ""), _counter_text())


func _ensure_vehicle(kind: String) -> void:
	var p = _player()
	if p == null:
		return
	if p.in_vehicle() and p.vehicle.get("kind") == kind:
		return
	var pp := _player_pos()
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("kind") == kind and v.get("driver") == null and (v as Node3D).global_position.distance_to(pp) < 120.0:
			_mark_vehicle(v)
			return
	var w = _world()
	var xf := Transform3D(Basis(), pp + Vector3(4, 0, 4))
	if w:
		var spawns: Array = w.vehicle_spawns(kind)
		if spawns.size() > 0:
			var best: Transform3D = spawns[0]
			for sp in spawns:
				if (sp as Transform3D).origin.distance_to(pp) < best.origin.distance_to(pp):
					best = sp
			if best.origin.distance_to(pp) < 400.0 or kind == "plane":
				xf = best
			else:
				xf.origin = w.random_ground_point_near(pp, 8.0, _rng)
		else:
			xf.origin = w.random_ground_point_near(pp, 8.0, _rng)
	var v2 = Session.make_vehicle(kind, era["eraId"], _rng.randi())
	spawn_root.add_child(v2)
	v2.global_transform = xf
	v2.global_position += Vector3.UP * 0.6
	_mark_vehicle(v2)
	if kind == "plane" and xf.origin.distance_to(pp) > 60.0:
		hud.toast("滑走路に飛行機を用意した。向かえ！", 4.0)


func _mark_vehicle(v: Node3D) -> void:
	var p = _player()
	if p and p.in_vehicle():
		return
	hud.extra_markers = hud.extra_markers + [v]


func _on_kill(_e) -> void:
	_kills += 1
	hud.set_counter("撃破 %d / %d" % [_kills, _need])
	if _kills >= _need:
		hud.toast("撃破完了！")
		Sfx.play(get_tree(), Sfx.pickup(), -2.0)
		_begin(idx + 1)


func _on_collect(_p) -> void:
	_kills += 1
	var s: Dictionary = steps[idx]
	hud.set_counter("%s %d / %d" % [s.get("item", "アイテム"), _kills, _need])
	if _kills >= _need:
		hud.toast("すべて回収した！")
		_begin(idx + 1)


func _process(dt: float) -> void:
	if idx < 0 or idx >= steps.size() or get_tree().paused:
		return
	var s: Dictionary = steps[idx]
	var t: String = s.get("type", "goto")
	var p = _player()
	if p == null or not is_instance_valid(p) or p.dead:
		return
	var pp := _player_pos()
	var lp := _pos(s.get("at", "village"))
	var in_plane: bool = p.in_vehicle() and p.vehicle.get("kind") == "plane"
	var flat_d := Vector2(pp.x - lp.x, pp.z - lp.z).length()
	match t:
		"goto":
			if flat_d < (70.0 if in_plane else (22.0 if p.in_vehicle() else 14.0)):
				hud.toast("%sに到着" % HistoryDB.landmark_name(era, s.get("at", "")))
				_begin(idx + 1)
		"talk":
			if _npc == null or not is_instance_valid(_npc) or _talking:
				return
			var d := pp.distance_to(_npc.global_position)
			if d < 4.0 and not in_plane:
				hud.set_prompt("E：%sと話す" % _npc.npc_name)
				if Input.is_action_just_pressed("interact") and not hud.is_dialog_open():
					_talking = true
					hud.set_prompt("")
					hud.dialog(_npc.npc_name, _npc.lines)
					await hud.dialog_finished
					_talking = false
					if is_instance_valid(_npc):
						_npc.talked = true
					_begin(idx + 1)
			else:
				hud.set_prompt("")
		"ride":
			var kind: String = s.get("vehicle", "horse")
			var riding: bool = p.in_vehicle() and p.vehicle.get("kind") == kind
			if riding and not _ride_started:
				_ride_started = true
				hud.extra_markers = []
				hud.toast("出発！ 制限時間内に%sへ" % HistoryDB.landmark_name(era, s.get("at", "")))
			if _ride_started:
				_timer -= dt
				hud.set_timer(_timer)
				if _timer <= 0.0:
					hud.set_timer(-1)
					failed.emit("時間切れ")
					idx = steps.size() + 1
					return
				if riding and flat_d < (80.0 if kind == "plane" else 25.0):
					hud.toast("時間内に到着！")
					_begin(idx + 1)
