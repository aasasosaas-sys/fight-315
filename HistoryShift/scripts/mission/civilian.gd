class_name Civilian
extends CharacterBody3D
## 町人。通りを歩き、銃声や爆発で逃げ惑い、車が来ると飛びのく。攻撃しても倒れない（伏せて逃げる）。
## 例外：設定「民間人への危害（成人向け）」がオンで、史実の虐殺・戦災に重なる場面でなければ、プレイヤーが原因の被害で倒れる
## （scripts/core/civil_harm.gd）。流血・遺体は出さない：アニメ調に倒れ、数秒で薄れて消える。

var points: Array = []
var era_id := ""
var _rig: Humanoid
var _goal := Vector3.ZERO
var _panic := 0.0
var _flee_from := Vector3.ZERO
var _wait := 0.0
var _dodge := Vector3.ZERO
static var _scream_t := 0.0
var hp := 35.0
var down := false
var _harm_t := 0.0
var _intact := {}             # 前回見たとき崩れていなかった近くの建物（新しく崩れたものだけ瓦礫の被害にする）
var _last_cause := "shot"


static func spawn(parent: Node, pos: Vector3, p_era: String, pts: Array) -> Civilian:
	var c := Civilian.new()
	c.era_id = p_era
	c.points = pts
	parent.add_child(c)
	c.global_position = pos
	c._goal = pos
	return c


func _ready() -> void:
	add_to_group("civilian")
	collision_layer = Game.COLLISION_CIVILIAN
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	add_child(cs)
	_rig = Humanoid.build_streamed(Humanoid.outfit_for(era_id, "civilian"), randi(), false, -1, "", Humanoid.PRIORITY_CROWD)
	_rig.rotation.y = PI
	add_child(_rig)
	_pick_goal()


func panic(from: Vector3) -> void:
	if global_position.distance_to(from) > 60.0:
		return
	_panic = randf_range(6.0, 10.0)
	_flee_from = from
	_wait = 0.0


func take_hit(_a: float, _t: int, point := Vector3.ZERO, _d := Vector3.ZERO) -> void:
	if civil_hit(_a, _t, point, _d):
		return
	panic(point)


## 民間人への危害（設定オンのときだけ）。被害を受けたら true（呼び出し側は panic の代わりにこれで済ませる）。
## オフ・除外の場面・プレイヤーが原因でない被害では false（従来どおり逃げるだけ）
func civil_hit(amount: float, team: int, point := Vector3.ZERO, _dir := Vector3.ZERO, unit_cause := "") -> bool:
	if down:
		return true
	if not CivilRuntime.player_caused(team, unit_cause):
		return false
	if not CivilRuntime.allowed_here(get_tree(), era_id, global_position):
		return false
	_last_cause = {-2: "fire", -3: "debris"}.get(team, "shot" if team == 0 else "explosion")
	panic(point if point != Vector3.ZERO else global_position + Vector3.FORWARD)
	hp -= amount
	if _rig and _rig.has_method("hurt"):
		_rig.call("hurt")
	if hp <= 0.0:
		_fall()
	return true


## 倒れる：アニメ調に倒れ、少しして薄れて消える（血・遺体・部位の欠損はない）
func _fall() -> void:
	down = true
	remove_from_group("civilian")
	collision_layer = 0
	collision_mask = Game.COLLISION_WORLD
	velocity = Vector3.ZERO
	if _rig and _rig.has_method("die"):
		_rig.call("die")
	CivilRuntime.on_casualty(era_id, global_position, _last_cause)
	get_tree().call_group("civilian", "panic", global_position)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_method(_set_fade, 0.0, 1.0, 1.6)
	tw.tween_callback(queue_free)


func _set_fade(a: float) -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = a


