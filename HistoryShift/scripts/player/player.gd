class_name Player
extends CharacterBody3D
## 時空エージェント。走る・跳ぶ・撃つ・乗り物を奪う・パラシュート。

signal died

const TEAM := 0
var max_hp := 150.0
var hp := 150.0
var regen := 12.0
var dead := false
var vehicle = null              # 乗っている乗り物（group "vehicle"）
var parachuting := false
var god_mode := false

# 銃
var mag_size := 30
var ammo := 30
var fire_rate := 9.0
var damage := 26.0
var reloading := false
var _reload_end := 0.0
var _next_shot := 0.0
var _last_hit := -99.0
var _vehicle_cd := 0.0

var rig: Humanoid
var tools: DestructionTools     # 破壊ツール（scripts/player/destruction_tools.gd）
var arms: PlayerArms            # 手持ち武器（素手・刀・槍・弓・銃。scripts/player/player_arms.gd）。現代の高校生なので最初は素手
var _chute: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.COLLISION_PLAYER
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_ENEMY | Game.COLLISION_CIVILIAN | Game.COLLISION_VEHICLE | Game.COLLISION_PROP
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	_shape.shape = cap
	_shape.position = Vector3(0, 0.9, 0)
	add_child(_shape)
	rig = Humanoid.build(Humanoid.Outfit.AGENT, 7, true)
	rig.rotation.y = PI
	add_child(rig)
	_chute = Node3D.new()
	_chute.position = Vector3(0, 4.3, 0)
	add_child(_chute)
	Humanoid.part(_chute, "sphere", Humanoid.mat(Color(0.9, 0.3, 0.2), 0.8), Vector3.ZERO, Vector3(5, 1.4, 5))
	_chute.visible = false
	# 破壊ツール（1-5 で切替、G で焙烙玉）
	tools = DestructionTools.new()
	add_child(tools)
	arms = PlayerArms.new()
	add_child(arms)
	Game.player = self


func _enter_tree() -> void:
	Game.player = self


func _exit_tree() -> void:
	# 乗り物への reparent でも呼ばれるので、本当に消える時だけ解除する
	if Game.player == self and is_queued_for_deletion():
		Game.player = null


func in_vehicle() -> bool:
	return vehicle != null and is_instance_valid(vehicle)


