class_name ShipLifeboat
extends Node3D
## 総員退船の短艇（乗組員が乗って岸へ漕いでいく。見た目だけ）。

var dir := Vector3.FORWARD
var _t := 0.0
var _life := 70.0


func setup(pos: Vector3, p_dir: Vector3, year: int) -> void:
	global_position = pos
	dir = Vector3(p_dir.x, 0, p_dir.z).normalized() if p_dir.length() > 0.01 else Vector3.FORWARD
	rotation.y = atan2(-dir.x, -dir.z)
	var kit := MeshKit.new()
	var hull := Color(0.92, 0.92, 0.9) if year >= 1880 else Color(0.62, 0.48, 0.34)
	kit.sphere("wood", Transform3D(Basis().scaled(Vector3(1.1, 0.5, 3.6)), Vector3(0, 0.1, 0)), 1.0, 10, 4, hull)
	kit.box("wood", Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(1.8, 0.1, 6.0), Color(0.75, 0.62, 0.45))
	for k in 4:
		var z := -2.0 + k * 1.3
		kit.box("cloth", Transform3D(Basis(), Vector3(0, 0.95, z)), Vector3(0.45, 0.8, 0.35), Color(0.2, 0.25, 0.45) if year >= 1880 else Color(0.55, 0.5, 0.4))
		kit.sphere("plaster", Transform3D(Basis(), Vector3(0, 1.55, z)), 0.18, 8, 5, Color(0.95, 0.8, 0.68))
		for sx: float in [-1.0, 1.0]:
			kit.rod("wood", Vector3(sx * 0.4, 0.9, z), Vector3(sx * 2.2, 0.0, z + 0.4), 0.04, 4, Color(0.6, 0.45, 0.3))
	add_child(kit.commit("Lifeboat"))


func step(dt: float) -> void:
	_t += dt
	global_position += dir * 1.6 * dt
	global_position.y = 0.05 + sin(_t * 1.3) * 0.08
	if _t > _life:
		global_position.y -= (_t - _life) * 0.5
	if _t > _life + 6.0:
		queue_free()
