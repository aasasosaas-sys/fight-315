class_name Horse
extends CharacterBody3D
## 馬。W 前進 / Shift 襲歩 / A・D 旋回 / Space 跳躍。騎乗したまま射撃可。

var kind := "horse"
var display_name := "馬"
var driver = null
var seat: Node3D
var speed := 0.0
var _turn := 0.0
var _gait := 0.0
var _legs: Array[Node3D] = []
var _neck: Node3D
var _tail: Node3D
var _sound: AudioStreamPlayer3D
var _rear := 0.0


static func create(seed: int) -> Horse:
	var h := Horse.new()
	h.name = "Horse"
	h._build(seed)
	return h


func _build(seed: int) -> void:
	add_to_group("vehicle")
	collision_layer = Game.COLLISION_VEHICLE
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP | Game.COLLISION_VEHICLE
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(45)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.8, 1.5, 2.3)
	cs.shape = bx
	cs.position = Vector3(0, 1.1, 0)
	add_child(cs)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var coat: Color = [Color(0.36, 0.22, 0.12), Color(0.18, 0.12, 0.08), Color(0.55, 0.42, 0.3), Color(0.82, 0.8, 0.76), Color(0.1, 0.09, 0.08)][rng.randi() % 5]
	var m := Humanoid.mat(coat, 0.55)
	var dark := Humanoid.mat(coat.darkened(0.6), 0.6)
	var tack := Humanoid.mat(Color(0.45, 0.12, 0.1), 0.5)
	seat = Node3D.new()
	seat.name = "Seat"
	add_child(seat)
	_sound = Sfx.loop_player(self, Sfx.hooves(), -8.0)
	if ResourceLoader.exists(MODEL):
		_build_model(rng, coat)
		return
	var body := Node3D.new()
	add_child(body)
	# 前方は -Z
	Humanoid.part(body, "capsule", m, Vector3(0, 1.35, 0), Vector3(0.62, 0.95, 0.68), Vector3(90, 0, 0))
	_neck = Node3D.new()
	_neck.position = Vector3(0, 1.55, -0.75)
	body.add_child(_neck)
	Humanoid.part(_neck, "capsule", m, Vector3(0, 0.35, -0.12), Vector3(0.28, 0.42, 0.34), Vector3(-35, 0, 0))
	Humanoid.part(_neck, "capsule", m, Vector3(0, 0.62, -0.42), Vector3(0.22, 0.32, 0.26), Vector3(-100, 0, 0))
	Humanoid.part(_neck, "box", dark, Vector3(0, 0.62, -0.1), Vector3(0.06, 0.55, 0.12), Vector3(-35, 0, 0)) # たてがみ
	Humanoid.part(_neck, "box", tack, Vector3(0, 0.6, -0.5), Vector3(0.24, 0.04, 0.3), Vector3(-100, 0, 0))
	for e in [-1, 1]:
		Humanoid.part(_neck, "cone", m, Vector3(0.07 * e, 0.88, -0.28), Vector3(0.06, 0.12, 0.06))
	for p in [Vector3(-0.22, 1.05, -0.55), Vector3(0.22, 1.05, -0.55), Vector3(-0.22, 1.05, 0.6), Vector3(0.22, 1.05, 0.6)]:
		var leg := Node3D.new()
		leg.position = p
		body.add_child(leg)
		Humanoid.part(leg, "capsule", m, Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.16))
		Humanoid.part(leg, "capsule", dark, Vector3(0, -0.75, 0), Vector3(0.09, 0.28, 0.1))
		Humanoid.part(leg, "cyl", dark, Vector3(0, -1.02, 0), Vector3(0.12, 0.06, 0.13))
		_legs.append(leg)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 1.55, 0.95)
	body.add_child(_tail)
	Humanoid.part(_tail, "capsule", dark, Vector3(0, -0.35, 0.1), Vector3(0.08, 0.35, 0.08), Vector3(20, 0, 0))
	Humanoid.part(body, "box", tack, Vector3(0, 1.7, 0.05), Vector3(0.7, 0.08, 0.75))  # 鞍
	seat.position = Vector3(0, 0.62, 0.1)


const MODEL := "res://assets/vehicles/horse.glb"
var _anim: AnimationPlayer
var _anim_name := ""


