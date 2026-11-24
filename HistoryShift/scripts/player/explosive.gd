class_name Explosive
extends RigidBody3D
## 撃つ・爆発に巻き込まれると誘爆する樽など。ワールド生成側が配置する。

@export var radius := 8.0
@export var damage := 140.0
var _done := false


func _ready() -> void:
	add_to_group("explosive")
	add_to_group("physics_prop")
	collision_layer = 32
	collision_mask = 1 | 2 | 4 | 16 | 32


func detonate(delay := 0.0) -> void:
	if _done:
		return
	_done = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	var fx = load("res://scripts/player/effects.gd")
	if fx:
		fx.explosion(get_tree(), global_position + Vector3.UP * 0.5, radius, damage, -1)
	queue_free()


## 弾が当たったとき（gameplay 側から呼ばれる）
func take_hit(_amount: float, _from_team: int, _point: Vector3, _dir: Vector3) -> void:
	detonate()
