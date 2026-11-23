class_name AirEnemy
extends CharacterBody3D
## 空の敵（戦闘機・修正力の飛行体）。目標地点の上空を旋回し、プレイヤーに気づくと追尾して撃ってくる。

signal killed(enemy)

var label := "敵機"
var is_guardian := false
var mission_target := false
var hp := 90.0
var dead := false
var center := Vector3.ZERO
var speed := 55.0
var _t := 0.0
var _cool := 2.0
var _burst := 0
var _visual: Node3D
var _tag: Label3D
var _smoke := 0.0
var _sound: AudioStreamPlayer3D


static func spawn(parent: Node, pos: Vector3, p_label: String) -> AirEnemy:
	var e := AirEnemy.new()
	e.label = p_label
	e.is_guardian = p_label.contains("修正力") or p_label.contains("番人") or p_label.contains("時空")
	parent.add_child(e)
	e.global_position = pos
	e.center = pos
	e._t = randf() * TAU
	return e


func is_enemy() -> bool:
	return true


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = Game.COLLISION_ENEMY
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(9.0, 1.6, 7.0)
	cs.shape = bx
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	var base := Color(0.08, 0.06, 0.12) if is_guardian else Color(0.42, 0.46, 0.4)
	var m := Humanoid.mat(base, 0.4, 0.6)
	var acc := Humanoid.mat(Effects.GUARD, 0.3, 0.0, 3.0) if is_guardian else Humanoid.mat(Color(0.1, 0.1, 0.1), 0.5)
	Humanoid.part(_visual, "capsule", m, Vector3.ZERO, Vector3(0.6, 3.6, 0.65), Vector3(90, 0, 0))
	Humanoid.part(_visual, "box", m, Vector3(0, -0.1, -0.2), Vector3(9.5, 0.1, 1.5))
	Humanoid.part(_visual, "box", acc, Vector3(0, -0.04, -0.2), Vector3(9.6, 0.02, 0.15))
	Humanoid.part(_visual, "box", m, Vector3(0, 0.05, 3.2), Vector3(3.2, 0.08, 0.8))
	Humanoid.part(_visual, "box", m, Vector3(0, 0.55, 3.3), Vector3(0.08, 1.1, 0.8))
	Humanoid.part(_visual, "sphere", Humanoid.mat(Color(0.2, 0.25, 0.3), 0.05, 0.3), Vector3(0, 0.4, 0.2), Vector3(0.5, 0.4, 1.2))
	_tag = Label3D.new()
	_tag.text = label
	_tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	_tag.font_size = 64
	_tag.pixel_size = 0.03
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = false
	_tag.outline_size = 12
	_tag.modulate = Effects.GUARD if is_guardian else Color(1, 0.45, 0.4)
	_tag.position = Vector3(0, 4, 0)
	add_child(_tag)
	_sound = Sfx.loop_player(self, Sfx.propeller(), -2.0)
	_sound.play()


func take_hit(amount: float, from_team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if dead or from_team == 1:
		return
	hp -= amount
	if hp <= 0.0:
		dead = true
		_tag.visible = false
		killed.emit(self)
		Wanted.report(global_position, 0.4)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("%sを撃墜！" % label)


func _physics_process(dt: float) -> void:
	var fwd := -global_basis.z
	if dead:
		# 煙を吐いて墜落
		var down := (fwd + Vector3.DOWN * 0.9).normalized()
		global_basis = global_basis.slerp(Basis.looking_at(down, Vector3.UP), dt * 0.8)
		_visual.rotation.z += dt * 3.0
		global_position += -global_basis.z * speed * dt
		_smoke -= dt
		if _smoke <= 0.0:
			_smoke = 0.08
			Effects.burst(get_tree(), global_position, Vector3.UP, Color(0.1, 0.1, 0.1, 0.8), Color(0.3, 0.3, 0.3), 3, 2.0, 2.5, 2.0, -0.05, false)
			Effects.burst(get_tree(), global_position, Vector3.UP, Color(1, 0.5, 0.1), Color(1, 0.2, 0), 2, 2.0, 1.2, 0.3, 0.0, true)
		var w = Game.world
		var gh: float = w.height_at(global_position.x, global_position.z) if w else 0.0
		if global_position.y <= gh + 1.0:
			Effects.explosion(get_tree(), global_position, 12.0, 80.0, 1)
			queue_free()
		return
	_t += dt
	var p = Game.player
	var desired: Vector3
	var target := Vector3.ZERO
	var chasing := false
	if p and is_instance_valid(p):
		target = p.vehicle.global_position if p.in_vehicle() else p.global_position
		chasing = global_position.distance_to(target) < 650.0
	if chasing:
		var lead: Vector3 = target
		if p.in_vehicle() and p.vehicle.has_method("get_velocity_vec"):
			lead += p.vehicle.get_velocity_vec() * 0.8
		if global_position.distance_to(lead) < 40.0:
			lead += global_basis.x * 120.0  # 近すぎたら一旦離脱
		desired = (lead + Vector3.UP * 8.0 - global_position).normalized()
	else:
		var orbit := center + Vector3(cos(_t * 0.25) * 220.0, 0, sin(_t * 0.25) * 220.0)
		desired = (orbit - global_position).normalized()
	var w2 = Game.world
	if w2:
		var gh2: float = w2.height_at(global_position.x, global_position.z)
		if global_position.y < gh2 + 60.0:
			desired = (desired + Vector3.UP * 1.5).normalized()
	var axis := fwd.cross(desired)
	var ang := fwd.angle_to(desired)
	if axis.length() > 0.0001:
		global_basis = Basis(axis.normalized(), minf(ang, 0.9 * dt)) * global_basis
	var local_turn := global_basis.inverse() * axis
	_visual.rotation.z = lerpf(_visual.rotation.z, clampf(-local_turn.y * 5.0, -1.1, 1.1), dt * 3.0)
	global_position += -global_basis.z * speed * dt
	# 射撃
	_cool -= dt
	if chasing and _cool <= 0.0:
		var to := (target - global_position)
		if to.length() < 320.0 and (-global_basis.z).angle_to(to.normalized()) < deg_to_rad(10.0):
			var dir := (to.normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03).normalized()
			Projectile.fire(get_tree(), global_position - global_basis.z * 4.0, dir, "energy" if is_guardian else "air", 1)
			Sfx.play_at(get_tree(), Sfx.shot(), global_position, -6.0)
			_burst += 1
			_cool = 0.1 if _burst % 6 != 0 else randf_range(1.5, 3.0)
