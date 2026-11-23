class_name BreakableProp
extends RigidBody3D
## 壊れる小道具（木箱・樽・桶・壺）。撃つ・爆風・体当たりで割れて木っ端になる。

var kind := "crate"
var hp := 40.0
var _broken := false


func _ready() -> void:
	add_to_group("physics_prop")
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body)


func take_hit(amount: float, _team: int, point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if _broken:
		return
	hp -= amount
	if hp <= 0.0:
		smash(point if point != Vector3.ZERO else global_position)


func _on_body(b: Node) -> void:
	if _broken:
		return
	var rel := linear_velocity.length()
	if b is RigidBody3D or b is CharacterBody3D:
		var bv: Vector3 = b.get("linear_velocity") if b is RigidBody3D else b.get("velocity")
		rel = (bv - linear_velocity).length()
	if rel > 9.0:
		smash(global_position)


func smash(p: Vector3) -> void:
	if _broken:
		return
	_broken = true
	var wood := Color(0.62, 0.45, 0.3) if kind != "pot" else Color(0.7, 0.45, 0.32)
	Effects.burst(get_tree(), p, Vector3.UP, wood, wood.darkened(0.4), 22, 6.0, 0.16, 1.0, 1.6, false, 110)
	Effects.burst(get_tree(), p, Vector3.UP, Color(0.7, 0.64, 0.55, 0.7), Color(0.6, 0.58, 0.55, 0.0), 6, 1.5, 1.0, 1.2, -0.05, false, 80)
	Sfx.play_at(get_tree(), Sfx.wood_break(), p, -6.0)
	Wanted.report(p, 0.02)
	var d = Destruction.current
	if d != null and is_instance_valid(d):
		# 板切れを数枚（破片プールを使う）
		for k in 3:
			var kit := MeshKit.new()
			var s := Vector3(randf_range(0.08, 0.14), randf_range(0.05, 0.08), randf_range(0.4, 0.8))
			kit.box("wood", Transform3D.IDENTITY, s, wood, false)
			d._spawn_one(kit.to_mesh(), global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3)), s,
				Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
	queue_free()
