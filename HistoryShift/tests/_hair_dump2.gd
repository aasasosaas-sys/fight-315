extends SceneTree
func _init() -> void:
	var n: Node3D = (load("res://assets/characters/vrm/cc0/Sakurada_Fumiriya.vrm") as PackedScene).instantiate()
	var face: MeshInstance3D = n.find_child("Face", true, false)
	var hair: MeshInstance3D = n.find_child("Hair001", true, false)
	var body: MeshInstance3D = n.find_child("Body", true, false)
	for m in [hair.mesh.surface_get_material(0), face.mesh.surface_get_material(5), face.mesh.surface_get_material(5).next_pass, body.mesh.surface_get_material(8)]:
		print("---- ", m.resource_name, " ", m.shader.resource_path, " rp=", m.render_priority)
		for p in m.shader.get_shader_uniform_list():
			print("   ", p.name, " = ", m.get_shader_parameter(p.name))
	print(hair.skin, " skel=", hair.skeleton)
	print(n.get_children())
	for c in n.get_children(): print(c.name, " ", c.get_class(), " ", c.get_script())
	quit()
