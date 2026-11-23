class_name Airplane
extends CharacterBody3D
## プロペラ機。マウス方向へ機首を向けるマウスエイム式。W/S スロットル、Shift ブースト、A/D ロール、左クリック 機銃。
## 速度が足りれば離陸。地面・建物に高速で突っ込むと墜落・爆発（脱出）。

var kind := "plane"
var display_name := "飛行機"
var driver = null
var seat: Node3D
var hp := 300.0
var throttle := 0.0
var speed := 0.0
var airborne := false
var _bank := 0.0
var _roll_extra := 0.0
var _prop: Node3D
var _visual: Node3D
var _sound: AudioStreamPlayer3D
var _next_shot := 0.0
var _guns: Array[Node3D] = []
var _dead := false
const TAKEOFF := 30.0
const GEAR := 1.1


static func create(seed: int) -> Airplane:
	var p := Airplane.new()
	p.name = "Plane"
	p._build(seed)
	return p


func _build(seed: int) -> void:
	add_to_group("vehicle")
	collision_layer = Game.COLLISION_VEHICLE
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0, 1.6, 8.0)
	cs.shape = bx
	cs.position = Vector3(0, 1.2, 0)
	add_child(cs)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var base: Color = [Color(0.72, 0.74, 0.7), Color(0.28, 0.34, 0.24), Color(0.6, 0.6, 0.62)][rng.randi() % 3]
	var m := Humanoid.mat(base, 0.4, 0.5)
	var m_dark := Humanoid.mat(Color(0.12, 0.12, 0.12), 0.5, 0.5)
	var m_glass := Humanoid.mat(Color(0.3, 0.45, 0.55), 0.05, 0.3)
	var m_stripe := Humanoid.mat(Effects.CYAN, 0.3, 0.0, 1.5)
	_visual = Node3D.new()
	_visual.position = Vector3(0, 1.3, 0)
	add_child(_visual)
	Humanoid.part(_visual, "capsule", m, Vector3(0, 0, 0), Vector3(0.62, 3.9, 0.7), Vector3(90, 0, 0))   # 胴体（-Z 前）
	Humanoid.part(_visual, "sphere", m_glass, Vector3(0, 0.42, 0.2), Vector3(0.55, 0.45, 1.3))           # 風防
	Humanoid.part(_visual, "box", m, Vector3(0, -0.15, -0.3), Vector3(10.5, 0.1, 1.7))                    # 主翼
	Humanoid.part(_visual, "box", m_stripe, Vector3(0, -0.09, -0.3), Vector3(10.6, 0.02, 0.18))
	Humanoid.part(_visual, "box", m, Vector3(0, 0.05, 3.5), Vector3(3.6, 0.08, 0.9))                       # 水平尾翼
	Humanoid.part(_visual, "box", m, Vector3(0, 0.6, 3.6), Vector3(0.08, 1.2, 0.9))                        # 垂直尾翼
	Humanoid.part(_visual, "cyl", m_dark, Vector3(0, 0, -3.85), Vector3(0.75, 0.3, 0.75), Vector3(90, 0, 0)) # カウル
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0, -4.05)
	_visual.add_child(_prop)
	Humanoid.part(_prop, "box", m_dark, Vector3.ZERO, Vector3(0.18, 3.0, 0.05))
	Humanoid.part(_prop, "box", m_dark, Vector3.ZERO, Vector3(3.0, 0.18, 0.05))
	for x in [-1.3, 1.3]:  # 脚
		Humanoid.part(_visual, "box", m_dark, Vector3(x, -0.7, -1.0), Vector3(0.08, 1.0, 0.1))
		Humanoid.part(_visual, "cyl", m_dark, Vector3(x, -1.15, -1.0), Vector3(0.5, 0.18, 0.5), Vector3(0, 0, 90))
		var g := Node3D.new()
		g.position = Vector3(x * 1.6, -0.1, -1.4)
		_visual.add_child(g)
		_guns.append(g)
	seat = Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0, -0.35, 0.3)
	_visual.add_child(seat)
	_sound = Sfx.loop_player(self, Sfx.propeller(), -4.0)
	display_name = "飛行機"


func get_speed() -> float: return speed
func get_velocity_vec() -> Vector3: return velocity


func enter(p) -> void:
	driver = p
	_sound.play()
	if CameraRig.I:
		CameraRig.I.yaw = global_rotation.y
		CameraRig.I.pitch = 0.0


func exit() -> void:
	driver = null
	if not airborne:
		throttle = 0.0
		_sound.stop()


func exit_point() -> Vector3:
	if airborne:
		return global_position + Vector3.UP * 3.0   # 空中脱出（パラシュートが開く）
	return global_position + global_basis.x * 4.0 + Vector3.UP * 0.3


