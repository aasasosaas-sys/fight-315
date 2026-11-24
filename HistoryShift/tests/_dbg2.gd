extends Node3D
func _ready():
	var cases := [[Humanoid.Outfit.WESTERN, true], [Humanoid.Outfit.WESTERN, false], [Humanoid.Outfit.SAMURAI, false], [Humanoid.Outfit.SAMURAI, true]]
	var hs := []
	for c in cases:
		var h := Humanoid.build(c[0], 31, c[1], 0)
		add_child(h)
		hs.append(h)
	for i in 30: await get_tree().process_frame
	for h in hs:
		var sk: Skeleton3D = h._skel
		var bi := sk.find_bone("LeftUpperArm")
		print("pose ", sk.get_bone_pose_rotation(bi), " rest ", sk.get_bone_rest(bi).basis.get_rotation_quaternion(), " anim_err=", h._tree.get("parameters/loco/blend_position"))
	get_tree().quit()