func take_hit(amount: float, from_team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if dead or from_team == TEAM or god_mode:
		return
	if arms != null:
		amount = arms.filter_damage(amount, _dir)   # 刀で受ける・受け流す（剣術）
		if amount <= 0.0:
			return
	hp = maxf(0.0, hp - amount)
	_last_hit = Time.get_ticks_msec() / 1000.0
	rig.hurt()
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.damage_flash(amount)
	if hp <= 0.0:
		dead = true
		if in_vehicle():
			exit_vehicle()
		rig.die()
		died.emit()


func heal_full() -> void:
	hp = max_hp
	dead = false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(dt: float) -> void:
	if dead:
		return
	var blocked := Game.input_blocked
	_vehicle_cd -= dt
	if _now() - _last_hit > 4.0:
		hp = minf(max_hp, hp + regen * dt * (Skills.regen_mult(Game.profile.level("medicine")) if Game.profile else 1.0))   # 医術で回復が速い

	if in_vehicle():
		rig.speed = vehicle.get_speed() if vehicle.has_method("get_speed") else 0.0
		if not blocked and Input.is_action_just_pressed("vehicle") and _vehicle_cd <= 0.0:
			exit_vehicle()
		elif not blocked and vehicle.get("kind") != "plane":
			_hand_weapon(dt)
		return

	var cam := CameraRig.I
	var mv := Vector2.ZERO
	if not blocked:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var wish := Vector3.ZERO
	if cam:
		wish = cam.flat_forward() * mv.y + cam.flat_right() * mv.x
	var aiming := not blocked and (Input.is_action_pressed("aim") or Input.is_action_pressed("fire"))
	var spd := 3.8 if aiming else (9.5 if not blocked and Input.is_action_pressed("sprint") else 5.2)

	if is_on_floor():
		parachuting = false
		if not blocked and Input.is_action_just_pressed("jump"):
			velocity.y = 6.8
	else:
		velocity.y -= 22.0 * dt
		if velocity.y < -14.0:
			parachuting = true
		if parachuting:
			velocity.y = maxf(velocity.y, -4.5)
	_chute.visible = parachuting

	var control := 1.0 if is_on_floor() else (0.6 if parachuting else 0.3)
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.lerp(wish * spd, 1.0 - exp(-dt * 12.0 * control))
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	# 地形の下・場外に落ちないように
	var w = Game.world
	if w and w.has_method("height_at"):
		var h: float = w.height_at(global_position.x, global_position.z)
		if global_position.y < h - 3.0:
			global_position.y = h + 1.0
			velocity = Vector3.ZERO
		var lim: float = w.half_size - 5.0
		global_position.x = clampf(global_position.x, -lim, lim)
		global_position.z = clampf(global_position.z, -lim, lim)

	var face := cam.flat_forward() if (aiming and cam) else (hv.normalized() if hv.length() > 0.7 else Vector3.ZERO)
	if face != Vector3.ZERO:
		var target_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-dt * (25.0 if aiming else 10.0)))
	rig.speed = hv.length()
	rig.aiming = aiming
	if cam:
		cam.aiming = not blocked and Input.is_action_pressed("aim")

	if not blocked:
		_hand_weapon(dt)
		if Input.is_action_just_pressed("vehicle") and _vehicle_cd <= 0.0:
			var v = _nearest_vehicle(5.0)
			if v:
				enter_vehicle(v)


## 手持ち武器（PlayerArms）。破壊ツールを構えている間は使わない
func _hand_weapon(dt: float) -> void:
	if tools != null and tools.blocks_gun():
		return
	if arms == null:
		_gun(dt)
		return
	arms.tick(dt)
	ammo = arms.mag()
	reloading = arms.reloading


## 旧来の銃（PlayerArms が無いときだけ）
func _gun(_dt: float) -> void:
	if tools != null and tools.blocks_gun():
		return
	var t := _now()
	if reloading and t >= _reload_end:
		reloading = false
		ammo = mag_size
	if not reloading and ((Input.is_action_just_pressed("reload") and ammo < mag_size) or ammo <= 0):
		reloading = true
		_reload_end = t + 1.3
	if reloading or not Input.is_action_pressed("fire") or t < _next_shot:
		return
	_next_shot = t + 1.0 / fire_rate
	ammo -= 1
	var cam := CameraRig.I
	if cam == null:
		return
	rig.aiming = true
	var ex: Array[RID] = [get_rid()]
	if in_vehicle() and vehicle is CollisionObject3D:
		ex.append((vehicle as CollisionObject3D).get_rid())
	var hit := cam.aim_hit(500.0, ex)
	var muzzle_pos: Vector3 = rig.muzzle.global_position if rig.muzzle else global_position + Vector3.UP * 1.4
	var spread := (0.004 if cam.aiming else 0.014) + (0.01 if in_vehicle() else 0.0)
	var dir := cam.aim_dir()
	var end := cam.global_position + dir * 500.0
	if not hit.is_empty():
		end = hit["position"]
	end += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread * muzzle_pos.distance_to(end)
	# 銃口からの実際の弾道で再判定
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + (end - muzzle_pos).normalized() * 520.0)
	q.exclude = ex
	var h2 := space.intersect_ray(q)
	if not h2.is_empty():
		end = h2["position"]
	Effects.muzzle(get_tree(), muzzle_pos, (end - muzzle_pos).normalized(), Effects.CYAN)
	Effects.tracer(get_tree(), muzzle_pos, end, Effects.CYAN, 0.035)
	Sfx.play(get_tree(), Sfx.shot(), -10.0)
	Wanted.report(global_position, 0.025)
	if not h2.is_empty():
		Player.apply_hit(get_tree(), h2, (end - muzzle_pos).normalized(), damage, TEAM)