func take_hit(amount: float, _team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_crash()


func _crash() -> void:
	if _dead:
		return
	_dead = true
	if driver != null and driver.has_method("exit_vehicle"):
		var d = driver
		d.exit_vehicle()
		d.take_hit(60.0, -1)
	Effects.explosion(get_tree(), global_position + Vector3.UP, 12.0, 150.0, -1)
	remove_from_group("vehicle")
	_sound.stop()
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		queue_free()


func _ground_h(p: Vector3) -> float:
	var w = Game.world
	return w.height_at(p.x, p.z) if w and w.has_method("height_at") else 0.0


func _physics_process(dt: float) -> void:
	var cam := CameraRig.I
	var controlling := driver != null and not Game.input_blocked
	var boost := false
	var roll_in := 0.0
	if controlling:
		if Input.is_action_pressed("move_forward"): throttle = minf(1.0, throttle + dt * 0.6)
		if Input.is_action_pressed("move_back"): throttle = maxf(0.0, throttle - dt * 0.6)
		boost = Input.is_action_pressed("sprint")
		roll_in = Input.get_axis("move_left", "move_right")
	elif driver == null and airborne:
		throttle = maxf(0.0, throttle - dt * 0.1)   # 無人機は滑空して落ちる
	var target_speed := lerpf(0.0, 85.0, throttle) * (1.45 if boost else 1.0)
	speed = move_toward(speed, target_speed, (14.0 if target_speed > speed else 8.0) * dt)

	var fwd := -global_basis.z
	var gh := _ground_h(global_position)
	if not airborne:
		# 地上滑走
		var yaw_in := 0.0
		if controlling and cam:
			yaw_in = clampf(angle_difference(global_rotation.y, cam.yaw), -1.0, 1.0)
		rotation.y += yaw_in * dt * 1.2 * clampf(speed / 10.0, 0.2, 1.0)
		rotation.x = lerpf(rotation.x, 0.0, dt * 4.0)
		rotation.z = lerpf(rotation.z, 0.0, dt * 4.0)
		var want_up := controlling and cam and cam.pitch > 0.05
		if speed > TAKEOFF and want_up:
			airborne = true
		var flat := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
		velocity = flat * speed
		velocity.y = (gh - global_position.y) / maxf(dt, 0.001)
		move_and_slide()
		if speed > 18.0 and get_slide_collision_count() > 0:
			for i in get_slide_collision_count():
				var n := get_slide_collision(i).get_normal()
				if n.y < 0.5:
					_crash()
					return
	else:
		# 飛行：カメラ方向へ機首を向ける
		var desired := fwd
		if controlling and cam:
			desired = cam.rot_basis() * Vector3.FORWARD
		elif driver == null:
			desired = (fwd + Vector3.DOWN * 0.3).normalized()
		var turn_rate := 1.25 * clampf(speed / 45.0, 0.35, 1.0)
		var axis := fwd.cross(desired)
		var ang := fwd.angle_to(desired)
		if axis.length() > 0.0001 and ang > 0.0005:
			var step := minf(ang, turn_rate * dt)
			global_basis = Basis(axis.normalized(), step) * global_basis
		# バンク（見た目）
		var local_turn := global_basis.inverse() * axis
		_bank = lerpf(_bank, clampf(-local_turn.y * 6.0, -1.2, 1.2), dt * 3.0)
		_roll_extra += roll_in * dt * 4.0
		_roll_extra = lerpf(_roll_extra, 0.0 if absf(roll_in) < 0.1 else _roll_extra, dt * 2.0)
		_visual.rotation.z = _bank + _roll_extra
		fwd = -global_basis.z
		# 失速
		var climb := fwd.dot(Vector3.UP)
		speed -= climb * 9.8 * dt * 0.6
		var lift := clampf((speed - 18.0) / (TAKEOFF - 18.0), 0.0, 1.0)
		velocity = fwd * speed + Vector3.DOWN * (1.0 - lift) * 12.0
		var col := move_and_collide(velocity * dt)
		if col:
			var n := col.get_normal()
			var level := absf(fwd.dot(Vector3.UP)) < 0.2 and global_basis.y.dot(Vector3.UP) > 0.85
			if n.y > 0.8 and level and speed < 40.0 and velocity.y > -8.0:
				airborne = false   # 着陸
				_bank = 0.0; _roll_extra = 0.0; _visual.rotation.z = 0.0
			else:
				_crash()
				return
		if global_position.y < gh + 0.3:
			if speed < 40.0 and absf(fwd.y) < 0.25:
				airborne = false
				global_position.y = gh
			else:
				_crash()
				return
		global_position.y = minf(global_position.y, 900.0)
		var w = Game.world
		if w and "half_size" in w:
			var lim: float = w.half_size + 600.0
			if absf(global_position.x) > lim or absf(global_position.z) > lim:
				global_basis = Basis(Vector3.UP, PI) * global_basis
	_prop.rotation.z += dt * (10.0 + throttle * 60.0)
	if _sound.playing:
		_sound.pitch_scale = lerpf(0.6, 1.6, throttle) * (1.15 if boost else 1.0)
	# 機銃
	if controlling and Input.is_action_pressed("fire") and Time.get_ticks_msec() / 1000.0 >= _next_shot:
		_next_shot = Time.get_ticks_msec() / 1000.0 + 1.0 / 14.0
		_fire_guns()


func _fire_guns() -> void:
	var space := get_world_3d().direct_space_state
	var cam := CameraRig.I
	for g in _guns:
		var from: Vector3 = g.global_position
		var dir := -global_basis.z
		if cam:
			var aim := cam.global_position + cam.aim_dir() * 600.0
			dir = dir.lerp((aim - from).normalized(), 0.6).normalized()
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.008).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 700.0)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var end := from + dir * 700.0
		if not hit.is_empty():
			end = hit["position"]
			Player.apply_hit(get_tree(), hit, dir, 16.0, 0)
		Effects.tracer(get_tree(), from, end, Color(1, 0.85, 0.4), 0.08)
	Effects.flash(get_tree(), global_position - global_basis.z * 2.0, Color(1, 0.8, 0.4), 2.0, 6.0, 0.05)
	Sfx.play(get_tree(), Sfx.shot(), -14.0)
	Wanted.report(global_position, 0.01)
