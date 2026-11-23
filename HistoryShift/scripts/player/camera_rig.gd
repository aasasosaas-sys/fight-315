class_name CameraRig
extends Camera3D
## 三人称カメラ。徒歩=肩越し、馬・車=後方追従、飛行機=マウスエイム式チェイス、ORBIT=タイトル背景。

enum Mode { ON_FOOT, GROUND, PLANE, ORBIT }

static var I: CameraRig

var target: Node3D
var mode := Mode.ON_FOOT
var yaw := 0.0
var pitch := -0.15
var aiming := false
var sensitivity := 0.0025
var _dist := 4.2
var _smooth := Vector3.ZERO
var _orbit_t := 0.0
var _exclude: Array[RID] = []


func _ready() -> void:
	I = self
	far = 3000.0
	near = 0.08
	fov = 65.0
	current = true
	var s = Game.get_meta("mouse_sensitivity", 1.0)
	sensitivity = 0.0025 * float(s)


func _exit_tree() -> void:
	if I == self:
		I = null


func set_target(t: Node3D, m: int) -> void:
	target = t
	mode = m
	_exclude.clear()
	var n: Node = t
	while n != null:
		if n is CollisionObject3D:
			_exclude.append((n as CollisionObject3D).get_rid())
		n = n.get_parent() if n.get_parent() is Node3D else null
	if t is CollisionObject3D:
		for c in t.get_children():
			if c is CollisionObject3D:
				_exclude.append(c.get_rid())
	var p := Game.player
	if p is CollisionObject3D:
		_exclude.append((p as CollisionObject3D).get_rid())


func snap() -> void:
	if target:
		_smooth = target.global_position
		yaw = target.global_rotation.y


func rot_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0))


func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func flat_right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func aim_dir() -> Vector3:
	return -global_basis.z


## 照準方向のレイキャスト（自分と乗り物を除外）
func aim_hit(max_dist := 600.0, extra_exclude: Array[RID] = []) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + aim_dir() * max_dist)
	var ex := _exclude.duplicate()
	ex.append_array(extra_exclude)
	q.exclude = ex
	q.collide_with_areas = false
	return space.intersect_ray(q)


func _unhandled_input(event: InputEvent) -> void:
	if Game.input_blocked or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var k := sensitivity * (0.55 if aiming else 1.0)
		yaw -= m.relative.x * k
		pitch = clampf(pitch - m.relative.y * k, deg_to_rad(-75), deg_to_rad(60))


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	# ゲームパッド右スティック
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if pad.length() > 0.15 and not Game.input_blocked:
		yaw -= pad.x * dt * 2.6
		pitch = clampf(pitch - pad.y * dt * 2.0, deg_to_rad(-75), deg_to_rad(60))

	if mode == Mode.ORBIT:
		_orbit_t += dt * 0.04
		var c := target.global_position + Vector3(cos(_orbit_t) * 190.0, 85.0, sin(_orbit_t) * 190.0)
		global_position = global_position.lerp(c, clampf(dt * 0.6, 0, 1)) if global_position.length() > 1 else c
		look_at(target.global_position + Vector3.UP * 15.0, Vector3.UP)
		fov = 55.0
		return

	var rb := rot_basis()
	var foot := mode == Mode.ON_FOOT
	var plane := mode == Mode.PLANE
	var want_dist := 16.0 if plane else ((2.9 if aiming else 4.8) if foot else 8.5)
	var height := 2.5 if plane else (1.75 if foot else 2.6)
	var shoulder := (1.0 if aiming else 0.75) if foot else 0.0
	_dist = lerpf(_dist, want_dist, 1.0 - exp(-dt * 10.0))
	_smooth = _smooth.lerp(target.global_position, 1.0 - exp(-dt * (30.0 if foot else (40.0 if plane else 14.0))))
	var pivot := _smooth + Vector3.UP * height + rb.x * shoulder
	var desired := pivot + rb.z * _dist

	# 壁抜け防止
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, desired, Game.COLLISION_WORLD | Game.COLLISION_PROP)
	q.exclude = _exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = pivot + (hit["position"] - pivot) * 0.9
	global_position = desired
	global_basis = rb
	var want_fov := 48.0 if aiming else (62.0 if foot else 70.0)
	if plane and target.has_method("get_speed"):
		want_fov = 66.0 + clampf(target.get_speed() / 90.0, 0, 1) * 12.0
	fov = lerpf(fov, want_fov, 1.0 - exp(-dt * 8.0))

	if Effects.shake > 0.0:
		var s := Effects.shake
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s * 0.25
		rotate_object_local(Vector3.RIGHT, randf_range(-1, 1) * s * 0.02)
		Effects.shake = maxf(0.0, s - dt * 1.8)
