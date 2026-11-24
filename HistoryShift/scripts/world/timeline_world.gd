class_name TimelineWorld
extends RefCounted
## 選んだ年に合わせて、組み上がった箱庭の建物を変える（EraWorld._build の最後に 1 行で呼ぶ）。
##  - その年にまだ無い・もう無い建物（EraTimeline.absent_rules：明暦の大火のあとの江戸城天守、銀座煉瓦街より前の煉瓦建築…）は消す
##    （土台＝天守台は残る）。
##  - その年ちょうどの被災（明暦の大火・関東大震災・東京大空襲の直後）は、決まった割合の建物を焼け跡・瓦礫にする。
##  - あなたが同じ時代の前の年（またはこの年）に壊した建物（HistoryState.ruins）は、建て直されるまで壊れたまま。
## いずれも破片・炎・歴史への通知（Game.chaos_event）は出さない。破壊ユニットの ID は年によらず同じ（生成は年で変えない）。


static func apply(w: Node3D) -> Dictionary:
	var stats := {"absent": 0, "ruin": 0, "player": 0}
	var era_id := str(w.get("era_id"))
	var year := int(w.get("year"))
	var d = w.get("destruction")
	if d == null or year == 0:
		return stats
	var units: Dictionary = d.get("units")
	var absent := EraTimeline.absent_rules(era_id, year)
	for r in absent:
		var kinds := EraTimeline._kinds(r)
		var cands: Array = []
		for id in units:
			var u = units[id]
			if str(u.landmark) == str(r.get("landmark", u.landmark)) and str(u.kind) in kinds:
				cands.append(u)
		cands.sort_custom(func(a, b): return a.aabb.get_volume() > b.aabb.get_volume())
		for i in range(int(r.get("keep", 0)), cands.size()):
			vanish(w, cands[i])
			stats["absent"] += 1
	var salt := hash(era_id) + year
	for r in EraTimeline.ruin_rules(era_id, year):
		var kinds := EraTimeline._kinds(r)
		for id in units:
			var u = units[id]
			if u.destroyed or str(u.landmark) != str(r.get("landmark", u.landmark)) or not (str(u.kind) in kinds):
				continue
			if EraTimeline.ruin_pick(int(id), float(r.get("frac", 0.5)), salt):
				preruin(w, u, bool(r.get("burned", false)))
				stats["ruin"] += 1
	var hist: Dictionary = w.get("hist") if w.get("hist") is Dictionary else {}
	for rr in EraTimeline.ruins_at(hist.get("ruins", []), year):
		var u = find_unit(units, rr)
		if u != null and not u.destroyed:
			if str(u.kind) in ["bridge", "boat"] or bool(rr.get("full", false)):
				vanish(w, u)
			else:
				preruin(w, u, bool(rr.get("burned", false)))
			u.set_meta("timeline_ruin", true)
			stats["player"] += 1
	if stats["absent"] + stats["ruin"] + stats["player"] > 0:
		# 状態テクスチャをすぐ作り直して全体に渡す（組み上げ直後＝まだ木に入っていないので Destruction._process を待たない）
		var img: Image = d.get("_img")
		var tex: ImageTexture = d.get("_tex")
		if img != null and tex != null:
			tex.set_image(img)
			RenderingServer.global_shader_parameter_set("destruct_tex", tex)
		print("[Timeline] %s %d: absent %d, ruined %d, your ruins %d" % [era_id, year, stats["absent"], stats["ruin"], stats["player"]])
	return stats


## 記録した建物（種類・名所・中心の位置）に当たるユニット
static func find_unit(units: Dictionary, rr: Dictionary):
	var p := Vector2(float(rr.get("x", 0)), float(rr.get("z", 0)))
	var best = null
	var bd := 2.5
	for id in units:
		var u = units[id]
		if str(u.kind) != str(rr.get("kind", "")) or str(u.landmark) != str(rr.get("landmark", "")):
			continue
		var c: Vector3 = u.center()
		var dd := Vector2(c.x, c.z).distance_to(p)
		if dd < bd:
			bd = dd
			best = u
	return best


## 記録用の形（HistoryState.record_ruins）
static func ruin_record(u, year: int) -> Dictionary:
	var c: Vector3 = u.center()
	return {"kind": str(u.kind), "landmark": str(u.landmark), "x": snappedf(c.x, 0.01), "z": snappedf(c.z, 0.01), "year": year,
		"burned": float(u.char_amt) > 0.5, "full": int(u.hide_bits) == 3}


## まだ建っていない・もう無い：見た目と当たり判定を消す（土台は残る）
static func vanish(w: Node3D, u) -> void:
	_mark(w, u)
	u.hide_bits = 3
	u.cut_y = 1e6
	u.clip_collision(-1e6, true)
	u.mgr.push_state(u)


## 焼け跡・瓦礫（倒壊したのと同じ姿。破片は飛ばさない）
static func preruin(w: Node3D, u, burned: bool) -> void:
	_mark(w, u)
	var small := bool(u.cfg.get("small", false))
	var h := maxf(float(u.top_y) - float(u.base_y), 0.5)
	if str(u.kind) == "bridge" or float(u.cfg["ruin"]) <= 0.0:
		vanish(w, u)
		return
	var cut := float(u.base_y) + h * float(u.cfg["ruin"])
	u.cut_y = cut
	u.char_amt = 0.85 if burned else 0.15
	u.crack = 0.9
	if u.palette.is_empty():
		u.palette = Fracture.material_palette(u.def)
	var ext: Vector3 = u.local_max - u.local_min
	var rh := clampf(h * 0.12, 0.25, 2.4) * (0.5 if small else 1.0)
	var rframe: Transform3D = u.frame * Transform3D(Basis(), Vector3((u.local_min.x + u.local_max.x) * 0.5, float(u.base_y) - u.frame.origin.y, (u.local_min.z + u.local_max.z) * 0.5))
	var rext := Vector2(ext.x * 0.5 + 0.4, ext.z * 0.5 + 0.4) * (0.7 if small else 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Rubble"
	mi.mesh = Fracture.rubble(u.palette, Transform3D.IDENTITY, rext, rh, u.char_amt, int(u.id) * 7919)
	u.add_child(mi)
	mi.transform = u.global_transform.affine_inverse() * rframe if u.is_inside_tree() else rframe
	u.clip_collision(cut, small)
	if not small:
		u.add_rubble_collision(rh)
	u.mgr.push_state(u)


static func _mark(w: Node3D, u) -> void:
	u.destroyed = true
	u.stage = 3
	u.hp = 0.0
	u.roof_gone = true
	for m in u.def.get("models", []):
		if is_instance_valid(m):
			(m as Node3D).visible = false
	var wi = w.get("interiors")
	if wi != null and is_instance_valid(wi):
		wi.on_destroyed(u)
