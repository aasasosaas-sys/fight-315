class_name Npc
extends Node3D
## 会話相手の歴史上の人物など。近づいて E で話す。

var npc_name := "人物"
var lines: Array = []
var era_id := ""
var talked := false
var _rig: Humanoid
var _tag: Label3D
var _ring: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, p_name: String, p_lines: Array, p_era: String) -> Npc:
	var n := Npc.new()
	n.npc_name = p_name
	n.lines = p_lines
	n.era_id = p_era
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	var outfit := Humanoid.outfit_for(era_id, "npc")
	if npc_name.contains("記録者"):
		outfit = Humanoid.Outfit.MONK
	_rig = Humanoid.build(outfit, hash(npc_name), false)
	_rig.rotation.y = PI
	add_child(_rig)
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_CIVILIAN
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	body.add_child(cs)
	add_child(body)
	_tag = Label3D.new()
	_tag.text = npc_name
	_tag.font = load("res://assets/fonts/NotoSerifJP-Bold.ttf")
	_tag.font_size = 56
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.outline_size = 12
	_tag.modulate = Color(1, 0.9, 0.55)
	_tag.position = Vector3(0, 2.4, 0)
	add_child(_tag)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	_ring.mesh = tm
	_ring.material_override = Effects.emissive(Color(1, 0.85, 0.4), 2.0)
	_ring.position = Vector3(0, 0.05, 0)
	add_child(_ring)


func _process(dt: float) -> void:
	var p = Game.player
	if p and is_instance_valid(p):
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		if to.length() < 12.0 and to.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + PI, dt * 3.0)
	_ring.rotation.y += dt
	_ring.visible = not talked
	_tag.modulate.a = 0.6 if talked else 1.0
