class_name FieldCannon
extends StaticBody3D
## 据え置きの大筒（明治以降は野砲）。DestructionTools が置き、照準点へ弾道計算して撃つ。

const SPEED := 85.0
var modern := false
var _barrel: Node3D
var _cool := 0.0


static func place(tree: SceneTree, pos: Vector3, yaw: float, p_modern: bool) -> FieldCannon:
	var c := FieldCannon.new()
	c.modern = p_modern
	var sess = tree.get_first_node_in_group("session")
	var root: Node = sess if sess else (tree.current_scene if tree.current_scene else tree.root)
	root.add_child(c)
	c.global_position = pos
	c.rotation.y = yaw
	return c


func _ready() -> void:
	add_to_group("field_cannon")
	collision_layer = Game.COLLISION_PROP
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 1.0, 2.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)
	var kit := MeshKit.new()
	var wood := Color(0.62, 0.45, 0.3)
	var metal := Color(0.35, 0.3, 0.2) if not modern else Color(0.25, 0.3, 0.26)
	# 台車と車輪
	kit.box("wood", Transform3D(Basis(), Vector3(0, 0.45, 0.2)), Vector3(0.9, 0.3, 1.8), wood)
	for sgn in [-1.0, 1.0]:
		kit.cylinder("darkwood", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sgn * 0.55, 0.5, 0.1)), 0.5, 0.5, 0.12, 12, Color(0.4, 0.3, 0.22))
	var base := MeshInstance3D.new()
	base.mesh = kit.to_mesh()
	add_child(base)
	_barrel = Node3D.new()
	_barrel.position = Vector3(0, 0.85, 0)
	add_child(_barrel)
	var bk := MeshKit.new()
	bk.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.5)), 0.24 if not modern else 0.16, 0.17 if not modern else 0.13, 2.1, 12, metal)
	bk.sphere("metal", Transform3D(Basis(), Vector3(0, 0, 0.5)), 0.26 if not modern else 0.2, 10, 6, metal)
	if not modern:
		for z in [0.0, -0.7, -1.3]:
			bk.cylinder("gold", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, z)), 0.26, 0.26, 0.08, 12, Color(0.85, 0.65, 0.3))
	var bm := MeshInstance3D.new()
	bm.mesh = bk.to_mesh()
	_barrel.add_child(bm)


func _physics_process(dt: float) -> void:
	_cool -= dt


func ready_to_fire() -> bool:
	return _cool <= 0.0


## target（ワールド座標）へ撃つ
func fire_at(target: Vector3, team := 0) -> void:
	if _cool > 0.0:
		return
	_cool = 1.6
	var muzzle := _barrel.global_position + (target - _barrel.global_position).normalized() * 1.6
	var v := Shell.ballistic(muzzle, target, SPEED)
	# 砲身を向ける
	var flat := Vector3(v.x, 0, v.z)
	rotation.y = atan2(-flat.x, -flat.z)
	_barrel.rotation.x = atan2(v.y, flat.length())
	muzzle = _barrel.global_position - _barrel.global_basis.z * 1.6
	Shell.fire(get_tree(), "shell" if modern else "cannonball", muzzle, v, team)
	Effects.burst(get_tree(), muzzle, v.normalized(), Color(1, 0.8, 0.4), Color(1, 0.3, 0.1), 20, 8.0, 0.4, 0.25, 0.0, true, 25)
	Effects.burst(get_tree(), muzzle, v.normalized(), Color(0.85, 0.83, 0.8, 0.8), Color(0.7, 0.7, 0.7, 0.0), 18, 4.0, 2.2, 2.4, -0.05, false, 35)
	Effects.flash(get_tree(), muzzle, Color(1, 0.7, 0.35), 8.0, 14.0, 0.15)
	Sfx.play_at(get_tree(), Sfx.cannon(), muzzle, 4.0)
	Effects.shake = maxf(Effects.shake, 0.35)
	Wanted.report(global_position, 0.15)
	var tw := _barrel.create_tween()
	tw.tween_property(_barrel, "position:z", 0.45, 0.06)
	tw.tween_property(_barrel, "position:z", 0.0, 0.5)
