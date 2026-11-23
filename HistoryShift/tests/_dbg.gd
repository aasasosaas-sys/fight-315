extends Node3D
func _ready():
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.6,0.7,0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.6,0.6,0.6); env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); add_child(sun)
	Humanoid.force_variant = "m01,f01"
	var outs := [Humanoid.Outfit.SAMURAI, Humanoid.Outfit.KIMONO, Humanoid.Outfit.COMMONER, Humanoid.Outfit.NOBLE]
	for i in 4:
		var h := Humanoid.build(outs[i], 31 + i * 7, false, 1 if i == 1 else 0)
		add_child(h)
		h.position = Vector3(-1.5 + i, 0, 0)
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 1.1, 4.2); cam.look_at(Vector3(0, 0.9, 0)); cam.fov = 45
	for i in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/dbg4.png")
	print("saved"); get_tree().quit()
