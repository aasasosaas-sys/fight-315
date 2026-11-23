class_name Car
extends RigidBody3D
## レイキャスト式サスペンションの車（ジャンプ・横転・爆発する）。明治=クラシックカー、昭和=セダン/トラック。

var kind := "car"
var display_name := "自動車"
var driver = null
var seat: Node3D
var hp := 220.0
var style := "sedan"
var _wheels: Array[Node3D] = []     # 見た目
var _wheel_pts: Array[Vector3] = [] # ローカル取付位置
var _steer := 0.0
var _spin := 0.0
var _engine: AudioStreamPlayer3D
var _smoke_t := 0.0
var _flip_t := 0.0
var _dead := false
const REST := 0.45
const RADIUS := 0.38
const SPRING := 38000.0
const DAMP := 3600.0


static func create(seed: int, era_id: String) -> Car:
	var c := Car.new()
	c.name = "Car"
	c._build(seed, era_id)
	return c


func _build(seed: int, era_id: String) -> void:
	add_to_group("vehicle")
	collision_layer = Game.COLLISION_VEHICLE
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP | Game.COLLISION_VEHICLE | Game.COLLISION_ENEMY
	mass = 1200.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0)
	angular_damp = 1.2
	linear_damp = 0.05
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	style = "classic" if era_id == "meiji_taisho" else (["sedan", "sedan", "truck", "sports"][rng.randi() % 4])
	var paint: Color = [Color(0.06, 0.06, 0.07), Color(0.55, 0.08, 0.08), Color(0.1, 0.22, 0.45), Color(0.85, 0.83, 0.78), Color(0.15, 0.35, 0.25), Color(0.75, 0.6, 0.2)][rng.randi() % 6]
	var m_paint := Humanoid.mat(paint, 0.25, 0.4)
	var m_chrome := Humanoid.mat(Color(0.85, 0.85, 0.88), 0.15, 1.0)
	var m_glass := Humanoid.mat(Color(0.15, 0.2, 0.25), 0.05, 0.2)
	var m_tire := Humanoid.mat(Color(0.05, 0.05, 0.05), 0.9)
	var m_light := Humanoid.mat(Color(1, 0.95, 0.8), 0.2, 0.0, 3.0)
	var body := Node3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var length := 4.2
	match style:
		"classic":
			length = 3.6
			Humanoid.part(body, "box", m_paint, Vector3(0, 0.75, -0.9), Vector3(1.1, 0.6, 1.4))
			Humanoid.part(body, "box", m_paint, Vector3(0, 1.05, 0.5), Vector3(1.4, 1.2, 1.6))
			Humanoid.part(body, "box", Humanoid.mat(Color(0.08, 0.08, 0.08), 0.6), Vector3(0, 1.7, 0.5), Vector3(1.5, 0.08, 1.7))
			Humanoid.part(body, "box", m_glass, Vector3(0, 1.3, -0.31), Vector3(1.3, 0.55, 0.04))
			Humanoid.part(body, "box", m_chrome, Vector3(0, 0.8, -1.62), Vector3(0.9, 0.5, 0.06))
			for x in [-0.75, 0.75]:
				Humanoid.part(body, "box", Humanoid.mat(Color(0.08, 0.08, 0.08), 0.5), Vector3(x, 0.55, 0), Vector3(0.3, 0.05, 3.2))
			bx.size = Vector3(1.5, 1.4, 3.6)
			cs.position = Vector3(0, 1.0, 0)
		"truck":
			length = 5.0
			Humanoid.part(body, "box", m_paint, Vector3(0, 1.05, -1.5), Vector3(1.9, 1.3, 1.6))
			Humanoid.part(body, "box", m_glass, Vector3(0, 1.35, -2.31), Vector3(1.7, 0.55, 0.04))
			Humanoid.part(body, "box", Humanoid.mat(Color(0.35, 0.3, 0.22), 0.8), Vector3(0, 0.8, 0.9), Vector3(2.0, 0.15, 3.0))
			for x in [-0.98, 0.98]:
				Humanoid.part(body, "box", Humanoid.mat(Color(0.35, 0.3, 0.22), 0.8), Vector3(x, 1.15, 0.9), Vector3(0.05, 0.6, 3.0))
			Humanoid.part(body, "box", Humanoid.mat(Color(0.35, 0.3, 0.22), 0.8), Vector3(0, 1.15, 2.38), Vector3(2.0, 0.6, 0.05))
			bx.size = Vector3(2.0, 1.4, 5.0)
			cs.position = Vector3(0, 1.0, 0)
		_:
			var low := style == "sports"
			Humanoid.part(body, "box", m_paint, Vector3(0, 0.7, 0), Vector3(1.8, 0.55, 4.3))
			Humanoid.part(body, "box", m_paint, Vector3(0, 1.15 if not low else 1.0, 0.2), Vector3(1.6, 0.5 if not low else 0.38, 2.1))
			Humanoid.part(body, "box", m_glass, Vector3(0, 1.17 if not low else 1.02, -0.86), Vector3(1.5, 0.42 if not low else 0.32, 0.04), Vector3(-25, 0, 0))
			Humanoid.part(body, "box", m_glass, Vector3(0, 1.17 if not low else 1.02, 1.26), Vector3(1.5, 0.4 if not low else 0.3, 0.04), Vector3(25, 0, 0))
			Humanoid.part(body, "box", m_chrome, Vector3(0, 0.55, -2.16), Vector3(1.8, 0.14, 0.06))
			Humanoid.part(body, "box", m_chrome, Vector3(0, 0.55, 2.16), Vector3(1.8, 0.14, 0.06))
			bx.size = Vector3(1.8, 1.1, 4.3)
			cs.position = Vector3(0, 0.9, 0)
	cs.shape = bx
	add_child(cs)
	for x in [-0.6, 0.6]:
		Humanoid.part(body, "sphere", m_light, Vector3(x, 0.85, -length * 0.5 - 0.02), Vector3(0.22, 0.22, 0.1))
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, 0.85, -length * 0.5)
		spot.spot_range = 40.0
		spot.spot_angle = 30.0
		spot.light_energy = 2.0
		spot.light_color = Color(1, 0.92, 0.75)
		body.add_child(spot)
	var hw := 0.85 if style != "truck" else 0.95
	var hl := length * 0.5 - 0.75
	_wheel_pts = [Vector3(-hw, 0.7, -hl), Vector3(hw, 0.7, -hl), Vector3(-hw, 0.7, hl), Vector3(hw, 0.7, hl)]
	for p in _wheel_pts:
		var w := Node3D.new()
		w.position = p - Vector3(0, REST, 0)
		add_child(w)
		Humanoid.part(w, "cyl", m_tire, Vector3.ZERO, Vector3(RADIUS * 2, 0.26, RADIUS * 2), Vector3(0, 0, 90))
		Humanoid.part(w, "cyl", m_chrome, Vector3.ZERO, Vector3(RADIUS * 1.1, 0.28, RADIUS * 1.1), Vector3(0, 0, 90))
		_wheels.append(w)
	seat = Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(-0.4, 0.35 if style != "classic" else 0.6, 0.1 if style != "truck" else -1.5)
	add_child(seat)
	_engine = Sfx.loop_player(self, Sfx.engine(), -6.0)
	display_name = {"classic": "クラシックカー", "truck": "トラック", "sports": "スポーツカー"}.get(style, "自動車")