## 火・崩れた建物・乗り物（設定オンのときだけ。0.4 秒ごと）
func _harm_check() -> void:
	var d = Destruction.current
	if d != null and is_instance_valid(d):
		var near: Array = d.units_near(global_position, 3.0)
		for u in d.units_near(global_position, 6.0):
			if not u.destroyed:
				_intact[u.id] = true
				if u.burning and u in near and civil_hit(12.0, -2, global_position, Vector3.ZERO, str(u.fire_cause)):
					return
			elif _intact.has(u.id):
				_intact.erase(u.id)
				if u in near and civil_hit(60.0, -3, global_position, Vector3.ZERO, str(u.last_cause)):
					return
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("driver") == null or v.get("driver") != Game.player:
			continue
		var vv: Vector3 = v.get_velocity_vec() if v.has_method("get_velocity_vec") else Vector3.ZERO
		if vv.length() > 7.0 and (v as Node3D).global_position.distance_to(global_position) < 2.4:
			civil_hit(vv.length() * 5.0, 0, global_position, vv.normalized())
			return


func _pick_goal() -> void:
	if points.is_empty():
		_goal = global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
		return
	# 近くの地点を優先
	var best: Vector3 = points[randi() % points.size()]
	for i in 4:
		var c: Vector3 = points[randi() % points.size()]
		if c.distance_to(global_position) < best.distance_to(global_position) and c.distance_to(global_position) > 6.0:
			best = c
	_goal = best


func _physics_process(dt: float) -> void:
	if down:
		velocity = Vector3(0, -1.0 if is_on_floor() else velocity.y - 22.0 * dt, 0)
		move_and_slide()
		return
	if CivilHarm.enabled():
		_harm_t -= dt
		if _harm_t <= 0.0:
			_harm_t = 0.4
			_harm_check()
			if down:
				return
		# 民心離反：犠牲が出た時代では、町人はあなたを見るだけで逃げる
		if CivilRuntime.unrest_level() >= 1 and Game.player and _panic <= 0.0 and (Game.player as Node3D).global_position.distance_to(global_position) < 8.0 + 6.0 * CivilRuntime.unrest_level():
			panic((Game.player as Node3D).global_position)
	var move := Vector3.ZERO
	var spd := 1.4
	_panic = maxf(0.0, _panic - dt)
	if _panic > 0.0:
		var away := global_position - _flee_from
		away.y = 0
		move = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		spd = 6.5
		_rig.crouch = lerpf(_rig.crouch, 0.35 if _panic > 7.0 else 0.0, dt * 4.0)
	else:
		_rig.crouch = lerpf(_rig.crouch, 0.0, dt * 3.0)
		if _wait > 0.0:
			_wait -= dt
		else:
			var to := _goal - global_position
			to.y = 0
			if to.length() < 1.5:
				_wait = randf_range(1.0, 6.0)
				_pick_goal()
			else:
				move = to.normalized()
	# 迫る乗り物から飛びのく
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("driver") == null:
			continue
		var vv: Vector3 = v.get_velocity_vec() if v.has_method("get_velocity_vec") else Vector3.ZERO
		var rel: Vector3 = global_position - (v as Node3D).global_position
		if rel.length() < 9.0 and vv.length() > 5.0 and vv.normalized().dot(-rel.normalized()) < -0.5:
			_dodge = vv.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0) * 8.0
			panic(v.global_position)
	if _dodge.length() > 0.1:
		move = _dodge.normalized()
		spd = 8.0
		_dodge = _dodge.move_toward(Vector3.ZERO, dt * 12.0)
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	velocity.y = -1.0 if is_on_floor() else velocity.y - 22.0 * dt
	move_and_slide()
	if move.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), dt * 8.0)
	_rig.speed = Vector2(velocity.x, velocity.z).length()
	if get_slide_collision_count() > 0 and _panic <= 0.0 and _wait <= 0.0 and randf() < 0.02:
		_pick_goal()
	var w = Game.world
	if w and global_position.y < w.height_at(global_position.x, global_position.z) - 3.0:
		global_position.y = w.height_at(global_position.x, global_position.z) + 1.0
