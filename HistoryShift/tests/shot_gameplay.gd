extends Node
## ゲームプレイのスクリーンショット: xvfb-run godot --path . --rendering-driver vulkan res://tests/shot_gameplay.tscn -- <era> [fallback]
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/"

func _ready() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 40:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("saved ", name)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var era_id: String = args[0] if args.size() > 0 else "sengoku"
	if "fallback" in args:
		Game.set_meta("force_fallback_world", true)
	var sess := Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await get_tree().process_frame
	Game.lock_mouse(false)
	var p: Player = sess.player
	p.god_mode = true
	var w = sess.world
	var lp: Vector3 = w.landmark_pos("village")
	var rng := RandomNumberGenerator.new()
	for i in 3:
		var e := Enemy.spawn(sess, p.global_position + Vector3(-4 + i * 4, 0.5, -14), "歴史の修正力" if i == 1 else "敵兵", era_id)
	var cam: CameraRig = sess.cam
	cam.yaw = 0.0
	cam.pitch = -0.12
	await _shot("game_%s_foot" % era_id)
	cam.aiming = true
	Input.action_press("aim")
	await _shot("game_%s_aim" % era_id)
	Input.action_release("aim")
	var v = null
	for n in get_tree().get_nodes_in_group("vehicle"):
		v = n
		break
	if v:
		p.enter_vehicle(v)
		cam.yaw = v.global_rotation.y + 0.6
		await _shot("game_%s_vehicle" % era_id)
	get_tree().quit()
