class_name Pickup
extends Node3D
## 回収アイテム。光る箱が浮遊し、触れると回収。

signal collected(p)

var item_name := "アイテム"
var _mesh: MeshInstance3D
var _t := 0.0
var _taken := false


static func spawn(parent: Node, pos: Vector3, p_name: String) -> Pickup:
	var p := Pickup.new()
	p.item_name = p_name
	parent.add_child(p)
	p.global_position = pos
	return p


func _ready() -> void:
	_t = randf() * 10.0
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	_mesh.mesh = bm
	_mesh.material_override = Humanoid.mat(Color(1.0, 0.8, 0.3), 0.3, 0.3, 2.5)
	add_child(_mesh)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.8, 0.4)
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.position = Vector3(0, 1, 0)
	add_child(l)
	var tag := Label3D.new()
	tag.text = item_name
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 10
	tag.position = Vector3(0, 1.8, 0)
	add_child(tag)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.15
	cm.height = 30.0
	beam.mesh = cm
	beam.material_override = Effects.emissive(Color(1, 0.8, 0.35, 0.25), 1.5)
	beam.position = Vector3(0, 15, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _process(dt: float) -> void:
	if _taken:
		return
	_t += dt
	_mesh.position.y = 1.0 + sin(_t * 2.0) * 0.2
	_mesh.rotation.y += dt * 1.5
	var p = Game.player
	if p and is_instance_valid(p):
		var pp: Vector3 = p.vehicle.global_position if p.in_vehicle() else p.global_position
		if pp.distance_to(global_position) < (2.0 if not p.in_vehicle() else 4.0):
			_taken = true
			Sfx.play(get_tree(), Sfx.pickup(), -4.0)
			Effects.burst(get_tree(), global_position + Vector3.UP, Vector3.UP, Color(1, 0.85, 0.4), Color.WHITE, 24, 5.0, 0.15, 0.6, 0.3, true, 180)
			collected.emit(self)
			queue_free()
