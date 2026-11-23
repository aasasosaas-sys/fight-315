extends Node
## 全ミッション（全問題×全選択肢）を実際の Session / MissionRunner で自動プレイし、完了できるか検証する。
## godot --headless --path . res://tests/test_missions.tscn [-- real] [-- q=<id>]   （real を付けると EraWorld を使う）

var results := {"ok": 0, "fail": 0}
var failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		print("Game autoload missing"); get_tree().quit(2); return
	var use_real := "real" in OS.get_cmdline_user_args()
	if not use_real:
		game.set_meta("force_fallback_world", true)
	var only: Array = Array(OS.get_cmdline_user_args()).filter(func(a): return a.begins_with("q="))
	var db: HistoryDB = game.db
	var t0 := Time.get_ticks_msec()
	for q in db.questions:
		if only.size() > 0 and ("q=" + q["id"]) not in only:
			continue
		for c in 4:
			var n_methods: int = db.missions_for(q, c).size()
			for mi in n_methods:
				await _play(game, q, c, mi)
	game.state.reset_all()
	HistoryState.delete_save()
	print("missions ok=%d fail=%d  (%.1fs)" % [results["ok"], results["fail"], (Time.get_ticks_msec() - t0) / 1000.0])
	for f in failures:
		print("  FAIL ", f)
	print("RESULT: ", "PASS" if results["fail"] == 0 else "FAIL")
	get_tree().quit(0 if results["fail"] == 0 else 1)


func _play(game, q: Dictionary, c: int, method := 0) -> void:
	var sess := Session.start_mission(q, c, method)
	get_tree().root.add_child(sess)
	await _frames(3)
	var runner: MissionRunner = sess.runner
	var done := [false, ""]
	runner.completed.connect(func(): done[0] = true)
	runner.failed.connect(func(r): done[1] = r)
	var player: Player = sess.player
	player.god_mode = true
	var guard := 0
	var last_idx := -1
	var stuck := 0
	while not done[0] and done[1] == "" and guard < 60:
		guard += 1
		if runner.idx >= runner.steps.size():
			break
		if runner.idx == last_idx:
			stuck += 1
		else:
			stuck = 0
			last_idx = runner.idx
		if stuck > 6:
			break
		var s: Dictionary = runner.steps[runner.idx]
		var lp: Vector3 = game.world.landmark_pos(s.get("at", "village"))
		match s.get("type", ""):
			"goto":
				player.teleport(lp)
			"talk":
				if runner._npc:
					player.teleport(runner._npc.global_position + Vector3(1.5, 0, 0))
					await _frames(2)
					Input.action_press("interact")
					await _frames(1)
					Input.action_release("interact")
					await _frames(1)
					for i in 6:
						sess.hud.advance_dialog()
						await _frames(1)
			"defeat":
				for t in runner._targets.duplicate():
					if is_instance_valid(t) and not t.dead:
						t.take_hit(99999.0, 0)
			"collect":
				for t in runner._targets.duplicate():
					if is_instance_valid(t):
						player.teleport(t.global_position)
						await _frames(2)
			"ride":
				var kind: String = s.get("vehicle", "horse")
				var veh = player.vehicle if player.in_vehicle() and player.vehicle.get("kind") == kind else null
				if veh == null and player.in_vehicle():
					player.exit_vehicle()
					await _frames(2)
				for v in sess.get_tree().get_nodes_in_group("vehicle"):
					if veh == null and v.get("kind") == kind and v.get("driver") == null:
						veh = v
				if veh == null:
					failures.append("%s c%d: no %s spawned" % [q["id"], c, kind])
					break
				if not player.in_vehicle():
					player.enter_vehicle(veh)
				await _frames(2)
				veh.global_position = lp + Vector3.UP * (120.0 if kind == "plane" else 1.0)
				if kind == "plane":
					veh.set("airborne", true)
					veh.set("speed", 60.0)
		await _frames(4)
	var m: Dictionary = sess.mission
	if done[0]:
		results["ok"] += 1
	else:
		results["fail"] += 1
		failures.append("%s c%d m%d「%s」 step %d/%d %s" % [q["id"], c, method, m.get("title", ""), runner.idx + 1, runner.steps.size(), done[1]])
	sess.end()
	await _frames(2)
