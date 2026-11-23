extends Node3D
## アニメーション確認: 歩き・エイム・騎乗を並べて撮影
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var tag := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "x"
	var configs := [[0.0, false, false], [1.5, false, false], [3.6, false, false], [6.0, false, false], [0.0, true, false]]
	var x := -2.4
	for c in configs:
		var h := Humanoid.build(Humanoid.Outfit.WESTERN, 11, true, 0)
		add_child(h)
		h.position = Vector3(x, 0, 0)
		h.rotation.y = deg_to_rad(-90)
		h.speed = c[0]; h.aiming = c[1]; h.riding = c[2]
		x += 1.2
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.0, 4.6)
	cam.look_at(Vector3(0, 0.9, 0))
	for i in 45: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "anim_" + tag + ".png")
	print("saved")
	get_tree().quit()
