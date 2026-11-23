class_name WorldLayouts
extends RefCounted
var w: EraWorld
var extra_car_spawns: Array = []
var plane_spawns: Array = []
func _init(world: EraWorld) -> void:
	w = world
func plan_terrain() -> void:
	pass
func terrain_features() -> void:
	pass
func build_all() -> void:
	var c: Dictionary = w.landmarks["capital"]
	w.player_spawn = c["pos"]
