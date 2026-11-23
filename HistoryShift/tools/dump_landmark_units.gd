extends SceneTree
## 各時代のワールドを組み立て、名所ごとに「歴史に通知される破壊ユニット」（cfg.chaos）の種類と数を tools/landmark_units.json に書き出す。
## godot --headless --path . -s tools/dump_landmark_units.gd   （layouts / architecture を変えたら再実行。validate_chaos.py が読む）

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var G = root.get_node("Game")
	var W = load("res://scripts/world/era_world.gd")
	var out := {}
	for e in G.db.eras:
		var w = W.build(e)
		root.add_child(w)
		for i in 5:
			await process_frame
		var d = w.get("destruction")
		var per := {}
		if d != null:
			for id in d.units:
				var u = d.units[id]
				if not bool(u.cfg["chaos"]):
					continue
				var lm: String = d._lm_id(u)
				if not per.has(lm):
					per[lm] = {"value": 0, "flammable": 0, "kinds": {}}
				per[lm]["kinds"][u.kind] = int(per[lm]["kinds"].get(u.kind, 0)) + 1
				per[lm]["value"] += int(u.cfg["value"])
				if bool(u.cfg["fire"]):
					per[lm]["flammable"] += 1
		out[e["eraId"]] = per
		w.queue_free()
		await process_frame
	var f := FileAccess.open("res://tools/landmark_units.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", true))
	f.close()
	print("wrote tools/landmark_units.json")
	quit()
