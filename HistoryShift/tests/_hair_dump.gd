extends SceneTree
func _init() -> void:
	for f in DirAccess.get_files_at("res://assets/characters/vrm/cc0"):
		if not f.ends_with(".vrm"): continue
		var n: Node3D = (load("res://assets/characters/vrm/cc0/" + f) as PackedScene).instantiate()
		print("=== ", f)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var hb := sk.find_bone("Head")
		print(" head rest global ", sk.get_bone_global_rest(hb))
		print(" skel path ", n.get_path_to(sk), " sk xf ", sk.global_transform if false else sk.transform)
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			print(" MI ", n.get_path_to(mi), " aabb ", mi.get_aabb())
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				var sh := ""
				if m is ShaderMaterial: sh = (m as ShaderMaterial).shader.resource_path
				print("    s", si, " ", m.resource_name if m else "null", " ", sh, " next=", m.next_pass != null if m else false)
		n.free()
	quit()
