class_name ShipBody
extends AnimatableBody3D
## 船の可動コリジョン（外装・船内）。弾・砲弾・体当たり・火矢を Ship に渡す。
## Effects.find_target / Player.apply_hit / Shell / 乗り物の ram から呼ばれる。

var ship: Node = null


func take_hit(amount: float, from_team: int, point := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	if ship and is_instance_valid(ship):
		ship.call("on_hit", amount, from_team, point, dir)


## 砲弾の直撃（Shell が爆発の前に呼ぶ）
func blast(dmg: float, origin: Vector3, fire_chance: float, _cause := "") -> void:
	if ship and is_instance_valid(ship):
		ship.call("on_direct_blast", dmg, origin, fire_chance)


## 乗り物の体当たり（車・馬・飛行機・舟）
func ram(speed: float, vel: Vector3, mass_k: float) -> void:
	if ship and is_instance_valid(ship):
		ship.call("on_ram", speed, vel, mass_k, Vector3.INF)


func ignite() -> void:
	if ship and is_instance_valid(ship):
		ship.call("on_ignite", Vector3.INF)