## 弾の命中処理（プレイヤー・敵・機銃で共用）
static func apply_hit(tree: SceneTree, hit: Dictionary, dir: Vector3, dmg: float, team: int) -> void:
	if team == 0:
		Destruction.note_player()   # 撃った樽の誘爆などを player_indirect として数える
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	var target: Node = Effects.find_target(col as Node) if col is Node else null
	if target and target.has_method("civil_hit") and target.civil_hit(dmg, team, pos, dir):
		Effects.spark(tree, pos, nrm, Color.WHITE)   # 民間人への危害（設定オンのときだけ。血は出さない。scripts/core/civil_harm.gd）
	elif target and target.has_method("panic") and not target.has_method("is_enemy"):
		target.panic(pos)  # 町人は倒れない：伏せて逃げる
		Effects.spark(tree, pos, nrm, Color.WHITE)
	elif target and target.has_method("take_hit"):
		target.take_hit(dmg, team, pos, dir)
		var guard: bool = target.get("is_guardian") == true
		if target is Explosive or target.is_in_group("vehicle") or target.is_in_group("destructible") or target.is_in_group("physics_prop"):
			Effects.spark(tree, pos, nrm)
		else:
			Effects.blood(tree, pos, nrm, guard)
		if team == 0:
			var hud = tree.get_first_node_in_group("hud")
			if hud and target.has_method("is_enemy"):
				hud.hit_marker(target.get("dead") == true)
	else:
		Effects.spark(tree, pos, nrm)
	if col is RigidBody3D:
		(col as RigidBody3D).apply_impulse(dir * 14.0, pos - (col as RigidBody3D).global_position)


func _nearest_vehicle(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("driver") != null:
			continue
		var d: float = (v as Node3D).global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = v
	return best


func enter_vehicle(v) -> void:
	if v == null or v.get("driver") != null:
		return
	vehicle = v
	_vehicle_cd = 0.5
	velocity = Vector3.ZERO
	parachuting = false
	_chute.visible = false
	_shape.disabled = true
	collision_layer = 0
	set_physics_process(true)
	reparent(v.get("seat"), false)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	rig.riding = true
	v.enter(self)
	var kind: String = v.get("kind")
	if CameraRig.I:
		CameraRig.I.set_target(v, CameraRig.Mode.PLANE if kind == "plane" else CameraRig.Mode.GROUND)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("%sに乗った（F で降りる）" % v.get("display_name"))
	if kind == "plane" and hud:
		hud.toast("W/S:スロットル  マウス:進路  左クリック:機銃  Shift:ブースト")


func exit_vehicle() -> void:
	if not in_vehicle():
		vehicle = null
		return
	var v = vehicle
	vehicle = null
	_vehicle_cd = 0.5
	var exit_pos: Vector3 = v.exit_point()
	var vel: Vector3 = v.get_velocity_vec() if v.has_method("get_velocity_vec") else Vector3.ZERO
	v.exit()
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var sess = get_tree().get_first_node_in_group("session")
	reparent(sess if sess else root, false)
	global_position = exit_pos
	rotation = Vector3(0, v.global_rotation.y, 0)
	velocity = vel * 0.6
	rig.riding = false
	_shape.disabled = false
	collision_layer = Game.COLLISION_PLAYER
	if CameraRig.I:
		CameraRig.I.set_target(self, CameraRig.Mode.ON_FOOT)


func teleport(pos: Vector3) -> void:
	if in_vehicle():
		exit_vehicle()
	global_position = pos + Vector3.UP * 0.3
	velocity = Vector3.ZERO
	if CameraRig.I:
		CameraRig.I.snap()
