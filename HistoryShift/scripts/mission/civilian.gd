class_name Civilian
extends CharacterBody3D
## 町人。通りを歩き、銃声や爆発で逃げ惑い、車が来ると飛びのく。攻撃しても倒れない（伏せて逃げる）。

var points: Array = []
var era_id := ""
var _rig: Humanoid
var _goal := Vector3.ZERO
var _panic := 0.0
var _flee_from := Vector3.ZERO
var _wait := 0.0
var _dodge := Vector3.ZERO
static var _scream_t := 0.0


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
	_rig = Humanoid.build(Humanoid.outfit_for(era_id, "civilian"), randi(), false)
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
	panic(point)


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
