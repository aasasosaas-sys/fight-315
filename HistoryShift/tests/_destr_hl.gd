extends Node
## 破壊システムのヘッドレス簡易テスト: godot --headless --path . res://tests/_destr_hl.tscn
func _ready() -> void:
	_go.call_deferred()
func _go() -> void:
	Game.chaos_event.connect(func(k, id, info): print("chaos ", k, " ", id, " ", info.get("type", ""), " cause=", info.get("cause", "")))
	var sess := Session.start_free_roam("edo")
	get_tree().root.add_child(sess)
	await get_tree().process_frame
	await get_tree().process_frame
	var d := Destruction.current
	var kinds := {}
	for u in d.units.values():
		kinds[u.kind] = kinds.get(u.kind, 0) + 1
	print(kinds)
	var cap: Vector3 = sess.world.landmark_pos("capital")
	var t0 := Time.get_ticks_usec()
	for i in 6:
		Effects.explosion(get_tree(), cap + Vector3(i * 8 - 20, 1, 15), 11.0, 900.0, 0, 0.5)
	print("blasts ms ", (Time.get_ticks_usec() - t0) / 1000.0, " debris ", d.live_debris(), " ", d.summary_text())
	for i in 240:
		await get_tree().physics_frame
	print("after ", d.live_debris(), " fires ", d.burning_count(), " ", d.summary_text())
	get_tree().quit()
