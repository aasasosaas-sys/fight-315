extends Node
func _ready() -> void:
	for era in ["edo", "sengoku", "meiji_taisho", "showa", "heian", "kamakura_muromachi", "asuka_nara", "jomon_kofun"]:
		var w := EraWorld.build(Game.db.get_era(era))
		add_child(w)
		var wi: WorldInteriors = w.interiors
		var bad := 0
		var lines: Array = []
		for id in wi.ids:
			var d: Dictionary = wi.defs[id]
			var inv: Transform3D = d["_inv"]
			var f: Dictionary = d["floors"][0]
			var r: Rect2 = (f["rect"] as Rect2).grow(-0.3)
			for u in Destruction.current.units_near(d["_c"], float(d["_r"]) + 15.0):
				var du := u as Destructible
				if du.id == id or du.kind in ["lamp", "lantern", "prop", "fence", "wall", "stonewall", "brickwall", "stall"]:
					continue
				# 相手の形状の中心が部屋の中にあるか（粗い判定）
				var hit := false
				for sh in du.def["shapes"]:
					var c: Vector3 = inv * (sh[0] as Transform3D).origin
					if r.has_point(Vector2(c.x, c.z)) and c.y > float(f["y"]) - 0.5 and c.y < float(f["y"]) + 8.0:
						hit = true
				if hit:
					bad += 1
					lines.append("  %d %s(%s) %s r=%s overlaps %d %s %s at %s" % [id, d["type"], d.get("landmark",""), (d["xf"] as Transform3D).origin, d["floors"][0]["rect"], du.id, du.kind, du.def.get("opts", {}).get("kind_detail", ""), (du.def["xf"] as Transform3D).origin])
					break
		print("[%s] defs=%d overlapped=%d" % [era, wi.ids.size(), bad])
		for l in lines.slice(0, 12):
			print(l)
		w.free()
	get_tree().quit()
