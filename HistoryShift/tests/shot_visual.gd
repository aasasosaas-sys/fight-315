extends Node
## 見た目（ルック）検証用のスクリーンショット: 町（HUD あり）・人物の寄り・俯瞰・寺社・夜・歴史改変の通知。
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1280x720 res://tests/shot_visual.tscn -- <era> <tag> [shots]
## 出力: <scratch>/shots/vis/<tag>_<era>_<name>.png
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/vis/"

var sess
var only: Array = []


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(tag: String, era_id: String, name: String, frames := 30) -> void:
	await _frames(frames)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "%s_%s_%s.png" % [tag, era_id, name])
	print("saved ", name)


func _want(name: String) -> bool:
	return only.is_empty() or name in only


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var args := OS.get_cmdline_user_args()
	var era_id: String = args[0] if args.size() > 0 else "edo"
	var tag: String = args[1] if args.size() > 1 else "test"
	if args.size() > 2 and args[2] != "all":
		only = Array(args[2].split(","))
	sess = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await get_tree().process_frame
	Game.lock_mouse(false)
	var p: Player = sess.player
	p.god_mode = true
	var w: EraWorld = sess.world
	var cam: CameraRig = sess.cam
	var hud: Hud = sess.hud
	var cap: Vector3 = w.landmark_pos("capital")
	var to_cap := cap - p.global_position
	cam.yaw = atan2(-to_cap.x, -to_cap.z) + 0.35
	cam.pitch = -0.1
	await _frames(20)
	if _want("street"):
		await _shot(tag, era_id, "street", 40)
	# 人物の寄り（HUD なし）
	var c2 := Camera3D.new()
	c2.fov = 40.0
	c2.near = 0.05
	c2.far = 4000.0
	w.add_child(c2)
	if _want("close"):
		hud.visible = false
		var fwd := -p.global_basis.z
		var head := p.global_position + Vector3(0, 1.5, 0)
		# 顔の向きは骨格の頭（VRM は骨格空間で +Z が正面）
		var sks := p.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			var sk: Skeleton3D = sks[0]
			var hb := sk.find_bone("Head")
			if hb >= 0:
				var hx := sk.global_transform * sk.get_bone_global_pose(hb)
				head = hx.origin + Vector3(0, 0.06, 0)
				var f := sk.global_basis * Vector3(0, 0, 1)
				f.y = 0.0
				if f.length() > 0.1:
					fwd = f.normalized()
		print("face fwd ", fwd)
		var dir := fwd.rotated(Vector3.UP, 0.55)
		c2.global_position = head + dir * 1.25 + Vector3(0, 0.08, 0)
		c2.look_at(head + Vector3(0, -0.06, 0), Vector3.UP)
		c2.current = true
		WorldAtmosphere.set_dof(w.env_nodes, 1.25)
		await _shot(tag, era_id, "close", 30)
		# 全身（少し引き）
		c2.global_position = head + fwd.rotated(Vector3.UP, -0.7) * 3.4 + Vector3(0, -0.2, 0)
		c2.look_at(head + Vector3(0, -0.55, 0), Vector3.UP)
		WorldAtmosphere.set_dof(w.env_nodes, 3.4)
		await _shot(tag, era_id, "body", 20)
		WorldAtmosphere.set_dof(w.env_nodes, 0.0)
	var ang: float = w.landmarks["capital"]["angle"]
	var b := Basis(Vector3.UP, ang)
	if _want("aerial"):
		hud.visible = false
		c2.fov = 62.0
		c2.global_position = cap + b * Vector3(75, 48, 115)
		c2.look_at(cap + b * Vector3(0, 0, -18), Vector3.UP)
		c2.current = true
		await _shot(tag, era_id, "aerial", 30)
	if _want("temple"):
		hud.visible = false
		c2.fov = 62.0
		var tem: Vector3 = w.landmark_pos("temple")
		var fp := tem + b * Vector3(-30, 12, 50)
		fp.y = maxf(fp.y, w.height_at(fp.x, fp.z) + 1.5)
		c2.global_position = fp
		c2.look_at(tem + Vector3(0, 8, 0), Vector3.UP)
		c2.current = true
		await _shot(tag, era_id, "temple", 30)
	if _want("village"):
		hud.visible = false
		c2.fov = 62.0
		var vil: Vector3 = w.landmark_pos("village")
		var vp := vil + b * Vector3(10, 0, 30)
		vp.y = w.height_at(vp.x, vp.z) + 1.7
		c2.global_position = vp
		c2.look_at(vil + Vector3(0, 3, 0), Vector3.UP)
		c2.current = true
		await _shot(tag, era_id, "village", 30)
	if _want("shift"):
		cam.make_current()
		hud.visible = true
		hud.set_objective("自由探索", "好きに暴れろ。乗り物は F で奪える。人物に近づいて E で話せる（T でヒント切替）。", "破壊 3 / 10")
		hud.history_shift("本能寺の変が起きなかった\n織田信長が天下を統一し、江戸幕府は開かれない。", false, "問12 ○ → ×　問14 × → ○")
		hud.toast("火縄銃を拾った")
		await _shot(tag, era_id, "shift", 22)
	if _want("night"):
		hud.visible = false
		w.set_time_of_day(20.5)
		c2.fov = 62.0
		var sp := p.global_position
		c2.global_position = sp + Vector3(0, 1.7, 0)
		c2.look_at(cap + Vector3(0, 5, 0), Vector3.UP)
		c2.current = true
		await _shot(tag, era_id, "night", 40)
	get_tree().quit()