## Blender で生成したリアル寄りの馬（tools/make_horse.py）
func _build_model(rng: RandomNumberGenerator, coat: Color) -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	inst.rotation.y = PI    # glTF の前方(+Z) → Godot の前方(-Z)
	add_child(inst)
	var coat_m := StandardMaterial3D.new()
	coat_m.albedo_color = coat
	coat_m.roughness = 0.42
	coat_m.rim_enabled = true
	coat_m.rim = 0.25
	coat_m.normal_enabled = true
	var nt := NoiseTexture2D.new()
	nt.width = 512; nt.height = 512
	nt.as_normal_map = true
	nt.bump_strength = 2.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	nt.noise = fn
	coat_m.normal_texture = nt
	coat_m.normal_scale = 0.35
	coat_m.uv1_triplanar = true
	coat_m.uv1_scale = Vector3(3, 3, 3)
	var hair_m := StandardMaterial3D.new()
	hair_m.albedo_color = coat.darkened(0.75) if coat.v > 0.4 else Color(0.05, 0.04, 0.035)
	hair_m.roughness = 0.75
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = hair_m if String(mi.name).contains("Hair") else coat_m
	# 鞍・鐙・手綱
	var tack := Humanoid.mat(Color(0.32, 0.12, 0.08), 0.55)
	var cloth := Humanoid.mat([Color(0.55, 0.1, 0.1), Color(0.12, 0.2, 0.45), Color(0.15, 0.15, 0.15)][rng.randi() % 3], 0.8)
	var saddle := Node3D.new()
	add_child(saddle)
	Humanoid.part(saddle, "box", cloth, Vector3(0, 1.66, -0.05), Vector3(0.82, 0.03, 0.85))
	Humanoid.part(saddle, "box", tack, Vector3(0, 1.72, -0.05), Vector3(0.42, 0.1, 0.62))
	Humanoid.part(saddle, "box", tack, Vector3(0, 1.8, -0.32), Vector3(0.3, 0.12, 0.06))
	Humanoid.part(saddle, "box", tack, Vector3(0, 1.79, 0.22), Vector3(0.34, 0.1, 0.06))
	for x in [-0.32, 0.32]:
		Humanoid.part(saddle, "box", tack, Vector3(x, 1.35, -0.05), Vector3(0.02, 0.7, 0.04))
		Humanoid.part(saddle, "box", Humanoid.mat(Color(0.3, 0.3, 0.32), 0.3, 0.9), Vector3(x, 0.98, -0.05), Vector3(0.1, 0.03, 0.12))
	seat.position = Vector3(0, 0.82, -0.02)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		_anim = aps[0]
		for n in _anim.get_animation_list():
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")


func _play(n: String) -> void:
	if _anim and _anim_name != n and _anim.has_animation(n):
		_anim_name = n
		_anim.play(n, 0.25)


func get_speed() -> float: return absf(speed)
func get_velocity_vec() -> Vector3: return velocity


func enter(p) -> void:
	driver = p


func exit() -> void:
	driver = null
	if _sound.playing:
		_sound.stop()


func exit_point() -> Vector3:
	return global_position + global_basis.x * 1.3 + Vector3.UP * 0.2


func take_hit(_amount: float, _team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	_rear = 1.0  # 驚いて竿立ち（馬は傷つかない）


func _physics_process(dt: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var gallop := false
	var jump := false
	if driver != null and not Game.input_blocked:
		var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		throttle = mv.y
		steer = -mv.x
		gallop = Input.is_action_pressed("sprint")
		jump = Input.is_action_just_pressed("jump")
		# 馬上で照準中はカメラ方向へ向く
		if Input.is_action_pressed("aim") and CameraRig.I and absf(throttle) < 0.1:
			rotation.y = lerp_angle(rotation.y, CameraRig.I.yaw, dt * 4.0)
	var top := 18.0 if gallop else 9.0
	var target := throttle * (top if throttle > 0 else 3.5)
	speed = move_toward(speed, target, (7.0 if absf(target) > absf(speed) else 10.0) * dt)
	_turn = lerpf(_turn, steer * lerpf(2.4, 1.3, clampf(absf(speed) / 18.0, 0, 1)), dt * 6.0)
	rotation.y += _turn * dt
	var fwd := -global_basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		if jump and absf(speed) > 3.0:
			velocity.y = 7.0
		else:
			velocity.y = -1.0
	else:
		velocity.y -= 22.0 * dt
	move_and_slide()
	if get_slide_collision_count() > 0 and absf(speed) > 12.0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var o = c.get_collider()
			if o and o.has_method("take_hit") and o.has_method("is_enemy"):
				o.take_hit(30.0, 0, c.get_position(), fwd)
			elif o and o.has_method("panic"):
				o.panic(global_position)
		speed *= 0.6
	# アニメーション
	if _anim:
		var sp := absf(speed)
		if sp < 0.5:
			_play("Idle"); _anim.speed_scale = 1.0
		elif sp < 10.0:
			_play("Walk"); _anim.speed_scale = clampf(sp / 4.0, 0.6, 2.2)
		else:
			_play("Gallop"); _anim.speed_scale = clampf(sp / 16.0, 0.8, 1.4)
	_gait += dt * lerpf(3.0, 13.0, clampf(absf(speed) / 18.0, 0, 1)) * (1.0 if absf(speed) > 0.3 else 0.0)
	var amp := clampf(absf(speed) / 6.0, 0.0, 1.0) * 35.0
	for i in _legs.size() if not _anim else 0:
		var off: float = [0.0, PI, PI * 0.5, PI * 1.5][i] if absf(speed) > 10.0 else [0.0, PI, PI, 0.0][i]
		_legs[i].rotation_degrees.x = sin(_gait + off) * amp
	_rear = move_toward(_rear, 0.0, dt * 1.2)
	if _neck: _neck.rotation_degrees.x = sin(_gait * 2.0) * 4.0 * clampf(absf(speed) / 10.0, 0, 1) - _rear * 40.0
	if _tail: _tail.rotation_degrees.x = 20.0 + sin(Time.get_ticks_msec() * 0.003) * 8.0 + absf(speed) * 2.0
	if driver != null and absf(speed) > 1.0:
		if not _sound.playing:
			_sound.play()
		_sound.pitch_scale = lerpf(0.7, 1.5, clampf(absf(speed) / 18.0, 0, 1))
	elif _sound.playing:
		_sound.stop()
