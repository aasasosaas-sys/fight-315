class_name CourseLesson
extends Node3D
## 乗り物の稽古（乗馬・路上教習・飛行訓練）。工房のそばに乗り物を出し、目印（旗・空の輪）を順に回る。
## 終わると finished(score)。score = 回った割合 × 時間の評価 − ぶつけた分。

signal finished(score: float)

var vehicle_kind := "horse"
var title := ""
var points: Array = []          # Array[Vector3]
var _marks: Array = []
var _i := 0
var _t := 0.0
var _limit := 90.0
var _par := 45.0
var _vehicle: Node3D
var _hp0 := 0.0
var _done := false
var hud


static func start(parent: Node, center: Vector3, kind: String, p_title: String, p_hud) -> CourseLesson:
	var c := CourseLesson.new()
	c.vehicle_kind = kind
	c.title = p_title
	c.hud = p_hud
	parent.add_child(c)
	c.global_position = center
	c._setup(center)
	return c


func _setup(center: Vector3) -> void:
	var w = Game.world
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var era := str(w.get("era_id")) if w and "era_id" in w else "edo"
	var spawn_xf := Transform3D(Basis(), center + Vector3(4, 0, 4))
	if vehicle_kind == "plane" and w and w.has_method("vehicle_spawns"):
		var sp: Array = w.vehicle_spawns("plane")
		if not sp.is_empty():
			spawn_xf = sp[0]
	_vehicle = Session.make_vehicle(vehicle_kind, era, rng.randi())
	get_parent().add_child(_vehicle)
	_vehicle.global_transform = spawn_xf
	if w and w.has_method("height_at"):
		_vehicle.global_position.y = w.height_at(_vehicle.global_position.x, _vehicle.global_position.z) + 0.6
	_hp0 = float(_vehicle.get("hp")) if _vehicle.get("hp") != null else 0.0
	var base := _vehicle.global_position
	match vehicle_kind:
		"plane":
			_limit = 200.0
			_par = 90.0
			var fwd := -_vehicle.global_basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			var right := fwd.cross(Vector3.UP)
			for k in 4:
				var a := TAU * k / 4.0
				points.append(base + fwd * 260.0 + (fwd * cos(a) + right * sin(a)) * 170.0 + Vector3.UP * (70.0 + k * 15.0))
		_:
			_limit = 100.0
			_par = 40.0 if vehicle_kind == "horse" else 35.0
			var r := 30.0 if vehicle_kind == "horse" else 45.0
			for k in 5:
				var a2 := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
				var p: Vector3 = base + Vector3(cos(a2), 0, sin(a2)) * r
				if w and w.has_method("random_ground_point_near"):
					p = w.random_ground_point_near(p, 8.0, rng)
				points.append(p)
	for i in points.size():
		_marks.append(_make_mark(points[i], i))
	_refresh()
	if hud:
		hud.toast("%s：%sに乗り（F）、目印を順に回れ" % [title, {"horse": "馬", "car": "車", "plane": "飛行機"}.get(vehicle_kind, "")], 4.0)


func _make_mark(p: Vector3, i: int) -> Node3D:
	var n := Node3D.new()
	get_parent().add_child(n)
	n.global_position = p
	var col := Color(1.0, 0.8, 0.3)
	if vehicle_kind == "plane":
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 9.0
		tm.outer_radius = 10.0
		mi.mesh = tm
		mi.rotation_degrees.x = 90
		mi.material_override = Effects.emissive(Color(col, 0.8), 2.0)
		n.add_child(mi)
	else:
		Humanoid.part(n, "box", Humanoid.mat(Color(0.4, 0.3, 0.2), 0.8), Vector3(0, 1.5, 0), Vector3(0.1, 3.0, 0.1))
		Humanoid.part(n, "box", Effects.emissive(col, 1.5), Vector3(0.45, 2.7, 0), Vector3(0.8, 0.5, 0.03))
	var tag := Label3D.new()
	tag.text = str(i + 1)
	tag.font_size = 96 if vehicle_kind == "plane" else 64
	tag.pixel_size = 0.02 if vehicle_kind == "plane" else 0.008
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 12
	tag.position = Vector3(0, 12 if vehicle_kind == "plane" else 3.6, 0)
	n.add_child(tag)
	return n


func _refresh() -> void:
	for k in _marks.size():
		if is_instance_valid(_marks[k]):
			(_marks[k] as Node3D).visible = k >= _i
			(_marks[k] as Node3D).scale = Vector3.ONE * (1.25 if k == _i else 1.0)
	if hud and _i < points.size():
		hud.target_world = points[_i] + Vector3.UP * 2.0
		hud.target_label = "目印 %d" % (_i + 1)
		hud.set_objective("稽古：" + title, "%sに乗り、目印を順に回れ。" % {"horse": "馬", "car": "車", "plane": "飛行機"}.get(vehicle_kind, ""), "目印 %d / %d" % [_i, points.size()])


func _process(dt: float) -> void:
	if _done:
		return
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var riding: bool = p.in_vehicle() and str(p.vehicle.get("kind")) == vehicle_kind
	if riding:
		_t += dt
	if hud:
		hud.set_timer(maxf(0.0, _limit - _t))
	if not is_instance_valid(_vehicle) or (_vehicle.get("hp") != null and float(_vehicle.get("hp")) <= 0.0):
		_end(0.15)
		return
	if _t >= _limit:
		_end(0.35 * float(_i) / maxf(1.0, float(points.size())))
		return
	if riding and _i < points.size():
		var vp: Vector3 = (p.vehicle as Node3D).global_position
		var r := 12.0 if vehicle_kind == "plane" else 6.0
		if vp.distance_to(points[_i]) < r:
			_i += 1
			Sfx.play(get_tree(), Sfx.pickup(), -4.0)
			_refresh()
			if _i >= points.size():
				var time_k := clampf(1.0 - maxf(0.0, _t - _par) / (_limit - _par), 0.5, 1.0)
				var dmg := 0.0
				if _vehicle.get("hp") != null and _hp0 > 0.0:
					dmg = clampf((_hp0 - float(_vehicle.get("hp"))) / _hp0, 0.0, 1.0)
				_end(clampf(time_k - dmg * 0.5, 0.2, 1.0))


## テスト用：目印を全部回ったことにする
func complete_now(score := 0.8) -> void:
	_end(score)


func abort() -> void:
	_end(0.0)


func _end(score: float) -> void:
	if _done:
		return
	_done = true
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	if hud:
		hud.target_world = null
		hud.set_timer(-1)
	finished.emit(score)
	queue_free()
