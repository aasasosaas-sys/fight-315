extends Node3D
## 単体モデル確認: shot_model.tscn -- <res path> [anim]
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"
func _ready() -> void:
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 40, 0); sun.shadow_enabled = true; add_child(sun)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); fl.mesh = pm; add_child(fl)
	var args := OS.get_cmdline_user_args()
	var inst: Node3D = load(args[0]).instantiate()
	add_child(inst)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		print("anims: ", aps[0].get_animation_list())
		if args.size() > 1: aps[0].play(args[1])
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(3.6, 1.6, 1.2); cam.look_at(Vector3(0, 1.0, 0))
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "model_%s.png" % (args[1] if args.size() > 1 else "rest"))
	print("saved"); get_tree().quit()
