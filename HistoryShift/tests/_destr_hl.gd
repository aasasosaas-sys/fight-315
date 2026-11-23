extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	await process_frame
	var g = root.get_node("/root/Game")
	var sess := Session.start_free_roam("edo")
	root.add_child(sess)
	await process_frame
	await process_frame
	var d := Destruction.current
	var kinds := {}
	for u in d.units.values():
		kinds[u.kind] = kinds.get(u.kind, 0) + 1
	print(kinds)
	var cap: Vector3 = sess.world.landmark_pos("capital")
	var t0 := Time.get_ticks_usec()
	for i in 6:
		Effects.explosion(self, cap + Vector3(i * 8 - 20, 1, 15), 11.0, 900.0, 0, 0.5)
	print("blasts ms ", (Time.get_ticks_usec() - t0) / 1000.0, " debris ", d.live_debris(), " ", d.summary_text())
	for i in 120:
		await physics_frame
	print("after ", d.live_debris(), " fires ", d.burning_count(), " ", d.summary_text())
	quit()
