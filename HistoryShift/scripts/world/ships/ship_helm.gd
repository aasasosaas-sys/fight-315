class_name ShipHelm
extends Node3D
## 船の舵（乗り物の口）。F で舵を取り、W/S で前進・後進、A/D で面舵・取舵。Ship._pilot が船を動かす。
## Player は group "vehicle" の driver/seat/enter/exit/exit_point を使う（car.gd・horse.gd と同じ）。

var kind := "boat"
var display_name := "船"
var driver = null
var seat: Node3D
var ship: Ship


func _ready() -> void:
	add_to_group("vehicle")
	seat = Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0, 0.05, 0.4)
	add_child(seat)
	if ship:
		display_name = "%s（操船）" % ship.sd.name_ja


func get_speed() -> float:
	return absf(ship.nav_speed) if ship else 0.0


func get_velocity_vec() -> Vector3:
	return -ship.anchor.basis.z * ship.nav_speed if ship else Vector3.ZERO


func enter(_p) -> void:
	driver = _p
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("舵を取った: W/S 前進・後進  A/D 面舵・取舵  Shift 全速  F で離れる", 4.0)


func exit() -> void:
	driver = null


func exit_point() -> Vector3:
	return global_position + global_basis.x * 1.3 + Vector3.UP * 0.4


func take_hit(_amount: float, _team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	pass