func get_speed() -> float: return linear_velocity.length()
func get_velocity_vec() -> Vector3: return linear_velocity


func enter(p) -> void:
	driver = p
	_engine.play()


func exit() -> void:
	driver = null
	_engine.stop()


func exit_point() -> Vector3:
	var p := global_position - global_basis.x * 1.8 + Vector3.UP * 0.5
	return p


func take_hit(amount: float, _team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_explode()


func _explode() -> void:
	_dead = true
	if driver != null and driver.has_method("exit_vehicle"):
		driver.exit_vehicle()
		driver.take_hit(45.0, -1)
	Effects.explosion(get_tree(), global_position + Vector3.UP, 9.0, 120.0, -1)
	apply_central_impulse(Vector3.UP * mass * 7.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 3.0)
	for c in get_children():
		if c is Node3D and c != seat:
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = Humanoid.mat(Color(0.06, 0.05, 0.05), 0.9)
	remove_from_group("vehicle")
	_engine.stop()
	await get_tree().create_timer(20.0).timeout
	if is_inside_tree():
		queue_free()


func _on_body_entered(b: Node) -> void:
	var v := linear_velocity.length()
	if v < 6.0:
		return
	if b.has_method("is_enemy") and b.has_method("take_hit"):
		b.take_hit(v * 5.0, 0, b.global_position, linear_velocity.normalized())
	elif b.has_method("panic"):
		b.panic(global_position)
	if v > 14.0:
		take_hit(v * 0.8, -1)
		Effects.spark(get_tree(), global_position + linear_velocity.normalized() * 2.0, -linear_velocity.normalized())
		Effects.shake = maxf(Effects.shake, 0.3) if driver != null else Effects.shake


func _physics_process(dt: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var brake := false
	var boost := false
	if driver != null and not Game.input_blocked and not _dead:
		var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		throttle = mv.y
		steer_in = -mv.x
		brake = Input.is_action_pressed("jump")
		boost = Input.is_action_pressed("sprint")
	var fwd := -global_basis.z
	var fspeed := linear_velocity.dot(fwd)
	_steer = lerpf(_steer, steer_in * lerpf(0.6, 0.18, clampf(absf(fspeed) / 35.0, 0, 1)), dt * 6.0)
	var space := get_world_3d().direct_space_state
	var grounded := 0
	for i in 4:
		var mount := to_global(_wheel_pts[i])
		var down := -global_basis.y
		var q := PhysicsRayQueryParameters3D.create(mount, mount + down * (REST + RADIUS), Game.COLLISION_WORLD | Game.COLLISION_PROP)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var wheel := _wheels[i]
		if hit.is_empty():
			wheel.position = _wheel_pts[i] - Vector3(0, REST, 0)
			continue
		grounded += 1
		var dist := mount.distance_to(hit["position"]) - RADIUS
		var compression := clampf(REST - dist, 0.0, REST)
		var up := global_basis.y
		var pvel := linear_velocity + angular_velocity.cross(mount - global_position)
		var spring := compression * SPRING - pvel.dot(up) * DAMP
		apply_force(up * maxf(spring, 0.0), mount - global_position)
		wheel.position = _wheel_pts[i] - Vector3(0, REST - compression, 0)
		# タイヤ方向
		var wb := global_basis
		if i < 2:
			wb = wb.rotated(global_basis.y, _steer)
			wheel.rotation.y = _steer
		var wf := -wb.z
		var wr := wb.x
		var lat := pvel.dot(wr)
		var grip := 0.9 if not brake else 0.45
		apply_force(-wr * lat * mass * 0.25 * grip / maxf(dt * 4.0, 0.016), mount - global_position)
		if i >= 2:
			var power := 9000.0 * (1.8 if boost else 1.0)
			var top := 34.0 if style != "classic" else 20.0
			if boost: top *= 1.35
			if throttle > 0.0 and fspeed < top:
				apply_force(wf * throttle * power, mount - global_position)
			elif throttle < 0.0:
				apply_force(wf * throttle * (power * 0.9 if fspeed < 1.0 else power * 1.4), mount - global_position)
		if brake:
			apply_force(-wf * signf(pvel.dot(wf)) * minf(absf(pvel.dot(wf)) * mass * 0.6, 9000.0), mount - global_position)
		if throttle == 0.0 and not brake:
			apply_force(-wf * pvel.dot(wf) * 60.0, mount - global_position)
	_spin += fspeed * dt / RADIUS
	for w in _wheels:
		for c in w.get_children():
			(c as Node3D).rotation = Vector3(_spin, 0, deg_to_rad(90))
	# 空中姿勢制御 & 横転復帰
	if grounded == 0 and driver != null:
		apply_torque(global_basis.x * -throttle * mass * 1.2 + global_basis.y * steer_in * mass * 0.8)
	if global_basis.y.dot(Vector3.UP) < 0.3 and linear_velocity.length() < 2.0:
		_flip_t += dt
		if _flip_t > 2.0 and not _dead:
			_flip_t = 0.0
			global_position += Vector3.UP * 1.5
			global_basis = Basis(Vector3.UP, global_rotation.y)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0
	if driver != null:
		_engine.pitch_scale = lerpf(0.6, 2.0, clampf(absf(fspeed) / 35.0, 0, 1)) + throttle * 0.1
	if hp < 70.0 and not _dead:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = 0.15
			Effects.burst(get_tree(), global_position + Vector3.UP * 1.2 - global_basis.z * 1.6, Vector3.UP, Color(0.15, 0.15, 0.15, 0.7), Color(0.3, 0.3, 0.3), 2, 2.0, 1.5, 1.5, -0.1, false)
